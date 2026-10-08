import { z } from "zod";

export const REPOSITORY = "kmshdev/foundation-models-utilities";
export const roster = [
  ["architecture", "Architecture and Swift concurrency"],
  ["models", "Foundation Models"],
  ["identity", "Authentication and session security"],
  ["swiftui", "SwiftUI and accessibility"],
  ["platforms", "iOS/macOS integration"],
  ["cloudflare", "Cloudflare infrastructure"],
  ["quality", "Testing and evaluation"],
  ["integration", "CI and integration"],
] as const;
export const botIds = roster.map(([id]) => id);
const text = z.string().trim().min(1).max(6000);
const id = z.string().regex(/^[a-zA-Z0-9_-]{1,100}$/);
const botId = z.enum([
  "architecture",
  "models",
  "identity",
  "swiftui",
  "platforms",
  "cloudflare",
  "quality",
  "integration",
]);
const filePath = z
  .string()
  .min(1)
  .max(250)
  .refine(
    (p) =>
      !p.startsWith("/") &&
      !p.includes("\\") &&
      !p.split("/").some((s) => !s || s === "." || s === "..") &&
      !/[\x00-\x1f*?\[\]]/.test(p),
    "Use a repository-relative file or directory, without globs or traversal",
  );
export const taskSpec = z
  .object({
    id,
    owner: botId,
    requirement: text,
    paths: z.array(filePath).min(1).max(30),
    acceptance: z.array(text).min(1).max(20),
    dependsOn: z.array(id).max(20),
    priority: z.number().int().min(0).max(4).default(0),
    userOrder: z.number().int().min(0).default(999),
    urgent: z.boolean().default(false),
  })
  .strict();
export const planSchema = z
  .object({ id, outcomeId: id, tasks: z.array(taskSpec).min(1).max(50) })
  .strict();
export type PlanInput = z.infer<typeof planSchema>;
export const evidenceSchema = z
  .object({
    commit: z.string().regex(/^[a-f0-9]{40}$/),
    summary: text,
    tests: z
      .array(
        z.object({
          command: text,
          status: z.enum(["passed", "failed", "not_run"]),
          detail: text,
        }),
      )
      .min(1)
      .max(30),
    changedFiles: z.array(filePath).max(100),
    pr: z.string().url().optional(),
  })
  .strict();
export type Evidence = z.infer<typeof evidenceSchema>;
export type Task = z.infer<typeof taskSpec> & {
  planId: string;
  outcomeId: string;
  status: "queued" | "running" | "blocked" | "done";
  fence: number;
  leaseUntil?: number;
  executor?: string;
  evidence?: Evidence;
  blocker?: string;
};
export type Bot = {
  id: string;
  specialty: string;
  lastSeen: number;
  executor?: string;
  ready: boolean;
};
export type Handoff = {
  id: string;
  from: string;
  to: string;
  taskId: string;
  commit: string;
  summary: string;
  acknowledgedAt?: number;
};
export type Question = {
  id: string;
  prompt: string;
  options: string[];
  answer?: string;
};
export type State = {
  version: 1;
  revision: number;
  paused: boolean;
  bots: Bot[];
  outcomes: { id: string; text: string; createdAt: number }[];
  plans: string[];
  tasks: Task[];
  handoffs: Handoff[];
  questions: Question[];
  events: { at: number; type: string; detail: string }[];
};
export class DomainError extends Error {
  constructor(
    message: string,
    public status = 409,
  ) {
    super(message);
  }
}
export function initialState(): State {
  return {
    version: 1,
    revision: 0,
    paused: false,
    bots: roster.map(([id, specialty]) => ({
      id,
      specialty,
      lastSeen: 0,
      ready: false,
    })),
    outcomes: [],
    plans: [],
    tasks: [],
    handoffs: [],
    questions: [],
    events: [],
  };
}
export function event(s: State, type: string, detail: string, now: number) {
  s.revision++;
  s.events.push({ at: now, type, detail });
  s.events = s.events.slice(-250);
}
export function bot(s: State, id: string) {
  const b = s.bots.find((b) => b.id === id);
  if (!b) throw new DomainError("Unknown bot", 404);
  return b;
}
export function availability(s: State, b: Bot, now: number) {
  if (!b.ready || now - b.lastSeen > 90000) return "offline";
  const t = s.tasks.find(
    (t) => t.owner === b.id && ["running", "blocked"].includes(t.status),
  );
  return t
    ? t.status === "blocked" || (t.leaseUntil ?? 0) < now
      ? "blocked"
      : "busy"
    : "available";
}
function overlap(a: string, b: string) {
  return a === b || a.startsWith(b + "/") || b.startsWith(a + "/");
}
function ancestor(
  tasks: PlanInput["tasks"],
  a: string,
  b: string,
  visited = new Set<string>(),
): boolean {
  if (visited.has(b)) return false;
  visited.add(b);
  const task = tasks.find((t) => t.id === b);
  return (
    !!task &&
    task.dependsOn.some((d) => d === a || ancestor(tasks, a, d, visited))
  );
}
export function addPlan(s: State, raw: unknown, now: number) {
  const p = planSchema.parse(raw);
  if (s.plans.includes(p.id)) throw new DomainError("Plan already exists");
  if (!s.outcomes.some((o) => o.id === p.outcomeId))
    throw new DomainError("Unknown outcome", 404);
  const ids = new Set(p.tasks.map((t) => t.id));
  if (
    ids.size !== p.tasks.length ||
    p.tasks.some((t) => s.tasks.some((old) => old.id === t.id))
  )
    throw new DomainError("Task IDs must be unique");
  for (const t of p.tasks) {
    if (t.dependsOn.some((d) => !ids.has(d)))
      throw new DomainError("Dependency must exist in this plan");
    if (ancestor(p.tasks, t.id, t.id))
      throw new DomainError("Dependency cycle");
  }
  for (let i = 0; i < p.tasks.length; i++)
    for (let j = i + 1; j < p.tasks.length; j++) {
      const a = p.tasks[i],
        b = p.tasks[j];
      if (
        a.paths.some((x) => b.paths.some((y) => overlap(x, y))) &&
        !ancestor(p.tasks, a.id, b.id) &&
        !ancestor(p.tasks, b.id, a.id)
      )
        throw new DomainError(
          "Overlapping ownership requires an explicit dependency: " +
            a.id +
            " / " +
            b.id,
        );
    }
  for (const t of p.tasks)
    for (const old of s.tasks.filter((t) => t.status !== "done"))
      if (t.paths.some((x) => old.paths.some((y) => overlap(x, y))))
        throw new DomainError(
          "Ownership conflicts with active plan: " + old.id,
        );
  if (s.tasks.length + p.tasks.length > 200)
    throw new DomainError(
      "Active room task capacity reached; archive completed history before adding more",
    );
  s.plans.push(p.id);
  s.tasks.push(
    ...p.tasks.map((t) => ({
      ...t,
      planId: p.id,
      outcomeId: p.outcomeId,
      status: "queued" as const,
      fence: 0,
    })),
  );
  event(
    s,
    "plan",
    `Plan ${p.id}: ${p.tasks.length} requirements assigned`,
    now,
  );
  return p;
}
export function heartbeat(
  s: State,
  botId: string,
  executor: string,
  ready: boolean,
  now: number,
) {
  const b = bot(s, botId);
  const held = s.tasks.find(
    (t) => t.owner === botId && ["running", "blocked"].includes(t.status),
  );
  if (held && held.executor !== executor)
    throw new DomainError(
      "Previous executor still owns work; reconcile it before replacing",
    );
  if (b.executor && b.executor !== executor && now - b.lastSeen < 90000)
    throw new DomainError("Bot already has a live executor");
  b.executor = executor;
  b.ready = ready;
  b.lastSeen = now;
  if (held && held.status === "running") held.leaseUntil = now + 90000;
}
export function claim(
  s: State,
  botId: string,
  executor: string,
  now: number,
): Task | null {
  const b = bot(s, botId);
  if (s.paused || s.questions.some((q) => !q.answer)) return null;
  if (b.executor !== executor || availability(s, b, now) !== "available")
    return null;
  if (s.tasks.filter((t) => t.status === "running").length >= 3) return null;
  const eligible = s.tasks.filter(
    (t) =>
      t.owner === botId &&
      t.status === "queued" &&
      t.dependsOn.every(
        (dep) =>
          s.tasks.find((t) => t.id === dep)?.status === "done" &&
          s.handoffs.some(
            (h) =>
              h.taskId === dep &&
              h.to === botId &&
              h.acknowledgedAt !== undefined,
          ),
      ),
  );
  const blockerCount = (t: Task) =>
    s.tasks.filter((x) => x.dependsOn.includes(t.id)).length;
  eligible.sort(
    (a, b) =>
      a.userOrder - b.userOrder ||
      Number(b.urgent) - Number(a.urgent) ||
      blockerCount(b) - blockerCount(a) ||
      (a.priority || 5) - (b.priority || 5),
  );
  const t = eligible[0];
  if (!t) return null;
  t.status = "running";
  t.fence++;
  t.executor = executor;
  t.leaseUntil = now + 90000;
  event(s, "assigned", `${t.id} → ${botId}`, now);
  return t;
}
export function ownedTask(
  s: State,
  botId: string,
  taskId: string,
  executor: string,
  fence: number,
  now: number,
) {
  const t = s.tasks.find((t) => t.id === taskId);
  if (
    !t ||
    t.owner !== botId ||
    t.executor !== executor ||
    t.fence !== fence ||
    !["running", "blocked"].includes(t.status)
  )
    throw new DomainError("Stale or invalid ownership");
  if ((t.leaseUntil ?? 0) < now)
    throw new DomainError(
      "Lease expired; heartbeat and reconcile before reporting",
    );
  return t;
}
export function complete(
  s: State,
  botId: string,
  taskId: string,
  executor: string,
  fence: number,
  raw: unknown,
  now: number,
) {
  const t = ownedTask(s, botId, taskId, executor, fence, now);
  const e = evidenceSchema.parse(raw);
  if (e.tests.some((t) => t.status !== "passed"))
    throw new DomainError(
      "Task cannot complete with failed or unrun acceptance checks",
    );
  if (
    e.changedFiles.some(
      (f) => !t.paths.some((p) => f === p || f.startsWith(p + "/")),
    )
  )
    throw new DomainError("Changed files exceed ownership");
  if (
    e.pr &&
    !new RegExp(
      "^https://github\\.com/" + REPOSITORY + "/pull/[1-9][0-9]*$",
    ).test(e.pr)
  )
    throw new DomainError("PR outside repository scope");
  t.status = "done";
  t.evidence = e;
  delete t.blocker;
  event(s, "complete", `${t.id} at ${e.commit}`, now);
  const recipients = new Set(
    s.tasks.filter((n) => n.dependsOn.includes(t.id)).map((n) => n.owner),
  );
  for (const to of recipients)
    s.handoffs.push({
      id: `${t.id}-${to}-${t.fence}`,
      from: botId,
      to,
      taskId: t.id,
      commit: e.commit,
      summary: e.summary,
    });
  return t;
}
export function acknowledge(
  s: State,
  botId: string,
  id: string,
  commit: string,
  now: number,
) {
  const h = s.handoffs.find((h) => h.id === id && h.to === botId);
  if (!h || h.commit !== commit)
    throw new DomainError("Handoff or artifact version mismatch");
  if (!h.acknowledgedAt) {
    h.acknowledgedAt = now;
    event(s, "handoff", `${h.id} acknowledged`, now);
  }
}
export function recover(
  s: State,
  taskId: string,
  executorStopped: boolean,
  now: number,
) {
  const t = s.tasks.find((t) => t.id === taskId);
  if (!t || !["running", "blocked"].includes(t.status) || !executorStopped)
    throw new DomainError(
      "Recovery requires confirmation that the previous executor stopped",
    );
  t.fence++;
  t.status = "queued";
  delete t.executor;
  delete t.leaseUntil;
  delete t.blocker;
  const b = bot(s, t.owner);
  b.ready = false;
  b.lastSeen = 0;
  delete b.executor;
  event(s, "recovered", `${taskId}: old executor fenced out`, now);
}
export function report(s: State, now: number) {
  return {
    ...s,
    bots: s.bots.map((b) => ({ ...b, status: availability(s, b, now) })),
    tasks: s.tasks.map((t) => ({
      ...t,
      leaseExpired: t.status === "running" && (t.leaseUntil ?? 0) < now,
    })),
    runtime:
      "Coordinator active; developer execution depends on authenticated runner heartbeats",
  };
}

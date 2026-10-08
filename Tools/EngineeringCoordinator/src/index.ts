import { Agent, getAgentByName } from "agents";
import { z } from "zod";
import { authenticate, mintRunner } from "./auth";
import {
  initialState,
  addPlan,
  heartbeat,
  claim,
  ownedTask,
  complete,
  acknowledge,
  recover,
  report,
  event,
  DomainError,
  type State,
} from "./domain";
import { readJSON, json } from "./http";
import { integrationStatus } from "./integrations";

const short = z.string().trim().min(1).max(100);
const progress = z
  .object({
    taskId: short,
    executor: short,
    fence: z.number().int().positive(),
    message: z.string().trim().min(1).max(6000),
    blocked: z.boolean().default(false),
  })
  .strict();
export class EngineeringCoordinator extends Agent<Env, State> {
  initialState = initialState();
  // No browser/runner can replace room state through the SDK's state-sync channel.
  validateStateChange(_state: State, source: unknown) {
    if (source !== "server")
      throw new DomainError("Direct client state replacement is disabled", 403);
  }
  async onRequest(request: Request): Promise<Response> {
    try {
      const principal = await authenticate(
        request,
        this.env.OWNER_TOKEN,
        this.env.RUNNER_SIGNING_KEY,
      );
      const url = new URL(request.url),
        path = url.pathname,
        now = Date.now();
      if (request.method === "GET" && path === "/v1/status") {
        if (principal.role === "owner") return json(report(this.state, now));
        return json({
          bot: this.state.bots.find((b) => b.id === principal.botId),
          tasks: this.state.tasks.filter((t) => t.owner === principal.botId),
          handoffs: this.state.handoffs
            .filter((h) => h.to === principal.botId)
            .map((h) => ({
              ...h,
              evidence: this.state.tasks.find((t) => t.id === h.taskId)
                ?.evidence,
            })),
          paused: this.state.paused,
          pendingQuestions: this.state.questions.filter((q) => !q.answer)
            .length,
        });
      }
      if (
        request.method === "GET" &&
        path === "/v1/integrations" &&
        principal.role === "owner"
      )
        return json(await integrationStatus(this.env));
      if (request.method !== "POST")
        return json({ error: "Route not found" }, 404);
      const raw = await readJSON(request);
      // Read current state AFTER awaited body/auth I/O. The synchronous transition and
      // setState below contain no await, so competing claims cannot lose updates.
      const next = structuredClone(this.state);
      let result: unknown = { ok: true };
      if (principal.role === "owner") {
        if (path === "/v1/outcomes") {
          const x = z
            .object({ id: short, text: z.string().trim().min(1).max(12000) })
            .strict()
            .parse(raw);
          if (next.outcomes.some((o) => o.id === x.id))
            throw new DomainError("Outcome already exists");
          if (next.outcomes.length >= 50)
            throw new DomainError("Outcome capacity reached");
          next.outcomes.push({ ...x, createdAt: now });
          event(next, "outcome", x.id, now);
        } else if (path === "/v1/plans") {
          result = addPlan(next, raw, now);
        } else if (path === "/v1/pause") {
          const x = z.object({ paused: z.boolean() }).strict().parse(raw);
          next.paused = x.paused;
          event(next, "pause", String(x.paused), now);
        } else if (path === "/v1/recover") {
          const x = z
            .object({ taskId: short, executorStopped: z.literal(true) })
            .strict()
            .parse(raw);
          recover(next, x.taskId, x.executorStopped, now);
        } else if (path === "/v1/questions") {
          const x = z
            .object({
              questions: z
                .array(
                  z
                    .object({
                      id: short,
                      prompt: z.string().trim().min(1).max(1000),
                      options: z.array(z.string().min(1).max(250)).max(5),
                    })
                    .strict(),
                )
                .min(1)
                .max(10),
            })
            .strict()
            .parse(raw);
          if (next.questions.some((q) => !q.answer))
            throw new DomainError(
              "An existing question batch is awaiting answers",
            );
          if (
            new Set(x.questions.map((q) => q.id)).size !== x.questions.length ||
            x.questions.some((q) =>
              next.questions.some((old) => old.id === q.id),
            )
          )
            throw new DomainError("Question IDs must be new and unique");
          next.questions.push(...x.questions);
          event(
            next,
            "questions",
            `${x.questions.length} questions awaiting answers`,
            now,
          );
        } else if (path === "/v1/answers") {
          const x = z
            .object({
              answers: z
                .array(
                  z
                    .object({
                      id: short,
                      answer: z.string().trim().min(1).max(6000),
                    })
                    .strict(),
                )
                .min(1)
                .max(10),
            })
            .strict()
            .parse(raw);
          if (new Set(x.answers.map((a) => a.id)).size !== x.answers.length)
            throw new DomainError("Duplicate answer IDs");
          for (const a of x.answers) {
            const q = next.questions.find((q) => q.id === a.id);
            if (!q) throw new DomainError("Unknown question");
            if (q.answer && q.answer !== a.answer)
              throw new DomainError("Answer already recorded");
            q.answer = a.answer;
          }
          event(next, "answers", `${x.answers.length} answers recorded`, now);
        } else if (path === "/v1/runner-token") {
          const x = z.object({ botId: short }).strict().parse(raw);
          return json({
            token: await mintRunner(x.botId, this.env.RUNNER_SIGNING_KEY),
            expiresIn: 86400,
          });
        } else return json({ error: "Route not found" }, 404);
      } else {
        const botId = principal.botId;
        if (path === "/v1/heartbeat") {
          const x = z
            .object({ executor: short, ready: z.boolean() })
            .strict()
            .parse(raw);
          heartbeat(next, botId, x.executor, x.ready, now);
        } else if (path === "/v1/claim") {
          const x = z.object({ executor: short }).strict().parse(raw);
          const task = claim(next, botId, x.executor, now);
          result = {
            task,
            context: task
              ? next.handoffs
                  .filter(
                    (h) => task.dependsOn.includes(h.taskId) && h.to === botId,
                  )
                  .map((h) => ({
                    ...h,
                    evidence: next.tasks.find((t) => t.id === h.taskId)
                      ?.evidence,
                  }))
              : [],
          };
        } else if (path === "/v1/progress") {
          const x = progress.parse(raw);
          const t = ownedTask(next, botId, x.taskId, x.executor, x.fence, now);
          if (x.blocked) {
            t.status = "blocked";
            t.blocker = x.message;
          }
          event(
            next,
            x.blocked ? "blocked" : "progress",
            `${x.taskId}: ${x.message}`,
            now,
          );
        } else if (path === "/v1/complete") {
          const x = z
            .object({
              taskId: short,
              executor: short,
              fence: z.number().int().positive(),
              evidence: z.unknown(),
            })
            .strict()
            .parse(raw);
          result = complete(
            next,
            botId,
            x.taskId,
            x.executor,
            x.fence,
            x.evidence,
            now,
          );
        } else if (path === "/v1/handoffs/ack") {
          const x = z
            .object({ id: short, commit: z.string().regex(/^[a-f0-9]{40}$/) })
            .strict()
            .parse(raw);
          acknowledge(next, botId, x.id, x.commit, now);
        } else return json({ error: "Route not found" }, 404);
      }
      this.setState(next);
      return json(result);
    } catch (error) {
      return failure(error);
    }
  }
}
function failure(error: unknown) {
  if (error instanceof DomainError)
    return json({ error: error.message }, error.status);
  if (error instanceof z.ZodError)
    return json(
      {
        error: "Invalid request",
        issues: error.issues.map((i) => ({ path: i.path, message: i.message })),
      },
      400,
    );
  console.error(
    JSON.stringify({
      event: "coordinator_request_failed",
      type: error instanceof Error ? error.name : "unknown",
    }),
  );
  return json({ error: "Internal coordinator error" }, 500);
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      // Exact routes only: no public Agent WebSocket/RPC path can bypass authorization.
      if (
        !new URL(request.url).pathname.startsWith("/v1/") ||
        request.headers.get("Upgrade")
      )
        return json({ error: "Route not found" }, 404);
      await authenticate(request, env.OWNER_TOKEN, env.RUNNER_SIGNING_KEY);
      const room = await getAgentByName(env.COORDINATOR, "engineering");
      return await room.fetch(request);
    } catch (error) {
      return failure(error);
    }
  },
} satisfies ExportedHandler<Env>;

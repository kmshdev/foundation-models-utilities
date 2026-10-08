import { test } from "node:test";
import assert from "node:assert/strict";
import {
  initialState,
  addPlan,
  heartbeat,
  claim,
  complete,
  acknowledge,
  recover,
  report,
} from "../src/domain";
const now = 1000000;
const spec = (
  id: string,
  owner = "architecture",
  paths = [id],
  dependsOn: string[] = [],
) => ({
  id,
  owner,
  paths,
  dependsOn,
  requirement: `Implement ${id}`,
  acceptance: ["Required checks pass"],
});
const setup = () => {
  const s = initialState();
  s.outcomes.push({ id: "first", text: "Build coordinator", createdAt: now });
  return s;
};
const plan = (tasks: unknown[], id = "plan1") => ({
  id,
  outcomeId: "first",
  tasks,
});
const evidence = {
  commit: "a".repeat(40),
  summary: "Implemented contract",
  changedFiles: ["shared/schema.ts"],
  tests: [
    { command: "npm test", status: "passed", detail: "Contract checks passed" },
  ],
};
test("eight identities start offline until a real executor heartbeat", () => {
  const s = initialState();
  assert.equal(s.bots.length, 8);
  assert.ok(report(s, now).bots.every((b) => b.status === "offline"));
  heartbeat(s, "models", "m1", true, now);
  assert.equal(
    report(s, now).bots.find((b) => b.id === "models")?.status,
    "available",
  );
  assert.equal(
    report(s, now + 90001).bots.find((b) => b.id === "models")?.status,
    "offline",
  );
});
test("rejects cycles, unknown dependencies and overlapping unsequenced file ownership", () => {
  for (const tasks of [
    [
      spec("a", "architecture", ["shared"]),
      spec("b", "models", ["shared/schema.ts"]),
    ],
    [
      spec("a", "architecture", ["a"], ["b"]),
      spec("b", "models", ["b"], ["a"]),
    ],
    [spec("a", "architecture", ["a"], ["missing"])],
  ])
    assert.throws(() => addPlan(setup(), plan(tasks), now));
});
test("task claims are exclusive and enforce the three-task capacity", () => {
  const s = setup();
  addPlan(
    s,
    plan(
      ["architecture", "models", "identity", "cloudflare"].map((b, i) =>
        spec(`t${i}`, b),
      ),
    ),
    now,
  );
  for (const b of ["architecture", "models", "identity", "cloudflare"])
    heartbeat(s, b, b, true, now);
  assert.ok(claim(s, "architecture", "architecture", now));
  assert.equal(claim(s, "architecture", "architecture", now), null);
  assert.ok(claim(s, "models", "models", now));
  assert.ok(claim(s, "identity", "identity", now));
  assert.equal(claim(s, "cloudflare", "cloudflare", now), null);
});
test("dependent work waits for artifact-version handoff acknowledgment", () => {
  const s = setup();
  addPlan(
    s,
    plan([
      spec("a", "architecture", ["shared"]),
      spec("b", "models", ["shared/schema.ts"], ["a"]),
    ]),
    now,
  );
  heartbeat(s, "architecture", "a1", true, now);
  heartbeat(s, "models", "m1", true, now);
  const a = claim(s, "architecture", "a1", now)!;
  assert.equal(claim(s, "models", "m1", now), null);
  complete(s, "architecture", "a", "a1", a.fence, evidence, now);
  assert.equal(claim(s, "models", "m1", now), null);
  assert.throws(() =>
    acknowledge(s, "models", s.handoffs[0].id, "b".repeat(40), now),
  );
  acknowledge(s, "models", s.handoffs[0].id, evidence.commit, now);
  assert.ok(claim(s, "models", "m1", now));
});
test("failed tests, missing tests, foreign PRs and out-of-scope changes do not complete tasks", () => {
  const s = setup();
  addPlan(s, plan([spec("a", "architecture", ["shared"])]), now);
  heartbeat(s, "architecture", "a1", true, now);
  const t = claim(s, "architecture", "a1", now)!;
  for (const e of [
    { ...evidence, tests: [] },
    {
      ...evidence,
      tests: [{ command: "npm test", status: "failed", detail: "Failure" }],
    },
    { ...evidence, changedFiles: ["other/file.ts"] },
    {
      ...evidence,
      pr: "https://github.com/apple/foundation-models-utilities/pull/2",
    },
  ])
    assert.throws(() =>
      complete(s, "architecture", "a", "a1", t.fence, e, now),
    );
  assert.equal(t.status, "running");
});
test("expired ownership cannot silently transfer or report success", () => {
  const s = setup();
  addPlan(s, plan([spec("a", "architecture", ["shared"])]), now);
  heartbeat(s, "architecture", "old", true, now);
  const fence = claim(s, "architecture", "old", now)!.fence;
  assert.throws(() =>
    complete(s, "architecture", "a", "old", fence, evidence, now + 90001),
  );
  assert.throws(() => heartbeat(s, "architecture", "new", true, now + 90001));
  assert.throws(() => recover(s, "a", false, now + 90001));
  recover(s, "a", true, now + 90001);
  heartbeat(s, "architecture", "new", true, now + 90002);
  const t = claim(s, "architecture", "new", now + 90002)!;
  assert.ok(t.fence > fence);
  assert.throws(() =>
    complete(s, "architecture", "a", "old", fence, evidence, now + 90003),
  );
});
test("all questions in the batch must be answered before dependent dispatch", () => {
  const s = setup();
  addPlan(s, plan([spec("a")]), now);
  heartbeat(s, "architecture", "a1", true, now);
  s.questions = [
    { id: "one", prompt: "A?", options: [] },
    { id: "two", prompt: "B?", options: [] },
  ];
  assert.equal(claim(s, "architecture", "a1", now), null);
  s.questions[0].answer = "A";
  assert.equal(claim(s, "architecture", "a1", now), null);
  s.questions[1].answer = "B";
  assert.ok(claim(s, "architecture", "a1", now));
});
test("pause prevents new claims without discarding ownership", () => {
  const s = setup();
  addPlan(s, plan([spec("a")]), now);
  heartbeat(s, "architecture", "a1", true, now);
  s.paused = true;
  assert.equal(claim(s, "architecture", "a1", now), null);
  s.paused = false;
  assert.ok(claim(s, "architecture", "a1", now));
});
test("fresh plans cannot collide with existing unfinished ownership", () => {
  const s = setup();
  addPlan(s, plan([spec("a", "architecture", ["shared"])]), now);
  assert.throws(() =>
    addPlan(s, plan([spec("b", "models", ["shared/file.ts"])], "second"), now),
  );
});
test("priority: explicit user order precedes urgency and Linear priority", () => {
  const s = setup();
  addPlan(
    s,
    plan([
      { ...spec("urgent"), urgent: true, priority: 1 },
      { ...spec("ordered"), userOrder: 0, priority: 4 },
    ]),
    now,
  );
  heartbeat(s, "architecture", "a1", true, now);
  assert.equal(claim(s, "architecture", "a1", now)?.id, "ordered");
});

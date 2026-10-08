import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
const values = Object.fromEntries(
  (await readFile(".dev.vars", "utf8"))
    .trim()
    .split("\n")
    .map((l) => {
      const i = l.indexOf("=");
      return [l.slice(0, i), l.slice(i + 1)];
    }),
);
const base = process.env.TEST_URL || "http://127.0.0.1:8787";
const owner = values.OWNER_TOKEN;
async function api(route, body, token = owner) {
  const res = await fetch(base + "/v1/" + route, {
    method: body ? "POST" : "GET",
    headers: {
      Authorization: "Bearer " + token,
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json();
  if (!res.ok)
    throw Error(route + ": " + res.status + " " + JSON.stringify(data));
  return data;
}
assert.equal((await fetch(base + "/v1/status")).status, 401);
assert.equal(
  (await fetch(base + "/agents/engineering-coordinator/engineering")).status,
  404,
);
const initial = await api("status");
assert.equal(initial.bots.length, 8);
const suffix = randomUUID().slice(0, 8),
  outcome = "o-" + suffix,
  a = "a-" + suffix,
  b = "b-" + suffix;
await api("outcomes", {
  id: outcome,
  text: "Runtime ownership and handoff proof",
});
const task = (id, owner, paths, dependsOn = []) => ({
  id,
  owner,
  paths,
  dependsOn,
  requirement: "Implement the contract",
  acceptance: ["Verify actual checks"],
});
await api("plans", {
  id: "p-" + suffix,
  outcomeId: outcome,
  tasks: [
    task(a, "architecture", ["shared-" + suffix]),
    task(b, "models", ["shared-" + suffix], [a]),
  ],
});
const architect = (await api("runner-token", { botId: "architecture" })).token,
  models = (await api("runner-token", { botId: "models" })).token;
assert.equal(
  (
    await fetch(base + "/v1/plans", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + architect,
        "Content-Type": "application/json",
      },
      body: "{}",
    })
  ).status,
  404,
);
await api("heartbeat", { executor: "a-" + suffix, ready: true }, architect);
await api("heartbeat", { executor: "m-" + suffix, ready: true }, models);
await api("questions", {
  questions: [
    { id: "q1-" + suffix, prompt: "Budget?", options: [] },
    { id: "q2-" + suffix, prompt: "Scope?", options: [] },
  ],
});
assert.equal(
  (await api("claim", { executor: "a-" + suffix }, architect)).task,
  null,
);
await api("answers", { answers: [{ id: "q1-" + suffix, answer: "Recorded" }] });
assert.equal(
  (await api("claim", { executor: "a-" + suffix }, architect)).task,
  null,
);
await api("answers", { answers: [{ id: "q2-" + suffix, answer: "Recorded" }] });
const claims = await Promise.all([
  api("claim", { executor: "a-" + suffix }, architect),
  api("claim", { executor: "a-" + suffix }, architect),
]);
assert.equal(claims.filter((c) => c.task).length, 1);
const t = claims.find((c) => c.task).task;
const evidence = {
  commit: "a".repeat(40),
  summary: "Contract ready",
  changedFiles: ["shared-" + suffix + "/schema.ts"],
  tests: [
    {
      command: "fixture-contract-check",
      status: "passed",
      detail: "Synthetic evidence for integration testing only",
    },
  ],
};
await api(
  "complete",
  { taskId: a, executor: "a-" + suffix, fence: t.fence, evidence },
  architect,
);
assert.equal(
  (await api("claim", { executor: "m-" + suffix }, models)).task,
  null,
);
const state = await api("status", null, models);
const handoff = state.handoffs.find((h) => h.taskId === a);
assert.deepEqual(handoff.evidence, evidence);
await api("handoffs/ack", { id: handoff.id, commit: handoff.commit }, models);
const next = (await api("claim", { executor: "m-" + suffix }, models)).task;
assert.equal(next.id, b);
await api(
  "complete",
  { taskId: b, executor: "m-" + suffix, fence: next.fence, evidence },
  models,
);
await api("heartbeat", { executor: "a-" + suffix, ready: false }, architect);
await api("heartbeat", { executor: "m-" + suffix, ready: false }, models);
const status = await api("status");
assert.equal(
  status.tasks.filter((t) => t.outcomeId === outcome && t.status === "done")
    .length,
  2,
);
console.log(
  "Runtime passed: authentication, role isolation, full question-batch wait, concurrent claim exclusivity, evidence handoff, dependent execution and persistence.",
);

#!/usr/bin/env node
// A private executor bridge. Model authentication belongs to the chosen harness;
// it is never collected through chat or copied from the assistant's environment.
import { spawn } from "node:child_process";
import { mkdir, writeFile, readFile } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
const endpoint = process.env.COORDINATOR_URL;
const token = process.env.RUNNER_TOKEN;
const harness = process.env.ENGINEERING_HARNESS;
const stateDir = path.resolve(
  process.env.RUNNER_STATE_DIR || ".engineering-runner",
);
if (!endpoint || !token || !harness)
  throw Error(
    "Set COORDINATOR_URL, RUNNER_TOKEN and ENGINEERING_HARNESS in the executor secret environment.",
  );
if (
  new URL(endpoint).protocol !== "https:" &&
  !["localhost", "127.0.0.1"].includes(new URL(endpoint).hostname)
)
  throw Error("Remote coordinator must use HTTPS");
await mkdir(stateDir, { recursive: true, mode: 0o700 });
const checkpoint = path.join(stateDir, "checkpoint.json");
let previous;
try {
  previous = JSON.parse(await readFile(checkpoint, "utf8"));
} catch (e) {
  if (e.code !== "ENOENT") throw e;
}
if (previous && !previous.closed)
  throw Error(
    "Previous task was not reconciled. Inspect its artifacts and recover it before starting another executor.",
  );
const executor = randomUUID();
let stopped = false,
  child = null,
  heartbeatRunning = false,
  heartbeatFailure = null;
async function api(route, body) {
  const response = await fetch(new URL("/v1/" + route, endpoint), {
    method: body ? "POST" : "GET",
    headers: {
      Authorization: "Bearer " + token,
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok)
    throw Error(`Coordinator ${route}: HTTP ${response.status}`);
  return response.json();
}
async function pulse() {
  if (heartbeatRunning) return;
  heartbeatRunning = true;
  try {
    await api("heartbeat", { executor, ready: true });
  } catch (e) {
    heartbeatFailure = e;
    stopped = true;
    stopChild();
  } finally {
    heartbeatRunning = false;
  }
}
function stopChild() {
  if (child) {
    try {
      if (process.platform !== "win32") process.kill(-child.pid, "SIGTERM");
      else child.kill("SIGTERM");
    } catch {}
    setTimeout(() => {
      try {
        if (child && process.platform !== "win32")
          process.kill(-child.pid, "SIGKILL");
        else child?.kill("SIGKILL");
      } catch {}
    }, 3000).unref();
  }
}
process.on("SIGINT", () => {
  stopped = true;
  stopChild();
});
process.on("SIGTERM", () => {
  stopped = true;
  stopChild();
});
async function runHarness(payload) {
  return new Promise((resolve, reject) => {
    child = spawn(harness, [], {
      stdio: ["pipe", "pipe", "pipe"],
      shell: false,
      detached: process.platform !== "win32",
    });
    let out = "",
      err = "";
    const timeout = setTimeout(
      () => {
        stopChild();
        reject(Error("Harness exceeded 30 minute task limit"));
      },
      30 * 60 * 1000,
    );
    child.stdout.on("data", (chunk) => {
      out += chunk;
      if (out.length > 1_000_000) {
        stopChild();
        reject(Error("Harness output exceeded limit"));
      }
    });
    child.stderr.on("data", (chunk) => {
      err = (err + chunk).slice(-4000);
    });
    child.on("error", (e) => {
      clearTimeout(timeout);
      child = null;
      reject(e);
    });
    child.on("close", (code) => {
      clearTimeout(timeout);
      child = null;
      if (code !== 0)
        return reject(
          Error(`Harness failed with exit ${code}; inspect local harness logs`),
        );
      try {
        resolve(JSON.parse(out));
      } catch {
        reject(Error("Harness must return one JSON evidence object on stdout"));
      }
    });
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify(payload));
  });
}
await pulse();
if (heartbeatFailure) throw heartbeatFailure;
const timer = setInterval(() => {
  void pulse();
}, 20000);
try {
  while (!stopped) {
    const state = await api("status");
    for (const handoff of state.handoffs.filter((h) => !h.acknowledgedAt)) {
      await writeFile(
        path.join(stateDir, `handoff-${handoff.id}.json`),
        JSON.stringify(handoff),
        { mode: 0o600 },
      );
      await api("handoffs/ack", { id: handoff.id, commit: handoff.commit });
    }
    const assignment = await api("claim", { executor });
    if (!assignment.task) {
      await new Promise((r) => setTimeout(r, 5000));
      continue;
    }
    const task = assignment.task;
    const record = {
      executor,
      task,
      context: assignment.context,
      closed: false,
    };
    await writeFile(checkpoint, JSON.stringify(record), { mode: 0o600 });
    try {
      const evidence = await runHarness({
        ...assignment,
        repository: "kmshdev/foundation-models-utilities",
        specialty: state.bot.specialty,
        policy: {
          isolatedWorktree: true,
          exclusivePaths: task.paths,
          recordObservedTests: true,
        },
      });
      if (heartbeatFailure) throw heartbeatFailure;
      await api("complete", {
        taskId: task.id,
        executor,
        fence: task.fence,
        evidence,
      });
      await writeFile(checkpoint, JSON.stringify({ ...record, closed: true }), {
        mode: 0o600,
      });
    } catch (e) {
      try {
        await api("progress", {
          taskId: task.id,
          executor,
          fence: task.fence,
          message: e.message,
          blocked: true,
        });
      } catch {}
      stopped = true;
      throw e;
    }
  }
} finally {
  clearInterval(timer);
  stopChild();
  try {
    await api("heartbeat", { executor, ready: false });
  } catch {}
}

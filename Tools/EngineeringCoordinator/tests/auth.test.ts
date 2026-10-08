import { test } from "node:test";
import assert from "node:assert/strict";
import { authenticate, mintRunner } from "../src/auth";
const owner = "o".repeat(48),
  key = "k".repeat(48);
test("owner and role-scoped runner identities remain distinct", async () => {
  assert.deepEqual(
    await authenticate(
      new Request("https://room/v1/status", {
        headers: { Authorization: `Bearer ${owner}` },
      }),
      owner,
      key,
    ),
    { role: "owner" },
  );
  const token = await mintRunner("quality", key);
  assert.deepEqual(
    await authenticate(
      new Request("https://room/v1/status", {
        headers: { Authorization: `Bearer ${token}` },
      }),
      owner,
      key,
    ),
    { role: "runner", botId: "quality" },
  );
  await assert.rejects(() => mintRunner("intruder", key));
});
test("missing, tampered or unconfigured credentials fail closed", async () => {
  await assert.rejects(() =>
    authenticate(new Request("https://room/v1/status"), owner, key),
  );
  await assert.rejects(() =>
    authenticate(
      new Request("https://room/v1/status", {
        headers: { Authorization: "Bearer invalid" },
      }),
      owner,
      key,
    ),
  );
  await assert.rejects(() =>
    authenticate(
      new Request("https://room/v1/status", {
        headers: { Authorization: `Bearer ${owner}` },
      }),
      undefined,
      key,
    ),
  );
});

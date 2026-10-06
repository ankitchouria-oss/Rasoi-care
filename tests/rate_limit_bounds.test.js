const { test } = require("node:test");
const assert = require("node:assert/strict");
const { setup } = require("./helpers");
const { BoundedMap } = require("../server/ratelimit");

const client = setup();

test("BoundedMap evicts the oldest key past maxSize", () => {
  const d = new BoundedMap(() => 0, 3);
  d.getOrCreate("a");
  d.getOrCreate("b");
  d.getOrCreate("c");
  assert.deepEqual(d.keys(), ["a", "b", "c"]);
  d.getOrCreate("d"); // over capacity — evicts "a", the least recently touched
  assert.deepEqual(d.keys(), ["b", "c", "d"]);
});

test("BoundedMap touch marks a key recently used", () => {
  const d = new BoundedMap(() => 0, 3);
  d.getOrCreate("a");
  d.getOrCreate("b");
  d.getOrCreate("c");
  d.getOrCreate("a"); // protects "a" from the next eviction
  d.getOrCreate("d");
  assert.ok(d.has("a"));
  assert.ok(!d.has("b"));
});

test("request body over the size limit returns a 413 JSON error", async () => {
  const resp = await client.post("/api/auth/register", {
    rawBody: Buffer.alloc(17 * 1024 * 1024, "x"), contentType: "application/json",
  });
  assert.equal(resp.status, 413);
  assert.ok(resp.body.error);
});

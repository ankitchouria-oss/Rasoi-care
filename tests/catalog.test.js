const { test } = require("node:test");
const assert = require("node:assert/strict");
const { setup } = require("./helpers");

const client = setup();

test("appliances listed", async () => {
  const resp = await client.get("/api/appliances");
  assert.equal(resp.status, 200);
  assert.ok(Array.isArray(resp.body) && resp.body.length > 0);
});

test("services listed", async () => {
  const resp = await client.get("/api/services");
  assert.equal(resp.status, 200);
  assert.ok(Array.isArray(resp.body) && resp.body.length > 0);
  assert.ok("price" in resp.body[0]);
});

test("customer catalog services are seeded and filterable", async () => {
  const resp = await client.get("/api/services?category=RasoiAir&quick_fix=false");
  assert.ok(resp.body.some((s) => s.id === "svc_chimney_deep_clean_full"));
  assert.ok(resp.body.every((s) => s.category === "RasoiAir" && s.quick_fix === false));
});

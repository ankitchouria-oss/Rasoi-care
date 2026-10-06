const { test } = require("node:test");
const assert = require("node:assert/strict");
const { setup, registerAndLogin, authHeaders, OWNER_PHONE, OWNER_PIN } = require("./helpers");

const client = setup();

test("staff login succeeds with the seeded owner", async () => {
  const resp = await client.post("/api/staff/login", { json: { phone: OWNER_PHONE, pin: OWNER_PIN } });
  assert.equal(resp.status, 200);
  assert.ok(resp.body.token);
  assert.equal(resp.body.staff.role, "owner");
});

test("staff login with the wrong PIN is rejected", async () => {
  assert.equal((await client.post("/api/staff/login", { json: { phone: OWNER_PHONE, pin: "0000" } })).status, 401);
});

test("staff me requires auth", async () => {
  assert.equal((await client.get("/api/staff/me")).status, 401);
});

test("staff me returns the current staff member", async () => {
  const login = (await client.post("/api/staff/login", { json: { phone: OWNER_PHONE, pin: OWNER_PIN } })).body;
  const resp = await client.get("/api/staff/me", { headers: authHeaders(login.token) });
  assert.equal(resp.status, 200);
  assert.equal(resp.body.phone, OWNER_PHONE);
});

test("a customer token is rejected on a staff route", async () => {
  const user = await registerAndLogin(client);
  assert.equal((await client.get("/api/staff/me", { headers: authHeaders(user.token) })).status, 401);
});

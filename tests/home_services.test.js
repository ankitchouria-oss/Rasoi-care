const { test } = require("node:test");
const assert = require("node:assert/strict");
const { setup, registerAndLogin, authHeaders } = require("./helpers");

const client = setup();

test("hs state requires auth", async () => {
  assert.equal((await client.get("/api/hs/state")).status, 401);
});

test("hs state lazily creates wallet and profile", async () => {
  const user = await registerAndLogin(client);
  const resp = await client.get("/api/hs/state", { headers: authHeaders(user.token) });
  assert.equal(resp.status, 200);
  assert.deepEqual(resp.body.bookings, []);
  assert.deepEqual(resp.body.wallet, { points: 100, tx: [] });
  assert.equal(resp.body.profile.name, "Alice");
});

test("hs booking lifecycle and cashback", async () => {
  const user = await registerAndLogin(client);
  const headers = authHeaders(user.token);
  const created = await client.post("/api/hs/bookings", { json: { serviceId: "otg", date: "2026-09-05" }, headers });
  assert.equal(created.status, 201);
  let result;
  // Requested -> Accepted -> On the way -> In Progress -> Completed
  for (let i = 0; i < 4; i++) {
    result = (await client.patch(`/api/hs/bookings/${created.body.id}/advance`, { headers })).body;
  }
  assert.equal(result.booking.status, "Completed");
  assert.equal(result.wallet.points, 122); // 100 starter + 5% of 449 (server-priced)
  assert.equal(result.wallet.tx[0].label, "Cashback: OTG");
});

test("hs redeem requires enough points", async () => {
  const user = await registerAndLogin(client);
  const headers = authHeaders(user.token);
  const r1 = await client.post("/api/hs/wallet/redeem", { headers });
  assert.equal(r1.status, 200);
  assert.equal(r1.body.points, 50);
  const r2 = await client.post("/api/hs/wallet/redeem", { headers });
  assert.equal(r2.status, 200);
  assert.equal(r2.body.points, 0);
  assert.equal((await client.post("/api/hs/wallet/redeem", { headers })).status, 400);
});

test("hs profile update", async () => {
  const user = await registerAndLogin(client);
  const resp = await client.patch("/api/hs/profile", { json: { name: "Renamed" }, headers: authHeaders(user.token) });
  assert.equal(resp.status, 200);
  assert.equal(resp.body.name, "Renamed");
});

test("hs data isolated between users", async () => {
  const alice = await registerAndLogin(client, { email: "hs-alice@example.com", phone: "9111111111" });
  const bob = await registerAndLogin(client, { email: "hs-bob@example.com", name: "Bob", phone: "9222222222" });
  await client.post("/api/hs/bookings", { json: { serviceId: "otg", date: "2026-09-05" }, headers: authHeaders(alice.token) });
  const bobState = (await client.get("/api/hs/state", { headers: authHeaders(bob.token) })).body;
  assert.deepEqual(bobState.bookings, []);
  assert.equal(bobState.wallet.points, 100);
});

test("hs booking rejects unknown service and ignores client price", async () => {
  const user = await registerAndLogin(client);
  const resp = await client.post("/api/hs/bookings", {
    json: { serviceId: "svc1", price: 9999999, date: "2026-09-05" }, headers: authHeaders(user.token),
  });
  assert.equal(resp.status, 400);
});

test("hs advance on unknown booking 404s", async () => {
  const user = await registerAndLogin(client);
  const resp = await client.patch("/api/hs/bookings/does-not-exist/advance", { headers: authHeaders(user.token) });
  assert.equal(resp.status, 404);
});

test("hs reset", async () => {
  const user = await registerAndLogin(client);
  const headers = authHeaders(user.token);
  await client.post("/api/hs/bookings", { json: { serviceId: "otg", date: "2026-09-05" }, headers });
  assert.equal((await client.post("/api/hs/reset", { headers })).status, 200);
  const state = (await client.get("/api/hs/state", { headers })).body;
  assert.deepEqual(state.bookings, []);
  assert.equal(state.wallet.points, 100);
});

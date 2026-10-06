const { test } = require("node:test");
const assert = require("node:assert/strict");
const { setup, registerAndLogin, authHeaders, mockFirebaseClaims } = require("./helpers");

const client = setup();

test("customer bootstrap: unverified email cannot take over an existing account", async () => {
  const victim = await registerAndLogin(client, { email: "victim@example.com" });
  // A brand-new Firebase account claiming the victim's email, unverified.
  mockFirebaseClaims({ uid: "attacker-uid", email: "victim@example.com", email_verified: false });
  const resp = await client.post("/api/me/bootstrap", { json: { name: "Attacker" }, headers: authHeaders("x") });
  assert.equal(resp.status, 200);
  assert.notEqual(resp.body.id, victim.user.id);
});

test("customer bootstrap: verified email merges into the existing account", async () => {
  const victim = await registerAndLogin(client, { email: "victim2@example.com" });
  mockFirebaseClaims({ uid: "real-uid", email: "victim2@example.com", email_verified: true });
  const resp = await client.post("/api/me/bootstrap", { json: { name: "Victim" }, headers: authHeaders("x") });
  assert.equal(resp.status, 200);
  assert.equal(resp.body.id, victim.user.id);
});

test("staff bootstrap: a later signup can never become owner", async () => {
  mockFirebaseClaims({ uid: "owner-uid", email: "owner@example.com", email_verified: true });
  const first = await client.post("/api/staff/bootstrap", { json: { role: "owner" }, headers: authHeaders("x") });
  // The seeded demo staff mean this deployment already has staff.
  assert.equal(first.body.role, "staff");

  mockFirebaseClaims({ uid: "attacker-uid", email: "attacker@example.com", email_verified: true });
  const second = await client.post("/api/staff/bootstrap", { json: { role: "owner" }, headers: authHeaders("x") });
  assert.equal(second.status, 200);
  assert.equal(second.body.role, "staff");
});

test("staff bootstrap: unverified email cannot take over existing staff", async () => {
  mockFirebaseClaims({ uid: "staffer-uid", email: "staffer@example.com", email_verified: true });
  const original = (await client.post("/api/staff/bootstrap", { json: {}, headers: authHeaders("x") })).body;
  mockFirebaseClaims({ uid: "attacker-uid", email: "staffer@example.com", email_verified: false });
  const resp = await client.post("/api/staff/bootstrap", { json: {}, headers: authHeaders("x") });
  assert.notEqual(resp.body.id, original.id);
});

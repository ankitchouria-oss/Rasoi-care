const { test } = require("node:test");
const assert = require("node:assert/strict");
const { setup, registerAndLogin, authHeaders } = require("./helpers");

const client = setup();

test("health check", async () => {
  assert.equal((await client.get("/api/health")).status, 200);
});

test("register creates account and returns token", async () => {
  const body = await registerAndLogin(client);
  assert.ok(body.token);
  assert.equal(body.user.email, "alice@example.com");
  assert.equal(body.user.name, "Alice");
  assert.equal(body.user.phone, "9876543210");
});

test("register duplicate email rejected", async () => {
  await registerAndLogin(client);
  const resp = await client.post("/api/auth/register", {
    json: { email: "alice@example.com", password: "hunter22", name: "Alice 2" },
  });
  assert.ok(resp.status >= 400);
});

test("register rejects short password", async () => {
  const resp = await client.post("/api/auth/register", { json: { email: "bob@example.com", password: "abc", name: "Bob" } });
  assert.equal(resp.status, 400);
});

test("login with correct credentials succeeds", async () => {
  await registerAndLogin(client);
  const resp = await client.post("/api/auth/login", { json: { email: "alice@example.com", password: "hunter22" } });
  assert.equal(resp.status, 200);
  assert.ok(resp.body.token);
});

test("login with wrong password fails", async () => {
  await registerAndLogin(client);
  const resp = await client.post("/api/auth/login", { json: { email: "alice@example.com", password: "wrong-pass" } });
  assert.equal(resp.status, 401);
});

test("login with unknown email fails", async () => {
  const resp = await client.post("/api/auth/login", { json: { email: "nobody@example.com", password: "whatever1" } });
  assert.equal(resp.status, 401);
});

test("me requires auth", async () => {
  assert.equal((await client.get("/api/auth/me")).status, 401);
});

test("me returns current user", async () => {
  const body = await registerAndLogin(client);
  const resp = await client.get("/api/auth/me", { headers: authHeaders(body.token) });
  assert.equal(resp.status, 200);
  assert.equal(resp.body.email, "alice@example.com");
});

test("me rejects garbage token", async () => {
  const resp = await client.get("/api/auth/me", { headers: { Authorization: "Bearer not-a-real-token" } });
  assert.equal(resp.status, 401);
});

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { setup, registerAndLogin, captureSms } = require("./helpers");

const client = setup();

const codeFrom = (captured) => /code is (\d{4})/.exec(captured.content)[1];

test("send-otp requires a valid phone", async () => {
  assert.equal((await client.post("/api/auth/phone/send-otp", { json: { phone: "123" } })).status, 400);
});

test("full signup flow creates an account with an unguessable password", async () => {
  const captured = captureSms();
  const phone = "9812345670";
  const sent = await client.post("/api/auth/phone/send-otp", { json: { phone } });
  assert.equal(sent.status, 200);
  assert.equal(sent.body.sent, true);

  const verified = await client.post("/api/auth/phone/verify-otp", { json: { phone, otp: codeFrom(captured) } });
  assert.equal(verified.status, 200);
  assert.deepEqual(verified.body, { needsRegistration: true });

  const registered = await client.post("/api/auth/phone/register", { json: { phone, name: "New Customer" } });
  assert.equal(registered.status, 201, JSON.stringify(registered.body));
  assert.ok(registered.body.token);
  assert.equal(registered.body.user.phone, phone);

  // The old predictable scheme ('rc-' + phone) must not work.
  const oldScheme = await client.post("/api/auth/login", {
    json: { email: `${phone}@rasoicare.demo`, password: `rc-${phone}` },
  });
  assert.equal(oldScheme.status, 401);
});

test("verify-otp logs in an existing account by phone", async () => {
  const phone = "9812345671";
  await registerAndLogin(client, { email: "existing@example.com", phone });
  const captured = captureSms();
  await client.post("/api/auth/phone/send-otp", { json: { phone } });
  const resp = await client.post("/api/auth/phone/verify-otp", { json: { phone, otp: codeFrom(captured) } });
  assert.equal(resp.status, 200);
  assert.ok(resp.body.token);
  assert.equal(resp.body.user.phone, phone);
});

test("verify-otp rejects a wrong code", async () => {
  const phone = "9812345672";
  const captured = captureSms();
  await client.post("/api/auth/phone/send-otp", { json: { phone } });
  const wrong = codeFrom(captured) === "0000" ? "1111" : "0000";
  const resp = await client.post("/api/auth/phone/verify-otp", { json: { phone, otp: wrong } });
  assert.equal(resp.status, 400);
});

test("register requires a verified phone first", async () => {
  const resp = await client.post("/api/auth/phone/register", { json: { phone: "9812345673", name: "Nobody" } });
  assert.equal(resp.status, 400);
});

test("register is a one-time use of the verified flag", async () => {
  const phone = "9812345674";
  const captured = captureSms();
  await client.post("/api/auth/phone/send-otp", { json: { phone } });
  await client.post("/api/auth/phone/verify-otp", { json: { phone, otp: codeFrom(captured) } });
  assert.equal((await client.post("/api/auth/phone/register", { json: { phone, name: "Alice" } })).status, 201);
  // Can't piggyback on the first registration's proof of phone ownership.
  assert.equal((await client.post("/api/auth/phone/register", { json: { phone, name: "Alice" } })).status, 400);
});

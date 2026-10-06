const { test } = require("node:test");
const assert = require("node:assert/strict");
const { setup, registerAndLogin, authHeaders, addTechnician, sql, staffHeaders } = require("./helpers");

const client = setup();

async function firstServiceId() {
  return (await client.get("/api/services")).body[0].id;
}

test("create booking requires auth", async () => {
  assert.equal((await client.post("/api/bookings", { json: { service_id: "x" } })).status, 401);
});

test("create booking fails with no technicians", async () => {
  const user = await registerAndLogin(client);
  const resp = await client.post("/api/bookings", {
    json: { service_id: await firstServiceId() }, headers: authHeaders(user.token),
  });
  assert.equal(resp.status, 503);
});

test("create booking happy path", async () => {
  await addTechnician();
  const user = await registerAndLogin(client);
  const resp = await client.post("/api/bookings", {
    json: { service_id: await firstServiceId() }, headers: authHeaders(user.token),
  });
  assert.equal(resp.status, 201, JSON.stringify(resp.body));
  assert.match(resp.body.id, /^RC-/);
  assert.equal(resp.body.status, "Requested");
  assert.equal(resp.body.technicianId, null);

  const listing = (await client.get("/api/bookings", { headers: authHeaders(user.token) })).body;
  assert.equal(listing.length, 1);
  assert.equal(listing[0].id, resp.body.id);
});

test("create booking rejects unknown service_id", async () => {
  await addTechnician();
  const user = await registerAndLogin(client);
  const resp = await client.post("/api/bookings", {
    json: { service_id: "does-not-exist" }, headers: authHeaders(user.token),
  });
  assert.equal(resp.status, 400);
});

test("bookings isolated between customers", async () => {
  await addTechnician();
  const alice = await registerAndLogin(client, { email: "alice2@example.com", phone: "9876543211" });
  const bob = await registerAndLogin(client, { email: "bob2@example.com", name: "Bob", phone: "9876543212" });
  await client.post("/api/bookings", { json: { service_id: await firstServiceId() }, headers: authHeaders(alice.token) });
  const bobBookings = (await client.get("/api/bookings", { headers: authHeaders(bob.token) })).body;
  assert.deepEqual(bobBookings, []);
});

test("assign technician rejects unverified technician", async () => {
  await sql(
    "INSERT INTO technicians (id, name, category, area, verified, online, rating, rating_count, jobs_completed) "
      + "VALUES ('unverified-tech', 'Not Yet Verified', 'RasoiSpark', 'Test Area', 0, 0, 5.0, 0, 0)",
  );
  await addTechnician();
  const user = await registerAndLogin(client);
  const booking = (await client.post("/api/bookings", {
    json: { service_id: await firstServiceId() }, headers: authHeaders(user.token),
  })).body;
  const resp = await client.patch(`/api/bookings/${booking.id}/assign`, {
    json: { technician_id: "unverified-tech" }, headers: await staffHeaders(client),
  });
  assert.equal(resp.status, 400);
});

test("assign technician rejects reassigning a completed booking", async () => {
  await addTechnician({ tid: "tech1" });
  await addTechnician({ tid: "tech2" });
  const user = await registerAndLogin(client);
  const booking = (await client.post("/api/bookings", {
    json: { service_id: await firstServiceId() }, headers: authHeaders(user.token),
  })).body;
  const headers = await staffHeaders(client);
  await client.patch(`/api/bookings/${booking.id}/assign`, { json: { technician_id: "tech1" }, headers });
  await sql("UPDATE bookings SET status = 'Completed' WHERE id = ?", [booking.id]);
  const resp = await client.patch(`/api/bookings/${booking.id}/assign`, { json: { technician_id: "tech2" }, headers });
  assert.equal(resp.status, 400);
});

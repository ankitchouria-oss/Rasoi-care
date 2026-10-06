const { test } = require("node:test");
const assert = require("node:assert/strict");
const { setup, registerAndLogin, authHeaders, addTechnician, sql } = require("./helpers");

const client = setup();

async function completedBooking(user, tid = "tech1") {
  await addTechnician({ tid });
  const services = (await client.get("/api/services")).body;
  const resp = await client.post("/api/bookings", { json: { service_id: services[0].id }, headers: authHeaders(user.token) });
  await sql("UPDATE bookings SET technician_id = ?, status = 'Completed' WHERE id = ?", [tid, resp.body.id]);
  return resp.body.id;
}

test("a rating cannot be submitted twice", async () => {
  const user = await registerAndLogin(client);
  const bookingId = await completedBooking(user);
  const first = await client.post(`/api/bookings/${bookingId}/rating`, {
    json: { serviceRating: 5, techRating: 5 }, headers: authHeaders(user.token),
  });
  assert.equal(first.status, 200);
  const [afterFirst] = await sql("SELECT rating, rating_count FROM technicians WHERE id = 'tech1'");
  assert.equal(afterFirst.rating_count, 11); // seeded at 10 + this one

  // Replaying (or a spammed 1-star) must not roll the average again.
  const second = await client.post(`/api/bookings/${bookingId}/rating`, {
    json: { serviceRating: 1, techRating: 1 }, headers: authHeaders(user.token),
  });
  assert.equal(second.status, 400);
  const [afterSecond] = await sql("SELECT rating, rating_count FROM technicians WHERE id = 'tech1'");
  assert.equal(afterSecond.rating_count, 11);
  assert.equal(afterSecond.rating, afterFirst.rating);
});

test("rating rejects another customer's booking", async () => {
  const alice = await registerAndLogin(client, { email: "alice3@example.com", phone: "9876543213" });
  const bob = await registerAndLogin(client, { email: "bob3@example.com", name: "Bob", phone: "9876543214" });
  const bookingId = await completedBooking(alice);
  const resp = await client.post(`/api/bookings/${bookingId}/rating`, {
    json: { serviceRating: 1, techRating: 1 }, headers: authHeaders(bob.token),
  });
  // 404, not 403 — booking ids are sequential.
  assert.equal(resp.status, 404);
});

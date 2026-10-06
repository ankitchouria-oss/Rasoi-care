const { test } = require("node:test");
const assert = require("node:assert/strict");
const { setup, registerAndLogin, authHeaders, mockFirebaseClaims, sql } = require("./helpers");

const client = setup();

async function bootstrapTechnician(uid, { category = "RasoiSpark", area = "Test Area" } = {}) {
  mockFirebaseClaims({ uid, email: `${uid}@example.com`, email_verified: true });
  const resp = await client.post("/api/technician/bootstrap", {
    json: { name: "Test Tech", category, area }, headers: authHeaders("x"),
  });
  assert.equal(resp.status, 200, JSON.stringify(resp.body));
  return resp.body;
}

async function createBooking({ category = "RasoiSpark", lat, lng, addressLine } = {}) {
  await sql(
    "INSERT INTO technicians (id, name, category, area, verified, online, rating, rating_count, jobs_completed) "
      + "VALUES ('seed-tech', 'Seed Tech', ?, 'Test Area', 1, 1, 4.5, 10, 10)",
    [category],
  );
  const user = await registerAndLogin(client, { email: "customer-claims@example.com", phone: "9876500001" });
  const services = (await client.get("/api/services")).body;
  const payload = { service_id: services.find((s) => s.category === category).id };
  if (lat !== undefined) payload.lat = lat;
  if (lng !== undefined) payload.lng = lng;
  if (addressLine !== undefined) payload.addressLine = addressLine;
  return (await client.post("/api/bookings", { json: payload, headers: authHeaders(user.token) })).body;
}

test("available bookings hide address and phone before a claim", async () => {
  const booking = await createBooking();
  const tech = await bootstrapTechnician("tech-see");
  await sql("UPDATE technicians SET verified = 1, online = 1 WHERE id = ?", [tech.id]);
  const resp = await client.get("/api/technician/bookings/available", { headers: authHeaders("x") });
  assert.equal(resp.status, 200);
  const listed = resp.body.find((b) => b.id === booking.id);
  assert.equal(listed.addressLine, null);
  assert.equal(listed.customerPhone, null);
  assert.equal(listed.lat, null);
  assert.equal(listed.lng, null);
});

test("an unverified technician cannot claim a booking", async () => {
  const booking = await createBooking();
  await bootstrapTechnician("tech-unverified"); // bootstrap always leaves them unverified
  const resp = await client.patch(`/api/bookings/${booking.id}/claim`, { headers: authHeaders("x") });
  assert.equal(resp.status, 403);
  const [row] = await sql("SELECT technician_id FROM bookings WHERE id = ?", [booking.id]);
  assert.equal(row.technician_id, null);
});

test("a verified technician can claim a booking", async () => {
  const booking = await createBooking();
  const tech = await bootstrapTechnician("tech-verified");
  await sql("UPDATE technicians SET verified = 1 WHERE id = ?", [tech.id]);
  const resp = await client.patch(`/api/bookings/${booking.id}/claim`, { headers: authHeaders("x") });
  assert.equal(resp.status, 200);
  assert.equal(resp.body.technicianId, tech.id);
});

test("booking city is inferred from coordinates", async () => {
  assert.equal((await createBooking({ lat: 19.9975, lng: 73.7898 })).city, "Nashik");
});

test("booking city is inferred from address text without coordinates", async () => {
  assert.equal((await createBooking({ addressLine: "12 FC Road, Pune, Maharashtra" })).city, "Pune");
});

test("a booking with no address has no city", async () => {
  assert.equal((await createBooking()).city, null);
});

test("available bookings only reach technicians in the same city", async () => {
  const booking = await createBooking({ lat: 19.9975, lng: 73.7898 }); // Nashik
  assert.equal(booking.city, "Nashik");

  const nashikTech = await bootstrapTechnician("tech-nashik", { area: "Nashik" });
  await sql("UPDATE technicians SET verified = 1, online = 1 WHERE id = ?", [nashikTech.id]);
  const listing = (await client.get("/api/technician/bookings/available", { headers: authHeaders("x") })).body;
  assert.ok(listing.some((b) => b.id === booking.id));

  const puneTech = await bootstrapTechnician("tech-pune", { area: "Pune" });
  await sql("UPDATE technicians SET verified = 1, online = 1 WHERE id = ?", [puneTech.id]);
  const listing2 = (await client.get("/api/technician/bookings/available", { headers: authHeaders("x") })).body;
  assert.ok(!listing2.some((b) => b.id === booking.id));
});

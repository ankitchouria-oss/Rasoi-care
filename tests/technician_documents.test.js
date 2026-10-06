const { test } = require("node:test");
const assert = require("node:assert/strict");
const { setup, addTechnician, sql, staffHeaders } = require("./helpers");

const client = setup();

test("listing technicians redacts document URLs", async () => {
  await addTechnician();
  await sql("UPDATE technicians SET aadhar_document_url = 'https://firebasestorage.googleapis.com/x' WHERE id = 'tech1'");
  const resp = await client.get("/api/technicians", { headers: await staffHeaders(client) });
  assert.equal(resp.status, 200);
  assert.equal(resp.body[0].aadharDocumentUrl, null);
  assert.equal(resp.body[0].aadharDocumentReady, true);
});

test("document proxy rejects an untrusted host", async () => {
  await addTechnician();
  await sql("UPDATE technicians SET aadhar_document_url = 'https://evil.example.com/steal' WHERE id = 'tech1'");
  const resp = await client.get("/api/technicians/tech1/document/aadhar-front", { headers: await staffHeaders(client) });
  assert.equal(resp.status, 502);
});

test("document proxy 404s when nothing was uploaded", async () => {
  await addTechnician();
  const resp = await client.get("/api/technicians/tech1/document/pan", { headers: await staffHeaders(client) });
  assert.equal(resp.status, 404);
});

test("document proxy requires staff auth", async () => {
  await addTechnician();
  assert.equal((await client.get("/api/technicians/tech1/document/pan")).status, 401);
});

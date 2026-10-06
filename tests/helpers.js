/*
 * Shared test setup. High rate-limit ceilings and a fixed JWT secret are
 * set *before* the app is loaded (its limits are read once, at load time)
 * so a suite can make many requests back-to-back. Every test gets its own
 * throwaway SQLite file — nothing here touches a real database.
 */

const os = require("node:os");
const fs = require("node:fs");
const path = require("node:path");
const { beforeEach, afterEach, before, after } = require("node:test");
const assert = require("node:assert/strict");

process.env.JWT_SECRET ??= "test-secret-do-not-use-in-production";
for (const name of [
  "RATE_LIMIT_GLOBAL_MAX_CALLS",
  "RATE_LIMIT_PUBLIC_MAX_CALLS",
  "RATE_LIMIT_AUTHENTICATED_MAX_CALLS",
  "RATE_LIMIT_AUTH_ACCOUNT_FREE_ATTEMPTS",
  "RATE_LIMIT_AUTH_IP_FREE_ATTEMPTS",
]) {
  process.env[name] ??= "100000";
}
delete process.env.DB_HOST;
delete process.env.DATABASE_URL;

const db = require("../server/db");
const integrations = require("../server/integrations");
const { app } = require("../server/app");

const originals = { ...integrations };

/** Registers the per-test fixtures and returns an HTTP client bound to a
 * server started once for the calling test file. */
function setup() {
  let server;
  let baseUrl;
  let tmpDir;

  before(async () => {
    server = app.listen(0);
    await new Promise((resolve) => server.once("listening", resolve));
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(async () => {
    await new Promise((resolve) => server.close(resolve));
    await db.closeAll();
  });

  beforeEach(async () => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "rasoicare-test-"));
    db.useSqliteFile(path.join(tmpDir, "test.db"));
    await db.initDb();
  });

  afterEach(async () => {
    Object.assign(integrations, originals);
    await db.closeAll();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  async function request(method, urlPath, { json, headers = {}, rawBody, contentType } = {}) {
    const init = { method, headers: { ...headers } };
    if (json !== undefined) {
      init.body = JSON.stringify(json);
      init.headers["Content-Type"] = "application/json";
    } else if (rawBody !== undefined) {
      init.body = rawBody;
      if (contentType) init.headers["Content-Type"] = contentType;
    }
    const resp = await fetch(baseUrl + urlPath, init);
    const text = await resp.text();
    let body = null;
    try {
      body = JSON.parse(text);
    } catch {
      body = null;
    }
    return { status: resp.status, body, headers: resp.headers };
  }

  return {
    get: (p, opts) => request("GET", p, opts),
    post: (p, opts) => request("POST", p, opts),
    patch: (p, opts) => request("PATCH", p, opts),
    delete: (p, opts) => request("DELETE", p, opts),
  };
}

async function registerAndLogin(client, {
  email = "alice@example.com", password = "hunter22", name = "Alice", phone = "9876543210",
} = {}) {
  const resp = await client.post("/api/auth/register", { json: { email, password, name, phone } });
  assert.equal(resp.status, 201, JSON.stringify(resp.body));
  return resp.body;
}

const authHeaders = (token) => ({ Authorization: `Bearer ${token}` });

/** Direct database access for arranging test state. */
async function sql(statement, params = []) {
  const conn = await db.getDb();
  try {
    const result = /^\s*select/i.test(statement) ? await conn.all(statement, params) : await conn.run(statement, params);
    await conn.commit();
    return result;
  } finally {
    conn.close();
  }
}

async function addTechnician({ tid = "tech1", category = "RasoiSpark", area = "Test Area" } = {}) {
  await sql(
    "INSERT INTO technicians (id, name, category, area, verified, online, rating, rating_count, jobs_completed) "
      + "VALUES (?,?,?,?,1,1,4.5,10,10)",
    [tid, "Test Technician", category, area],
  );
}

/** Makes every Firebase-authenticated endpoint see these claims, without a
 * real Firebase project. Any bearer token value works. */
function mockFirebaseClaims({ uid, email = null, email_verified = false, name = null, phone_number = null }) {
  integrations.verifyFirebaseToken = async () => ({ uid, email, email_verified, name, phone_number });
}

/** Captures outgoing SMS instead of sending them. */
function captureSms() {
  const captured = {};
  integrations.sendSms = async (to, content) => {
    captured.to = to;
    captured.content = content;
    return true;
  };
  return captured;
}

const OWNER_PHONE = "9822000001";
const OWNER_PIN = "1234";

async function staffHeaders(client) {
  const login = await client.post("/api/staff/login", { json: { phone: OWNER_PHONE, pin: OWNER_PIN } });
  return authHeaders(login.body.token);
}

module.exports = {
  setup, registerAndLogin, authHeaders, sql, addTechnician, mockFirebaseClaims, captureSms,
  staffHeaders, OWNER_PHONE, OWNER_PIN,
};

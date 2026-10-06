/*
 * RasoiCare backend — database layer.
 *
 * Two modes, chosen by whether DB_HOST (or DATABASE_URL) is set:
 *
 * - Unset (default): SQLite, a single file on disk (rasoicare.db), via
 *   Node's built-in node:sqlite. Zero setup — the right choice for local
 *   development and the test suite.
 * - Set: MySQL, the database Hostinger's web/cloud hosting provides on the
 *   same server as the app. Connect to 127.0.0.1:3306 from the deployed
 *   app (not the srvNNNN.hstgr.io host, which is only for remote access).
 *
 * Routes never touch this distinction — they all call conn.get/all/run
 * with `?` placeholders and plain-object rows. The handful of statements
 * whose syntax genuinely differs between the two (upserts, insert-ignore,
 * column introspection) branch on conn.dialect.
 */

const path = require("node:path");
const crypto = require("node:crypto");
const { generatePasswordHash } = require("./passwords");

const DEFAULT_SQLITE_PATH = path.join(__dirname, "..", "rasoicare.db");

const config = {
  sqlitePath: process.env.SQLITE_PATH || DEFAULT_SQLITE_PATH,
  mysql: mysqlConfigFromEnv(),
};

function mysqlConfigFromEnv() {
  if (process.env.DATABASE_URL && /^mysql:\/\//.test(process.env.DATABASE_URL)) {
    return { uri: process.env.DATABASE_URL };
  }
  if (!process.env.DB_HOST) return null;
  return {
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  };
}

function isMysql() {
  return Boolean(config.mysql);
}

// ---------------------------------------------------------------- schema
// Type tokens, expanded per dialect: SQLite is happy with TEXT everywhere,
// but MySQL needs a bounded VARCHAR for anything that's a key or carries a
// DEFAULT, and LONGTEXT for the base64 job photos (up to ~12MB each).
const TYPES = {
  sqlite: { ID: "TEXT", S: "TEXT", T: "TEXT", L: "TEXT", I: "INTEGER", B: "INTEGER", R: "REAL" },
  mysql: { ID: "VARCHAR(64)", S: "VARCHAR(255)", T: "TEXT", L: "LONGTEXT", I: "INT", B: "BIGINT", R: "DOUBLE" },
};

// utf8mb4_bin keeps comparisons byte-exact, matching SQLite — Firebase UIDs
// and ids are case-sensitive, and MySQL's default case-insensitive
// collation would otherwise let two different UIDs collide.
const MYSQL_TABLE_SUFFIX = " ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin";

const TABLES = [
  ["technicians", `
    id                       {ID} PRIMARY KEY,
    name                     {S} NOT NULL,
    category                 {S} NOT NULL,
    area                     {S} NOT NULL DEFAULT '',
    verified                 {I} NOT NULL DEFAULT 0,
    online                   {I} NOT NULL DEFAULT 1,
    rating                   {R} NOT NULL DEFAULT 5.0,
    rating_count             {I} NOT NULL DEFAULT 0,
    jobs_completed           {I} NOT NULL DEFAULT 0,
    photo_url                {T},
    experience_years         {I},
    id_document_url          {T},
    bank_account_name        {S},
    bank_account_number      {S},
    bank_ifsc                {S},
    pan_number               {S},
    application_submitted    {I} NOT NULL DEFAULT 0,
    email                    {S},
    firebase_uid             {S} UNIQUE,
    aadhar_number            {S},
    date_of_birth            {S},
    gst_number               {S},
    emergency_contact_name   {S},
    emergency_contact_phone  {S},
    aadhar_document_url      {T},
    pan_document_url         {T},
    address                  {T},
    upi_id                   {S},
    categories_json          {T},
    aadhar_document_back_url {T},
    bank_passbook_url        {T},
    partner_code             {S} UNIQUE,
    employment_type          {S} NOT NULL DEFAULT 'outsourced'`],
  ["bookings", `
    id               {ID} PRIMARY KEY,
    category         {S} NOT NULL,
    service          {S} NOT NULL,
    price            {B} NOT NULL,
    technician_id    {ID} REFERENCES technicians(id),
    customer_name    {S} NOT NULL DEFAULT 'Amit Sharma',
    status           {S} NOT NULL DEFAULT 'Requested',
    bachat_slot      {S},
    service_rating   {I},
    tech_rating      {I},
    area             {S},
    created_at       {S} NOT NULL,
    updated_at       {S} NOT NULL,
    user_id          {ID},
    service_id       {ID},
    total_amount     {B},
    lat              {R},
    lng              {R},
    in_progress_at   {S},
    suction_before   {R},
    suction_after    {R},
    time_on_site_min {I},
    cancelled_at     {S},
    cancellation_fee {I},
    directions       {T},
    notes            {T},
    issues_json      {T},
    payment_method   {S},
    start_code       {S},
    before_photo_b64 {L},
    after_photo_b64  {L},
    signature_b64    {L},
    scheduled_at     {S},
    address_line     {T},
    brand            {S},
    model_number     {S},
    city             {S}`],
  ["technician_ledger", `
    id            {ID} PRIMARY KEY,
    technician_id {ID} NOT NULL REFERENCES technicians(id),
    booking_id    {ID} REFERENCES bookings(id),
    kind          {S} NOT NULL,
    amount_paise  {B} NOT NULL,
    reason        {T} NOT NULL,
    created_at    {S} NOT NULL`],
  ["booking_parts", `
    id          {ID} PRIMARY KEY,
    booking_id  {ID} NOT NULL REFERENCES bookings(id),
    name        {S} NOT NULL,
    sku         {S},
    qty         {I} NOT NULL DEFAULT 1,
    price_paise {B} NOT NULL,
    status      {S} NOT NULL DEFAULT 'pending',
    created_at  {S} NOT NULL,
    decided_at  {S}`],
  // A real record of the technician swapping this booking's service for a
  // different one in the same catalog category. old/new price are whole
  // rupees, matching bookings.price/total_amount's own convention.
  ["booking_service_changes", `
    id          {ID} PRIMARY KEY,
    booking_id  {ID} NOT NULL REFERENCES bookings(id),
    old_service {S} NOT NULL,
    new_service {S} NOT NULL,
    old_price   {B} NOT NULL,
    new_price   {B} NOT NULL,
    created_at  {S} NOT NULL`],
  ["complaints", `
    id         {ID} PRIMARY KEY,
    booking_id {ID} NOT NULL REFERENCES bookings(id),
    text       {T} NOT NULL,
    status     {S} NOT NULL DEFAULT 'New',
    response   {T},
    created_at {S} NOT NULL`],
  ["counters", `
    name  {ID} PRIMARY KEY,
    value {B} NOT NULL`],
  ["staff", `
    id           {ID} PRIMARY KEY,
    name         {S} NOT NULL,
    phone        {S} UNIQUE NOT NULL,
    pin_hash     {S} NOT NULL,
    role         {S} NOT NULL DEFAULT 'staff',
    active       {I} NOT NULL DEFAULT 1,
    created_at   {S} NOT NULL,
    email        {S},
    firebase_uid {S} UNIQUE`],
  ["inventory", `
    id            {ID} PRIMARY KEY,
    name          {S} NOT NULL,
    sku           {S} NOT NULL,
    category      {S} NOT NULL,
    quantity      {I} NOT NULL DEFAULT 0,
    reorder_level {I} NOT NULL DEFAULT 10,
    updated_at    {S} NOT NULL`],
  ["users", `
    id            {ID} PRIMARY KEY,
    email         {S} UNIQUE NOT NULL,
    password_hash {S} NOT NULL,
    name          {S} NOT NULL,
    phone         {S},
    created_at    {S} NOT NULL,
    firebase_uid  {S} UNIQUE,
    coins_balance {B} NOT NULL DEFAULT 0`],
  ["appliances", `
    id         {ID} PRIMARY KEY,
    name       {S} NOT NULL,
    category   {S} NOT NULL,
    mono       {S} NOT NULL,
    created_at {S} NOT NULL`],
  ["services", `
    id           {ID} PRIMARY KEY,
    appliance_id {ID} NOT NULL REFERENCES appliances(id),
    category     {S} NOT NULL,
    name         {S} NOT NULL,
    price        {B} NOT NULL,
    quick_fix    {I} NOT NULL DEFAULT 0,
    created_at   {S} NOT NULL`],
  ["appliance_health", `
    id           {ID} PRIMARY KEY,
    user_id      {ID} NOT NULL REFERENCES users(id),
    appliance_id {ID} NOT NULL REFERENCES appliances(id),
    metric_name  {S} NOT NULL,
    value_pct    {I} NOT NULL,
    status_label {S} NOT NULL,
    updated_at   {S} NOT NULL,
    UNIQUE(user_id, appliance_id)`],
  ["shop_orders", `
    id          {ID} PRIMARY KEY,
    user_id     {ID} NOT NULL REFERENCES users(id),
    items_json  {T} NOT NULL,
    total_paise {B} NOT NULL,
    status      {S} NOT NULL DEFAULT 'Placed',
    created_at  {S} NOT NULL`],
  // Standalone Home Services app, keyed by the same authenticated user id
  // as RasoiCare's own bookings — it reuses the RasoiCare login.
  ["hs_bookings", `
    id           {ID} PRIMARY KEY,
    user_id      {ID} NOT NULL REFERENCES users(id),
    service_id   {S} NOT NULL,
    service_name {S} NOT NULL,
    price        {B} NOT NULL,
    date         {S} NOT NULL,
    status       {S} NOT NULL DEFAULT 'Requested',
    created_at   {S} NOT NULL,
    updated_at   {S} NOT NULL`],
  ["hs_wallet", `
    user_id {ID} PRIMARY KEY REFERENCES users(id),
    points  {B} NOT NULL DEFAULT 100`],
  ["hs_wallet_tx", `
    id         {ID} PRIMARY KEY,
    user_id    {ID} NOT NULL REFERENCES users(id),
    label      {S} NOT NULL,
    amount     {B} NOT NULL,
    created_at {S} NOT NULL`],
  ["hs_profile", `
    user_id {ID} PRIMARY KEY REFERENCES users(id),
    name    {S} NOT NULL DEFAULT '',
    plan    {S}`],
];

function expandTypes(body, dialect) {
  return body.replace(/\{(ID|S|T|L|I|B|R)\}/g, (_, t) => TYPES[dialect][t]);
}

/** Splits a table body into its column definitions (skipping table-level
 * constraints) so ensureColumns can add any that an older database file
 * is missing. */
function columnDefs(body, dialect) {
  return expandTypes(body, dialect)
    .split(",\n")
    .map((s) => s.trim())
    .filter((s) => s && !/^UNIQUE\(/.test(s))
    .map((s) => {
      const name = s.split(/\s+/)[0];
      // ALTER TABLE ADD COLUMN can't carry PRIMARY KEY/UNIQUE inline on
      // SQLite; a column old enough to be missing never had them anyway.
      const def = s.replace(/\s+PRIMARY KEY/, "").replace(/\s+UNIQUE/, "");
      return { name, def };
    });
}

function schemaStatements(dialect) {
  return TABLES.map(([name, body]) => {
    const sql = `CREATE TABLE IF NOT EXISTS ${name} (${expandTypes(body, dialect)}\n)`;
    return dialect === "mysql" ? sql + MYSQL_TABLE_SUFFIX : sql;
  });
}

// ---------------------------------------------------------------- seed data
const APPLIANCES_SEED = [
  ["app_chimney", "Chimney", "RasoiAir", "CH"],
  ["app_hob", "Hob", "RasoiSpark", "HB"],
  ["app_cooktop", "Cooktop", "RasoiSpark", "CT"],
  ["app_microwave", "Built-in Microwave", "RasoiBuilt", "MW"],
  ["app_dishwasher", "Dishwasher", "RasoiWash", "DW"],
  ["app_fridge", "Refrigerator", "RasoiChill", "RF"],
  ["app_otg", "OTG", "RasoiBuilt", "OT"],
  ["app_purifier", "Water Purifier", "RasoiPure", "WP"],
];

// [id, appliance_id, category, name, price, quick_fix]
const SERVICES_SEED = [
  ["svc_chimney_deep_cleaning", "app_chimney", "RasoiAir", "Deep Cleaning", 1600, 0],
  ["svc_chimney_low_suction", "app_chimney", "RasoiAir", "Low Suction", 399, 1],
  ["svc_chimney_noisy_motor", "app_chimney", "RasoiAir", "Noisy Motor", 499, 1],
  ["svc_hob_ignition_fix", "app_hob", "RasoiSpark", "Ignition Fix", 399, 1],
  ["svc_hob_burner_cleaning", "app_hob", "RasoiSpark", "Burner Cleaning", 299, 1],
  ["svc_cooktop_ignition_fix", "app_cooktop", "RasoiSpark", "Ignition Fix", 399, 1],
  ["svc_cooktop_autoshutoff", "app_cooktop", "RasoiSpark", "Auto-shutoff Issue", 449, 1],
  ["svc_microwave_not_heating", "app_microwave", "RasoiBuilt", "Not Heating", 599, 0],
  ["svc_microwave_door_repair", "app_microwave", "RasoiBuilt", "Door / Hinge Repair", 399, 1],
  ["svc_microwave_general", "app_microwave", "RasoiBuilt", "General Service", 349, 1],
  ["svc_dishwasher_not_draining", "app_dishwasher", "RasoiWash", "Not Draining", 549, 0],
  ["svc_dishwasher_general", "app_dishwasher", "RasoiWash", "General Service", 399, 1],
  ["svc_fridge_not_cooling", "app_fridge", "RasoiChill", "Not Cooling", 699, 0],
  ["svc_fridge_gas_refill", "app_fridge", "RasoiChill", "Gas Refill", 1200, 0],
  ["svc_fridge_general", "app_fridge", "RasoiChill", "General Service", 399, 1],
  ["svc_otg_not_heating", "app_otg", "RasoiBuilt", "Not Heating", 399, 1],
  ["svc_otg_general", "app_otg", "RasoiBuilt", "General Service", 299, 1],
  ["svc_purifier_filter_change", "app_purifier", "RasoiPure", "Filter Change", 499, 1],
  ["svc_purifier_not_purifying", "app_purifier", "RasoiPure", "Not Purifying", 399, 1],
  ["svc_purifier_annual_service", "app_purifier", "RasoiPure", "Annual Service", 349, 1],
];

// The deep-clean / repair / install / uninstall services the Customer
// app's Service tab shows. Inserted idempotently on every boot (see
// addCustomerCatalogServices) so they reach databases seeded long ago.
const CUSTOMER_CATALOG_SEED = [
  ["svc_chimney_deep_clean_full", "app_chimney", "RasoiAir", "Deep clean — filters, motor, duct", 1599, 0],
  ["svc_chimney_filter_clean", "app_chimney", "RasoiAir", "Normal filter clean", 899, 0],
  ["svc_chimney_repair_visit", "app_chimney", "RasoiAir", "Repair visit and diagnosis", 399, 1],
  ["svc_chimney_install", "app_chimney", "RasoiAir", "Installation with duct work", 1699, 0],
  ["svc_chimney_uninstall", "app_chimney", "RasoiAir", "Uninstall and shift", 599, 0],
  ["svc_hob_deep_clean_full", "app_hob", "RasoiSpark", "Deep clean — burners, valves, igniters", 799, 0],
  ["svc_hob_repair_visit", "app_hob", "RasoiSpark", "Repair visit and diagnosis", 399, 1],
  ["svc_hob_install", "app_hob", "RasoiSpark", "Installation with gas line check", 699, 0],
  ["svc_hob_uninstall", "app_hob", "RasoiSpark", "Uninstall and cap the line", 399, 0],
  ["svc_cooktop_deep_clean_full", "app_cooktop", "RasoiSpark", "Deep clean and calibration", 499, 0],
  ["svc_cooktop_repair_visit", "app_cooktop", "RasoiSpark", "Repair visit and diagnosis", 399, 1],
  ["svc_cooktop_install", "app_cooktop", "RasoiSpark", "Installation and panel fitting", 399, 0],
  ["svc_cooktop_uninstall", "app_cooktop", "RasoiSpark", "Uninstall and pack for a move", 299, 0],
  ["svc_dishwasher_deep_clean_full", "app_dishwasher", "RasoiWash", "Deep clean — filter, spray arms, seals", 1199, 0],
  ["svc_dishwasher_repair_visit", "app_dishwasher", "RasoiWash", "Repair visit and diagnosis", 599, 1],
  ["svc_dishwasher_install", "app_dishwasher", "RasoiWash", "Installation and plumbing connection", 1499, 0],
  ["svc_dishwasher_uninstall", "app_dishwasher", "RasoiWash", "Uninstall and cap the lines", 599, 0],
  ["svc_microwave_deep_clean_full", "app_microwave", "RasoiBuilt", "Deep clean and safety check", 549, 0],
  ["svc_microwave_repair_visit", "app_microwave", "RasoiBuilt", "Repair visit and diagnosis", 399, 1],
  ["svc_microwave_install", "app_microwave", "RasoiBuilt", "Built-in installation and trim kit", 999, 0],
  ["svc_microwave_uninstall", "app_microwave", "RasoiBuilt", "Uninstall and cap the housing", 599, 0],
  ["svc_otg_deep_clean_full", "app_otg", "RasoiBuilt", "Deep clean and element check", 549, 0],
  ["svc_otg_repair_visit", "app_otg", "RasoiBuilt", "Repair visit and diagnosis", 399, 1],
  ["svc_otg_install", "app_otg", "RasoiBuilt", "Installation and test bake", 999, 0],
  ["svc_otg_uninstall", "app_otg", "RasoiBuilt", "Uninstall and pack for a move", 599, 0],
];

// The demo owner/staff logins seedStaff creates on first boot. Set
// STAFF_SEED_OWNER_PIN/STAFF_SEED_STAFF_PIN before the first boot of any
// real deployment — the phone numbers and default PIN are public (they're
// right here in source control). seedStaff never touches an existing row,
// so changing them later has no effect on an already-seeded database.
function staffSeed() {
  const ownerPin = process.env.STAFF_SEED_OWNER_PIN || "1234";
  const staffPin = process.env.STAFF_SEED_STAFF_PIN || "1234";
  return [
    ["staff_owner", "Priya Deshmukh", "9822000001", ownerPin, "owner"],
    ["staff_ops", "Rahul Jadhav", "9822000002", staffPin, "staff"],
  ];
}

// ---------------------------------------------------------------- connections
function normalizeParams(params) {
  return params.map((p) => {
    if (p === undefined) return null;
    if (p === true) return 1;
    if (p === false) return 0;
    return p;
  });
}

let sqliteDb = null;
let sqliteDbPath = null;

function openSqlite() {
  if (sqliteDb && sqliteDbPath === config.sqlitePath) return sqliteDb;
  if (sqliteDb) sqliteDb.close();
  const { DatabaseSync } = require("node:sqlite");
  sqliteDb = new DatabaseSync(config.sqlitePath);
  sqliteDb.exec("PRAGMA foreign_keys = ON");
  sqliteDbPath = config.sqlitePath;
  return sqliteDb;
}

/** SQLite runs in autocommit mode on one shared connection — node:sqlite
 * is synchronous, and that's plenty for local development and tests. */
class SqliteConn {
  constructor(db) {
    this.db = db;
    this.dialect = "sqlite";
  }

  async get(sql, params = []) {
    const row = this.db.prepare(sql).get(...normalizeParams(params));
    return row ? { ...row } : null;
  }

  async all(sql, params = []) {
    return this.db.prepare(sql).all(...normalizeParams(params)).map((r) => ({ ...r }));
  }

  async run(sql, params = []) {
    const result = this.db.prepare(sql).run(...normalizeParams(params));
    return { changes: Number(result.changes) };
  }

  async commit() {}

  close() {}
}

let mysqlPool = null;

function getMysqlPool() {
  if (mysqlPool) return mysqlPool;
  const mysql = require("mysql2/promise");
  const base = {
    // SUM()/AVG() come back as DECIMAL — without this mysql2 hands them
    // over as strings, and every revenue total would turn into "0" + "1600".
    decimalNumbers: true,
    connectionLimit: Number(process.env.DB_POOL_SIZE || 5),
    charset: "utf8mb4",
    timezone: "Z",
    // DB_SSL=true encrypts the connection — worth it when the database is
    // reached over the internet (e.g. Render -> Hostinger remote MySQL).
    ...(process.env.DB_SSL === "true" ? { ssl: { rejectUnauthorized: false } } : {}),
  };
  mysqlPool = config.mysql.uri
    ? mysql.createPool({ uri: config.mysql.uri, ...base })
    : mysql.createPool({ ...config.mysql, ...base });
  return mysqlPool;
}

/** One pooled MySQL connection inside an explicit transaction — the same
 * unit-of-work shape the routes were written against: nothing a request
 * writes is visible to anyone else until it calls commit(). */
class MysqlConn {
  constructor(conn) {
    this.conn = conn;
    this.dialect = "mysql";
    this.inTransaction = false;
  }

  async begin() {
    await this.conn.beginTransaction();
    this.inTransaction = true;
  }

  async get(sql, params = []) {
    const [rows] = await this.conn.query(sql, normalizeParams(params));
    return rows.length ? { ...rows[0] } : null;
  }

  async all(sql, params = []) {
    const [rows] = await this.conn.query(sql, normalizeParams(params));
    return rows.map((r) => ({ ...r }));
  }

  async run(sql, params = []) {
    const [result] = await this.conn.query(sql, normalizeParams(params));
    return { changes: result.affectedRows };
  }

  async commit() {
    await this.conn.commit();
    await this.begin();
  }

  close() {
    const conn = this.conn;
    if (!conn) return;
    this.conn = null;
    // Anything not explicitly committed is discarded, same as closing a
    // sqlite3/psycopg2 connection without commit().
    conn.rollback().catch(() => {}).finally(() => conn.release());
  }
}

async function getDb() {
  if (isMysql()) {
    const conn = new MysqlConn(await getMysqlPool().getConnection());
    await conn.begin();
    return conn;
  }
  return new SqliteConn(openSqlite());
}

async function tableColumns(conn, table) {
  if (conn.dialect === "mysql") {
    const rows = await conn.all(
      "SELECT COLUMN_NAME AS name FROM information_schema.COLUMNS "
        + "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?",
      [table],
    );
    return new Set(rows.map((r) => r.name));
  }
  const rows = await conn.all(`PRAGMA table_info(${table})`);
  return new Set(rows.map((r) => r.name));
}

// ---------------------------------------------------------------- helpers
function now() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

/** IDs for entities outside the counter-based sequence (users, staff,
 * ledger rows, ...). */
function newUuidId(prefix) {
  return `${prefix}-${crypto.randomUUID().replace(/-/g, "").slice(0, 10)}`;
}

async function nextId(conn, counterName, prefix) {
  // FOR UPDATE locks the counter row for the rest of this transaction on
  // MySQL, so two concurrent bookings can't both read the same value.
  const lock = conn.dialect === "mysql" ? " FOR UPDATE" : "";
  const row = await conn.get(`SELECT value FROM counters WHERE name = ?${lock}`, [counterName]);
  let value;
  if (!row) {
    await conn.run("INSERT INTO counters (name, value) VALUES (?, 1)", [counterName]);
    value = 1;
  } else {
    value = Number(row.value);
  }
  await conn.run("UPDATE counters SET value = ? WHERE name = ?", [value + 1, counterName]);
  return `${prefix}-${value}`;
}

// ---------------------------------------------------------------- init
async function ensureColumns(conn) {
  for (const [table, body] of TABLES) {
    const existing = await tableColumns(conn, table);
    for (const { name, def } of columnDefs(body, conn.dialect)) {
      if (!existing.has(name)) {
        await conn.run(`ALTER TABLE ${table} ADD COLUMN ${def}`);
      }
    }
  }
}

async function seedCatalog(conn) {
  const row = await conn.get("SELECT COUNT(*) AS n FROM appliances");
  if (Number(row.n) > 0) return;
  const ts = now();
  for (const [id, name, category, mono] of APPLIANCES_SEED) {
    await conn.run(
      "INSERT INTO appliances (id, name, category, mono, created_at) VALUES (?,?,?,?,?)",
      [id, name, category, mono, ts],
    );
  }
  for (const [id, applianceId, category, name, price, quickFix] of SERVICES_SEED) {
    await conn.run(
      "INSERT INTO services (id, appliance_id, category, name, price, quick_fix, created_at) "
        + "VALUES (?,?,?,?,?,?,?)",
      [id, applianceId, category, name, price, quickFix, ts],
    );
  }
}

async function addCustomerCatalogServices(conn) {
  const ts = now();
  const insert = conn.dialect === "mysql" ? "INSERT IGNORE" : "INSERT OR IGNORE";
  for (const [id, applianceId, category, name, price, quickFix] of CUSTOMER_CATALOG_SEED) {
    await conn.run(
      `${insert} INTO services (id, appliance_id, category, name, price, quick_fix, created_at) `
        + "VALUES (?,?,?,?,?,?,?)",
      [id, applianceId, category, name, price, quickFix, ts],
    );
  }
}

async function seedStaff(conn) {
  const row = await conn.get("SELECT COUNT(*) AS n FROM staff");
  if (Number(row.n) > 0) return;
  const seed = staffSeed();
  if (seed.some(([, , , pin]) => pin === "1234")) {
    console.warn(
      "WARNING: seeding the owner/staff accounts with the default PIN '1234' — this and "
        + "the seeded phone numbers are public (they're in source control). Set "
        + "STAFF_SEED_OWNER_PIN/STAFF_SEED_STAFF_PIN to real secrets before the first boot "
        + "of any deployment reachable outside a trusted network.",
    );
  }
  const ts = now();
  for (const [id, name, phone, pin, role] of seed) {
    await conn.run(
      "INSERT INTO staff (id, name, phone, pin_hash, role, active, created_at) VALUES (?,?,?,?,?,1,?)",
      [id, name, phone, generatePasswordHash(pin), role, ts],
    );
  }
}

async function initDb() {
  const conn = await getDb();
  try {
    for (const statement of schemaStatements(conn.dialect)) {
      await conn.run(statement);
    }
    await ensureColumns(conn);
    await seedCatalog(conn);
    await addCustomerCatalogServices(conn);
    await seedStaff(conn);
    await conn.commit();
  } finally {
    conn.close();
  }
}

/** Points the SQLite backend at a different file — used by the test suite
 * to give every test its own throwaway database. */
function useSqliteFile(filePath) {
  config.sqlitePath = filePath;
  config.mysql = null;
}

async function closeAll() {
  if (sqliteDb) {
    sqliteDb.close();
    sqliteDb = null;
    sqliteDbPath = null;
  }
  if (mysqlPool) {
    await mysqlPool.end();
    mysqlPool = null;
  }
}

module.exports = {
  getDb,
  initDb,
  nextId,
  now,
  newUuidId,
  isMysql,
  useSqliteFile,
  closeAll,
  schemaStatements,
  TABLES,
};

/*
 * One-time copy of every row from the old Postgres database (the
 * DATABASE_URL the Render deployment used) into the Hostinger MySQL
 * database this backend now runs on.
 *
 *   SOURCE_DATABASE_URL=postgresql://user:pass@host/db \
 *   DB_HOST=srvNNNN.hstgr.io DB_USER=... DB_PASSWORD=... DB_NAME=... \
 *   npm run migrate:from-postgres
 *
 * Run it from your own machine: Hostinger's MySQL only accepts outside
 * connections after you allow your IP under hPanel -> Databases -> Remote
 * MySQL, and then the host is the srvNNNN.hstgr.io name shown there (the
 * deployed app itself uses 127.0.0.1).
 *
 * Creates the schema first (same as the server's boot), then copies table
 * by table. Source rows win: a row with the same primary key — e.g. the
 * seeded catalog and staff — is updated in place to the source's version.
 * Safe to re-run.
 */

const db = require("../db");

const BATCH_SIZE = 200;

async function main() {
  const sourceUrl = process.env.SOURCE_DATABASE_URL;
  if (!sourceUrl) throw new Error("Set SOURCE_DATABASE_URL to the old Postgres connection string.");
  if (!db.isMysql()) throw new Error("Set DB_HOST/DB_USER/DB_PASSWORD/DB_NAME for the target MySQL database.");

  let pg;
  try {
    pg = require("pg");
  } catch {
    throw new Error("The 'pg' package isn't installed — run `npm install pg` first.");
  }

  await db.initDb();
  const source = new pg.Client({
    connectionString: sourceUrl,
    ssl: /sslmode=disable/.test(sourceUrl) ? false : { rejectUnauthorized: false },
  });
  await source.connect();
  const target = await db.getDb();
  try {
    // Tables are copied one at a time, so a child row can briefly arrive
    // before the parent it references.
    await target.run("SET FOREIGN_KEY_CHECKS = 0");
    for (const [table] of db.TABLES) {
      const exists = await source.query("SELECT to_regclass($1) AS t", [table]);
      if (!exists.rows[0].t) {
        console.log(`${table}: not in source, skipped`);
        continue;
      }
      const targetCols = new Set(
        (await target.all(
          "SELECT COLUMN_NAME AS name FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?",
          [table],
        )).map((r) => r.name),
      );
      const { rows } = await source.query(`SELECT * FROM ${table}`);
      if (!rows.length) {
        console.log(`${table}: 0 rows`);
        continue;
      }
      const cols = Object.keys(rows[0]).filter((c) => targetCols.has(c));
      for (let i = 0; i < rows.length; i += BATCH_SIZE) {
        const batch = rows.slice(i, i + BATCH_SIZE);
        const placeholders = batch.map(() => `(${cols.map(() => "?").join(",")})`).join(",");
        await target.run(
          `INSERT INTO ${table} (${cols.join(",")}) VALUES ${placeholders} `
            + `ON DUPLICATE KEY UPDATE ${cols.map((c) => `${c} = VALUES(${c})`).join(", ")}`,
          batch.flatMap((r) => cols.map((c) => r[c])),
        );
      }
      await target.commit();
      console.log(`${table}: ${rows.length} rows`);
    }
    await target.run("SET FOREIGN_KEY_CHECKS = 1");
  } finally {
    target.close();
    await source.end();
    await db.closeAll();
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});

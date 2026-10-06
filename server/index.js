/*
 * Entry point: creates/migrates the schema, then starts listening.
 * Hostinger (and most Node hosts) set PORT; locally it defaults to 8420.
 */

const { app } = require("./app");
const { initDb, isMysql } = require("./db");

const port = Number(process.env.PORT || 8420);

initDb()
  .then(() => {
    app.listen(port, () => {
      console.log(`RasoiCare backend running on port ${port} (${isMysql() ? "MySQL" : "SQLite"})`);
    });
  })
  .catch((err) => {
    console.error("Failed to initialise the database:", err);
    process.exit(1);
  });

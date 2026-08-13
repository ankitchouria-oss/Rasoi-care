// Base URL for the shared Flask+SQLite backend (app.py/database.py at the
// repo root). Override at build/run time with
// `--dart-define=API_BASE_URL=http://10.0.2.2:5000` for a local backend, for
// example. The default points at the Render deploy documented in the repo's
// root README.md — it may not be live yet, and every caller in lib/data/api
// degrades gracefully (same spirit as the unconfigured-Firebase fallback in
// main.dart) if it isn't reachable.
abstract final class ApiConfig {
  static const baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'https://rasoicare-backend.onrender.com');
}

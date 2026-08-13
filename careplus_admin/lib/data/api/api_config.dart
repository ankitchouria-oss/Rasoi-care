// Base URL for the live Flask+SQLite backend (see repo root app.py /
// database.py). Override at build/run time with
// `--dart-define=API_BASE_URL=http://localhost:5000` when pointing at a
// local backend instead of the deployed one.

abstract final class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://rasoicare-backend.onrender.com',
  );
}

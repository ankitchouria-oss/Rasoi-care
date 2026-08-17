import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the last mobile number someone signed in with, purely so the
/// phone screen can prefill it next time instead of showing a blank (or,
/// as it used to, a hardcoded demo number unrelated to the actual account).
class RecentPhoneStore {
  static const _key = 'recent_phone_number';

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> save(String tenDigitPhone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, tenDigitPhone);
  }
}

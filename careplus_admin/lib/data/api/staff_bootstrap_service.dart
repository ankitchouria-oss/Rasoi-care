// Best-effort staff bootstrap against the live Flask+SQLite backend, called
// once right after a successful sign-in (any method) alongside
// [StaffProfileService.touchProfile] (Firestore). Never blocks getting into
// the app: if the backend isn't deployed yet, is unreachable, or the call
// otherwise fails, this is a silent no-op — sign-in has already completed.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import 'api_config.dart';

class StaffBootstrapService {
  StaffBootstrapService({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;

  /// Posts the *requested* role (only honoured by the backend for a
  /// brand-new staff row — see bootstrap_staff's docstring in app.py: the
  /// very first sign-in ever becomes owner regardless of what's requested,
  /// and a returning staff member's role never changes here) and returns
  /// the real, backend-assigned role from the response — never the
  /// requested one. Returns null on any failure (backend not deployed yet,
  /// unreachable, timed out); the caller keeps showing the last-known role
  /// in that case rather than clearing it.
  Future<AdminRole?> bootstrap({required AdminRole role}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final token = await user.getIdToken();
      if (token == null) return null;
      final res = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/staff/bootstrap'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'name':
                  user.displayName ?? user.email ?? user.phoneNumber ?? 'Staff',
              'role': role == AdminRole.owner ? 'owner' : 'staff',
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return json['role'] == 'owner' ? AdminRole.owner : AdminRole.staff;
    } catch (_) {
      // Best-effort — backend may not be deployed yet, or the request may
      // time out. Sign-in already completed; never block on this.
      return null;
    }
  }
}

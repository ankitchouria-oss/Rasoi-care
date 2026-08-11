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

  Future<void> bootstrap({required AdminRole role}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await user.getIdToken();
      if (token == null) return;
      await _client
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
    } catch (_) {
      // Best-effort — backend may not be deployed yet, or the request may
      // time out. Sign-in already completed; never block on this.
    }
  }
}

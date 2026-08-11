// Thin HTTP client for the shared Flask+SQLite backend. Every method here is
// best-effort: wrapped in try/catch with a timeout, so a network failure
// (backend not deployed yet, offline device, slow connection) never throws
// past this class — callers get null/[] back and fall back to whatever
// MockRepository already provides. Mirrors the same never-block-a-flow
// philosophy as UserProfileService's Firestore writes
// (lib/data/firebase/firestore_user_profile_service.dart).

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class BackendClient {
  static const _timeout = Duration(seconds: 8);

  Map<String, String> _headers(String idToken) => {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      };

  /// POST /api/me/bootstrap — called once right after Firebase sign-in so
  /// the backend has a matching `users` row. Fire-and-forget from the
  /// caller's side; failures are swallowed here too.
  Future<void> bootstrap({required String idToken, required String name}) async {
    try {
      await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/me/bootstrap'),
            headers: _headers(idToken),
            body: jsonEncode({'name': name}),
          )
          .timeout(_timeout);
    } catch (_) {
      // Best-effort — see file header.
    }
  }

  /// POST /api/bookings using the legacy category/service/price shape.
  /// Returns the decoded booking JSON on a 201, or null on any failure
  /// (network error, timeout, non-2xx response).
  Future<Map<String, dynamic>?> createBooking({
    required String idToken,
    required String category,
    required String service,
    required int price,
    String? area,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/bookings'),
            headers: _headers(idToken),
            body: jsonEncode({
              'category': category,
              'service': service,
              'price': price,
              if (area != null && area.isNotEmpty) 'area': area,
            }),
          )
          .timeout(_timeout);
      if (res.statusCode == 201) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {
      // Best-effort — see file header.
    }
    return null;
  }

  /// GET /api/bookings with the caller's Firebase ID token — the backend
  /// scopes the result to that user's own bookings. Returns an empty list
  /// on any failure.
  Future<List<Map<String, dynamic>>> fetchBookings({required String idToken}) async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/bookings'),
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          return decoded.whereType<Map<String, dynamic>>().toList();
        }
      }
    } catch (_) {
      // Best-effort — see file header.
    }
    return [];
  }
}

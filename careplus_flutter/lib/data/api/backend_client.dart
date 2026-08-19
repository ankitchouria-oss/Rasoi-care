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
  /// Returns the decoded booking JSON on a 201. On any failure, `booking`
  /// is null and `error` carries the reason: the backend's own message for
  /// an unsuccessful-but-reachable request (e.g. app.py's 503 "No
  /// technician is available for this service yet" once the demo
  /// technicians were removed), or a generic one for a real network
  /// failure (offline, timeout) — so the caller can show the customer what
  /// actually went wrong instead of always blaming their connection.
  Future<({Map<String, dynamic>? booking, String? error, bool unauthorized})> createBooking({
    required String idToken,
    required String category,
    required String service,
    required int price,
    String? area,
    double? lat,
    double? lng,
    String? directions,
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
              if (lat != null) 'lat': lat,
              if (lng != null) 'lng': lng,
              if (directions != null && directions.isNotEmpty) 'directions': directions,
            }),
          )
          .timeout(_timeout);
      final decoded = jsonDecode(res.body);
      if (res.statusCode == 201 && decoded is Map<String, dynamic>) {
        return (booking: decoded, error: null, unauthorized: false);
      }
      if (res.statusCode == 401) {
        // require_auth's own 401s use {"error": "Unauthorized", "message":
        // "<real reason>"} — "error" here is just a coarse category label,
        // not something worth showing a customer. This is almost always a
        // stale ID token, so `unauthorized: true` tells ApiRepository to
        // retry once with a forced token refresh before ever surfacing
        // this to the UI as a final failure.
        return (
          booking: null,
          error: 'Your session needs refreshing — please try again.',
          unauthorized: true,
        );
      }
      // Business-logic rejections (e.g. the 503 "no technician available")
      // put the full human-readable reason directly in "error".
      final message = decoded is Map<String, dynamic> ? decoded['error'] as String? : null;
      return (
        booking: null,
        error: message ?? 'The server rejected this booking (${res.statusCode}).',
        unauthorized: false,
      );
    } catch (_) {
      return (booking: null, error: null, unauthorized: false); // real network failure — see file header
    }
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

  /// PATCH /api/bookings/{id}/cancel — the backend computes and applies the
  /// real cancellation fee itself (based on how far the job had progressed;
  /// see app.py's CANCELLATION_FEE_BY_STATUS), so this call carries no fee
  /// the client could tamper with. Returns the updated booking JSON on a
  /// 200, or null on any failure (network error, forbidden, already past
  /// the point a booking can be cancelled).
  Future<Map<String, dynamic>?> cancelBooking({
    required String idToken,
    required String bookingId,
  }) async {
    try {
      final res = await http
          .patch(
            Uri.parse('${ApiConfig.baseUrl}/api/bookings/$bookingId/cancel'),
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {
      // Best-effort — see file header.
    }
    return null;
  }

  /// POST /api/bookings/{id}/rating — the real endpoint the RateScreen
  /// star rating submits to. Returns true on success; the caller decides
  /// what to tell the customer on failure rather than silently pretending
  /// it worked.
  Future<bool> rateBooking({
    required String idToken,
    required String bookingId,
    required int rating,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/bookings/$bookingId/rating'),
            headers: _headers(idToken),
            body: jsonEncode({'serviceRating': rating, 'techRating': rating}),
          )
          .timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

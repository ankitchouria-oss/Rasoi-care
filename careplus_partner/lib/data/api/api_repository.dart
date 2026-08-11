// Real-backend-backed [PartnerRepository].
//
// The interface stays 100% synchronous (see repository.dart's header
// comment), so this class keeps an in-memory cache of the last successful
// fetch and serves every synchronous getter off that cache. Network calls
// (`refreshBookings`, `refreshMe`, `advanceJob`, `setOnDuty`) are async and
// meant to be awaited by the UI layer, which then forces a rebuild so the
// screens re-read the now-updated cache — see
// lib/state/providers.dart's `jobsFeedTickProvider`.
//
// Anything the backend has no concept of (checklist items, parts,
// directions, invoice line detail, per-job distance/time-window) is served
// unchanged from [MockPartnerRepository] — this never fabricates server
// data that doesn't exist.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models.dart';
import '../repository.dart';
import 'api_config.dart';
import 'booking_dto.dart';

const _timeout = Duration(seconds: 8);

class ApiRepository implements PartnerRepository {
  ApiRepository({MockPartnerRepository? mock}) : _mock = mock ?? MockPartnerRepository();

  final MockPartnerRepository _mock;

  List<BookingDto> _bookings = const [];

  /// True once `/technician/bookings` has been fetched successfully at
  /// least once. Until then — backend not deployed, no network, still
  /// loading — [incomingRequest] and [routeToday] serve Mock-shaped data so
  /// the feed is never just blank; after a real fetch, an empty result is
  /// trusted as genuinely empty (no more falling back to Mock).
  bool _bookingsFetched = false;

  /// Null until the first successful `/technician/online` or
  /// `/technician/me` response — falls back to the mock's onDuty until then.
  bool? _online;

  // ---------------------------------------------------------------- auth

  Future<String?> _idToken() async {
    if (Firebase.apps.isEmpty) return null; // mock/unconfigured — no token to send
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------- fetching

  /// Refreshes this technician's assigned bookings from the real backend.
  /// Silently keeps the previous cache (or the empty list) on any failure —
  /// backend not deployed yet, timeout, network error, unauthenticated.
  Future<void> refreshBookings() async {
    try {
      final token = await _idToken();
      if (token == null) return;
      final res = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/technician/bookings'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      if (data is! List) return;
      _bookings = data
          .whereType<Map<String, dynamic>>()
          .map(BookingDto.fromJson)
          .toList(growable: false);
      _bookingsFetched = true;
    } catch (_) {
      // Backend unreachable or not deployed yet — keep whatever we had.
    }
  }

  /// Refreshes on-duty state from `/api/technician/me`. Best-effort, same
  /// failure handling as [refreshBookings].
  Future<void> refreshMe() async {
    try {
      final token = await _idToken();
      if (token == null) return;
      final res = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/technician/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) return;
      if (data['online'] is bool) _online = data['online'] as bool;
    } catch (_) {
      // Ignored — techStats() falls back to the mock's onDuty.
    }
  }

  /// Fetches bookings and on-duty state together — call once after sign-in
  /// / whenever the job feed wants a fresh look at the server.
  Future<void> refreshAll() => Future.wait([refreshBookings(), refreshMe()]);

  // -------------------------------------------------------------- actions

  /// Moves [jobId] to its next status via the real backend (the server
  /// decides the target — this can't request an arbitrary one). Returns
  /// true if the call succeeded, in which case the local cache has already
  /// been advanced to match so the caller can rebuild immediately without
  /// waiting on another round trip.
  Future<bool> advanceJob(String jobId) async {
    try {
      final res = await http
          .patch(Uri.parse('${ApiConfig.baseUrl}/api/bookings/$jobId/advance'))
          .timeout(_timeout);
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic> && data['status'] is String) {
        _replaceBookingStatus(jobId, data['status'] as String);
      } else {
        _advanceBookingStatusLocally(jobId);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sets on-duty state via `/api/technician/online`. Returns true on
  /// success (and updates the local cache to match); false on any failure,
  /// in which case the UI should not optimistically flip the toggle.
  Future<bool> setOnDuty(bool value) async {
    try {
      final token = await _idToken();
      if (token == null) return false;
      final res = await http
          .patch(
            Uri.parse('${ApiConfig.baseUrl}/api/technician/online'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'online': value}),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return false;
      _online = value;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _replaceBookingStatus(String jobId, String status) {
    final i = _bookings.indexWhere((b) => b.id == jobId);
    if (i == -1) return;
    final next = [..._bookings];
    next[i] = next[i].copyWith(status: status);
    _bookings = next;
  }

  void _advanceBookingStatusLocally(String jobId) {
    final i = _bookings.indexWhere((b) => b.id == jobId);
    if (i == -1) return;
    final order = kBookingStatusOrder.indexOf(_bookings[i].status);
    if (order == -1 || order >= kBookingStatusOrder.length - 1) return;
    _replaceBookingStatus(jobId, kBookingStatusOrder[order + 1]);
  }

  // ------------------------------------------------------- PartnerRepository

  @override
  TechStats techStats() {
    final mock = _mock.techStats();
    final online = _online;
    return online == null
        ? mock
        : TechStats(
            earningsTodayPaise: mock.earningsTodayPaise,
            jobsDone: mock.jobsDone,
            jobsTotal: mock.jobsTotal,
            tipsPaise: mock.tipsPaise,
            rating: mock.rating,
            firstTimeFixPct: mock.firstTimeFixPct,
            onDuty: online,
          );
  }

  @override
  JobRequest? incomingRequest() {
    if (!_bookingsFetched) return _mock.incomingRequest();
    final requested = _bookings.where((b) => b.status == 'Requested');
    if (requested.isEmpty) return null;
    final b = requested.first;
    return JobRequest(
      jobId: b.id,
      serviceTitle: b.service,
      distanceKm: 2.0, // no real distance data from the backend yet
      timeWindow: _timeWindow(b.createdAt),
      payoutPaise: b.totalAmountPaise,
      note: '',
    );
  }

  @override
  List<RouteStop> routeToday() {
    if (!_bookingsFetched) return _mock.routeToday();
    return _bookings
        .where((b) => b.status == 'Accepted' || b.status == 'On the way' || b.status == 'In Progress')
        .map((b) => RouteStop(
              jobId: b.id,
              time: _clockTime(b.createdAt),
              title: b.service,
              customerName: b.customerName,
              meta: b.area ?? '',
              status: b.status == 'Accepted' ? StopStatus.next : StopStatus.inProgress,
            ))
        .toList(growable: false);
  }

  @override
  JobDetail jobDetail(String jobId) {
    final match = _bookings.where((b) => b.id == jobId);
    final base = _mock.jobDetail(jobId);
    if (match.isEmpty) return base;
    final b = match.first;
    return JobDetail(
      jobId: base.jobId,
      customerName: b.customerName,
      customerInitials: _initials(b.customerName),
      addressLine: (b.area?.trim().isNotEmpty ?? false) ? b.area! : base.addressLine,
      directions: base.directions,
      reportedTags: base.reportedTags,
      reportedQuote: base.reportedQuote,
      checklist: base.checklist,
      parts: base.parts,
    );
  }

  @override
  List<InvoiceLine> closeInvoice(String jobId) => _mock.closeInvoice(jobId);

  /// The live status string for [jobId] if it's a known real booking from
  /// the last successful `/technician/bookings` fetch, else null (a mock
  /// job, or a real job not yet fetched). Used by the job screen to decide
  /// which status-advance action to offer next.
  String? statusOf(String jobId) {
    final match = _bookings.where((b) => b.id == jobId);
    return match.isEmpty ? null : match.first.status;
  }

  // ------------------------------------------------------------- helpers

  String _clockTime(DateTime? dt) {
    if (dt == null) return 'Today';
    try {
      return DateFormat('h:mm a').format(dt.toLocal());
    } catch (_) {
      return 'Today';
    }
  }

  String _timeWindow(DateTime? dt) {
    if (dt == null) return 'Today';
    try {
      final local = dt.toLocal();
      final start = DateFormat('h:mm a').format(local);
      final end = DateFormat('h:mm a').format(local.add(const Duration(hours: 1)));
      return '$start–$end';
    } catch (_) {
      return 'Today';
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

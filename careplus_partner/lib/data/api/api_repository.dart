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
// Anything the backend genuinely has no concept of at all (a parts/quote
// workflow, invoice line detail) stays empty rather than fabricating it —
// this never serves [MockPartnerRepository]'s canned data for a real,
// fetched booking. The in-job checklist is real too, just not backend-
// sourced: [defaultChecklistFor] is a genuine per-category procedure list
// (no fabricated readings, nothing pre-checked), the same way the
// Customer app's ServiceItem.included lists are real static content.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
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

  /// Null until the first successful `/technician/me` response — falls
  /// back to the mock's rating/jobsCompletedTotal until then. See
  /// [refreshMe].
  double? _rating;
  int? _jobsCompletedTotal;

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

  /// Refreshes on-duty state and this technician's real rating/completed-
  /// job total from `/api/technician/me`. Best-effort, same failure
  /// handling as [refreshBookings].
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
      // Previously discarded — the Jobs tab's "Rating" stat box kept
      // showing Mock's fixed 4.94 forever, even after this real value
      // loaded, while the Profile tab a few taps away showed the real
      // (and often different) one.
      if (data['rating'] is num) _rating = (data['rating'] as num).toDouble();
      if (data['jobsCompleted'] is num) {
        _jobsCompletedTotal = (data['jobsCompleted'] as num).toInt();
      }
    } catch (_) {
      // Ignored — techStats() falls back to the mock's figures.
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
  Future<bool> advanceJob(String jobId, {int? suctionBefore, int? suctionAfter}) async {
    try {
      final token = await _idToken();
      if (token == null) return false;
      final res = await http
          .patch(
            Uri.parse('${ApiConfig.baseUrl}/api/bookings/$jobId/advance'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              if (suctionBefore != null) 'suctionBefore': suctionBefore,
              if (suctionAfter != null) 'suctionAfter': suctionAfter,
            }),
          )
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

  /// Passes on [jobId] via the real backend — previously "Pass" only
  /// removed the request from this screen, leaving the booking assigned
  /// to this technician forever with the customer's job never actually
  /// moving. Returns whether the booking was handed to a different
  /// technician (true) or had to be cancelled because nobody else was
  /// available (false) — null on outright failure, in which case the local
  /// cache is left untouched so the request stays visible to retry.
  Future<bool?> declineJob(String jobId) async {
    try {
      final token = await _idToken();
      if (token == null) return null;
      final res = await http
          .patch(
            Uri.parse('${ApiConfig.baseUrl}/api/bookings/$jobId/decline'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) return null;
      final reassigned = data['reassigned'] == true;
      if (reassigned) {
        // No longer this technician's job — drop it from the local cache
        // entirely rather than showing a status update for a booking that
        // isn't theirs any more.
        _bookings = _bookings.where((b) => b.id != jobId).toList(growable: false);
      } else if (data['status'] is String) {
        _replaceBookingStatus(jobId, data['status'] as String);
      }
      return reassigned;
    } catch (_) {
      return null;
    }
  }

  /// Records how the customer actually paid via `/api/bookings/<id>/payment`
  /// — [method] is one of upi/card/cash/link. Previously the close-job
  /// screen's "Mark paid" button called nothing at all; the booking was
  /// already Completed by the prior advance-to-Completed call, so this had
  /// zero effect beyond a SnackBar. Returns whether the call succeeded.
  Future<bool> setPaymentMethod(String jobId, String method) async {
    try {
      final token = await _idToken();
      if (token == null) return false;
      final res = await http
          .patch(
            Uri.parse('${ApiConfig.baseUrl}/api/bookings/$jobId/payment'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'paymentMethod': method}),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return false;
      final i = _bookings.indexWhere((b) => b.id == jobId);
      if (i != -1) {
        final next = [..._bookings];
        next[i] = next[i].copyWith(paymentMethod: method);
        _bookings = next;
      }
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
    final rating = _rating ?? mock.rating;
    final jobsCompletedTotal = _jobsCompletedTotal ?? mock.jobsCompletedTotal;
    if (!_bookingsFetched) {
      return online == null && _rating == null && _jobsCompletedTotal == null
          ? mock
          : _withRealFields(mock, online, rating, jobsCompletedTotal);
    }
    final today = DateTime.now();
    bool isToday(DateTime? dt) =>
        dt != null && dt.year == today.year && dt.month == today.month && dt.day == today.day;
    final completedToday =
        _bookings.where((b) => b.status == 'Completed' && isToday(b.updatedAt));
    final touchedToday = _bookings.where((b) => isToday(b.createdAt) || isToday(b.updatedAt));
    final earningsTodayPaise =
        completedToday.fold<int>(0, (sum, b) => sum + b.totalAmountPaise);
    return TechStats(
      earningsTodayPaise: earningsTodayPaise,
      jobsDone: completedToday.length,
      // touchedToday is a superset of completedToday by construction
      // (completed-today implies updated-today), so this is always >= jobsDone.
      jobsTotal: touchedToday.length,
      rating: rating,
      jobsCompletedTotal: jobsCompletedTotal,
      onDuty: online ?? mock.onDuty,
    );
  }

  TechStats _withRealFields(TechStats s, bool? onDuty, double rating, int jobsCompletedTotal) =>
      TechStats(
        earningsTodayPaise: s.earningsTodayPaise,
        jobsDone: s.jobsDone,
        jobsTotal: s.jobsTotal,
        rating: rating,
        jobsCompletedTotal: jobsCompletedTotal,
        onDuty: onDuty ?? s.onDuty,
      );

  /// Every completed booking, most recent first — the real data behind the
  /// earnings/reports screen. Empty (not Mock) once bookings have actually
  /// been fetched, same "don't fabricate" rule as [hasActiveJob].
  List<BookingDto> completedBookings() {
    final list = _bookings.where((b) => b.status == 'Completed').toList();
    list.sort((a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(0))
        .compareTo(a.updatedAt ?? a.createdAt ?? DateTime(0)));
    return list;
  }

  /// Jobs a customer cancelled after this technician had already committed
  /// time — the ones that actually carry a real cancellation fee (see
  /// app.py's CANCELLATION_FEE_BY_STATUS). A cancellation before any
  /// engagement carries a fee of 0 and is filtered out here; there's
  /// nothing to compensate for.
  List<BookingDto> cancellationFeeBookings() {
    final list = _bookings
        .where((b) => b.status == 'Cancelled' && (b.cancellationFeePaise ?? 0) > 0)
        .toList();
    list.sort((a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(0))
        .compareTo(a.updatedAt ?? a.createdAt ?? DateTime(0)));
    return list;
  }

  bool get bookingsFetched => _bookingsFetched;

  @override
  JobRequest? incomingRequest() {
    if (!_bookingsFetched) return _mock.incomingRequest();
    final requested = _bookings.where((b) => b.status == 'Requested');
    if (requested.isEmpty) return null;
    final b = requested.first;
    double? distanceKm;
    if (_myLat != null && _myLng != null && b.lat != null && b.lng != null) {
      distanceKm = Geolocator.distanceBetween(_myLat!, _myLng!, b.lat!, b.lng!) / 1000;
    }
    return JobRequest(
      jobId: b.id,
      serviceTitle: b.service,
      // The customer's real area, from their booking — previously a
      // hardcoded "Gangapur Road" shown for every request regardless of
      // which of this app's supported cities it was actually in.
      areaLabel: (b.area?.trim().isNotEmpty ?? false) ? b.area! : '',
      distanceKm: distanceKm,
      timeWindow: _timeWindow(b.createdAt),
      payoutPaise: b.totalAmountPaise,
      note: '',
    );
  }

  /// Caches this technician's last known position so [incomingRequest] can
  /// compute a real straight-line distance to a job — called by
  /// TechJobsScreen once after a best-effort Geolocator fix. Never queried
  /// itself (no permission prompts live in this repository layer); a
  /// missing position just means [incomingRequest] leaves distance null
  /// instead of ever fabricating one.
  void setMyPosition(double lat, double lng) {
    _myLat = lat;
    _myLng = lng;
  }

  double? _myLat;
  double? _myLng;

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
      // The customer's own real "directions for the technician" text —
      // previously this always showed the mock job's fabricated "Gate code
      // 4402, lift on the left" for every real booking too, regardless of
      // what the customer actually typed (or didn't).
      directions: b.directions ?? 'No directions given by the customer.',
      // The customer's own real reported symptoms/notes — previously this
      // always showed the mock job's fabricated "Weak suction, rattling
      // noise..." for every real booking regardless of appliance or what
      // was actually reported (or nothing at all).
      reportedTags: b.issues,
      reportedQuote: b.notes ?? '',
      // A genuine per-category procedure list, all unchecked — previously
      // every real job showed the identical mock chimney checklist,
      // including two items pre-ticked with a fabricated suction reading
      // ("480 m³/hr") nobody had actually taken yet.
      checklist: defaultChecklistFor(b.category),
      // No real parts/quote backend exists yet — an empty list here (never
      // the mock's fabricated pre-approved "Baffle filter — Elica 90cm")
      // is what TechJobScreen renders as a genuine "coming soon" state.
      parts: const [],
      lat: b.lat,
      lng: b.lng,
      customerPhone: b.customerPhone,
    );
  }

  /// Real jobs get a single honest line — the service and its actual
  /// booked total_amount, straight from the last `/technician/bookings`
  /// fetch. There's no real payment gateway or itemized-parts backend
  /// behind this app yet, so a fabricated visit-fee/coupon/GST/parts
  /// breakdown would just be numbers nobody actually charged — this was
  /// the exact bug reported: every job showed the same hardcoded ₹899 +
  /// parts + coupon + GST invoice regardless of what was really booked.
  /// Falls back to the mock invoice only for a job this technician doesn't
  /// have in their real, fetched bookings (a mock/demo job).
  @override
  List<InvoiceLine> closeInvoice(String jobId) {
    final match = _bookings.where((b) => b.id == jobId);
    if (match.isEmpty) return _mock.closeInvoice(jobId);
    final booking = match.first;
    return [InvoiceLine(booking.service, booking.totalAmountPaise)];
  }

  /// The live status string for [jobId] if it's a known real booking from
  /// the last successful `/technician/bookings` fetch, else null (a mock
  /// job, or a real job not yet fetched). Used by the job screen to decide
  /// which status-advance action to offer next.
  String? statusOf(String jobId) {
    final match = _bookings.where((b) => b.id == jobId);
    return match.isEmpty ? null : match.first.status;
  }

  /// The appliance category code (e.g. 'RasoiAir' for chimneys) for [jobId]
  /// if it's a known real booking, else null — used to offer the airflow
  /// (CFM) reading screen only for chimney jobs.
  String? categoryOf(String jobId) {
    final match = _bookings.where((b) => b.id == jobId);
    return match.isEmpty ? null : match.first.category;
  }

  /// True if any of this technician's real bookings from the last
  /// `/technician/bookings` fetch is assigned and not yet completed
  /// (`Accepted`, `On the way`, or `In Progress`). Used to gate live GPS
  /// reporting — see `technician_location_reporter.dart`. Unlike
  /// [routeToday], this deliberately does NOT fall back to Mock data before
  /// the first fetch: reporting should only ever start for a real job.
  bool hasActiveJob() => _bookings.any((b) =>
      b.status == 'Accepted' || b.status == 'On the way' || b.status == 'In Progress');

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

/// A genuine on-site procedure list for a real booking, by the backend's
/// appliance category code (see appliance_category.dart in the Customer
/// app) — every item starts unchecked; the technician actually ticks them
/// off during the visit. This replaces MockPartnerRepository's single fixed
/// chimney checklist, which used to show for every category and shipped
/// two items pre-checked with a fabricated suction reading.
List<ChecklistItem> defaultChecklistFor(String category) {
  final steps = switch (category) {
    'RasoiAir' => const [
        'Start code verified with customer',
        'Floor sheeting laid',
        'Filters and blower degreased',
        'Duct checked for blockage or leaks',
        'Suction tested after cleaning',
        'Site cleaned, customer walkthrough',
      ],
    'RasoiSpark' => const [
        'Start code verified with customer',
        'Burner caps and igniters inspected',
        'Gas line leak-tested on every joint',
        'Flame colour and evenness checked',
        'Site cleaned, customer walkthrough',
      ],
    'RasoiWash' => const [
        'Start code verified with customer',
        'Filter, spray arms and seals checked',
        'Drain line tested for blockage',
        'Test cycle run',
        'Site cleaned, customer walkthrough',
      ],
    'RasoiBuilt' => const [
        'Start code verified with customer',
        'Door seal and hinge checked',
        'Heating element and thermostat tested',
        'Test cycle run',
        'Site cleaned, customer walkthrough',
      ],
    'RasoiChill' => const [
        'Start code verified with customer',
        'Coolant lines and compressor checked',
        'Door seal tested',
        'Temperature verified after service',
        'Site cleaned, customer walkthrough',
      ],
    'RasoiPure' => const [
        'Start code verified with customer',
        'Filters inspected and replaced if due',
        'Membrane and tank checked',
        'Output water tested',
        'Site cleaned, customer walkthrough',
      ],
    _ => const [
        'Start code verified with customer',
        'Fault diagnosed and confirmed with customer',
        'Repair completed',
        'Site cleaned, customer walkthrough',
      ],
  };
  return [for (final step in steps) ChecklistItem(step)];
}

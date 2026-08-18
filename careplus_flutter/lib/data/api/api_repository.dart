// Real-backend-backed [CareRepository]. Everything except bookings is
// delegated unchanged to a wrapped [MockRepository] — the rich local catalog
// content (appliance descriptions, "what's included" lists, reviews) has no
// server-side equivalent and isn't meant to grow one, see the build brief.
// Only booking creation and "my bookings" talk to the real backend
// (app.py/database.py at the repo root).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';

import '../mock_repository.dart';
import '../models.dart';
import 'appliance_category.dart';
import 'backend_client.dart';

class ApiRepository implements CareRepository {
  ApiRepository({BackendClient? client, this.onBookingsChanged})
      : _client = client ?? BackendClient(),
        _mock = MockRepository() {
    unawaited(_loadInitialBookings());
  }

  final BackendClient _client;
  final MockRepository _mock;

  /// Called whenever the real-booking cache changes (initial fetch lands,
  /// or a new booking is created) so a Riverpod provider can trigger a
  /// rebuild of screens reading [bookings]. See bookingsRefreshProvider in
  /// lib/state/providers.dart.
  final void Function()? onBookingsChanged;

  /// null until the first successful GET /api/bookings — at which point we
  /// switch over from MockRepository's canned demo bookings to real ones
  /// entirely (see the build brief: "favor simplicity"). A failed or
  /// not-yet-completed fetch leaves this null and [bookings] keeps
  /// serving the mock list, same as before this class existed.
  List<Booking>? _realBookings;

  Future<String?> _idToken() async {
    if (Firebase.apps.isEmpty) return null; // mock auth mode — nothing to send
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadInitialBookings() async {
    final token = await _idToken();
    if (token == null) return;
    final rows = await _client.fetchBookings(idToken: token);
    // An empty-but-successful fetch (new user, no bookings yet) still counts
    // as "we have real data now" — an empty list, not the mock demo data.
    _realBookings = rows.map(_bookingFromJson).toList();
    onBookingsChanged?.call();
  }

  /// Called from the booking flow's final confirm/pay step
  /// (PaymentScreen in lib/features/booking/booking_screens.dart). Posts
  /// the booking to the backend and, on success, adds it to the in-memory
  /// cache immediately so [bookings] reflects it without a refetch. Never
  /// throws — on any failure this returns null and the caller's local
  /// "booking confirmed" UI flow proceeds regardless.
  ///
  /// [totalPaise] must be the exact figure shown to the customer as
  /// "Payable now" (visit fee + tax − any discount, from
  /// `BookingDraft.totalPaise`) — this is what gets stored as the
  /// booking's real total_amount, so it's what the Partner and Admin
  /// apps see too. Falling back to the bare service price here previously
  /// meant the customer could be shown one figure at checkout while a
  /// completely different (lower) one landed in the technician's app.
  Future<Booking?> createBooking({
    required ServiceItem service,
    required int totalPaise,
    String? areaLabel,
    double? lat,
    double? lng,
  }) async {
    final token = await _idToken();
    if (token == null) return null;
    final category = applianceToBackendCategory[service.appliance] ?? 'RasoiAir';
    final json = await _client.createBooking(
      idToken: token,
      category: category,
      service: service.title,
      price: totalPaise ~/ 100, // backend stores whole rupees
      area: areaLabel,
      lat: lat,
      lng: lng,
    );
    if (json == null) return null;
    final booking = _bookingFromJson(json);
    _realBookings = [...(_realBookings ?? []), booking];
    onBookingsChanged?.call();
    return booking;
  }

  Booking _bookingFromJson(Map<String, dynamic> json) {
    final categoryStr = json['category'] as String?;
    final appliance = backendCategoryToAppliance[categoryStr] ?? Appliance.chimney;
    final totalRupees = (json['total_amount'] as num?)?.toInt() ??
        (json['price'] as num?)?.toInt() ??
        0;
    return Booking(
      id: json['id'] as String? ?? '',
      title: json['service'] as String? ?? 'Service',
      appliance: appliance,
      status: _statusFromBackend(json['status'] as String?),
      whenLabel: _whenLabel(json['createdAt'] as String?),
      addressLabel: (json['area'] as String?) ?? 'Address on file',
      totalPaise: totalRupees * 100,
      // The booking payload has no technician profile fields (name,
      // rating, jobs done, vehicle) — not worth a second fetch for this
      // pass, see the build brief.
      technician: null,
      stars: null,
      // Raw id + coordinates the backend does send — enough for the
      // tracking screen's live map without a second fetch. See
      // TechnicianLocationService.
      technicianId: json['technicianId'] as String?,
      // Firestore key for live location — NOT the same as technicianId
      // above, see Booking.technicianFirebaseUid's doc comment.
      technicianFirebaseUid: json['technicianFirebaseUid'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      suctionBefore: (json['suctionBefore'] as num?)?.toInt(),
      suctionAfter: (json['suctionAfter'] as num?)?.toInt(),
      timeOnSiteMin: (json['timeOnSiteMin'] as num?)?.toInt(),
      cancellationFeePaise: (json['cancellationFee'] as num?) == null
          ? null
          : (json['cancellationFee'] as num).toInt() * 100,
      rawStatus: json['status'] as String? ?? '',
    );
  }

  /// A preview of what cancelling [booking] right now would cost — the
  /// same tiers as app.py's CANCELLATION_FEE_BY_STATUS, so the "are you
  /// sure" dialog can show a real number instead of a vague warning. The
  /// server recomputes this independently when the cancellation actually
  /// happens, so a stale preview (job advanced a step since this was read)
  /// can never under- or overcharge — it just shows the wrong estimate for
  /// a moment.
  static int? cancellationFeePreviewPaise(Booking booking) => switch (booking.rawStatus) {
        'Requested' => 0,
        'Accepted' => 10000,
        'On the way' || 'In Progress' => 20000,
        _ => null,
      };

  BookingStatus _statusFromBackend(String? status) => switch (status) {
        'Requested' => BookingStatus.scheduled,
        'Accepted' => BookingStatus.scheduled,
        'On the way' => BookingStatus.onTheWay,
        'In Progress' => BookingStatus.inProgress,
        'Completed' => BookingStatus.completed,
        'Cancelled' => BookingStatus.cancelled,
        _ => BookingStatus.scheduled,
      };

  /// Cancels a booking this customer owns. On success, updates the
  /// in-memory cache in place so BookingsScreen's Upcoming/Cancelled tabs
  /// reflect it immediately without a refetch. Returns the real fee (in
  /// paise, 0 if none) that was applied, or null if the cancellation
  /// itself failed (network error, already completed, not this
  /// customer's booking).
  Future<int?> cancelBooking(String bookingId) async {
    final token = await _idToken();
    if (token == null) return null;
    final json = await _client.cancelBooking(idToken: token, bookingId: bookingId);
    if (json == null) return null;
    final updated = _bookingFromJson(json);
    _realBookings = [
      for (final b in _realBookings ?? const <Booking>[])
        if (b.id == bookingId) updated else b,
    ];
    onBookingsChanged?.call();
    return updated.cancellationFeePaise ?? 0;
  }

  String _whenLabel(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      return DateFormat('d MMM · h:mm a').format(dt);
    } catch (_) {
      return createdAt;
    }
  }

  // ---------------------------------------------------------------------
  // Everything below is delegated to MockRepository unchanged.
  // ---------------------------------------------------------------------

  @override
  List<ServiceItem> servicesFor(Appliance a) => _mock.servicesFor(a);

  @override
  List<ServiceItem> catalog() => _mock.catalog();

  @override
  List<Issue> issuesFor(Appliance a) => _mock.issuesFor(a);

  @override
  ApplianceDetail applianceDetail(Appliance a) => _mock.applianceDetail(a);

  @override
  List<SavedAddress> addresses() => _mock.addresses();

  @override
  List<PaymentMethod> paymentMethods() => _mock.paymentMethods();

  @override
  Technician get preferredTechnician => _mock.preferredTechnician;

  @override
  Stream<int> etaStream(String bookingId) => _mock.etaStream(bookingId);

  List<Booking> get _allBookings =>
      _realBookings ?? [..._mock.bookings(), ..._mock.bookings(completed: true)];

  @override
  List<Booking> bookings({BookingStatus? status, bool completed = false}) {
    final all = _allBookings;
    if (completed) {
      return all.where((b) => b.status == BookingStatus.completed).toList();
    }
    if (status == BookingStatus.cancelled) {
      return all.where((b) => b.status == BookingStatus.cancelled).toList();
    }
    // "Upcoming" — everything not yet completed and not cancelled. Without
    // the cancelled exclusion here, a cancelled booking used to land back
    // in Upcoming (the only other bucket BookingsScreen had a real query
    // for), since it's neither the completed status nor a status match.
    return all
        .where((b) =>
            b.status != BookingStatus.completed && b.status != BookingStatus.cancelled)
        .where((b) => status == null || b.status == status)
        .toList();
  }

  @override
  Booking? bookingById(String id) {
    for (final b in _allBookings) {
      if (b.id == id) return b;
    }
    return null;
  }
}

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
  Future<Booking?> createBooking({
    required ServiceItem service,
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
      price: service.pricePaise ~/ 100, // backend stores whole rupees
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
    );
  }

  BookingStatus _statusFromBackend(String? status) => switch (status) {
        'Requested' => BookingStatus.scheduled,
        'Accepted' => BookingStatus.scheduled,
        'On the way' => BookingStatus.onTheWay,
        'In Progress' => BookingStatus.inProgress,
        'Completed' => BookingStatus.completed,
        _ => BookingStatus.scheduled,
      };

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
    return all
        .where((b) => b.status != BookingStatus.completed)
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

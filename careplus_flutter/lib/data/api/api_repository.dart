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
  ApiRepository({BackendClient? client, this.onBookingsChanged, this.onCoinsChanged})
      : _client = client ?? BackendClient(),
        _mock = MockRepository() {
    unawaited(_loadInitialBookings());
    unawaited(_fetchMe());
  }

  final BackendClient _client;
  final MockRepository _mock;

  /// Called whenever the real-booking cache changes (initial fetch lands,
  /// or a new booking is created) so a Riverpod provider can trigger a
  /// rebuild of screens reading [bookings]. See bookingsRefreshProvider in
  /// lib/state/providers.dart.
  final void Function()? onBookingsChanged;

  /// Called whenever the real Care Coins balance changes (initial fetch
  /// lands, or a redemption succeeds). See coinsRefreshProvider in
  /// lib/state/providers.dart.
  final void Function()? onCoinsChanged;

  /// null until the first successful GET /api/bookings — at which point we
  /// switch over from MockRepository's canned demo bookings to real ones
  /// entirely (see the build brief: "favor simplicity"). A failed or
  /// not-yet-completed fetch leaves this null and [bookings] keeps
  /// serving the mock list, same as before this class existed.
  List<Booking>? _realBookings;

  /// null until the first successful GET /api/auth/me — the checkout
  /// screen treats null as "balance unknown yet" (hides the Care Coins
  /// option) rather than assuming zero.
  int? _coinsBalance;
  int? get coinsBalance => _coinsBalance;

  Future<String?> _idToken({bool forceRefresh = false}) async {
    if (Firebase.apps.isEmpty) return null; // mock auth mode — nothing to send
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken(forceRefresh);
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

  /// Public re-fetch, called from BookingsScreen on mount and on
  /// pull-to-refresh. The constructor's one-shot [_loadInitialBookings] can
  /// run before Firebase Auth has restored `currentUser` on a cold start —
  /// [_idToken] then returns null, [_realBookings] is never set, and
  /// [bookings] silently keeps serving mock demo data for the rest of the
  /// app's lifetime with nothing to retry it. This gives the UI a way to
  /// ask again once a real signed-in user is actually available.
  Future<void> refreshBookings() => _loadInitialBookings();

  Future<void> _fetchMe() async {
    final token = await _idToken();
    if (token == null) return;
    final json = await _client.fetchMe(idToken: token);
    if (json == null) return;
    _coinsBalance = (json['coinsBalance'] as num?)?.toInt() ?? 0;
    onCoinsChanged?.call();
  }

  /// Public re-fetch — same cold-start-race reasoning as [refreshBookings].
  Future<void> refreshCoins() => _fetchMe();

  /// Redeems [amount] real Care Coins (1 coin = ₹1) right before checkout
  /// creates the booking(s) — called once per order, decoupled from how
  /// many booking rows a multi-service cart creates. Returns true and
  /// updates the cached balance on success; false if the backend rejected
  /// it (e.g. balance changed since it was last fetched) or the request
  /// failed outright — the caller should treat false as "redeemed nothing"
  /// and charge the full price rather than guessing.
  /// Places a real shop order (see ShopScreen's cart/checkout) — `items` is
  /// `{productId: qty}`. Returns the placed order's total on success, or an
  /// error message on failure; never throws.
  Future<({int? totalPaise, String? error})> placeShopOrder(Map<String, int> items) async {
    final token = await _idToken();
    if (token == null) {
      return (totalPaise: null, error: 'Sign in again to place an order.');
    }
    final result = await _client.placeShopOrder(
      idToken: token,
      items: [
        for (final e in items.entries) {'productId': e.key, 'qty': e.value},
      ],
    );
    if (result.order == null) {
      return (totalPaise: null, error: result.error);
    }
    return (totalPaise: (result.order!['totalPaise'] as num).toInt(), error: null);
  }

  Future<bool> redeemCoins(int amount) async {
    if (amount <= 0) return true; // nothing to redeem
    final token = await _idToken();
    if (token == null) return false;
    final json = await _client.redeemCoins(idToken: token, amount: amount);
    if (json == null) return false;
    _coinsBalance = (json['coinsBalance'] as num?)?.toInt() ?? _coinsBalance;
    onCoinsChanged?.call();
    return true;
  }

  /// Called from the booking flow's final confirm/pay step
  /// (PaymentScreen in lib/features/booking/booking_screens.dart). Posts
  /// the booking to the backend and, on success, adds it to the in-memory
  /// cache immediately so [bookings] reflects it without a refetch. Never
  /// throws — on failure `booking` is null and `error` carries why (see
  /// BackendClient.createBooking), so the caller can tell the customer the
  /// real reason instead of a generic "check your connection".
  ///
  /// [totalPaise] must be the exact figure shown to the customer as
  /// "Payable now" (visit fee + tax − any discount, from
  /// `BookingDraft.totalPaise`) — this is what gets stored as the
  /// booking's real total_amount, so it's what the Partner and Admin
  /// apps see too. Falling back to the bare service price here previously
  /// meant the customer could be shown one figure at checkout while a
  /// completely different (lower) one landed in the technician's app.
  Future<({Booking? booking, String? error})> createBooking({
    required ServiceItem service,
    required int totalPaise,
    String? areaLabel,
    double? lat,
    double? lng,
    String? directions,
  }) async {
    final token = await _idToken();
    if (token == null) return (booking: null, error: 'You need to be signed in to book.');
    final category = applianceToBackendCategory[service.appliance] ?? 'RasoiAir';
    var result = await _client.createBooking(
      idToken: token,
      category: category,
      service: service.title,
      price: totalPaise ~/ 100, // backend stores whole rupees
      area: areaLabel,
      lat: lat,
      lng: lng,
      directions: directions,
    );
    // A 401 here is almost always a stale cached ID token (Firebase tokens
    // expire hourly; getIdToken() without forceRefresh can hand back one
    // that's about to or has just expired) rather than a real "you're not
    // signed in" — retry once with a forced refresh before ever surfacing
    // this as a failure. This is the single highest-stakes action in the
    // app (creating a real, paid booking), worth one extra round trip to
    // avoid a spurious failure on a genuinely signed-in customer.
    if (result.unauthorized) {
      final freshToken = await _idToken(forceRefresh: true);
      if (freshToken != null) {
        result = await _client.createBooking(
          idToken: freshToken,
          category: category,
          service: service.title,
          price: totalPaise ~/ 100,
          area: areaLabel,
          lat: lat,
          lng: lng,
          directions: directions,
        );
      }
    }
    if (result.booking == null) return (booking: null, error: result.error);
    final booking = _bookingFromJson(result.booking!);
    _realBookings = [...(_realBookings ?? []), booking];
    onBookingsChanged?.call();
    return (booking: booking, error: null);
  }

  /// Submits the real star rating from RateScreen — previously the
  /// "Submit rating" button never called anything, just showed a fake
  /// "60 Care Coins added" toast and went home regardless of what was
  /// picked. Returns true only if the backend actually recorded it.
  Future<bool> rateBooking({required String bookingId, required int rating}) async {
    final token = await _idToken();
    if (token == null) return false;
    return _client.rateBooking(idToken: token, bookingId: bookingId, rating: rating);
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

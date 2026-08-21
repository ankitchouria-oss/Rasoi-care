// Riverpod wiring. The repository provider is the single place you change to
// go from mock data to Firebase.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/mock_repository.dart';
import '../data/api/api_repository.dart';
import 'firestore_providers.dart';

/// Bumped every time [ApiRepository]'s real-booking cache changes (initial
/// fetch lands, or a new booking is created), so screens that read
/// `repo.bookings()` can `ref.watch` this to pick up the change — see
/// BookingsScreen in lib/features/account/account_screens.dart.
final bookingsRefreshProvider = StateProvider<int>((ref) => 0);

/// Bumped every time [ApiRepository]'s real Care Coins balance changes
/// (initial fetch lands, or a redemption succeeds) — see [pricingProvider],
/// which watches this to recompute the checkout total.
final coinsRefreshProvider = StateProvider<int>((ref) => 0);

/// The concrete repository, exposed separately from [repositoryProvider] so
/// call sites that need to *write* (creating a booking) can reach methods
/// outside the read-only [CareRepository] interface — e.g. PaymentScreen in
/// lib/features/booking/booking_screens.dart.
final apiRepositoryProvider = Provider<ApiRepository>((ref) {
  return ApiRepository(
    onBookingsChanged: () => ref.read(bookingsRefreshProvider.notifier).state++,
    onCoinsChanged: () => ref.read(coinsRefreshProvider.notifier).state++,
  );
});

/// Swap the provider built here to change data sources — nothing else moves.
/// [ApiRepository] wraps a [MockRepository] for everything except bookings,
/// which come from the real Flask+SQLite backend — see lib/data/api.
final repositoryProvider =
    Provider<CareRepository>((ref) => ref.watch(apiRepositoryProvider));

/// The addresses screens actually show: real ones saved through the map
/// picker's address-details step (SelectLocationScreen's "Saved
/// addresses"), falling back to the single address collected at signup
/// only if nothing's been explicitly saved yet. No more hardcoded demo
/// "Home"/"Parents" entries for every customer.
final savedAddressesProvider = Provider<List<SavedAddress>>((ref) {
  final repo = ref.watch(repositoryProvider);
  final profile = ref.watch(userProfileStreamProvider).valueOrNull;
  if (profile != null && profile.addresses.isNotEmpty) {
    return profile.addresses;
  }
  final signupAddress = (profile != null && profile.address.isNotEmpty)
      ? [SavedAddress('a_signup', 'Home', profile.address, '🏠', profile.lat, profile.lng)]
      : const <SavedAddress>[];
  return [...signupAddress, ...repo.addresses()];
});

/// Which of [savedAddressesProvider]'s entries the Home screen's "Serving"
/// header shows — null means "use the first one" (the real signup address,
/// when there is one). Set by tapping an entry in HomeScreen's location
/// sheet; previously that sheet closed without recording the tap at all, so
/// the header stayed on its hardcoded text no matter what you picked.
final selectedAddressIdProvider = StateProvider<String?>((ref) => null);

/// A map-picked address that isn't part of [savedAddressesProvider]'s list
/// (the signup address / repo.addresses()) — set when HomeScreen's location
/// sheet sends someone through the real AddressPickerScreen. Previously
/// "Use current location" there just closed the sheet with nothing wired
/// behind it, so no pick ever reached the Home screen no matter what was
/// chosen.
final homeAddressOverrideProvider = StateProvider<SavedAddress?>((ref) => null);

/// App-wide light/dark toggle. Persist to shared_preferences in production.
final themeModeProvider = NotifierProvider<ThemeModeVM, ThemeMode>(ThemeModeVM.new);

class ThemeModeVM extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;
  void toggle() =>
      state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  set(ThemeMode m) => state = m;
}

/// Live ETA for a tracked booking.
final etaProvider = StreamProvider.autoDispose.family<int, String>(
  (ref, bookingId) => ref.watch(repositoryProvider).etaStream(bookingId),
);

// ---------------------------------------------------------------------------
// Booking draft — one immutable object carried across the four booking steps.
// The View reads it; intents mutate it. This is the MVVM "one state object per
// flow" pattern from the build spec.
// ---------------------------------------------------------------------------
class BookingDraft {
  const BookingDraft({
    this.services = const [],
    this.issues = const [],
    this.notes = '',
    this.day = 'Sat 25 Jul',
    this.slot = '10:00 – 11:30 am',
    this.addressId = 'a_home',
    this.pickedAddress,
    this.directions = '',
    this.useCoins = false,
    this.paymentId = 'upi',
  });

  /// Every service the customer added on the service-detail screen —
  /// previously a single `ServiceItem?`, which silently dropped the first
  /// pick the moment a second one was tapped even though its "Add"/"Added"
  /// button language implied you could add more than one.
  final List<ServiceItem> services;
  final List<Issue> issues;
  final String notes;
  final String day;
  final String slot;
  final String addressId;

  /// A one-off address confirmed through the map picker
  /// (AddressPickerScreen), carrying real lat/lng — not part of
  /// `repo.addresses()`'s canned list, so it's threaded through the draft
  /// directly instead. [addressId] is set to match its id whenever this is
  /// set, so the existing "which card is selected" comparisons in
  /// AddressScreen keep working unchanged.
  final SavedAddress? pickedAddress;

  /// Free-text the customer actually typed on the address step — sent to
  /// the backend and shown to the technician as-is. Previously a
  /// hardcoded, non-editable "Gate code 4402, lift on the left" that every
  /// customer's job showed regardless of their real address, and that
  /// wasn't wired to the backend even if you could have edited it.
  final String directions;

  /// Whether the customer opted to redeem their real Care Coins balance at
  /// checkout — see [pricingProvider], which caps the actual redemption at
  /// whatever's really available and really needed.
  final bool useCoins;

  /// Which "Pay with" option is highlighted on checkout — display only,
  /// see [PaymentMethod]'s doc comment. Never read by booking creation.
  final String paymentId;

  /// The real, unmodified total of what was actually selected — no
  /// invented visit fee, coupon, loyalty-coin discount, or GST used to be
  /// layered on top of this by default (CARE30 was even pre-applied),
  /// none of which reflected an actual pricing or tax policy. Used for the
  /// pre-checkout cart preview; [pricingProvider] computes the real
  /// payable total shown at checkout.
  int get totalPaise => services.fold(0, (sum, s) => sum + s.pricePaise);

  BookingDraft copyWith({
    List<ServiceItem>? services,
    List<Issue>? issues,
    String? notes,
    String? day,
    String? slot,
    String? addressId,
    SavedAddress? pickedAddress,
    String? directions,
    bool? useCoins,
    String? paymentId,
  }) =>
      BookingDraft(
        services: services ?? this.services,
        issues: issues ?? this.issues,
        notes: notes ?? this.notes,
        day: day ?? this.day,
        slot: slot ?? this.slot,
        addressId: addressId ?? this.addressId,
        pickedAddress: pickedAddress ?? this.pickedAddress,
        directions: directions ?? this.directions,
        useCoins: useCoins ?? this.useCoins,
        paymentId: paymentId ?? this.paymentId,
      );
}

// ---------------------------------------------------------------------------
// Checkout pricing — visit fee, an auto-applied coupon above a real
// threshold, real 18% GST, and (optionally) real Care Coins redemption.
// Every figure here is a fixed, disclosed business rule, not an invented
// number: ₹49 visit fee, ₹200 off once the pre-GST subtotal passes ₹1,700,
// 18% GST (the standard rate for services in India), 1 Care Coin = ₹1,
// earned server-side at 2% of a booking's real total once it's actually
// completed (see advance_booking in app.py) and redeemed server-side via
// POST /api/me/coins/redeem right before checkout creates the booking(s).
// ---------------------------------------------------------------------------
const kVisitFeePaise = 4900;
const kCouponThresholdPaise = 170000;
const kCouponDiscountPaise = 20000;
const kGstRate = 0.18;

class PricingBreakdown {
  const PricingBreakdown({
    required this.subtotalPaise,
    required this.visitFeePaise,
    required this.couponDiscountPaise,
    required this.gstPaise,
    required this.coinsRedeemed,
    required this.grandTotalPaise,
  });
  final int subtotalPaise;
  final int visitFeePaise;
  final int couponDiscountPaise;
  final int gstPaise;

  /// Whole coins (= rupees) actually redeemed — capped at both the real
  /// balance and what's left to pay, so this can never exceed either.
  final int coinsRedeemed;
  final int grandTotalPaise;
}

PricingBreakdown computePricing(
  List<ServiceItem> services, {
  required bool useCoins,
  required int coinsBalance,
}) {
  final subtotal = services.fold(0, (sum, s) => sum + s.pricePaise);
  if (subtotal == 0) {
    return const PricingBreakdown(
      subtotalPaise: 0,
      visitFeePaise: 0,
      couponDiscountPaise: 0,
      gstPaise: 0,
      coinsRedeemed: 0,
      grandTotalPaise: 0,
    );
  }
  final preGstBase = subtotal + kVisitFeePaise;
  final coupon = preGstBase > kCouponThresholdPaise ? kCouponDiscountPaise : 0;
  final afterCoupon = preGstBase - coupon;
  final gst = (afterCoupon * kGstRate).round();
  final beforeCoins = afterCoupon + gst;
  final coinsRedeemed = useCoins ? coinsBalance.clamp(0, beforeCoins ~/ 100) : 0;
  return PricingBreakdown(
    subtotalPaise: subtotal,
    visitFeePaise: kVisitFeePaise,
    couponDiscountPaise: coupon,
    gstPaise: gst,
    coinsRedeemed: coinsRedeemed,
    grandTotalPaise: beforeCoins - coinsRedeemed * 100,
  );
}

/// The real checkout total for the current [bookingDraftProvider], factoring
/// in the visit fee, auto-coupon, GST, and any Care Coins redemption —
/// recomputed whenever the draft or the real coins balance changes.
final pricingProvider = Provider<PricingBreakdown>((ref) {
  final draft = ref.watch(bookingDraftProvider);
  ref.watch(coinsRefreshProvider);
  final coinsBalance = ref.watch(apiRepositoryProvider).coinsBalance ?? 0;
  return computePricing(draft.services, useCoins: draft.useCoins, coinsBalance: coinsBalance);
});

final bookingDraftProvider =
    NotifierProvider<BookingDraftVM, BookingDraft>(BookingDraftVM.new);

class BookingDraftVM extends Notifier<BookingDraft> {
  @override
  BookingDraft build() => const BookingDraft();

  void start(List<ServiceItem> services) {
    if (services.isEmpty) return;
    final issues = ref.read(repositoryProvider).issuesFor(services.first.appliance);
    // Matches the label SlotScreen builds for its "Today" chip — so that
    // chip shows selected by default instead of the flow opening on a
    // mismatched, permanently-stale hardcoded date.
    final today = 'Today ${DateFormat('d MMM').format(DateTime.now())}';
    state = BookingDraft(services: services, issues: issues, day: today);
  }

  void toggleIssue(int i) {
    final next = [...state.issues];
    next[i] = next[i].copyWith(selected: !next[i].selected);
    state = state.copyWith(issues: next);
  }

  void setNotes(String v) => state = state.copyWith(notes: v);
  void setSlot(String day, String slot) =>
      state = state.copyWith(day: day, slot: slot);
  void setAddress(String id) => state = state.copyWith(addressId: id);

  /// Called when the map picker (or its no-Maps-configured fallback form)
  /// confirms a new address — selects it immediately, same as tapping an
  /// existing `repo.addresses()` card.
  void setPickedAddress(SavedAddress address) =>
      state = state.copyWith(addressId: address.id, pickedAddress: address);
  void setDirections(String v) => state = state.copyWith(directions: v);
  void toggleUseCoins() => state = state.copyWith(useCoins: !state.useCoins);
  void setPayment(String id) => state = state.copyWith(paymentId: id);
}

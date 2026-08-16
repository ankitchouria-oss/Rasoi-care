// Riverpod wiring. The repository provider is the single place you change to
// go from mock data to Firebase.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/mock_repository.dart';
import '../data/api/api_repository.dart';
import 'firestore_providers.dart';

/// Bumped every time [ApiRepository]'s real-booking cache changes (initial
/// fetch lands, or a new booking is created), so screens that read
/// `repo.bookings()` can `ref.watch` this to pick up the change — see
/// BookingsScreen in lib/features/account/account_screens.dart.
final bookingsRefreshProvider = StateProvider<int>((ref) => 0);

/// The concrete repository, exposed separately from [repositoryProvider] so
/// call sites that need to *write* (creating a booking) can reach methods
/// outside the read-only [CareRepository] interface — e.g. PaymentScreen in
/// lib/features/booking/booking_screens.dart.
final apiRepositoryProvider = Provider<ApiRepository>((ref) {
  return ApiRepository(
    onBookingsChanged: () => ref.read(bookingsRefreshProvider.notifier).state++,
  );
});

/// Swap the provider built here to change data sources — nothing else moves.
/// [ApiRepository] wraps a [MockRepository] for everything except bookings,
/// which come from the real Flask+SQLite backend — see lib/data/api.
final repositoryProvider =
    Provider<CareRepository>((ref) => ref.watch(apiRepositoryProvider));

/// The addresses screens actually show: the real one collected at signup
/// (if any) first, followed by `repo.addresses()` — which is always empty
/// today, but kept as the seam for a future multi-address feature. No more
/// hardcoded demo "Home"/"Parents" entries for every customer.
final savedAddressesProvider = Provider<List<SavedAddress>>((ref) {
  final repo = ref.watch(repositoryProvider);
  final profile = ref.watch(userProfileStreamProvider).valueOrNull;
  final signupAddress = (profile != null && profile.address.isNotEmpty)
      ? [SavedAddress('a_signup', 'Home', profile.address, '🏠', profile.lat, profile.lng)]
      : const <SavedAddress>[];
  return [...signupAddress, ...repo.addresses()];
});

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
    this.service,
    this.issues = const [],
    this.notes = '',
    this.day = 'Sat 25 Jul',
    this.slot = '10:00 – 11:00 am',
    this.addressId = 'a_home',
    this.pickedAddress,
    this.paymentId = 'upi',
    this.couponApplied = true,
    this.useCoins = false,
  });

  final ServiceItem? service;
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
  final String paymentId;
  final bool couponApplied;
  final bool useCoins;

  // Pricing is derived, never stored — the source of truth is the line items.
  int get itemPaise => service?.pricePaise ?? 0;
  int get visitPaise => 4900;
  int get discountPaise => couponApplied ? (itemPaise * 0.30).round() : 0;
  int get coinsPaise => useCoins ? 20000 : 0;
  int get taxablePaise => itemPaise + visitPaise - discountPaise - coinsPaise;
  int get taxPaise => (taxablePaise * 0.18).round();
  int get totalPaise => taxablePaise + taxPaise;

  BookingDraft copyWith({
    ServiceItem? service,
    List<Issue>? issues,
    String? notes,
    String? day,
    String? slot,
    String? addressId,
    SavedAddress? pickedAddress,
    String? paymentId,
    bool? couponApplied,
    bool? useCoins,
  }) =>
      BookingDraft(
        service: service ?? this.service,
        issues: issues ?? this.issues,
        notes: notes ?? this.notes,
        day: day ?? this.day,
        slot: slot ?? this.slot,
        addressId: addressId ?? this.addressId,
        pickedAddress: pickedAddress ?? this.pickedAddress,
        paymentId: paymentId ?? this.paymentId,
        couponApplied: couponApplied ?? this.couponApplied,
        useCoins: useCoins ?? this.useCoins,
      );
}

final bookingDraftProvider =
    NotifierProvider<BookingDraftVM, BookingDraft>(BookingDraftVM.new);

class BookingDraftVM extends Notifier<BookingDraft> {
  @override
  BookingDraft build() => const BookingDraft();

  void start(ServiceItem service) {
    final issues = ref.read(repositoryProvider).issuesFor(service.appliance);
    state = BookingDraft(service: service, issues: issues);
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
  void setPayment(String id) => state = state.copyWith(paymentId: id);
  void toggleCoupon() =>
      state = state.copyWith(couponApplied: !state.couponApplied);
  void toggleCoins() => state = state.copyWith(useCoins: !state.useCoins);
}

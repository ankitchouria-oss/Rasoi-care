// Riverpod wiring. The repository provider is the single place you change to
// go from mock data to Firebase.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/mock_repository.dart';

/// Swap `MockRepository()` for `FirestoreRepository()` here — nothing else moves.
final repositoryProvider = Provider<CareRepository>((ref) => MockRepository());

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
  void setPayment(String id) => state = state.copyWith(paymentId: id);
  void toggleCoupon() =>
      state = state.copyWith(couponApplied: !state.couponApplied);
  void toggleCoins() => state = state.copyWith(useCoins: !state.useCoins);
}

// ---------------------------------------------------------------------------
// Technician job checklist — one mutable list per job id, keyed by jobId so
// the feed and the job screen can share the same ticks if revisited.
// ---------------------------------------------------------------------------
final techChecklistProvider = NotifierProvider.family<TechChecklistVM,
    List<ChecklistItem>, String>(TechChecklistVM.new);

class TechChecklistVM extends FamilyNotifier<List<ChecklistItem>, String> {
  @override
  List<ChecklistItem> build(String arg) =>
      ref.read(repositoryProvider).jobDetail(arg).checklist;

  void toggle(int i) {
    final next = [...state];
    next[i] = next[i].copyWith(checked: !next[i].checked);
    state = next;
  }
}

/// How many "after" photos the technician has captured for a job (0..2).
/// A plain counter is enough here — the mock camera just fills a box in.
final techAfterPhotosProvider =
    NotifierProvider.family<TechAfterPhotosVM, int, String>(
        TechAfterPhotosVM.new);

class TechAfterPhotosVM extends FamilyNotifier<int, String> {
  @override
  int build(String arg) => 0;
  void capture() {
    if (state < 2) state = state + 1;
  }
}

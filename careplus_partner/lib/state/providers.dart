// Riverpod wiring. The repository provider is the single place you change to
// go from mock data to a real backend.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/repository.dart';

/// Swap `MockPartnerRepository()` for a real implementation here — nothing
/// else moves.
final repositoryProvider =
    Provider<PartnerRepository>((ref) => MockPartnerRepository());

/// App-wide light/dark toggle. Persist to shared_preferences in production.
final themeModeProvider = NotifierProvider<ThemeModeVM, ThemeMode>(ThemeModeVM.new);

class ThemeModeVM extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;
  void toggle() =>
      state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  set(ThemeMode m) => state = m;
}

// ---------------------------------------------------------------------------
// Job checklist — one mutable list per job id, keyed by jobId so the feed and
// the job screen can share the same ticks if revisited.
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

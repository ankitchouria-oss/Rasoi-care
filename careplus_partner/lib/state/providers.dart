// Riverpod wiring. The repository provider is the single place you change to
// go from mock data to a real backend.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/api_repository.dart';
import '../data/models.dart';
import '../data/repository.dart';

/// Live-backend-backed repository. It falls back to
/// [MockPartnerRepository]-shaped data internally for anything the server
/// doesn't have and for any failed request — see ApiRepository's header
/// comment. A single instance lives for the app's lifetime so its request
/// cache survives screen rebuilds; watch [jobsFeedTickProvider] to rebuild
/// after its async methods complete.
final repositoryProvider = Provider<PartnerRepository>((ref) => ApiRepository());

/// Bumped by the UI after every real fetch/action against
/// [repositoryProvider] (cast to [ApiRepository]) completes. The repository
/// interface itself stays synchronous, so this is the signal that tells
/// screens watching it to rebuild and re-read the (mutated in place) cache
/// — see tech_jobs_screen.dart / tech_job_screen.dart.
final jobsFeedTickProvider = NotifierProvider<JobsFeedTickVM, int>(JobsFeedTickVM.new);

class JobsFeedTickVM extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

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

/// The before/after photos actually captured (via the device camera) for a
/// job — up to 2 each, local file paths. Real capture, not a fake counter:
/// see _capturePhoto in tech_job_screen.dart.
final techBeforePhotosProvider =
    NotifierProvider.family<JobPhotosVM, List<String>, String>(JobPhotosVM.new);
final techAfterPhotosProvider =
    NotifierProvider.family<JobPhotosVM, List<String>, String>(JobPhotosVM.new);

class JobPhotosVM extends FamilyNotifier<List<String>, String> {
  @override
  List<String> build(String arg) => const [];
  void add(String path) {
    if (state.length < 2) state = [...state, path];
  }
}

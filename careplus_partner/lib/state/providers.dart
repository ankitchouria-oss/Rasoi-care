// Riverpod wiring. The repository provider is the single place you change to
// go from mock data to a real backend.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Whether this device should get job-critical updates over WhatsApp —
/// a real, persisted device preference (see More tab), matching Urban
/// Company Partner's "Send WhatsApp updates" toggle. What it doesn't do,
/// because there's no WhatsApp Business API wired into this backend yet,
/// is actually deliver anything over WhatsApp — the preference is real,
/// the delivery channel behind it isn't built. Defaults to on, same as
/// UC's own default, until the real stored value (if any) loads.
final whatsappUpdatesProvider =
    NotifierProvider<WhatsAppUpdatesVM, bool>(WhatsAppUpdatesVM.new);

class WhatsAppUpdatesVM extends Notifier<bool> {
  static const _key = 'whatsapp_updates_enabled';

  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_key);
    if (stored != null) state = stored;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

/// The app's display language — a real, persisted device preference, not
/// just a menu row. Defaults to the device's own language when it's one we
/// support (English/Hindi today), else falls back to English, until the
/// real stored choice (if any) loads. Data that actually came from the
/// server — a customer's name, an address a technician typed — is never
/// translated; only this app's own UI chrome changes.
final localeProvider = NotifierProvider<LocaleVM, Locale>(LocaleVM.new);

const supportedLocales = [Locale('en'), Locale('hi')];

class LocaleVM extends Notifier<Locale> {
  static const _key = 'app_locale';

  @override
  Locale build() {
    _load();
    return const Locale('en');
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored != null) {
      final match = supportedLocales.where((l) => l.languageCode == stored);
      if (match.isNotEmpty) {
        state = match.first;
        return;
      }
    }
    final deviceCode = PlatformDispatcher.instance.locale.languageCode;
    final deviceMatch = supportedLocales.where((l) => l.languageCode == deviceCode);
    if (deviceMatch.isNotEmpty) state = deviceMatch.first;
  }

  Future<void> set(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.languageCode);
  }
}

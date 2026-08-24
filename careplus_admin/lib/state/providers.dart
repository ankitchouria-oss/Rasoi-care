// Riverpod wiring. The repository provider is the single place you change to
// go from mock data to a real backend.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/api_repository.dart';
import '../data/locations.dart';
import '../data/models.dart';

/// [ApiRepository] (see lib/data/api/api_repository.dart) is the sole
/// [AdminRepository] implementation — real data from the live backend, with
/// every getter nullable until its first fetch resolves. It's a
/// `ChangeNotifier` so screens watching this provider rebuild once
/// background fetches resolve, even though [AdminRepository]'s methods stay
/// synchronous.
final repositoryProvider = ChangeNotifierProvider<ApiRepository>(
  (ref) => ApiRepository(),
);

/// App-wide light/dark toggle. Persist to shared_preferences in production.
final themeModeProvider = NotifierProvider<ThemeModeVM, ThemeMode>(
  ThemeModeVM.new,
);

class ThemeModeVM extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;
  void toggle() =>
      state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  set(ThemeMode m) => state = m;
}

/// Which date range the Reports tab is currently showing.
final reportRangeProvider = NotifierProvider<ReportRangeVM, ReportRange>(
  ReportRangeVM.new,
);

class ReportRangeVM extends Notifier<ReportRange> {
  @override
  ReportRange build() => ReportRange.week;
  void set(ReportRange r) => state = r;
}

/// Which State/District the whole dashboard (Overview, Reports, Bookings,
/// Team) is currently scoped to — see lib/data/locations.dart.
final locationFilterProvider = NotifierProvider<LocationFilterVM, LocationFilter>(
  LocationFilterVM.new,
);

class LocationFilterVM extends Notifier<LocationFilter> {
  @override
  LocationFilter build() => LocationFilter(stateName: kStatesAndDistricts.keys.first);

  void setStateName(String stateName) => state = LocationFilter(stateName: stateName);

  void setDistrict(String? district) =>
      state = LocationFilter(stateName: state.stateName, district: district);
}

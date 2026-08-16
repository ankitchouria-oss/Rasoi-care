// Pick a service address with a real GPS pin — pushed from AddressScreen's
// "+ Add a new address" button. Two entirely different bodies live in this
// one screen, split by [MapsConfig.isConfigured]:
//
//   - not configured: today's level of address entry (a label + a free-text
//     line, no coordinates) — just moved into its own screen instead of
//     being a dead `onTap: () {}`, so the flow isn't a dead end while no
//     Maps key exists.
//   - configured: a draggable GoogleMap ("pan the map to place the pin"), a
//     Places Autocomplete search bar, and a "use my current location"
//     button — all via direct HTTP calls (google_maps_flutter's the only
//     Maps *package* dependency; Places/Geocoding are called the same way
//     BackendClient calls the Flask backend, see the file header there).
//
// Either way, confirming pops the screen with a [SavedAddress] the caller
// (AddressScreen) hands to BookingDraftVM.setPickedAddress.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../core/config/maps_config.dart';
import '../../core/widgets/care_widgets.dart';
import '../../data/models.dart';

class AddressPickerScreen extends StatelessWidget {
  const AddressPickerScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: context.pop),
          title: const Text('Add a new address'),
        ),
        body: SafeArea(
          top: false,
          child: MapsConfig.isConfigured ? const _MapPickerBody() : const _ManualEntryBody(),
        ),
      );
}

// ============================================================ FALLBACK
// No Maps key yet — a plain label + address-line form, styled like every
// other step in the booking flow.
class _ManualEntryBody extends StatefulWidget {
  const _ManualEntryBody();
  @override
  State<_ManualEntryBody> createState() => _ManualEntryBodyState();
}

class _ManualEntryBodyState extends State<_ManualEntryBody> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _line = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _line.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    final address = SavedAddress(
      'a_picked_${DateTime.now().millisecondsSinceEpoch}',
      _label.text.trim(),
      _line.text.trim(),
      '📍',
      // No map configured — no coordinates to attach. See SavedAddress's
      // doc comment in lib/data/models.dart.
    );
    context.pop(address);
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              children: [
                Text(
                  'Pinpoint map entry isn\'t set up yet on this build — add the address by hand for now.',
                  style: context.type.bodyMedium,
                ),
                const SizedBox(height: 20),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      CareField('Label — e.g. Home, Office',
                          controller: _label,
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Give it a label' : null),
                      const SizedBox(height: 14),
                      CareField('Full address',
                          controller: _line,
                          maxLines: 3,
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Enter the address' : null),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Dock(
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _confirm, child: const Text('Save address')),
            ),
          ),
        ],
      );
}

// ============================================================ MAP PICKER
// Only reachable once MapsConfig.isConfigured is true — every call here
// assumes a working API key.
class _MapPickerBody extends StatefulWidget {
  const _MapPickerBody();
  @override
  State<_MapPickerBody> createState() => _MapPickerBodyState();
}

class _MapPickerBodyState extends State<_MapPickerBody> {
  static const _timeout = Duration(seconds: 8);
  static const _fallbackCenter = LatLng(19.9975, 73.7898); // Nashik — same city as the mock addresses

  final _searchController = TextEditingController();
  GoogleMapController? _mapController;
  LatLng _center = _fallbackCenter;
  String? _resolvedLine;
  bool _resolving = false;
  bool _locating = false;
  List<_PlaceSuggestion> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Auto-locate on open instead of sitting on the fallback city center —
    // silent because a permission prompt or GPS miss on first load
    // shouldn't greet the person with an error before they've done anything.
    _useCurrentLocation(silent: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _resolving = true);
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '${point.latitude},${point.longitude}',
        'key': MapsConfig.apiKey,
      });
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          final results = decoded['results'];
          if (results is List && results.isNotEmpty) {
            final first = results.first;
            if (first is Map<String, dynamic>) {
              _resolvedLine = first['formatted_address'] as String?;
            }
          }
        }
      }
    } catch (_) {
      // Best-effort — the confirm button falls back to lat/lng text below.
    }
    if (mounted) setState(() => _resolving = false);
  }

  Future<void> _search(String query) async {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
          'input': query,
          'key': MapsConfig.apiKey,
        });
        final res = await http.get(uri).timeout(_timeout);
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) {
            final predictions = decoded['predictions'];
            if (predictions is List) {
              final parsed = predictions
                  .whereType<Map<String, dynamic>>()
                  .map(_PlaceSuggestion.fromJson)
                  .whereType<_PlaceSuggestion>()
                  .toList();
              if (mounted) setState(() => _suggestions = parsed);
              return;
            }
          }
        }
      } catch (_) {
        // Best-effort — an empty suggestion list just means no dropdown.
      }
      if (mounted) setState(() => _suggestions = []);
    });
  }

  Future<void> _selectSuggestion(_PlaceSuggestion s) async {
    setState(() {
      _suggestions = [];
      _searchController.text = s.description;
    });
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'place_id': s.placeId,
        'key': MapsConfig.apiKey,
      });
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          final results = decoded['results'];
          if (results is List && results.isNotEmpty) {
            final first = results.first as Map<String, dynamic>;
            final loc = first['geometry']?['location'];
            if (loc is Map<String, dynamic>) {
              final lat = (loc['lat'] as num?)?.toDouble();
              final lng = (loc['lng'] as num?)?.toDouble();
              if (lat != null && lng != null) {
                final point = LatLng(lat, lng);
                setState(() {
                  _center = point;
                  _resolvedLine = first['formatted_address'] as String? ?? s.description;
                });
                await _mapController?.animateCamera(CameraUpdate.newLatLng(point));
                return;
              }
            }
          }
        }
      }
    } catch (_) {
      // Best-effort — the pin just stays put if this fails.
    }
  }

  // [silent] is used for the automatic on-open attempt: permission prompts
  // still happen (so it can actually succeed), but a denial/failure just
  // quietly falls back to resolving an address for the default center
  // instead of greeting the person with an error before they've done
  // anything. An explicit tap on the location button always reports back.
  Future<void> _useCurrentLocation({bool silent = false}) async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Location permission denied — pan the map to place the pin instead.')));
        }
        if (silent) await _reverseGeocode(_center);
        return;
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Turn on location services, or pan the map to place the pin.')));
        }
        if (silent) await _reverseGeocode(_center);
        return;
      }
      final position = await Geolocator.getCurrentPosition().timeout(_timeout);
      final point = LatLng(position.latitude, position.longitude);
      setState(() => _center = point);
      await _mapController?.animateCamera(CameraUpdate.newLatLng(point));
      await _reverseGeocode(point);
    } catch (_) {
      // Degrade to manual pin placement — never dead-end the flow.
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Couldn\'t get your location — pan the map to place the pin instead.')));
      }
      if (silent) await _reverseGeocode(_center);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _confirm() {
    final line = _resolvedLine ??
        '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}';
    final address = SavedAddress(
      'a_picked_${DateTime.now().millisecondsSinceEpoch}',
      'New address',
      line,
      '📍',
      _center.latitude,
      _center.longitude,
    );
    context.pop(address);
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: CareField('Search for an area or landmark',
                controller: _searchController,
                prefix: const Icon(Icons.search),
                suffix: _locating
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(
                        icon: const Icon(Icons.my_location),
                        tooltip: 'Use my current location',
                        onPressed: _locating ? null : _useCurrentLocation,
                      ),
                onChanged: _search),
          ),
          if (_suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CareCard(
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final s in _suggestions)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined, size: 18),
                        title: Text(s.description, style: context.type.bodySmall),
                        onTap: () => _selectSuggestion(s),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _center, zoom: 16),
                  onMapCreated: (c) => _mapController = c,
                  onCameraMove: (pos) => _center = pos.target,
                  onCameraIdle: () => _reverseGeocode(_center),
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                ),
                // Fixed center pin — the map pans underneath it, so wherever
                // it points is the address being picked.
                IgnorePointer(
                  child: Icon(Icons.location_on, size: 42, color: context.scheme.primary,
                      shadows: const [Shadow(blurRadius: 6, color: Colors.black38)]),
                ),
                // A second, clearly-labelled way to re-center on GPS — the
                // search bar's icon is easy to miss, this one isn't.
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: FloatingActionButton.small(
                    heroTag: 'address-picker-locate-me',
                    onPressed: _locating ? null : () => _useCurrentLocation(),
                    tooltip: 'Use my current location',
                    child: _locating
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              'Pan the map to place the pin exactly on the entrance.',
              style: context.type.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          Dock(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_resolving)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Finding the address…', style: context.type.bodySmall),
                  )
                else if (_resolvedLine != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_resolvedLine!,
                        style: context.type.bodySmall, textAlign: TextAlign.center),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: _confirm, child: const Text('Confirm this location')),
                ),
              ],
            ),
          ),
        ],
      );
}

class _PlaceSuggestion {
  const _PlaceSuggestion(this.placeId, this.description);
  final String placeId;
  final String description;

  static _PlaceSuggestion? fromJson(Map<String, dynamic> json) {
    final placeId = json['place_id'] as String?;
    final description = json['description'] as String?;
    if (placeId == null || description == null) return null;
    return _PlaceSuggestion(placeId, description);
  }
}

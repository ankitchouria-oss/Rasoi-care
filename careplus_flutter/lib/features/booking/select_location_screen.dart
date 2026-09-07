// A single "Select your location" screen, reused verbatim by both the Home
// screen's "Serving" header and the booking flow's "Where should we come?"
// step — previously two different, much thinner UIs (a 2-line bottom sheet
// on Home, an inline CareCard list in the booking step). Always pops with
// the chosen [SavedAddress]; callers apply the result however fits their
// context (Home sets homeAddressOverrideProvider, the booking step calls
// BookingDraftVM.setAddress/setPickedAddress).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/widgets/care_widgets.dart';
import '../../data/models.dart';
import '../../l10n/l10n_extensions.dart';
import '../../state/firestore_providers.dart';
import '../../state/providers.dart';
import 'address_picker_screen.dart';

class SelectLocationScreen extends ConsumerStatefulWidget {
  const SelectLocationScreen({super.key, this.currentId});

  /// The address id to show as "SELECTED", if the caller has one already
  /// (Home's [selectedAddressIdProvider], or the booking draft's
  /// addressId) — null shows no address as selected.
  final String? currentId;

  @override
  ConsumerState<SelectLocationScreen> createState() => _SelectLocationScreenState();
}

class _SelectLocationScreenState extends ConsumerState<SelectLocationScreen> {
  Position? _myPosition;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  // Best-effort and silent — this only powers the "110 m away" distance
  // labels, so a denied permission or disabled GPS just means those don't
  // show, never an error the person didn't ask for.
  Future<void> _loadPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() => _myPosition = last);
        return;
      }
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.reduced),
      ).timeout(const Duration(seconds: 5));
      if (mounted) setState(() => _myPosition = fresh);
    } catch (_) {
      // No distance labels — the list still works fine without them.
    }
  }

  String? _distanceLabel(SavedAddress a) {
    final pos = _myPosition;
    if (pos == null || a.lat == null || a.lng == null) return null;
    final meters = Geolocator.distanceBetween(pos.latitude, pos.longitude, a.lat!, a.lng!);
    return meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Future<void> _useCurrentLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.selectLocationPermissionDenied)));
        }
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.selectLocationServiceDisabled)));
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      final resolved = await resolveAreaLine(position.latitude, position.longitude);
      if (!mounted) return;
      final address = await Navigator.of(context).push<SavedAddress>(
        MaterialPageRoute(
          builder: (_) => AddressDetailsScreen(
              lat: position.latitude, lng: position.longitude, resolvedArea: resolved),
        ),
      );
      if (address != null && mounted) Navigator.pop(context, address);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.selectLocationLocationError)));
      }
    }
  }

  Future<void> _addNewAddress() async {
    final address = await Navigator.of(context).push<SavedAddress>(
      MaterialPageRoute(builder: (_) => const AddressPickerScreen()),
    );
    if (address != null && mounted) Navigator.pop(context, address);
  }

  Future<void> _delete(SavedAddress a) async {
    final t = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.selectLocationRemoveTitle),
        content: Text(t.selectLocationRemoveBody(a.label)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(t.selectLocationCancel)),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(t.selectLocationRemove)),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ref.read(userProfileServiceProvider).deleteAddress(a.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.selectLocationRemoveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final addresses = ref.watch(savedAddressesProvider);
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        title: Text(t.selectLocationTitle),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
          children: [
            GestureDetector(
              onTap: _addNewAddress,
              child: AbsorbPointer(
                child: CareField(t.selectLocationSearchHint,
                    prefix: const Icon(Icons.search), suffix: const SizedBox.shrink()),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.my_location,
                  label: t.selectLocationUseCurrentLocation,
                  onTap: _useCurrentLocation,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickAction(
                  icon: Icons.add_location_alt_outlined,
                  label: t.selectLocationAddNewAddress,
                  onTap: _addNewAddress,
                ),
              ),
            ]),
            const SizedBox(height: 22),
            if (addresses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  t.selectLocationEmptyState,
                  style: context.type.bodySmall,
                ),
              )
            else ...[
              Eyebrow(t.selectLocationSavedAddresses),
              const SizedBox(height: 10),
              CareCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < addresses.length; i++)
                      _AddressRow(
                        address: addresses[i],
                        selected: addresses[i].id == widget.currentId,
                        distance: _distanceLabel(addresses[i]),
                        last: i == addresses.length - 1,
                        onTap: () => Navigator.pop(context, addresses[i]),
                        onDelete: () => _delete(addresses[i]),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CareCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: context.scheme.primary, size: 22),
            const SizedBox(height: 10),
            Text(label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.25)),
          ],
        ),
      );
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.address,
    required this.selected,
    required this.distance,
    required this.last,
    required this.onTap,
    required this.onDelete,
  });
  final SavedAddress address;
  final bool selected;
  final String? distance;
  final bool last;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: context.care.hairline)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: context.scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10)),
                child: Text(address.glyph, style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(address.label,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      if (distance != null) ...[
                        const SizedBox(width: 8),
                        Text(distance!,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: context.care.inkMuted)),
                      ],
                      if (selected) ...[
                        const SizedBox(width: 8),
                        StatusChip(context.l10n.selectLocationSelectedChip,
                            tone: ChipTone.success, height: 20),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(address.line,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: context.type.bodySmall),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_vert, size: 18),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      );
}

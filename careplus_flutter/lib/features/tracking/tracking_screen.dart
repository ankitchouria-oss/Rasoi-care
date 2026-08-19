import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/config/maps_config.dart';
import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/firebase/technician_location_service.dart';
import '../../data/models.dart';
import '../../state/firestore_providers.dart';
import '../../state/providers.dart';

/// Real backend status order — mirrors kBookingStatusOrder in the Partner
/// app (app.py enforces the same progression server-side).
const _statusOrder = ['Requested', 'Accepted', 'On the way', 'In Progress', 'Completed'];

class TrackingScreen extends ConsumerWidget {
  const TrackingScreen({super.key, required this.bookingId});
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(bookingsRefreshProvider);
    final repo = ref.watch(repositoryProvider);
    final booking = repo.bookingById(bookingId);

    // The real assigned technician's Firebase uid (and the booking's own
    // address coordinates), when this is a real backend-sourced booking.
    // Deliberately technicianFirebaseUid, not technicianId — see Booking's
    // doc comment for why those differ.
    final technicianFirebaseUid = booking?.technicianFirebaseUid;
    final liveLocation = (MapsConfig.isConfigured && technicianFirebaseUid != null)
        ? ref.watch(technicianLocationProvider(technicianFirebaseUid)).valueOrNull
        : null;

    final stepIndex = booking == null ? 0 : _statusOrder.indexOf(booking.rawStatus);
    final cancelled = booking?.status == BookingStatus.cancelled;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/')),
        title: const Text('Live tracking'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          children: [
            _TrackingMap(booking: booking, liveLocation: liveLocation),
            const SizedBox(height: 16),
            CareCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow('Status'),
                  const SizedBox(height: 4),
                  Text(
                      cancelled
                          ? 'Cancelled'
                          : (booking?.rawStatus.isNotEmpty ?? false)
                              ? booking!.rawStatus
                              : 'Requested',
                      style: CareType.mono(context.scheme.onSurface,
                          size: 20, w: FontWeight.w600)),
                  if (booking != null) ...[
                    const SizedBox(height: 3),
                    Text('${booking.title} · ${booking.addressLabel}',
                        style: context.type.bodySmall),
                  ],
                ],
              ),
            ),
            if (!cancelled) ...[
              const SizedBox(height: 12),
              CareCard(
                child: Row(children: [
                  Icon(Icons.person_outline, color: context.care.inkFaint, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        stepIndex >= 1
                            ? 'A technician has been assigned to your job.'
                            : "We're finding a technician for you.",
                        style: context.type.bodySmall),
                  ),
                ]),
              ),
            ],
            const SectionHeader('Progress'),
            if (booking == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Loading your booking…', style: context.type.bodySmall),
              )
            else if (cancelled)
              StepDot(TimelineStepView(
                  'Booking cancelled', booking.whenLabel, TrackState.done),
                  last: true)
            else ...[
              StepDot(TimelineStepView(
                  'Booking confirmed', booking.whenLabel, TrackState.done)),
              for (var i = 1; i < _statusOrder.length; i++)
                StepDot(
                  TimelineStepView(
                    _statusOrder[i] == 'Accepted'
                        ? 'Technician assigned'
                        : _statusOrder[i],
                    '',
                    i < stepIndex
                        ? TrackState.done
                        : i == stepIndex
                            ? TrackState.now
                            : TrackState.upcoming,
                  ),
                  last: i == _statusOrder.length - 1,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The map area at the top of the tracking screen. Renders a real live
/// `GoogleMap` only once [MapsConfig.isConfigured] and a technician
/// position has actually arrived over Firestore — every other case (no
/// Maps key, no location doc yet) falls back to a static placeholder so
/// this never looks broken or blank while Maps isn't set up.
class _TrackingMap extends StatelessWidget {
  const _TrackingMap({required this.booking, required this.liveLocation});
  final Booking? booking;
  final TechnicianLocation? liveLocation;

  @override
  Widget build(BuildContext context) {
    if (MapsConfig.isConfigured && liveLocation != null) {
      final techPoint = LatLng(liveLocation!.lat, liveLocation!.lng);
      final customerPoint =
          (booking?.lat != null && booking?.lng != null)
              ? LatLng(booking!.lat!, booking!.lng!)
              : null;
      return ClipRRect(
        borderRadius: Radii.rLg,
        child: SizedBox(
          height: 210,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: techPoint, zoom: 14),
            markers: {
              Marker(
                markerId: const MarkerId('technician'),
                position: techPoint,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                infoWindow: const InfoWindow(title: 'Your technician'),
              ),
              if (customerPoint != null)
                Marker(
                  markerId: const MarkerId('customer'),
                  position: customerPoint,
                  infoWindow: const InfoWindow(title: 'Your address'),
                ),
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            liteModeEnabled: true,
          ),
        ),
      );
    }
    // Placeholder — unchanged from before this feature existed.
    return Container(
      height: 210,
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainerHigh,
        borderRadius: Radii.rLg,
        border: Border.all(color: context.care.hairline),
      ),
      child: Center(
        child: Icon(Icons.map_outlined, size: 44, color: context.care.inkFaint),
      ),
    );
  }
}

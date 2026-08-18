import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/maps_config.dart';
import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/api/api_repository.dart';
import '../../data/firebase/technician_upload_service.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

class TechJobScreen extends ConsumerStatefulWidget {
  const TechJobScreen({super.key, required this.jobId});
  final String jobId;
  @override
  ConsumerState<TechJobScreen> createState() => _TechJobScreenState();
}

class _TechJobScreenState extends ConsumerState<TechJobScreen> {
  int _elapsedSecs = 84; // 01:24 — matches the on-site timer already running
  Timer? _t;
  bool _advancing = false;

  // ---- job-tracking map (only ever used when MapsConfig.isConfigured) ----
  GoogleMapController? _mapController;
  LatLng? _myLocation;
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsedSecs++);
    });
    if (MapsConfig.isConfigured) {
      _refreshMyLocation();
      _locationTimer =
          Timer.periodic(const Duration(seconds: 15), (_) => _refreshMyLocation());
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshMyLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 8));
      if (!mounted) return;
      final point = LatLng(pos.latitude, pos.longitude);
      setState(() => _myLocation = point);
      await _mapController?.animateCamera(CameraUpdate.newLatLng(point));
    } catch (_) {
      // Best-effort — the map just shows the destination alone.
    }
  }

  /// Opens the phone's own Google Maps app for turn-by-turn directions
  /// (falls back to a plain maps search URL if that's not available, or if
  /// this booking has no real coordinates — only a label-only address).
  Future<void> _openNavigation(JobDetail job) async {
    var launched = false;
    if (job.lat != null && job.lng != null) {
      try {
        launched = await launchUrl(
          Uri.parse('google.navigation:q=${job.lat},${job.lng}&mode=d'),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        launched = false;
      }
    }
    if (!launched) {
      final query = (job.lat != null && job.lng != null)
          ? '${job.lat},${job.lng}'
          : Uri.encodeComponent(job.addressLine);
      try {
        launched = await launchUrl(
          Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        launched = false;
      }
    }
    if (!launched && mounted) _toast(context, 'Could not open navigation.');
  }

  String get _clock {
    final m = _elapsedSecs ~/ 60, s = _elapsedSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Label for the dock's primary button, driven by the job's real status
  /// when this is a known live booking (see `ApiRepository.statusOf`);
  /// `null` covers mock/local jobs, which keep the original single-step
  /// flow straight into the invoice screen.
  String _primaryLabel(String? liveStatus) => switch (liveStatus) {
        'Requested' => 'Accept job',
        'Accepted' => 'On my way',
        'On the way' => 'Arrived — start job',
        _ => 'Complete and invoice', // In Progress, Completed, null (mock)
      };

  Future<void> _handlePrimaryAction(String? liveStatus, JobDetail job) async {
    if (liveStatus == null || liveStatus == 'Completed') {
      context.push('/tech/job/${widget.jobId}/close');
      return;
    }
    // Completing the job — this is the one real chance to record suction
    // readings for the customer's invoice, so ask before advancing. Chimney
    // jobs get the richer airflow (CFM) screen instead of the plain dialog.
    (int?, int?) suction = (null, null);
    if (liveStatus == 'In Progress') {
      final repo = ref.read(repositoryProvider);
      final category = repo is ApiRepository ? repo.categoryOf(widget.jobId) : null;
      suction = category == 'RasoiAir'
          ? await _askAirflowReadings(job)
          : await _askSuctionReadings();
    }
    await _advanceStatus(suctionBefore: suction.$1, suctionAfter: suction.$2);
    if (liveStatus == 'In Progress' && mounted) {
      context.push('/tech/job/${widget.jobId}/close');
    }
  }

  Future<(int?, int?)> _askAirflowReadings(JobDetail job) async {
    final result = await context.push<(int, int)>(
      '/tech/job/${widget.jobId}/airflow',
      extra: (job.customerName, job.addressLine),
    );
    return result ?? (null, null);
  }

  Future<(int?, int?)> _askSuctionReadings() async {
    final beforeCtrl = TextEditingController();
    final afterCtrl = TextEditingController();
    final result = await showDialog<(int?, int?)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Suction readings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Optional — shown on the customer\'s invoice.',
                style: Theme.of(dialogContext).textTheme.bodySmall),
            const SizedBox(height: 14),
            TextField(
              controller: beforeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Before (m³/hr)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: afterCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'After (m³/hr)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop((null, null)),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop((
              int.tryParse(beforeCtrl.text),
              int.tryParse(afterCtrl.text),
            )),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result ?? (null, null);
  }

  Future<void> _advanceStatus({int? suctionBefore, int? suctionAfter}) async {
    setState(() => _advancing = true);
    final repo = ref.read(repositoryProvider);
    if (repo is ApiRepository) {
      final ok = await repo.advanceJob(widget.jobId,
          suctionBefore: suctionBefore, suctionAfter: suctionAfter);
      if (ok) {
        ref.read(jobsFeedTickProvider.notifier).bump();
      } else if (mounted) {
        _toast(context, 'Could not update status — check connection');
      }
    }
    if (mounted) setState(() => _advancing = false);
  }

  // Opens the real device camera (not a fake "fills a box in" counter) and,
  // on a successful capture, records it in the matching before/after
  // provider and best-effort uploads it to Firebase Storage under this
  // job — mirroring TechnicianUploadService's use during signup. Upload
  // failure never blocks the technician; the local capture already
  // satisfied the checklist requirement.
  Future<void> _capturePhoto(bool isBefore) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked == null || !mounted) return;
    final vm = ref.read((isBefore ? techBeforePhotosProvider : techAfterPhotosProvider)(widget.jobId).notifier);
    vm.add(picked.path);
    final kind = '${isBefore ? 'before' : 'after'}_${DateTime.now().millisecondsSinceEpoch}';
    unawaited(TechnicianUploadService().upload(File(picked.path), kind: '${widget.jobId}_$kind'));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(jobsFeedTickProvider); // rebuild once a real fetch/action lands
    final repo = ref.watch(repositoryProvider);
    final job = repo.jobDetail(widget.jobId);
    final liveStatus = repo is ApiRepository ? repo.statusOf(widget.jobId) : null;
    final checklist = ref.watch(techChecklistProvider(widget.jobId));
    final checklistVM = ref.read(techChecklistProvider(widget.jobId).notifier);
    final beforePhotos = ref.watch(techBeforePhotosProvider(widget.jobId));
    final afterPhotos = ref.watch(techAfterPhotosProvider(widget.jobId));
    final doneCount = checklist.where((c) => c.checked).length;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: Text(widget.jobId),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: StatusChip(_clock, height: 30)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  CareCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Blob(job.customerInitials),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(job.customerName,
                                  style: const TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text('${job.addressLine}\n${job.directions}',
                                  style: context.type.bodySmall!.copyWith(height: 1.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (MapsConfig.isConfigured && job.lat != null && job.lng != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: Radii.rMd,
                      child: SizedBox(
                        height: 160,
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                              target: _myLocation ?? LatLng(job.lat!, job.lng!), zoom: 14),
                          onMapCreated: (c) => _mapController = c,
                          markers: {
                            Marker(
                              markerId: const MarkerId('destination'),
                              position: LatLng(job.lat!, job.lng!),
                              infoWindow: InfoWindow(title: job.customerName),
                            ),
                            if (_myLocation != null)
                              Marker(
                                markerId: const MarkerId('me'),
                                position: _myLocation!,
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                    BitmapDescriptor.hueAzure),
                                infoWindow: const InfoWindow(title: 'You'),
                              ),
                          },
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.95,
                    children: [
                      _ActionTile(
                          glyph: '🧭',
                          label: 'Navigate',
                          onTap: () => _openNavigation(job)),
                      _ActionTile(
                          glyph: '📞',
                          label: 'Call',
                          onTap: () => _toast(context, 'Calling — masked')),
                      _ActionTile(
                          glyph: '💬',
                          label: 'Chat',
                          onTap: () => _toast(context, 'Opening chat')),
                      _ActionTile(
                          glyph: '⚑',
                          label: 'Escalate',
                          onTap: () => _toast(context, 'Escalated to ops')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CareCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow('Customer reported'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final tag in job.reportedTags)
                              StatusChip(tag, tone: ChipTone.danger, height: 28),
                          ],
                        ),
                        const SizedBox(height: 11),
                        Text('"${job.reportedQuote}"',
                            style: context.type.bodySmall!.copyWith(height: 1.55)),
                        const SizedBox(height: 12),
                        Row(children: [
                          _thumb(context),
                          const SizedBox(width: 8),
                          _thumb(context),
                        ]),
                      ],
                    ),
                  ),
                  SectionHeader('Checklist',
                      trailing: Mono('$doneCount / ${checklist.length}',
                          color: context.care.inkMuted)),
                  CareCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (var i = 0; i < checklist.length; i++)
                          _ChecklistRow(
                            item: checklist[i],
                            onTap: () => checklistVM.toggle(i),
                            last: i == checklist.length - 1,
                          ),
                      ],
                    ),
                  ),
                  const SectionHeader('Photos'),
                  Text('Before and after are mandatory', style: context.type.bodySmall),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1,
                    children: [
                      for (var i = 0; i < 2; i++)
                        _photoBox(context,
                            label: 'Before',
                            imagePath: i < beforePhotos.length ? beforePhotos[i] : null,
                            onTap: i == beforePhotos.length ? () => _capturePhoto(true) : null),
                      for (var i = 0; i < 2; i++)
                        _photoBox(context,
                            label: 'After',
                            imagePath: i < afterPhotos.length ? afterPhotos[i] : null,
                            onTap: i == afterPhotos.length ? () => _capturePhoto(false) : null),
                    ],
                  ),
                  SectionHeader('Parts used',
                      trailing: GestureDetector(
                        onTap: () => _toast(context, 'Scan part barcode'),
                        child: Text('Scan',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.scheme.primary)),
                      )),
                  for (final part in job.parts) ...[
                    CareCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(part.name,
                                        style: const TextStyle(
                                            fontSize: 13, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 3),
                                    Text('SKU ${part.sku} · qty ${part.qty}',
                                        style: context.type.bodySmall),
                                  ],
                                ),
                              ),
                              Text(Money.rupees(part.pricePaise),
                                  style: CareType.mono(context.scheme.onSurface, size: 13)),
                            ],
                          ),
                          if (part.approved) ...[
                            const Divider(height: 22),
                            StatusChip('Customer approved ${part.approvedAt}',
                                tone: ChipTone.success, height: 26),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _toast(context, 'Quote sent for approval'),
                      child: const Text('+ Add a part and send quote'),
                    ),
                  ),
                ],
              ),
            ),
            Dock(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      _advancing ? null : () => _handlePrimaryAction(liveStatus, job),
                  child: _advancing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_primaryLabel(liveStatus)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Widget _thumb(BuildContext context) => Container(
        width: 62,
        height: 62,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.scheme.surfaceContainerHigh,
          borderRadius: Radii.rSm,
          border: Border.all(color: context.care.hairline),
        ),
        child: Icon(Icons.image_outlined, color: context.care.inkFaint, size: 20),
      );

  Widget _photoBox(BuildContext context,
      {required String label, String? imagePath, VoidCallback? onTap}) {
    final filled = imagePath != null;
    final content = ClipRRect(
      borderRadius: Radii.rMd,
      child: Container(
        decoration: BoxDecoration(
          color: filled ? context.scheme.primaryContainer : context.scheme.surfaceContainerHigh,
          border: Border.all(color: context.care.hairline),
        ),
        child: filled
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(imagePath), fit: BoxFit.cover),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Icon(Icons.check_circle,
                        size: 16, color: context.scheme.primary, shadows: const [
                      Shadow(color: Colors.black45, blurRadius: 3),
                    ]),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, size: 18, color: context.care.inkFaint),
                  const SizedBox(height: 4),
                  Text(label, style: TextStyle(fontSize: 10.5, color: context.care.inkFaint)),
                ],
              ),
      ),
    );
    return onTap == null ? content : Pressable(onTap: onTap, scale: 0.94, child: content);
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.glyph, required this.label, required this.onTap});
  final String glyph, label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.94,
        child: Container(
          decoration: BoxDecoration(
            color: context.scheme.surface,
            borderRadius: Radii.rMd,
            border: Border.all(color: context.care.hairline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(glyph, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.item, required this.onTap, required this.last});
  final ChecklistItem item;
  final VoidCallback onTap;
  final bool last;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: context.care.hairline)),
          ),
          child: Row(children: [
            Icon(item.checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
                color: item.checked ? context.care.success : context.care.inkFaint),
            const SizedBox(width: 12),
            Expanded(
              child: Text(item.label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: item.checked
                          ? context.scheme.onSurface
                          : context.care.inkMuted)),
            ),
          ]),
        ),
      );
}

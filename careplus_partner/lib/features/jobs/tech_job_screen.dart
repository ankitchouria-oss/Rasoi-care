import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
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

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsedSecs++);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String get _clock {
    final m = _elapsedSecs ~/ 60, s = _elapsedSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(repositoryProvider).jobDetail(widget.jobId);
    final checklist = ref.watch(techChecklistProvider(widget.jobId));
    final checklistVM = ref.read(techChecklistProvider(widget.jobId).notifier);
    final afterPhotos = ref.watch(techAfterPhotosProvider(widget.jobId));
    final afterPhotosVM = ref.read(techAfterPhotosProvider(widget.jobId).notifier);
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
                          onTap: () => _toast(context, 'Opening Google Maps')),
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
                      _photoBox(context, label: 'Before', filled: true),
                      _photoBox(context, label: 'Before', filled: true),
                      _photoBox(context,
                          label: 'After',
                          filled: afterPhotos > 0,
                          onTap: afterPhotos < 2
                              ? () {
                                  afterPhotosVM.capture();
                                  _toast(context, 'Camera');
                                }
                              : null),
                      _photoBox(context,
                          label: 'After',
                          filled: afterPhotos > 1,
                          onTap: afterPhotos < 2
                              ? () {
                                  afterPhotosVM.capture();
                                  _toast(context, 'Camera');
                                }
                              : null),
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
                  onPressed: () => context.push('/tech/job/${widget.jobId}/close'),
                  child: const Text('Complete and invoice'),
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
      {required String label, required bool filled, VoidCallback? onTap}) {
    final content = Container(
      decoration: BoxDecoration(
        color: filled ? context.scheme.primaryContainer : context.scheme.surfaceContainerHigh,
        borderRadius: Radii.rMd,
        border: Border.all(color: context.care.hairline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(filled ? Icons.check_circle : Icons.add_a_photo_outlined,
              size: 18,
              color: filled ? context.scheme.primary : context.care.inkFaint),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10.5, color: context.care.inkFaint)),
        ],
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

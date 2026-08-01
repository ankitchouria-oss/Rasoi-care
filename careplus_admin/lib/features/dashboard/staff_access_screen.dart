import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

class StaffAccessScreen extends ConsumerStatefulWidget {
  const StaffAccessScreen({super.key});
  @override
  ConsumerState<StaffAccessScreen> createState() => _StaffAccessScreenState();
}

class _StaffAccessScreenState extends ConsumerState<StaffAccessScreen> {
  late List<StaffAccount> _staff;
  var _loaded = false;

  ChipTone _statusTone(StaffStatus s) => switch (s) {
        StaffStatus.active => ChipTone.success,
        StaffStatus.invited => ChipTone.warning,
        StaffStatus.suspended => ChipTone.danger,
      };

  String _statusLabel(StaffStatus s) => switch (s) {
        StaffStatus.active => 'Active',
        StaffStatus.invited => 'Invited',
        StaffStatus.suspended => 'Suspended',
      };

  void _toggleSuspend(int i) {
    setState(() {
      final s = _staff[i];
      final next = s.status == StaffStatus.suspended ? StaffStatus.active : StaffStatus.suspended;
      _staff[i] = StaffAccount(
        name: s.name,
        initials: s.initials,
        phone: s.phone,
        role: s.role,
        status: next,
        lastActive: next == StaffStatus.suspended ? 'Suspended just now' : 'Reinstated just now',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      _staff = [...ref.read(repositoryProvider).staffAccounts()];
      _loaded = true;
    }
    final activeCount = _staff.where((s) => s.status == StaffStatus.active).length;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: const Text('Staff & access'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          children: [
            Row(children: [
              Expanded(child: _Kpi(label: 'Active accounts', value: '$activeCount / ${_staff.length}')),
              const SizedBox(width: 10),
              Expanded(
                  child: _Kpi(
                      label: 'Owners',
                      value: '${_staff.where((s) => s.role == AdminRole.owner).length}')),
            ]),
            const SectionHeader('Accounts'),
            Stagger(children: [
              for (var i = 0; i < _staff.length; i++)
                CareCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Blob(_staff[i].initials, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(_staff[i].name,
                                    style: const TextStyle(
                                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                              ),
                              StatusChip(_staff[i].role.label,
                                  tone: _staff[i].role == AdminRole.owner
                                      ? ChipTone.selected
                                      : ChipTone.neutral,
                                  height: 22),
                            ]),
                            const SizedBox(height: 4),
                            Text('+91 ${_staff[i].phone} · ${_staff[i].lastActive}',
                                style: context.type.bodySmall),
                            const SizedBox(height: 8),
                            Row(children: [
                              StatusChip(_statusLabel(_staff[i].status),
                                  tone: _statusTone(_staff[i].status), height: 24),
                              const Spacer(),
                              if (_staff[i].role != AdminRole.owner)
                                GestureDetector(
                                  onTap: () => _toggleSuspend(i),
                                  child: Text(
                                      _staff[i].status == StaffStatus.suspended
                                          ? 'Reinstate'
                                          : 'Suspend',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _staff[i].status == StaffStatus.suspended
                                              ? context.care.success
                                              : context.scheme.error)),
                                ),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Invite link sent by SMS (demo)'))),
                child: const Text('+ Invite a staff member'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => CareCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(label),
            const SizedBox(height: 6),
            Text(value,
                style: CareType.mono(context.scheme.onSurface, size: 21, w: FontWeight.w600)),
          ],
        ),
      );
}

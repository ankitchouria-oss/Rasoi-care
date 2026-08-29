// Shared "assign a technician to this unassigned booking" flow — used from
// both the Bookings queue's detail sheet and the Overview tab's "Needs
// attention" list, so there's exactly one place this dropdown-and-PATCH
// logic lives.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

Future<void> showAssignTechnicianSheet(
  BuildContext context, {
  required String bookingId,
  required String jobTitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AssignTechnicianSheet(bookingId: bookingId, jobTitle: jobTitle),
  );
}

class _AssignTechnicianSheet extends ConsumerStatefulWidget {
  const _AssignTechnicianSheet({required this.bookingId, required this.jobTitle});
  final String bookingId;
  final String jobTitle;

  @override
  ConsumerState<_AssignTechnicianSheet> createState() => _AssignTechnicianSheetState();
}

class _AssignTechnicianSheetState extends ConsumerState<_AssignTechnicianSheet> {
  String? _selectedId;
  bool _submitting = false;

  Future<void> _assign(List<AdminTeamMember> options) async {
    final id = _selectedId;
    if (id == null) return;
    setState(() => _submitting = true);
    final repo = ref.read(repositoryProvider);
    final ok = await repo.assignTechnician(widget.bookingId, id);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't assign — check your connection and try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    // Only technicians the platform has actually verified — an unverified
    // applicant isn't real routing-ready yet, same gate as auto-routing.
    final options = repo.team()?.where((t) => t.verified && t.id != null).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: context.care.hairline, borderRadius: Radii.pill),
            ),
          ),
          const Text('Assign a technician',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(widget.jobTitle, style: context.type.bodySmall),
          const SizedBox(height: 18),
          if (options == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (options.isEmpty)
            const EmptyState(
              glyph: '◌',
              title: 'No verified technicians yet',
              body: 'Verify a technician on the Team tab before you can assign a job.',
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedId,
              decoration: const InputDecoration(labelText: 'Technician'),
              items: [
                for (final t in options)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text('${t.name} · ${t.specialties}'),
                  ),
              ],
              onChanged: (v) => setState(() => _selectedId = v),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selectedId == null || _submitting ? null : () => _assign(options),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text('Assign'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

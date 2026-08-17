// Self-signup application — modelled directly on Urban Company's Partner
// app "Tell us about yourself" screen: name (validated), a work-category
// dropdown, a city dropdown, and a terms checkbox before continuing, plus
// (on later steps, collapsed into one screen here) an ID document and
// payout bank + PAN details. All reviewed by an admin before the
// technician is verified and starts appearing in the real job feed — see
// TechPendingScreen for what happens right after submitting.
//
// Also reused for editing an already-submitted application (see
// TechProfileScreen's "Edit" action) — [existing] prefills every field from
// the technician's current record, and a re-picked photo/ID document is the
// only thing that overwrites what's already on file; everything else is
// just a normal field update via the same PATCH /api/technician/me call.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/auth/auth_service.dart';
import '../../state/auth_providers.dart';

const _categories = [
  ('RasoiAir', 'Chimney'),
  ('RasoiSpark', 'Hob / Cooktop'),
  ('RasoiWash', 'Dishwasher'),
  ('RasoiBuilt', 'Microwave / OTG'),
  ('RasoiChill', 'Refrigerator'),
  ('RasoiPure', 'Water purifier'),
];

// The cities Rasoi Care actually operates in today — same idea as UC's city
// picker, just a real (short) list instead of a free-text field, so a typo
// can't put someone in an area nobody's routing jobs for.
const _cities = ['Nashik', 'Pune', 'Mumbai', 'Nagpur', 'Aurangabad'];

final _nameCharsRe = RegExp(r'^[A-Za-z ]*$');

class TechApplyScreen extends ConsumerStatefulWidget {
  const TechApplyScreen({super.key, this.existing});
  final Map<String, dynamic>? existing;
  @override
  ConsumerState<TechApplyScreen> createState() => _TechApplyScreenState();
}

class _TechApplyScreenState extends ConsumerState<TechApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.existing?['name'] as String? ?? '');
  late final _experienceCtrl = TextEditingController(
      text: widget.existing?['experienceYears'] != null
          ? '${widget.existing!['experienceYears']}'
          : '');
  late final _bankNameCtrl =
      TextEditingController(text: widget.existing?['bankAccountName'] as String? ?? '');
  late final _bankAccountCtrl =
      TextEditingController(text: widget.existing?['bankAccountNumber'] as String? ?? '');
  late final _bankIfscCtrl =
      TextEditingController(text: widget.existing?['bankIfsc'] as String? ?? '');
  late final _panCtrl =
      TextEditingController(text: widget.existing?['panNumber'] as String? ?? '');
  late final _gstCtrl =
      TextEditingController(text: widget.existing?['gstNumber'] as String? ?? '');
  late final _aadharCtrl =
      TextEditingController(text: widget.existing?['aadharNumber'] as String? ?? '');
  late final _dobCtrl =
      TextEditingController(text: widget.existing?['dateOfBirth'] as String? ?? '');
  late final _emergencyNameCtrl =
      TextEditingController(text: widget.existing?['emergencyContactName'] as String? ?? '');
  late final _emergencyPhoneCtrl =
      TextEditingController(text: widget.existing?['emergencyContactPhone'] as String? ?? '');
  late final _addressCtrl =
      TextEditingController(text: widget.existing?['address'] as String? ?? '');
  late final _upiCtrl = TextEditingController(text: widget.existing?['upiId'] as String? ?? '');
  late String? _category = widget.existing?['category'] as String?;
  late String? _city = _cities.contains(widget.existing?['area'])
      ? widget.existing!['area'] as String
      : null;
  late final String? _existingPhotoUrl = widget.existing?['photoUrl'] as String?;
  late final String? _existingAadharDocumentUrl =
      widget.existing?['aadharDocumentUrl'] as String?;
  late final String? _existingPanDocumentUrl = widget.existing?['panDocumentUrl'] as String?;
  File? _photo;
  File? _aadharDocument;
  File? _panDocument;
  bool _agreedToTerms = false;
  bool _submitting = false;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _experienceCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankAccountCtrl.dispose();
    _bankIfscCtrl.dispose();
    _panCtrl.dispose();
    _gstCtrl.dispose();
    _aadharCtrl.dispose();
    _dobCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    _addressCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_dobCtrl.text) ?? DateTime(now.year - 25);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 80),
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (picked != null) {
      setState(() => _dobCtrl.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _photo = File(picked.path));
  }

  Future<void> _pickAadharDocument() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _aadharDocument = File(picked.path));
  }

  Future<void> _pickPanDocument() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _panDocument = File(picked.path));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_category == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick what work you do.')));
      return;
    }
    if (_city == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick where you live.')));
      return;
    }
    if (!_isEditing && !_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Accept the Terms & conditions to continue.')));
      return;
    }
    if (_aadharDocument == null && _existingAadharDocumentUrl == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Upload a photo of your Aadhaar card.')));
      return;
    }
    if (_panDocument == null && _existingPanDocumentUrl == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Upload a photo of your PAN card.')));
      return;
    }
    if (_addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter your address.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final uploadService = ref.read(technicianUploadServiceProvider);
      // Only re-upload what was actually re-picked — omitting a key from the
      // PATCH body leaves that field (and whatever's already on file)
      // untouched, see app.py's update_technician_me.
      final photoUrl =
          _photo == null ? null : await uploadService.upload(_photo!, kind: 'photo');
      final aadharDocumentUrl = _aadharDocument == null
          ? null
          : await uploadService.upload(_aadharDocument!, kind: 'aadhar_document');
      final panDocumentUrl = _panDocument == null
          ? null
          : await uploadService.upload(_panDocument!, kind: 'pan_document');
      final result = await submitTechnicianApplication({
        'name': _nameCtrl.text.trim(),
        'category': _category,
        'area': _city,
        'address': _addressCtrl.text.trim(),
        'experienceYears': int.tryParse(_experienceCtrl.text.trim()),
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (aadharDocumentUrl != null) 'aadharDocumentUrl': aadharDocumentUrl,
        if (panDocumentUrl != null) 'panDocumentUrl': panDocumentUrl,
        'bankAccountName': _bankNameCtrl.text.trim(),
        'bankAccountNumber': _bankAccountCtrl.text.trim(),
        'bankIfsc': _bankIfscCtrl.text.trim(),
        'upiId': _upiCtrl.text.trim(),
        'panNumber': _panCtrl.text.trim().toUpperCase(),
        'gstNumber': _gstCtrl.text.trim().toUpperCase(),
        'aadharNumber': _aadharCtrl.text.trim(),
        'dateOfBirth': _dobCtrl.text.trim(),
        'emergencyContactName': _emergencyNameCtrl.text.trim(),
        'emergencyContactPhone': _emergencyPhoneCtrl.text.trim(),
        'submit': true,
      });
      if (!mounted) return;
      ref.read(technicianMeProvider.notifier).state = result;
      if (_isEditing) {
        Navigator.of(context).pop();
      } else {
        routeToStage(context, stageFromTechnicianJson(result));
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit profile' : 'Complete your application')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (!_isEditing)
                Container(
                  width: double.infinity,
                  color: CareColors.brass.withValues(alpha: 0.16),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Text('A few more steps to start getting jobs and earnings!',
                      style: context.type.bodySmall!.copyWith(fontWeight: FontWeight.w700)),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    if (!_isEditing) ...[
                      Text('Tell us about yourself!', style: context.type.headlineLarge),
                      const SizedBox(height: 20),
                    ],
                    Center(
                      child: GestureDetector(
                        onTap: _pickPhoto,
                        child: CircleAvatar(
                          radius: 44,
                          backgroundColor: context.scheme.surfaceContainerHigh,
                          backgroundImage: _photo != null
                              ? FileImage(_photo!)
                              : (_existingPhotoUrl != null
                                  ? NetworkImage(_existingPhotoUrl)
                                  : null) as ImageProvider?,
                          child: _photo == null && _existingPhotoUrl == null
                              ? Icon(Icons.add_a_photo_outlined,
                                  color: context.care.inkFaint, size: 28)
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                        child: Text('Profile photo — tap to change', style: context.type.bodySmall)),
                    const SizedBox(height: 22),
                    Eyebrow("What's your name?"),
                    const SizedBox(height: 8),
                    CareField('Full name',
                        controller: _nameCtrl,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Enter your name';
                          if (!_nameCharsRe.hasMatch(v)) {
                            return 'Special characters like !@#\$%^&*()_-+={}::;~,. are not allowed';
                          }
                          return null;
                        }),
                    const SizedBox(height: 18),
                    Eyebrow('What work do you do?'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      hint: const Text('Select your trade'),
                      items: [
                        for (final c in _categories)
                          DropdownMenuItem(value: c.$1, child: Text(c.$2)),
                      ],
                      onChanged: (v) => setState(() => _category = v),
                    ),
                    const SizedBox(height: 18),
                    Eyebrow('Where do you live?'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _city,
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      hint: const Text('Select city'),
                      items: [
                        for (final c in _cities) DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => setState(() => _city = v),
                    ),
                    const SizedBox(height: 13),
                    CareField('Years of experience',
                        controller: _experienceCtrl,
                        keyboardType: TextInputType.number,
                        validator: (v) => (v == null || int.tryParse(v.trim()) == null)
                            ? 'Enter a number'
                            : null),
                    const SizedBox(height: 24),
                    _SectionCard(
                      icon: Icons.badge_outlined,
                      title: 'Aadhaar card',
                      child: Column(
                        children: [
                          CareField('Aadhaar number',
                              controller: _aadharCtrl, keyboardType: TextInputType.number),
                          const SizedBox(height: 13),
                          _DocPickerRow(
                            label: _aadharDocument != null
                                ? _aadharDocument!.path.split('/').last
                                : (_existingAadharDocumentUrl != null
                                    ? 'Uploaded — tap to replace'
                                    : 'Upload a photo of your Aadhaar card'),
                            onTap: _pickAadharDocument,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      icon: Icons.credit_card_outlined,
                      title: 'PAN card',
                      child: Column(
                        children: [
                          CareField('PAN number', controller: _panCtrl),
                          const SizedBox(height: 13),
                          _DocPickerRow(
                            label: _panDocument != null
                                ? _panDocument!.path.split('/').last
                                : (_existingPanDocumentUrl != null
                                    ? 'Uploaded — tap to replace'
                                    : 'Upload a photo of your PAN card'),
                            onTap: _pickPanDocument,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      icon: Icons.home_outlined,
                      title: 'Address',
                      child: CareField('Full address',
                          controller: _addressCtrl, maxLines: 3),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      icon: Icons.account_balance_outlined,
                      title: 'Bank & payout details',
                      child: Column(
                        children: [
                          CareField('Account holder name', controller: _bankNameCtrl),
                          const SizedBox(height: 13),
                          CareField('Account number',
                              controller: _bankAccountCtrl, keyboardType: TextInputType.number),
                          const SizedBox(height: 13),
                          CareField('IFSC code', controller: _bankIfscCtrl),
                          const SizedBox(height: 13),
                          CareField('UPI ID (optional)',
                              controller: _upiCtrl,
                              keyboardType: TextInputType.emailAddress,
                              prefix: const Icon(Icons.alternate_email, size: 18)),
                          const SizedBox(height: 13),
                          CareField('GST number (optional)', controller: _gstCtrl),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Eyebrow('Personal details'),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _pickDob,
                      child: AbsorbPointer(
                        child: CareField('Date of birth (optional)', controller: _dobCtrl),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Eyebrow('Emergency contact (optional)'),
                    const SizedBox(height: 10),
                    CareField('Contact name', controller: _emergencyNameCtrl),
                    const SizedBox(height: 13),
                    CareField('Contact phone number',
                        controller: _emergencyPhoneCtrl, keyboardType: TextInputType.phone),
                    if (!_isEditing) ...[
                      const SizedBox(height: 22),
                      CareCard(
                        color: context.scheme.surfaceContainerHigh,
                        borderColor: Colors.transparent,
                        onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
                        child: Row(children: [
                          Checkbox(
                            value: _agreedToTerms,
                            onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                          ),
                          Expanded(
                            child: Text(
                                'By proceeding, you agree to Rasoi Care\'s Terms & conditions and Privacy policy',
                                style: context.type.bodySmall),
                          ),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
              Dock(
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isEditing ? 'Save changes' : 'Continue'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled card wrapping a related group of fields — used to give the KYC
/// document sections (Aadhaar/PAN/Address/Bank) clearer visual separation
/// than a flat scroll of labels, without the risk of a full multi-step
/// wizard rewrite.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => CareCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: context.scheme.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );
}

class _DocPickerRow extends StatelessWidget {
  const _DocPickerRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: Radii.rMd,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: Radii.rMd,
            border: Border.all(color: context.care.hairline),
          ),
          child: Row(children: [
            Icon(Icons.add_a_photo_outlined, size: 18, color: context.scheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: context.type.bodySmall)),
            Icon(Icons.chevron_right, size: 18, color: context.care.inkMuted),
          ]),
        ),
      );
}


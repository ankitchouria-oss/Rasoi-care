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
  late String? _category = widget.existing?['category'] as String?;
  late String? _city = _cities.contains(widget.existing?['area'])
      ? widget.existing!['area'] as String
      : null;
  late final String? _existingPhotoUrl = widget.existing?['photoUrl'] as String?;
  late final String? _existingIdDocumentUrl = widget.existing?['idDocumentUrl'] as String?;
  File? _photo;
  File? _idDocument;
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

  Future<void> _pickIdDocument() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _idDocument = File(picked.path));
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
    if (_idDocument == null && _existingIdDocumentUrl == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Upload an ID document.')));
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
      final idDocumentUrl = _idDocument == null
          ? null
          : await uploadService.upload(_idDocument!, kind: 'id_document');
      final result = await submitTechnicianApplication({
        'name': _nameCtrl.text.trim(),
        'category': _category,
        'area': _city,
        'experienceYears': int.tryParse(_experienceCtrl.text.trim()),
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (idDocumentUrl != null) 'idDocumentUrl': idDocumentUrl,
        'bankAccountName': _bankNameCtrl.text.trim(),
        'bankAccountNumber': _bankAccountCtrl.text.trim(),
        'bankIfsc': _bankIfscCtrl.text.trim(),
        'panNumber': _panCtrl.text.trim().toUpperCase(),
        'gstNumber': _gstCtrl.text.trim().toUpperCase(),
        'aadharNumber': _aadharCtrl.text.trim(),
        'dateOfBirth': _dobCtrl.text.trim(),
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
                    const SizedBox(height: 22),
                    Eyebrow('ID document'),
                    const SizedBox(height: 10),
                    CareCard(
                      onTap: _pickIdDocument,
                      child: Row(children: [
                        Icon(Icons.badge_outlined, color: context.scheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                              _idDocument != null
                                  ? _idDocument!.path.split('/').last
                                  : (_existingIdDocumentUrl != null
                                      ? 'Uploaded — tap to replace'
                                      : 'Upload Aadhaar, PAN or other government ID'),
                              style: context.type.bodyMedium),
                        ),
                        Icon(Icons.chevron_right, color: context.care.inkMuted),
                      ]),
                    ),
                    const SizedBox(height: 22),
                    Eyebrow('Financial details'),
                    const SizedBox(height: 10),
                    CareField('GST number (optional)', controller: _gstCtrl),
                    const SizedBox(height: 13),
                    CareField('PAN number', controller: _panCtrl),
                    const SizedBox(height: 13),
                    CareField('Account holder name', controller: _bankNameCtrl),
                    const SizedBox(height: 13),
                    CareField('Account number',
                        controller: _bankAccountCtrl, keyboardType: TextInputType.number),
                    const SizedBox(height: 13),
                    CareField('IFSC code', controller: _bankIfscCtrl),
                    const SizedBox(height: 22),
                    Eyebrow('Personal details'),
                    const SizedBox(height: 10),
                    CareField('Aadhaar number (optional)',
                        controller: _aadharCtrl, keyboardType: TextInputType.number),
                    const SizedBox(height: 13),
                    GestureDetector(
                      onTap: _pickDob,
                      child: AbsorbPointer(
                        child: CareField('Date of birth (optional)', controller: _dobCtrl),
                      ),
                    ),
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


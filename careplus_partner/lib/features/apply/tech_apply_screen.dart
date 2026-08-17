// Self-signup application — modelled on Urban Company's Partner app flow:
// profile photo + name, service category + area, experience, an ID
// document, and payout bank details, all reviewed by an admin before the
// technician is verified and starts appearing in the real job feed. See
// TechPendingScreen for what happens right after submitting.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/widgets/care_widgets.dart';
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

class TechApplyScreen extends ConsumerStatefulWidget {
  const TechApplyScreen({super.key});
  @override
  ConsumerState<TechApplyScreen> createState() => _TechApplyScreenState();
}

class _TechApplyScreenState extends ConsumerState<TechApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _bankIfscCtrl = TextEditingController();
  String? _category;
  File? _photo;
  File? _idDocument;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _areaCtrl.dispose();
    _experienceCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankAccountCtrl.dispose();
    _bankIfscCtrl.dispose();
    super.dispose();
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
          .showSnackBar(const SnackBar(content: Text('Pick a service category.')));
      return;
    }
    if (_idDocument == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Upload an ID document.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final uploadService = ref.read(technicianUploadServiceProvider);
      final photoUrl =
          _photo == null ? null : await uploadService.upload(_photo!, kind: 'photo');
      final idDocumentUrl = await uploadService.upload(_idDocument!, kind: 'id_document');
      final result = await submitTechnicianApplication({
        'name': _nameCtrl.text.trim(),
        'category': _category,
        'area': _areaCtrl.text.trim(),
        'experienceYears': int.tryParse(_experienceCtrl.text.trim()),
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (idDocumentUrl != null) 'idDocumentUrl': idDocumentUrl,
        'bankAccountName': _bankNameCtrl.text.trim(),
        'bankAccountNumber': _bankAccountCtrl.text.trim(),
        'bankIfsc': _bankIfscCtrl.text.trim(),
        'submit': true,
      });
      if (!mounted) return;
      routeToStage(context, stageFromTechnicianJson(result));
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
      appBar: AppBar(title: const Text('Complete your application')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    Text(
                        'A few details so we can verify you and get you routed real jobs — same as Urban Company\'s partner review.',
                        style: context.type.bodyMedium),
                    const SizedBox(height: 20),
                    Center(
                      child: GestureDetector(
                        onTap: _pickPhoto,
                        child: CircleAvatar(
                          radius: 44,
                          backgroundColor: context.scheme.surfaceContainerHigh,
                          backgroundImage: _photo != null ? FileImage(_photo!) : null,
                          child: _photo == null
                              ? Icon(Icons.add_a_photo_outlined,
                                  color: context.care.inkFaint, size: 28)
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                        child: Text('Profile photo', style: context.type.bodySmall)),
                    const SizedBox(height: 22),
                    CareField('Full name',
                        controller: _nameCtrl,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Enter your name' : null),
                    const SizedBox(height: 18),
                    Eyebrow('Service category'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in _categories)
                          ChoiceChip(
                            label: Text(c.$2),
                            selected: _category == c.$1,
                            onSelected: (_) => setState(() => _category = c.$1),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    CareField('Service area — e.g. Nashik',
                        controller: _areaCtrl,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Enter your service area' : null),
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
                              _idDocument == null
                                  ? 'Upload Aadhaar, PAN or other government ID'
                                  : _idDocument!.path.split('/').last,
                              style: context.type.bodyMedium),
                        ),
                        Icon(Icons.chevron_right, color: context.care.inkMuted),
                      ]),
                    ),
                    const SizedBox(height: 22),
                    Eyebrow('Payout bank details'),
                    const SizedBox(height: 10),
                    CareField('Account holder name', controller: _bankNameCtrl),
                    const SizedBox(height: 13),
                    CareField('Account number',
                        controller: _bankAccountCtrl, keyboardType: TextInputType.number),
                    const SizedBox(height: 13),
                    CareField('IFSC code', controller: _bankIfscCtrl),
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
                        : const Text('Submit application'),
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

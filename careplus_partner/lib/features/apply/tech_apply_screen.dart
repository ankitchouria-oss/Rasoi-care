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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/auth/auth_service.dart';
import '../../l10n/l10n_extensions.dart';
import '../../state/auth_providers.dart';
import 'aadhaar_ocr.dart';

/// IFSC decodes to a bank + branch via Razorpay's free, public, no-key-
/// needed lookup — real-time confirmation that a typo'd code gets caught
/// before submitting, not a substitute for actual account-ownership
/// verification (that needs a paid penny-drop KYC vendor this app doesn't
/// have credentials for).
final _ifscFormatRe = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');

const _categoryOptions = [
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

/// A technician can be skilled in more than one appliance category, so this
/// prefills from the new `categories` list the backend returns; a record
/// saved before that existed only has the old single `category` field.
Set<String> _initialCategories(Map<String, dynamic>? existing) {
  final raw = existing?['categories'];
  if (raw is List && raw.isNotEmpty) {
    return raw.map((e) => e.toString()).toSet();
  }
  final single = existing?['category'] as String?;
  return single == null || single.isEmpty ? {} : {single};
}

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
  late final Set<String> _categories = _initialCategories(widget.existing);
  late String? _city = _cities.contains(widget.existing?['area'])
      ? widget.existing!['area'] as String
      : null;
  late final String? _existingPhotoUrl = widget.existing?['photoUrl'] as String?;
  late final String? _existingAadharDocumentUrl =
      widget.existing?['aadharDocumentUrl'] as String?;
  late final String? _existingAadharDocumentBackUrl =
      widget.existing?['aadharDocumentBackUrl'] as String?;
  late final String? _existingPanDocumentUrl = widget.existing?['panDocumentUrl'] as String?;
  late final String? _existingPassbookUrl = widget.existing?['bankPassbookUrl'] as String?;
  File? _photo;
  File? _aadharDocument;
  File? _aadharDocumentBack;
  File? _panDocument;
  File? _passbookDocument;
  bool _agreedToTerms = false;
  bool _submitting = false;
  bool _addressAutofilled = false;
  Timer? _ifscDebounce;
  String? _ifscBankBranch;
  bool _ifscLookupFailed = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _bankIfscCtrl.addListener(_onIfscChanged);
    if (_ifscFormatRe.hasMatch(_bankIfscCtrl.text.trim().toUpperCase())) {
      _lookupIfsc(_bankIfscCtrl.text.trim().toUpperCase());
    }
  }

  void _onIfscChanged() {
    _ifscDebounce?.cancel();
    final code = _bankIfscCtrl.text.trim().toUpperCase();
    if (!_ifscFormatRe.hasMatch(code)) {
      if (_ifscBankBranch != null || _ifscLookupFailed) {
        setState(() {
          _ifscBankBranch = null;
          _ifscLookupFailed = false;
        });
      }
      return;
    }
    _ifscDebounce = Timer(const Duration(milliseconds: 500), () => _lookupIfsc(code));
  }

  Future<void> _lookupIfsc(String code) async {
    try {
      final res = await http
          .get(Uri.parse('https://ifsc.razorpay.com/$code'))
          .timeout(const Duration(seconds: 6));
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() {
          _ifscBankBranch = null;
          _ifscLookupFailed = true;
        });
        return;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final bank = body['BANK'] as String?;
      final branch = body['BRANCH'] as String?;
      setState(() {
        _ifscLookupFailed = false;
        _ifscBankBranch =
            [bank, branch].where((s) => s != null && s.isNotEmpty).join(' — ');
      });
    } catch (_) {
      // No network / lookup service unreachable — not a reason to block
      // submission, just no confirmation shown for now.
    }
  }

  @override
  void dispose() {
    _ifscDebounce?.cancel();
    _bankIfscCtrl.removeListener(_onIfscChanged);
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

  /// The address (and the QR code) is printed on the Aadhaar card's *back*,
  /// not the front — so this is also the photo the OCR autofill in
  /// [_tryAutofillAddress] reads from.
  Future<void> _pickAadharDocumentBack() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final file = File(picked.path);
    setState(() => _aadharDocumentBack = file);
    await _tryAutofillAddress(file);
  }

  /// Runs on-device OCR against the just-picked Aadhaar back photo and, if
  /// it can find an address-shaped block of text, prefills the address
  /// field with it — always still editable, never silently trusted (see
  /// aadhaar_ocr.dart for why).
  Future<void> _tryAutofillAddress(File file) async {
    final address = await extractAddressFromImage(file);
    if (!mounted || address == null || address.isEmpty) return;
    setState(() {
      _addressCtrl.text = address;
      _addressAutofilled = true;
    });
  }

  Future<void> _pickPanDocument() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _panDocument = File(picked.path));
  }

  Future<void> _pickPassbookDocument() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _passbookDocument = File(picked.path));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final t = context.l10n;
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.applyPickCategory)));
      return;
    }
    if (_city == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.applyPickCity)));
      return;
    }
    if (!_isEditing && !_agreedToTerms) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.applyAcceptTerms)));
      return;
    }
    if (_aadharDocument == null && _existingAadharDocumentUrl == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.applyUploadAadhaar)));
      return;
    }
    if (_aadharDocumentBack == null && _existingAadharDocumentBackUrl == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.applyUploadAadhaarBack)));
      return;
    }
    if (_panDocument == null && _existingPanDocumentUrl == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.applyUploadPan)));
      return;
    }
    if (_addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.applyEnterAddress)));
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
      final aadharDocumentBackUrl = _aadharDocumentBack == null
          ? null
          : await uploadService.upload(_aadharDocumentBack!, kind: 'aadhar_document_back');
      final panDocumentUrl = _panDocument == null
          ? null
          : await uploadService.upload(_panDocument!, kind: 'pan_document');
      final passbookUrl = _passbookDocument == null
          ? null
          : await uploadService.upload(_passbookDocument!, kind: 'bank_passbook');
      final fields = {
        'name': _nameCtrl.text.trim(),
        'categories': _categories.toList(),
        'area': _city,
        'address': _addressCtrl.text.trim(),
        'experienceYears': int.tryParse(_experienceCtrl.text.trim()),
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (aadharDocumentUrl != null) 'aadharDocumentUrl': aadharDocumentUrl,
        if (aadharDocumentBackUrl != null) 'aadharDocumentBackUrl': aadharDocumentBackUrl,
        if (panDocumentUrl != null) 'panDocumentUrl': panDocumentUrl,
        if (passbookUrl != null) 'bankPassbookUrl': passbookUrl,
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
      };
      final result = await _submitApplication(fields);
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

  /// A 401 here almost always means [bootstrapTechnicianBackend] never
  /// actually created this technician's row — most likely it silently
  /// timed out against a cold-starting backend right after sign-in (Render
  /// free tier can take well past the original 8-second bootstrap timeout
  /// to wake up). Rather than stranding someone who just filled out the
  /// whole KYC form behind a generic error, retry the bootstrap once and
  /// resubmit before giving up for real.
  Future<Map<String, dynamic>> _submitApplication(Map<String, dynamic> fields) async {
    try {
      return await submitTechnicianApplication(fields);
    } on TechnicianProfileMissingException {
      final bootstrapped = await bootstrapTechnicianBackend();
      if (bootstrapped == null) {
        throw const AuthException(
            "Couldn't verify your sign-in — please sign out and sign in again.");
      }
      return submitTechnicianApplication(fields);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? t.applyEditTitle : t.applyTitle)),
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
                  child: Text(t.applyStepsBanner,
                      style: context.type.bodySmall!.copyWith(fontWeight: FontWeight.w700)),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    if (!_isEditing) ...[
                      Text(t.applyIntro, style: context.type.headlineLarge),
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
                        child: Text(t.applyPhotoHint, style: context.type.bodySmall)),
                    const SizedBox(height: 22),
                    Eyebrow(t.applyNameQuestion),
                    const SizedBox(height: 8),
                    CareField(t.applyFullName,
                        controller: _nameCtrl,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return t.applyNameRequired;
                          if (!_nameCharsRe.hasMatch(v)) {
                            return t.applyNameInvalid;
                          }
                          return null;
                        }),
                    const SizedBox(height: 18),
                    Eyebrow(t.applyWorkQuestion),
                    const SizedBox(height: 4),
                    Text(t.applySelectTrade, style: context.type.bodySmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in _categoryOptions)
                          FilterChip(
                            label: Text(c.$2),
                            selected: _categories.contains(c.$1),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _categories.add(c.$1);
                              } else {
                                _categories.remove(c.$1);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Eyebrow(t.applyLiveQuestion),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _city,
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      hint: Text(t.applySelectCity),
                      items: [
                        for (final c in _cities) DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => setState(() => _city = v),
                    ),
                    const SizedBox(height: 13),
                    CareField(t.applyExperience,
                        controller: _experienceCtrl,
                        keyboardType: TextInputType.number,
                        validator: (v) => (v == null || int.tryParse(v.trim()) == null)
                            ? t.applyExperienceError
                            : null),
                    const SizedBox(height: 24),
                    _SectionCard(
                      icon: Icons.badge_outlined,
                      title: t.applyAadhaarCard,
                      child: Column(
                        children: [
                          CareField(t.applyAadhaarNumber,
                              controller: _aadharCtrl, keyboardType: TextInputType.number),
                          const SizedBox(height: 13),
                          _DocPickerRow(
                            label: _aadharDocument != null
                                ? _aadharDocument!.path.split('/').last
                                : (_existingAadharDocumentUrl != null
                                    ? t.applyAadhaarFrontUploaded
                                    : t.applyAadhaarFrontUpload),
                            onTap: _pickAadharDocument,
                          ),
                          const SizedBox(height: 10),
                          _DocPickerRow(
                            label: _aadharDocumentBack != null
                                ? _aadharDocumentBack!.path.split('/').last
                                : (_existingAadharDocumentBackUrl != null
                                    ? t.applyAadhaarBackUploaded
                                    : t.applyAadhaarBackUpload),
                            onTap: _pickAadharDocumentBack,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      icon: Icons.credit_card_outlined,
                      title: t.applyPanCard,
                      child: Column(
                        children: [
                          CareField(t.applyPanNumber, controller: _panCtrl),
                          const SizedBox(height: 13),
                          _DocPickerRow(
                            label: _panDocument != null
                                ? _panDocument!.path.split('/').last
                                : (_existingPanDocumentUrl != null
                                    ? t.applyPanUploaded
                                    : t.applyPanUpload),
                            onTap: _pickPanDocument,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      icon: Icons.home_outlined,
                      title: t.applyAddress,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CareField(t.applyFullAddress,
                              controller: _addressCtrl, maxLines: 3),
                          if (_addressAutofilled) ...[
                            const SizedBox(height: 8),
                            Text(t.applyAddressAutofilled,
                                style: context.type.bodySmall!
                                    .copyWith(color: context.care.success)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      icon: Icons.account_balance_outlined,
                      title: t.applyBankDetails,
                      child: Column(
                        children: [
                          CareField(t.applyAccountHolder, controller: _bankNameCtrl),
                          const SizedBox(height: 13),
                          CareField(t.applyAccountNumber,
                              controller: _bankAccountCtrl, keyboardType: TextInputType.number),
                          const SizedBox(height: 13),
                          CareField(t.applyIfsc, controller: _bankIfscCtrl),
                          if (_ifscBankBranch != null) ...[
                            const SizedBox(height: 6),
                            Text(_ifscBankBranch!,
                                style: context.type.bodySmall!
                                    .copyWith(color: context.care.success)),
                          ] else if (_ifscLookupFailed) ...[
                            const SizedBox(height: 6),
                            Text(t.applyIfscNotFound,
                                style: context.type.bodySmall!
                                    .copyWith(color: context.scheme.error)),
                          ],
                          const SizedBox(height: 13),
                          CareField(t.applyUpi,
                              controller: _upiCtrl,
                              keyboardType: TextInputType.emailAddress,
                              prefix: const Icon(Icons.alternate_email, size: 18)),
                          const SizedBox(height: 13),
                          CareField(t.applyGst, controller: _gstCtrl),
                          const SizedBox(height: 13),
                          _DocPickerRow(
                            label: _passbookDocument != null
                                ? _passbookDocument!.path.split('/').last
                                : (_existingPassbookUrl != null
                                    ? t.applyPassbookUploaded
                                    : t.applyPassbookUpload),
                            onTap: _pickPassbookDocument,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Eyebrow(t.applyPersonalDetails),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _pickDob,
                      child: AbsorbPointer(
                        child: CareField(t.applyDob, controller: _dobCtrl),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Eyebrow(t.applyEmergencyContact),
                    const SizedBox(height: 10),
                    CareField(t.applyContactName, controller: _emergencyNameCtrl),
                    const SizedBox(height: 13),
                    CareField(t.applyContactPhone,
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
                            child: Text(t.applyTermsText, style: context.type.bodySmall),
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
                        : Text(_isEditing ? t.applySaveChanges : t.applyContinue),
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


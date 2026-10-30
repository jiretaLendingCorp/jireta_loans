// lib/presentation/features/lender/profile/widgets/lender_details_dialogs.dart
//
// Mga popup para sa Lender Profile (Personal Details / Email / Residence
// Address). Pindot lang sa section title at dito lalabas ang existing details
// — pwede agad i-edit at i-save, walang card at walang dropdown arrow.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../../../../shared/widgets/security/email_change_otp_dialog.dart';
import '../providers/lender_profile_provider.dart';

Future<void> showLenderPersonalDetailsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _LenderPersonalDetailsDialog(),
  );
}

Future<void> showLenderEmailDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _LenderEmailDialog(),
  );
}

Future<void> showLenderAddressDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _LenderAddressDialog(),
  );
}

// ── Shared dialog shell ─────────────────────────────────────────────────────

class _LenderDialogShell extends StatelessWidget {
  final String title;
  final Widget child;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _LenderDialogShell({
    required this.title,
    required this.child,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.cSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.cTextPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: saving ? null : onCancel,
                    icon: Icon(Icons.close_rounded,
                        size: 20, color: context.cTextTertiary),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              child,
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: saving ? null : onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.cTextSecondary,
                          side: BorderSide(color: context.cBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: FilledButton(
                        onPressed: saving ? null : onSave,
                        style: FilledButton.styleFrom(
                          backgroundColor: context.cBrandBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Save',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Personal Details ────────────────────────────────────────────────────────

class _LenderPersonalDetailsDialog extends ConsumerStatefulWidget {
  const _LenderPersonalDetailsDialog();

  @override
  ConsumerState<_LenderPersonalDetailsDialog> createState() =>
      _LenderPersonalDetailsDialogState();
}

class _LenderPersonalDetailsDialogState
    extends ConsumerState<_LenderPersonalDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();

  static const _genderOptions = ['Male', 'Female', 'Prefer not to say'];
  static const _civilOptions = ['Single', 'Married', 'Widowed', 'Separated'];

  String? _gender;
  String? _civilStatus;
  DateTime? _dob;
  String? _dobError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(lenderProfileProvider).user;
    if (user != null) {
      _firstNameCtrl.text = user.firstName;
      _middleNameCtrl.text = user.middleName ?? '';
      _lastNameCtrl.text = user.lastName;
      _phoneCtrl.text = user.phoneNumber ?? '';
      _gender = _normalizeOption(user.gender, _genderOptions, aliases: {
        'other': 'Prefer not to say',
        'prefer_not_to_say': 'Prefer not to say',
      });
      _civilStatus = _normalizeOption(user.civilStatus, _civilOptions);
      _dob = user.dateOfBirth;
      if (_dob != null) {
        _dobCtrl.text = DateFormat('yyyy-MM-dd').format(_dob!);
      }
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  static String _toDbEnum(String value) {
    final v = value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '_');
    if (v == 'prefer_not_to_say') return 'other';
    return v;
  }

  static String? _normalizeOption(
    String? value,
    List<String> options, {
    Map<String, String>? aliases,
  }) {
    if (value == null || value.isEmpty) return null;
    final key = value.trim().toLowerCase();
    if (aliases != null && aliases.containsKey(key)) {
      final target = aliases[key]!;
      return options.contains(target) ? target : null;
    }
    for (final opt in options) {
      if (opt.toLowerCase().replaceAll(RegExp(r'[\s-]'), '_') == key) {
        return opt;
      }
    }
    return null;
  }

  String? Function(String?) _required(String label) =>
      (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1990),
      firstDate: DateTime(1920),
      lastDate: DateTime.now().subtract(const Duration(days: 6570)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.lenderBlue,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
        _dobError = null;
      });
    }
  }

  Future<void> _save() async {
    setState(
        () => _dobError = _dob == null ? 'Date of birth is required' : null);
    final formOk = _formKey.currentState!.validate();
    if (!formOk || _dob == null) {
      setState(() {});
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (_gender == null || _civilStatus == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please select your gender and civil status.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final ok = await ref.read(lenderProfileProvider.notifier).updateProfile({
      'first_name': _firstNameCtrl.text.trim(),
      'last_name': _lastNameCtrl.text.trim(),
      if (_middleNameCtrl.text.trim().isNotEmpty)
        'middle_name': _middleNameCtrl.text.trim(),
      'lender_profile': {
        'gender': _toDbEnum(_gender!),
        'civil_status': _toDbEnum(_civilStatus!),
        'dob': DateFormat('yyyy-MM-dd').format(_dob!),
      },
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(ref.read(lenderProfileProvider).error ??
              'Failed to update profile. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Personal details updated.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _LenderDialogShell(
      title: 'Personal Details',
      saving: _saving,
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: 'First Name',
              controller: _firstNameCtrl,
              minimal: true,
              maxLength: 100,
              validator: _required('First name'),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Middle Name (optional)',
              controller: _middleNameCtrl,
              minimal: true,
              maxLength: 100,
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Last Name',
              controller: _lastNameCtrl,
              minimal: true,
              maxLength: 100,
              validator: _required('Last name'),
            ),
            const SizedBox(height: 16),
            _MinimalDropdown(
              label: 'Gender',
              value: _gender,
              hint: 'Select gender',
              items: _genderOptions
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: 16),
            _MinimalDropdown(
              label: 'Civil Status',
              value: _civilStatus,
              hint: 'Select civil status',
              items: _civilOptions
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _civilStatus = v),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Date of Birth',
              controller: _dobCtrl,
              minimal: true,
              readOnly: true,
              onTap: _pickDate,
              hint: 'Tap to select',
            ),
            if (_dobError != null) ...[
              const SizedBox(height: 4),
              Text(
                _dobError!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ],
            const SizedBox(height: 16),
            // Phone ang login credential ng lender — hindi ito ini-edit dito
            // (kapareho ng dating Edit Personal Information screen).
            AppTextField(
              label: 'Phone Number',
              controller: _phoneCtrl,
              minimal: true,
              readOnly: true,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Email ───────────────────────────────────────────────────────────────────

class _LenderEmailDialog extends ConsumerStatefulWidget {
  const _LenderEmailDialog();

  @override
  ConsumerState<_LenderEmailDialog> createState() => _LenderEmailDialogState();
}

class _LenderEmailDialogState extends ConsumerState<_LenderEmailDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final raw = (ref.read(lenderProfileProvider).user?.email ?? '').trim();
    // `${phone}@jireta.temp` = internal GoTrue credential lang ng phone login.
    _emailCtrl.text = raw.toLowerCase().endsWith('@jireta.temp') ? '' : raw;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  /// Opsyonal ang email (phone ang login), pero kapag may nilagay dapat valid.
  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return null;
    final ok = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(value);
    return ok ? null : 'Enter a valid email address';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final email = _emailCtrl.text.trim().toLowerCase();
    final notifier = ref.read(lenderProfileProvider.notifier);

    // Blangko = alisin ang email (phone naman ang tunay na login ng lender),
    // kaya walang address na mapapatunayan — direktang update pa rin ito.
    if (email.isEmpty) {
      setState(() => _saving = true);
      final ok = await notifier.updateProfile({'email': ''});
      if (!mounted) return;
      setState(() => _saving = false);
      if (!ok) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ref.read(lenderProfileProvider).error ??
                'Failed to update email. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Email removed.'),
          backgroundColor: AppColors.success,
        ),
      );
      return;
    }

    final current = (ref.read(lenderProfileProvider).user?.email ?? '')
        .trim()
        .toLowerCase();
    if (email == current) {
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Email unchanged.'),
          backgroundColor: AppColors.success,
        ),
      );
      return;
    }

    // (1) 6-digit code sa BAGONG email — hindi pa nagbabago ang account.
    setState(() => _saving = true);
    final sendError = await notifier.requestEmailChange(email);
    if (!mounted) return;
    setState(() => _saving = false);
    if (sendError != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(sendError),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // (2) Dito lang isinusulat ng server ang bagong email pagkatapos ng code.
    final verified = await showEmailChangeOtpDialog(
      context,
      email: email,
      onVerify: (otp) => notifier.confirmEmailChange(email: email, otp: otp),
      onResend: () => notifier.requestEmailChange(email),
    );
    if (!mounted) return;
    if (!verified) return;

    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Email updated and verified.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _LenderDialogShell(
      title: 'Email',
      saving: _saving,
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      child: Form(
        key: _formKey,
        child: AppTextField(
          label: 'Email Address',
          controller: _emailCtrl,
          minimal: true,
          keyboardType: TextInputType.emailAddress,
          maxLength: 150,
          validator: _validateEmail,
        ),
      ),
    );
  }
}

// ── Residence Address ───────────────────────────────────────────────────────

class _LenderAddressDialog extends ConsumerStatefulWidget {
  const _LenderAddressDialog();

  @override
  ConsumerState<_LenderAddressDialog> createState() =>
      _LenderAddressDialogState();
}

class _LenderAddressDialogState extends ConsumerState<_LenderAddressDialog> {
  final _formKey = GlobalKey<FormState>();
  final _streetCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(lenderProfileProvider).user;
    if (user != null) {
      _streetCtrl.text = user.streetAddress ?? '';
      _barangayCtrl.text = user.barangay ?? '';
      _cityCtrl.text = user.city ?? '';
      _provinceCtrl.text = user.province ?? '';
      _zipCtrl.text = user.zipCode ?? '';
    }
  }

  @override
  void dispose() {
    _streetCtrl.dispose();
    _barangayCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    _zipCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final ok = await ref.read(lenderProfileProvider.notifier).updateProfile({
      'street_address': _streetCtrl.text.trim(),
      'barangay': _barangayCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'province': _provinceCtrl.text.trim(),
      'zip_code': _zipCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(ref.read(lenderProfileProvider).error ??
              'Failed to update address. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Residence address updated.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _LenderDialogShell(
      title: 'Residence Address',
      saving: _saving,
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: 'Street Address',
              controller: _streetCtrl,
              minimal: true,
              maxLength: 100,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Barangay',
              controller: _barangayCtrl,
              minimal: true,
              maxLength: 100,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'City / Municipality',
              controller: _cityCtrl,
              minimal: true,
              maxLength: 100,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Province',
              controller: _provinceCtrl,
              minimal: true,
              maxLength: 100,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'ZIP Code',
              controller: _zipCtrl,
              minimal: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small shared bits ───────────────────────────────────────────────────────

class _MinimalDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final String? hint;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _MinimalDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      isDense: true,
      dropdownColor: context.cSurface,
      style: TextStyle(fontSize: 14, color: context.cTextPrimary),
      hint: hint != null
          ? Text(hint!,
              style: TextStyle(fontSize: 14, color: context.cTextTertiary))
          : null,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
        labelStyle: TextStyle(
          fontSize: 12,
          color: context.cTextTertiary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        floatingLabelStyle: TextStyle(
          fontSize: 12,
          color: context.cTextPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        border: UnderlineInputBorder(
            borderSide: BorderSide(color: context.cBorder)),
        enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.cBorder)),
        focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.cTextPrimary, width: 1.5)),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

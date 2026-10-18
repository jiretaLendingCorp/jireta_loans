// lib/presentation/features/rider/profile/widgets/rider_details_dialogs.dart
//
// Mga popup na bumubukas kapag pinindot ang section title sa Rider Profile
// (Personal Details / Email / Rider Information). Dito na nakalagay ang mga
// field — hindi sa ilalim ng title — at pwedeng i-edit at i-save agad.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../providers/rider_profile_provider.dart';

/// Motorcycle brands lang — kapareho ng Edit Profile screen.
const List<String> _motorcycleBrands = [
  'Honda',
  'Yamaha',
  'Suzuki',
  'Kawasaki',
  'Kymco',
  'Mio',
  'Vespa',
  'Piaggio',
  'Bajaj',
  'TVS',
  'Benelli',
  'Rusi',
  'Royal Enfield',
];

const List<String> _vehicleTypes = ['motorcycle'];

Future<void> showRiderPersonalDetailsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _RiderPersonalDetailsDialog(),
  );
}

Future<void> showRiderEmailDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _RiderEmailDialog(),
  );
}

Future<void> showRiderInfoDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _RiderInfoDialog(),
  );
}

// ── Shared dialog shell ─────────────────────────────────────────────────────

class _RiderDialogShell extends StatelessWidget {
  final String title;
  final Widget child;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _RiderDialogShell({
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
                          backgroundColor: context.cBrandGreen,
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

class _RiderPersonalDetailsDialog extends ConsumerStatefulWidget {
  const _RiderPersonalDetailsDialog();

  @override
  ConsumerState<_RiderPersonalDetailsDialog> createState() =>
      _RiderPersonalDetailsDialogState();
}

class _RiderPersonalDetailsDialogState
    extends ConsumerState<_RiderPersonalDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _suffixCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(riderProfileProvider).user;
    if (user != null) {
      _firstNameCtrl.text = user.firstName;
      _middleNameCtrl.text = user.middleName ?? '';
      _lastNameCtrl.text = user.lastName;
      _suffixCtrl.text = user.suffix ?? '';
      _phoneCtrl.text = user.phoneNumber ?? '';
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _suffixCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  String? Function(String?) _required(String label) =>
      (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null;

  String? _validatePhone(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Phone number is required';
    if (value.length != 11) return 'Phone number must be 11 digits';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final ok = await ref.read(riderProfileProvider.notifier).updateProfile({
      'first_name': _firstNameCtrl.text.trim(),
      'middle_name': _middleNameCtrl.text.trim(),
      'last_name': _lastNameCtrl.text.trim(),
      'suffix': _suffixCtrl.text.trim(),
      'phone_number': _phoneCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(ref.read(riderProfileProvider).error ??
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
    final user = ref.watch(riderProfileProvider).user;
    return _RiderDialogShell(
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
            AppTextField(
              label: 'Suffix (optional)',
              controller: _suffixCtrl,
              minimal: true,
              maxLength: 20,
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Phone Number',
              controller: _phoneCtrl,
              minimal: true,
              keyboardType: TextInputType.phone,
              maxLength: 11,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: _validatePhone,
            ),
            const SizedBox(height: 18),
            _ReadOnlyRow(label: 'Member since', value: _memberSince(user)),
            const SizedBox(height: 12),
            _ReadOnlyRow(
              label: 'Address',
              value: (user?.formattedAddress.isEmpty ?? true)
                  ? '—'
                  : user!.formattedAddress,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Email ───────────────────────────────────────────────────────────────────

class _RiderEmailDialog extends ConsumerStatefulWidget {
  const _RiderEmailDialog();

  @override
  ConsumerState<_RiderEmailDialog> createState() => _RiderEmailDialogState();
}

class _RiderEmailDialogState extends ConsumerState<_RiderEmailDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = ref.read(riderProfileProvider).user?.email ?? '';
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Email is required';
    final ok = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(value);
    return ok ? null : 'Enter a valid email address';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final ok = await ref.read(riderProfileProvider.notifier).updateProfile({
      'email': _emailCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(ref.read(riderProfileProvider).error ??
              'Failed to update email. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Email updated.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RiderDialogShell(
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

// ── Rider Information ───────────────────────────────────────────────────────

class _RiderInfoDialog extends ConsumerStatefulWidget {
  const _RiderInfoDialog();

  @override
  ConsumerState<_RiderInfoDialog> createState() => _RiderInfoDialogState();
}

class _RiderInfoDialogState extends ConsumerState<_RiderInfoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _plateCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _otherBrandCtrl = TextEditingController();

  String _vehicleType = 'motorcycle';
  String? _vehicleBrand;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(riderProfileProvider).user;
    if (user != null) {
      _plateCtrl.text = user.plateNumber ?? '';
      _licenseCtrl.text = user.driversLicenseNumber ?? '';
      final type = (user.vehicleType ?? '').toString().toLowerCase();
      _vehicleType = (type == 'bicycle' || type == 'car') ? type : 'motorcycle';
      final brand = (user.vehicleBrand ?? '').toString().trim();
      if (brand.isEmpty) {
        _vehicleBrand = null;
      } else if (_motorcycleBrands.contains(brand)) {
        _vehicleBrand = brand;
      } else {
        _vehicleBrand = 'other';
        _otherBrandCtrl.text = brand;
      }
    }
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    _licenseCtrl.dispose();
    _otherBrandCtrl.dispose();
    super.dispose();
  }

  List<String> get _vehicleTypeItems {
    if (_vehicleType.isEmpty || _vehicleTypes.contains(_vehicleType)) {
      return _vehicleTypes;
    }
    return [..._vehicleTypes, _vehicleType];
  }

  String get _resolvedBrand {
    if (_vehicleBrand == null) return '';
    if (_vehicleBrand == 'other') return _otherBrandCtrl.text.trim();
    return _vehicleBrand!;
  }

  String? Function(String?) _required(String label) =>
      (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    if (_vehicleBrand == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please select a vehicle brand.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (_vehicleBrand == 'other' && _otherBrandCtrl.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please enter the vehicle brand.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final ok = await ref.read(riderProfileProvider.notifier).updateProfile({
      'rider_profile': {
        'plate_number': _plateCtrl.text.trim(),
        'drivers_license_number': _licenseCtrl.text.trim(),
        'vehicle_type': _vehicleType,
        'vehicle_brand': _resolvedBrand,
      },
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(ref.read(riderProfileProvider).error ??
              'Failed to update rider information. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Rider information updated.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RiderDialogShell(
      title: 'Rider Information',
      saving: _saving,
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: 'Plate Number',
              controller: _plateCtrl,
              minimal: true,
              maxLength: 20,
              validator: _required('Plate number'),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: "Driver's License Number",
              controller: _licenseCtrl,
              minimal: true,
              maxLength: 50,
              validator: _required("Driver's license number"),
            ),
            const SizedBox(height: 16),
            _MinimalDropdown(
              label: 'Vehicle Type',
              value: _vehicleType,
              items: [
                for (final t in _vehicleTypeItems)
                  DropdownMenuItem(
                    value: t,
                    child: Text(t[0].toUpperCase() + t.substring(1)),
                  ),
              ],
              onChanged: (v) =>
                  setState(() => _vehicleType = v ?? 'motorcycle'),
            ),
            const SizedBox(height: 16),
            _MinimalDropdown(
              label: 'Vehicle Brand',
              value: _vehicleBrand,
              hint: 'Select brand',
              items: [
                ..._motorcycleBrands.map(
                  (b) => DropdownMenuItem(value: b, child: Text(b)),
                ),
                const DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _vehicleBrand = v),
            ),
            if (_vehicleBrand == 'other') ...[
              const SizedBox(height: 16),
              AppTextField(
                label: 'Other Brand',
                controller: _otherBrandCtrl,
                minimal: true,
                maxLength: 100,
                validator: _required('Vehicle brand'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Small shared bits ───────────────────────────────────────────────────────

class _ReadOnlyRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReadOnlyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: context.cTextTertiary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: context.cTextPrimary,
          ),
        ),
      ],
    );
  }
}

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

/// `created_at` ay pwede pang String mula sa API/flat fallback — kaya dynamic
/// ang paghawak, kapareho ng dating helper sa profile screen.
String _memberSince(UserModel? user) {
  if (user == null) return '—';
  try {
    final dynamic ca = (user as dynamic).createdAt;
    DateTime? dt;
    if (ca is DateTime) {
      dt = ca;
    } else if (ca is String) {
      dt = DateTime.tryParse(ca);
      if (dt == null && ca.isNotEmpty) return ca;
    } else if (ca != null) {
      dt = DateTime.tryParse(ca.toString());
    }
    if (dt == null) return '—';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return '—';
  }
}

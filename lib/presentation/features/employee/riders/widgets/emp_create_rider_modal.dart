// lib/presentation/features/employee/riders/widgets/emp_create_rider_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../providers/emp_rider_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class EmpCreateRiderModal extends ConsumerStatefulWidget {
  const EmpCreateRiderModal({super.key});

  @override
  ConsumerState<EmpCreateRiderModal> createState() =>
      _EmpCreateRiderModalState();
}

class _EmpCreateRiderModalState extends ConsumerState<EmpCreateRiderModal> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _otherBrandCtrl = TextEditingController();
  String _vehicleType = 'motorcycle';
  String? _vehicleBrand;
  DateTime? _licenseExpiry;
  bool _isSaving = false;

  static const List<String> _brands = [
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
    'Toyota',
    'Mitsubishi',
    'Nissan',
    'Hyundai',
    'Isuzu',
    'Ford',
    'Chevrolet',
  ];

  String get _resolvedBrand {
    if (_vehicleBrand == null) return '';
    if (_vehicleBrand == 'other') return _otherBrandCtrl.text.trim();
    return _vehicleBrand!;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _plateCtrl.dispose();
    _licenseCtrl.dispose();
    _otherBrandCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_licenseExpiry == null) {
      context.showSnackBarAsToast(
          const SnackBar(content: Text('Please select license expiry date')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref.read(empRiderProvider.notifier).createRider({
        'first_name': _firstNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'email': _emailCtrl.text.trim().toLowerCase(),
        'phone': _phoneCtrl.text.trim(),
        'vehicle_type': _vehicleType,
        'plate_number': _plateCtrl.text.trim(),
        'drivers_license_number': _licenseCtrl.text.trim(),
        'drivers_license_expiry':
            _licenseExpiry!.toIso8601String().substring(0, 10),
        'vehicle_brand': _resolvedBrand,
      });
      if (mounted) {
        Navigator.of(context).pop();
        context.showSnackBarAsToast(const SnackBar(
            content: Text('Rider created.'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBarAsToast(SnackBar(
            content: Text('Error: $e'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(
                            child: _field('First Name', _firstNameCtrl,
                                maxLength: 100)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _field('Last Name', _lastNameCtrl,
                                maxLength: 100)),
                      ]),
                      const SizedBox(height: 14),
                      _field('Email Address', _emailCtrl, isEmail: true),
                      const SizedBox(height: 14),
                      _field('Phone Number', _phoneCtrl, maxLength: 11),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _vehicleType,
                        decoration:
                            const InputDecoration(labelText: 'Vehicle Type'),
                        items: ['motorcycle', 'tricycle', 'car']
                            .map((v) => DropdownMenuItem(
                                value: v, child: Text(v.toUpperCase())))
                            .toList(),
                        onChanged: (v) => setState(() => _vehicleType = v!),
                      ),
                      const SizedBox(height: 14),
                      _field('Plate Number', _plateCtrl, maxLength: 20),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _vehicleBrand,
                        decoration: const InputDecoration(
                            labelText: 'Vehicle Brand', counterText: ''),
                        hint: const Text('Select brand'),
                        items: [
                          ..._brands.map((b) => DropdownMenuItem(
                              value: b, child: Text(b))),
                          const DropdownMenuItem(
                              value: 'other', child: Text('Other')),
                        ],
                        onChanged: (v) =>
                            setState(() => _vehicleBrand = v),
                      ),
                      if (_vehicleBrand == 'other') ...[
                        const SizedBox(height: 14),
                        _field('Other Brand', _otherBrandCtrl,
                            maxLength: 100),
                      ],
                      const SizedBox(height: 14),
                      _field("Driver's License Number", _licenseCtrl,
                          maxLength: 50),
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: () async {
                          final d = await showDatePicker(
                              context: context,
                              initialDate:
                                  DateTime.now().add(const Duration(days: 365)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 3650)));
                          if (d != null) setState(() => _licenseExpiry = d);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                              labelText: 'License Expiry'),
                          child: Text(
                              _licenseExpiry == null
                                  ? 'Select date'
                                  : _licenseExpiry!
                                      .toIso8601String()
                                      .substring(0, 10),
                              style: TextStyle(
                                  color: _licenseExpiry == null
                                      ? AppColors.textHint
                                      : AppColors.textPrimary)),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
            color: AppColors.deepNavy,
            borderRadius: BorderRadius.zero),
        child: Row(children: [
          const Icon(Icons.directions_bike, color: AppColors.gold, size: 20),
          const SizedBox(width: 10),
          const Text('Add New Rider',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white54, size: 20)),
        ]),
      );

  Widget _buildFooter() => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero),
              ),
              child: const Text('Cancel')),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black87,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero)),
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create Rider'),
          ),
        ]),
      );

  Widget _field(String label, TextEditingController ctrl, {int? maxLength, bool isEmail = false}) =>
      TextFormField(
        controller: ctrl,
        maxLength: maxLength,
        keyboardType: isEmail ? TextInputType.emailAddress : null,
        decoration:
            InputDecoration(labelText: label, counterText: ''),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Required';
          if (isEmail) {
            final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
            if (!regex.hasMatch(v.trim())) return 'Enter a valid email address';
          }
          return null;
        },
      );
}

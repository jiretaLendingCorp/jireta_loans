// lib/presentation/features/head_manager/riders/widgets/create_rider_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/theme/app_colors.dart';
import '../providers/hm_rider_provider.dart';

class CreateRiderModal extends ConsumerStatefulWidget {
  const CreateRiderModal({super.key});
  @override
  ConsumerState<CreateRiderModal> createState() => _CreateRiderModalState();
}

class _CreateRiderModalState extends ConsumerState<CreateRiderModal> {
  final _formKey = GlobalKey<FormState>();
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _otherBrandCtrl = TextEditingController();
  String _vehicleType = 'motorcycle';
  String? _vehicleBrand;
  bool _loading = false;
  String? _error;

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
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _plateCtrl.dispose();
    _licenseCtrl.dispose();
    _otherBrandCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.delivery_dining,
                        color: AppColors.riderGreen,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Add New Rider',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                          child: _f('First Name', _firstCtrl,
                              req: true, maxLength: 100)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _f('Last Name', _lastCtrl,
                              req: true, maxLength: 100)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _f(
                    'Email Address',
                    _emailCtrl,
                    req: true,
                    type: TextInputType.emailAddress,
                    isEmail: true,
                  ),
                  const SizedBox(height: 12),
                  _f(
                    'Phone Number',
                    _phoneCtrl,
                    req: true,
                    type: TextInputType.phone,
                    maxLength: 11,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _vehicleType,
                          decoration: _dec('Vehicle Type'),
                          items: const [
                            DropdownMenuItem(
                              value: 'motorcycle',
                              child: Text('Motorcycle'),
                            ),
                            DropdownMenuItem(
                              value: 'bicycle',
                              child: Text('Bicycle'),
                            ),
                            DropdownMenuItem(value: 'car', child: Text('Car')),
                          ],
                          onChanged: (v) => setState(() => _vehicleType = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _vehicleBrand,
                          decoration: _dec('Vehicle Brand'),
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
                      ),
                    ],
                  ),
                  if (_vehicleBrand == 'other') ...[
                    const SizedBox(height: 12),
                    _f('Other Brand', _otherBrandCtrl, maxLength: 100),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _f('Plate Number', _plateCtrl,
                            req: true, maxLength: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _f("Driver's License #", _licenseCtrl,
                            req: true, maxLength: 50),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.riderGreen,
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Create Rider'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _f(
    String label,
    TextEditingController ctrl, {
    bool req = false,
    TextInputType? type,
    int? maxLength,
    bool isEmail = false,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: type,
        maxLength: maxLength,
        decoration: _dec(label),
        validator: (v) {
          if (req && (v == null || v.trim().isEmpty)) return '$label is required';
          if (isEmail && v != null && v.trim().isNotEmpty) {
            final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
            if (!regex.hasMatch(v.trim())) return 'Enter a valid email address';
          }
          return null;
        },
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(hmRiderProvider.notifier).createRider({
        'first_name': _firstCtrl.text.trim(),
        'last_name': _lastCtrl.text.trim(),
        'email': _emailCtrl.text.trim().toLowerCase(),
        'phone': _phoneCtrl.text.trim(),
        'vehicle_type': _vehicleType,
        'vehicle_brand': _resolvedBrand,
        'plate_number': _plateCtrl.text.trim(),
        'drivers_license_number': _licenseCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = ErrorHandler.handle(e).message;
        _loading = false;
      });
    }
  }
}

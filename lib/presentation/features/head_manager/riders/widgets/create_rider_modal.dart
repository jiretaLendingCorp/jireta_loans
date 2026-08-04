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
  final _phoneCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  String _vehicleType = 'motorcycle';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    _plateCtrl.dispose();
    _licenseCtrl.dispose();
    _brandCtrl.dispose();
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Default password: 12345678. Rider must change on first login.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
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
                  Expanded(child: _f('First Name', _firstCtrl, req: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _f('Last Name', _lastCtrl, req: true)),
                ],
              ),
              const SizedBox(height: 12),
              _f(
                'Phone Number',
                _phoneCtrl,
                req: true,
                type: TextInputType.phone,
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
                  Expanded(child: _f('Vehicle Brand', _brandCtrl)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _f('Plate Number', _plateCtrl, req: true),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _f("Driver's License #", _licenseCtrl, req: true),
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
  }) => TextFormField(
    controller: ctrl,
    keyboardType: type,
    decoration: _dec(label),
    validator: req
        ? (v) => v == null || v.isEmpty ? '$label is required' : null
        : null,
  );

  InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        'phone': _phoneCtrl.text.trim(),
        'vehicle_type': _vehicleType,
        'vehicle_brand': _brandCtrl.text.trim(),
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

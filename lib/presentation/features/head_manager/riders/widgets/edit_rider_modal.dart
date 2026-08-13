// lib/presentation/features/head_manager/riders/widgets/edit_rider_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/validators.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/forms/app_dropdown.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../providers/hm_rider_provider.dart';

class EditRiderModal extends ConsumerStatefulWidget {
  final UserModel rider;

  const EditRiderModal({super.key, required this.rider});

  @override
  ConsumerState<EditRiderModal> createState() => _EditRiderModalState();
}

class _EditRiderModalState extends ConsumerState<EditRiderModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _plateCtrl;
  late final TextEditingController _licenseCtrl;
  late final TextEditingController _vehicleBrandCtrl;
  String? _vehicleType;
  bool _submitting = false;

  static const _vehicleTypes = ['Motorcycle', 'Bicycle', 'Car', 'Van', 'Truck'];

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController(text: widget.rider.firstName);
    _lastNameCtrl = TextEditingController(text: widget.rider.lastName);
    _phoneCtrl = TextEditingController(text: widget.rider.phone);
    _plateCtrl = TextEditingController(text: widget.rider.plateNumber ?? '');
    _licenseCtrl =
        TextEditingController(text: widget.rider.driversLicenseNumber ?? '');
    _vehicleBrandCtrl =
        TextEditingController(text: widget.rider.vehicleBrand ?? '');
    _vehicleType = widget.rider.vehicleType;
  }

  @override
  void dispose() {
    for (final c in [
      _firstNameCtrl,
      _lastNameCtrl,
      _phoneCtrl,
      _plateCtrl,
      _licenseCtrl,
      _vehicleBrandCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      await ref.read(hmRiderProvider.notifier).updateRider(
            userId: widget.rider.id,
            firstName: _firstNameCtrl.text.trim(),
            lastName: _lastNameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            plateNumber: _plateCtrl.text.trim(),
            driversLicenseNumber: _licenseCtrl.text.trim(),
            vehicleType: _vehicleType,
            vehicleBrand: _vehicleBrandCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rider updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Edit Rider',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 20),
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _firstNameCtrl,
                              label: 'First Name',
                              validator: AppValidators.required,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: _lastNameCtrl,
                              label: 'Last Name',
                              validator: AppValidators.required,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _phoneCtrl,
                        label: 'Phone Number',
                        keyboardType: TextInputType.phone,
                        validator: AppValidators.phone,
                      ),
                      const SizedBox(height: 12),
                      AppDropdown<String>(
                        value: _vehicleType,
                        label: 'Vehicle Type',
                        items: _vehicleTypes
                            .map((v) =>
                                DropdownMenuItem(value: v, child: Text(v)))
                            .toList(),
                        onChanged: (v) => setState(() => _vehicleType = v),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _vehicleBrandCtrl,
                              label: 'Vehicle Brand',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: _plateCtrl,
                              label: 'Plate Number',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _licenseCtrl,
                        label: "Driver's License Number",
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Save Changes',
                    isLoading: _submitting,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

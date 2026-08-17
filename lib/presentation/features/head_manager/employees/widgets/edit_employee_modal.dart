// lib/presentation/features/head_manager/employees/widgets/edit_employee_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/validators.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/forms/app_dropdown.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../providers/hm_employee_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class EditEmployeeModal extends ConsumerStatefulWidget {
  final UserModel employee;

  const EditEmployeeModal({super.key, required this.employee});

  @override
  ConsumerState<EditEmployeeModal> createState() => _EditEmployeeModalState();
}

class _EditEmployeeModalState extends ConsumerState<EditEmployeeModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _middleNameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _departmentCtrl;
  late final TextEditingController _positionCtrl;
  String? _gender;
  String? _civilStatus;
  bool _submitting = false;

  static const _genders = ['Male', 'Female', 'Other'];
  static const _civilStatuses = ['Single', 'Married', 'Widowed', 'Separated'];

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController(text: widget.employee.firstName);
    _lastNameCtrl = TextEditingController(text: widget.employee.lastName);
    _middleNameCtrl =
        TextEditingController(text: widget.employee.middleName ?? '');
    _phoneCtrl = TextEditingController(text: widget.employee.phone);
    _departmentCtrl =
        TextEditingController(text: widget.employee.department ?? '');
    _positionCtrl = TextEditingController(text: widget.employee.position ?? '');
    _gender = widget.employee.gender;
    _civilStatus = widget.employee.civilStatus;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _phoneCtrl.dispose();
    _departmentCtrl.dispose();
    _positionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      await ref.read(hmEmployeeProvider.notifier).updateEmployee(
            userId: widget.employee.id,
            firstName: _firstNameCtrl.text.trim(),
            lastName: _lastNameCtrl.text.trim(),
            middleName: _middleNameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            department: _departmentCtrl.text.trim(),
            position: _positionCtrl.text.trim(),
            gender: _gender,
            civilStatus: _civilStatus,
          );
      if (mounted) {
        Navigator.pop(context);
        context.showSnackBarAsToast(
          const SnackBar(content: Text('Employee updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBarAsToast(
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
        width: 560,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Edit Employee',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
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
                              maxLength: 100,
                              validator: AppValidators.required,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: _lastNameCtrl,
                              label: 'Last Name',
                              maxLength: 100,
                              validator: AppValidators.required,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _middleNameCtrl,
                        label: 'Middle Name (Optional)',
                        maxLength: 100,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppDropdown<String>(
                              value: _gender,
                              label: 'Gender',
                              items: _genders
                                  .map((g) => DropdownMenuItem(
                                      value: g, child: Text(g)))
                                  .toList(),
                              onChanged: (v) => setState(() => _gender = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppDropdown<String>(
                              value: _civilStatus,
                              label: 'Civil Status',
                              items: _civilStatuses
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _civilStatus = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _phoneCtrl,
                        label: 'Phone Number',
                        keyboardType: TextInputType.phone,
                        maxLength: 11,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _departmentCtrl,
                              label: 'Department',
                              maxLength: 100,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: _positionCtrl,
                              label: 'Position',
                              maxLength: 100,
                            ),
                          ),
                        ],
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

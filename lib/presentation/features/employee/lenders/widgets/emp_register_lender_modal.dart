// lib/presentation/features/employee/lenders/widgets/emp_register_lender_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/validators.dart';
import '../providers/emp_lender_provider.dart';

class EmpRegisterLenderModal extends ConsumerStatefulWidget {
  const EmpRegisterLenderModal({super.key});

  @override
  ConsumerState<EmpRegisterLenderModal> createState() =>
      _EmpRegisterLenderModalState();
}

class _EmpRegisterLenderModalState
    extends ConsumerState<EmpRegisterLenderModal> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _gcashCtrl = TextEditingController();
  final _employerCtrl = TextEditingController();
  final _incomeCtrl = TextEditingController();
  String _gender = 'male';
  String _civilStatus = 'single';
  String _employmentType = 'employed';
  DateTime? _dob;
  bool _isLoading = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _gcashCtrl.dispose();
    _employerCtrl.dispose();
    _incomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Date of birth is required')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(empLenderProvider.notifier).createLender({
        'first_name': _firstNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'gender': _gender,
        'civil_status': _civilStatus,
        'dob': _dob!.toIso8601String().split('T')[0],
        'employment_type': _employmentType,
        'employer_name': _employerCtrl.text.trim(),
        'monthly_income': double.tryParse(_incomeCtrl.text) ?? 0,
        'gcash_number': _gcashCtrl.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lender registered successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandler.handle(e).message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionLabel('Personal Information'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                              child: _buildTextField(
                            _firstNameCtrl,
                            'First Name',
                            Icons.person_outline,
                            validator: (v) =>
                                v?.isEmpty == true ? 'Required' : null,
                          )),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _buildTextField(
                            _lastNameCtrl,
                            'Last Name',
                            Icons.person_outline,
                            validator: (v) =>
                                v?.isEmpty == true ? 'Required' : null,
                          )),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        _phoneCtrl,
                        'Phone Number (09XXXXXXXXX)',
                        Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (!AppValidators.isValidPhone(v)) {
                            return 'Invalid phone';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
        child: DropdownButtonFormField<String>(
          initialValue: _gender,
                              decoration:
                                  const InputDecoration(labelText: 'Gender'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'male', child: Text('Male')),
                                DropdownMenuItem(
                                    value: 'female', child: Text('Female')),
                              ],
                              onChanged: (v) => setState(() => _gender = v!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
        child: DropdownButtonFormField<String>(
          initialValue: _civilStatus,
                              decoration: const InputDecoration(
                                  labelText: 'Civil Status'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'single', child: Text('Single')),
                                DropdownMenuItem(
                                    value: 'married', child: Text('Married')),
                                DropdownMenuItem(
                                    value: 'widowed', child: Text('Widowed')),
                                DropdownMenuItem(
                                    value: 'separated',
                                    child: Text('Separated')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _civilStatus = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime(1990),
                            firstDate: DateTime(1940),
                            lastDate: DateTime.now().subtract(
                              const Duration(days: 365 * 18),
                            ),
                          );
                          if (picked != null) setState(() => _dob = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date of Birth',
                            prefixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                          child: Text(
                            _dob != null
                                ? '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}'
                                : 'Select date of birth',
                            style: TextStyle(
                              color: _dob != null
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildSectionLabel('Employment & Financial'),
                      const SizedBox(height: 12),
  DropdownButtonFormField<String>(
    initialValue: _employmentType,
                        decoration:
                            const InputDecoration(labelText: 'Employment Type'),
                        items: const [
                          DropdownMenuItem(
                              value: 'employed', child: Text('Employed')),
                          DropdownMenuItem(
                              value: 'self_employed',
                              child: Text('Self Employed')),
                          DropdownMenuItem(
                              value: 'business_owner',
                              child: Text('Business Owner')),
                          DropdownMenuItem(
                              value: 'unemployed', child: Text('Unemployed')),
                        ],
                        onChanged: (v) => setState(() => _employmentType = v!),
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        _employerCtrl,
                        'Employer / Business Name',
                        Icons.business_outlined,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                              child: _buildTextField(
                            _incomeCtrl,
                            'Monthly Income (₱)',
                            Icons.payments_outlined,
                            keyboardType: TextInputType.number,
                          )),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _buildTextField(
                            _gcashCtrl,
                            'GCash Number',
                            Icons.account_balance_wallet_outlined,
                            keyboardType: TextInputType.phone,
                          )),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.infoLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: AppColors.info),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Default password will be set to 12345678. Lender must change on first login.',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.info),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.lenderPurple,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_add_outlined, color: Colors.white),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Register New Lender',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
      ),
      validator: validator,
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.lenderPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Register Lender'),
          ),
        ],
      ),
    );
  }
}

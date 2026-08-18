// lib/presentation/features/head_manager/lenders/widgets/create_lender_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/theme/app_colors.dart';
import '../providers/hm_lender_provider.dart';

class CreateLenderModal extends ConsumerStatefulWidget {
  const CreateLenderModal({super.key});
  @override
  ConsumerState<CreateLenderModal> createState() => _CreateLenderModalState();
}

class _CreateLenderModalState extends ConsumerState<CreateLenderModal> {
  final _formKey = GlobalKey<FormState>();
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _employerCtrl = TextEditingController();
  final _incomeCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  String _gender = 'male';
  String _civilStatus = 'single';
  String _employmentType = 'employed';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    _employerCtrl.dispose();
    _incomeCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 580,
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
                        Icons.person_add,
                        color: AppColors.lenderBlue,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Register New Lender',
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
                    'Phone Number',
                    _phoneCtrl,
                    req: true,
                    type: TextInputType.phone,
                    maxLength: 11,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _dobCtrl,
                    readOnly: true,
                    onTap: _pickDob,
                    decoration: _dec('Date of Birth'),
                    validator: (v) => v == null || v.isEmpty
                        ? 'Date of Birth is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _gender,
                          decoration: _dec('Gender'),
                          items: const [
                            DropdownMenuItem(
                                value: 'male', child: Text('Male')),
                            DropdownMenuItem(
                              value: 'female',
                              child: Text('Female'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _gender = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _civilStatus,
                          decoration: _dec('Civil Status'),
                          items: const [
                            DropdownMenuItem(
                              value: 'single',
                              child: Text('Single'),
                            ),
                            DropdownMenuItem(
                              value: 'married',
                              child: Text('Married'),
                            ),
                            DropdownMenuItem(
                              value: 'widowed',
                              child: Text('Widowed'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _civilStatus = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _employmentType,
                          decoration: _dec('Employment Type'),
                          items: const [
                            DropdownMenuItem(
                              value: 'employed',
                              child: Text('Employed'),
                            ),
                            DropdownMenuItem(
                              value: 'self_employed',
                              child: Text('Self-Employed'),
                            ),
                            DropdownMenuItem(
                              value: 'unemployed',
                              child: Text('Unemployed'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _employmentType = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _f('Employer/Business', _employerCtrl,
                              maxLength: 255)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _f('Monthly Income (₱)', _incomeCtrl,
                      type: TextInputType.number, maxLength: 12),
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
                          backgroundColor: AppColors.lenderBlue,
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
                            : const Text('Register Lender'),
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
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: type,
        maxLength: maxLength,
        decoration: _dec(label),
        validator: req
            ? (v) => v == null || v.isEmpty ? '$label is required' : null
            : null,
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select Date of Birth',
    );
    if (picked != null) {
      setState(() => _dobCtrl.text = picked.toIso8601String().split('T').first);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(hmLenderProvider.notifier).createLender({
        'first_name': _firstCtrl.text.trim(),
        'last_name': _lastCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'gender': _gender,
        'civil_status': _civilStatus,
        'dob': _dobCtrl.text.trim(),
        'employment_type': _employmentType,
        'employer_name': _employerCtrl.text.trim(),
        'monthly_income': double.tryParse(_incomeCtrl.text) ?? 0,
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

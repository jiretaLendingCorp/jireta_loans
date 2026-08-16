// lib/presentation/features/employee/lenders/widgets/emp_edit_lender_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../providers/emp_lender_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class EmpEditLenderModal extends ConsumerStatefulWidget {
  final Map<String, dynamic> lenderData;
  const EmpEditLenderModal({super.key, required this.lenderData});

  @override
  ConsumerState<EmpEditLenderModal> createState() => _EmpEditLenderModalState();
}

class _EmpEditLenderModalState extends ConsumerState<EmpEditLenderModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _gcashCtrl;
  late final TextEditingController _employerCtrl;
  late final TextEditingController _incomeCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.lenderData;
    _firstNameCtrl = TextEditingController(text: d['first_name'] ?? '');
    _lastNameCtrl = TextEditingController(text: d['last_name'] ?? '');
    _phoneCtrl = TextEditingController(text: d['phone'] ?? '');
    _gcashCtrl = TextEditingController(
        text: d['lender_profiles']?['gcash_number'] ?? '');
    _employerCtrl = TextEditingController(
        text: d['lender_profiles']?['employer_name'] ?? '');
    _incomeCtrl = TextEditingController(
        text: d['lender_profiles']?['monthly_income']?.toString() ?? '');
  }

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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(empLenderProvider.notifier).updateProfile({
        'user_id': widget.lenderData['id'],
        'first_name': _firstNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'gcash_number': _gcashCtrl.text.trim(),
        'employer_name': _employerCtrl.text.trim(),
        'monthly_income': double.tryParse(_incomeCtrl.text.trim()),
      });
      if (mounted) Navigator.of(context).pop();
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480,
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
                        Expanded(child: _field('First Name', _firstNameCtrl)),
                        const SizedBox(width: 12),
                        Expanded(child: _field('Last Name', _lastNameCtrl)),
                      ]),
                      const SizedBox(height: 14),
                      _field('Phone Number', _phoneCtrl),
                      const SizedBox(height: 14),
                      _field('GCash Number', _gcashCtrl),
                      const SizedBox(height: 14),
                      _field('Employer Name', _employerCtrl, required: false),
                      const SizedBox(height: 14),
                      _field('Monthly Income', _incomeCtrl,
                          required: false, keyboardType: TextInputType.number),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.deepNavy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, color: AppColors.gold, size: 20),
          const SizedBox(width: 10),
          const Text('Edit Lender',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white54, size: 20)),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black87),
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {bool required = true, TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (v) => v == null || v.trim().isEmpty ? 'Required' : null
          : null,
    );
  }
}

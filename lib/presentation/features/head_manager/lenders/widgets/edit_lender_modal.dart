// lib/presentation/features/head_manager/lenders/widgets/edit_lender_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/forms/app_text_field.dart';
import '../../../../shared/widgets/app_button.dart';
import '../providers/hm_lender_provider.dart';

class EditLenderModal extends ConsumerStatefulWidget {
  final Map<String, dynamic> lender;
  const EditLenderModal({super.key, required this.lender});

  @override
  ConsumerState<EditLenderModal> createState() => _EditLenderModalState();
}

class _EditLenderModalState extends ConsumerState<EditLenderModal> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _gcashCtrl = TextEditingController();
  final _employerCtrl = TextEditingController();
  final _incomeCtrl = TextEditingController();
  String _employmentType = 'employed';
  bool _loading = false;
  String? _error;

  final _employmentOptions = [
    'employed',
    'self_employed',
    'unemployed',
    'student'
  ];

  @override
  void initState() {
    super.initState();
    final l = widget.lender;
    _firstNameCtrl.text = l['first_name'] ?? '';
    _lastNameCtrl.text = l['last_name'] ?? '';
    _phoneCtrl.text = l['phone_number'] ?? '';
    _gcashCtrl.text = l['lender_profile']?['gcash_number'] ?? '';
    _employerCtrl.text = l['lender_profile']?['employer_name'] ?? '';
    _incomeCtrl.text = l['lender_profile']?['monthly_income']?.toString() ?? '';
    _employmentType = l['lender_profile']?['employment_type'] ?? 'employed';
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

  Future<void> _submit() async {
    if (_firstNameCtrl.text.trim().isEmpty ||
        _lastNameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'First name and last name are required');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(hmLenderProvider.notifier).updateLender(
        userId: widget.lender['id'] as String,
        data: {
          'first_name': _firstNameCtrl.text.trim(),
          'last_name': _lastNameCtrl.text.trim(),
          'phone_number': _phoneCtrl.text.trim(),
          'gcash_number': _gcashCtrl.text.trim(),
          'employment_type': _employmentType,
          'employer_name': _employerCtrl.text.trim(),
          'monthly_income': double.tryParse(_incomeCtrl.text.trim()) ?? 0,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.deepNavy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined,
                      color: AppColors.gold, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Text('Edit Lender',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700))),
                  IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close,
                          color: Colors.white60, size: 20)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: AppTextField(
                                controller: _firstNameCtrl,
                                label: 'First Name *')),
                        const SizedBox(width: 12),
                        Expanded(
                            child: AppTextField(
                                controller: _lastNameCtrl,
                                label: 'Last Name *')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                        controller: _phoneCtrl,
                        label: 'Phone Number',
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 16),
                    AppTextField(
                        controller: _gcashCtrl,
                        label: 'GCash Number',
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 16),
                    const Text('Employment Type',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _employmentType,
                          isExpanded: true,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          borderRadius: BorderRadius.circular(8),
                          items: _employmentOptions
                              .map((e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                      e.replaceAll('_', ' ').capitalize())))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _employmentType = v!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                        controller: _employerCtrl, label: 'Employer Name'),
                    const SizedBox(height: 16),
                    AppTextField(
                        controller: _incomeCtrl,
                        label: 'Monthly Income (₱)',
                        keyboardType: TextInputType.number),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.3))),
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 13)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                            child: OutlinedButton(
                                onPressed: _loading
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: const Text('Cancel'))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: AppButton(
                                label: 'Save Changes',
                                onPressed: _loading ? null : _submit,
                                isLoading: _loading,
                                color: AppColors.deepNavy)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension StringExt on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

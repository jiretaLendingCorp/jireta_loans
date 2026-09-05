// lib/presentation/features/head_manager/head_managers/widgets/create_head_manager_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/theme/app_colors.dart';
import '../providers/hm_head_managers_provider.dart';

class CreateHeadManagerModal extends ConsumerStatefulWidget {
  const CreateHeadManagerModal({super.key});

  @override
  ConsumerState<CreateHeadManagerModal> createState() =>
      _CreateHeadManagerModalState();
}

class _CreateHeadManagerModalState extends ConsumerState<CreateHeadManagerModal> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _suffixCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _gender = 'male';
  String _civilStatus = 'single';
  DateTime? _dob;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _suffixCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.deepNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.zero,
                      ),
                      child: const Icon(
                        Icons.person_add,
                        color: AppColors.deepNavy,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Create Head Manager',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
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
                  'Default password will be set to 12345678. Head Manager must change on first login.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        'First Name',
                        _firstNameCtrl,
                        required: true,
                        maxLength: 100,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _field('Middle Name', _middleNameCtrl,
                            maxLength: 100)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field('Last Name', _lastNameCtrl,
                          required: true, maxLength: 100),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _field('Suffix (Jr., Sr.)', _suffixCtrl,
                            maxLength: 20)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _gender,
                        decoration: _dec('Gender'),
                        items: const [
                          DropdownMenuItem(value: 'male', child: Text('Male')),
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
                          DropdownMenuItem(
                            value: 'separated',
                            child: Text('Separated'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _civilStatus = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dob ?? DateTime(1990),
                      firstDate: DateTime(1940),
                      lastDate: DateTime.now().subtract(
                        const Duration(days: 365 * 18),
                      ),
                    );
                    if (picked != null) setState(() => _dob = picked);
                  },
                  child: InputDecorator(
                    decoration: _dec('Date of Birth').copyWith(
                      prefixIcon: const Icon(Icons.calendar_today_outlined),
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
                const SizedBox(height: 12),
                _field(
                  'Email Address',
                  _emailCtrl,
                  required: true,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 254,
                ),
                const SizedBox(height: 12),
                _field(
                  'Phone Number',
                  _phoneCtrl,
                  required: true,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.deepNavy,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero),
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
                          : const Text('Create Head Manager'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool required = false,
    TextInputType? keyboardType,
    int? maxLength,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLength: maxLength,
        decoration: _dec(label),
        validator: required
            ? (v) => v == null || v.isEmpty ? '$label is required' : null
            : null,
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.zero),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) {
      setState(() => _error = 'Date of birth is required');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(hmHeadManagersProvider.notifier).createHeadManager({
        'first_name': _firstNameCtrl.text.trim(),
        'middle_name': _middleNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'suffix': _suffixCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        'gender': _gender,
        'civil_status': _civilStatus,
        'date_of_birth': _dob!.toIso8601String().split('T')[0],
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
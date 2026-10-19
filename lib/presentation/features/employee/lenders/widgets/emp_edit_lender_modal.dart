// lib/presentation/features/employee/lenders/widgets/emp_edit_lender_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/validators.dart';
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
  late final TextEditingController _emailCtrl;

  /// Ang email na nakalabas sa field — para hindi maipadala kapag hindi binago.
  String _shownEmail = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.lenderData;
    _firstNameCtrl = TextEditingController(text: d['first_name'] ?? '');
    _lastNameCtrl = TextEditingController(text: d['last_name'] ?? '');
    _phoneCtrl = TextEditingController(text: d['phone'] ?? '');
    final rawEmail = (d['email'] as String?) ?? '';
    // `${phone}@jireta.temp` = internal GoTrue credential lang — huwag ipakita.
    _emailCtrl = TextEditingController(
        text: rawEmail.toLowerCase().endsWith('@jireta.temp') ? '' : rawEmail);
    _shownEmail = _emailCtrl.text;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
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
        // Ipinapadala lang kapag TALAGANG binago ang email.
        if (_emailCtrl.text.trim().toLowerCase() !=
            _shownEmail.trim().toLowerCase())
          'email': _emailCtrl.text.trim(),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
                        Expanded(
                            child: _field('First Name', _firstNameCtrl,
                                maxLength: 100)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _field('Last Name', _lastNameCtrl,
                                maxLength: 100)),
                      ]),
                      const SizedBox(height: 14),
                      _field('Phone Number', _phoneCtrl, maxLength: 11),
                      const SizedBox(height: 14),
                      _emailField(),
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
              style: OutlinedButton.styleFrom(
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero)),
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
                : const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  /// Email ng lender — para maayos ang blangko/maling email sa People.
  Widget _emailField() {
    return TextFormField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: 'Email',
        hintText: 'name@example.com',
        border: OutlineInputBorder(borderRadius: BorderRadius.zero),
      ),
      validator: (v) {
        final value = (v ?? '').trim();
        if (value.isEmpty) return null;
        return AppValidators.isValidEmail(value)
            ? null
            : 'Enter a valid email address';
      },
    );
  }

  Widget _field(String label, TextEditingController ctrl,
    {bool required = true,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength}) {
  return TextFormField(
    controller: ctrl,
    keyboardType: keyboardType,
    maxLength: maxLength,
    decoration: InputDecoration(
      labelText: label,
      counterText: '',
      border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
    ),
    validator: required
        ? (v) => v == null || v.trim().isEmpty ? 'Required' : null
        : null,
  );
}
}

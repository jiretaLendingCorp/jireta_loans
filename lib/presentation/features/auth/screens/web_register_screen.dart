// lib/presentation/features/auth/screens/web_register_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class WebRegisterScreen extends ConsumerStatefulWidget {
  const WebRegisterScreen({super.key});

  @override
  ConsumerState<WebRegisterScreen> createState() => _WebRegisterScreenState();
}

class _WebRegisterScreenState extends ConsumerState<WebRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  String _gender = 'male';
  String _civilStatus = 'single';
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _submitted = false;
  // Email Uniqueness Check — surface 409 DUPLICATE as a field error, not just a toast.
  String? _emailDuplicationError;
  String? _phoneDuplicationError;

  static const List<String> _genders = ['male', 'female', 'other'];
  static const List<String> _civilStatuses = [
    'single',
    'married',
    'widowed',
    'separated',
  ];

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Clear previous server-side uniqueness errors so a corrected email can
    // re-validate.  Local format validators still run first.
    setState(() {
      _emailDuplicationError = null;
      _phoneDuplicationError = null;
    });
    if (!_formKey.currentState!.validate()) return;
    final repoError = await ref.read(authProvider.notifier).register(
          firstName: _firstNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          // Email is canonicalised with lower(trim) before hitting the
          // Email Uniqueness Check (DB index `uq_users_email_lower`).
          email: AppValidators.normalizeEmail(_emailCtrl.text),
          phoneNumber: _phoneCtrl.text.trim(),
          password: _passwordCtrl.text,
          gender: _gender,
          civilStatus: _civilStatus,
        );
    if (!mounted) return;
    if (repoError == null) {
      setState(() => _submitted = true);
    } else {
      // Email Uniqueness Validation — promote 409 to a field-level error so
      // the user sees exactly which field collided; still show a toast.
      final isEmailDup = AppValidators.isEmailDuplicateError(repoError);
      final isPhoneDup = repoError.toLowerCase().contains('phone') &&
          (repoError.toLowerCase().contains('already') ||
              repoError.toLowerCase().contains('duplicate'));
      if (isEmailDup) {
        setState(() => _emailDuplicationError = AppValidators.duplicateEmailMessage);
        // Re-run validators so the new server error appears inline.
        _formKey.currentState!.validate();
      }
      if (isPhoneDup) {
        setState(() => _phoneDuplicationError = 'Phone number already registered. Please use a different number.');
        _formKey.currentState!.validate();
      }
      context.showSnackBarAsToast(
        SnackBar(
          content: Text(repoError),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authProvider).isLoading;

    return Scaffold(
      backgroundColor: AppColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.go(RouteConstants.webLogin),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: _submitted ? _buildSuccess() : _buildForm(isLoading),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Create Staff Account',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.deepNavy,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Register as an employee. You can sign in right after registering.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 28),
        Form(
          key: _formKey,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameCtrl,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'First Name',
                        prefixIcon: Icon(Icons.person_outlined),
                        counterText: '',
                      ),
                      validator: (v) => AppValidators.required(v, 'First name'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameCtrl,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Last Name',
                        counterText: '',
                      ),
                      validator: (v) => AppValidators.required(v, 'Last name'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                maxLength: 254,
                onChanged: (_) {
                  if (_emailDuplicationError != null) {
                    setState(() => _emailDuplicationError = null);
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: Icon(Icons.email_outlined),
                  counterText: '',
                ),
                validator: (v) {
                  // Server-side Email Uniqueness Check — shown inline after 409.
                  if (_emailDuplicationError != null) return _emailDuplicationError;
                  if (v == null || v.isEmpty) return 'Email is required';
                  if (!AppValidators.isValidEmail(v)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 20,
                onChanged: (_) {
                  if (_phoneDuplicationError != null) {
                    setState(() => _phoneDuplicationError = null);
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                  counterText: '',
                ),
                validator: (v) {
                  if (_phoneDuplicationError != null) return _phoneDuplicationError;
                  if (v == null || v.isEmpty) return 'Phone number is required';
                  if (!AppValidators.isValidPhone(v)) {
                    return 'Enter a valid PH phone number (e.g. 09xxxxxxxxx)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: const InputDecoration(
                        labelText: 'Gender',
                        border: OutlineInputBorder(),
                      ),
                      items: _genders
                          .map((g) => DropdownMenuItem(
                                value: g,
                                child: Text(_capitalize(g)),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _gender = v ?? _gender),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _civilStatus,
                      decoration: const InputDecoration(
                        labelText: 'Civil Status',
                        border: OutlineInputBorder(),
                      ),
                      items: _civilStatuses
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(_capitalize(s)),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _civilStatus = v ?? _civilStatus),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                maxLength: 128,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: AppValidators.password,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordCtrl,
                obscureText: _obscureConfirm,
                maxLength: 128,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) => AppValidators.confirmPassword(
                    v, _passwordCtrl.text),
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Register',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(fontSize: 13),
                    ),
                    TextButton(
                      onPressed: () => context.go(RouteConstants.webLogin),
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      children: [
        const Text(
          'Registration Successful!',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.deepNavy,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your account has been created successfully. '
          'You can now sign in.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.6),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => context.go(RouteConstants.webLogin),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.deepNavy,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Back to Login',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
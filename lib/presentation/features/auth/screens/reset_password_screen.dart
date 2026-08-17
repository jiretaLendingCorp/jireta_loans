// lib/presentation/features/auth/screens/reset_password_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _done = false;
  String _token = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uri = Uri.base;
      _token = uri.queryParameters['token'] ?? '';
    });
  }

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(authProvider.notifier)
        .resetPassword(token: _token, newPassword: _newCtrl.text);
    if (!mounted) return;
    if (ok) {
      setState(() => _done = true);
    } else {
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text('Reset link may have expired. Request a new one.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authProvider).isLoading;

    return Scaffold(
      backgroundColor: AppColors.deepNavy,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: _done ? _buildSuccess() : _buildForm(isLoading),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool isLoading) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.gold),
          ),
          child: const Icon(Icons.lock_reset, color: AppColors.gold, size: 36),
        ),
        const SizedBox(height: 20),
        const Text(
          'Reset Password',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Set your new password below.',
          style: TextStyle(fontSize: 13, color: Colors.white60),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _newCtrl,
                  obscureText: _obscureNew,
                  maxLength: 128,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    counterText: '',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNew
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 8) return 'At least 8 characters';
                    if (!RegExp(r'[A-Z]').hasMatch(v)) {
                      return 'Include an uppercase letter';
                    }
                    if (!RegExp(r'[0-9]').hasMatch(v)) {
                      return 'Include a number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  maxLength: 128,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
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
                  validator: (v) =>
                      v != _newCtrl.text ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 20),
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
                            'Reset Password',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(
            color: AppColors.successLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_outline,
            color: AppColors.success,
            size: 44,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Password Reset!',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your password has been updated successfully.',
          style: TextStyle(fontSize: 13, color: Colors.white60),
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
              'Login',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}

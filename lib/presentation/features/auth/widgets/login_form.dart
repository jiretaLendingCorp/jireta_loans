// lib/presentation/features/auth/widgets/login_form.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';

class LoginForm extends StatefulWidget {
  final Function(String email, String password) onSubmit;
  final bool isLoading;
  final String? error;

  const LoginForm({
    super.key,
    required this.onSubmit,
    this.isLoading = false,
    this.error,
  });

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      widget.onSubmit(_emailCtrl.text.trim(), _passCtrl.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.error!,
                      style:
                          const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            maxLength: 254,
            validator: AppValidators.email,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.email_outlined),
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            maxLength: 128,
            onFieldSubmitted: (_) => _submit(),
            validator: AppValidators.required,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              counterText: '',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: widget.isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: widget.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Login',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// lib/presentation/features/auth/screens/web_login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';

class WebLoginScreen extends ConsumerStatefulWidget {
  const WebLoginScreen({super.key});

  @override
  ConsumerState<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends ConsumerState<WebLoginScreen> {
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(authProvider.notifier);
    final ok = await notifier.login(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (!ok && mounted) {
      final err = ref.read(authProvider).error;
      _showError(
        notifier.extractErrorMessage(err ?? 'Error') ?? 'Login failed.',
      );
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authProvider);
    final isLoading = authAsync.isLoading;
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: AppColors.deepNavy,
      body: isWide ? _buildWide(isLoading) : _buildNarrow(isLoading),
    );
  }

  Widget _buildWide(bool isLoading) {
    return Row(
      children: [
        Expanded(flex: 5, child: _buildBrandPanel()),
        Expanded(
          flex: 4,
          child: Container(
            color: AppColors.surfaceWhite,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _buildForm(isLoading),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow(bool isLoading) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.deepNavy,
            child: _buildBrandPanel(),
          ),
          Container(
            color: AppColors.surfaceWhite,
            padding: const EdgeInsets.all(32),
            child: _buildForm(isLoading),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandPanel() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.gold),
                ),
                child: const Icon(
                  Icons.account_balance,
                  color: AppColors.gold,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'JIRETA',
                    style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.gold,
                      letterSpacing: 4,
                    ),
                  ),
                  Text(
                    'LOANS & CREDIT CORP · 1966',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white54,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 40),
          const Text(
            'Enterprise\nLending Platform',
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Secure, compliant, and efficient loan management for your team.',
            style: TextStyle(fontSize: 14, color: Colors.white60, height: 1.6),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              _featurePill(Icons.verified_user, 'RBAC Security'),
              const SizedBox(width: 8),
              _featurePill(Icons.insights, 'Live KPIs'),
              const SizedBox(width: 8),
              _featurePill(Icons.receipt_long, 'Audit Logs'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _featurePill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.gold),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(bool isLoading) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Welcome back',
              style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.deepNavy,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Sign in to your account',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email Address',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Email is required';
                if (!AppValidators.isValidEmail(v)) {
                  return 'Enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Password is required';
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.go(RouteConstants.forgotPassword),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
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
                        'Sign In',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppColors.info),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'For Riders & Lenders, use the mobile app.',
                      style: TextStyle(fontSize: 12, color: AppColors.info),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

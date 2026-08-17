// lib/presentation/features/auth/screens/web_login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/asset_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../shared/providers/connectivity_provider.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/offline_toast.dart';
import '../providers/auth_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

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
  Timer? _lockTimer;
  int _lockSecondsLeft = 0;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _lockTimer?.cancel();
    super.dispose();
  }

  bool get _isOnline => ref.read(connectivityProvider).valueOrNull ?? true;

  /// Shows the remaining login-lock time as a live countdown in a top-right
  /// toast while the Login button stays disabled.
  void _startLockCountdown(int seconds) {
    _lockTimer?.cancel();
    setState(() => _lockSecondsLeft = seconds);
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_lockSecondsLeft <= 1) {
        t.cancel();
        setState(() => _lockSecondsLeft = 0);
      } else {
        setState(() => _lockSecondsLeft--);
      }
    });
    AppToast.showWidget(
      context,
      LockoutCountdownToast(
        seconds: seconds,
        onExpired: () {
          if (mounted) setState(() => _lockSecondsLeft = 0);
        },
      ),
    );
  }

  Future<void> _submit() async {
    if (ref.read(authProvider).isLoading) return;
    if (_lockSecondsLeft > 0) return;
    if (!_isOnline) {
      _showNoInternetToast();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(authProvider.notifier);
    final ok = await notifier.login(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (!ok && mounted) {
      final err = ref.read(authProvider).error;
      // Login lockout: show a live countdown instead of a one-off snackbar.
      final lockSecs = notifier.extractOtpLockoutSeconds(err ?? '');
      if (lockSecs != null && lockSecs > 0) {
        _startLockCountdown(lockSecs);
        return;
      }
      _showError(
        notifier.extractErrorMessage(err ?? 'Error') ?? 'Login failed.',
      );
    }
  }

  void _showNoInternetToast() {
    if (!mounted) return;
    AppToast.show(
      context,
      'No Internet Connection',
      type: AppToastType.info,
    );
  }

  void _showError(String msg) {
    context.showSnackBarAsToast(
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
    ref.listen<bool>(
      connectivityProvider.select((v) => v.valueOrNull ?? true),
      (previous, next) {
        if (previous == true && next == false) {
          _showNoInternetToast();
        }
      },
    );
    final authAsync = ref.watch(authProvider);
    final isLoading = authAsync.isLoading;
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;

    return Scaffold(
      backgroundColor: AppColors.surfaceWhite,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      _buildBrand(),
                      const SizedBox(height: 24),
                      _buildForm(isLoading, isOnline),
                    ],
                  ),
                ),
              ),
            ),
            if (!isOnline)
              const Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(left: 24, right: 24, bottom: 24),
                  child: OfflineToast(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrand() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.gold),
          ),
          child: ClipOval(
            child: Image.asset(AssetConstants.logoJpg, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'JIRETA',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.gold,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'LOANS & CREDIT CORP · 1966',
          style: TextStyle(
            fontSize: 9,
            color: AppColors.textSecondary,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildForm(bool isLoading, bool isOnline) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Login to your account',
              style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.deepNavy,
              ),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              maxLength: 254,
              readOnly: _lockSecondsLeft > 0,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                prefixIcon: Icon(Icons.email_outlined),
                counterText: '',
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
              maxLength: 128,
              readOnly: _lockSecondsLeft > 0,
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
                onPressed: (isLoading || !isOnline || _lockSecondsLeft > 0)
                    ? null
                    : _submit,
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
                        'Login',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// lib/presentation/features/auth/screens/reviewer_login_screen.dart
//
// GOOGLE PLAY STORE REVIEWER SIGN-IN.
//
// Paano ito nakarating dito: 7 beses na tap sa copyright line sa ilalim ng
// mobile login screen (naka-document sa Play Console instructions). Hindi ito
// visible na menu item para sa ordinaryong user.
//
// MAHALAGANG SEGURIDAD:
//   * Walang reviewer phone, password, o OTP na naka-hardcode dito — ang
//     reviewer ang nagta-type ng credentials na ibinigay sa Play Console.
//   * Ang server (`auth-reviewer`) ang nagpapatunay kung allowed ang account
//     at kung tama ang password. Kung hindi naka-configure ang reviewer
//     secrets, 404 ang endpoint at hindi ito gumagana.
//   * Kapag na-authenticate, rider/lender pa rin ang reviewer account kaya
//     dumadaan ito sa normal na MPIN gate (kapareho ng OTP login).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../auth_post_login.dart';
import '../providers/auth_provider.dart';

class ReviewerLoginScreen extends ConsumerStatefulWidget {
  const ReviewerLoginScreen({super.key});

  @override
  ConsumerState<ReviewerLoginScreen> createState() =>
      _ReviewerLoginScreenState();
}

class _ReviewerLoginScreenState extends ConsumerState<ReviewerLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    final phone = _phoneCtrl.text.trim();
    final ok = await ref.read(authProvider.notifier).reviewerLogin(
          phone: phone,
          password: _passwordCtrl.text,
        );
    if (!mounted) return;
    setState(() => _loading = false);

    if (!ok) {
      final err = ref.read(authProvider).error;
      setState(() => _error = _messageFor(err));
      return;
    }

    // Kapareho ng OTP / MFA login ang susunod na hakbang: rider / lender na
    // may MPIN → "Enter MPIN", walang MPIN → setup. Hindi ito dinadaanan ng
    // staff role dahil hindi reviewer ang staff accounts.
    final destination = await resolvePostAuthDestination(ref, phone: phone);
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    navigator.pop();
    router.go(destination.location, extra: destination.extra);
  }

  String _messageFor(Object? error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 404) {
        return 'Reviewer sign-in is not available in this app build.';
      }
      if (status == 429) {
        return 'Too many sign-in attempts. Please wait a few minutes and try again.';
      }
      final data = error.response?.data;
      if (data is Map) {
        final err = data['error'];
        if (err is Map && err['message'] is String) {
          final message = (err['message'] as String).trim();
          if (message.isNotEmpty) return message;
        }
      }
    }
    final extracted =
        ref.read(authProvider.notifier).extractErrorMessage(error ?? '');
    return extracted ??
        'Reviewer sign-in failed. Please check the details and try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.deepNavy,
        title: const Text(
          'Reviewer Sign-In',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _formKey,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.deepNavy.withValues(alpha: 0.08),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'GOOGLE PLAY REVIEW ACCESS',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: AppColors.goldDark,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Jireta Loans',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.deepNavy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Use the reviewer credentials provided in Google Play Console.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 22),
                      TextFormField(
                        controller: _phoneCtrl,
                        enabled: !_loading,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9+\s-]'),
                          ),
                        ],
                        validator: AppValidators.phone,
                        decoration: _inputDecoration(
                          label: 'Reviewer mobile number',
                          hint: '09XXXXXXXXX',
                          icon: Icons.phone_iphone_rounded,
                        ),
                        onFieldSubmitted: (_) =>
                            _passwordFocus.requestFocus(),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordCtrl,
                        focusNode: _passwordFocus,
                        enabled: !_loading,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        validator: (value) =>
                            AppValidators.required(value, 'Reviewer password'),
                        onFieldSubmitted: (_) => _submit(),
                        decoration: _inputDecoration(
                          label: 'Reviewer password',
                          hint: 'Password',
                          icon: Icons.lock_outline_rounded,
                        ).copyWith(
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: _loading
                                ? null
                                : () => setState(
                                      () => _obscurePassword =
                                          !_obscurePassword,
                                    ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.errorLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  size: 16, color: AppColors.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.deepNavy,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                AppColors.deepNavy.withValues(alpha: 0.5),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Sign in as reviewer',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Reviewer test accounts cannot perform payments, '
                        'disbursements, or cash collections.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.45,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 19, color: AppColors.textTertiary),
      labelStyle: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
      hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
      filled: true,
      fillColor: AppColors.surfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.goldDark, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.4),
      ),
    );
  }
}

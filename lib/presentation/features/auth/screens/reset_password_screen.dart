// ignore_for_file: unnecessary_null_comparison, invalid_null_aware_operator, unnecessary_non_null_assertion
// lib/presentation/features/auth/screens/reset_password_screen.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/security/secure_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_state_provider.dart';
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
  String? _statusMsg;
  bool _hasSession = false;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _extractToken());
  }

  Future<void> _extractToken() async {
    try {
      // Give Supabase Flutter a moment to auto-process the URL fragment
      // (it restores session from #access_token / PKCE code on web).
      await Future.delayed(const Duration(milliseconds: 400));
      if (Supabase.instance.client.auth.currentSession != null) {
        _hasSession = true;
      }

      final uri = Uri.base;

      // 1) Extract raw token/code from query params or fragment.
      // Supabase `generateLink(type: recovery)` produces an `action_link` like:
      //   https://xxx.supabase.co/auth/v1/verify?token=TOKEN_HASH&type=recovery&redirect_to=APP_URL/reset-password
      // After the user clicks it, Supabase verifies and redirects to:
      //   APP_URL/reset-password?code=PKCE_CODE   (PKCE flow)
      // or keeps hash:
      //   APP_URL/reset-password#access_token=...&refresh_token=...&type=recovery
      // We need to support all forms for robustness.
      String? token = uri.queryParameters['token'] ??
          uri.queryParameters['code'] ??
          uri.queryParameters['token_hash'] ??
          uri.queryParameters['hashed_token'] ??
          uri.queryParameters['access_token'];

      // Also check hash fragment for implicit flow (access_token in URL hash)
      if ((token == null || token.isEmpty) && uri.fragment.isNotEmpty) {
        final fragParams = Uri.splitQueryString(uri.fragment);
        token = fragParams['access_token'] ??
            fragParams['token'] ??
            fragParams['code'] ??
            fragParams['token_hash'] ??
            fragParams['hashed_token'];
        // If fragment contained tokens, Supabase should have already recovered
        // the session automatically. Check again.
        if (Supabase.instance.client.auth.currentSession != null) {
          _hasSession = true;
        }
      }

      // 2) If we have a PKCE `code`, exchange it for a recovery session so
      //    we can call `updateUser` directly (modern Supabase flow).
      String? code = uri.queryParameters['code'];
      // Also consider token as code if it looks like PKCE and no explicit code param
      if ((code == null || code.isEmpty) &&
          token != null &&
          token.isNotEmpty &&
          _isPkceCode(token)) {
        code = token;
      }
      // Also check fragment for code
      if ((code == null || code.isEmpty) && uri.fragment.isNotEmpty) {
        final fragParams = Uri.splitQueryString(uri.fragment);
        final fragCode = fragParams['code'];
        if (fragCode != null && fragCode.isNotEmpty && _isPkceCode(fragCode)) {
          code = fragCode;
        }
      }

      if (code != null && code.isNotEmpty && _isPkceCode(code)) {
        try {
          final res =
              await Supabase.instance.client.auth.exchangeCodeForSession(code);
          if (res.session != null) {
            _hasSession = true;
            debugPrint(
                '[reset] PKCE code exchanged, session user=${res.session!.user.id}');
          } else if (Supabase.instance.client.auth.currentSession != null) {
            _hasSession = true;
            debugPrint('[reset] PKCE exchange: session recovered via currentSession');
          }
        } catch (e) {
          debugPrint('[reset] exchangeCodeForSession failed: $e');
          // Keep token for backend fallback even if exchange fails (token may be
          // a token_hash that backend can verify via verifyOtp).
        }
      }

      // Final session check
      if (Supabase.instance.client.auth.currentSession != null) {
        _hasSession = true;
      }

      if (token != null && token.isNotEmpty) {
        _token = token;
      }

      if (_token.isEmpty && !_hasSession) {
        debugPrint('[reset] No token/code found in URL: ${uri.toString()}');
      } else {
        debugPrint(
            '[reset] token extracted: ${_token.isNotEmpty ? "${_token.substring(0, _token.length.clamp(0, 12))}..." : "none"} hasSession=$_hasSession url=${uri.toString()}');
      }
    } catch (e) {
      debugPrint('[reset] _extractToken error: $e');
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  bool _isPkceCode(String s) {
    // JWT access_tokens contain dots, PKCE codes do not
    if (s.contains('.')) return false;
    // Legacy UUID tokens are exactly 36 chars with hyphen groups 8-4-4-4-12
    if (RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            caseSensitive: false)
        .hasMatch(s)) {
      return false;
    }
    // PKCE codes are typically >20 chars, base64url-like
    return s.length > 20;
  }

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_token.isEmpty && !_hasSession) {
      context.showSnackBarAsToast(
        const SnackBar(
          content: Text(
              'Missing or expired reset link. Please request a new one.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final notifier = ref.read(authProvider.notifier);
    bool ok = false;
    String? errMsg;

    // Prefer direct Supabase update when we have a recovery session (PKCE / hash
    // flow from the Resend email's action_link). This is the modern Supabase
    // recovery flow and does not need the backend token handler.
    if (_hasSession && Supabase.instance.client.auth.currentSession != null) {
      try {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: _newCtrl.text),
        );
        ok = true;
        debugPrint('[reset] updateUser via session succeeded');
        // Clear the recovery session + any stale local session so the
        // post-reset redirect to Login is not bounced back to dashboard.
        // Spec flow: Password successfully changed → Redirect to Login
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        try {
          await SecureStorage.clearAll();
        } catch (_) {}
        try {
          await ref.read(authStateProvider.notifier).logout();
        } catch (_) {}
        _hasSession = false;
      } catch (e) {
        debugPrint('[reset] updateUser via session failed: $e');
        errMsg = notifier.extractErrorMessage(e) ?? e.toString();
        // Fallback to backend with token if available
        if (_token.isNotEmpty) {
          ok = await notifier.resetPassword(
              token: _token, newPassword: _newCtrl.text);
          if (ok) {
            errMsg = null;
            try {
              await Supabase.instance.client.auth.signOut();
            } catch (_) {}
            try {
              await SecureStorage.clearAll();
            } catch (_) {}
            try {
              await ref.read(authStateProvider.notifier).logout();
            } catch (_) {}
            _hasSession = false;
          } else {
            final err = ref.read(authProvider).maybeWhen(
                  error: (e, _) => e,
                  orElse: () => null,
                );
            if (err != null) {
              errMsg = notifier.extractErrorMessage(err) ?? errMsg;
            }
          }
        }
      }
    } else {
      // No session — call backend which handles token_hash / code / JWT / legacy UUID
      ok = await notifier.resetPassword(
          token: _token, newPassword: _newCtrl.text);
      if (!ok) {
        final err = ref.read(authProvider).maybeWhen(
              error: (e, _) => e,
              orElse: () => null,
            );
        if (err != null) {
          errMsg = notifier.extractErrorMessage(err);
          // Surface INVALID_TOKEN as expired link for better UX
          final raw = err.toString().toLowerCase();
          if (raw.contains('invalid or expired') ||
              raw.contains('invalid_token')) {
            errMsg = 'Reset link is invalid or has expired. Please request a new one.';
          }
        }
      } else {
        // Backend succeeded — ensure any Supabase + local session is cleared
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        try {
          await SecureStorage.clearAll();
        } catch (_) {}
        try {
          await ref.read(authStateProvider.notifier).logout();
        } catch (_) {}
        _hasSession = false;
      }
    }

    if (!mounted) return;
    if (ok) {
      setState(() => _done = true);
      // Clear sensitive fields
      _newCtrl.clear();
      _confirmCtrl.clear();
    } else {
      context.showSnackBarAsToast(
        SnackBar(
          content: Text(
              errMsg ?? 'Reset link may have expired. Request a new one.'),
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
            child: _initializing
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: AppColors.gold),
                    ),
                  )
                : _done
                    ? _buildSuccess()
                    : (_token.isEmpty && !_hasSession && kIsWeb)
                        ? _buildInvalidLink()
                        : _buildForm(isLoading),
          ),
        ),
      ),
    );
  }

  Widget _buildInvalidLink() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.orange),
          ),
          child: const Icon(Icons.link_off, color: Colors.orange, size: 36),
        ),
        const SizedBox(height: 20),
        const Text(
          'Invalid or Expired Link',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'This password reset link is missing, invalid, or has expired. Links expire in 1 hour and can only be used once.',
          style: TextStyle(fontSize: 13, color: Colors.white60, height: 1.6),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => context.go(RouteConstants.forgotPassword),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.deepNavy,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Request New Link',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go(RouteConstants.webLogin),
          child: const Text('Back to Login',
              style: TextStyle(color: Colors.white70)),
        ),
      ],
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
                  onChanged: (_) {
                    // Re-validate confirm field when new password changes
                    if (_confirmCtrl.text.isNotEmpty) {
                      _formKey.currentState?.validate();
                    }
                  },
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
                    if (!RegExp(r'[a-z]').hasMatch(v)) {
                      return 'Include a lowercase letter';
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
                            'Change Password',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                if (_statusMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(_statusMsg!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.error)),
                ],
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
          'Your password has been updated successfully. Please log in with your new password.',
          style: TextStyle(fontSize: 13, color: Colors.white60, height: 1.6),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              // Ensure recovery + local sessions are fully cleared before navigating
              // so the redirect to Login is not bounced to dashboard.
              try {
                await Supabase.instance.client.auth.signOut();
              } catch (_) {}
              try {
                await SecureStorage.clearAll();
              } catch (_) {}
              try {
                await ref.read(authStateProvider.notifier).logout();
              } catch (_) {}
              if (!mounted) return;
              context.go(RouteConstants.webLogin);
            },
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
}

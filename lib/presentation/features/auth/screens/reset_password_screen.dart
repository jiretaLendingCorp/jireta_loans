// ignore_for_file: unnecessary_null_comparison, invalid_null_aware_operator, unnecessary_non_null_assertion
// lib/presentation/features/auth/screens/reset_password_screen.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
      final uri = Uri.base;
      // Check query params first (covers Supabase PKCE `code`, legacy `token`, etc.)
      String? token = uri.queryParameters['token'] ??
          uri.queryParameters['code'] ??
          uri.queryParameters['token_hash'] ??
          uri.queryParameters['hashed_token'] ??
          uri.queryParameters['access_token'];

      // Hash fragment (implicit flow): #access_token=xxx&refresh_token=...
      if ((token == null || token.isEmpty) && uri.fragment.isNotEmpty) {
        final fragParams = Uri.splitQueryString(uri.fragment);
        token = fragParams['access_token'] ??
            fragParams['token'] ??
            fragParams['code'] ??
            fragParams['token_hash'];
        // Supabase Flutter auto-recovers session from URL fragment on web,
        // but try explicit refresh-token recovery for reliability.
        final refresh = fragParams['refresh_token'];
        final access = fragParams['access_token'];
        if (refresh != null && refresh.isNotEmpty) {
          try {
            await Supabase.instance.client.auth.setSession(refresh);
            _hasSession = Supabase.instance.client.auth.currentSession != null;
          } catch (_) {}
        } else if (access != null && access.isNotEmpty) {
          // Fallback: hash contains access_token only (older implicit flow)
          // Wait briefly for Supabase to auto-process the fragment
          await Future.delayed(const Duration(milliseconds: 300));
          _hasSession = Supabase.instance.client.auth.currentSession != null;
          // Keep token as access_token for backend fallback
          token ??= access;
        }
      }

      // PKCE: exchange `code` for a session so updateUser works directly.
      String? code = uri.queryParameters['code'];
      if ((code == null || code.isEmpty) && token != null && token.isNotEmpty && _isPkceCode(token)) {
        code = token;
      }
      if (code != null && code.isNotEmpty && _isPkceCode(code)) {
        try {
          final res = await Supabase.instance.client.auth.exchangeCodeForSession(code);
          if (res.session != null) {
            _hasSession = true;
            debugPrint('[reset] PKCE code exchanged, session user=${res.session.user.id}');
          }
        } catch (e) {
          debugPrint('[reset] exchangeCodeForSession failed: $e');
          // Keep token for backend fallback even if exchange fails
        }
      } else if (Supabase.instance.client.auth.currentSession != null) {
        _hasSession = true;
      }

      // Also detect if we already have a session from the redirect (Supabase
      // may have auto-established it before this screen mounted).
      if (Supabase.instance.client.auth.currentSession != null) {
        _hasSession = true;
      }

      if (token != null && token.isNotEmpty) {
        _token = token;
      } else if (uri.queryParameters['token'] != null) {
        _token = uri.queryParameters['token']!;
      }

      // For debugging: show if token missing
      if (_token.isEmpty && !_hasSession) {
        debugPrint('[reset] No token/code found in URL: ${uri.toString()}');
      } else {
        debugPrint('[reset] token extracted: ${_token.isNotEmpty ? "${_token.substring(0, _token.length.clamp(0, 12))}..." : "none"} hasSession=$_hasSession');
      }
    } catch (e) {
      debugPrint('[reset] _extractToken error: $e');
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  bool _isPkceCode(String s) {
    // PKCE codes are longer than UUIDs and contain no hyphens in groups of 8-4-4-4-12
    if (RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false).hasMatch(s)) {
      return false; // legacy UUID
    }
    // Heuristic: PKCE codes are base64url-like, length > 20
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
          content: Text('Missing or expired reset link. Please request a new one.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final notifier = ref.read(authProvider.notifier);
    bool ok = false;
    String? errMsg;

    // Prefer direct Supabase update when we have a session (PKCE / hash flow
    // from the Resend email's action_link). This is the modern Supabase
    // recovery flow and does not need the backend token handler.
    if (_hasSession && Supabase.instance.client.auth.currentSession != null) {
      try {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: _newCtrl.text),
        );
        ok = true;
        debugPrint('[reset] updateUser via session succeeded');
      } catch (e) {
        debugPrint('[reset] updateUser via session failed: $e');
        errMsg = notifier.extractErrorMessage(e) ?? e.toString();
        // Fallback to backend with token if available
        if (_token.isNotEmpty) {
          ok = await notifier.resetPassword(token: _token, newPassword: _newCtrl.text);
          if (ok) errMsg = null;
        }
      }
    } else {
      // No session — call backend which now handles code/token_hash/legacy UUID
      ok = await notifier.resetPassword(token: _token, newPassword: _newCtrl.text);
      if (!ok) {
        final err = ref.read(authProvider).maybeWhen(
              error: (e, _) => e,
              orElse: () => null,
            );
        if (err != null) errMsg = notifier.extractErrorMessage(err);
      }
    }

    if (!mounted) return;
    if (ok) {
      setState(() => _done = true);
    } else {
      context.showSnackBarAsToast(
        SnackBar(
          content: Text(errMsg ?? 'Reset link may have expired. Request a new one.'),
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
                    : _buildForm(isLoading),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool isLoading) {
    final showTokenWarning = _token.isEmpty && !_hasSession && kIsWeb;
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
        if (showTokenWarning) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reset link missing or expired. Please request a new one from the login screen.',
                    style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                if (_statusMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(_statusMsg!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
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

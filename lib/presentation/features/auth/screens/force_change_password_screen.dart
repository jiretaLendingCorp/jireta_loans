// lib/presentation/features/auth/screens/force_change_password_screen.dart
//
// Clean redesign — kaparehong design language ng web login page: rounded white
// card na may soft navy/gold shadows, PlayfairDisplay heading, premium gradient
// CTA, focus/hover states sa inputs, at laging nakikitang password
// requirements panel + strength meter.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class ForceChangePasswordScreen extends ConsumerStatefulWidget {
  const ForceChangePasswordScreen({super.key});

  @override
  ConsumerState<ForceChangePasswordScreen> createState() =>
      _ForceChangePasswordScreenState();
}

class _ForceChangePasswordScreenState
    extends ConsumerState<ForceChangePasswordScreen> {
  /// Default password na ibinibigay ng admin — ipinapakita sa subtitle at
  /// hinaharangan sa validator (iisang source of truth sa dalawang lugar).
  static const String _defaultPassword = '12345678';

  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  final _currentFocus = FocusNode();
  final _newFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool _currentHovered = false;
  bool _newHovered = false;
  bool _confirmHovered = false;
  bool _btnHovered = false;

  @override
  void initState() {
    super.initState();
    // Kailangan ang rebuild para sumunod ang fill/border sa focus state.
    for (final f in [_currentFocus, _newFocus, _confirmFocus]) {
      f.addListener(_onFocusChange);
    }
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final f in [_currentFocus, _newFocus, _confirmFocus]) {
      f.removeListener(_onFocusChange);
      f.dispose();
    }
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(authProvider.notifier).forceChangePassword(
          currentPassword: _currentCtrl.text,
          newPassword: _newCtrl.text,
        );
    if (!mounted) return;
    if (ok) {
      await ref.read(authProvider.notifier).logout();
      if (!mounted) return;
      context.go(RouteConstants.webLogin);
    } else {
      final err = ref.read(authProvider).error;
      context.showSnackBarAsToast(
        SnackBar(
          content: Text(err?.toString() ?? 'Failed to change password.'),
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
      backgroundColor: const Color(0xFFF6F7FB),
      body: Stack(
        children: [
          // Faint brand glows — kapareho ng web login page para tuloy-tuloy
          // ang branding kahit nasa onboarding step pa ang user.
          Positioned(
            top: -150,
            right: -130,
            child: _glow(AppColors.gold, 0.07, 360),
          ),
          Positioned(
            bottom: -170,
            left: -150,
            child: _glow(AppColors.deepNavy, 0.05, 400),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: _buildCard(isLoading),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double alpha, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0.0),
          ]),
        ),
      );

  Widget _buildCard(bool isLoading) {
    final pw = _newCtrl.text;
    final meetsLength = pw.length >= 8;
    final meetsUpper = RegExp(r'[A-Z]').hasMatch(pw);
    final meetsNumber = RegExp(r'[0-9]').hasMatch(pw);
    // Validation hint lang ang checklist — hindi ito laging nakikita. Lalabas
    // lang kapag may nakasalang na password na kulang pa sa requirements.
    final needsGuidance =
        pw.isNotEmpty && !(meetsLength && meetsUpper && meetsNumber);

    return Container(
      padding: const EdgeInsets.fromLTRB(36, 34, 36, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECEEF3)),
        boxShadow: [
          BoxShadow(
              color: AppColors.deepNavy.withValues(alpha: 0.08),
              blurRadius: 36,
              offset: const Offset(0, 18)),
          BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Brand badge ──
            Center(
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0D1B2A), Color(0xFF1E3A5F)],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.deepNavy.withValues(alpha: 0.24),
                        blurRadius: 18,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: const Icon(Icons.lock_reset_rounded,
                    size: 26, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'Change Your Password',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepNavy,
                  height: 1.15,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.6,
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                  ),
                  children: const [
                    TextSpan(text: 'Your default password '),
                    TextSpan(
                      text: _defaultPassword,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.deepNavy,
                        letterSpacing: 0.6,
                      ),
                    ),
                    TextSpan(
                        text: ' must be changed before proceeding.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 28),

            // ── Current password ──
            const _FieldLabel('Current Password'),
            const SizedBox(height: 8),
            _passwordField(
              controller: _currentCtrl,
              focusNode: _currentFocus,
              hovered: _currentHovered,
              onHover: (v) => setState(() => _currentHovered = v),
              obscure: _obscureCurrent,
              onToggleObscure: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
              hint: 'Enter your current password',
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _newFocus.requestFocus(),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Enter your current password' : null,
            ),
            const SizedBox(height: 18),

            // ── New password ──
            const _FieldLabel('New Password'),
            const SizedBox(height: 8),
            _passwordField(
              controller: _newCtrl,
              focusNode: _newFocus,
              hovered: _newHovered,
              onHover: (v) => setState(() => _newHovered = v),
              obscure: _obscureNew,
              onToggleObscure: () => setState(() => _obscureNew = !_obscureNew),
              hint: 'Create a new password',
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _confirmFocus.requestFocus(),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter a new password';
                if (v.length < 8) return 'At least 8 characters';
                if (!RegExp(r'[A-Z]').hasMatch(v)) {
                  return 'Include an uppercase letter';
                }
                if (!RegExp(r'[0-9]').hasMatch(v)) {
                  return 'Include a number';
                }
                if (v == _defaultPassword) {
                  return 'Cannot use the default password';
                }
                return null;
              },
            ),
            if (pw.isNotEmpty) ...[
              const SizedBox(height: 12),
              _strengthMeter(pw),
            ],
            if (needsGuidance) ...[
              const SizedBox(height: 12),
              _requirementsPanel(
                meetsLength: meetsLength,
                meetsUpper: meetsUpper,
                meetsNumber: meetsNumber,
              ),
            ],

            // ── Confirm password ──
            const SizedBox(height: 18),
            const _FieldLabel('Confirm New Password'),
            const SizedBox(height: 8),
            _passwordField(
              controller: _confirmCtrl,
              focusNode: _confirmFocus,
              hovered: _confirmHovered,
              onHover: (v) => setState(() => _confirmHovered = v),
              obscure: _obscureConfirm,
              onToggleObscure: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              hint: 'Re-enter your new password',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Re-enter your new password';
                if (v != _newCtrl.text) return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 24),

            // ── Premium gradient CTA ──
            MouseRegion(
              onEnter: (_) => setState(() => _btnHovered = true),
              onExit: (_) => setState(() => _btnHovered = false),
              child: AnimatedScale(
                scale: _btnHovered && !isLoading ? 1.01 : 1.0,
                duration: const Duration(milliseconds: 140),
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: isLoading
                        ? null
                        : const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF0D1B2A),
                              Color(0xFF1E3A5F),
                              Color(0xFF0D1B2A),
                            ],
                          ),
                    color: isLoading
                        ? AppColors.deepNavy.withValues(alpha: 0.42)
                        : null,
                    boxShadow: isLoading
                        ? []
                        : _btnHovered
                            ? [
                                BoxShadow(
                                    color: AppColors.deepNavy
                                        .withValues(alpha: 0.28),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10)),
                                BoxShadow(
                                    color:
                                        AppColors.gold.withValues(alpha: 0.12),
                                    blurRadius: 12),
                              ]
                            : [
                                BoxShadow(
                                    color: AppColors.deepNavy
                                        .withValues(alpha: 0.16),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6)),
                              ],
                  ),
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.transparent,
                      disabledForegroundColor:
                          Colors.white.withValues(alpha: 0.9),
                      shadowColor: Colors.transparent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded,
                                  size: 18, color: Colors.white),
                              SizedBox(width: 8),
                              Text('Update Password'),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Security note ──
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.shield_outlined,
                      size: 14, color: AppColors.textTertiary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'For your security, you will be signed out after updating.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppColors.textTertiary.withValues(alpha: 0.95),
                      ),
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

  /// Rounded password input na may focus/hover styling gaya ng login card.
  Widget _passwordField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool hovered,
    required ValueChanged<bool> onHover,
    required bool obscure,
    required VoidCallback onToggleObscure,
    required String hint,
    required TextInputAction textInputAction,
    required String? Function(String?) validator,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    final focused = focusNode.hasFocus;
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: focused || hovered
              ? [
                  BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.14),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ]
              : [],
        ),
        child: TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          maxLength: 128,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                fontSize: 13.5,
                color: AppColors.textTertiary.withValues(alpha: 0.75)),
            prefixIcon: Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: focused ? AppColors.deepNavy : AppColors.textTertiary,
            ),
            counterText: '',
            filled: true,
            fillColor: focused ? Colors.white : const Color(0xFFF8F9FC),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: hovered
                      ? const Color(0xFFCBD2DE)
                      : const Color(0xFFE4E7EE)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.deepNavy, width: 1.4),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.error, width: 1.4),
            ),
            suffixIcon: IconButton(
              tooltip: obscure ? 'Show password' : 'Hide password',
              icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
              onPressed: onToggleObscure,
            ),
          ),
          validator: validator,
        ),
      ),
    );
  }

  /// Checklist na lumalabas lang habang hindi pa pasado ang new password —
  /// nawawala kapag kumpleto na (strength meter na ang nagbibigay ng positive
  /// feedback), para hindi ito permanente sa screen.
  Widget _requirementsPanel({
    required bool meetsLength,
    required bool meetsUpper,
    required bool meetsNumber,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFECEEF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: AppColors.textSecondary),
              SizedBox(width: 6),
              Text(
                'Password must contain',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _requirementRow('At least 8 characters', meetsLength),
          _requirementRow('One uppercase letter', meetsUpper),
          _requirementRow('One number', meetsNumber),
        ],
      ),
    );
  }

  Widget _requirementRow(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 14,
            color: met ? AppColors.success : AppColors.textTertiary,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: met ? AppColors.success : AppColors.textTertiary,
              fontWeight: met ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  /// 4-segment strength meter — lumalabas lang kapag may laman na ang field.
  Widget _strengthMeter(String pw) {
    final score = _passwordScore(pw);
    const labels = ['Weak', 'Fair', 'Good', 'Strong'];
    final label = pw.length < 8 ? 'Too short' : labels[score.clamp(0, 3)];
    final color = pw.length < 8
        ? AppColors.error
        : switch (score) {
            0 => AppColors.error,
            1 => AppColors.warning,
            2 => AppColors.info,
            _ => AppColors.success,
          };

    return Row(
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 4,
              margin: EdgeInsets.only(right: i == 3 ? 0 : 4),
              decoration: BoxDecoration(
                color: i <= score && pw.length >= 8
                    ? color
                    : const Color(0xFFE4E7EE),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }

  int _passwordScore(String pw) {
    var s = 0;
    if (pw.length >= 8) s++;
    if (RegExp(r'[A-Z]').hasMatch(pw) && RegExp(r'[a-z]').hasMatch(pw)) s++;
    if (RegExp(r'[0-9]').hasMatch(pw)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pw) || pw.length >= 12) s++;
    return (s - 1).clamp(0, 3);
  }
}

/// Maliit na label sa itaas ng bawat input — kapareho ng login card.
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary),
    );
  }
}

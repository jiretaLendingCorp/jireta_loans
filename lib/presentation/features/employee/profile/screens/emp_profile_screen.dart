// lib/presentation/features/employee/profile/screens/emp_profile_screen.dart
// Website layout: wide 2-column on desktop (left summary + right details),
// single-column on mobile. Walang Log out dito — nasa top-bar avatar menu na.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/config/app_config.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/auth_state_provider.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/forms/app_date_picker.dart';
import '../../../../shared/widgets/profile/modern_profile_widgets.dart';
import '../../../../shared/widgets/profile_avatar_upload.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../profile/providers/emp_profile_provider.dart';

class EmpProfileScreen extends ConsumerStatefulWidget {
  const EmpProfileScreen({super.key});

  @override
  ConsumerState<EmpProfileScreen> createState() => _EmpProfileScreenState();
}

class _EmpProfileScreenState extends ConsumerState<EmpProfileScreen> {
  static const _accent = AppColors.employeeOrange;

  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(empProfileProvider.notifier).loadProfile());
  }

  @override
  void dispose() {
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(empProfileProvider);
    final authState = ref.watch(authStateProvider);
    final user = profileState.valueOrNull ?? authState.user;

    if (profileState.isLoading && user == null) {
      return WebScaffold(
        title: 'My Profile',
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: const ShimmerLoader(height: 320),
            ),
          ),
        ),
      );
    }

    if (user == null) {
      final err = profileState.hasError
          ? profileState.error.toString()
          : 'Unable to load profile';
      return WebScaffold(
        title: 'My Profile',
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: ModernProfileStyles.iconBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.person_off_outlined,
                      size: 24, color: ModernProfileStyles.iconColor),
                ),
                const SizedBox(height: 12),
                Text(err,
                    textAlign: TextAlign.center,
                    style: ModernProfileStyles.sub),
                const SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  child: ModernPrimaryButton(
                    label: 'Retry',
                    icon: Icons.refresh_rounded,
                    color: _accent,
                    onPressed: () => ref
                        .read(empProfileProvider.notifier)
                        .loadProfile(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // profile + auth fallback ay parehong UserModel na.
    final UserModel model = user;

    return WebScaffold(
      title: 'My Profile',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                if (!isWide) return _buildNarrowLayout(model);
                return _buildWideLayout(model);
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── Mobile / narrow: single column ──────────────────────
  Widget _buildNarrowLayout(UserModel user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(user),
        const SizedBox(height: 16),
        ModernPrimaryButton(
          label: 'Edit Profile',
          icon: Icons.edit_outlined,
          color: _accent,
          onPressed: () => _openEditDialog(user),
        ),
        const SizedBox(height: 12),
        _buildSecurityButton(),
        const SizedBox(height: 20),
        _buildPersonalCard(user),
        const SizedBox(height: 12),
        _buildWorkCard(user),
        const SizedBox(height: 20),
        _buildGeneralCard(),
        const SizedBox(height: 16),
        _buildVersionFooter(),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Website / wide: 2 columns ───────────────────────────
  Widget _buildWideLayout(UserModel user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 340,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(user),
                  const SizedBox(height: 16),
                  ModernPrimaryButton(
                    label: 'Edit Profile',
                    icon: Icons.edit_outlined,
                    color: _accent,
                    onPressed: () => _openEditDialog(user),
                  ),
                  const SizedBox(height: 12),
                  _buildSecurityButton(),
                  const SizedBox(height: 16),
                  _buildGeneralCard(),
                  const SizedBox(height: 16),
                  _buildVersionFooter(),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPersonalCard(user),
                  const SizedBox(height: 16),
                  _buildWorkCard(user),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Cards ───────────────────────────────────────────────
  Widget _buildPersonalCard(UserModel user) {
    return ModernInfoCard(
      title: 'Personal Details',
      icon: Icons.person_outline_rounded,
      rows: [
        ModernInfoRowData(
            icon: Icons.person_outline_rounded,
            label: 'Full name',
            value: _fullName(user)),
        ModernInfoRowData(
            icon: Icons.email_outlined,
            label: 'Email',
            value:
                (user.email ?? '').isEmpty ? '—' : user.email!),
        ModernInfoRowData(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: (user.phoneNumber ?? '').isEmpty
                ? '—'
                : user.phoneNumber!),
        ModernInfoRowData(
            icon: Icons.wc_outlined,
            label: 'Gender',
            value: _formatLabel(user.gender)),
        ModernInfoRowData(
            icon: Icons.favorite_border_rounded,
            label: 'Civil status',
            value: _formatLabel(user.civilStatus)),
        ModernInfoRowData(
            icon: Icons.cake_outlined,
            label: 'Date of birth',
            value: user.dateOfBirth != null
                ? AppFormatters.date(user.dateOfBirth!)
                : '—'),
      ],
    );
  }

  Widget _buildWorkCard(UserModel user) {
    return ModernInfoCard(
      title: 'Work Details',
      icon: Icons.badge_outlined,
      rows: [
        ModernInfoRowData(
            icon: Icons.work_outline_rounded,
            label: 'Position',
            value: (user.position ?? '').isEmpty
                ? '—'
                : user.position!),
        ModernInfoRowData(
            icon: Icons.verified_user_outlined,
            label: 'Account status',
            value: _formatLabel(user.accountStatus)),
        ModernInfoRowData(
            icon: Icons.calendar_today_outlined,
            label: 'Member since',
            value: AppFormatters.date(user.createdAt)),
        ModernInfoRowData(
            icon: Icons.access_time_rounded,
            label: 'Last login',
            value: user.lastLoginAt != null
                ? AppFormatters.dateTime(user.lastLoginAt!)
                : '—'),
      ],
    );
  }

  Widget _buildGeneralCard() {
    return ModernMenuCard(items: [
      ModernMenuItem(
        icon: Icons.notifications_outlined,
        title: 'Notifications',
        subtitle: 'View alerts and updates',
        onTap: () =>
            context.go(RouteConstants.empNotifications),
      ),
      ModernMenuItem(
        icon: Icons.support_agent_outlined,
        title: 'Help Center',
        subtitle: 'FAQs and support guide',
        onTap: () => _showSheet(
          title: 'Help Center',
          icon: Icons.support_agent_outlined,
          sections: const [
            ModernSheetSection(
              title: 'How do I handle lender verifications?',
              body:
                  'Open Lender Account Upgrade to review submitted IDs and documents, then verify or request resubmission.',
            ),
            ModernSheetSection(
              title: 'How do I record office payments?',
              body:
                  'Go to Collections, find the due schedule, and record the cash payment with the official receipt number.',
            ),
            ModernSheetSection(
              title: 'Forgot password?',
              body:
                  'Use Change Password above. If locked out, use Forgot Password on the login page to reset via email.',
            ),
          ],
        ),
      ),
      ModernMenuItem(
        icon: Icons.info_outline_rounded,
        title: 'About Jireta',
        subtitle: 'Since 1966',
        onTap: () => _showSheet(
          title: 'About Jireta',
          icon: Icons.info_outline_rounded,
          sections: const [
            ModernSheetSection(
              title: 'Company',
              body:
                  'Jireta Loans & Credit Corp 1966 provides accessible financial assistance to Filipinos.',
            ),
            ModernSheetSection(
              title: 'Your role',
              body:
                  'As Staff you assist with verifications, loan processing, collections, and lender support.',
            ),
          ],
        ),
      ),
      ModernMenuItem(
        icon: Icons.privacy_tip_outlined,
        title: 'Privacy & Terms',
        subtitle: 'How we protect data',
        onTap: () => _showSheet(
          title: 'Privacy & Terms',
          icon: Icons.privacy_tip_outlined,
          sections: const [
            ModernSheetSection(
              title: 'Data privacy',
              body:
                  'Lender and company information must be kept confidential and used only for official duties, under the Data Privacy Act of 2012 (RA 10173).',
            ),
            ModernSheetSection(
              title: 'Account security',
              body:
                  'Never share your password or OTP. Change your password regularly and log out on shared devices.',
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildVersionFooter() {
    return const Center(
      child: Text(
        'Version ${AppConfig.appVersion}',
        style:
            TextStyle(fontSize: 12, color: AppColors.textTertiary),
      ),
    );
  }

  // ── Header: plain text lang ang status (hindi pill/button) ──
  Widget _buildHeader(UserModel user) {
    final status = _statusStyle(user.accountStatus);
    return Container(
      width: double.infinity,
      decoration: ModernProfileStyles.card,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          ProfileAvatarUpload(
            photoUrl: user.profilePhotoUrl,
            name: _fullName(user),
            color: _accent,
            radius: 36,
            onUploaded: _updatePhoto,
          ),
          const SizedBox(height: 12),
          Text(
            _fullName(user),
            textAlign: TextAlign.center,
            style: ModernProfileStyles.name,
          ),
          const SizedBox(height: 10),
          // Plain text + dot lang — walang pill background para di mukhang button.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: status.fg,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                status.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: status.fg,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _updatePhoto(String url) async {
    final ok = await ref
        .read(empProfileProvider.notifier)
        .updateProfile({'profile_photo_url': url});
    if (mounted && ok) {
      context.showSuccessToast('Profile picture updated');
    } else if (mounted) {
      context.showErrorToast('Failed to update photo');
    }
  }

  // ── Security: button sa ilalim ng Edit Profile; dialog ang bumubukas ──
  Widget _buildSecurityButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _openChangePasswordDialog,
        icon: const Icon(Icons.lock_outline_rounded, size: 18),
        label: const Text('Change Password',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accent,
          side: BorderSide(color: _accent.withValues(alpha: 0.4)),
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  /// Bubukas ng Update Password dialog kapag pinindot ang Change Password.
  Future<void> _openChangePasswordDialog() async {
    _currentPassCtrl.clear();
    _newPassCtrl.clear();
    _confirmPassCtrl.clear();
    var showCurrent = false;
    var showNew = false;
    var showConfirm = false;
    var saving = false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          Future<void> submit() async {
            setDlg(() => error = null);
            if (_currentPassCtrl.text.isEmpty) {
              setDlg(() => error = 'Enter your current password.');
              return;
            }
            if (_newPassCtrl.text.length < 8) {
              setDlg(() =>
                  error = 'New password must be at least 8 characters.');
              return;
            }
            if (_newPassCtrl.text != _confirmPassCtrl.text) {
              setDlg(() => error = 'New passwords do not match.');
              return;
            }
            setDlg(() => saving = true);
            try {
              final err =
                  await ref.read(authProvider.notifier).changePassword(
                        currentPassword: _currentPassCtrl.text,
                        newPassword: _newPassCtrl.text,
                      );
              if (!ctx.mounted) return;
              if (err == null) {
                _currentPassCtrl.clear();
                _newPassCtrl.clear();
                _confirmPassCtrl.clear();
                Navigator.pop(ctx);
                if (mounted) {
                  context.showSuccessToast('Password updated successfully');
                }
              } else {
                setDlg(() {
                  error = err;
                  saving = false;
                });
              }
            } catch (_) {
              if (ctx.mounted) setDlg(() => saving = false);
            }
          }

          return AlertDialog(
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero),
            title: const Text('Change Password',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPassField(
                      _currentPassCtrl,
                      'Current password',
                      showCurrent,
                      () => setDlg(() => showCurrent = !showCurrent),
                    ),
                    const SizedBox(height: 12),
                    _buildPassField(
                      _newPassCtrl,
                      'New password (min. 8)',
                      showNew,
                      () => setDlg(() => showNew = !showNew),
                      onChanged: (_) => setDlg(() {}),
                    ),
                    if (_newPassCtrl.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _strengthBar(_newPassCtrl.text),
                    ],
                    const SizedBox(height: 12),
                    _buildPassField(
                      _confirmPassCtrl,
                      'Confirm new password',
                      showConfirm,
                      () => setDlg(() => showConfirm = !showConfirm),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 14, color: AppColors.error),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(error!,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.error)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero)),
                onPressed: saving ? null : submit,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.key_rounded, size: 18),
                label: Text(saving ? 'Updating…' : 'Update Password'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPassField(
    TextEditingController ctrl,
    String label,
    bool obscure,
    VoidCallback toggle, {
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: label,
        prefixIcon: const Icon(Icons.lock_outline_rounded,
            size: 18, color: ModernProfileStyles.iconColor),
        suffixIcon: IconButton(
          icon: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 18,
            color: ModernProfileStyles.iconColor,
          ),
          onPressed: toggle,
        ),
        border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: ModernProfileStyles.cardBorder),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _accent, width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _strengthBar(String pw) {
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
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i == 3 ? 0 : 4),
              decoration: BoxDecoration(
                color: i <= score && pw.length >= 8
                    ? color
                    : ModernProfileStyles.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
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

  // (Change password is handled inside [_openChangePasswordDialog].)

  // ── Edit dialog ─────────────────────────────────────────
  Future<void> _openEditDialog(UserModel user) async {
    final first = TextEditingController(text: user.firstName);
    final middle = TextEditingController(text: user.middleName ?? '');
    final last = TextEditingController(text: user.lastName);
    final phone = TextEditingController(text: user.phoneNumber ?? '');
    final formKey = GlobalKey<FormState>();
    var saving = false;
    DateTime? dob = user.dateOfBirth;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Profile',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: TextFormField(
                                controller: first,
                                decoration: const InputDecoration(
                                    labelText: 'First name',
                                    border: OutlineInputBorder()),
                                validator: (v) =>
                                    (v ?? '').trim().isEmpty ? 'Required' : null)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextFormField(
                                controller: middle,
                                decoration: const InputDecoration(
                                    labelText: 'Middle name',
                                    border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: last,
                        decoration: const InputDecoration(
                            labelText: 'Last name',
                            border: OutlineInputBorder()),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? 'Required' : null),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone (09xxxxxxxxx)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppDatePicker(
                      label: 'Date of birth',
                      value: dob,
                      lastDate: DateTime.now(),
                      onChanged: (d) => setDlg(() => dob = d),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: saving
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) {
                        return;
                      }
                      setDlg(() => saving = true);
                      final birthDate = dob;
                      final ok = await ref
                          .read(empProfileProvider.notifier)
                          .updateProfile({
                        'first_name': first.text.trim(),
                        'middle_name': middle.text.trim().isEmpty
                            ? null
                            : middle.text.trim(),
                        'last_name': last.text.trim(),
                        'phone_number': phone.text.trim().isEmpty
                            ? null
                            : phone.text.trim(),
                        if (birthDate != null)
                          'employee_profile': {
                            'date_of_birth': birthDate
                                .toIso8601String()
                                .substring(0, 10),
                          },
                      });
                      if (ctx.mounted) Navigator.pop(ctx, ok);
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );

    first.dispose();
    middle.dispose();
    last.dispose();
    phone.dispose();
    if (!mounted) return;
    if (saved == true) {
      context.showSuccessToast('Profile updated');
    } else if (saved == false) {
      context.showErrorToast('Failed to save changes');
    }
  }

  void _showSheet({
    required String title,
    required IconData icon,
    required List<ModernSheetSection> sections,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ModernInfoSheet(title: title, icon: icon, sections: sections),
    );
  }

  // ── Helpers ─────────────────────────────────────────────
  String _fullName(UserModel user) {
    final parts = [
      user.firstName,
      user.middleName,
      user.lastName,
      user.suffix,
    ].where((e) => e != null && e.toString().trim().isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(' ');
  }

  String _formatLabel(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return '—';
    final s = value.toString();
    return s
        .split('_')
        .map((w) => w.isEmpty
            ? w
            : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  _StatusStyle _statusStyle(String? status) {
    final s = (status ?? 'active').toLowerCase();
    return switch (s) {
      'active' => const _StatusStyle(
          'Active', AppColors.success, AppColors.successLight),
      'suspended' => const _StatusStyle(
          'Suspended', AppColors.warning, AppColors.warningLight),
      'blacklisted' || 'deactivated' => _StatusStyle(
          s[0].toUpperCase() + s.substring(1),
          AppColors.error,
          AppColors.errorLight),
      _ => _StatusStyle(_formatLabel(status),
          AppColors.textSecondary, ModernProfileStyles.iconBg),
    };
  }
}

class _StatusStyle {
  final String label;
  final Color fg;
  final Color bg;
  const _StatusStyle(this.label, this.fg, this.bg);
}

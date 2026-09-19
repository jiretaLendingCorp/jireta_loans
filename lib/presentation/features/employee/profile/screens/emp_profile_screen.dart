// lib/presentation/features/employee/profile/screens/emp_profile_screen.dart
// Website layout: wide 2-column on desktop (left summary + right details),
// single-column on mobile. Walang Log out dito — nasa top-bar avatar menu na.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/config/app_config.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/validators.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/auth_state_provider.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/forms/app_date_picker.dart';
import '../../../../shared/widgets/philippines_address_field.dart';
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

  // Kaparehong value sets ng employee_profiles CHECK constraints
  // (male/female/other, single/married/widowed/separated) — nakikita sa
  // Personal Details ng My Profile.
  static const List<String> _genderOptions = ['Male', 'Female', 'Other'];
  static const List<String> _civilStatusOptions = [
    'Single',
    'Married',
    'Widowed',
    'Separated',
  ];

  /// Pinakamahabang pinapayagang pangalan / phone sa Edit Profile — kapareho ng
  /// `users` table columns at ng ibang profile forms (edit_user_modal).
  static const int _nameMaxLength = 100;
  static const int _phoneMaxLength = 11;

  /// Letters (may accent), space, hyphen, apostrophe at period lang — para sa
  /// "Ma. Cristina", "O'Brien", "Delos-Santos".
  static final RegExp _namePattern = RegExp(r"^[A-Za-zÑñÁÉÍÓÚáéíóúÜü .'-]+$");

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
        // Primary home address (addresses table) — hindi lang sa People →
        // details ito makikita, kundi sa sariling Profile din ng employee.
        ModernInfoRowData(
            icon: Icons.location_on_outlined,
            label: 'Address',
            value: user.formattedAddress.isEmpty
                ? '—'
                : user.formattedAddress),
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
            value: AppFormatters.dateTime(user.createdAt)),
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

          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.lock_reset_rounded,
                              size: 21, color: _accent),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Change Password',
                                  style: TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary)),
                              SizedBox(height: 2),
                              Text(
                                  'Use at least 8 characters with letters and numbers.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildPassField(
                      _currentPassCtrl,
                      'Current password',
                      showCurrent,
                      () => setDlg(() => showCurrent = !showCurrent),
                    ),
                    const SizedBox(height: 14),
                    _buildPassField(
                      _newPassCtrl,
                      'New password',
                      showNew,
                      () => setDlg(() => showNew = !showNew),
                      onChanged: (_) => setDlg(() {}),
                    ),
                    if (_newPassCtrl.text.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _strengthBar(_newPassCtrl.text),
                    ],
                    const SizedBox(height: 14),
                    _buildPassField(
                      _confirmPassCtrl,
                      'Confirm new password',
                      showConfirm,
                      () => setDlg(() => showConfirm = !showConfirm),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                size: 16, color: AppColors.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(error!,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.error)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                saving ? null : () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(color: AppColors.border),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel',
                                style:
                                    TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: saving ? null : submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  _accent.withValues(alpha: 0.5),
                              elevation: 0,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Update Password',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        isDense: true,
        prefixIcon: const Icon(Icons.lock_outline_rounded,
            size: 18, color: AppColors.textTertiary),
        suffixIcon: IconButton(
          tooltip: obscure ? 'Show password' : 'Hide password',
          icon: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 18,
            color: AppColors.textTertiary,
          ),
          onPressed: toggle,
        ),
        filled: true,
        fillColor: AppColors.surfaceVariant.withValues(alpha: 0.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _accent, width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
    final email = TextEditingController(text: user.email ?? '');
    final phone = TextEditingController(text: user.phoneNumber ?? '');
    final formKey = GlobalKey<FormState>();
    final addressKey = GlobalKey<PhilippinesAddressFieldState>();
    var saving = false;
    DateTime? dob = user.dateOfBirth;
    var gender = _normalizeOption(user.gender, _genderOptions);
    var civilStatus = _normalizeOption(user.civilStatus, _civilStatusOptions);
    // Ang address lang ang ipapadala kapag aktwal na ginalaw — kung hindi,
    // mananatili ang nakatagong primary home address (hindi ito mababakante).
    var addressTouched = false;
    // Kapag wala pang naka-save na address, kailangang kumpleto ito bago
    // mag-save (may `*` ang mga label ng address cascade).
    final addressRequired = user.formattedAddress.trim().isEmpty;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Profile',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 560,
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
                            maxLength: _nameMaxLength,
                            textCapitalization: TextCapitalization.words,
                            decoration: _dialogDeco('First name'),
                            validator: (v) => _validateName(v, 'First name',
                                isRequired: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: middle,
                            maxLength: _nameMaxLength,
                            textCapitalization: TextCapitalization.words,
                            decoration: _dialogDeco('Middle name'),
                            validator: (v) =>
                                _validateName(v, 'Middle name'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: last,
                      maxLength: _nameMaxLength,
                      textCapitalization: TextCapitalization.words,
                      decoration: _dialogDeco('Last name'),
                      validator: (v) =>
                          _validateName(v, 'Last name', isRequired: true),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: email,
                      readOnly: true,
                      decoration: _dialogDeco('Email'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      maxLength: _phoneMaxLength,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: _dialogDeco('Phone (09xxxxxxxxx)'),
                      validator: _validatePhone,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: gender,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Gender',
                              border: OutlineInputBorder(),
                            ),
                            items: _genderOptions
                                .map((g) =>
                                    DropdownMenuItem(value: g, child: Text(g)))
                                .toList(),
                            onChanged: (v) => setDlg(() => gender = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: civilStatus,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Civil status',
                              border: OutlineInputBorder(),
                            ),
                            items: _civilStatusOptions
                                .map((c) =>
                                    DropdownMenuItem(value: c, child: Text(c)))
                                .toList(),
                            onChanged: (v) => setDlg(() => civilStatus = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppDatePicker(
                      label: 'Date of birth',
                      value: dob,
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                      onChanged: (d) => setDlg(() => dob = d),
                    ),
                    const SizedBox(height: 12),
                    // Kaparehong source of truth ng Personal Details — ang
                    // primary home address sa `addresses` table.
                    PhilippinesAddressField(
                      key: addressKey,
                      label: 'Address',
                      initialStreet: user.streetAddress,
                      initialProvince: user.province,
                      initialCity: user.city,
                      initialBarangay: user.barangay,
                      onChanged: (_) => addressTouched = true,
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
                      if ((addressTouched || addressRequired) &&
                          !(addressKey.currentState?.validate() ?? false)) {
                        return;
                      }
                      setDlg(() => saving = true);
                      final birthDate = dob;
                      final addr = addressKey.currentState;
                      // Final locals para ma-promote ang nullable values sa
                      // loob ng collection-if (hindi na-promote ang `var`).
                      final chosenGender = gender;
                      final chosenCivilStatus = civilStatus;
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
                        // Nested — hindi flat, para hindi ito mapagkamalang
                        // lender payload ng users-manage handler.
                        'employee_profile': {
                          if (chosenGender != null)
                            'gender': chosenGender.toLowerCase(),
                          if (chosenCivilStatus != null)
                            'civil_status': chosenCivilStatus.toLowerCase(),
                          if (birthDate != null)
                            'date_of_birth': birthDate
                                .toIso8601String()
                                .substring(0, 10),
                        },
                        if (addressTouched && addr != null) ...{
                          'street_address': addr.street,
                          'barangay': addr.barangay ?? '',
                          'city': addr.city ?? '',
                          'province': addr.province ?? '',
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
    email.dispose();
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

  /// Pare-parehong decoration ng Edit Profile fields — nakahide ang counter
  /// text dahil nasa loob ito ng dialog (gumagawa ng extra na linya).
  InputDecoration _dialogDeco(String label, {String? errorText}) =>
      InputDecoration(
        labelText: label,
        counterText: '',
        errorText: errorText,
        border: const OutlineInputBorder(),
      );

  /// Pangalan: required kapag sinabi, letters/spaces/punctuation lang, at may
  /// limitasyon sa haba para tugma sa `users.first_name/middle_name/last_name`.
  String? _validateName(String? value, String label,
      {bool isRequired = false}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return isRequired ? '$label is required' : null;
    if (v.length > _nameMaxLength) {
      return '$label is too long (max $_nameMaxLength characters)';
    }
    if (!_namePattern.hasMatch(v)) {
      return "Letters, spaces and . ' - only";
    }
    return null;
  }

  /// Optional ang phone sa My Profile (puwedeng bakante), pero kapag may
  /// nakasulat, kailangang valid na PH mobile number (09xxxxxxxxx).
  String? _validatePhone(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    if (v.length != _phoneMaxLength) {
      return 'Phone number must be $_phoneMaxLength digits (09xxxxxxxxx)';
    }
    return AppValidators.phone(v);
  }

  /// Itinutugma ang stored enum value (hal. `male`, `prefer_not_to_say`) sa
  /// exact na dropdown option label. Kung walang tugma, `null` — kung hindi,
  /// nag-a-assert ang DropdownButtonFormField kapag wala sa items ang value.
  String? _normalizeOption(String? value, List<String> options) {
    final key = (value ?? '').trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final opt in options) {
      if (opt.toLowerCase() == key) return opt;
    }
    return null;
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

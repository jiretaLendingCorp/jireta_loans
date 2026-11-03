// lib/presentation/features/account/screens/delete_account_screen.dart
//
// PUBLIC na Delete Account page (`/delete-account`) — ito ang Google Play
// "Delete Account URL": https://www.jireta.com/delete-account
//
// Dalawang paraan:
//   1. Naka-log-in na lender/rider → agad na deletion (`account-delete?fn=delete-self`).
//      Hinaharangan ng server kapag may active/overdue loan.
//   2. Walang login (o staff account) → request form
//      (`account-delete?fn=request`) na sinusuri ng staff bago iproseso.
//
// Hinding-hindi nagbabalik ang page ng "existing account ba ito" — generic ang
// sagot para hindi maging account-enumeration tool.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/security/secure_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/datasources/remote/account_deletion_remote_datasource.dart';
import '../../../shared/providers/auth_state_provider.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _requestFormKey = GlobalKey<FormState>();
  final _deleteFormKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _acknowledged = false;
  bool _showManualRequest = false;
  String? _error;
  String? _ackError;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _nameCtrl.dispose();
    _reasonCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool _isSelfServiceRole(String? role) =>
      role == AppConstants.roleLender || role == AppConstants.roleRider;

  String? _validateIdentifier(String? value) {
    final input = (value ?? '').trim();
    if (input.isEmpty) {
      return 'Enter your registered mobile number or email.';
    }
    if (input.contains('@')) {
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(input)) {
        return 'Enter a valid email address.';
      }
      return null;
    }
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^(09\d{9}|639\d{9}|9\d{9})$').hasMatch(digits)) {
      return 'Enter a valid PH mobile number (e.g. 09XXXXXXXXX).';
    }
    return null;
  }

  String _messageFor(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final serverError = data['error'];
        if (serverError is Map && serverError['message'] is String) {
          final message = (serverError['message'] as String).trim();
          if (message.isNotEmpty) return message;
        }
      }
      if (error.response?.statusCode == 401) {
        return 'Your session expired. Please sign in again.';
      }
      if (error.response?.statusCode == 429) {
        return 'Too many requests. Please wait a few minutes and try again.';
      }
    }
    return 'Something went wrong. Please check your connection and try again.';
  }

  Future<void> _submitSelfDeletion() async {
    if (_loading) return;
    if (!(_deleteFormKey.currentState?.validate() ?? false)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently removes your profile, contact details, uploaded '
          'documents, and login access. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await sl<AccountDeletionRemoteDataSource>().deleteSelf(
        confirmation: _confirmCtrl.text.trim(),
        reason: _reasonCtrl.text,
      );
      if (!mounted) return;

      final deletion = result['deletion'];
      final cancelled = deletion is Map ? deletion['cancelled_loans'] : 0;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Account deleted'),
          content: Text(
            'Your account and personal data have been deleted.'
            '${cancelled is int && cancelled > 0 ? '\n\n$cancelled pending loan application(s) were cancelled.' : ''}'
            '\n\nLoan, payment, disbursement, collection, and audit records '
            'are retained for the period required by law.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );

      // Hard sign-out (hindi ang MPIN "lock" na ginagamit ng normal logout):
      // wala nang account na babalikan, kaya dapat maalis lahat ng lokal na
      // session at hindi na muling magpakita ng MPIN screen.
      try {
        await ref.read(authStateProvider.notifier).logout();
      } catch (_) {}
      // Kung tumigil ang logout sa gitna (hal. revoke call), tiyaking wala nang
      // natirang local session o MPIN lock — wala nang account na mai-unlock.
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      try {
        await SecureStorage.clearAll();
      } catch (_) {}
      if (!mounted) return;
      context.go(RouteConstants.landing);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitPublicRequest() async {
    if (_loading) return;
    if (!(_requestFormKey.currentState?.validate() ?? false)) return;
    if (!_acknowledged) {
      setState(() {
        _ackError = 'Please confirm that you understand how deletion works.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _ackError = null;
    });

    try {
      final result =
          await sl<AccountDeletionRemoteDataSource>().requestDeletion(
        identifier: _identifierCtrl.text.trim(),
        fullName: _nameCtrl.text.trim(),
        reason: _reasonCtrl.text,
      );
      if (!mounted) return;

      final reference = (result['reference'] ?? '').toString();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Deletion request received'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Keep this reference. Our team will verify your identity and '
                'process the request within 7 business days.',
              ),
              if (reference.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Reference',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  reference,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.deepNavy,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      _identifierCtrl.clear();
      _nameCtrl.clear();
      _reasonCtrl.clear();
      setState(() {
        _acknowledged = false;
        _showManualRequest = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final role = auth.role;
    final canSelfDelete = auth.isAuthenticated && _isSelfServiceRole(role);
    final isStaff = auth.isAuthenticated && !canSelfDelete;

    return Scaffold(
      backgroundColor: AppColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.deepNavy,
        title: const Text(
          'Delete Account',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildWarning(),
                  const SizedBox(height: 16),
                  const _SectionCard(
                    icon: Icons.person_remove_outlined,
                    iconColor: AppColors.error,
                    title: 'What will be deleted',
                    bullets: [
                      'Your account and login access',
                      'Name, mobile number, email, and profile photo',
                      'Addresses and emergency contacts',
                      'Uploaded ID / KYC / account-upgrade documents',
                      'MPIN, devices, push tokens, and notifications',
                    ],
                  ),
                  const SizedBox(height: 12),
                  const _SectionCard(
                    icon: Icons.account_balance_outlined,
                    iconColor: AppColors.info,
                    title: 'What we keep',
                    intro:
                        'Jireta Loans is a lending company. Philippine law and '
                        'accounting rules require us to keep financial records.',
                    bullets: [
                      'Loan applications and schedules',
                      'Payments and official receipts',
                      'Disbursements and collection records',
                      'Security and audit logs',
                    ],
                    footer:
                        'These records no longer show your name or contact details. '
                        'They are kept only for the required retention period.',
                  ),
                  if (auth.isLoading) ...[
                    const SizedBox(height: 20),
                    const Center(child: CircularProgressIndicator()),
                  ] else if (canSelfDelete) ...[
                    const SizedBox(height: 20),
                    if (!_showManualRequest) ...[
                      _buildSelfDeleteCard(),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() => _showManualRequest = true),
                          child: const Text(
                            'Submit a request for manual review instead',
                          ),
                        ),
                      ),
                    ] else ...[
                      _buildRequestCard(),
                      Center(
                        child: TextButton(
                          onPressed: _loading
                              ? null
                              : () =>
                                  setState(() => _showManualRequest = false),
                          child: const Text('Back to instant deletion'),
                        ),
                      ),
                    ],
                  ] else ...[
                    if (isStaff) ...[
                      const SizedBox(height: 20),
                      _buildStaffNotice(),
                    ],
                    const SizedBox(height: 20),
                    _buildRequestCard(),
                  ],
                  const SizedBox(height: 24),
                  _buildSupportFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      decoration: BoxDecoration(
        color: AppColors.deepNavy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.delete_forever_outlined,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delete your Jireta Loans account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'You can delete your account from inside the app, or submit '
                  'a request here if you can no longer sign in.',
                  style: TextStyle(
                    color: Color(0xFFD3DAE4),
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarning() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 19, color: AppColors.error),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Account deletion is permanent. You will not be able to sign in '
              'again with this account, and the same mobile number or email '
              'can be used to create a new one afterwards.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelfDeleteCard() {
    return _CardShell(
      child: Form(
        key: _deleteFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Delete this account now',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.deepNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This works immediately if you have no active or overdue loan. '
              'If you still owe a balance, settle it first — the request will '
              'be blocked until then.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reasonCtrl,
              enabled: !_loading,
              maxLength: 500,
              minLines: 1,
              maxLines: 3,
              decoration: _inputDecoration(
                label: 'Reason (optional)',
                hint: 'Tell us why you are leaving',
                icon: Icons.chat_bubble_outline_rounded,
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _confirmCtrl,
              enabled: !_loading,
              textCapitalization: TextCapitalization.characters,
              validator: (value) {
                if ((value ?? '').trim().toUpperCase() != 'DELETE') {
                  return 'Type DELETE to confirm.';
                }
                return null;
              },
              decoration: _inputDecoration(
                label: 'Type DELETE to confirm',
                hint: 'DELETE',
                icon: Icons.keyboard_outlined,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorBox(message: _error!),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _loading ? null : _submitSelfDeletion,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_outline_rounded, size: 19),
                label: Text(_loading ? 'Deleting…' : 'Delete my account'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 19, color: AppColors.info),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Staff accounts (head manager / employee) are managed by HR or '
              'the system administrator and cannot be deleted from this page. '
              'You can still submit a request below for manual handling.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.info,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard() {
    return _CardShell(
      child: Form(
        key: _requestFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Request deletion without signing in',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.deepNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter the details registered to your account. Our team will '
              'verify that the request came from the account owner before '
              'deleting anything.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _identifierCtrl,
              enabled: !_loading,
              keyboardType: TextInputType.emailAddress,
              validator: _validateIdentifier,
              decoration: _inputDecoration(
                label: 'Registered mobile number or email',
                hint: '09XXXXXXXXX or you@example.com',
                icon: Icons.alternate_email_rounded,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              enabled: !_loading,
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                final name = (value ?? '').trim();
                if (name.length < 2) {
                  return 'Enter the full name on the account.';
                }
                return null;
              },
              decoration: _inputDecoration(
                label: 'Full name on the account',
                hint: 'Juan Dela Cruz',
                icon: Icons.badge_outlined,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reasonCtrl,
              enabled: !_loading,
              maxLength: 500,
              minLines: 1,
              maxLines: 3,
              decoration: _inputDecoration(
                label: 'Reason (optional)',
                hint: 'Tell us why you want to delete your account',
                icon: Icons.chat_bubble_outline_rounded,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _acknowledged,
                  activeColor: AppColors.deepNavy,
                  onChanged: _loading
                      ? null
                      : (value) => setState(() {
                            _acknowledged = value ?? false;
                            if (_acknowledged) _ackError = null;
                          }),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: GestureDetector(
                    onTap: _loading
                        ? null
                        : () => setState(() {
                              _acknowledged = !_acknowledged;
                              if (_acknowledged) _ackError = null;
                            }),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'I understand that my account and personal data will be '
                        'deleted, and that loan and payment records are kept as '
                        'required by law.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_ackError != null) ...[
              const SizedBox(height: 6),
              Text(
                _ackError!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              _ErrorBox(message: _error!),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _loading ? null : _submitPublicRequest,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.deepNavy,
                  foregroundColor: Colors.white,
                ),
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(
                  _loading ? 'Submitting…' : 'Submit deletion request',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportFooter() {
    return const Column(
      children: [
        Text(
          'Need help?',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        SizedBox(height: 4),
        SelectableText(
          AppConstants.supportEmail,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.info,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Jireta Loans & Credit Corp. · Sta. Barbara, Pangasinan',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
      ],
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
      filled: true,
      fillColor: AppColors.surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.deepNavy, width: 1.4),
      ),
      labelStyle:
          const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.bullets,
    this.intro,
    this.footer,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final List<String> bullets;
  final String? intro;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.deepNavy,
                  ),
                ),
              ),
            ],
          ),
          if (intro != null) ...[
            const SizedBox(height: 10),
            Text(
              intro!,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          for (final bullet in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.remove_circle_outline_rounded,
                      size: 15,
                      color: iconColor.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      bullet,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (footer != null) ...[
            const SizedBox(height: 4),
            Text(
              footer!,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              message,
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
    );
  }
}

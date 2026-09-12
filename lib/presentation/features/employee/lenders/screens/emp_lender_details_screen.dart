// lib/presentation/features/employee/lenders/screens/emp_lender_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../core/di/injection.dart';
import '../../../../shared/widgets/details/details_actions_card.dart';
import '../../../../shared/widgets/dialogs/confirmation_dialog.dart';
import '../../../../shared/widgets/details/details_section_card.dart';
import '../../../../shared/widgets/details/user_profile_header_card.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/providers/auth_state_provider.dart';
import '../widgets/emp_edit_lender_modal.dart';

final _lenderDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final ds = sl<UserRemoteDataSource>();
  return await ds.getProfileMap(userId: id);
});

final _empLenderLoansProvider =
    FutureProvider.family<List<dynamic>, String>((ref, lenderId) async {
  try {
    final res =
        await sl<LoanRemoteDataSource>().getList(lenderId: lenderId, limit: 50);
    return (res['data'] as List? ?? []).toList();
  } catch (_) {
    return [];
  }
});

class EmpLenderDetailsScreen extends ConsumerWidget {
  final String lenderId;
  const EmpLenderDetailsScreen({super.key, required this.lenderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_lenderDetailProvider(lenderId));
    final authState = ref.watch(authStateProvider);
    final canEdit = authState.role == 'head_manager';

    return WebScaffold(
      title: 'Lender Details',
      actions: [
        TextButton.icon(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back'),
        ),
        const SizedBox(width: 8),
        if (canEdit) ...[
          OutlinedButton.icon(
            onPressed: () => state.whenData((data) => _showEdit(context, data)),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
          ),
          const SizedBox(width: 12),
        ],
      ],
      body: state.when(
        loading: () => _buildShimmer(),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (data) => _buildContent(context, ref, data),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, Map<String, dynamic> data) {
    final name =
        '${data['first_name'] ?? ''} ${data['last_name'] ?? ''}'.trim();
    final lp = data['lender_profiles'] as Map<String, dynamic>?;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserProfileHeaderCard(
            photoUrl: data['profile_photo_url'] as String?,
            name: name.isEmpty ? 'Lender' : name,
            subtitle: data['email'] ?? '—',
            subtitleIcon: Icons.email_outlined,
            roleLabel: 'Lender',
            roleIcon: Icons.account_balance_wallet_outlined,
            accentColor: AppColors.lenderBlue,
            accountStatus: data['account_status'] ?? 'active',
          ),
          const SizedBox(height: 20),
          DetailsSectionCard(
            title: 'Personal Information',
            icon: Icons.person_outline,
            accentColor: AppColors.lenderBlue,
            items: [
              DetailsItem('Gender', lp?['gender'] ?? '—'),
              DetailsItem('Civil Status', lp?['civil_status'] ?? '—'),
              DetailsItem(
                'Date of Birth',
                (lp?['date_of_birth'] ?? '').toString().length >= 10
                    ? (lp?['date_of_birth'] ?? '').toString().substring(0, 10)
                    : (lp?['date_of_birth'] ?? '—').toString(),
              ),
              // 00128: financial details live on the LOAN application, not on
              // the lender profile.
            ],
          ),
          const SizedBox(height: 20),
          DetailsSectionCard(
            title: 'Contact Information',
            icon: Icons.phone_outlined,
            accentColor: AppColors.lenderBlue,
            items: [
              DetailsItem('Phone', data['phone_number'] ?? data['phone'] ?? '—'),
              DetailsItem('Email', data['email'] ?? '—'),
            ],
          ),
          const SizedBox(height: 20),
          DetailsSectionCard(
            title: 'Address',
            icon: Icons.location_on_outlined,
            accentColor: AppColors.lenderBlue,
            items: [
              DetailsItem('Street', data['street_address'] ?? '—'),
              DetailsItem('Barangay', data['barangay'] ?? '—'),
              DetailsItem('City', data['city'] ?? '—'),
              DetailsItem('Province', data['province'] ?? '—'),
              DetailsItem('Zip Code', data['zip_code'] ?? '—'),
            ],
          ),
          const SizedBox(height: 20),
          DetailsSectionCard(
            title: 'Account',
            icon: Icons.account_circle_outlined,
            accentColor: AppColors.lenderBlue,
            items: [
              DetailsItem('Account Status', data['account_status'] ?? '—'),
              DetailsItem(
                'Created At',
                (data['created_at'] ?? '').toString().length >= 10
                    ? (data['created_at'] ?? '').toString().substring(0, 10)
                    : (data['created_at'] ?? '—').toString(),
              ),
              DetailsItem(
                'Account Upgrade',
                '',
                valueWidget: StatusBadge(
                  status: lp?['account_upgrade_status'] ??
                      data['account_upgrade_status'] ??
                      'not_submitted',
                  small: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _EmpPreviousLoans(lenderId: lenderId),
          const SizedBox(height: 20),
          DetailsActionsCard(
            title: 'Actions',
            icon: Icons.settings_outlined,
            accentColor: AppColors.lenderBlue,
            actions: [
              // Escalation pause (00152) — pangalawa nang natapos ang loan
              // term ng lender na may utang. HM o Employee ang nag-a-unpause.
              if (data['account_status'] == 'paused')
                OutlinedButton.icon(
                  onPressed: () => _unpauseAccount(context, ref, lenderId),
                  icon: const Icon(Icons.lock_open_rounded, size: 18),
                  label: const Text('Unpause Account'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.success,
                    side: const BorderSide(color: AppColors.success),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() => ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, __) => const ShimmerLoader(height: 180),
      );

  void _showEdit(BuildContext context, Map<String, dynamic> data) {
    showDialog(
        context: context, builder: (_) => EmpEditLenderModal(lenderData: data));
  }

  /// Inaalis ang escalation pause (00152). Ang action na ito (sa backend) ay
  /// lender-only at 'paused' → 'active' lang ang binabago, kasama ang audit
  /// log — hindi ito bukas na pag-edit ng user record.
  Future<void> _unpauseAccount(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Unpause Account',
      message: 'Reactivate this lender\u2019s account? They will be able to use '
          'the app and apply for a new loan again. Their outstanding balances '
          'are not cleared.',
      confirmLabel: 'Unpause',
      confirmColor: AppColors.success,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await sl<UserRemoteDataSource>().unpauseLender(id);
      ref.invalidate(_lenderDetailProvider(id));
      if (context.mounted) context.showToast('Account reactivated');
    } catch (e) {
      if (context.mounted) {
        context.showErrorToast(
            'Failed to unpause: ${e.toString().replaceAll('Exception: ', '')}');
      }
    }
  }
}

class _EmpPreviousLoans extends ConsumerWidget {
  final String lenderId;
  const _EmpPreviousLoans({required this.lenderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(_empLenderLoansProvider(lenderId));
    return DetailsSectionCard(
      title: 'Previous Loans',
      icon: Icons.history_rounded,
      accentColor: AppColors.lenderBlue,
      items: const [],
      footer: loansAsync.when(
        loading: () => const SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, __) => const SizedBox.shrink(),
        data: (loans) {
          if (loans.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No previous loans found for this lender.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            );
          }
          return Column(
            children: loans.take(10).map((e) {
              final m = e is Map<String, dynamic> ? e : <String, dynamic>{};
              final loanNum = m['loan_number']?.toString() ?? '—';
              final status = m['status']?.toString() ?? '—';
              final principal =
                  (m['principal_amount'] as num?)?.toDouble() ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(loanNum,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text('₱${principal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ]),
                    ),
                    StatusBadge(status: status, small: true),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

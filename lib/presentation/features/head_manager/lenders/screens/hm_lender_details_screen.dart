// lib/presentation/features/head_manager/lenders/screens/hm_lender_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/details/details_actions_card.dart';
import '../../../../shared/widgets/details/details_section_card.dart';
import '../../../../shared/widgets/details/user_profile_header_card.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/hm_lender_provider.dart';

final _lenderDetailProvider = FutureProvider.family<UserModel, String>((
  ref,
  id,
) async {
  return sl<UserRemoteDataSource>().getProfile(userId: id);
});

final _lenderLoansProvider =
    FutureProvider.family<List<dynamic>, String>((ref, lenderId) async {
  try {
    final res = await sl<LoanRemoteDataSource>()
        .getList(lenderId: lenderId, limit: 50);
    return (res['data'] as List? ?? []).toList();
  } catch (_) {
    return [];
  }
});

class HmLenderDetailsScreen extends ConsumerWidget {
  final String userId;
  const HmLenderDetailsScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_lenderDetailProvider(userId));
    return WebScaffold(
      title: 'Lender Details',
      actions: [
        TextButton.icon(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back'),
        ),
        const SizedBox(width: 8),
      ],
      body: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              ShimmerLoader(height: 140),
              SizedBox(height: 16),
              ShimmerLoader(height: 200),
            ],
          ),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (user) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserProfileHeaderCard(
                photoUrl: user.profilePhotoUrl,
                name: '${user.firstName} ${user.lastName}',
                subtitle: user.email ?? '—',
                subtitleIcon: Icons.email_outlined,
                roleLabel: 'Lender',
                roleIcon: Icons.account_balance_wallet_outlined,
                accentColor: AppColors.lenderBlue,
                accountStatus: user.accountStatus,
              ),
              const SizedBox(height: 20),
              DetailsSectionCard(
                title: 'Personal Information',
                icon: Icons.person_outline,
                accentColor: AppColors.lenderBlue,
                items: [
                  DetailsItem('Gender', user.gender ?? '—'),
                  DetailsItem('Civil Status', user.civilStatus ?? '—'),
                  DetailsItem(
                    'Date of Birth',
                    user.dateOfBirth?.toString().substring(0, 10) ?? '—',
                  ),
                  // 00128: financial details live on the LOAN application,
                  // not on the lender profile.
                ],
              ),
              const SizedBox(height: 20),
              DetailsSectionCard(
                title: 'Contact Information',
                icon: Icons.phone_outlined,
                accentColor: AppColors.lenderBlue,
                items: [
                  DetailsItem('Phone', user.phoneNumber ?? '—'),
                  DetailsItem('Email', user.email ?? '—'),
                ],
              ),
              const SizedBox(height: 20),
              DetailsSectionCard(
                title: 'Address',
                icon: Icons.location_on_outlined,
                accentColor: AppColors.lenderBlue,
                items: [
                  DetailsItem('Street', user.streetAddress ?? '—'),
                  DetailsItem('Barangay', user.barangay ?? '—'),
                  DetailsItem('City', user.city ?? '—'),
                  DetailsItem('Province', user.province ?? '—'),
                  DetailsItem('Zip Code', user.zipCode ?? '—'),
                ],
              ),
              const SizedBox(height: 20),
              DetailsSectionCard(
                title: 'Account',
                icon: Icons.account_circle_outlined,
                accentColor: AppColors.lenderBlue,
                items: [
                  DetailsItem('Account Status', user.accountStatus),
                  DetailsItem(
                    'Member Since',
                    user.createdAt.toString().substring(0, 10),
                  ),
                  DetailsItem(
                    'Account Upgrade',
                    '',
                    valueWidget: user.accountUpgradeStatus == null ||
                            user.accountUpgradeStatus!.isEmpty
                        ? const Text('—')
                        : StatusBadge(
                            status: user.accountUpgradeStatus!,
                            small: true,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              DetailsActionsCard(
                title: 'Actions',
                icon: Icons.settings_outlined,
                accentColor: AppColors.lenderBlue,
                actions: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref.read(hmLenderProvider.notifier).archive(user.id);
                      if (context.mounted) context.pop();
                    },
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: const Text('Archive'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _PreviousLoansCard(lenderId: user.id),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviousLoansCard extends ConsumerWidget {
  final String lenderId;
  const _PreviousLoansCard({required this.lenderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(_lenderLoansProvider(lenderId));
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
              final m = e is Map<String, dynamic>
                  ? e
                  : (e as dynamic).toJson() as Map<String, dynamic>;
              final loanNum = m['loan_number']?.toString() ?? '—';
              final status = m['status']?.toString() ?? '—';
              final principal =
                  (m['principal_amount'] as num?)?.toDouble() ?? 0;
              final outstanding =
                  (m['outstanding_balance'] as num?)?.toDouble();
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
                            Text(
                                '₱${principal.toStringAsFixed(2)}${outstanding != null ? ' · Outstanding: ₱${outstanding.toStringAsFixed(2)}' : ''}',
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
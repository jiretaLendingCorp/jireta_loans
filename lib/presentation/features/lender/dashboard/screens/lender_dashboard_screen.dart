// lib/presentation/features/lender/dashboard/screens/lender_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/animated/count_up_animation.dart';
import '../../account_upgrade/providers/lender_account_upgrade_provider.dart';
import '../../loans/providers/lender_loan_provider.dart';
import '../../profile/providers/lender_profile_provider.dart';
import '../providers/lender_dashboard_provider.dart';

class LenderDashboardScreen extends ConsumerStatefulWidget {
  const LenderDashboardScreen({super.key});

  @override
  ConsumerState<LenderDashboardScreen> createState() =>
      _LenderDashboardScreenState();
}

class _LenderDashboardScreenState extends ConsumerState<LenderDashboardScreen> {
  static const _riderNavItems = [
    MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard,
    ),
    MobileNavItem(
      icon: Icons.payment_outlined,
      activeIcon: Icons.payment,
      label: 'Payments',
      route: RouteConstants.lenderPayments,
    ),
    MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.lenderProfile,
    ),
  ];

  LoanModel? _approvedUnreleased(List<LoanModel> loans) {
    for (final loan in loans) {
      if (loan.status == 'approved' && loan.disbursedAt == null) {
        return loan;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lenderDashboardProvider);
    final loanState = ref.watch(lenderLoanProvider);
    final profileState = ref.watch(lenderProfileProvider);

    final activeLoan = loanState.isLoading ? null : loanState.activeLoan;
    final approvedLoan = _approvedUnreleased(loanState.loans);

    return MobileScaffold(
      title: '',
      accentColor: AppColors.lenderBlue,
      navItems: _riderNavItems,
      appBarLeading: _AppBarAvatar(user: profileState.user),
      body: state.isLoading
          ? const ShimmerLoader()
          : RefreshIndicator(
              onRefresh: () async {
                await ref.read(lenderDashboardProvider.notifier).load();
                await ref.read(lenderLoanProvider.notifier).loadLoans();
                await ref.read(lenderProfileProvider.notifier).loadProfile();
                await ref
                    .read(lenderAccountUpgradeProvider.notifier)
                    .loadStatus();
              },
              color: AppColors.lenderBlue,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     _WelcomeBanner(user: profileState.user, kpi: state.kpi),
                    const SizedBox(height: 16),
                    const _ApplyNowRow(),
                    const SizedBox(height: 20),
                    const _LoanPromoText(),
                    const SizedBox(height: 24),
                    if (approvedLoan != null) ...[
                      _ApprovedLoanBanner(loan: approvedLoan),
                      const SizedBox(height: 20),
                    ],
                    if (activeLoan != null) ...[
                      _MyLoanCard(loan: activeLoan),
                      const SizedBox(height: 24),
                      _LoanHistorySection(
                        loans: loanState.loans,
                        activeLoanId: activeLoan.id,
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (state.error != null) _ErrorBanner(state.error!),
                  ],
                ),
              ),
            ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  final UserModel? user;
  final dynamic kpi;
  const _WelcomeBanner({required this.user, required this.kpi});

  String get _firstName => user?.firstName ?? '';

  @override
  Widget build(BuildContext context) {
    final firstName = _firstName;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.lenderBlue, AppColors.lenderBlueLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.lenderBlue.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            firstName.isNotEmpty ? 'Hello, $firstName!' : 'Hello!',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Here is your outstanding balance',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 20),
          const Text(
            'Outstanding Balance',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          CountUpAnimation(
            value: (kpi?.remainingBalance ?? 0).toDouble(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              fontFamily: 'PlayfairDisplay',
            ),
            prefix: '₱',
            decimalPlaces: 2,
          ),
        ],
      ),
    );
  }
}

class _AppBarAvatar extends StatelessWidget {
  final UserModel? user;
  const _AppBarAvatar({this.user});

  @override
  Widget build(BuildContext context) {
    final photo = user?.profilePhotoUrl;
    final name = user?.firstName ?? user?.lastName ?? '';
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 4),
      child: InkWell(
        onTap: () => context.push(RouteConstants.lenderProfile),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: photo != null && photo.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    photo,
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _initial(name),
                  ),
                )
              : _initial(name),
        ),
      ),
    );
  }

  Widget _initial(String name) {
    return Container(
      width: 34,
      height: 34,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white24,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ApprovedLoanBanner extends StatelessWidget {
  final LoanModel loan;
  const _ApprovedLoanBanner({required this.loan});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(RouteConstants.lenderLoans),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.lenderBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.lenderBlue.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: AppColors.lenderBlue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Loan #${loan.loanNumber} Approved',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Choose how you want to receive your funds to complete the release.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.lenderBlue),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplyNowRow extends StatelessWidget {
  const _ApplyNowRow();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(RouteConstants.lenderLoans),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: AppColors.lenderBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_circle_outline,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              'Apply Now',
              style: TextStyle(
                color: AppColors.lenderBlue,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right,
                color: AppColors.lenderBlue, size: 20),
          ],
        ),
      ),
    );
  }
}

class _LoanPromoText extends StatelessWidget {
  const _LoanPromoText();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('You can loan up to',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            )),
        SizedBox(height: 2),
        Text(
          '₱3,000 – ₱500,000',
          style: TextStyle(
            color: AppColors.lenderBlue,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'PlayfairDisplay',
          ),
        ),
        SizedBox(height: 4),
        Text(
          'with low interest rates and flexible payment terms.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _MyLoanCard extends StatelessWidget {
  final LoanModel loan;
  const _MyLoanCard({required this.loan});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('My Loan'),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => context.push(
            RouteConstants.lenderLoanDetails.replaceFirst(':id', loan.id),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.lenderBlue, AppColors.lenderBlueLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.lenderBlue.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        loan.status == 'overdue'
                            ? 'Overdue Loan'
                            : 'Active Loan',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    StatusBadge(status: loan.status, small: true),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Outstanding Balance',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                CountUpAnimation(
                  value: loan.outstandingBalance,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'PlayfairDisplay',
                  ),
                  prefix: '₱',
                  decimalPlaces: 2,
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Payable',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      loan.totalPayable.toCurrency,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _LoanHistorySection extends StatelessWidget {
  final List<LoanModel> loans;
  final String activeLoanId;

  const _LoanHistorySection({
    required this.loans,
    required this.activeLoanId,
  });

  @override
  Widget build(BuildContext context) {
    final pastLoans = loans.where((l) => l.id != activeLoanId).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _SectionLabel('Loan History'),
            GestureDetector(
              onTap: () => context.push(RouteConstants.lenderLoanHistory),
              child: const Row(
                children: [
                  Text(
                    'View All',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.lenderBlue,
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 16, color: AppColors.lenderBlue),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (pastLoans.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.history_outlined,
                    color: AppColors.textTertiary, size: 20),
                SizedBox(width: 10),
                Text(
                  'No past loans yet',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          )
        else
          ...pastLoans.take(3).map(
                (loan) => _LoanHistoryTile(
                  loan: loan,
                  onTap: () => context.push(
                    RouteConstants.lenderLoanDetails
                        .replaceFirst(':id', loan.id),
                  ),
                ),
              ),
      ],
    );
  }
}

class _LoanHistoryTile extends StatelessWidget {
  final LoanModel loan;
  final VoidCallback onTap;

  const _LoanHistoryTile({required this.loan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      loan.loanNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    StatusBadge(status: loan.status, small: true),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Principal',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.textSecondary)),
                        Text(
                          loan.principalAmount.toCurrency,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Total Payable',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.textSecondary)),
                        Text(
                          loan.totalPayable.toCurrency,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.lenderBlue),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Applied: ${loan.createdAt.toDateString()}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String error;
  const _ErrorBanner(this.error);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
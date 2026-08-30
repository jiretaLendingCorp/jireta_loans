// lib/presentation/features/lender/dashboard/screens/lender_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rive/rive.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/widgets/animated/count_up_animation.dart';
import '../../../../shared/widgets/layout/mobile_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../loans/providers/lender_loan_provider.dart';
import '../../profile/providers/lender_profile_provider.dart';
import '../providers/lender_dashboard_provider.dart';
import 'widgets/lender_rider_tracking_card.dart';

class LenderDashboardScreen extends ConsumerStatefulWidget {
  const LenderDashboardScreen({super.key});

  @override
  ConsumerState<LenderDashboardScreen> createState() =>
      _LenderDashboardScreenState();
}

class _LenderDashboardScreenState extends ConsumerState<LenderDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;

  static const _riderNavItems = [
    MobileNavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      route: RouteConstants.lenderDashboard,
    ),
    MobileNavItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      label: 'Payments',
      route: RouteConstants.lenderPayments,
    ),
    MobileNavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'History',
      route: RouteConstants.lenderPaymentHistory,
    ),
    MobileNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
      route: RouteConstants.lenderProfile,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  static const _inReviewStatuses = {
    'pending',
    'under_review',
    'ci_required',
    'ci_assigned',
    'ci_completed',
    'ci_approved',
  };

  LoanModel? _approvedUnreleased(List<LoanModel> loans) {
    for (final loan in loans) {
      if (loan.status == 'approved' && loan.disbursedAt == null) {
        return loan;
      }
    }
    return null;
  }

  LoanModel? _inReviewLoan(List<LoanModel> loans) {
    for (final loan in loans) {
      if (_inReviewStatuses.contains(loan.status)) {
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
    final activeLoan = loanState.activeLoan;
    final approvedLoan = _approvedUnreleased(loanState.loans);
    final inReviewLoan = _inReviewLoan(loanState.loans);
    // Keep showing the loader until loans are resolved so the "no active loan"
    // layout (balance card / overview) never flashes before the active loan.
    final showLoanLoader = loanState.isLoading && loanState.loans.isEmpty;

    return MobileScaffold(
      title: 'My Account',
      accentColor: AppColors.lenderBlue,
      navItems: _riderNavItems,
      body: state.isLoading || showLoanLoader
          ? const ShimmerLoader()
          : RefreshIndicator(
              onRefresh: () async {
                await ref.read(lenderDashboardProvider.notifier).load();
                await ref.read(lenderLoanProvider.notifier).loadLoans();
              },
              color: AppColors.lenderBlue,
              child: FadeTransition(
                opacity: _fadeCtrl,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  // Extra bottom space so the last item rests level with
                  // the floating pill of the bottom nav bar when scrolled.
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WelcomeBanner(
                        kpi: state.kpi,
                        firstName: profileState.user?.firstName,
                        showBalance: activeLoan == null,
                      ),
                      const SizedBox(height: 16),
                      if (approvedLoan != null && activeLoan == null) ...[
                        _ApprovedLoanBanner(loan: approvedLoan),
                        const SizedBox(height: 20),
                      ],
                      if (activeLoan == null) ...[
                        if (inReviewLoan != null)
                          _PendingLoanCard(loan: inReviewLoan)
                        else if (approvedLoan == null)
                          _QuickActions(context: context),
                        const SizedBox(height: 20),
                      ],
                      if (activeLoan != null) ...[
                        Transform.translate(
                          offset: const Offset(0, -14),
                          child: _MyLoanCard(loan: activeLoan),
                        ),
                        const SizedBox(height: 6),
                      ] else
                        _MyLoansOverview(kpi: state.kpi),
                      // Loan History renders with or without an active loan —
                      // a lender whose only loan is already completed must
                      // still see it here.
                      _LoanHistorySection(
                        loans: loanState.loans,
                        activeLoanId: activeLoan?.id ?? '',
                      ),
                      const LenderRiderTrackingCard(),
                      const SizedBox(height: 20),
                      if (state.error != null) _ErrorBanner(state.error!),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  final dynamic kpi;
  final String? firstName;
  final bool showBalance;
  const _WelcomeBanner(
      {required this.kpi, this.firstName, this.showBalance = true});

  @override
  Widget build(BuildContext context) {
    if (!showBalance) {
      return Align(
        alignment: Alignment.topRight,
        child: _FoxyRiveGroup(firstName: firstName),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -10,
          right: 4,
          child: _FoxyRiveGroup(firstName: firstName),
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 95),
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
              const SizedBox(height: 16),
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
        ),
      ],
    );
  }
}

class _FoxyRiveGroup extends StatelessWidget {
  final String? firstName;
  const _FoxyRiveGroup({this.firstName});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _GoodMorningBubble(name: firstName),
        const SizedBox(width: 6),
        const SizedBox(
          width: 118,
          height: 118,
          child: _FoxyRive(),
        ),
      ],
    );
  }
}

class _GoodMorningBubble extends StatefulWidget {
  final String? name;
  const _GoodMorningBubble({this.name});

  @override
  State<_GoodMorningBubble> createState() => _GoodMorningBubbleState();
}

class _GoodMorningBubbleState extends State<_GoodMorningBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final name = widget.name?.trim() ?? '';
    final message = name.isEmpty ? '$greeting!' : '$greeting, $name!';

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.6, 0.4),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack)),
      child: FadeTransition(
        opacity: _ctrl,
        child: Container(
          margin: const EdgeInsets.only(top: 26),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(
                message,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Positioned(
                right: -8,
                bottom: -10,
                child: ClipPath(
                  clipper: _BubbleTailClipper(),
                  child: Container(
                    width: 16,
                    height: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BubbleTailClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _BubbleTailClipper oldClipper) => false;
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
                    Text(
                      loan.disbursementMethod == null
                          ? 'Choose how you want to receive your funds to complete the release.'
                          : 'Your funds are being prepared. We will notify you once your loan is released.',
                      style: const TextStyle(
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

class _QuickActions extends StatelessWidget {
  final BuildContext context;
  const _QuickActions({required this.context});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(RouteConstants.lenderLoans),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.lenderBlue, AppColors.lenderBlueLight],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.lenderBlue.withValues(alpha: 0.3),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.arrow_forward, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Apply Now',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingLoanCard extends StatelessWidget {
  final LoanModel loan;
  const _PendingLoanCard({required this.loan});

  String _titleForStatus(String status, String? ciStatus) {
    switch (status) {
      case 'ci_required':
        return 'CI Required';
      case 'ci_assigned':
        if (ciStatus == 'assigned') return 'Rider Assigned for CI';
        if (ciStatus == 'in_progress' || ciStatus == 'accepted') return 'CI In Progress';
        return 'Credit Investigation';
      case 'ci_completed':
        if (ciStatus == 'completed') return 'CI Submitted — Awaiting Approval';
        if (ciStatus == 'approved') return 'CI Approved';
        if (ciStatus == 'rejected') return 'CI Needs Review';
        return 'CI Completed';
      default:
        return 'Loan #${loan.loanNumber} Under Review';
    }
  }

  String _subtitleForStatus(String status, String? ciStatus) {
    switch (status) {
      case 'pending':
        return 'Your application has been submitted. Track its progress here.';
      case 'under_review':
        return 'Our team is reviewing your application.';
      case 'ci_required':
        return 'A credit investigation is required. A rider will be assigned soon.';
      case 'ci_assigned':
        if (ciStatus == 'assigned') return 'A rider has been assigned and will visit your address for verification.';
        if (ciStatus == 'in_progress' || ciStatus == 'accepted') return 'Rider is conducting the investigation. Please be available at your address.';
        return 'Credit investigation is in progress.';
      case 'ci_completed':
        if (ciStatus == 'completed') return 'Rider submitted the report. Manager is reviewing it before approval & disbursement.';
        if (ciStatus == 'approved') return 'Investigation approved! Awaiting final loan approval. You\'ll choose disbursement method after approval.';
        if (ciStatus == 'rejected') return 'Investigation needs additional review. Our team will contact you.';
        return 'Investigation completed. Awaiting manager approval.';
      default:
        return 'Track the progress of your loan application.';
    }
  }

  IconData _iconForStatus(String status, String? ciStatus) {
    switch (status) {
      case 'ci_assigned':
        return Icons.delivery_dining_rounded;
      case 'ci_completed':
        if (ciStatus == 'completed') return Icons.rate_review_rounded;
        if (ciStatus == 'approved') return Icons.verified_rounded;
        if (ciStatus == 'rejected') return Icons.report_problem_rounded;
        return Icons.assignment_turned_in_rounded;
      case 'ci_required':
        return Icons.search_rounded;
      default:
        return Icons.hourglass_top;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _titleForStatus(loan.status, loan.ciStatus);
    final subtitle = _subtitleForStatus(loan.status, loan.ciStatus);
    final icon = _iconForStatus(loan.status, loan.ciStatus);
    final isAwaitingApproval = loan.status == 'ci_completed' && loan.ciStatus == 'completed';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(
          RouteConstants.lenderLoanApplicationStatus.replaceFirst(':id', loan.id),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isAwaitingApproval ? AppColors.warning.withValues(alpha: 0.12) : AppColors.warningLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isAwaitingApproval ? AppColors.warning : AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isAwaitingApproval ? AppColors.warning : AppColors.warning,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    if (isAwaitingApproval) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.warning.withValues(alpha: 0.3))),
                        child: const Text('Manager approval required before you can choose disbursement method', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.warning)),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.warning),
            ],
          ),
        ),
      ),
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

class _MyLoanCard extends StatelessWidget {
  final LoanModel loan;
  const _MyLoanCard({required this.loan});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: () => context.push(
              RouteConstants.lenderPaymentMethod,
              extra: {'loan_id': loan.id},
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.lenderBlue),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.payment, size: 18, color: AppColors.lenderBlue),
                  SizedBox(width: 8),
                  Text('Pay',
                      style: TextStyle(
                        color: AppColors.lenderBlue,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          ),
        ),
      ],
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
            const _SectionLabel('Recent Transactions'),
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
                Icon(Icons.receipt_long_outlined,
                    color: AppColors.textTertiary, size: 20),
                SizedBox(width: 10),
                Text(
                  'No transactions yet',
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
    final status = loan.status.toLowerCase();
    final Color accent;
    final IconData icon;
    if (status == 'active') {
      accent = AppColors.lenderBlue;
      icon = Icons.account_balance_wallet_rounded;
    } else if (status == 'approved') {
      accent = AppColors.success;
      icon = Icons.check_circle_rounded;
    } else if (status == 'rejected') {
      accent = AppColors.error;
      icon = Icons.cancel_rounded;
    } else if (['pending', 'under_review', 'ci_required', 'ci_assigned', 'ci_completed'].contains(status)) {
      accent = AppColors.warning;
      icon = Icons.hourglass_top_rounded;
    } else {
      accent = AppColors.textTertiary;
      icon = Icons.receipt_long_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: accent.withValues(alpha: 0.15)),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loan.loanNumber, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(loan.createdAt.toDateString(), style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                      const SizedBox(height: 2),
                      Text(loan.paymentFrequency.toUpperCase(), style: const TextStyle(fontSize: 10, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(loan.principalAmount.toCurrency, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    StatusBadge(status: loan.status, small: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MyLoansOverview extends StatelessWidget {
  final dynamic kpi;
  const _MyLoansOverview({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final submitted = kpi?.totalApplications ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Need cash now?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: AppColors.lenderBlue,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Borrow from ₱3,000\nto ₱500,000',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 26,
            height: 1.2,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Fast approval · Flexible terms · Low monthly rates\n'
          'Apply today and get the cash you need, right when you need it.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          submitted == 1
              ? '$submitted application submitted so far'
              : '$submitted applications submitted so far',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary,
          ),
        ),
      ],
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

class _FoxyRive extends StatefulWidget {
  const _FoxyRive();

  @override
  State<_FoxyRive> createState() => _FoxyRiveState();
}

class _FoxyRiveState extends State<_FoxyRive> {
  late final FileLoader _loader;

  @override
  void initState() {
    super.initState();
    _loader = FileLoader.fromAsset(
      'assets/rive/foxy.riv',
      riveFactory: Factory.rive,
    );
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RiveWidgetBuilder(
      fileLoader: _loader,
      builder: (context, state) => switch (state) {
        RiveLoading() => const SizedBox.shrink(),
        RiveFailed() => const SizedBox.shrink(),
        RiveLoaded() => RiveWidget(
            controller: state.controller,
            fit: Fit.contain,
            alignment: Alignment.bottomCenter,
          ),
      },
    );
  }
}

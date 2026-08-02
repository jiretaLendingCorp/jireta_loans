// lib/presentation/features/head_manager/dashboard/widgets/hm_kpi_cards_grid.dart
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/kpi_head_manager_model.dart';
import '../../../../shared/widgets/kpi_stat_card.dart';

class HmKpiCardsGrid extends StatelessWidget {
  final KpiHeadManagerModel kpi;

  const HmKpiCardsGrid({super.key, required this.kpi});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _KpiDef('Total Employees', kpi.totalEmployees, Icons.badge_outlined,
          AppColors.info),
      _KpiDef('Total Riders', kpi.totalRiders, Icons.two_wheeler,
          AppColors.riderGreen),
      _KpiDef('Total Lenders', kpi.totalLenders, Icons.people_outline,
          AppColors.lenderPurple),
      _KpiDef('Loan Applications', kpi.totalLoanApplications,
          Icons.description_outlined, AppColors.deepNavy),
      _KpiDef('Approved Loans', kpi.totalApproved, Icons.check_circle_outline,
          AppColors.success),
      _KpiDef('Rejected Loans', kpi.totalRejected, Icons.cancel_outlined,
          AppColors.error),
      _KpiDef(
          'Active Loans', kpi.totalActive, Icons.trending_up, AppColors.gold),
      _KpiDef('Completed Loans', kpi.totalCompleted, Icons.done_all,
          AppColors.info),
      _KpiDef('Overdue Loans', kpi.totalOverdue, Icons.warning_amber_outlined,
          AppColors.statusOverdue),
      _KpiDef('Amount Released', kpi.totalReleased, Icons.payments_outlined,
          AppColors.success, true),
      _KpiDef('Amount Collected', kpi.totalCollected,
          Icons.account_balance_wallet_outlined, AppColors.riderGreen, true),
      _KpiDef('Outstanding Balance', kpi.totalOutstanding,
          Icons.account_balance_outlined, AppColors.error, true),
      _KpiDef('Interest Earned', kpi.totalInterest, Icons.percent,
          AppColors.gold, true),
      _KpiDef('Penalties Collected', kpi.totalPenalties, Icons.gavel_outlined,
          AppColors.warning, true),
      _KpiDef('Total Revenue', kpi.totalRevenue, Icons.bar_chart,
          AppColors.deepNavy, true),
      _KpiDef('Collection Txns', kpi.totalCollectionTxns,
          Icons.receipt_outlined, AppColors.lenderPurple),
      _KpiDef('CI Assignments', kpi.totalCiAssignments,
          Icons.assignment_outlined, AppColors.info),
      _KpiDef('Report Exports', kpi.totalReportExports, Icons.download_outlined,
          AppColors.riderGreenDark),
      _KpiDef('Pending KYC', kpi.totalPendingKyc, Icons.pending_actions,
          AppColors.warning),
    ];

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final crossAxisCount = constraints.maxWidth < 800
            ? 2
            : constraints.maxWidth < 1200
                ? 3
                : 4;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.5,
          ),
          itemCount: cards.length,
          itemBuilder: (_, i) {
            final c = cards[i];
            return KpiStatCard(
              title: c.title,
              value: c.value,
              icon: c.icon,
              color: c.color,
              isCurrency: c.isCurrency,
            );
          },
        );
      },
    );
  }
}

class _KpiDef {
  final String title;
  final dynamic value;
  final IconData icon;
  final Color color;
  final bool isCurrency;
  const _KpiDef(this.title, this.value, this.icon, this.color,
      [this.isCurrency = false]);
}

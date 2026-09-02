// lib/presentation/features/head_manager/loans/screens/hm_loan_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/hm_loan_provider.dart';
import '../widgets/loan_details_modal.dart';

final hmActiveLoanProvider =
    AutoDisposeStateNotifierProvider<HmLoanNotifier, HmLoanState>((ref) {
  return HmLoanNotifier(sl<LoanRemoteDataSource>(), initialFilter: 'active');
});

class HmLoanListScreen extends ConsumerStatefulWidget {
  const HmLoanListScreen({super.key});

  @override
  ConsumerState<HmLoanListScreen> createState() => _HmLoanListScreenState();
}

class _HmLoanListScreenState extends ConsumerState<HmLoanListScreen> {
  final _searchCtrl = TextEditingController();

  final _tabs = const [
    _ActiveTab('active', 'Active', Icons.bolt_rounded),
    _ActiveTab('completed', 'Completed', Icons.verified_rounded),
    _ActiveTab('overdue', 'Overdue', Icons.warning_rounded),
    _ActiveTab('all', 'All History', Icons.history_rounded),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmActiveLoanProvider);
    final activeTab = state.tabFilter;

    return WebScaffold(
      title: 'Active Loans',
      body: Container(
        color: const Color(0xFFF0F2F5),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTabPills(activeTab),
              const SizedBox(height: 16),
              _buildToolbar(state),
              const SizedBox(height: 16),
              if (state.isLoading)
                _buildShimmer()
              else if (state.loans.isEmpty)
                _buildEmpty(state)
              else
                _Entrance(child: _buildTable(state.loans)),
              if (state.totalPages > 1) ...[
                const SizedBox(height: 16),
                _buildPagination(state),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Tabs ─────────────────────────
  Widget _buildTabPills(String active) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _tabs.map((t) {
          final isActive = t.key == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () =>
                  ref.read(hmActiveLoanProvider.notifier).setTab(t.key),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.deepNavy : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isActive ? AppColors.deepNavy : AppColors.border,
                      width: isActive ? 1.2 : 1),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.deepNavy.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.icon,
                        size: 14,
                        color: isActive
                            ? AppColors.gold
                            : AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      t.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color:
                            isActive ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ───────────────────────── Toolbar ─────────────────────────
  Widget _buildToolbar(HmLoanState state) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search loans...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) =>
                    ref.read(hmActiveLoanProvider.notifier).setSearch(v),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.deepNavy,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    '${state.loans.length} results',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ───────────────────────── Table ─────────────────────────
  Widget _buildTable(List<LoanModel> loans) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    final dateFmt = DateFormat('MMM dd, yyyy');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FB),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: const Row(
              children: [
                Expanded(
                    flex: 3,
                    child: _HLabel('Lender & Loan', Icons.person_outline)),
                Expanded(
                    flex: 2,
                    child: _HLabel('Principal', Icons.payments_outlined)),
                Expanded(
                    flex: 3,
                    child: _HLabel('Outstanding & Progress',
                        Icons.trending_up_rounded)),
                Expanded(
                    flex: 2, child: _HLabel('Due Date', Icons.event_outlined)),
                Expanded(
                    flex: 2, child: _HLabel('Status', Icons.flag_outlined)),
                SizedBox(
                    width: 80,
                    child: _HLabel('Actions', Icons.visibility_outlined,
                        alignEnd: true)),
              ],
            ),
          ),
          ...loans.asMap().entries.map((e) {
            final idx = e.key;
            final loan = e.value;
            final isEven = idx.isEven;
            final lenderName = (loan.lenderName ?? '').trim().isEmpty
                ? '${loan.lenderFirstName} ${loan.lenderLastName}'.trim()
                : (loan.lenderName ?? '').trim();
            final displayName =
                lenderName.isEmpty ? '—' : lenderName;
            final outstanding = loan.outstandingBalance;
            final totalPayable =
                loan.totalPayable > 0 ? loan.totalPayable : loan.principalAmount * 1.2;
            final progress = totalPayable > 0
                ? ((totalPayable - outstanding) / totalPayable)
                    .clamp(0.0, 1.0)
                : 0.0;
            final due = loan.dueDate;
            final daysLeft = due?.difference(nowManila()).inDays;

            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isEven ? Colors.white : const Color(0xFFFDFDFD),
                border: const Border(
                    bottom: BorderSide(color: Color(0xFFF0F0F0))),
              ),
              child: Row(
                children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.deepNavy
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              loan.loanNumber,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.deepNavy),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '₱${fmt.format(loan.principalAmount)}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary),
                          ),
                          Text(
                            'Payable ₱${fmt.format(totalPayable)}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '₱${fmt.format(outstanding)}',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: loan.displayStatus == 'overdue'
                                        ? AppColors.error
                                        : AppColors.textPrimary),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (progress >= 1
                                          ? AppColors.success
                                          : AppColors.deepNavy)
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${(progress * 100).toStringAsFixed(0)}%',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: progress >= 1
                                          ? AppColors.success
                                          : AppColors.deepNavy),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor:
                                  AppColors.border.withValues(alpha: 0.7),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                loan.displayStatus == 'overdue'
                                    ? AppColors.error
                                    : progress >= 1
                                        ? AppColors.success
                                        : AppColors.deepNavy,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            progress >= 1
                                ? 'Fully paid'
                                : '${fmt.format(totalPayable - outstanding)} collected',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            due != null ? dateFmt.format(due) : '—',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary),
                          ),
                          if (due != null)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _dueBg(daysLeft),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _dueLabel(daysLeft),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _dueColor(daysLeft)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusBadge(status: loan.displayStatus),
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _ViewButton(
                          onTap: () => showLoanDetailsModal(context, loan.id),
                          needsRider: _needsRiderAssignment(loan),
                        ),
                      ),
                    ),
                  ],
                ),
              );
          }),
        ],
      ),
    );
  }

  bool _needsRiderAssignment(LoanModel loan) {
    final status = loan.status.toLowerCase();
    // Needs CI rider when loan is pending/under_review/ci_required and no CI assigned yet
    if (['pending', 'under_review', 'ci_required'].contains(status) && (loan.ciStatus == null || loan.ciStatus!.isEmpty)) {
      return true;
    }
    // Needs delivery rider when loan is approved but no delivery rider assigned
    if (status == 'approved' && !loan.riderDeliveryAssigned) {
      return true;
    }
    return false;
  }

  Color _dueBg(int? daysLeft) {
    if (daysLeft == null) return AppColors.surfaceVariant;
    if (daysLeft < 0) return AppColors.error.withValues(alpha: 0.10);
    if (daysLeft <= 7) return AppColors.warning.withValues(alpha: 0.14);
    return AppColors.success.withValues(alpha: 0.10);
  }

  Color _dueColor(int? daysLeft) {
    if (daysLeft == null) return AppColors.textTertiary;
    if (daysLeft < 0) return AppColors.error;
    if (daysLeft <= 7) return AppColors.warning;
    return AppColors.success;
  }

  String _dueLabel(int? daysLeft) {
    if (daysLeft == null) return '—';
    if (daysLeft < 0) return '${daysLeft.abs()}d overdue';
    if (daysLeft == 0) return 'Due today';
    if (daysLeft == 1) return 'Due tomorrow';
    return 'Due in ${daysLeft}d';
  }

  Widget _buildShimmer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          6,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: AppColors.shimmerBase.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10))),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 12,
                        decoration: BoxDecoration(
                            color:
                                AppColors.shimmerBase.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 8),
                    Container(
                        height: 10,
                        width: 160,
                        decoration: BoxDecoration(
                            color: AppColors.shimmerHighlight
                                .withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(6))),
                  ],
                )),
                const SizedBox(width: 16),
                Container(
                    width: 86,
                    height: 28,
                    decoration: BoxDecoration(
                        color: AppColors.shimmerBase.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(20))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(HmLoanState state) {
    final isFiltered = state.search.isNotEmpty || state.tabFilter != 'all';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFiltered
                ? Icons.search_off_rounded
                : Icons.account_balance_wallet_outlined,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered ? 'No matching loans' : 'No loan records',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          if (isFiltered) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () {
                _searchCtrl.clear();
                ref.read(hmActiveLoanProvider.notifier).setSearch('');
                ref.read(hmActiveLoanProvider.notifier).setTab('active');
              },
              icon: const Icon(Icons.clear_all_rounded, size: 16),
              label: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPagination(HmLoanState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(
            'Page ${state.currentPage} of ${state.totalPages}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
          const Spacer(),
          _PageBtn(
            icon: Icons.chevron_left_rounded,
            enabled: state.currentPage > 1,
            onTap: () => ref
                .read(hmActiveLoanProvider.notifier)
                .fetchLoans(page: state.currentPage - 1),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${state.currentPage} / ${state.totalPages}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          _PageBtn(
            icon: Icons.chevron_right_rounded,
            enabled: state.currentPage < state.totalPages,
            onTap: () => ref
                .read(hmActiveLoanProvider.notifier)
                .fetchLoans(page: state.currentPage + 1),
          ),
        ],
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Support widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveTab {
  final String key;
  final String label;
  final IconData icon;
  const _ActiveTab(this.key, this.label, this.icon);
}






class _HLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool alignEnd;
  const _HLabel(this.text, this.icon, {this.alignEnd = false});

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textTertiary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    if (alignEnd) return Align(alignment: Alignment.centerRight, child: row);
    return row;
  }
}

class _ViewButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool needsRider;
  const _ViewButton({required this.onTap, this.needsRider = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: needsRider ? 'View — Rider needs assignment' : 'View',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.deepNavy.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.deepNavy.withValues(alpha: 0.14)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility_outlined, size: 14, color: AppColors.deepNavy),
                  SizedBox(width: 4),
                  Text('View',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.deepNavy)),
                ],
              ),
            ),
            if (needsRider)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.warning.withValues(alpha: 0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PageBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _PageBtn(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: enabled ? AppColors.border : AppColors.divider),
        ),
        child: Icon(icon,
            size: 18,
            color: enabled ? AppColors.textPrimary : AppColors.textTertiary),
      ),
    );
  }
}

class _Entrance extends StatefulWidget {
  final Widget child;
  const _Entrance({required this.child});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    final curved =
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _offset = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(curved);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

// lib/presentation/features/head_manager/loans/screens/hm_loan_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/hm_loan_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

class HmLoanDetailsScreen extends ConsumerStatefulWidget {
  final String loanId;
  const HmLoanDetailsScreen({super.key, required this.loanId});

  @override
  ConsumerState<HmLoanDetailsScreen> createState() =>
      _HmLoanDetailsScreenState();
}

class _HmLoanDetailsScreenState extends ConsumerState<HmLoanDetailsScreen> {
  Map<String, dynamic>? _loan;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data =
        await ref.read(hmLoanProvider.notifier).getLoanDetails(widget.loanId);
    if (!mounted) return;
    setState(() {
      _loan = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WebScaffold(
      title: 'Loan Details',
      actions: [
        TextButton.icon(
          onPressed: () => context.go(RouteConstants.hmLoans),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Back')),
        const SizedBox(width: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border)),
          child: IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded,
                size: 18, color: AppColors.textSecondary),
            tooltip: 'Refresh')),
        const SizedBox(width: 12),
      ],
      body: Container(
        color: const Color(0xFFF0F2F5),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loan == null
                ? _buildNotFound()
                : _buildContent()));
  }

  Widget _buildNotFound() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                shape: BoxShape.circle),
              child: const Icon(Icons.search_off_rounded,
                  size: 28, color: AppColors.error)),
            const SizedBox(height: 16),
            const Text('Loan not found',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text(
              'The loan may have been removed or the link is invalid.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => context.go(RouteConstants.hmLoans),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to Loans'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white)),
          ])));
  }

  Widget _buildContent() {
    final loan = _loan!;
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHero(loan, fmt),
          LayoutBuilder(
            builder: (context, c) {
              final isNarrow = c.maxWidth < 820;
              if (isNarrow) {
                return Column(
                  children: [
                    _buildLenderCard(loan),
                    const SizedBox(height: 16),
                    _buildLoanCard(loan, fmt),
                    const SizedBox(height: 16),
                    _buildDisbursementCard(loan, fmt),
                    const SizedBox(height: 16),
                    _buildScheduleCard(loan, fmt),
                    const SizedBox(height: 16),
                    _buildPaymentsCard(loan, fmt),
                    const SizedBox(height: 16),
                    if (loan['status'] == 'overdue' &&
                        loan['penalty_applied'] != true)
                      _buildPenaltyAction(loan),
                  ]);
              }
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildLenderCard(loan)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildLoanCard(loan, fmt)),
                    ]),
                  const SizedBox(height: 16),
                  _buildDisbursementCard(loan, fmt),
                  const SizedBox(height: 16),
                  _buildScheduleCard(loan, fmt),
                  const SizedBox(height: 16),
                  _buildPaymentsCard(loan, fmt),
                  const SizedBox(height: 16),
                  if (loan['status'] == 'overdue' &&
                      loan['penalty_applied'] != true)
                    _buildPenaltyAction(loan),
                ]);
            }),
          const SizedBox(height: 8),
        ]));
  }

  // ───────────────────────── Hero ─────────────────────────
  Widget _buildHero(Map<String, dynamic> loan, NumberFormat fmt) {
    final rawStatus = loan['status'] as String? ?? '';
    final status = (loan['rider_delivery_assigned'] == true &&
            rawStatus == 'approved')
        ? 'rider_delivery_assigned'
        : rawStatus;
    final lender = loan['lender'] as Map<String, dynamic>? ?? {};
    final name =
        '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim();
    final loanNumber = loan['loan_number'] as String? ?? '-';
    final due = loan['due_date'];
    final outstanding =
        (loan['outstanding_balance'] as num?)?.toDouble() ?? 0;
    final totalPayable = (loan['total_payable'] as num?)?.toDouble() ?? 0;
    final principal = (loan['principal_amount'] as num?)?.toDouble() ?? 0;
    final progress = totalPayable > 0
        ? ((totalPayable - outstanding) / totalPayable).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF1A2E45), Color(0xFF223A5E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 6)),
        ]),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.gold, AppColors.goldDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.32),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                  ]),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white, size: 26)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            loanNumber,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.4),
                            overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 10),
                        StatusBadge(status: status),
                        if (loan['penalty_applied'] == true) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(20)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_rounded,
                                    size: 12, color: Colors.white),
                                SizedBox(width: 4),
                                Text('PENALTY APPLIED',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: 0.4)),
                              ])),
                        ],
                      ]),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.16))),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_outline_rounded,
                                  size: 12, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(
                                name.isEmpty ? '—' : name,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70)),
                            ])),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.16))),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.event_outlined,
                                  size: 12, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(
                                'Released ${_formatDate(loan['disbursed_at'] ?? loan['release_date'])}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70)),
                            ])),
                      ]),
                  ])),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                  ]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Outstanding',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textTertiary,
                            letterSpacing: 0.6)),
                    Text('₱${fmt.format(outstanding)}',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: status == 'overdue'
                                ? AppColors.error
                                : AppColors.deepNavy)),
                    Text(
                      due != null ? 'Due ${_formatDate(due)}' : 'No due date',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                  ])),
            ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10))),
            child: Row(
              children: [
                _HeroStatSmall(
                  label: 'Principal',
                  value: '₱${fmt.format(principal)}'),
                Container(
                    width: 1,
                    height: 36,
                    color: Colors.white.withValues(alpha: 0.12)),
                _HeroStatSmall(
                  label: 'Total Payable',
                  value: '₱${fmt.format(totalPayable)}'),
                Container(
                    width: 1,
                    height: 36,
                    color: Colors.white.withValues(alpha: 0.12)),
                _HeroStatSmall(
                  label: 'Collected',
                  value: '${(progress * 100).toStringAsFixed(1)}%',
                  sub: '₱${fmt.format(totalPayable - outstanding)}'),
              ])),
        ]));
  }
  // ───────────────────────── Cards ─────────────────────────
  Widget _buildLenderCard(Map<String, dynamic> loan) {
    final lender = loan['lender'] as Map<String, dynamic>? ?? {};
    final profile = lender['lender_profiles'] as Map<String, dynamic>? ?? {};
    final name =
        '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim();
    final initials = _initials(name.isEmpty ? 'Lender' : name);

    return _PremiumCard(
      title: 'Lender Information',
      subtitle: 'Lender KYC & contact',
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _avatarColor(name),
                      _avatarColor(name).withValues(alpha: 0.72)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: Text(initials,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? '—' : name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    Text(_maskPhone(lender['phone_number'] as String? ?? ''),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ])),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _upgradeBg(
                      profile['account_upgrade_status'] as String?),
                  borderRadius: BorderRadius.circular(20)),
                child: Text(
                  _capitalize(
                      profile['account_upgrade_status'] as String? ?? 'Unknown'),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _upgradeColor(
                          profile['account_upgrade_status'] as String?)))),
            ]),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _KVRow(
              label: 'Phone',
              value: _maskPhone(lender['phone_number'] as String? ?? '')),
          _KVRow(
              label: 'Employment',
              value: _capitalize(profile['employment_type'] as String? ?? '-')),
          _KVRow(
              label: 'GCash',
              value: _maskPhone(profile['gcash_number'] as String? ?? '-')),
          _KVRow(
              label: 'Address',
              value: _formatAddress(profile['address'])),
        ]));
  }

  Widget _buildLoanCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final frequency =
        (loan['payment_frequency'] ?? loan['frequency'] ?? '').toString();

    return _PremiumCard(
      title: 'Loan Details',
      subtitle: 'Terms & repayment structure',
      child: Column(
        children: [
          _KVRow(
              label: 'Principal',
              value: '₱${fmt.format(loan['principal_amount'] ?? 0)}',
              valueStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.deepNavy)),
          _KVRow(
              label: 'Interest (20%)',
              value: '₱${fmt.format(loan['interest_amount'] ?? 0)}'),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.deepNavy.withValues(alpha: 0.06),
                  AppColors.gold.withValues(alpha: 0.10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.22))),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.deepNavy,
                    borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.savings_rounded,
                      size: 16, color: AppColors.gold)),
                const SizedBox(width: 10),
                const Text('Total Payable',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                const Spacer(),
                Text('₱${fmt.format(loan['total_payable'] ?? 0)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.deepNavy)),
              ])),
          _KVRow(
              label: 'Outstanding',
              value: '₱${fmt.format(loan['outstanding_balance'] ?? 0)}',
              valueStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: loan['status'] == 'overdue'
                      ? AppColors.error
                      : AppColors.textPrimary)),
          _KVRow(
              label: 'Frequency',
              value: _capitalize(frequency),
              valueWidget: _FrequencyPill(frequency: frequency)),
          _KVRow(
              label: 'Loan Term',
              value: _loanTermLabel(loan)),
          _KVRow(
              label: 'No. of Payments',
              value: '${loan['term_periods'] ?? '-'}'),
          _KVRow(
              label: 'Installment',
              value: '₱${fmt.format(loan['installment_amount'] ?? 0)}'),
          _KVRow(
              label: 'Due Date',
              value: _formatDate(loan['due_date'])),
        ]));
  }

  Widget _buildDisbursementCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final disburse = (loan['disbursements'] as List?)?.isNotEmpty == true
        ? (loan['disbursements'] as List).first as Map<String, dynamic>
        : <String, dynamic>{};
    if (disburse.isEmpty) return const SizedBox.shrink();
    final method = (disburse['disbursement_method'] as String? ?? '-');
    final status = (disburse['status'] as String? ?? '-');

    return _PremiumCard(
      title: 'Disbursement Info',
      subtitle: 'Funds delivery & settlement',
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _disbursementBg(method),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _disbursementBorder(method))),
            child: Row(
              children: [
                Icon(_disbursementIcon(method),
                    size: 14, color: _disbursementColor(method)),
                const SizedBox(width: 6),
                Text(
                  _capitalize(method.replaceAll('_', ' ')),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _disbursementColor(method))),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20)),
                  child: Text(_capitalize(status),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _disbursementColor(method)))),
              ])),
          const SizedBox(height: 12),
          _KVRow(
              label: 'Amount',
              value: '₱${fmt.format(disburse['amount'] ?? 0)}'),
          _KVRow(
              label: 'Date',
              value: _formatDate(disburse['disbursed_at'])),
          if (disburse['xendit_reference'] != null)
            _KVRow(
                label: 'Xendit Ref',
                value: disburse['xendit_reference'] as String),
        ]));
  }

  Widget _buildScheduleCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final schedules =
        (loan['loan_schedules'] as List? ?? []).cast<Map<String, dynamic>>();
    if (schedules.isEmpty) return const SizedBox.shrink();
    final paid = schedules.where((s) => s['status'] == 'paid').length;

    return _PremiumCard(
      title: 'Payment Schedule',
      subtitle: 'Installment-by-installment breakdown',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: paid == schedules.length
              ? AppColors.success.withValues(alpha: 0.10)
              : AppColors.deepNavy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20)),
        child: Text(
          '$paid / ${schedules.length} paid',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: paid == schedules.length
                  ? AppColors.success
                  : AppColors.deepNavy))),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor:
                WidgetStateProperty.all(const Color(0xFFF8F9FB)),
            headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                color: AppColors.textSecondary,
                letterSpacing: 0.4),
            dataTextStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary),
            columns: const [
              DataColumn(label: Text('#')),
              DataColumn(label: Text('Due Date')),
              DataColumn(label: Text('Amount Due')),
              DataColumn(label: Text('Amount Paid')),
              DataColumn(label: Text('Status')),
            ],
            rows: schedules.map((s) {
              final sStatus = s['status'] as String? ?? '-';
              final c = sStatus == 'paid'
                  ? AppColors.success
                  : sStatus == 'overdue'
                      ? AppColors.error
                      : AppColors.warning;
              return DataRow(cells: [
                DataCell(Text(
                    s['period_number']?.toString() ??
                        s['installment_number']?.toString() ??
                        '-',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text(_formatDate(s['due_date']))),
                DataCell(Text('₱${fmt.format(s['amount_due'] ?? 0)}',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('₱${fmt.format(s['amount_paid'] ?? 0)}')),
                DataCell(
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.withValues(alpha: 0.18))),
                    child: Text(_capitalize(sStatus),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: c)))),
              ]);
            }).toList()))));
  }

  Widget _buildPaymentsCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final payments =
        (loan['payments'] as List? ?? []).cast<Map<String, dynamic>>();
    if (payments.isEmpty) {
      return _PremiumCard(
        title: 'Payment History',
        subtitle: 'All verified collections',
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border)),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: AppColors.textTertiary),
              SizedBox(width: 8),
              Text('No payments recorded yet.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ])));
    }

    return _PremiumCard(
      title: 'Payment History',
      subtitle: '${payments.length} transactions',
      child: Column(
        children: payments.map((p) => _buildPaymentTile(p, fmt)).toList()));
  }

  String _paymentMethodLabel(String m) {
    switch (m) {
      case 'gcash':
      case 'gcash_xendit':
        return 'GCash';
      case 'office_cash':
      case 'cash':
        return 'Office';
      case 'rider_collection':
        return 'Rider Collection';
      default:
        return m.replaceAll('_', ' ');
    }
  }

  Widget _buildPaymentTile(Map<String, dynamic> p, NumberFormat fmt) {
    final method = p['payment_method'] as String? ?? '-';
    final status = p['status'] as String? ?? '-';
    final isVerified = status == 'verified';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
        ]),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isVerified
                  ? AppColors.success.withValues(alpha: 0.12)
                  : AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10)),
            child: Icon(
              method.contains('gcash')
                  ? Icons.phone_iphone_rounded
                  : method.contains('rider')
                      ? Icons.delivery_dining_rounded
                      : Icons.storefront_rounded,
              size: 18,
              color: isVerified ? AppColors.success : AppColors.warning)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('₱${fmt.format(p['amount'] ?? 0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13)),
                Text(
                    '${_paymentMethodLabel(method)} • ${_formatDate(p['created_at'])}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isVerified
                  ? AppColors.success.withValues(alpha: 0.10)
                  : AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isVerified
                      ? AppColors.success.withValues(alpha: 0.18)
                      : AppColors.warning.withValues(alpha: 0.18))),
            child: Text(
              _capitalize(status),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isVerified ? AppColors.success : AppColors.warning))),
        ]));
  }

  Widget _buildPenaltyAction(Map<String, dynamic> loan) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.error.withValues(alpha: 0.10),
            AppColors.error.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 2)),
        ]),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.error,
              borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.warning_rounded,
                color: Colors.white, size: 22)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Loan Overdue — Penalty Available',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.error)),
                const SizedBox(height: 3),
                Text(
                  '20% penalty on total payable = ₱${NumberFormat('#,##0.00').format(((loan['total_payable'] as num?)?.toDouble() ?? 0) * 0.20)}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              ])),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => _applyPenalty(loan['id'] as String),
            icon: const Icon(Icons.gavel_rounded, size: 16),
            label: const Text('Apply Penalty'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)))),
        ]));
  }

  Future<void> _applyPenalty(String loanId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.gavel_rounded,
                  color: AppColors.error, size: 18)),
            const SizedBox(width: 10),
            const Text('Apply Penalty'),
          ]),
        content: const Text(
          'Apply 20% penalty to this loan? This action cannot be undone and will be logged for audit.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Apply Penalty')),
        ]));
    if (confirm == true && mounted) {
      final ok = await ref.read(hmLoanProvider.notifier).applyPenalty(loanId);
      if (!mounted) return;
      context.showSnackBarAsToast(
        SnackBar(
            content: Text(ok ? 'Penalty applied' : 'Failed to apply penalty'),
            backgroundColor: ok ? AppColors.success : AppColors.error));
      if (ok) _load();
    }
  }

  // ───────────────────────── Helpers ─────────────────────────
  String _initials(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return name.trim().substring(0, 1).toUpperCase();
  }

  Color _avatarColor(String seed) {
    const palette = [
      Color(0xFF0D1B2A),
      Color(0xFF1565C0),
      Color(0xFF2E7D32),
      Color(0xFF6A1B9A),
      Color(0xFF00695C),
      Color(0xFFAD1457),
      Color(0xFF4E342E),
      Color(0xFF37474F),
    ];
    return palette[seed.hashCode.abs() % palette.length];
  }

  String _formatDate(dynamic d) {
    if (d == null) return '-';
    try {
      return DateFormat('MMM dd, yyyy').format(DateTime.parse(d.toString()));
    } catch (_) {
      return d.toString();
    }
  }

  String _maskPhone(String p) {
    if (p.length < 8) return p;
    return '${p.substring(0, 4)}****${p.substring(p.length - 3)}';
  }

  String _capitalize(String s) => s.isEmpty
      ? s
      : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

  String _loanTermLabel(Map<String, dynamic> loan) {
    final frequency =
        (loan['payment_frequency'] ?? loan['frequency'] ?? '').toString();
    final unit = frequency.toLowerCase() == 'daily'
        ? 'days'
        : frequency.toLowerCase() == 'weekly'
            ? 'weeks'
            : 'months';
    final periods = (loan['term_periods'] as num?)?.toInt() ?? 0;
    if (periods > 0) return '$periods $unit';
    final schedules = (loan['loan_schedules'] as List?) ?? const [];
    if (schedules.isNotEmpty) return '${schedules.length} $unit';
    final days = loan['term_days'];
    return days != null ? '$days days' : '-';
  }

  Color _upgradeBg(String? s) {
    switch (s) {
      case 'approved':
        return AppColors.success.withValues(alpha: 0.10);
      case 'pending':
        return AppColors.warning.withValues(alpha: 0.12);
      case 'rejected':
        return AppColors.error.withValues(alpha: 0.10);
      default:
        return AppColors.surfaceVariant;
    }
  }

  Color _upgradeColor(String? s) {
    switch (s) {
      case 'approved':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Color _disbursementBg(String m) {
    switch (m) {
      case 'gcash':
      case 'gcash_xendit':
        return AppColors.info.withValues(alpha: 0.08);
      case 'rider_delivery':
        return AppColors.gold.withValues(alpha: 0.12);
      default:
        return AppColors.surfaceVariant;
    }
  }

  Color _disbursementBorder(String m) {
    switch (m) {
      case 'gcash':
      case 'gcash_xendit':
        return AppColors.info.withValues(alpha: 0.18);
      case 'rider_delivery':
        return AppColors.gold.withValues(alpha: 0.24);
      default:
        return AppColors.border;
    }
  }

  Color _disbursementColor(String m) {
    switch (m) {
      case 'gcash':
      case 'gcash_xendit':
        return AppColors.info;
      case 'rider_delivery':
        return AppColors.goldDark;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _disbursementIcon(String m) {
    switch (m) {
      case 'gcash':
      case 'gcash_xendit':
        return Icons.phone_iphone_rounded;
      case 'rider_delivery':
        return Icons.delivery_dining_rounded;
      default:
        return Icons.payments_outlined;
    }
  }

  String _formatAddress(dynamic a) {
    if (a == null) return '-';
    if (a is String) return a.isEmpty ? '-' : a;
    if (a is Map) {
      final parts = [
        a['street'],
        a['barangay'],
        a['city'],
        a['province'],
      ]
          .where((e) => e != null && e.toString().isNotEmpty)
          .map((e) => e.toString())
          .toList();
      return parts.isEmpty ? '-' : parts.join(', ');
    }
    return a.toString();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable premium card + helpers
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  const _PremiumCard(
      {required this.title,
      required this.subtitle,
      required this.child,
      this.trailing});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textTertiary)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _KVRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;
  final Widget? valueWidget;
  const _KVRow(
      {required this.label,
      required this.value,
      this.valueStyle,
      this.valueWidget});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 122,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deepNavy))),
          Expanded(
            child: valueWidget ??
                Text(
                  value,
                  style: valueStyle ??
                      const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary))),
        ]));
  }
}

class _FrequencyPill extends StatelessWidget {
  final String frequency;
  const _FrequencyPill({required this.frequency});
  @override
  Widget build(BuildContext context) {
    final f = frequency.toLowerCase();
    final Color c;
    switch (f) {
      case 'daily':
        c = AppColors.riderGreen;
        break;
      case 'weekly':
        c = AppColors.lenderBlue;
        break;
      default:
        c = AppColors.deepNavy;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.22))),
      child: Text(
        f.isEmpty ? '-' : '${f[0].toUpperCase()}${f.substring(1)}',
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800, color: c, letterSpacing: 0.2)));
  }
}

class _HeroStatSmall extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  const _HeroStatSmall({required this.label, required this.value, this.sub});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.62),
                        letterSpacing: 0.4)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                    overflow: TextOverflow.ellipsis),
                if (sub != null)
                  Text(sub!,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.62)),
                      overflow: TextOverflow.ellipsis),
              ])),
        ]));
  }
}

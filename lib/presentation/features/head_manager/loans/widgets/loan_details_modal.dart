// lib/presentation/features/head_manager/loans/widgets/loan_details_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/hm_loan_provider.dart';

Future<void> showLoanDetailsModal(BuildContext context, String loanId) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => LoanDetailsModal(loanId: loanId));
}

class LoanDetailsModal extends ConsumerStatefulWidget {
  final String loanId;
  const LoanDetailsModal({super.key, required this.loanId});

  @override
  ConsumerState<LoanDetailsModal> createState() => _LoanDetailsModalState();
}

class _LoanDetailsModalState extends ConsumerState<LoanDetailsModal> {
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
    final size = MediaQuery.of(context).size;
    final maxW = size.width > 960 ? 900.0 : size.width * 0.92;
    final maxH = size.height * 0.88;

    return Dialog(
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF0F2F5),
            borderRadius: BorderRadius.zero,
            boxShadow: [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 24,
                  offset: Offset(0, 8)),
            ]),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _loan == null
                        ? _buildNotFound()
                        : _buildContent()),
            ]))));
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.deepNavy,
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: AppColors.gold, size: 18)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Loan Details',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                Text('Repayment • Disbursement • Schedule • Payments',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textTertiary)),
              ])),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded,
                size: 18, color: AppColors.textSecondary),
            tooltip: 'Refresh',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surfaceVariant,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)))),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSecondary),
            tooltip: 'Close',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surfaceVariant,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)))),
        ]));
  }

  Widget _buildNotFound() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                shape: BoxShape.circle),
              child: const Icon(Icons.search_off_rounded,
                  size: 26, color: AppColors.error)),
            const SizedBox(height: 14),
            const Text('Loan not found',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9))),
              child: const Text('Close')),
          ])));
  }

  Widget _buildContent() {
    final loan = _loan!;
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHero(loan, fmt),
          LayoutBuilder(
            builder: (context, c) {
              final isNarrow = c.maxWidth < 760;
              if (isNarrow) {
                return Column(
                  children: [
                    _buildLenderCard(loan),
                    const SizedBox(height: 14),
                    _buildLoanCard(loan, fmt),
                    const SizedBox(height: 14),
                    _buildDisbursementCard(loan, fmt),
                    const SizedBox(height: 14),
                    _buildScheduleCard(loan, fmt),
                    const SizedBox(height: 14),
                    _buildPaymentsCard(loan, fmt),
                    const SizedBox(height: 14),
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
                      const SizedBox(width: 14),
                      Expanded(child: _buildLoanCard(loan, fmt)),
                    ]),
                  const SizedBox(height: 14),
                  _buildDisbursementCard(loan, fmt),
                  const SizedBox(height: 14),
                  _buildScheduleCard(loan, fmt),
                  const SizedBox(height: 14),
                  _buildPaymentsCard(loan, fmt),
                  const SizedBox(height: 14),
                  if (loan['status'] == 'overdue' &&
                      loan['penalty_applied'] != true)
                    _buildPenaltyAction(loan),
                ]);
            }),
        ]));
  }  Widget _buildHero(Map<String, dynamic> loan, NumberFormat fmt) {
    final rawStatus = loan['status'] as String? ?? '';
    final status = (loan['rider_delivery_assigned'] == true &&
            rawStatus == 'approved')
        ? 'rider_delivery_assigned'
        : rawStatus;
    final lender = loan['lender'] as Map<String, dynamic>? ?? {};
    final name =
        '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim();
    final loanNumber = loan['loan_number'] as String? ?? '-';
    final outstanding =
        (loan['outstanding_balance'] as num?)?.toDouble() ?? 0;
    final totalPayable = (loan['total_payable'] as num?)?.toDouble() ?? 0;
    final principal = (loan['principal_amount'] as num?)?.toDouble() ?? 0;

    return _PremiumCard(
      title: loanNumber,
      subtitle: name.isEmpty
          ? 'Released ${_formatDate(loan['disbursed_at'] ?? loan['release_date'])}'
          : '$name • Released ${_formatDate(loan['disbursed_at'] ?? loan['release_date'])}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBadge(status: status),
          if (loan['penalty_applied'] == true) ...[ const SizedBox(width: 6), Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(20)),
              child: const Text('PENALTY',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white))),
          ],
        ],
      ),
      child: Row(
        children: [
          Expanded(
              child: _SimpleStat(
                  label: 'Principal',
                  value: '₱${fmt.format(principal)}')),
          Container(width: 1, height: 32, color: AppColors.divider),
          Expanded(
              child: _SimpleStat(
                  label: 'Total Payable',
                  value: '₱${fmt.format(totalPayable)}')),
          Container(width: 1, height: 32, color: AppColors.divider),
          Expanded(
              child: _SimpleStat(
                  label: 'Outstanding',
                  value: '₱${fmt.format(outstanding)}')),
        ],
      ),
    );
  }
  // Cards — reused simplified versions (same as application modal but with active fields)
  Widget _buildLenderCard(Map<String, dynamic> loan) {
    final lender = loan['lender'] as Map<String, dynamic>? ?? {};
    final profile = (loan['lender_profile'] as Map<String, dynamic>?) ??
        (lender['lender_profiles'] as Map<String, dynamic>? ?? {});
    final name =
        '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim();
    final initials = _initials(name.isEmpty ? 'Lender' : name);
    return _PremiumCard(
      title: 'Lender Information',
      subtitle: 'Lender KYC',
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _avatarColor(name),
                      _avatarColor(name).withValues(alpha: 0.72)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(11)),
                alignment: Alignment.center,
                child: Text(initials,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? '—' : name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    Text(lender['phone_number'] as String? ?? '',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ])),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _upgradeBg(profile['account_upgrade_status'] as String?),
                  borderRadius: BorderRadius.circular(20)),
                child: Text(
                  _capitalize(
                      profile['account_upgrade_status'] as String? ?? 'Unknown'),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _upgradeColor(
                          profile['account_upgrade_status'] as String?)))),
            ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _KVRow(
              label: 'Phone',
              value: lender['phone_number'] as String? ?? '-'),
          _KVRow(
              label: 'Employment',
              value: _capitalize(profile['employment_type'] as String? ?? '-')),
          _KVRow(
              label: 'Address',
              value: _formatAddress(profile['address'] ?? loan['lender_address'])),
        ]));
  }

  Widget _buildLoanCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final frequency =
        (loan['payment_frequency'] ?? loan['frequency'] ?? '').toString();
    return _PremiumCard(
      title: 'Loan Details',
      subtitle: 'Terms & repayment',
      child: Column(
        children: [
          _KVRow(
              label: 'Principal',
              value: '₱${fmt.format(loan['principal_amount'] ?? 0)}',
              valueStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.deepNavy)),
          _KVRow(
              label: 'Interest (20%)',
              value: '₱${fmt.format(loan['interest_amount'] ?? 0)}'),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.deepNavy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border)),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.deepNavy,
                    borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.savings_rounded,
                      size: 14, color: AppColors.gold)),
                const SizedBox(width: 8),
                const Text('Total Payable',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                const Spacer(),
                Text('₱${fmt.format(loan['total_payable'] ?? 0)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.deepNavy)),
              ])),
          _KVRow(
              label: 'Outstanding',
              value: '₱${fmt.format(loan['outstanding_balance'] ?? 0)}',
              valueStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: loan['status'] == 'overdue'
                      ? AppColors.error
                      : AppColors.textPrimary)),
          _KVRow(
              label: 'Frequency',
              value: _capitalize(frequency)),
          _KVRow(
              label: 'Loan Term',
              value: _loanTermLabel(loan)),
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
      subtitle: 'Funds delivery',
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _disbursementBg(method),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _disbursementBorder(method))),
            child: Row(
              children: [
                Icon(_disbursementIcon(method),
                    size: 13, color: _disbursementColor(method)),
                const SizedBox(width: 6),
                Text(_capitalize(method.replaceAll('_', ' ')),
                    style: TextStyle(
                        fontSize: 11,
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
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _disbursementColor(method)))),
              ])),
          const SizedBox(height: 10),
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
      subtitle: 'Breakdown',
      trailing: Text('$paid / ${schedules.length} paid',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: paid == schedules.length
                  ? const Color(0xFFA5D6A7)
                  : Colors.white70)),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8F9FB)),
            headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 10,
                color: AppColors.textSecondary),
            dataTextStyle: const TextStyle(
                fontSize: 11, color: AppColors.textPrimary),
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
                DataCell(Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.withValues(alpha: 0.18))),
                  child: Text(_capitalize(sStatus),
                      style: TextStyle(
                          fontSize: 10,
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
        subtitle: 'Collections',
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border)),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 16, color: AppColors.textTertiary),
              SizedBox(width: 8),
              Text('No payments recorded yet.',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ])));
    }
    return _PremiumCard(
      title: 'Payment History',
      subtitle: '${payments.length} transactions',
      child: Column(
        children: payments.map((p) => _buildPaymentTile(p, fmt)).toList()));
  }

  Widget _buildPaymentTile(Map<String, dynamic> p, NumberFormat fmt) {
    final method = p['payment_method'] as String? ?? '-';
    final status = p['status'] as String? ?? '-';
    final isVerified = status == 'verified';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isVerified
                  ? AppColors.success.withValues(alpha: 0.12)
                  : AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9)),
            child: Icon(
              method.contains('gcash')
                  ? Icons.phone_iphone_rounded
                  : method.contains('rider')
                      ? Icons.delivery_dining_rounded
                      : Icons.storefront_rounded,
              size: 16,
              color: isVerified ? AppColors.success : AppColors.warning)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('₱${fmt.format(p['amount'] ?? 0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12)),
                Text(
                    '${_paymentMethodLabel(method)} • ${_formatDate(p['created_at'])}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10)),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: isVerified
                  ? AppColors.success.withValues(alpha: 0.10)
                  : AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isVerified
                      ? AppColors.success.withValues(alpha: 0.18)
                      : AppColors.warning.withValues(alpha: 0.18))),
            child: Text(_capitalize(status),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isVerified ? AppColors.success : AppColors.warning))),
        ]));
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

  Widget _buildPenaltyAction(Map<String, dynamic> loan) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.18))),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.warning_rounded,
                color: Colors.white, size: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Loan Overdue — Penalty Available',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.error)),
                Text(
                  '20% penalty = ₱${NumberFormat('#,##0.00').format(((loan['total_payable'] as num?)?.toDouble() ?? 0) * 0.20)}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
              ])),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _applyPenalty(loan['id'] as String),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            child: const Text('Apply',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
        ]));
  }

  Future<void> _applyPenalty(String loanId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Apply Penalty'),
        content: const Text(
            'Apply 20% penalty? This cannot be undone.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Apply')),
        ]));
    if (confirm == true && mounted) {
      final ok = await ref.read(hmLoanProvider.notifier).applyPenalty(loanId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ok ? 'Penalty applied' : 'Failed to apply penalty'),
            backgroundColor: ok ? AppColors.success : AppColors.error));
      if (ok) _load();
    }
  }

  // helpers
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

  String _capitalize(String s) => s.isEmpty
      ? s
      : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

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
}

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
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF5C6370),
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      if (subtitle.isNotEmpty)
                        Text(subtitle,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

class _KVRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;
  const _KVRow(
      {required this.label, required this.value, this.valueStyle});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary))),
          Expanded(
            child: Text(
              value,
              style: valueStyle ??
                  const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleStat extends StatelessWidget {
  final String label;
  final String value;
  const _SimpleStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary)),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
            textAlign: TextAlign.center),
      ]);
  }
}

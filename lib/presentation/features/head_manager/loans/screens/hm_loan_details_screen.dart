// lib/presentation/features/head_manager/loans/screens/hm_loan_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../providers/hm_loan_provider.dart';

class HmLoanDetailsScreen extends ConsumerStatefulWidget {
  final String loanId;
  const HmLoanDetailsScreen({super.key, required this.loanId});

  @override
  ConsumerState<HmLoanDetailsScreen> createState() => _HmLoanDetailsScreenState();
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
    final data = await ref.read(hmLoanProvider.notifier).getLoanDetails(widget.loanId);
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
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back'),
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 12),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loan == null
              ? const Center(child: Text('Loan not found'))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final loan = _loan!;
    final fmt = NumberFormat('#,##0.00', 'en_PH');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(loan, fmt),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildLenderCard(loan)),
              const SizedBox(width: 20),
              Expanded(child: _buildLoanCard(loan, fmt)),
            ],
          ),
          const SizedBox(height: 20),
          _buildDisbursementCard(loan, fmt),
          const SizedBox(height: 20),
          _buildScheduleCard(loan, fmt),
          const SizedBox(height: 20),
          _buildPaymentsCard(loan, fmt),
          const SizedBox(height: 20),
          if (loan['status'] == 'overdue' && loan['penalty_applied'] != true)
            _buildPenaltyAction(loan),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final status = loan['status'] as String? ?? '';
    final statusColor = _statusColor(status);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.deepNavy,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.account_balance_wallet, color: AppColors.gold, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loan['loan_number'] as String? ?? '-', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Released: ${_formatDate(loan['disbursed_at'] ?? loan['release_date'])}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(
                status.replaceAll('_', ' ').toUpperCase(),
                style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold),
              ),
            ),
            if (loan['penalty_applied'] == true) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: const Text('PENALTY APPLIED', style: TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLenderCard(Map<String, dynamic> loan) {
    final lender = loan['lender'] as Map<String, dynamic>? ?? {};
    final profile = lender['lender_profiles'] as Map<String, dynamic>? ?? {};
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Lender Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            _row('Name', '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim()),
            _row('Phone', _maskPhone(lender['phone_number'] as String? ?? '')),
            _row('KYC Status', _capitalize(profile['kyc_status'] as String? ?? 'Unknown')),
            _row('Employment', _capitalize(profile['employment_type'] as String? ?? '-')),
            _row('GCash', _maskPhone(profile['gcash_number'] as String? ?? '-')),
          ],
        ),
      ),
    );
  }

  Widget _buildLoanCard(Map<String, dynamic> loan, NumberFormat fmt) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Loan Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            _row('Principal', '₱${fmt.format(loan['principal_amount'] ?? 0)}'),
            _row('Interest (20%)', '₱${fmt.format(loan['interest_amount'] ?? 0)}'),
            _row('Total Payable', '₱${fmt.format(loan['total_payable'] ?? 0)}', bold: true),
            _row('Outstanding', '₱${fmt.format(loan['outstanding_balance'] ?? 0)}', bold: true),
            _row('Frequency', _capitalize(loan['payment_frequency'] as String? ?? '-')),
            _row('Term', '${loan['term_days'] ?? '-'} days'),
            _row('Installment', '₱${fmt.format(loan['installment_amount'] ?? 0)}'),
            _row('Due Date', _formatDate(loan['due_date'])),
          ],
        ),
      ),
    );
  }

  Widget _buildDisbursementCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final disburse = (loan['disbursements'] as List?)?.isNotEmpty == true
        ? (loan['disbursements'] as List).first as Map<String, dynamic>
        : <String, dynamic>{};
    if (disburse.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Disbursement Info', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            _row('Method', _capitalize(disburse['disbursement_method'] as String? ?? '-')),
            _row('Amount', '₱${fmt.format(disburse['amount'] ?? 0)}'),
            _row('Date', _formatDate(disburse['disbursed_at'])),
            _row('Status', _capitalize(disburse['status'] as String? ?? '-')),
            if (disburse['xendit_reference'] != null)
              _row('Xendit Ref', disburse['xendit_reference'] as String),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final schedules = (loan['loan_schedules'] as List? ?? []).cast<Map<String, dynamic>>();
    if (schedules.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Payment Schedule', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${schedules.where((s) => s['status'] == 'paid').length} / ${schedules.length} paid',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
                4: FlexColumnWidth(1.5),
              },
              border: TableBorder.all(color: AppColors.border, borderRadius: BorderRadius.circular(8)),
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: AppColors.surfaceVariant),
                  children: ['#', 'Due Date', 'Amount Due', 'Amount Paid', 'Status']
                      .map((h) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Text(h, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          ))
                      .toList(),
                ),
                ...schedules.map((s) {
                  final sStatus = s['status'] as String? ?? '-';
                  final sColor = sStatus == 'paid' ? AppColors.success : sStatus == 'overdue' ? AppColors.error : AppColors.warning;
                  return TableRow(
                    children: [
                      _tableCell(s['period_number']?.toString() ?? '-'),
                      _tableCell(_formatDate(s['due_date'])),
                      _tableCell('₱${fmt.format(s['amount_due'] ?? 0)}'),
                      _tableCell('₱${fmt.format(s['amount_paid'] ?? 0)}'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(color: sColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                          child: Text(_capitalize(sStatus), style: TextStyle(fontSize: 11, color: sColor, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentsCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final payments = (loan['payments'] as List? ?? []).cast<Map<String, dynamic>>();
    if (payments.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Payment History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...payments.map((p) => _buildPaymentTile(p, fmt)),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentTile(Map<String, dynamic> p, NumberFormat fmt) {
    final method = p['payment_method'] as String? ?? '-';
    final status = p['status'] as String? ?? '-';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.infoLight, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.payments_outlined, size: 18, color: AppColors.info),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('₱${fmt.format(p['amount'] ?? 0)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text('${_capitalize(method)} • ${_formatDate(p['created_at'])}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: status == 'verified' ? AppColors.successLight : AppColors.warningLight,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _capitalize(status),
              style: TextStyle(fontSize: 11, color: status == 'verified' ? AppColors.success : AppColors.warning, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPenaltyAction(Map<String, dynamic> loan) {
    return Card(
      elevation: 0,
      color: AppColors.errorLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.error),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.warning_outlined, color: AppColors.error, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Loan Overdue - Penalty Available', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.error)),
                  Text('20% penalty on total payable = ₱${NumberFormat('#,##0.00').format(((loan['total_payable'] as num?)?.toDouble() ?? 0) * 0.20)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => _applyPenalty(loan['id'] as String),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
              child: const Text('Apply Penalty'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyPenalty(String loanId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apply Penalty'),
        content: const Text('Apply 20% penalty to this loan? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final ok = await ref.read(hmLoanProvider.notifier).applyPenalty(loanId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Penalty applied' : 'Failed to apply penalty'), backgroundColor: ok ? AppColors.success : AppColors.error),
      );
      if (ok) _load();
    }
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
            Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
          ],
        ),
      );

  Widget _tableCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      );

  Color _statusColor(String status) {
    switch (status) {
      case 'active': return AppColors.statusActive;
      case 'completed': return AppColors.statusCompleted;
      case 'overdue': return AppColors.statusOverdue;
      case 'rejected': return AppColors.statusRejected;
      default: return AppColors.info;
    }
  }

  String _formatDate(dynamic d) {
    if (d == null) return '-';
    try { return DateFormat('MMM dd, yyyy').format(DateTime.parse(d.toString())); } catch (_) { return d.toString(); }
  }

  String _maskPhone(String p) {
    if (p.length < 8) return p;
    return '${p.substring(0, 4)}****${p.substring(p.length - 3)}';
  }

  String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';
}
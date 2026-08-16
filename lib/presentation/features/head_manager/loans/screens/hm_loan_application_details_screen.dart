// lib/presentation/features/head_manager/loans/screens/hm_loan_application_details_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../providers/hm_loan_provider.dart';
import '../../disbursements/widgets/rider_disburse_assign_modal.dart';

class HmLoanApplicationDetailsScreen extends ConsumerStatefulWidget {
  final String loanId;
  const HmLoanApplicationDetailsScreen({super.key, required this.loanId});

  @override
  ConsumerState<HmLoanApplicationDetailsScreen> createState() =>
      _HmLoanApplicationDetailsScreenState();
}

class _HmLoanApplicationDetailsScreenState
    extends ConsumerState<HmLoanApplicationDetailsScreen> {
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
    setState(() {
      _loan = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WebScaffold(
      title: 'Loan Application Details',
      actions: [
        TextButton.icon(
          onPressed: () => context.go(RouteConstants.hmLoanApplications),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back'),
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
    final status = loan['status'] as String? ?? '';
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
          _buildCoMakerCard(loan),
          const SizedBox(height: 20),
          _buildSchedulePreview(loan, fmt),
          const SizedBox(height: 20),
          if (status == 'approved' &&
              loan['disbursement_method'] == 'rider_delivery')
            _buildDisbursementAction(loan),
        ],
      ),
    );
  }

  Widget _buildDisbursementAction(Map<String, dynamic> loan) {
    return Card(
      elevation: 0,
      color: AppColors.infoLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.info),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cash via Rider — Disbursement',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'The lender chose to receive the loan via a delivery rider. Assign an available rider to hand the cash to the lender.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () =>
                  _showAssignDisbursementRider(loan['id'] as String),
              icon: const Icon(Icons.delivery_dining, size: 18),
              label: const Text('Assign Delivery Rider'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAssignDisbursementRider(String loanId) async {
    final assigned = await showDialog<bool>(
      context: context,
      builder: (_) => RiderDisburseAssignModal(
        loanId: loanId,
        loanAmount: (_loan?['principal_amount'] as num?)?.toDouble() ?? 0,
        lenderName:
            '${_loan?['lender']?['first_name'] ?? ''} ${_loan?['lender']?['last_name'] ?? ''}'
                .trim(),
        lenderAddress: (_loan?['lender_profile']?['address'] != null)
            ? _loan?['lender_profile']?['address'].toString()
            : null,
      ),
    );
    if (assigned == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery rider assigned'),
          backgroundColor: AppColors.success,
        ),
      );
      await _load();
    }
  }

  Widget _buildHeaderCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final rawStatus = loan['status'] as String? ?? '';
    final status = (loan['rider_delivery_assigned'] == true &&
            rawStatus == 'approved')
        ? 'rider_delivery_assigned'
        : rawStatus;
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
              child: const Icon(Icons.description_outlined,
                  color: AppColors.gold, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loan['loan_number'] as String? ?? 'Pending Number',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Applied ${_formatDate(loan['created_at'])}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
            _buildStatusChip(status),
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
            const Text('Lender Information',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            _row(
                'Name',
                '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'
                    .trim()),
            _row('Phone', _maskPhone(lender['phone_number'] as String? ?? '')),
            _row(
                'Account Upgrade Status',
                _capitalize(
                    profile['account_upgrade_status'] as String? ?? 'Unknown')),
            _row('Employment',
                _capitalize(profile['employment_type'] as String? ?? '-')),
            _row(
                'Monthly Income',
                profile['monthly_income'] != null
                    ? '₱${NumberFormat('#,##0.00').format(profile['monthly_income'])}'
                    : '-'),
          ],
        ),
      ),
    );
  }

  Widget _buildCoMakerCard(Map<String, dynamic> loan) {
    final coMakers =
        (loan['co_makers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (coMakers.isEmpty) return const SizedBox.shrink();
    final cm = coMakers.first;
    final signature = cm['signature'] as String?;
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
            const Text('Co-Maker',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            _row('Name',
                '${cm['first_name'] ?? ''} ${cm['last_name'] ?? ''}'.trim()),
            _row('Relationship', cm['relationship'] as String? ?? '-'),
            _row('Phone', _maskPhone(cm['phone_number'] as String? ?? '')),
            _row('Birthday', cm['date_of_birth'] as String? ?? '-'),
            _row('Address', cm['address'] as String? ?? '-'),
            if (signature != null && signature.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Co-Maker Signature',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Container(
                width: 280,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildSignatureImage(signature),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSignatureImage(String signature) {
    const placeholder = Center(
      child: Icon(Icons.draw_outlined,
          size: 40, color: AppColors.textTertiary),
    );
    if (signature.startsWith('data:') || signature.startsWith('http')) {
      return Image.network(
        signature,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    try {
      final bytes = base64Decode(signature);
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => placeholder,
      );
    } catch (_) {
      return placeholder;
    }
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
            const Text('Loan Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            _row('Principal', '₱${fmt.format(loan['principal_amount'] ?? 0)}'),
            _row('Interest (20%)',
                '₱${fmt.format(loan['interest_amount'] ?? 0)}'),
            _row('Total Payable', '₱${fmt.format(loan['total_payable'] ?? 0)}',
                bold: true),
            _row('Frequency',
                _capitalize((loan['payment_frequency'] ?? loan['frequency'])
                        ?.toString() ??
                    '-')),
            _row('Loan Term', _loanTermLabel(loan)),
            _row('Number of Payments', '${loan['term_periods'] ?? '-'}'),
            _row('Installment',
                '₱${fmt.format(loan['installment_amount'] ?? 0)}'),
            _row('Purpose', loan['loan_purpose'] as String? ?? '-'),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedulePreview(Map<String, dynamic> loan, NumberFormat fmt) {
    final schedules = (loan['loan_schedules'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .take(5)
        .toList();
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
            const Text('Payment Schedule (First 5 periods)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(1),
              },
              border: TableBorder.all(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(8)),
              children: [
                TableRow(
                  decoration:
                      const BoxDecoration(color: AppColors.surfaceVariant),
                  children: ['#', 'Due Date', 'Amount Due', 'Status']
                      .map((h) => Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Text(h,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 12)),
                          ))
                      .toList(),
                ),
                ...schedules.map((s) => TableRow(
                      children: [
                        _tableCell(s['period_number']?.toString() ?? '-'),
                        _tableCell(_formatDate(s['due_date'])),
                        _tableCell('₱${fmt.format(s['amount_due'] ?? 0)}'),
                        _tableCell(_capitalize(s['status'] as String? ?? '-')),
                      ],
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      );

  Widget _buildStatusChip(String status) {
    Color c;
    switch (status) {
      case 'pending':
        c = AppColors.statusPending;
        break;
      case 'approved':
        c = AppColors.statusActive;
        break;
      case 'rejected':
        c = AppColors.statusRejected;
        break;
      case 'ci_completed':
        c = AppColors.lenderBlue;
        break;
      case 'rider_delivery_assigned':
        c = AppColors.lenderBlue;
        break;
      default:
        c = AppColors.info;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.bold),
      ),
    );
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
}

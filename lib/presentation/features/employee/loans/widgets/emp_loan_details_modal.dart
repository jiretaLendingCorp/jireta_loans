// lib/presentation/features/employee/loans/widgets/emp_loan_details_modal.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../head_manager/disbursements/widgets/rider_disburse_assign_modal.dart';
import '../providers/emp_loan_provider.dart';
import 'package:jireta_loans/core/extensions/context_extensions.dart';

final _empModalLoanDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return await sl<LoanRemoteDataSource>().getDetails(loanId: id);
});

Future<void> showEmpLoanDetailsModal(BuildContext context, String loanId) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => EmpLoanDetailsModal(loanId: loanId));
}

class EmpLoanDetailsModal extends ConsumerStatefulWidget {
  final String loanId;
  const EmpLoanDetailsModal({super.key, required this.loanId});

  @override
  ConsumerState<EmpLoanDetailsModal> createState() =>
      _EmpLoanDetailsModalState();
}

class _EmpLoanDetailsModalState extends ConsumerState<EmpLoanDetailsModal> {
  final _reasonCtrl = TextEditingController();
  bool _isActing = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxW = size.width > 960 ? 900.0 : size.width * 0.92;
    final maxH = size.height * 0.88;
    final loanAsync = ref.watch(_empModalLoanDetailProvider(widget.loanId));

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
                child: loanAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _buildError('Failed to load loan: $e'),
                  data: (loan) => _buildContent(loan),
                ),
              ),
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
            child: const Icon(Icons.description_outlined,
                color: AppColors.gold, size: 18)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Loan Application Details',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
          ),
          IconButton(
            onPressed: () =>
                ref.invalidate(_empModalLoanDetailProvider(widget.loanId)),
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

  Widget _buildError(String msg) {
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
              child: const Icon(Icons.error_outline,
                  size: 26, color: AppColors.error)),
            const SizedBox(height: 14),
            Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
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

  Widget _buildContent(Map<String, dynamic> loan) {
    final rawStatus = loan['status'] as String? ?? '';
    final status = (loan['rider_delivery_assigned'] == true &&
            rawStatus == 'approved')
        ? 'rider_delivery_assigned'
        : rawStatus;
    final canAssignDeliveryRider =
        rawStatus == 'approved' && loan['disbursement_method'] == 'rider_delivery';
    final fmt = NumberFormat('#,##0.00', 'en_PH');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHero(loan, status, fmt),
          if (canAssignDeliveryRider) ...[
            const SizedBox(height: 14),
            _buildDisbursementAction(loan),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final isNarrow = c.maxWidth < 760;
              if (isNarrow) {
                return Column(
                  children: [
                    _buildLenderCard(loan),
                    const SizedBox(height: 14),
                    _buildCoMakerCard(loan),
                    const SizedBox(height: 14),
                    _buildLoanCard(loan, fmt),
                    const SizedBox(height: 14),
                    _buildSchedulePreview(loan, fmt),
                  ]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLenderCard(loan),
                        const SizedBox(height: 14),
                        _buildCoMakerCard(loan),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLoanCard(loan, fmt),
                        const SizedBox(height: 14),
                        _buildSchedulePreview(loan, fmt),
                      ],
                    ),
                  ),
                ],
              );
            }),
          const SizedBox(height: 14),
          if (rawStatus == 'overdue' && loan['penalty_applied'] != true)
            _buildPenaltyAction(loan),
        ]));
  }

  Widget _buildHero(
      Map<String, dynamic> loan, String status, NumberFormat fmt) {
    final lender = loan['lender'] as Map<String, dynamic>? ?? {};
    final name =
        '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim();
    final loanNumber = loan['loan_number'] as String? ?? 'Pending Number';
    final principal = (loan['principal_amount'] as num?)?.toDouble() ?? 0;
    final totalPayable = (loan['total_payable'] as num?)?.toDouble() ?? 0;

    return _PremiumCard(
      title: loanNumber,
      subtitle: name.isEmpty
          ? 'Applied ${_formatDate(loan['created_at'])}'
          : '$name • Applied ${_formatDate(loan['created_at'])}',
      trailing: _buildHeroActions(loan, status),
      child: Row(
        children: [
          Expanded(
              child: _SimpleStat(
                  label: 'Principal', value: '₱${fmt.format(principal)}')),
          Container(width: 1, height: 32, color: AppColors.divider),
          Expanded(
              child: _SimpleStat(
                  label: 'Total Payable',
                  value: '₱${fmt.format(totalPayable)}')),
          Container(width: 1, height: 32, color: AppColors.divider),
          Expanded(
              child: _SimpleStat(
                  label: 'Term', value: _loanTermLabel(loan))),
        ],
      ),
    );
  }

  // Status text + 3-dot action menu (gaya ng Head Manager).
  Widget _buildHeroActions(Map<String, dynamic> loan, String status) {
    final canApprove = const {
      'pending',
      'under_review',
      'ci_required',
      'ci_assigned',
      'ci_completed'
    }.contains(status);
    final canReject = canApprove;
    final canRequestCI = status == 'under_review';
    final hasActions = canApprove || canReject || canRequestCI;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusText(status: status),
        if (hasActions) ...[
          const SizedBox(width: 2),
          PopupMenuButton<String>(
            tooltip: 'Actions',
            offset: const Offset(0, 34),
            shape:
                const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            color: const Color(0xFFF0F2F5),
            onSelected: (v) {
              switch (v) {
                case 'approve':
                  _confirmApprove(loan);
                  break;
                case 'reject':
                  _showRejectDialog(loan);
                  break;
                case 'request_ci':
                  _confirmRequestCi(loan);
                  break;
              }
            },
            itemBuilder: (_) => [
              if (canApprove)
                const PopupMenuItem(
                    value: 'approve',
                    child: Row(children: [
                      Icon(Icons.check_circle_outline,
                          size: 16, color: AppColors.success),
                      SizedBox(width: 8),
                      Text('Approve')
                    ])),
              if (canRequestCI)
                const PopupMenuItem(
                    value: 'request_ci',
                    child: Row(children: [
                      Icon(Icons.search_rounded,
                          size: 16, color: AppColors.info),
                      SizedBox(width: 8),
                      Text('Request CI')
                    ])),
              if (canReject)
                const PopupMenuItem(
                    value: 'reject',
                    child: Row(children: [
                      Icon(Icons.cancel_outlined,
                          size: 16, color: AppColors.error),
                      SizedBox(width: 8),
                      Text('Reject')
                    ])),
            ],
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.zero,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.40)),
                  ),
                  child: const Icon(Icons.more_vert_rounded,
                      size: 18, color: Colors.white),
                ),
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.warning,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF5C6370)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDisbursementAction(Map<String, dynamic> loan) {
    return _PremiumCard(
      title: 'Cash via Rider — Disbursement',
      subtitle: 'Assign an available rider to hand the cash to the lender',
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'The lender chose to receive the loan via a delivery rider.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => _showAssignDeliveryRider(loan),
            icon: const Icon(Icons.delivery_dining, size: 18),
            label: const Text('Assign Delivery Rider'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black87,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAssignDeliveryRider(Map<String, dynamic> loan) async {
    final assigned = await showDialog<bool>(
      context: context,
      builder: (_) => RiderDisburseAssignModal(
        loanId: loan['id'] as String,
        loanAmount: (loan['principal_amount'] as num?)?.toDouble() ?? 0,
        lenderName:
            '${loan['lender']?['first_name'] ?? ''} ${loan['lender']?['last_name'] ?? ''}'
                .trim(),
      ),
    );
    if (assigned == true && mounted) {
      context.showSnackBarAsToast(const SnackBar(
          content: Text('Delivery rider assigned'),
          backgroundColor: AppColors.success));
      ref.invalidate(_empModalLoanDetailProvider(widget.loanId));
    }
  }

  // ───────────────────────── Cards ─────────────────────────
  Widget _buildLenderCard(Map<String, dynamic> loan) {
    final lender = loan['lender'] as Map<String, dynamic>? ?? {};
    final profile = (loan['lender_profile'] as Map<String, dynamic>?) ??
        (lender['lender_profiles'] as Map<String, dynamic>? ?? {});
    final name =
        '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim();
    return _PremiumCard(
      title: 'Lender Information',
      subtitle: 'Upgraded Account',
      child: Column(
        children: [
          Row(
            children: [
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
              Text(
                _capitalize(
                    profile['account_upgrade_status'] as String? ?? 'Unknown'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _upgradeColor(
                        profile['account_upgrade_status'] as String?))),
            ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _KVRow(
              label: 'Employment',
              value: _capitalize(profile['employment_type'] as String? ?? '-')),
          _KVRow(
              label: 'Monthly Income',
              value: profile['monthly_income'] != null
                  ? '₱${NumberFormat('#,##0.00').format(profile['monthly_income'])}'
                  : '-'),
          _KVRow(
              label: 'Address',
              value: _formatAddress(profile['address'] ?? loan['lender_address'])),
        ]));
  }

  Widget _buildCoMakerCard(Map<String, dynamic> loan) {
    final coMakers =
        (loan['co_makers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (coMakers.isEmpty) {
      return const _PremiumCard(
        title: 'Co-Maker',
        subtitle: 'Guarantor information',
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: 15, color: AppColors.textTertiary),
            SizedBox(width: 8),
            Expanded(
              child: Text('No co-maker on file for this application.',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ]));
    }
    final cm = coMakers.first;
    final signature = cm['signature'] as String?;
    final name = '${cm['first_name'] ?? ''} ${cm['last_name'] ?? ''}'.trim();
    return _PremiumCard(
      title: 'Co-Maker',
      subtitle: 'Guarantor & signature',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? '—' : name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    Text(cm['relationship'] as String? ?? '-',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ])),
            ]),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _KVRow(
              label: 'Phone',
              value: cm['phone_number'] as String? ?? '-'),
          _KVRow(
              label: 'Birthday',
              value: cm['date_of_birth'] as String? ?? '-'),
          _KVRow(
              label: 'Address',
              value: cm['address'] as String? ?? '-'),
          if (signature != null && signature.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Co-Maker Signature',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.4)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border)),
              clipBehavior: Clip.antiAlias,
              child: _buildSignatureImage(signature)),
          ],
        ]));
  }

  Widget _buildSignatureImage(String signature) {
    const placeholder = Center(
        child: Icon(Icons.draw_outlined,
            size: 32, color: AppColors.textTertiary));
    if (signature.startsWith('data:') || signature.startsWith('http')) {
      return Image.network(signature,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => placeholder);
    }
    try {
      final bytes = base64Decode(signature);
      return Image.memory(bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => placeholder);
    } catch (_) {
      return placeholder;
    }
  }

  Widget _buildLoanCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final frequency =
        (loan['payment_frequency'] ?? loan['frequency'] ?? '-').toString();
    final method = (loan['disbursement_method'] ?? '-').toString();
    return _PremiumCard(
      title: 'Loan Details',
      subtitle: 'Terms & disbursement',
      child: Column(
        children: [
          _KVRow(
              label: 'Principal',
              value: '₱${fmt.format(loan['principal_amount'] ?? 0)}',
              highlight: true),
          _KVRow(
              label: 'Interest (20%)',
              value: '₱${fmt.format(loan['interest_amount'] ?? 0)}'),
          const Divider(height: 1),
          const SizedBox(height: 4),
          _KVRow(
              label: 'Total Payable',
              value: '₱${fmt.format(loan['total_payable'] ?? 0)}',
              highlight: true),
          const SizedBox(height: 4),
          const Divider(height: 1),
          const SizedBox(height: 4),
          _KVRow(label: 'Frequency', value: _capitalize(frequency)),
          _KVRow(label: 'Loan Term', value: _loanTermLabel(loan)),
          _KVRow(
              label: 'No. of Payments',
              value: '${loan['term_periods'] ?? '-'}'),
          _KVRow(
              label: 'Installment',
              value: '₱${fmt.format(loan['installment_amount'] ?? 0)}'),
          _KVRow(
              label: 'Purpose',
              value: (loan['purpose'] as String?) ??
                  (loan['loan_purpose'] as String?) ??
                  '-'),
          if (loan['rejection_reason'] != null &&
              (loan['rejection_reason'] as String).isNotEmpty)
            _KVRow(
                label: 'Rejection Reason',
                value: loan['rejection_reason'] as String,
                valueStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error)),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(_disbursementIcon(method),
                  size: 14, color: _disbursementColor(method)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Disbursement: ${_capitalize(method.replaceAll('_', ' '))}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _disbursementColor(method))),
              ),
            ]),
        ]));
  }

  Widget _buildSchedulePreview(Map<String, dynamic> loan, NumberFormat fmt) {
    final schedules = (loan['loan_schedules'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .take(5)
        .toList();
    if (schedules.isEmpty) {
      return const _PremiumCard(
        title: 'Payment Schedule',
        subtitle: 'First 5 periods',
        child: Row(
          children: [
            Icon(Icons.event_note_outlined,
                size: 15, color: AppColors.textTertiary),
            SizedBox(width: 8),
            Expanded(
              child: Text('No schedule generated yet.',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ]));
    }
    return _PremiumCard(
      title: 'Payment Schedule',
      subtitle: 'First 5 periods • Preview',
      trailing: Text('${loan['term_periods'] ?? schedules.length} payments',
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white70)),
      child: Column(
        children: [
          Table(
            columnWidths: const {
              0: FlexColumnWidth(0.9),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(1.2),
            },
            border: const TableBorder(
              horizontalInside: BorderSide(color: Color(0xFFF0F0F0)),
            ),
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFF8F9FB)),
                children: ['#', 'Due Date', 'Amount Due', 'Status']
                    .map((h) => Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 9),
                          child: Text(h,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  color: AppColors.textSecondary))))
                    .toList()),
              ...schedules.map((s) {
                final st = s['status'] as String? ?? '-';
                return TableRow(
                  children: [
                    _tableCell(
                        s['period_number']?.toString() ??
                            s['installment_number']?.toString() ??
                            '-',
                        bold: true),
                    _tableCell(_formatDate(s['due_date'])),
                    _tableCell('₱${fmt.format(s['amount_due'] ?? 0)}',
                        bold: true),
                    _scheduleStatusCell(st),
                  ]);
              }),
            ],
          ),
          const SizedBox(height: 6),
          const Text('Full schedule available after approval.',
              style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
        ]));
  }

  Widget _tableCell(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: AppColors.textPrimary)));

  Widget _scheduleStatusCell(String status) {
    final s = status.toLowerCase();
    final Color c;
    switch (s) {
      case 'paid':
        c = AppColors.success;
        break;
      case 'overdue':
        c = AppColors.error;
        break;
      default:
        c = AppColors.warning;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Text(
        status.isEmpty ? '-' : _capitalize(status),
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: c,
            letterSpacing: 0.2),
      ),
    );
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
            onPressed:
                _isActing ? null : () => _applyPenalty(loan['id'] as String),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            child: const Text('Apply',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
        ]));
  }

  Future<void> _applyPenalty(String loanId) async {
    final ok = await _confirmDialog(
      title: 'Apply Penalty',
      message: 'Apply 20% penalty? This cannot be undone.',
      confirmLabel: 'Apply',
    );
    if (ok != true || !mounted) return;
    setState(() => _isActing = true);
    try {
      await sl<LoanRemoteDataSource>().applyPenalty(loanId);
      if (!mounted) return;
      _toast('Penalty applied', AppColors.success);
      _refreshAfterAction();
    } catch (e) {
      if (!mounted) return;
      _toast('Failed to apply penalty: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  // ───────────────────────── Actions ─────────────────────────
  Future<void> _confirmApprove(Map<String, dynamic> loan) async {
    final ok = await _confirmDialog(
      title: 'Approve Loan',
      message:
          'Are you sure you want to approve ${loan['loan_number'] ?? 'this loan'}?',
      confirmLabel: 'Approve',
    );
    if (ok != true || !mounted) return;
    setState(() => _isActing = true);
    try {
      await ref.read(empLoanProvider.notifier).approveLoan(widget.loanId);
      if (!mounted) return;
      _toast('Loan approved successfully', AppColors.success);
      _refreshAfterAction();
    } catch (e) {
      if (!mounted) return;
      _toast('Approval failed: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _confirmRequestCi(Map<String, dynamic> loan) async {
    final ok = await _confirmDialog(
      title: 'Request CI',
      message:
          'Request credit investigation for ${loan['loan_number'] ?? 'this loan'}?',
      confirmLabel: 'Request',
    );
    if (ok != true || !mounted) return;
    setState(() => _isActing = true);
    try {
      await ref.read(empLoanProvider.notifier).requestCi(widget.loanId);
      if (!mounted) return;
      _toast('Credit investigation requested', AppColors.success);
      _refreshAfterAction();
    } catch (e) {
      if (!mounted) return;
      _toast('Request failed: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _showRejectDialog(Map<String, dynamic> loan) async {
    _reasonCtrl.clear();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('Reject Loan',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rejecting ${loan['loan_number'] ?? 'this loan'}. '
                'Please provide a reason:',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter rejection reason...',
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: AppColors.border)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero)),
            onPressed: () => Navigator.pop(ctx, _reasonCtrl.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ));
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() => _isActing = true);
    try {
      await ref
          .read(empLoanProvider.notifier)
          .rejectLoan(widget.loanId, reason);
      if (!mounted) return;
      _toast('Loan rejected', AppColors.error);
      _refreshAfterAction();
    } catch (e) {
      if (!mounted) return;
      _toast('Reject failed: $e', AppColors.textSecondary);
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(title,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text(message,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepNavy,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero)),
            child: Text(confirmLabel),
          ),
        ],
      ));
  }

  void _refreshAfterAction() {
    ref.invalidate(_empModalLoanDetailProvider(widget.loanId));
    ref.read(empLoanProvider.notifier).load();
  }

  void _toast(String msg, Color color) {
    context.showSnackBarAsToast(
        SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ───────────────────────── Helpers ─────────────────────────
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

  Color _upgradeColor(String? s) {
    switch (s) {
      case 'approved':
      case 'verified':
        return AppColors.success;
      case 'pending':
      case 'submitted':
        return AppColors.warning;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
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
  final bool highlight;
  final TextStyle? valueStyle;
  const _KVRow(
      {required this.label,
      required this.value,
      this.highlight = false,
      this.valueStyle});
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
                  TextStyle(
                      fontSize: 13,
                      fontWeight:
                          highlight ? FontWeight.w800 : FontWeight.w600,
                      color: highlight
                          ? AppColors.deepNavy
                          : AppColors.textPrimary),
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
      ],
    );
  }
}

class _StatusText extends StatelessWidget {
  final String status;
  const _StatusText({required this.status});
  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final Color c;
    if (s == 'rejected' ||
        s == 'cancelled' ||
        s == 'overdue' ||
        s == 'suspended' ||
        s == 'blacklisted' ||
        s == 'declined') {
      c = const Color(0xFFFFB4AB);
    } else if (s == 'pending' ||
        s == 'under_review' ||
        s == 'ci_required' ||
        s == 'ci_assigned' ||
        s == 'ci_completed' ||
        s == 'requested' ||
        s == 'in_progress' ||
        s == 'submitted') {
      c = const Color(0xFFFFD54F);
    } else if (s.isEmpty || s == '-' || s == 'unknown') {
      c = Colors.white70;
    } else {
      c = Colors.white;
    }
    return Text(
      s.isEmpty || s == '-'
          ? '-'
          : '${status[0].toUpperCase()}${status.substring(1).replaceAll('_', ' ')}',
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: c,
          letterSpacing: 0.3),
    );
  }
}
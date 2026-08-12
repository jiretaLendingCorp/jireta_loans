// lib/presentation/features/head_manager/loans/screens/hm_loan_application_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../providers/hm_loan_provider.dart';
import '../widgets/approve_reject_modal.dart';
import '../../ci/widgets/ci_assign_modal.dart';

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
    final isPending = [
      'pending',
      'under_review',
      'ci_required',
      'ci_assigned',
      'ci_completed'
    ].contains(status);
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
          if (isPending) _buildActionButtons(loan, status),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final status = loan['status'] as String? ?? '';
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
            _row('Account Upgrade Status',
                _capitalize(profile['account_upgrade_status'] as String? ?? 'Unknown')),
            _row('Employment',
                _capitalize(profile['employment_type'] as String? ?? '-')),
            _row(
                'Monthly Income',
                profile['monthly_income'] != null
                    ? '₱${NumberFormat('#,##0.00').format(profile['monthly_income'])}'
                    : '-'),
            _row('Blacklisted',
                profile['is_blacklisted'] == true ? '🔴 Yes' : '🟢 No'),
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
            _row(
                'Name',
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
                child: signature.startsWith('data:') ||
                        signature.startsWith('http')
                    ? Image.network(
                        signature,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.draw_outlined,
                                size: 40, color: AppColors.textTertiary)),
                      )
                    : const Center(
                        child: Icon(Icons.draw_outlined,
                            size: 40, color: AppColors.textTertiary)),
              ),
            ],
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
            const Text('Loan Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            _row('Principal', '₱${fmt.format(loan['principal_amount'] ?? 0)}'),
            _row('Interest (20%)',
                '₱${fmt.format(loan['interest_amount'] ?? 0)}'),
            _row('Total Payable', '₱${fmt.format(loan['total_payable'] ?? 0)}',
                bold: true),
            _row('Frequency',
                _capitalize(loan['payment_frequency'] as String? ?? '-')),
            _row('Term', '${loan['term_days'] ?? '-'} days'),
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

  Widget _buildActionButtons(Map<String, dynamic> loan, String status) {
    final canApprove = status == 'ci_completed';
    final canAssignCi = ['pending', 'under_review', 'ci_required'].contains(status);
    final canRequestCi = status == 'under_review';
    final canReject = [
      'pending',
      'under_review',
      'ci_required',
      'ci_assigned',
      'ci_completed'
    ].contains(status);
    final canCancel = ['pending', 'under_review'].contains(status);

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
            const Text('Actions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Review all details above before taking action.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (canApprove)
                  ElevatedButton.icon(
                    onPressed: () => _showApprove(loan['id'] as String),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (canAssignCi)
                  ElevatedButton.icon(
                    onPressed: () => _showAssignRider(loan['id'] as String),
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Assign Rider for CI'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black87,
                    ),
                  ),
                if (canRequestCi)
                  ElevatedButton.icon(
                    onPressed: () => _requestCi(loan['id'] as String),
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Request CI'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black87,
                    ),
                  ),
                if (canReject)
                  OutlinedButton.icon(
                    onPressed: () => _showReject(loan['id'] as String),
                    icon: const Icon(Icons.cancel_outlined,
                        size: 18, color: AppColors.error),
                    label: const Text('Reject',
                        style: TextStyle(color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.error)),
                  ),
                if (canCancel)
                  TextButton.icon(
                    onPressed: () => _confirmCancel(loan['id'] as String),
                    icon: const Icon(Icons.close,
                        size: 18, color: AppColors.textSecondary),
                    label: const Text('Cancel',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showApprove(String loanId) {
    showDialog(
      context: context,
      builder: (_) => ApproveRejectModal(
        loanId: loanId,
        isApprove: true,
        onConfirm: (_, __) async {
          final ok =
              await ref.read(hmLoanProvider.notifier).approveLoan(loanId);
          if (!mounted) return;
          Navigator.of(context).pop();
          if (ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Loan approved successfully'),
                  backgroundColor: AppColors.success),
            );
            context.go(RouteConstants.hmLoanApplications);
          }
        },
      ),
    );
  }

  void _showReject(String loanId) {
    showDialog(
      context: context,
      builder: (_) => ApproveRejectModal(
        loanId: loanId,
        isApprove: false,
        onConfirm: (_, reason) async {
          final ok = await ref
              .read(hmLoanProvider.notifier)
              .rejectLoan(loanId, reason ?? '');
          if (!mounted) return;
          Navigator.of(context).pop();
          if (ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Loan rejected'),
                  backgroundColor: AppColors.error),
            );
            context.go(RouteConstants.hmLoanApplications);
          }
        },
      ),
    );
  }

  Future<void> _showAssignRider(String loanId) async {
    final assigned = await showDialog<bool>(
      context: context,
      builder: (_) => CiAssignModal(loanId: loanId),
    );
    if (assigned == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rider assigned for credit investigation'),
          backgroundColor: AppColors.success,
        ),
      );
      await _load();
    }
  }

  Future<void> _requestCi(String loanId) async {
    final ok = await ref.read(hmLoanProvider.notifier).requestCi(loanId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(ok ? 'CI requested successfully' : 'Failed to request CI'),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
    if (ok) await _load();
  }

  Future<void> _confirmCancel(String loanId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Application'),
        content: const Text(
            'Are you sure you want to cancel this loan application?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final ok = await ref.read(hmLoanProvider.notifier).cancelLoan(loanId);
      if (ok && mounted) context.go(RouteConstants.hmLoanApplications);
    }
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
        c = AppColors.lenderPurple;
        break;
      default:
        c = AppColors.info;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
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
}

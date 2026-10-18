// lib/presentation/features/head_manager/lenders/widgets/lender_loan_history_modal.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';

/// Kumpletong kasaysayan ng loan ng isang kliyente (lender) para sa head
/// manager.
///
/// Kasama ang LAHAT ng loan — pending, approved, ongoing/active, overdue, at
/// completed. Kaya kapag nabayaran na ng lender ang loan niya (completed na
/// ito), nakikita pa rin ito ng admin dito kasama ng mga dating loan.
Future<void> showHmLenderLoanHistoryModal(
  BuildContext context, {
  required String lenderId,
  required String lenderName,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => LenderLoanHistoryModal(
      lenderId: lenderId,
      lenderName: lenderName,
    ),
  );
}

class LenderLoanHistoryModal extends StatefulWidget {
  final String lenderId;
  final String lenderName;

  const LenderLoanHistoryModal({
    super.key,
    required this.lenderId,
    required this.lenderName,
  });

  @override
  State<LenderLoanHistoryModal> createState() => _LenderLoanHistoryModalState();
}

class _LenderLoanHistoryModalState extends State<LenderLoanHistoryModal> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// `limit: 100` — ito ang maximum ng `validatePagination` sa backend, kaya
  /// ito na ang pinakamalapit sa "kompletong" kasaysayan sa isang query.
  Future<Map<String, dynamic>> _load() => sl<LoanRemoteDataSource>().getList(
        lenderId: widget.lenderId,
        limit: 100,
      );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: size.width > 720 ? 720 : size.width * 0.96,
          maxHeight: size.height * 0.88,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 24,
                  offset: Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(context),
              const Divider(height: 1, color: AppColors.divider),
              Flexible(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const _LoadingHistory();
                    }
                    if (snap.hasError) {
                      return const _EmptyHistory(
                        icon: Icons.error_outline_rounded,
                        title: 'Hindi ma-load ang loan history',
                        message:
                            'Subukang muli. Kung nagpatuloy ito, i-refresh ang pahina.',
                      );
                    }
                    return _historyBody(snap.data ?? const {});
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: const BoxDecoration(
        color: AppColors.deepNavy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.history_rounded,
                size: 19, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Previous Loans',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.lenderName.isEmpty
                      ? 'All loans of this client'
                      : 'All loans of ${widget.lenderName}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _historyBody(Map<String, dynamic> res) {
    final rows = (res['data'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final meta = res['meta'] as Map<String, dynamic>? ?? const {};
    final total = (meta['total'] as num?)?.toInt() ?? rows.length;

    if (rows.isEmpty) {
      return const _EmptyHistory(
        icon: Icons.history_toggle_off_rounded,
        title: 'No previous loans found',
        message: 'Wala pang loan ang kliyenteng ito.',
      );
    }

    final ongoing = rows
        .where((r) => ['active', 'overdue'].contains(_statusOf(r)))
        .length;
    final completed = rows.where((r) => _statusOf(r) == 'completed').length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatChip(label: 'Total loans', value: '$total'),
              const SizedBox(width: 8),
              _StatChip(
                  label: 'Ongoing', value: '$ongoing', color: AppColors.riderGreen),
              const SizedBox(width: 8),
              _StatChip(
                  label: 'Completed',
                  value: '$completed',
                  color: AppColors.statusCompleted),
            ],
          ),
          const SizedBox(height: 14),
          ...rows.map(_loanTile),
          if (total > rows.length) ...[
            const SizedBox(height: 6),
            Text(
              'Nagpapakita ng ${rows.length} sa $total loans.',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  static String _statusOf(Map<String, dynamic> m) =>
      (m['status'] ?? '').toString().toLowerCase();

  Widget _loanTile(Map<String, dynamic> m) {
    final status = _statusOf(m);
    final loanNumber = (m['loan_number'] ?? '—').toString();
    final principal = (m['principal_amount'] as num?)?.toDouble() ?? 0;
    final outstanding = (m['outstanding_balance'] as num?)?.toDouble();
    final frequency = (m['payment_frequency'] ?? m['frequency'] ?? '')
        .toString()
        .toLowerCase();
    final createdAt = parseManila(m['created_at']);
    final appliedAt =
        createdAt != null ? DateFormat('MMM dd, yyyy').format(createdAt) : '—';

    // Ang outstanding ay may saysay lang sa na-release at hindi pa tapos na
    // loan (active/overdue) — ₱0.00 sa pending/approved/completed.
    final isReleased = status == 'active' || status == 'overdue';
    final isCompleted = status == 'completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loanNumber,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    'Applied $appliedAt',
                    if (frequency.isNotEmpty) frequency.toUpperCase(),
                  ].join(' · '),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₱${_money.format(principal)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  isReleased
                      ? 'Outstanding ₱${_money.format(outstanding ?? 0)}'
                      : isCompleted
                          ? 'Fully paid'
                          : '—',
                  style: TextStyle(
                    fontSize: 11,
                    color: isReleased
                        ? AppColors.deepNavy
                        : isCompleted
                            ? AppColors.success
                            : AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Kapareho ng Loan Records: 'Ongoing' ang label ng aktibong loan.
          StatusBadge(
            status: status,
            labelOverride: status == 'active' ? 'Ongoing' : null,
            small: true,
          ),
        ],
      ),
    );
  }

  static final _money = NumberFormat('#,##0.00', 'en_PH');
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.deepNavy;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: accent),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingHistory extends StatelessWidget {
  const _LoadingHistory();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShimmerLoader(height: 44),
          SizedBox(height: 10),
          ShimmerLoader(height: 64),
          SizedBox(height: 8),
          ShimmerLoader(height: 64),
          SizedBox(height: 8),
          ShimmerLoader(height: 64),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyHistory({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

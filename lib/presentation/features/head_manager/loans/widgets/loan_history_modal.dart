// lib/presentation/features/head_manager/loans/widgets/loan_history_modal.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';

/// KASAYSAYAN NG LOAN (Loan Records → Previous Loan tab)
///
/// Ipinapakita para sa isang loan:
///   • ang buod nito (principal, total paid, outstanding),
///   • LAHAT ng pagbabayad — petsa at ORAS, halaga, paraan, at status, at
///   • ang mga DATING loan ng parehong kliyente (previous loans), kaya
///     makikita ng head manager ang buong kasaysayan niya sa isang tingin.
Future<void> showHmLoanHistoryModal(
  BuildContext context, {
  required LoanModel loan,
  String? detailsPath,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => HmLoanHistoryModal(loan: loan, detailsPath: detailsPath),
  );
}

class HmLoanHistoryModal extends StatefulWidget {
  final LoanModel loan;

  /// Route ng "Open loan details" — HM ang default; iba ang path ng Employee
  /// Loan Records.
  final String? detailsPath;

  const HmLoanHistoryModal({
    super.key,
    required this.loan,
    this.detailsPath,
  });

  @override
  State<HmLoanHistoryModal> createState() => _HmLoanHistoryModalState();
}

class _HistoryData {
  final Map<String, dynamic> details;
  final List<Map<String, dynamic>> clientLoans;
  const _HistoryData({required this.details, required this.clientLoans});
}

class _HmLoanHistoryModalState extends State<HmLoanHistoryModal> {
  static final _money = NumberFormat('#,##0.00', 'en_PH');
  static final _day = DateFormat('MMM dd, yyyy');
  static final _time = DateFormat('h:mm a');
  late Future<_HistoryData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HistoryData> _load() async {
    final ds = sl<LoanRemoteDataSource>();
    // Detalye ng loan → kasama ang `payments` (amount, method, paid_at, status).
    final details = await ds.getDetails(loanId: widget.loan.id);
    // Kasaysayan ng kliyente: lahat ng loan niya sa parehong lender_id.
    var clientLoans = <Map<String, dynamic>>[];
    if (widget.loan.lenderId.isNotEmpty) {
      try {
        final res = await ds.getList(lenderId: widget.loan.lenderId, limit: 100);
        clientLoans = (res['data'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
      } catch (_) {
        // Best-effort lang ang previous loans — hindi dapat i-block ang
        // payment history kung mabigo ito.
      }
    }
    return _HistoryData(details: details, clientLoans: clientLoans);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: size.width > 820 ? 820 : size.width * 0.96,
          maxHeight: size.height * 0.9,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            // Square corners — walang border radius ang modal.
            borderRadius: BorderRadius.zero,
            boxShadow: [
              BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 32,
                  offset: Offset(0, 12)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(context),
              Flexible(
                child: FutureBuilder<_HistoryData>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const _LoadingHistory();
                    }
                    if (snap.hasError) {
                      return const _EmptyNote(
                        icon: Icons.error_outline_rounded,
                        text: 'Failed to load loan history. Please try again.',
                      );
                    }
                    return _body(snap.data!);
                  },
                ),
              ),
              _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header(BuildContext context) {
    final lenderName = widget.loan.lenderName ??
        '${widget.loan.lenderFirstName} ${widget.loan.lenderLastName}'.trim();
    final status = widget.loan.status.toLowerCase();
    // Light variants — madaling basahin sa navy header (dark background).
    final (statusColor, statusLabel) = switch (status) {
      'completed' => (const Color(0xFFA5D6A7), 'Completed'),
      'overdue' => (const Color(0xFFFF8A80), 'Overdue'),
      'active' => (const Color(0xFFA5D6A7), 'Ongoing'),
      _ => (Colors.white70, status.replaceAll('_', ' ')),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.deepNavy, Color(0xFF1E3350)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                size: 21, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Previous Loan · ${widget.loan.loanNumber}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  lenderName.isEmpty ? '—' : lenderName,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.72)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Plain status text — hindi button ang dating.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                statusLabel,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor),
              ),
            ],
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded,
                size: 18, color: Colors.white70),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _body(_HistoryData data) {
    final payments = (data.details['payments'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final outstanding = widget.loan.outstandingBalance;
    final isCompleted = widget.loan.status.toLowerCase() == 'completed' ||
        widget.loan.isFullyPaid;

    // Ang KASALUKUYANG loan ay "previous loan" na rin kapag bayad na
    // (completed) — bahagi na ito ng kasaysayan, kaya dapat nakikita sa
    // listahan. Habang ongoing pa ito, hindi ito inuulit dito; ang mga DATING
    // loan lang ng kliyente ang nasa section. Minamarkahan ito ng "This loan".
    final previousLoans = data.clientLoans.where((l) {
      final isCurrent = (l['id'] ?? '').toString() == widget.loan.id;
      return !isCurrent || isCompleted;
    }).toList();
    if (isCompleted &&
        !previousLoans
            .any((l) => (l['id'] ?? '').toString() == widget.loan.id)) {
      previousLoans.insert(0, {
        'id': widget.loan.id,
        'loan_number': widget.loan.loanNumber,
        'status': widget.loan.status,
        'principal_amount': widget.loan.principalAmount,
        'created_at': widget.loan.createdAt,
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Buod ng loan ────────────────────────────────────────────────
          _SummaryRow(
            items: [
              _SummaryItem('Principal',
                  '₱${_money.format(widget.loan.principalAmount)}',
                  AppColors.deepNavy, Icons.payments_outlined),
              _SummaryItem('Total paid',
                  '₱${_money.format(widget.loan.totalPaid)}',
                  AppColors.success, Icons.savings_outlined),
              _SummaryItem(
                  'Outstanding',
                  '₱${_money.format(outstanding)}',
                  isCompleted
                      ? AppColors.textSecondary
                      : AppColors.goldDark,
                  Icons.account_balance_wallet_outlined),
            ],
          ),
          const SizedBox(height: 20),

          // ── Mga pagbabayad (petsa at oras) ──────────────────────────────
          _SectionTitle(
            title: 'Payments',
            subtitle: 'Date, time, and amount of each payment',
            trailing: '${payments.length} transaction'
                '${payments.length == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 8),
          if (payments.isEmpty)
            const _EmptyNote(
              icon: Icons.info_outline_rounded,
              text: 'No payments recorded for this loan yet.',
            )
          else
            _PaymentsTable(payments: payments, money: _money),
          const SizedBox(height: 20),

          // ── Mga dating loan ng kliyente ─────────────────────────────────
          _SectionTitle(
            title: 'Previous Loans',
            subtitle: 'All loans of this client',
            trailing: '${previousLoans.length} loan'
                '${previousLoans.length == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 8),
          if (previousLoans.isEmpty)
            const _EmptyNote(
              icon: Icons.history_toggle_off_rounded,
              text: 'No other loans for this client yet.',
            )
          else
            _ClientLoansList(
              loans: previousLoans,
              money: _money,
            ),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _footer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFC),
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Complete payment history and previous loans of this client.',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              context.push(widget.detailsPath ??
                  RouteConstants.hmLoanApplicationDetails
                      .replaceFirst(':id', widget.loan.id));
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: const Text('Open loan details'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.deepNavy,
              side:
                  BorderSide(color: AppColors.deepNavy.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Summary ─────────────────────────────────────────────────────────────────
class _SummaryItem {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _SummaryItem(this.label, this.value, this.color, this.icon);
}

class _SummaryRow extends StatelessWidget {
  final List<_SummaryItem> items;
  const _SummaryRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // 2x2 sa makitid na lapad, 4-in-a-row sa desktop.
      // 2 per row sa makitid na lapad; lahat sa isang row sa desktop.
      final isNarrow = constraints.maxWidth < 620;
      final perRow = isNarrow ? 2 : items.length;
      final width =
          (constraints.maxWidth - 8 * (perRow - 1)) / perRow;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items
            .map((it) => SizedBox(width: width, child: _SummaryCard(item: it)))
            .toList(),
      );
    });
  }
}

class _SummaryCard extends StatelessWidget {
  final _SummaryItem item;
  const _SummaryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: item.color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.icon, size: 13, color: item.color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  item.label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w700,
                      color: item.color.withValues(alpha: 0.85)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: item.color),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Payments table ──────────────────────────────────────────────────────────
class _PaymentsTable extends StatelessWidget {
  final List<Map<String, dynamic>> payments;
  final NumberFormat money;
  const _PaymentsTable({required this.payments, required this.money});

  static String _methodLabel(String m) {
    switch (m) {
      case 'gcash':
      case 'gcash_xendit':
        return 'GCash';
      case 'office_cash':
      case 'cash':
        return 'Office Cash';
      case 'rider_collection':
        return 'Rider Collection';
      default:
        return m.isEmpty ? 'Payment' : m.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = payments.fold<double>(
        0, (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            color: AppColors.surfaceVariant,
            child: const Row(
              children: [
                Expanded(flex: 4, child: _TableHead('DATE & TIME')),
                Expanded(flex: 3, child: _TableHead('AMOUNT')),
                Expanded(flex: 3, child: _TableHead('METHOD')),
                Expanded(flex: 2, child: _TableHead('STATUS')),
              ],
            ),
          ),
          ...payments.map(_row),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFBFC),
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            // "Total paid" at amount — magkatabi, hindi magkalayo.
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('Total paid',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                const SizedBox(width: 10),
                Text(
                  '₱${money.format(total)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.success),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> p) {
    final amount = (p['amount'] as num?)?.toDouble() ?? 0;
    final method = (p['payment_method'] ?? '').toString().toLowerCase();
    final status = (p['status'] ?? '').toString().toLowerCase();
    final isVerified = status == 'verified';
    final paidAt = parseManila(p['paid_at'] ?? p['created_at']);
    final reference = (p['xendit_reference'] ?? p['notes'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paidAt != null ? _HmLoanHistoryModalState._day.format(paidAt) : '—',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // ORAS ng bayad — hiwalay na linya para malinaw.
                Text(
                  paidAt != null
                      ? _HmLoanHistoryModalState._time.format(paidAt)
                      : '',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
                if (reference.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Ref: $reference',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textTertiary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '₱${money.format(amount)}',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _methodLabel(method),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            // 'verified' = bayad na (kapareho ng payments status label).
            child: Text(
              isVerified ? 'Paid' : paymentStatusLabel(status),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color:
                      isVerified ? AppColors.success : AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHead extends StatelessWidget {
  final String label;
  const _TableHead(this.label);

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.textSecondary),
        overflow: TextOverflow.ellipsis,
      );
}

// ── Client loans list ───────────────────────────────────────────────────────
class _ClientLoansList extends StatelessWidget {
  final List<Map<String, dynamic>> loans;
  final NumberFormat money;
  const _ClientLoansList({
    required this.loans,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < loans.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: i.isEven ? Colors.white : const Color(0xFFFBFCFD),
                border: i == loans.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: AppColors.divider)),
              ),
              child: _row(loans[i]),
            ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> l) {
    final number = (l['loan_number'] ?? '—').toString();
    final status = (l['status'] ?? '').toString().toLowerCase();
    final principal = (l['principal_amount'] as num?)?.toDouble() ?? 0;
    // `parseManilaValue` — raw backend string O DateTime na galing model.
    final createdAt = parseManilaValue(l['created_at']);
    final applied =
        createdAt != null ? _HmLoanHistoryModalState._day.format(createdAt) : '—';
    final isCompleted = status == 'completed';

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                number,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${isCompleted ? 'Completed' : 'Applied'} · $applied',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textTertiary),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            '₱${money.format(principal)}',
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: AppColors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Shared bits ─────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final String trailing;
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.deepNavy),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: const TextStyle(
                    fontSize: 10.5, color: AppColors.textTertiary),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Text(
          trailing,
          style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
      ],
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
          ShimmerLoader(height: 76),
          SizedBox(height: 14),
          ShimmerLoader(height: 90),
          SizedBox(height: 10),
          ShimmerLoader(height: 60),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyNote({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

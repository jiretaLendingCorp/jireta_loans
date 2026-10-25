// lib/presentation/features/head_manager/rider_monitoring/screens/hm_rider_monitoring_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../../core/extensions/date_extensions.dart';
import '../../../../../core/extensions/num_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../data/models/rider_collection_monitoring_model.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/hm_rider_monitoring_provider.dart';
import '../utils/monitoring_money.dart';
import '../widgets/rider_monitoring_stat_card.dart';

class HmRiderMonitoringDetailsScreen extends ConsumerStatefulWidget {
  final String riderId;
  const HmRiderMonitoringDetailsScreen({super.key, required this.riderId});

  @override
  ConsumerState<HmRiderMonitoringDetailsScreen> createState() =>
      _HmRiderMonitoringDetailsScreenState();
}

class _HmRiderMonitoringDetailsScreenState
    extends ConsumerState<HmRiderMonitoringDetailsScreen> {
  String? _dateFrom;
  String? _dateTo;
  bool _readQuery = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_readQuery) return;
    _readQuery = true;
    final params = GoRouterState.of(context).uri.queryParameters;
    _dateFrom = _validDate(params['date_from']);
    _dateTo = _validDate(params['date_to']);
  }

  static String? _validDate(String? value) {
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    return value;
  }

  RiderMonitoringDetailArgs get _args => (
        riderId: widget.riderId,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmRiderMonitoringDetailProvider(_args));
    final detail = state.detail;

    return WebScaffold(
      title: 'Rider Monitoring',
      // Back button sa TOP BAR — hindi na sa loob ng profile card.
      leading: IconButton(
        tooltip: 'Back',
        onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () =>
              ref.read(hmRiderMonitoringDetailProvider(_args).notifier).load(),
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
      ],
      body: Container(
        color: context.cPageBg,
        child: state.isLoading && detail == null
            ? const RiderMonitoringDetailSkeleton()
            : state.error != null && detail == null
                ? ErrorStateWidget(
                    message: state.error!,
                    onRetry: () => ref
                        .read(hmRiderMonitoringDetailProvider(_args).notifier)
                        .load(),
                  )
                : detail == null
                    ? EmptyStateWidget(
                        title: 'Rider not found',
                        message:
                            'The rider may have been archived. Go back to the monitoring list and refresh.',
                        actionLabel: 'Go back',
                        onAction: () => context.pop(),
                      )
                    : RiderMonitoringDetailBody(
                        detail: detail,
                        dateFrom: _dateFrom,
                        dateTo: _dateTo,
                      ),
      ),
    );
  }
}

/// Loading skeleton ng rider details page.
///
/// SCROLLABLE ito (tulad ng totoong body sa ibaba) — dati ay hubad na
/// `Column` na may fixed-height shimmer, kaya sa mababang viewport (hal.
/// 1366x690 desktop) "BOTTOM OVERFLOWED BY N PIXELS" ang lumalabas habang
/// naglo-load pa lang. Public para direktang ma-test ang layout.
class RiderMonitoringDetailSkeleton extends StatelessWidget {
  const RiderMonitoringDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        children: [
          ShimmerLoader(height: 130, borderRadius: 16),
          SizedBox(height: 16),
          ShimmerLoader(height: 120, borderRadius: 12),
          SizedBox(height: 16),
          ShimmerLoader(height: 260, borderRadius: 16),
        ],
      ),
    );
  }
}

/// Body ng rider details page. Public para direktang ma-test ang rendering
/// (hal. JSON numbers na `dynamic` → `₱` formatting) nang walang network.
class RiderMonitoringDetailBody extends StatelessWidget {
  final RiderMonitoringDetail detail;
  final String? dateFrom;
  final String? dateTo;

  const RiderMonitoringDetailBody({
    super.key,
    required this.detail,
    this.dateFrom,
    this.dateTo,
  });

  Map<String, dynamic> get _rider => detail.rider;
  List<Map<String, dynamic>> get _accounts => detail.accounts;
  List<Map<String, dynamic>> get _payments => detail.payments;
  List<Map<String, dynamic>> get _history => detail.history;

  Map<String, dynamic> get _summary => {
        'expected_collection': detail.summary.expectedCollection,
        'confirmed_collection': detail.summary.confirmedCollection,
        'remaining_due': detail.summary.remainingDue,
        'overdue_accounts': detail.summary.overdueAccounts,
        'overdue_installments': detail.summary.overdueInstallments,
        'assigned_installments': detail.summary.assignedInstallments,
        'open_assignments': detail.summary.openAssignments,
        'collection_performance': detail.summary.collectionPerformance,
      };

  static double _num(dynamic value) => monitoringAmount(value);

  String get _rangeLabel {
    if (dateFrom == null && dateTo == null) return 'All dates';
    final from = dateFrom == null
        ? 'Beginning'
        : DateFormat('MMM d, y').format(DateTime.parse(dateFrom!));
    final to = dateTo == null
        ? 'Today'
        : DateFormat('MMM d, y').format(DateTime.parse(dateTo!));
    return '$from – $to';
  }

  @override
  Widget build(BuildContext context) {
    final performance =
        (_summary['collection_performance'] as num?)?.toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileCard(
            rider: _rider,
            summary: _summary,
            rangeLabel: _rangeLabel,
          ),
          const SizedBox(height: 20),
          const _SectionTitle(
            title: 'Collection Summary',
            subtitle:
                'Expected versus verified collections for the selected range.',
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              // 4 compact cards kada row sa desktop (~1060px content), 2 sa
              // tablet, 1 sa mobile.
              final perRow = constraints.maxWidth >= 960
                  ? 4
                  : constraints.maxWidth >= 640
                      ? 2
                      : 1;
              final width =
                  (constraints.maxWidth - (perRow - 1) * 12) / perRow - 1;
              final cards = [
                RiderMonitoringStatCard(
                  title: 'Expected Collection',
                  value: _num(_summary['expected_collection']).toPeso(),
                  icon: Icons.event_note_outlined,
                  color: AppColors.info,
                  subtitle:
                      '${_summary['assigned_installments'] ?? 0} installments',
                ),
                RiderMonitoringStatCard(
                  title: 'Confirmed Collection',
                  value: _num(_summary['confirmed_collection']).toPeso(),
                  icon: Icons.verified_outlined,
                  color: AppColors.success,
                  subtitle: performance == null
                      ? null
                      : '${performance.toStringAsFixed(1)}%',
                ),
                RiderMonitoringStatCard(
                  title: 'Remaining Amount Due',
                  value: _num(_summary['remaining_due']).toPeso(),
                  icon: Icons.pending_actions_outlined,
                  color: AppColors.warning,
                ),
                RiderMonitoringStatCard(
                  title: 'Overdue Accounts',
                  value: '${_summary['overdue_accounts'] ?? 0}',
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.statusRejected,
                  subtitle:
                      '${_summary['overdue_installments'] ?? 0} installments',
                ),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children:
                    cards.map((c) => SizedBox(width: width, child: c)).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Assigned Lenders & Loan Accounts',
            subtitle:
                'Outstanding balances come from the same verified-payment records used by Loan Records.',
            trailing: '${_accounts.length} account(s)',
          ),
          const SizedBox(height: 10),
          if (_accounts.isEmpty)
            const _InlineEmpty(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No assigned accounts',
              message:
                  'This rider has no collection assignments in the selected date range.',
            )
          else
            ..._accounts.map((account) => _AccountCard(account: account)),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Confirmed Payments',
            subtitle:
                'Verified payments only — pending, failed, cancelled and unverified records are excluded.',
            trailing: '${_payments.length} record(s)',
          ),
          const SizedBox(height: 10),
          _PaymentsTable(payments: _payments),
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Collection History',
            subtitle:
                'Assignment activity, including declined, rejected and pending records.',
            trailing: '${_history.length} record(s)',
          ),
          const SizedBox(height: 10),
          _HistoryTable(history: _history),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final Map<String, dynamic> rider;
  final Map<String, dynamic> summary;
  final String rangeLabel;

  const _ProfileCard({
    required this.rider,
    required this.summary,
    required this.rangeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final name = (rider['rider_name'] ?? 'Rider').toString().trim();
    final parts = name.split(RegExp(r'\s+'));
    final initials = parts.take(2).map((p) => p.isEmpty ? '' : p[0]).join();
    final isAvailable = rider['is_available'] as bool?;
    final joinedAt = DateTime.tryParse((rider['joined_at'] ?? '').toString());
    final contact = <String>[
      if ((rider['phone_number'] ?? '').toString().trim().isNotEmpty)
        rider['phone_number'].toString(),
      if ((rider['plate_number'] ?? '').toString().trim().isNotEmpty)
        rider['plate_number'].toString(),
      if ((rider['vehicle_type'] ?? '').toString().trim().isNotEmpty)
        rider['vehicle_type'].toString(),
    ];
    final address = (rider['address'] ?? '').toString().trim();
    final open = (summary['open_assignments'] as num? ?? 0).toInt();
    final overdue = (summary['overdue_accounts'] as num? ?? 0).toInt();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plain text na lang ang date range — hindi na chip/button ang
          // itsura (dati may tinted na pill background).
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_outlined,
                    size: 14, color: context.cTextTertiary),
                const SizedBox(width: 6),
                Text(
                  rangeLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: context.cTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final identity = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor:
                        AppColors.riderGreen.withValues(alpha: 0.12),
                    child: Text(
                      initials.isEmpty ? 'R' : initials.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.riderGreen,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name.isEmpty ? 'Unnamed rider' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: context.cTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          joinedAt == null
                              ? 'Rider'
                              : 'Rider · Joined ${DateFormat('MMM d, y').format(joinedAt)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: context.cTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final tags = Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Plain status text (may maliit na dot) — hindi button/pill.
                  _StatusText(
                    label: isAvailable == true ? 'Available' : 'Unavailable',
                    color: isAvailable == true
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                  if (open > 0)
                    _Pill(label: '$open open', color: AppColors.info),
                  if (overdue > 0)
                    _Pill(
                      label: '$overdue overdue',
                      color: AppColors.statusRejected,
                    ),
                ],
              );
              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [identity, const SizedBox(height: 10), tags],
                );
              }
              return Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 12),
                  tags,
                ],
              );
            },
          ),
          if (contact.isNotEmpty || address.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: context.cDivider),
            const SizedBox(height: 10),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                if (contact.isNotEmpty)
                  _Meta(
                    icon: Icons.badge_outlined,
                    text: contact.join('  ·  '),
                  ),
                if (address.isNotEmpty)
                  _Meta(icon: Icons.location_on_outlined, text: address),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.cTextTertiary),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: context.cTextSecondary),
          ),
        ),
      ],
    );
  }
}

/// Status na plain text + maliit na colored dot — hindi ito button o chip na
/// pinipindot, kaya walang background.
class _StatusText extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusText({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Compact na empty state para sa mga section ng details page — hindi ito
/// kumukuha ng buong viewport (dating `EmptyStateWidget` na may 72px circle
/// at 40px padding, kaya napakalaki ng blangko).
class _InlineEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _InlineEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.cSurfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: context.cTextTertiary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.cTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.cTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? trailing;

  const _SectionTitle({
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.cTextPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cTextSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(fontSize: 12, color: context.cTextTertiary),
          ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  final Map<String, dynamic> account;

  const _AccountCard({required this.account});

  static double _num(dynamic value) => monitoringAmount(value);

  @override
  Widget build(BuildContext context) {
    final schedules = (account['schedules'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final overdue = account['overdue_installments'] as num? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  (account['lender_name'] ?? 'Unknown lender').toString(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.cTextPrimary,
                  ),
                ),
                Text(
                  'Loan ${account['loan_number'] ?? '—'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cTextSecondary,
                  ),
                ),
                if ((account['loan_status'] ?? '').toString().isNotEmpty)
                  StatusBadge(status: account['loan_status'].toString()),
                if (overdue > 0)
                  _Pill(
                    label: '$overdue overdue',
                    color: AppColors.statusRejected,
                  ),
                const SizedBox(width: 8),
                Text(
                  'Outstanding ${_num(account['outstanding_balance']).toPeso()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.cTextPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: context.cSurfaceVariant,
            child: Wrap(
              spacing: 20,
              runSpacing: 4,
              children: [
                _Money(
                    label: 'Expected', value: account['expected_collection']),
                _Money(
                  label: 'Confirmed',
                  value: account['confirmed_collection'],
                  color: AppColors.success,
                ),
                _Money(
                  label: 'Remaining',
                  value: account['remaining_due'],
                  color: AppColors.warning,
                ),
                Text(
                  '${schedules.length} installment(s)',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          ResponsiveTableScroll(
            minWidth: 820,
            child: Column(
              children: [
                _scheduleHeader(context),
                ...schedules.map((s) => _scheduleRow(context, s)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleHeader(BuildContext context) {
    const style = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: AppColors.textTertiary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: context.cBorder),
          bottom: BorderSide(color: context.cBorder),
        ),
      ),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('#', style: style)),
          Expanded(flex: 3, child: Text('DUE DATE', style: style)),
          Expanded(flex: 3, child: Text('AMOUNT DUE', style: style)),
          Expanded(flex: 3, child: Text('PAID', style: style)),
          Expanded(flex: 3, child: Text('REMAINING', style: style)),
          Expanded(flex: 3, child: Text('CONFIRMED (RIDER)', style: style)),
          Expanded(flex: 2, child: Text('STATUS', style: style)),
        ],
      ),
    );
  }

  Widget _scheduleRow(BuildContext context, Map<String, dynamic> s) {
    final status = (s['status'] ?? 'pending').toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.cDivider)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text('${s['installment_number'] ?? '—'}',
                style: TextStyle(fontSize: 12, color: context.cTextPrimary)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              s['due_date'] == null
                  ? '—'
                  : DateFormat('MMM d, y')
                      .format(DateTime.parse(s['due_date'].toString())),
              style: TextStyle(fontSize: 12, color: context.cTextSecondary),
            ),
          ),
          Expanded(flex: 3, child: _amount(s['amount_due'], context)),
          Expanded(flex: 3, child: _amount(s['amount_paid'], context)),
          Expanded(
            flex: 3,
            child: _amount(
              s['remaining_due'],
              context,
              color: _num(s['remaining_due']) > 0 ? AppColors.warning : null,
            ),
          ),
          Expanded(
            flex: 3,
            child: _amount(s['confirmed_collection'], context,
                color: AppColors.success),
          ),
          Expanded(
            flex: 2,
            child: _ScheduleStatus(
              status: status,
              overdue: status == 'overdue' && _num(s['remaining_due']) > 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _amount(dynamic value, BuildContext context, {Color? color}) {
    return Text(
      _num(value).toPeso(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color ?? context.cTextPrimary,
      ),
    );
  }
}

class _ScheduleStatus extends StatelessWidget {
  final String status;
  final bool overdue;
  const _ScheduleStatus({required this.status, required this.overdue});

  @override
  Widget build(BuildContext context) {
    final effective = overdue ? 'overdue' : status;
    final (color, label) = switch (effective) {
      'paid' => (AppColors.success, 'Paid'),
      'partial' => (AppColors.warning, 'Partial'),
      'overdue' => (AppColors.statusRejected, 'Overdue'),
      _ => (context.cTextSecondary, 'Pending'),
    };
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

class _Money extends StatelessWidget {
  final String label;
  final dynamic value;
  final Color? color;
  const _Money({required this.label, this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              fontSize: 11,
              color: context.cTextSecondary,
            ),
          ),
          TextSpan(
            // `monitoringPeso` ang humahawak ng dynamic JSON values nang
            // walang dynamic-dispatch extension error.
            text: monitoringPeso(value),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color ?? context.cTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentsTable extends StatelessWidget {
  final List<Map<String, dynamic>> payments;
  const _PaymentsTable({required this.payments});

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return const _InlineEmpty(
        icon: Icons.verified_outlined,
        title: 'No confirmed payments',
        message:
            'No verified collections were recorded for this rider in the selected range.',
      );
    }
    return ResponsiveListCard(
      minTableWidth: 820,
      variant: ResponsiveListVariant.premium,
      columns: const [
        ResponsiveCol('Date', icon: Icons.event_outlined, flex: 2),
        ResponsiveCol('Lender', icon: Icons.person_outline, flex: 3),
        ResponsiveCol('Loan', icon: Icons.description_outlined, flex: 2),
        ResponsiveCol('Installment', icon: Icons.format_list_numbered, flex: 1),
        ResponsiveCol('Amount', icon: Icons.payments_outlined, flex: 2),
      ],
      rows: payments.map((p) {
        final paidAt = p['paid_at'] == null
            ? null
            : DateTime.tryParse(p['paid_at'].toString());
        return ResponsiveRow(
          cells: [
            Text(
              paidAt == null ? '—' : paidAt.toDateString(),
              style: TextStyle(fontSize: 12, color: context.cTextSecondary),
            ),
            Text(
              (p['lender_name'] ?? '—').toString(),
              style: TextStyle(fontSize: 12, color: context.cTextPrimary),
            ),
            Text(
              (p['loan_number'] ?? '—').toString(),
              style: TextStyle(fontSize: 12, color: context.cTextPrimary),
            ),
            Text(
              '#${p['installment_number'] ?? '—'}',
              style: TextStyle(fontSize: 12, color: context.cTextSecondary),
            ),
            Text(
              monitoringPeso(p['amount']),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.success,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _HistoryTable extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _HistoryTable({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const _InlineEmpty(
        icon: Icons.history_rounded,
        title: 'No collection history',
        message: 'No assignment activity in the selected date range.',
      );
    }
    return ResponsiveListCard(
      minTableWidth: 900,
      variant: ResponsiveListVariant.premium,
      columns: const [
        ResponsiveCol('Date', icon: Icons.event_outlined, flex: 2),
        ResponsiveCol('Lender', icon: Icons.person_outline, flex: 3),
        ResponsiveCol('Loan', icon: Icons.description_outlined, flex: 2),
        ResponsiveCol('Installment', icon: Icons.format_list_numbered, flex: 1),
        ResponsiveCol('Collected', icon: Icons.payments_outlined, flex: 2),
        ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 2),
      ],
      rows: history.map((h) {
        final at = h['activity_at'] == null
            ? null
            : DateTime.tryParse(h['activity_at'].toString());
        final collected = (h['amount_collected'] as num?)?.toDouble();
        return ResponsiveRow(
          cells: [
            Text(
              at == null ? '—' : at.toDateString(),
              style: TextStyle(fontSize: 12, color: context.cTextSecondary),
            ),
            Text(
              (h['lender_name'] ?? '—').toString(),
              style: TextStyle(fontSize: 12, color: context.cTextPrimary),
            ),
            Text(
              (h['loan_number'] ?? '—').toString(),
              style: TextStyle(fontSize: 12, color: context.cTextPrimary),
            ),
            Text(
              '#${h['installment_number'] ?? '—'}',
              style: TextStyle(fontSize: 12, color: context.cTextSecondary),
            ),
            Text(
              collected == null ? '—' : collected.toPeso(),
              style: TextStyle(fontSize: 12, color: context.cTextPrimary),
            ),
            StatusBadge(status: (h['status'] ?? 'pending').toString()),
          ],
        );
      }).toList(),
    );
  }
}

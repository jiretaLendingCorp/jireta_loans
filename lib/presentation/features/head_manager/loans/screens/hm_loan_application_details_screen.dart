// lib/presentation/features/head_manager/loans/screens/hm_loan_application_details_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../providers/hm_loan_provider.dart';

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
    if (!mounted) return;
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
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Back to Applications')),
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
              'The application may have been removed or the link is invalid.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => context.go(RouteConstants.hmLoanApplications),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to Applications'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: Colors.white)),
          ])));
  }

  Widget _buildContent() {
    final loan = _loan!;
    final rawStatus = loan['status'] as String? ?? '';
    final status = (loan['rider_delivery_assigned'] == true &&
            rawStatus == 'approved')
        ? 'rider_delivery_assigned'
        : rawStatus;
    final fmt = NumberFormat('#,##0.00', 'en_PH');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHero(loan, status, fmt),
          const SizedBox(height: 16),
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
                    _buildCoMakerCard(loan),
                    const SizedBox(height: 16),
                    _buildSchedulePreview(loan, fmt),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildCoMakerCard(loan)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildSchedulePreview(loan, fmt)),
                    ]),
                ]);
            }),
        ]));
  }

  // ─────────────────────────────── Hero (Simplified) ───────────────────────────────
  Widget _buildHero(Map<String, dynamic> loan, String status, NumberFormat fmt) {
    final lender = loan['lender'] as Map<String, dynamic>? ?? {};
    final name =
        '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim();
    final loanNumber = loan['loan_number'] as String? ?? 'Pending Number';
    final principal = (loan['principal_amount'] as num?)?.toDouble() ?? 0;
    final totalPayable = (loan['total_payable'] as num?)?.toDouble() ?? 0;
    final applied = loan['created_at'];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 2)),
        ]),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border)),
                child: const Icon(Icons.description_outlined,
                    color: AppColors.textSecondary, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loanNumber,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      name.isEmpty
                          ? 'Applied ${_formatDate(applied)}'
                          : '$name • Applied ${_formatDate(applied)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis),
                  ])),
              StatusBadge(status: status),
            ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
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
                  label: 'Term',
                  value: _loanTermLabel(loan))),
            ]),
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
      subtitle: 'Lender profile & KYC',
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
                    Text(
                      _maskPhone(lender['phone_number'] as String? ?? ''),
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
              label: 'Employment',
              value: _capitalize(profile['employment_type'] as String? ?? '-')),
          _KVRow(
              label: 'Monthly Income',
              value: profile['monthly_income'] != null
                  ? '₱${NumberFormat('#,##0.00').format(profile['monthly_income'])}'
                  : '-'),
          _KVRow(
              label: 'Address',
              value: _formatAddress(profile['address'])),
        ]));
  }

  Widget _buildLoanCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final frequency =
        (loan['payment_frequency'] ?? loan['frequency'] ?? '-').toString();
    final method = (loan['disbursement_method'] ?? '-').toString();

    return _PremiumCard(
      title: 'Loan Details',
      subtitle: 'Terms & disbursement preference',
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
                  child:
                      const Icon(Icons.savings_rounded, size: 16, color: AppColors.gold)),
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
              label: 'Frequency',
              value: _capitalize(frequency),
              valueWidget: _FrequencyPill(frequency: frequency)),
          _KVRow(label: 'Loan Term', value: _loanTermLabel(loan)),
          _KVRow(
              label: 'No. of Payments',
              value: '${loan['term_periods'] ?? '-'}'),
          _KVRow(
              label: 'Installment',
              value: '₱${fmt.format(loan['installment_amount'] ?? 0)}'),
          _KVRow(label: 'Purpose', value: loan['loan_purpose'] as String? ?? '-'),
          const SizedBox(height: 10),
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
                  'Disbursement: ${_capitalize(method.replaceAll('_', ' '))}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _disbursementColor(method))),
              ])),
        ]));
  }

  Widget _buildCoMakerCard(Map<String, dynamic> loan) {
    final coMakers =
        (loan['co_makers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (coMakers.isEmpty) {
      return _PremiumCard(
        title: 'Co-Maker',
        subtitle: 'Guarantor information',
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border)),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: AppColors.textTertiary),
              SizedBox(width: 8),
              Text('No co-maker on file for this application.',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ])));
    }
    final cm = coMakers.first;
    final signature = cm['signature'] as String?;
    final name =
        '${cm['first_name'] ?? ''} ${cm['last_name'] ?? ''}'.trim();

    return _PremiumCard(
      title: 'Co-Maker',
      subtitle: 'Guarantor & signature',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.lenderBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.person_outline_rounded,
                    color: AppColors.lenderBlue, size: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? '—' : name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    Text(cm['relationship'] as String? ?? '-',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ])),
            ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _KVRow(
              label: 'Phone',
              value: _maskPhone(cm['phone_number'] as String? ?? '')),
          _KVRow(
              label: 'Birthday',
              value: cm['date_of_birth'] as String? ?? '-'),
          _KVRow(
              label: 'Address',
              value: cm['address'] as String? ?? '-'),
          if (signature != null && signature.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Co-Maker Signature',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 8,
                      offset: Offset(0, 2)),
                ]),
              clipBehavior: Clip.antiAlias,
              child: _buildSignatureImage(signature)),
          ],
        ]));
  }

  Widget _buildSignatureImage(String signature) {
    const placeholder = Center(
      child: Icon(Icons.draw_outlined,
          size: 40, color: AppColors.textTertiary));
    if (signature.startsWith('data:') || signature.startsWith('http')) {
      return Image.network(
        signature,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => placeholder);
    }
    try {
      final bytes = base64Decode(signature);
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => placeholder);
    } catch (_) {
      return placeholder;
    }
  }

  Widget _buildSchedulePreview(Map<String, dynamic> loan, NumberFormat fmt) {
    final schedules = (loan['loan_schedules'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .take(5)
        .toList();
    if (schedules.isEmpty) {
      return _PremiumCard(
        title: 'Payment Schedule',
        subtitle: 'First 5 periods preview',
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border)),
          child: const Text('No schedule generated yet.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary))));
    }

    return _PremiumCard(
      title: 'Payment Schedule',
      subtitle: 'First 5 periods • Preview',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.deepNavy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20)),
        child: Text(
          '${loan['term_periods'] ?? schedules.length} total',
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.deepNavy))),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10)),
            clipBehavior: Clip.antiAlias,
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(0.9),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(1.2),
              },
              children: [
                TableRow(
                  decoration:
                      const BoxDecoration(color: Color(0xFFF8F9FB)),
                  children: ['#', 'Due Date', 'Amount Due', 'Status']
                      .map((h) => Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Text(h,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.4))))
                      .toList()),
                ...schedules.map((s) {
                  final st = s['status'] as String? ?? '-';
                  return TableRow(
                    decoration: const BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: Color(0xFFF0F0F0)))),
                    children: [
                      _tableCell(
                          s['period_number']?.toString() ??
                              s['installment_number']?.toString() ??
                              '-',
                          bold: true),
                      _tableCell(_formatDate(s['due_date'])),
                      _tableCell('₱${fmt.format(s['amount_due'] ?? 0)}',
                          bold: true),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: _ScheduleStatusPill(status: st)),
                    ]);
                }),
              ])),
          const SizedBox(height: 8),
          const Text(
            'Full schedule available after approval and disbursement.',
            style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
        ]));
  }

  Widget _tableCell(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: AppColors.textPrimary)));

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

class _ScheduleStatusPill extends StatelessWidget {
  final String status;
  const _ScheduleStatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.18))),
      child: Text(
        s.isEmpty ? '-' : '${s[0].toUpperCase()}${s.substring(1)}',
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: c)));
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
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
            textAlign: TextAlign.center),
      ]);
  }
}

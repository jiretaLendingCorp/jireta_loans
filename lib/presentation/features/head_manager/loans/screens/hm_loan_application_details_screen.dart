// lib/presentation/features/head_manager/loans/screens/hm_loan_application_details_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../core/utils/loan_frequency.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/constants/route_constants.dart';
import '../../../../shared/widgets/layout/web_scaffold.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../ci/widgets/ci_assign_modal.dart';
import '../../disbursements/widgets/rider_disburse_assign_modal.dart';
import '../providers/hm_loan_provider.dart';
import '../widgets/approve_reject_modal.dart';

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
      child: Center(
        // Wag masyadong i-wide — naka-constrain ang content sa gitna.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
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
                        _buildCoMakerCard(loan),
                        const SizedBox(height: 16),
                        _buildLoanCard(loan, fmt),
                        const SizedBox(height: 16),
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
                            const SizedBox(height: 16),
                            _buildCoMakerCard(loan),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLoanCard(loan, fmt),
                            const SizedBox(height: 16),
                            _buildSchedulePreview(loan, fmt),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────── Loan hero: name/applied nasa head ───────────────────
  Widget _buildHero(
      Map<String, dynamic> loan, String status, NumberFormat fmt) {
    final lender = loan['lender'] as Map<String, dynamic>? ?? {};
    final name =
        '${lender['first_name'] ?? ''} ${lender['last_name'] ?? ''}'.trim();
    final loanNumber = loan['loan_number'] as String? ?? 'Pending Number';
    final principal = (loan['principal_amount'] as num?)?.toDouble() ?? 0;
    final totalPayable = (loan['total_payable'] as num?)?.toDouble() ?? 0;
    final applied = loan['created_at'];

    return _PremiumCard(
      title: loanNumber,
      subtitle: name.isEmpty
          ? 'Applied ${_formatDateTime(applied)}'
          : '$name • Applied ${_formatDateTime(applied)}',
      trailing: _buildHeroTrailing(loan, status),
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
            child:
                _SimpleStat(label: 'Term', value: _loanTermLabel(loan))),
        ],
      ),
    );
  }

  // Status + vertical 3-dot menu sa right side ng Pending — pag pinindot,
  // lalabas ang Approve / Assign CI / Assign Delivery / Reject.
  Widget _buildHeroTrailing(Map<String, dynamic> loan, String status) {
    final s = (loan['status'] as String? ?? '').toLowerCase().trim();
    final ciStatus =
        (loan['ci_status'] as String?)?.toLowerCase().trim() ?? '';
    final ciFailed = ciStatus == 'failed' ||
        ciStatus == 'expired' ||
        ciStatus == 'declined';
    final canApprove = const {
      'pending',
      'under_review',
      'ci_required',
      'ci_assigned',
      'ci_completed'
    }.contains(s);
    final canAssignCi =
        const {'pending', 'under_review', 'ci_required'}.contains(s) ||
            (s == 'ci_assigned' && ciFailed);
    final canAssignDelivery = s == 'approved' &&
        loan['rider_delivery_assigned'] != true &&
        (loan['disbursement_method'] as String? ?? '') == 'rider_delivery';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusBadge(status: status),
        if (canApprove || canAssignCi || canAssignDelivery) ...[
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            tooltip: 'Actions',
            offset: const Offset(0, 36),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              switch (v) {
                case 'approve':
                  _showApprove(widget.loanId);
                  break;
                case 'reject':
                  _showReject(widget.loanId);
                  break;
                case 'assign_ci':
                  _showAssignCi();
                  break;
                case 'assign_delivery':
                  _showAssignDeliveryRider();
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
              if (canAssignCi)
                PopupMenuItem(
                    value: 'assign_ci',
                    child: Row(children: [
                      const Icon(Icons.search_rounded,
                          size: 16, color: AppColors.info),
                      const SizedBox(width: 8),
                      Text(ciFailed ? 'Reassign CI Rider' : 'Assign CI Rider')
                    ])),
              if (canAssignDelivery)
                const PopupMenuItem(
                    value: 'assign_delivery',
                    child: Row(children: [
                      Icon(Icons.delivery_dining_rounded,
                          size: 16, color: AppColors.goldDark),
                      SizedBox(width: 8),
                      Text('Assign Delivery Rider')
                    ])),
              if (canApprove)
                const PopupMenuItem(
                    value: 'reject',
                    child: Row(children: [
                      Icon(Icons.cancel_outlined,
                          size: 16, color: AppColors.error),
                      SizedBox(width: 8),
                      Text('Reject')
                    ])),
            ],
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.40)),
              ),
              child: const Icon(Icons.more_vert_rounded,
                  size: 18, color: Colors.white),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showApprove(String loanId) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ApproveRejectModal(
        loanId: loanId,
        isApprove: true,
        onConfirm: (_, __) async {
          final ok =
              await ref.read(hmLoanProvider.notifier).approveLoan(loanId);
          if (!mounted) return;
          Navigator.of(context).pop();
          _toast(ok ? 'Loan approved successfully' : 'Approval failed',
              ok ? AppColors.success : AppColors.error);
          if (ok) await _load();
        },
      ),
    );
  }

  Future<void> _showReject(String loanId) async {
    await showDialog<void>(
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
          _toast(ok ? 'Loan rejected' : 'Reject failed',
              ok ? AppColors.error : AppColors.textSecondary);
          if (ok) await _load();
        },
      ),
    );
  }

  Future<void> _showAssignCi() async {
    final assigned = await showDialog<bool>(
      context: context,
      builder: (_) => CiAssignModal(loanId: widget.loanId),
    );
    if (assigned == true && mounted) {
      _toast('Rider assigned for credit investigation', AppColors.success);
      await _load();
    }
  }

  Future<void> _showAssignDeliveryRider() async {
    final assigned = await showDialog<bool>(
      context: context,
      builder: (_) => RiderDisburseAssignModal(loanId: widget.loanId),
    );
    if (assigned == true && mounted) {
      _toast('Delivery rider assigned', AppColors.success);
      await _load();
    }
  }

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
    ));
  }

  // ───────────────────────── Cards ─────────────────────────
  // Lahat ng lender info mula sa upgrade account (profile + KYC) nakalagay
  // dito — puro labeled text rows lang, walang divider line at walang
  // button-like na pill. Ang Verified nasa gray header na.
  Widget _buildLenderCard(Map<String, dynamic> loan) {
    final lender = loan['lender'] as Map<String, dynamic>? ?? {};
    final profile = (loan['lender_profile'] as Map<String, dynamic>?) ??
        (lender['lender_profiles'] as Map<String, dynamic>? ?? {});

    String pick(Map m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
      return '';
    }

    String orDash(String v) => v.isEmpty ? '-' : v;

    final nameParts = [
      pick(lender, ['first_name']),
      pick(lender, ['middle_name']),
      pick(lender, ['last_name']),
    ].where((e) => e.isNotEmpty).toList();
    final name = nameParts.join(' ');
    final phone =
        pick(lender, ['phone_number', 'phone', 'mobile_number']);
    final email = pick(lender, ['email', 'email_address']);
    // Nasa lender_profiles ang gender/civil_status/birthday (kita sa
    // kyc-view), kaya profile muna bago lender fallback.
    final both = <String, dynamic>{...lender, ...profile};
    final gender = pick(both, ['gender']);
    final civilStatus = pick(both, ['civil_status']);
    final dobRaw =
        pick(both, ['date_of_birth', 'birthdate', 'birth_date']);
    final employment = pick(profile, ['employment_type', 'employment']);
    final employer = pick(profile, ['employer_name', 'employer']);
    final gcash = pick(profile, ['gcash_number', 'gcash']);
    final upgradeStatus = pick(profile, ['account_upgrade_status']);
    final addrParts = [
      pick(lender, ['street_address', 'street']),
      pick(lender, ['barangay']),
      pick(lender, ['city', 'town', 'municipality']),
      pick(lender, ['province']),
      pick(lender, ['zip_code', 'zipcode', 'postal_code']),
    ].where((e) => e.isNotEmpty).toList();
    final address = addrParts.isNotEmpty
        ? addrParts.join(', ')
        : _formatAddress(profile['address'] ?? loan['lender_address']);

    return _PremiumCard(
      title: 'Lender Information',
      subtitle: 'Upgraded Account',
      trailing: Text(
        upgradeStatus.isEmpty ? 'Unknown' : _capitalize(upgradeStatus),
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white),
      ),
      child: Column(
        children: [
          _KVRow(label: 'Name', value: name.isEmpty ? '—' : name),
          _KVRow(label: 'Phone', value: orDash(phone)),
          _KVRow(label: 'Email', value: orDash(email)),
          _KVRow(
              label: 'Gender', value: orDash(_capitalize(gender))),
          _KVRow(
              label: 'Civil Status', value: orDash(_capitalize(civilStatus))),
          _KVRow(
              label: 'Date of Birth',
              value: dobRaw.isEmpty ? '-' : _formatDate(dobRaw)),
          _KVRow(
              label: 'Employment',
              value: orDash(_capitalize(employment))),
          _KVRow(label: 'Employer', value: orDash(employer)),
          _KVRow(
              label: 'Monthly Income',
              value: profile['monthly_income'] != null
                  ? '₱${NumberFormat('#,##0.00').format(profile['monthly_income'])}'
                  : '-'),
          _KVRow(
              label: 'GCash Number', value: gcash.isEmpty ? 'N/A' : gcash),
          _KVRow(
              label: 'Address',
              value: orDash(address)),
        ]));
  }

  Widget _buildLoanCard(Map<String, dynamic> loan, NumberFormat fmt) {
    final frequency = resolveLoanFrequency(loan);
    final frequencyDisplay =
        frequency.isEmpty ? '-' : _capitalize(frequency);
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
          _KVRow(
              label: 'Total Payable',
              value: '₱${fmt.format(loan['total_payable'] ?? 0)}'),
          _KVRow(
              label: 'Frequency', value: frequencyDisplay),
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
          _KVRow(
              label: 'Disbursement',
              value: method.trim().isEmpty || method.trim() == '-'
                  ? 'N/A'
                  : _capitalize(method.replaceAll('_', ' '))),
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
    final dob = cm['date_of_birth'] as String? ?? '';

    return _PremiumCard(
      title: 'Co-Maker',
      subtitle: 'Guarantor & signature',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KVRow(label: 'Name', value: name.isEmpty ? '—' : name),
          _KVRow(
              label: 'Relationship',
              value: cm['relationship'] as String? ?? '-'),
          _KVRow(
              label: 'Phone',
              value: cm['phone_number'] as String? ?? '-'),
          _KVRow(
              label: 'Birthday',
              value: dob.isEmpty ? '-' : _formatDate(dob)),
          _KVRow(
              label: 'Address',
              value: cm['address'] as String? ?? '-'),
          if (signature != null && signature.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 130,
                    child: Text('Signature',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary))),
                  OutlinedButton.icon(
                    onPressed: () => _showSignatureViewer(signature),
                    icon: const Icon(Icons.visibility_outlined, size: 14),
                    label: const Text('View',
                        style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          if (_coMakerValidIdUrls(cm).isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 130,
                    child: Text('Valid ID',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary))),
                  OutlinedButton.icon(
                    onPressed: () => _showValidIdViewer(
                        _coMakerValidIdUrls(cm)),
                    icon: const Icon(Icons.visibility_outlined, size: 14),
                    label: const Text('View',
                        style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
        ]));
  }

  // Buong view ng signature sa dialog.
  Future<void> _showSignatureViewer(String signature) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Co-Maker Signature',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary))),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border)),
                  clipBehavior: Clip.antiAlias,
                  child: _buildSignatureImage(signature),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 00147: kinukuha ang URL ng co-maker valid ID image(s) — sa dialog
  /// pinapakita kapag pinindot ang View.
  List<String> _coMakerValidIdUrls(Map<String, dynamic> cm) {
    final docs = (cm['co_maker_documents'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .where((d) => d['document_type'] == 'valid_id')
        .toList();
    return docs
        .map((d) =>
            (d['signed_url'] as String?) ?? (d['file_path'] as String?))
        .where((url) => url != null && url.isNotEmpty)
        .cast<String>()
        .toList();
  }

  // Buong view ng valid ID image(s) sa dialog.
  Future<void> _showValidIdViewer(List<String> urls) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Co-Maker Valid ID',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary))),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var i = 0; i < urls.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            height: 280,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: AppColors.border)),
                            clipBehavior: Clip.antiAlias,
                            child: Image.network(
                              urls[i],
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.badge_outlined,
                                    size: 40,
                                    color: AppColors.textTertiary)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    final allSchedules = (loan['loan_schedules'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    // Once the loan is approved (or beyond), the schedule is final — show the
    // FULL list. Before approval it is a 5-row preview only.
    final status = (loan['status'] as String? ?? '').toLowerCase();
    final isFinal = ['approved', 'active', 'overdue', 'completed', 'rejected']
        .contains(status);
    final schedules =
        (isFinal ? allSchedules : allSchedules.take(5)).toList();
    // Frequency (Daily / Weekly / Monthly) — nakalagay sa subtitle at
    // mismo sa loob ng table area para laging visible.
    final frequency = resolveLoanFrequency(loan);
    final freqLabel = frequency.isEmpty ? '' : _capitalize(frequency);
    final emptySubtitle = freqLabel.isEmpty
        ? 'First 5 periods preview'
        : '$freqLabel • First 5 periods preview';
    final subtitle = freqLabel.isEmpty
        ? (isFinal ? 'Full schedule' : 'First 5 periods • Preview')
        : (isFinal
            ? '$freqLabel • Full schedule'
            : '$freqLabel • First 5 periods • Preview');
    if (schedules.isEmpty) {
      return _PremiumCard(
        title: 'Payment Schedule',
        subtitle: emptySubtitle,
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
      subtitle: subtitle,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20)),
        child: Text(
          '${loan['term_periods'] ?? allSchedules.length} total',
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white))),
      child: Column(
        children: [
          if (freqLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                // Plain text lang — hindi button.
                child: Text(
                  'Frequency: $freqLabel',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary),
                ),
              ),
            ),
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
          if (!isFinal) ...[
            const SizedBox(height: 8),
            const Text(
              'Full schedule available after approval and disbursement.',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
          ],
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
  String _formatDate(dynamic d) {
    if (d == null) return '-';
    final dt = parseManila(d);
    if (dt == null) return d.toString();
    return DateFormat('MMM dd, yyyy').format(dt);
  }

  String _formatDateTime(dynamic d) {
    if (d == null) return '-';
    final dt = parseManila(d);
    if (dt == null) return d.toString();
    return DateFormat('MMM dd, yyyy h:mm a').format(dt);
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

  String _loanTermLabel(Map<String, dynamic> loan) {
    final frequency = resolveLoanFrequency(loan);
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
                        color: AppColors.textPrimary))),
        ]));
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
    // Plain text lang — hindi button.
    return Text(
      s.isEmpty ? '-' : '${s[0].toUpperCase()}${s.substring(1)}',
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c));
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

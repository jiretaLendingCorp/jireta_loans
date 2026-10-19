// lib/presentation/features/head_manager/loans/widgets/loan_details_side_panel.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../../core/di/injection.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../../data/models/loan_model.dart';
import '../../../../shared/utils/file_downloader.dart';

/// Loader ng `loans-get-details` payload — maaaring palitan sa tests.
typedef LoanDetailsLoader = Future<Map<String, dynamic>> Function(
    String loanId);

/// SLIDE-IN PANEL NG LOAN DETAILS (Loan Records → Previous Loan → View)
///
/// Lumalabas sa KANAN ng screen (hindi dialog sa gitna): Loan ID + status,
/// financial summary, Client Information, Loan Information, Payment Schedule,
/// Payment History, Notes, at Download Receipt.
Future<void> showLoanDetailsSidePanel(
  BuildContext context, {
  required String loanId,
  LoanModel? loan,
  LoanDetailsLoader? loadDetails,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Loan Details',
    barrierColor: Colors.black.withValues(alpha: 0.28),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => Align(
      alignment: Alignment.centerRight,
      child: LoanDetailsSidePanel(
        loanId: loanId,
        loan: loan,
        loadDetails: loadDetails,
      ),
    ),
    transitionBuilder: (_, animation, __, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class LoanDetailsSidePanel extends StatefulWidget {
  final String loanId;

  /// Row data mula sa Previous Loan table — pantay agad ang Loan ID/status
  /// habang naglo-load pa ang buong details.
  final LoanModel? loan;

  /// Kapag `null`, `LoanRemoteDataSource.getDetails` ang ginagamit.
  final LoanDetailsLoader? loadDetails;

  const LoanDetailsSidePanel({
    super.key,
    required this.loanId,
    this.loan,
    this.loadDetails,
  });

  @override
  State<LoanDetailsSidePanel> createState() => _LoanDetailsSidePanelState();
}

class _LoanDetailsSidePanelState extends State<LoanDetailsSidePanel> {
  static final _money = NumberFormat('#,##0.00', 'en_PH');
  static final _compactMoney = NumberFormat('#,##0.##', 'en_PH');
  static final _day = DateFormat('MMM dd, yyyy');
  static final _dateTime = DateFormat('MMM dd, yyyy h:mm a');

  final _scrollCtrl = ScrollController();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loadDetails ??
          (id) => sl<LoanRemoteDataSource>().getDetails(loanId: id);
      final data = await loader(widget.loanId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load loan details.';
        _loading = false;
      });
    }
  }

  // ─────────────────────────────── Layout ────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 600;
    // Mas malapad para buo ang address, ang 5-column na payment history, at
    // hindi na kailangang mag-scroll nang pahiga.
    final width = isMobile ? size.width : (size.width >= 1200 ? 560.0 : 520.0);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        height: size.height,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: isMobile
              ? BorderRadius.zero
              : const BorderRadius.horizontal(left: Radius.circular(14)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x2E000000), blurRadius: 28, offset: Offset(-8, 0)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          left: false,
          child: Column(
            children: [
              _header(),
              Expanded(child: _body()),
              if (_data != null) _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.description_outlined,
                size: 19, color: AppColors.info),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Loan Details',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSecondary),
            tooltip: 'Close',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surfaceVariant,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4)),
            SizedBox(height: 12),
            Text('Loading loan details...',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    if (_error != null || _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 34, color: AppColors.textTertiary),
              const SizedBox(height: 10),
              Text(_error ?? 'Loan not found.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final data = _data!;
    // Laging visible ang scrollbar — hindi mukhang "naputol" ang sections sa
    // ilalim (Payment Schedule/History/Notes).
    return Scrollbar(
      controller: _scrollCtrl,
      thumbVisibility: true,
      thickness: 6,
      radius: const Radius.circular(3),
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(14, 14, 18, 18),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _loanIdCard(data),
          const SizedBox(height: 10),
          _financialCard(data),
          const SizedBox(height: 10),
          _sectionCard(
            icon: Icons.person_outline_rounded,
            title: 'Client Information',
            child: _clientInfo(data),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            icon: Icons.assignment_outlined,
            title: 'Loan Information',
            child: _loanInfo(data),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            icon: Icons.calendar_month_outlined,
            title: 'Payment Schedule',
            child: _scheduleTable(data),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            icon: Icons.history_rounded,
            title: 'Payment History',
            child: _paymentHistory(data),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Notes',
            child: Text(
              _notes(data),
              style: const TextStyle(
                  fontSize: 12.5, height: 1.5, color: AppColors.textSecondary),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton.icon(
          onPressed: _downloading ? null : _downloadReceipt,
          icon: _downloading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_outlined, size: 18),
          label: const Text(
            'Download Receipt',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.info,
            side: BorderSide(color: AppColors.info.withValues(alpha: 0.45)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────── Cards ─────────────────────────────────────
  Widget _loanIdCard(Map<String, dynamic> data) {
    final number = (data['loan_number'] as String?) ??
        widget.loan?.loanNumber ??
        '—';
    final (label, color, _) = _statusStyle(_statusKey(data));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Loan ID',
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.2),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  number,
                  style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Plain na text + dot — walang background, hindi mukhang button.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Apat na financial figures sa ISANG row — gaya ng mock.
  Widget _financialCard(Map<String, dynamic> data) {
    final totalPayable = _num(data['total_payable']);
    final outstanding = _num(data['outstanding_balance']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final width = (constraints.maxWidth - gap * 3) / 4;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: width,
                  child: _stat('Loan Amount', _peso(data['principal_amount']))),
              const SizedBox(width: gap),
              SizedBox(
                width: width,
                child: _stat(
                  'Total Amount Payable',
                  _peso(totalPayable),
                  sub: _interestLabel(data['interest_rate']),
                ),
              ),
              const SizedBox(width: gap),
              SizedBox(
                  width: width,
                  child: _stat('Total Amount Paid', _peso(_totalPaid(data)))),
              const SizedBox(width: gap),
              SizedBox(
                width: width,
                child: _stat(
                  'Remaining Balance',
                  _peso(outstanding),
                  valueColor: outstanding > 0 ? AppColors.error : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value, {String? sub, Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 10.5,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.textPrimary),
        ),
        if (sub != null && sub.trim().isNotEmpty)
          Text(
            sub.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 9.5, height: 1.2, color: AppColors.textTertiary),
          ),
      ],
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 15, color: AppColors.info),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _clientInfo(Map<String, dynamic> data) {
    final lender = (data['lender'] as Map<String, dynamic>?) ?? const {};
    final name = [
      lender['first_name'],
      lender['middle_name'],
      lender['last_name'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).join(' ');
    final phone = (lender['phone_number'] as String? ?? '').trim();
    final email = (lender['email'] as String? ?? '').trim();
    final address = _addressLabel(data['lender_address']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field('Client Name', name.isEmpty ? '—' : name)),
            const SizedBox(width: 12),
            Expanded(child: _field('Phone Number', phone.isEmpty ? '—' : phone)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: _field('Email', email.isEmpty ? 'Not provided' : email)),
            const SizedBox(width: 12),
            Expanded(child: _field('Address', address, maxLines: 3)),
          ],
        ),
      ],
    );
  }

  Widget _loanInfo(Map<String, dynamic> data) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field('Term', _termLabel(data)),
              const SizedBox(height: 10),
              _field('Installment Amount',
                  _peso(_num(data['installment_amount']))),
              const SizedBox(height: 10),
              _field('Start Date', _dayLabel(_startDate(data))),
              const SizedBox(height: 10),
              _field('End Date', _dayLabel(_endDate(data))),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field('Approval Date', _dateTimeLabel(_approvalDate(data))),
              const SizedBox(height: 10),
              _field('Completion Date', _dateTimeLabel(_completionDate(data))),
              const SizedBox(height: 10),
              _field('Transaction Reference', _transactionReference(data)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(String label, String value, {int maxLines = 2}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textTertiary),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 12.5,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
      ],
    );
  }

  Widget _scheduleTable(Map<String, dynamic> data) {
    final schedules = _schedules(data);
    if (schedules.isEmpty) {
      return const Text(
        'No payment schedule for this loan.',
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      );
    }

    Expanded head(String label, int flex, {TextAlign align = TextAlign.left}) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            label,
            textAlign: align,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary),
          ),
        ),
      );
    }

    Expanded cell(String value, int flex,
        {TextAlign align = TextAlign.left,
        FontWeight weight = FontWeight.w500}) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            value,
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: weight,
                color: AppColors.textPrimary),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF8F9FB),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            child: Row(
              children: [
                head('#', 1),
                head('Due Date', 3),
                head('Amount', 2, align: TextAlign.right),
                head('Status', 3),
                head('Paid Date', 3),
              ],
            ),
          ),
          ...schedules.asMap().entries.map((entry) {
            final s = entry.value;
            final status = (s['status'] as String?)?.toLowerCase() ?? 'pending';
            final (label, color, background) = _scheduleStatusStyle(status);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              decoration: BoxDecoration(
                border: entry.key == schedules.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  cell('${_installmentNo(s)}', 1, weight: FontWeight.w700),
                  cell(_dayLabel(s['due_date']), 3),
                  cell(_peso(_num(s['amount_due'])), 2,
                      align: TextAlign.right, weight: FontWeight.w700),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _pill(label, color, background, fontSize: 9.5),
                    ),
                  ),
                  cell(s['paid_at'] != null ? _dayLabel(s['paid_at']) : '—', 3),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _paymentHistory(Map<String, dynamic> data) {
    final payments = _payments(data);
    if (payments.isEmpty) {
      return const Text(
        'No payments recorded yet.',
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      );
    }

    Expanded head(String label, int flex, {TextAlign align = TextAlign.left}) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            label,
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF8F9FB),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            child: Row(
              children: [
                head('Date & Time', 4),
                head('Amount', 3, align: TextAlign.right),
                head('Method', 3),
                head('Reference', 4),
                head('Status', 3),
              ],
            ),
          ),
          ...payments.asMap().entries.map((entry) {
            final p = entry.value;
            final status = (p['status'] as String?)?.toLowerCase() ?? '';
            final verified = status == 'verified';
            final (label, color, background) = verified
                ? (
                    'Successful',
                    AppColors.success,
                    AppColors.successLight,
                  )
                : _scheduleStatusStyle(status == '' ? 'pending' : status);
            final ref = _paymentReference(p);
            Widget cell(String value, int flex,
                {TextAlign align = TextAlign.left,
                FontWeight weight = FontWeight.w500,
                Color color = AppColors.textPrimary}) {
              return Expanded(
                flex: flex,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    value,
                    textAlign: align,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 9.5, fontWeight: weight, color: color),
                  ),
                ),
              );
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              decoration: BoxDecoration(
                border: entry.key == payments.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  cell(_dateTimeLabel(p['paid_at'] ?? p['created_at']), 4,
                      weight: FontWeight.w600),
                  cell(_peso(_num(p['amount'])), 3,
                      align: TextAlign.right, weight: FontWeight.w700),
                  cell(_methodLabel(p['payment_method'] as String? ?? ''), 3),
                  cell(ref.isEmpty ? '—' : ref, 4),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _pill(label, color, background, fontSize: 9),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color, Color background,
      {double fontSize = 9}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: fontSize, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  // ─────────────────────────────── Download ──────────────────────────────────
  Future<void> _downloadReceipt() async {
    final data = _data;
    if (data == null) return;
    setState(() => _downloading = true);
    try {
      final bytes = await _buildReceiptPdf(data);
      final number =
          (data['loan_number'] as String?) ?? widget.loan?.loanNumber ?? 'loan';
      final safe = number.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      await saveFile(bytes, 'Loan-Receipt-$safe.pdf');
      if (!mounted) return;
      context.showSnackBarAsToast(
        const SnackBar(
            content: Text('Receipt downloaded'),
            backgroundColor: AppColors.success),
      );
    } catch (_) {
      if (!mounted) return;
      context.showSnackBarAsToast(
        const SnackBar(
            content: Text('Unable to download the receipt'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<Uint8List> _buildReceiptPdf(Map<String, dynamic> data) async {
    final doc = pw.Document();
    final number =
        (data['loan_number'] as String?) ?? widget.loan?.loanNumber ?? '-';
    final lender = (data['lender'] as Map<String, dynamic>?) ?? const {};
    final borrower = [
      lender['first_name'],
      lender['middle_name'],
      lender['last_name'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).join(' ');
    final payments = _payments(data);

    String money(dynamic value) => 'PHP ${_money.format(_num(value))}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Text('Jireta Loans & Credit Corp',
              style:
                  pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text('OFFICIAL LOAN RECEIPT',
              style:
                  const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 12),
          pw.Divider(color: PdfColors.grey400),
          pw.SizedBox(height: 8),
          pw.Text('Loan ID: $number',
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          if (borrower.isNotEmpty)
            pw.Text('Borrower: $borrower',
                style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Status: ${_statusStyle(_statusKey(data)).$1}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['Item', 'Value'],
            data: [
              ['Loan Amount', money(data['principal_amount'])],
              ['Total Amount Payable', money(data['total_payable'])],
              ['Total Amount Paid', money(_totalPaid(data))],
              ['Remaining Balance', money(data['outstanding_balance'])],
              ['Term', _termLabel(data)],
              ['Start Date', _dayLabel(_startDate(data))],
              ['End Date', _dayLabel(_endDate(data))],
              ['Transaction Reference', _transactionReference(data)],
            ],
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey800),
            headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellPadding: const pw.EdgeInsets.all(5),
          ),
          pw.SizedBox(height: 14),
          pw.Text('PAYMENTS',
              style:
                  pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (payments.isEmpty)
            pw.Text('No payments recorded.',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey700))
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Amount', 'Method', 'Reference'],
              data: [
                for (final p in payments)
                  [
                    _dayLabel(p['paid_at'] ?? p['created_at']),
                    money(p['amount']),
                    _methodLabel(p['payment_method'] as String? ?? ''),
                    _paymentReference(p),
                  ],
              ],
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blueGrey800),
              headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.all(5),
            ),
          pw.SizedBox(height: 14),
          pw.Text('Notes: ${_notes(data)}',
              style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 18),
          pw.Text(
              'Generated ${DateFormat('MMM dd, yyyy h:mm a').format(nowManila())}',
              style:
                  const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ],
      ),
    );
    return doc.save();
  }

  // ─────────────────────────────── Helpers ───────────────────────────────────
  double _num(dynamic value) => (value as num?)?.toDouble() ?? 0;

  String _peso(dynamic value) => '₱${_compactMoney.format(_num(value))}';

  String _dayLabel(dynamic value) {
    final dt = parseManila(value);
    return dt == null ? '—' : _day.format(dt);
  }

  String _dateTimeLabel(dynamic value) {
    final dt = parseManila(value);
    return dt == null ? '—' : _dateTime.format(dt);
  }

  List<Map<String, dynamic>> _schedules(Map<String, dynamic> data) {
    final list = ((data['loan_schedules'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    list.sort((a, b) => _installmentNo(a).compareTo(_installmentNo(b)));
    return list;
  }

  List<Map<String, dynamic>> _payments(Map<String, dynamic> data) {
    final list = ((data['payments'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    list.sort((a, b) {
      final da = parseManila(a['paid_at'] ?? a['created_at']);
      final db = parseManila(b['paid_at'] ?? b['created_at']);
      if (da == null || db == null) return 0;
      return da.compareTo(db);
    });
    return list;
  }

  int _installmentNo(Map<String, dynamic> s) =>
      (s['installment_number'] as num?)?.toInt() ??
      (s['period_number'] as num?)?.toInt() ??
      0;

  /// Kabuuang bayad na — verified payments, o `total payable - outstanding`
  /// kapag wala pang payments sa payload.
  double _totalPaid(Map<String, dynamic> data) {
    var paid = 0.0;
    for (final p in _payments(data)) {
      if ((p['status'] as String?)?.toLowerCase() == 'verified') {
        paid += _num(p['amount']);
      }
    }
    if (paid > 0) return paid;
    final remaining =
        _num(data['total_payable']) - _num(data['outstanding_balance']);
    return remaining > 0 ? remaining : 0;
  }

  dynamic _startDate(Map<String, dynamic> data) =>
      data['disbursed_at'] ?? data['release_date'] ?? data['created_at'];

  /// End date: huling schedule, `due_date`, huling bayad, o huling update.
  dynamic _endDate(Map<String, dynamic> data) {
    final schedules = _schedules(data);
    if (schedules.isNotEmpty) {
      DateTime? latest;
      dynamic latestRaw;
      for (final s in schedules) {
        final dt = parseManila(s['due_date']);
        if (dt != null && (latest == null || dt.isAfter(latest))) {
          latest = dt;
          latestRaw = s['due_date'];
        }
      }
      if (latestRaw != null) return latestRaw;
    }
    if (data['due_date'] != null) return data['due_date'];
    final payments = _payments(data);
    if (payments.isNotEmpty) {
      return payments.last['paid_at'] ?? payments.last['created_at'];
    }
    return data['updated_at'];
  }

  dynamic _approvalDate(Map<String, dynamic> data) =>
      data['disbursed_at'] ?? data['release_date'] ?? data['updated_at'];

  dynamic _completionDate(Map<String, dynamic> data) {
    final payments = _payments(data);
    if (payments.isNotEmpty) {
      return payments.last['paid_at'] ?? payments.last['created_at'];
    }
    return _statusKey(data) == 'completed' ? data['updated_at'] : null;
  }

  String _transactionReference(Map<String, dynamic> data) {
    for (final d in ((data['disbursements'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()) {
      for (final key in const [
        'xendit_id',
        'xendit_reference',
        'reference_number'
      ]) {
        final raw = d[key];
        if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      }
    }
    for (final p in _payments(data)) {
      final ref = _paymentReference(p);
      if (ref != '—') return ref;
    }
    // Walang Xendit/payment reference (hal. cash o rider release) — gamitin
    // ang Loan ID bilang reference para may masuri pa ring numero.
    return (data['loan_number'] as String?) ?? '—';
  }

  /// Reference ng isang bayad. Ang GCash/Xendit ay may `xendit_reference`;
  /// ang cash at rider collection ay walang external ref — ang maikling
  /// payment ID ang system reference para hindi "—" ang lumabas.
  String _paymentReference(Map<String, dynamic> p) {
    for (final key in const [
      'reference_number',
      'xendit_reference',
      'xendit_payment_id',
    ]) {
      final raw = p[key];
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    }
    final id = (p['id'] as String?)?.replaceAll('-', '').trim();
    if (id != null && id.isNotEmpty) {
      final short = id.length > 8 ? id.substring(0, 8) : id;
      return 'PAY-${short.toUpperCase()}';
    }
    final idem = (p['idempotency_key'] as String?)?.trim();
    if (idem != null && idem.isNotEmpty) return idem;
    return '—';
  }

  String _termLabel(Map<String, dynamic> data) {
    final frequency = (data['payment_frequency'] ?? data['frequency'] ?? '')
        .toString()
        .toLowerCase();
    final unit = frequency == 'daily'
        ? 'days'
        : frequency == 'weekly'
            ? 'weeks'
            : 'months';
    var count = (data['term_periods'] as num?)?.toInt() ?? 0;
    if (count <= 0) count = _schedules(data).length;
    final term = count > 0
        ? '$count ${_plural(count, unit)}'
        : ((data['term_days'] as num?)?.toInt() ?? 0) > 0
            ? '${(data['term_days'] as num).toInt()} ${_plural((data['term_days'] as num).toInt(), 'days')}'
            : '—';
    if (frequency.isEmpty || term == '—') return term;
    return '$term (${frequency[0].toUpperCase()}${frequency.substring(1)})';
  }

  /// "1 day" / "3 months" — hindi "1 days".
  String _plural(int count, String unit) =>
      count == 1 && unit.endsWith('s')
          ? unit.substring(0, unit.length - 1)
          : unit;

  String _addressLabel(dynamic raw) {
    if (raw == null) return '—';
    if (raw is String) return raw.trim().isEmpty ? '—' : raw.trim();
    if (raw is Map) {
      final parts = [
        raw['street'],
        raw['barangay'],
        raw['city'],
        raw['province'],
        raw['zip_code'],
      ]
          .where((e) => e != null && e.toString().trim().isNotEmpty)
          .map((e) => e.toString().trim())
          .toList();
      return parts.isEmpty ? '—' : parts.join(', ');
    }
    return raw.toString();
  }

  /// "(20% flat rate)" sa ilalim ng Total Amount Payable — ang aktwal na
  /// rate ng loan (`loans.interest_rate`), hindi hardcoded.
  String _interestLabel(dynamic rate) {
    final value =
        rate is num ? rate.toDouble() : double.tryParse('${rate ?? ''}');
    if (value == null) return '';
    final text =
        value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
    return '($text% flat rate)';
  }

  String _methodLabel(String method) {
    switch (method) {
      case 'gcash':
      case 'gcash_xendit':
        return 'GCash';
      case 'office_cash':
      case 'cash':
        return 'Office';
      case 'rider_collection':
        return 'Rider';
      default:
        return method.isEmpty
            ? '—'
            : method.replaceAll('_', ' ').split(' ').map((w) {
                if (w.isEmpty) return w;
                return '${w[0].toUpperCase()}${w.substring(1)}';
              }).join(' ');
    }
  }

  String _notes(Map<String, dynamic> data) {
    final raw = data['notes'] ?? data['remarks'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    final status = _statusKey(data);
    if (status == 'completed') {
      return 'Loan fully paid. No outstanding balance.';
    }
    if (status == 'overdue') {
      return 'This loan is overdue. Coordinate with the borrower for the remaining balance.';
    }
    return 'No notes for this loan.';
  }

  /// Status key ng panel. Ang released na loan na ubos nang bayad ay
  /// Completed kahit `active` pa ang hilaw na status.
  String _statusKey(Map<String, dynamic> data) {
    final status = (data['status'] as String? ?? '').toLowerCase();
    final outstanding = _num(data['outstanding_balance']);
    if (status == 'completed') return 'completed';
    if (outstanding <= 0 && (status == 'active' || status == 'overdue')) {
      return 'completed';
    }
    if (status == 'active') return 'ongoing';
    return status;
  }

  (String, Color, Color) _statusStyle(String key) {
    switch (key) {
      case 'completed':
        return ('Completed', AppColors.success, AppColors.successLight);
      case 'ongoing':
        return ('Ongoing', AppColors.warning, AppColors.warningLight);
      case 'overdue':
        return ('Overdue', AppColors.error, AppColors.errorLight);
      default:
        final label = key.isEmpty
            ? '—'
            : key.replaceAll('_', ' ').split(' ').map((w) {
                if (w.isEmpty) return w;
                return '${w[0].toUpperCase()}${w.substring(1)}';
              }).join(' ');
        return (label, AppColors.info, AppColors.infoLight);
    }
  }

  (String, Color, Color) _scheduleStatusStyle(String status) {
    switch (status) {
      case 'paid':
        return ('Paid', AppColors.success, AppColors.successLight);
      case 'overdue':
        return ('Overdue', AppColors.error, AppColors.errorLight);
      case 'partial':
        return ('Partial', AppColors.info, AppColors.infoLight);
      default:
        return ('Pending', AppColors.warning, AppColors.warningLight);
    }
  }
}

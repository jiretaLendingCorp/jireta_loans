// lib/presentation/features/head_manager/reports/widgets/loan_records_preview.dart
//
// Dashboard-style na loan records view — layout na kapareho ng mockup/Loan
// Report page:
//   1) filter card sa itaas (Status / Lender dropdowns na may label + search,
//      at opsyonal na date-range pill at Export button),
//   2) apat na summary card sa isang row (icon, label, halaga, paliwanag),
//   3) "Loan Records" card na may premium table at pagination footer
//      ("Showing 1–10 of 124 records" + numbered pages).
//
// Ginagamit ito sa DALAWANG lugar:
//   * /hm/reports page mismo — ang Loan Report section sa itaas, at
//   * ang preview modal pagkatapos ng Generate (Interest Report).
//
// Ang Interest Report ay may 7 fields kada loan (loanNumber, lenderName,
// principalAmount, interestRate, interestAmount, totalPayable,
// outstandingBalance, status) pero Amount, Interest at Total lang ang
// ipinapakita at ine-export — tugma ang nasa screen sa na-download na file.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../shared/utils/report_exporter.dart';
import '../../../../shared/widgets/app_chip.dart';
import '../../../../shared/widgets/filter_dropdown.dart';
import '../../../../shared/widgets/layout/responsive_content.dart';

/// Template key ng Interest Report — ito lang ang report na Amount, Interest at
/// Total ang columns sa preview at sa export.
const String kInterestReportKey = 'interest_report';

/// Isang column ng preview: [label] ang header at [keys] ang mga sinusubukang
/// key sa bawat row na ibinabalik ng `reports-generate` (unang may laman ang
/// gagamitin). [money] = ₱ ang ipinapakitang format ng cell.
class _LoanRecordCol {
  final String label;
  final List<String> keys;
  final IconData icon;
  final bool money;
  final bool total;
  final int flex;

  /// `keys` na walang laman = pinagsamang cell (loan number + lender name) na
  /// tulad ng "Lender & Loan" column ng Loan Records page.
  const _LoanRecordCol(this.label, this.keys, this.icon,
      {this.money = false, this.total = false, this.flex = 2});
}

/// Columns NA I-E-EXPORT: Loan Record, Loan Name, Amount, Interest, Total.
const List<_LoanRecordCol> _exportCols = [
  _LoanRecordCol('Loan Record', _loanKeys, Icons.tag_outlined),
  _LoanRecordCol('Loan Name', _lenderKeys, Icons.person_outline),
  _LoanRecordCol(
      'Amount', ['principalAmount', 'amount'], Icons.payments_outlined,
      money: true),
  _LoanRecordCol(
      'Interest', ['interestAmount', 'interest_amount'], Icons.percent_rounded,
      money: true),
  _LoanRecordCol('Total', ['totalPayable', 'total_payable'],
      Icons.account_balance_wallet_outlined,
      money: true, total: true),
];

/// Columns NA NAKA-TABLE sa screen — kapareho ng Loan Records page: ang loan
/// number (bold) at lender name (grey) ay nasa ISANG column, tapos ang mga
/// halaga. Status column ang idinadagdag kapag may status data ang rows.
const List<_LoanRecordCol> _tableCols = [
  _LoanRecordCol('Lender & Loan', [], Icons.tag_outlined, flex: 3),
  _LoanRecordCol(
      'Amount', ['principalAmount', 'amount'], Icons.payments_outlined,
      money: true),
  _LoanRecordCol(
      'Interest', ['interestAmount', 'interest_amount'], Icons.percent_rounded,
      money: true),
  _LoanRecordCol('Total', ['totalPayable', 'total_payable'],
      Icons.account_balance_wallet_outlined,
      money: true, total: true),
];

/// Halaga ng isang column mula sa row — unang key na may totoong laman
/// (nilalaktawan ang wala at ang `N/A` ng server).
dynamic reportColumnValue(Map<String, dynamic> r, List<String> keys) {
  for (final k in keys) {
    final v = r[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isEmpty || s == 'N/A') continue;
    return v;
  }
  return null;
}

/// Isinasalin ang bawat loan row sa columns na ipinapakita at ine-export —
/// pareho ang laman ng table sa screen at ng PDF/Excel.
List<Map<String, dynamic>> interestPreviewRows(
  List<Map<String, dynamic>> rows,
) =>
    [
      for (final r in rows)
        {
          for (final c in _exportCols) c.label: reportColumnValue(r, c.keys),
        },
    ];

/// Kabuuang halaga ng report para sa napiling panahon (Beginning Date –
/// Ending Date):
///   * [collected]     — Halagang nakolekta na (Total − Outstanding).
///   * [outstanding]   — Halagang hindi pa nakokolekta.
///   * [income]        — Kabuuang kita (interest).
///   * [total]         — Kabuuang halaga (Total Payable) sa panahon.
///   * [principal]     — Kabuuang principal ng mga loan.
class LoanReportTotals {
  final double principal;
  final double collected;
  final double outstanding;
  final double income;
  final double total;

  const LoanReportTotals({
    this.principal = 0,
    this.collected = 0,
    this.outstanding = 0,
    this.income = 0,
    this.total = 0,
  });
}

/// Numero lang ang binibilang — ang `N/A` / blangko ay binabalewala sa halip
/// na gawing zero ang buong column.
double? _reportNum(dynamic v) {
  if (v is num) return v.toDouble();
  final s = (v ?? '').toString().replaceAll(',', '').trim();
  return num.tryParse(s)?.toDouble();
}

/// Kinukuha ang mga kabuuan ng report mula sa hilaw na `interest_report` rows
/// (kailangan ang `outstandingBalance` para sa nakolekta / hindi pa
/// nakokolekta). Ang row na walang outstanding data ay hindi idinadagdag sa
/// `collected` — hindi ito itinuturing na fully paid.
LoanReportTotals loanReportTotals(List<Map<String, dynamic>> rows) {
  var principal = 0.0;
  var collected = 0.0;
  var outstanding = 0.0;
  var income = 0.0;
  var total = 0.0;

  for (final r in rows) {
    final p = _reportNum(reportColumnValue(r, ['principalAmount', 'amount']));
    final i = _reportNum(
        reportColumnValue(r, ['interestAmount', 'interest_amount']));
    final t = _reportNum(reportColumnValue(r, ['totalPayable', 'total_payable']));
    final o = _reportNum(
        reportColumnValue(r, ['outstandingBalance', 'outstanding_balance']));

    if (p != null) principal += p;
    if (i != null) income += i;
    if (t != null) total += t;
    if (o != null) outstanding += o;
    if (t != null && o != null) {
      final paid = t - o;
      if (paid > 0) collected += paid;
    }
  }

  return LoanReportTotals(
    principal: principal,
    collected: collected,
    outstanding: outstanding,
    income: income,
    total: total,
  );
}

/// Rows na ine-export — may huling `TOTAL` row na nagbubuod sa Amount,
/// Interest at Total ng buong naka-filter na report (hindi lang sa kasalukuyang
/// page), tulad ng kabuuang hinihingi sa dulo ng report.
List<Map<String, dynamic>> interestPreviewRowsWithTotals(
  List<Map<String, dynamic>> rows,
) {
  final out = interestPreviewRows(rows);
  if (out.isEmpty) return out;
  final totals = loanReportTotals(rows);
  out.add({
    // Nasa Loan Name column ang TOTAL para malapit sa mga halaga.
    'Loan Record': reportBlank,
    'Loan Name': 'TOTAL',
    'Amount': totals.principal,
    'Interest': totals.income,
    'Total': totals.total,
  });
  return out;
}

/// Puting panel na may manipis na border — iisang estilo para sa lahat ng
/// section ng Reports page (filter bar, summary cards, table, history).
Widget reportPanel({
  required Widget child,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
}) =>
    Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );

/// Value ng "All …" na item ng mga dropdown.
const String _allFilter = 'all';

/// Keys na sinusubukan sa bawat row — sumasalo sa mga lumang report na iba ang
/// pangalan ng field.
const List<String> _lenderKeys = ['lenderName', 'lender_name', 'lender'];
const List<String> _statusKeys = ['status'];
const List<String> _loanKeys = ['loanNumber', 'loan_number'];

/// Label sa ibabaw ng isang filter field — tulad ng "Report Type" / "Lender"
/// na label sa mockup. Pampubliko ito para magamit ng page kapag nagbibigay
/// ito ng sariling filter (hal. "Report Type").
Widget labeledFilterField(String label, Widget field) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        field,
      ],
    );

class LoanRecordsPreview extends StatefulWidget {
  /// Buong rows mula sa `reports-generate` — kailangan dito ang loanNumber,
  /// lenderName at status para sa search/filter dropdowns.
  final List<Map<String, dynamic>> rows;

  /// Tinatawag kada may pagbabago sa filter. Ang ibinibigay na rows ay
  /// Amount / Interest / Total lang (kapareho ng nasa table) at may huling
  /// `TOTAL` row — ito ang ipinapasa sa Excel/PDF export para tugma ang file
  /// sa nakikita sa screen.
  final ValueChanged<List<Map<String, dynamic>>>? onFilteredChanged;

  /// Tinatawag kasabay ng [onFilteredChanged] — ang kabuuan ng panahon
  /// (Beginning/Ending Date, nakolekta, hindi pa nakokolekta, kita) na
  /// nakalagay sa PDF/Excel export.
  final ValueChanged<ReportSummary>? onSummaryChanged;

  /// Napiling panahon — kapag may [onPickDateRange], may date pill sa may
  /// kanan ng search (tulad ng "Sep 01, 2025 – Sep 30, 2025" sa mockup).
  final DateTimeRange? dateRange;
  final VoidCallback? onPickDateRange;

  /// Export button (PDF/Excel) na katabi ng date pill — nasa page ito, wala
  /// sa preview modal dahil may sariling Excel/PDF buttons ang modal.
  final Widget? exportActions;

  /// Mga filter na nauuna sa Lender dropdown (hal. "Report Type" sa Reports
  /// page). Kapag walang ibinigay, Status dropdown ang unang lumalabas —
  /// iyon ang gamit ng preview modal.
  final List<Widget> leadingFilters;

  /// Padding ng buong content. Sa Reports page, zero — ang page na ang may
  /// sariling margin.
  final EdgeInsetsGeometry contentPadding;

  /// Kapag false, walang Status / Lender dropdown (search at date pa lang).
  final bool showDropdownFilters;

  const LoanRecordsPreview({
    super.key,
    required this.rows,
    this.onFilteredChanged,
    this.onSummaryChanged,
    this.dateRange,
    this.onPickDateRange,
    this.exportActions,
    this.leadingFilters = const [],
    this.contentPadding = const EdgeInsets.fromLTRB(20, 18, 20, 18),
    this.showDropdownFilters = true,
  });

  @override
  State<LoanRecordsPreview> createState() => _LoanRecordsPreviewState();
}

class _LoanRecordsPreviewState extends State<LoanRecordsPreview> {
  /// 10 rows kada page — kapareho ng "Showing 1–10 of 124 records" footer.
  static const int _pageSize = 10;

  final TextEditingController _searchCtrl = TextEditingController();
  int _page = 1;
  String _status = _allFilter;
  String _lender = _allFilter;

  @override
  void initState() {
    super.initState();
    // Ipaalam agad sa screen ang buong set — ito ang unang ine-export kung
    // walang babaguhin sa filter.
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyParent());
  }

  @override
  void didUpdateWidget(covariant LoanRecordsPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Bagong date range / bagong report → bagong rows. Bumalik sa page 1 at
    // i-refresh ang ine-export para tugma ito sa bagong report (hindi ang
    // lumang rows ng dating panahon).
    if (!identical(oldWidget.rows, widget.rows)) {
      _page = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _notifyParent());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────── Filtering ───────────────────────────

  /// Lender name / status / loan number ng isang row — blangko kapag wala o
  /// `N/A` ang value (galing sa server) para hindi ito maging dropdown option.
  static String _text(Map<String, dynamic> r, List<String> keys) =>
      reportColumnValue(r, keys)?.toString().trim() ?? '';

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return widget.rows.where((r) {
      if (_status != _allFilter &&
          _text(r, _statusKeys).toLowerCase() != _status) {
        return false;
      }
      if (_lender != _allFilter && _text(r, _lenderKeys) != _lender) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay = '${_text(r, _loanKeys)} ${_text(r, _lenderKeys)}';
        if (!hay.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList();
  }

  List<String> _options(List<String> keys) {
    final set = <String>{for (final r in widget.rows) _text(r, keys)}
      ..remove('');
    final list = set.toList()..sort();
    return list;
  }

  void _notifyParent() {
    final filtered = _filtered;
    widget.onFilteredChanged
        ?.call(interestPreviewRowsWithTotals(filtered));

    final totals = loanReportTotals(filtered);
    final range = widget.dateRange;
    widget.onSummaryChanged?.call(ReportSummary(
      beginningDate:
          range == null ? '—' : DateFormat('MMM dd, yyyy').format(range.start),
      endingDate:
          range == null ? '—' : DateFormat('MMM dd, yyyy').format(range.end),
      collected: totals.collected,
      outstanding: totals.outstanding,
      income: totals.income,
    ));
  }

  /// Kapag nagbago ang filter, bumalik sa unang page para hindi makita ang
  /// blangkong page (hal. naging 2 rows na lang mula sa 30).
  void _onFilterChanged(VoidCallback change) {
    setState(() {
      change();
      _page = 1;
    });
    _notifyParent();
  }

  // ─────────────────────────── UI ───────────────────────────

  double _sum(List<Map<String, dynamic>> rows, String label) =>
      rows.fold<double>(0, (total, r) => total + (_reportNum(r[label]) ?? 0));

  static String _money(double v) => NumberFormat('#,##0.00', 'en_PH').format(v);

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final rows = interestPreviewRows(filtered);
    final reportTotals = loanReportTotals(filtered);
    final total = rows.length;
    final totalPages = total == 0 ? 1 : (total / _pageSize).ceil();
    final page = _page > totalPages ? totalPages : _page;
    final items =
        filtered.skip((page - 1) * _pageSize).take(_pageSize).toList();
    // Status pill column lang kapag may status data ang rows (kapareho ng
    // Loan Records page); kung wala, hindi na ito pinipilit ipakita.
    final hasStatus = filtered.any((r) => _text(r, _statusKeys).isNotEmpty);

    return SingleChildScrollView(
      padding: widget.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          reportPanel(
            padding: const EdgeInsets.all(16),
            child: _buildFilterCard(),
          ),
          const SizedBox(height: 16),
          // LOAN SUMMARY sa TAAS — ang mga summary card.
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text('Loan Summary',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
          ),
          _buildSummaryCards(reportTotals, filtered.length),
          const SizedBox(height: 28),
          // LOAN RECORDS sa GITNA — ang table ng mga loan.
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text('Loan Records',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
          ),
          _buildTableCard(items, page, totalPages, total,
              hasStatus: hasStatus, totalsRow: rows),
          const SizedBox(height: 20),
          // Beginning Date / Ending Date / mga halaga — nasa PINAKABABA.
          _buildPeriodSummary(reportTotals),
        ],
      ),
    );
  }

  // ── 1) Filter card (Status / Lender + search) ──

  Widget _buildFilterCard() {
    final statuses = _options(_statusKeys);
    final lenders = _options(_lenderKeys);

    final filters = [
      // May sariling filter ang page ("Report Type"); sa preview modal, Status
      // dropdown ang unang nasa row.
      if (widget.showDropdownFilters) ...[
      if (widget.leadingFilters.isEmpty)
        labeledFilterField(
          'Status',
          FilterDropdown<String>(
            value: _status,
            items: [
              const DropdownMenuItem(
                  value: _allFilter, child: Text('All Status')),
              for (final s in statuses)
                DropdownMenuItem(value: s.toLowerCase(), child: Text(s)),
            ],
            onChanged: (v) => _onFilterChanged(() => _status = v ?? _allFilter),
          ),
        )
      else
        ...widget.leadingFilters,
      labeledFilterField(
        'Lender',
        FilterDropdown<String>(
          value: _lender,
          items: [
            const DropdownMenuItem(
                value: _allFilter, child: Text('All Lenders')),
            for (final l in lenders) DropdownMenuItem(value: l, child: Text(l)),
          ],
          onChanged: (v) => _onFilterChanged(() => _lender = v ?? _allFilter),
        ),
      ),
      ],
    ];

    final search = SizedBox(
      height: 48,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (_) => _onFilterChanged(() {}),
        decoration: InputDecoration(
          hintText: 'Search by client name or loan no.',
          hintStyle:
              const TextStyle(color: AppColors.textTertiary, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded,
              size: 19, color: AppColors.textTertiary),
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        // Opsyonal na date pill at Export button — nasa dulo ng filter row,
        // tulad ng nasa mockup na header.
        final extras = <Widget>[
          if (widget.dateRange != null) _datePill(widget.dateRange!),
          if (widget.exportActions != null) widget.exportActions!,
        ];

        // Malapad: mga dropdown sa kaliwa, search sa gitna, at ang date
        // pill/Export sa kanan (naka-align sa ibaba ng mga dropdown, hindi
        // sa label). Masikip: nakasalansan lahat.
        if (c.maxWidth >= 980) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final f in filters) ...[
                f,
                const SizedBox(width: 14),
              ],
              Expanded(child: search),
              for (final e in extras) ...[
                const SizedBox(width: 12),
                e,
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [...filters, ...extras],
            ),
          ],
        );
      },
    );
  }

  /// Napiling panahon — tulad ng "Sep 01, 2025 – Sep 30, 2025" pill sa mockup.
  Widget _datePill(DateTimeRange range) => InkWell(
        onTap: widget.onPickDateRange,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.date_range_rounded,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${DateFormat('MMM dd, yyyy').format(range.start)} – ${DateFormat('MMM dd, yyyy').format(range.end)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      );

  // ── 2) Summary cards ──

  /// Mga summary card ng report — Loans, Total Amount, Total Income, Total
  /// Payable, Amount Collected, at Not Yet Collected. Apat kada
  /// row sa malapad na viewport, dalawa kapag masikip.
  Widget _buildSummaryCards(LoanReportTotals totals, int loanCount) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth >= 700 ? 4 : (c.maxWidth >= 420 ? 2 : 1);
        final w = (c.maxWidth - (perRow - 1) * 12) / perRow;
        final cards = [
          _PreviewStatCard(
              label: 'Loans',
              value: '$loanCount',
              caption: 'Loans in period',
              icon: Icons.description_outlined,
              color: AppColors.deepNavy),
          _PreviewStatCard(
              label: 'Total Amount',
              value: '₱${_money(totals.principal)}',
              caption: 'Principal amount',
              icon: Icons.payments_outlined,
              color: AppColors.info),
          _PreviewStatCard(
              label: 'Total Income',
              value: '₱${_money(totals.income)}',
              caption: 'Total income',
              icon: Icons.percent_rounded,
              color: AppColors.goldDark),
          _PreviewStatCard(
              label: 'Total Payable',
              value: '₱${_money(totals.total)}',
              caption: 'Total amount for the period',
              icon: Icons.account_balance_wallet_outlined,
              color: AppColors.riderGreen),
          _PreviewStatCard(
              label: 'Amount Collected',
              value: '₱${_money(totals.collected)}',
              caption: 'Amount collected',
              icon: Icons.savings_outlined,
              color: AppColors.success),
          _PreviewStatCard(
              label: 'Not Yet Collected',
              value: '₱${_money(totals.outstanding)}',
              caption: 'Amount not yet collected',
              icon: Icons.schedule_rounded,
              color: AppColors.warning),
        ];
        // Bawat row ay centered — kapag hindi puno ang huling row (hal.
        // Amount Collected at Not Yet Collected), nasa GITNA ito.
        final rows = <Widget>[];
        for (var start = 0; start < cards.length; start += perRow) {
          final end = math.min(start + perRow, cards.length);
          rows.add(Padding(
            padding: EdgeInsets.only(bottom: end < cards.length ? 12 : 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = start; i < end; i++) ...[
                  if (i > start) const SizedBox(width: 12),
                  SizedBox(width: w, child: cards[i]),
                ],
              ],
            ),
          ));
        }
        return Column(children: rows);
      },
    );
  }

  /// "Loan Summary" — Beginning Date, Ending Date, at ang mga kabuuan ng
  /// napiling panahon, na may TOTAL row sa dulo (halimbawa ng format ng
  /// report). Naka-horizontal scroll sa makitid na viewport para hindi
  /// mag-overflow ang mga column.
  Widget _buildPeriodSummary(LoanReportTotals totals) {
    final range = widget.dateRange;
    final beginning = range == null
        ? '—'
        : DateFormat('MMM dd, yyyy').format(range.start);
    final ending =
        range == null ? '—' : DateFormat('MMM dd, yyyy').format(range.end);
    final headline = <String>[
      'Beginning Date',
      'Ending Date',
      'Amount Collected',
      'Amount to Collect',
      'Total Income',
      'Total Amount',
    ];
    final values = <String>[
      beginning,
      ending,
      '₱${_money(totals.collected)}',
      '₱${_money(totals.outstanding)}',
      '₱${_money(totals.income)}',
      '₱${_money(totals.total)}',
    ];
    final totalCells = <String>[
      '',
      'TOTAL',
      '₱${_money(totals.collected)}',
      '₱${_money(totals.outstanding)}',
      '₱${_money(totals.income)}',
      '₱${_money(totals.total)}',
    ];

    return reportPanel(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child:          // Punuin ang buong lapad ng card (walang blangkong space sa
          // kanan); sa makitid na viewport lang ito nagiging horizontal
          // scroll.
          ResponsiveTableScroll(
            minWidth: 900,
            child: Column(
              children: [
                _periodRow(headline, header: true),
                _periodRow(values),
                _periodRow(totalCells, total: true),
              ],
            ),
          ),
      ),
    );
  }

  /// Isang row ng Loan Summary — header, value, o TOTAL row.
  Widget _periodRow(List<String> cells,
      {bool header = false, bool total = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: header
            ? const Color(0xFFF8F9FB)
            : (total ? AppColors.surfaceVariant : Colors.white),
        border: header
            ? const Border(bottom: BorderSide(color: AppColors.border))
            : (total
                ? const Border(top: BorderSide(color: AppColors.border))
                : const Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
      ),
      child: Row(
        children: [
          for (final cell in cells)
            Expanded(
              child: Text(
                header ? cell.toUpperCase() : cell,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: header ? 10.5 : 12.5,
                  fontWeight: total
                      ? FontWeight.w800
                      : (header ? FontWeight.w700 : FontWeight.w600),
                  letterSpacing: header ? 0.4 : 0,
                  color: header
                      ? AppColors.textSecondary
                      : (total
                          ? AppColors.textPrimary
                          : AppColors.textPrimary),
                  fontFeatures: total || !header
                      ? const [FontFeature.tabularFigures()]
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 3) Table card (title + table + footer) ──

  Widget _buildTableCard(
    List<Map<String, dynamic>> items,
    int page,
    int totalPages,
    int total, {
    required bool hasStatus,
    required List<Map<String, dynamic>> totalsRow,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              child: Center(
                child: Text(
                    widget.rows.isEmpty
                        ? 'No loans in the selected period.'
                        : 'No loans match the current filters.',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
            )
          else ...[
            // Sariling card na ng table card ang border — walang doble.
            ResponsiveListCard(
              // `minTableWidth: 0` = LAGING table ang Loan Records (tabular,
              // tulad ng hiling) — hindi na ito nagbabalik sa stacked cards sa
              // makitid na viewport; naka-horizontal scroll na lang kapag
              // masikip, pero table pa rin ang ayos.
              minTableWidth: 0,
              variant: ResponsiveListVariant.premium,
              radius: 0,
              outerBorder: const Border(),
              outerShadow: const [],
              rowPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              headerPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              columns: [
                for (final c in _tableCols)
                  ResponsiveCol(c.label, icon: c.icon, flex: c.flex),
                if (hasStatus)
                  const ResponsiveCol('Status',
                      icon: Icons.flag_outlined, flex: 2),
              ],
              rows: [
                for (final r in items)
                  ResponsiveRow(
                    cells: [
                      for (final c in _tableCols) _previewCell(r, c),
                      if (hasStatus) _statusCell(r),
                    ],
                  ),
              ],
            ),
            // TOTAL row — kabuuan ng buong naka-filter na report (hindi lang
            // ng kasalukuyang page), nakahanay sa mga column ng table.
            _buildTableTotal(totalsRow, hasStatus: hasStatus),
            _buildPagination(page, totalPages, total),
          ],
        ],
      ),
    );
  }

  /// Isang cell ng table — kapareho ng ayos ng Loan Records page:
  /// loan number (bold) + lender name (grey) sa unang column, ₱ na bold ang
  /// mga halaga, at text ang iba.
  Widget _previewCell(Map<String, dynamic> r, _LoanRecordCol c) {
    // Pinagsamang "Lender & Loan" cell — walang keys ang column na ito.
    if (c.keys.isEmpty) {
      final loanNo = reportColumnValue(r, _loanKeys)?.toString().trim() ?? '';
      final name = reportColumnValue(r, _lenderKeys)?.toString().trim() ?? '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(loanNo.isEmpty ? 'N/A' : loanNo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepNavy)),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        ],
      );
    }

    final v = reportColumnValue(r, c.keys);

    if (!c.money) {
      final text = v?.toString().trim() ?? '';
      if (text.isEmpty) return _muted('N/A');
      return Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary));
    }

    // Ang halagang ₱ lang ang naka-format; ang `N/A` (walang datos) ay
    // ipinapakita pa rin bilang text.
    final n = _reportNum(v);
    return Text(
      n == null ? reportCellValue(v) : '₱${_money(n)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: c.total ? FontWeight.w800 : FontWeight.w700,
        color: c.total ? AppColors.deepNavy : AppColors.textPrimary,
        // Tabular figures: pantay-pantay ang lapad ng digits kaya naka-kolumna
        // (nakatabular) ang mga halaga sa ilalim ng kanilang header.
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  /// Huling row ng table: "TOTAL" + kabuuan ng Amount / Interest / Total.
  Widget _buildTableTotal(List<Map<String, dynamic>> rows,
      {required bool hasStatus}) {
    final cells = <Widget>[
      const Text('TOTAL',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.deepNavy)),
      for (final c in _tableCols.skip(1))
        Text(
          '₱${_money(_sum(rows, c.label))}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: c.total ? AppColors.deepNavy : AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      if (hasStatus) const SizedBox.shrink(),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: i < _tableCols.length ? _tableCols[i].flex : 2,
              child: cells[i],
            ),
        ],
      ),
    );
  }

  Widget _muted(String text) => Text(text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, color: AppColors.textTertiary));

  /// Status — colored dot + label, kapareho ng Status column ng Loan Records
  /// page (at ng mockup).
  Widget _statusCell(Map<String, dynamic> r) {
    final status = _text(r, _statusKeys);
    if (status.isEmpty) return _muted('—');
    final color = statusColor(status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(statusLabel(status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
        ),
      ],
    );
  }

  /// Mga page number na ipapakita: unang page, huling page, at ang window ng
  /// limang pahina sa paligid ng kasalukuyan (`null` = "…").
  static List<int?> _pageWindow(int current, int totalPages) {
    if (totalPages <= 6) return [for (var i = 1; i <= totalPages; i++) i];
    final start = math.max(1, math.min(current - 2, totalPages - 4));
    final end = math.min(totalPages, start + 4);
    return [
      if (start > 1) 1,
      if (start > 2) null,
      for (var i = start; i <= end; i++) i,
      if (end < totalPages) null,
      if (end < totalPages) totalPages,
    ];
  }

  /// "Showing 1–10 of 124 records" sa kaliwa, numbered pages sa **KANAN** —
  /// nasa loob ng table card, tulad ng mockup.
  Widget _buildPagination(int page, int totalPages, int total) {
    final from = (page - 1) * _pageSize + 1;
    final rawTo = page * _pageSize;
    final to = rawTo > total ? total : rawTo;
    final window =
        totalPages > 1 ? _pageWindow(page, totalPages) : const <int?>[];

    final label = Text('Showing $from–$to of $total records',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 12, color: AppColors.textSecondary));

    // Naka-scroll pahalang kapag marami ang page number, `reverse: true` para
    // nakadikit sa KANAN ang content sa loob ng bounded na lapad nito.
    final pager = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PageButton(
            icon: Icons.chevron_left_rounded,
            onTap: page > 1 ? () => setState(() => _page = page - 1) : null,
          ),
          for (final p in window) ...[
            const SizedBox(width: 6),
            if (p == null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Text('…',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textTertiary)),
              )
            else
              _PageButton(
                label: '$p',
                active: p == page,
                onTap: p == page ? null : () => setState(() => _page = p),
              ),
          ],
          const SizedBox(width: 6),
          _PageButton(
            icon: Icons.chevron_right_rounded,
            onTap: page < totalPages
                ? () => setState(() => _page = page + 1)
                : null,
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        // Makitid (mobile/dialog): label sa taas, pager sa ibaba — parehong
        // NAKA-RIGHT.
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              label,
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: pager,
              ),
            ],
          );
        }
        // Desktop: NAKA-RIGHT ang buong footer — magkasama at dikit ang
        // "Showing …" text at ang pager. `Align` + `MainAxisSize.min` para
        // hindi lumawak (at kumalat) ang label box pauwi sa kanan.
        return Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              label,
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: pager,
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Summary card sa itaas ng preview — icon, label, halaga at maikling
/// paliwanag, tulad ng stat cards ng mockup.
class _PreviewStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;
  const _PreviewStatCard(
      {required this.label,
      required this.value,
      required this.caption,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) => reportPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Isang page button — numero (may [label]) o prev/next (may [icon]). Ang
/// aktibong page ay punong deepNavy na may puting text, tulad ng mockup.
class _PageButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool active;
  final VoidCallback? onTap;
  const _PageButton({this.label, this.icon, this.active = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? AppColors.deepNavy
              : (enabled ? Colors.white : AppColors.surfaceVariant),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: active ? AppColors.deepNavy : AppColors.border),
        ),
        child: label != null
            ? Text(label!,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : AppColors.textPrimary))
            : Icon(icon,
                size: 18,
                color: active
                    ? Colors.white
                    : (enabled
                        ? AppColors.textPrimary
                        : AppColors.textTertiary)),
      ),
    );
  }
}

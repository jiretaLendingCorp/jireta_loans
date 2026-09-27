// lib/presentation/features/head_manager/loans/widgets/loan_reapply_picker.dart
//
// 00176: "Kailan pwedeng mag-apply ulit ang lender?" chooser para sa reject
// flow ng HM at Employee. Ang staff ang nagde-decide ng re-apply window —
// dati kasi hard-coded na 1 buwan sa `loans-apply`.
//
// Isang beses lang ito naka-set (sa oras ng rejection) at ipinapadala sa
// `loans-manage?fn=reject` bilang `reapply_allowed_at` (ISO UTC).
//
// Ginagamit ito ng:
//   * ApproveRejectModal (HM + Employee loan application screens / modals)
//   * EmpLoanDetailsModal (reject dialog na may free-text reason)
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/filter_pill_tab.dart';

/// Mga preset na pagpipilian ng staff. Ang [custom] ay bubukas ng calendar
/// (date picker) para sa eksaktong petsa.
enum LoanReapplyPreset { now, oneMonth, threeMonths, sixMonths, custom }

/// Picks kung kailan pwedeng mag-apply ulit ang lender pagkatapos ng rejection.
///
/// WALANG default na selection: ang staff ang kailangang pumili (preset o
/// calendar) — hindi ito basta naka-1 month. Ang parent ang humahawak ng
/// napiling petsa sa pamamagitan ng [onChanged] (`null` = wala pang napili).
class LoanReapplyPicker extends StatefulWidget {
  /// Tinatawag kada magbago ang napiling petsa (`null` kapag wala pa) — ito ang
  /// ipapasa sa `rejectLoan(..., reapplyAllowedAt: ...)`.
  final ValueChanged<DateTime?> onChanged;

  const LoanReapplyPicker({super.key, required this.onChanged});

  @override
  State<LoanReapplyPicker> createState() => _LoanReapplyPickerState();
}

class _LoanReapplyPickerState extends State<LoanReapplyPicker> {
  /// `null` = wala pang pinipili ang staff (dapat explicit na pagpili).
  LoanReapplyPreset? _preset;
  DateTime? _customDate;

  /// Pinakamaagang pwedeng piliin sa calendar: ngayon (pwede agad).
  static final DateTime _today = DateUtils.dateOnly(DateTime.now());

  DateTime? _resolved() {
    final now = DateTime.now();
    switch (_preset) {
      case null:
        return null;
      case LoanReapplyPreset.now:
        return now;
      case LoanReapplyPreset.oneMonth:
        return _addMonths(now, 1);
      case LoanReapplyPreset.threeMonths:
        return _addMonths(now, 3);
      case LoanReapplyPreset.sixMonths:
        return _addMonths(now, 6);
      case LoanReapplyPreset.custom:
        // Custom na petsa: simula ng araw na iyon (00:00) — bago pa man
        // matapos ang araw na iyon, nakapag-apply na ang lender.
        return _customDate ?? now;
    }
  }

  /// Idinadagdag ang buwan nang hindi lumalampas sa dulo ng buwan
  /// (hal. Jan 31 + 1 month = Feb 28/29), kapareho ng server-side
  /// `setMonth(+1)` na logic.
  static DateTime _addMonths(DateTime base, int months) {
    final t = base.month + months;
    final year = base.year + (t - 1) ~/ 12;
    final month = ((t - 1) % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = base.day > lastDay ? lastDay : base.day;
    return DateTime(year, month, day, base.hour, base.minute, base.second);
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? _addMonths(DateTime.now(), 1),
      firstDate: _today,
      // Kapareho ng server-side guard rail (max 2 taon).
      lastDate: DateTime(_today.year + 2, _today.month, _today.day),
      helpText: 'Select re-apply date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customDate = DateUtils.dateOnly(picked);
      _preset = LoanReapplyPreset.custom;
    });
    widget.onChanged(_resolved());
  }

  void _select(LoanReapplyPreset preset) {
    if (preset == LoanReapplyPreset.custom) {
      _pickCustomDate();
      return;
    }
    setState(() => _preset = preset);
    widget.onChanged(_resolved());
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolved();
    final isNow = _preset == LoanReapplyPreset.now;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'When can the lender apply again?',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterPillTab(
              def: const FilterTabDef(
                  'now', 'Immediately', Icons.bolt_rounded),
              active: _preset == LoanReapplyPreset.now,
              onTap: () => _select(LoanReapplyPreset.now),
            ),
            FilterPillTab(
              def: const FilterTabDef(
                  '1m', '1 month', Icons.calendar_month_rounded),
              active: _preset == LoanReapplyPreset.oneMonth,
              onTap: () => _select(LoanReapplyPreset.oneMonth),
            ),
            FilterPillTab(
              def: const FilterTabDef(
                  '3m', '3 months', Icons.date_range_rounded),
              active: _preset == LoanReapplyPreset.threeMonths,
              onTap: () => _select(LoanReapplyPreset.threeMonths),
            ),
            FilterPillTab(
              def: const FilterTabDef(
                  '6m', '6 months', Icons.event_available_rounded),
              active: _preset == LoanReapplyPreset.sixMonths,
              onTap: () => _select(LoanReapplyPreset.sixMonths),
            ),
            FilterPillTab(
              def: const FilterTabDef(
                  'custom', 'Other date', Icons.edit_calendar_rounded),
              active: _preset == LoanReapplyPreset.custom,
              onTap: () => _select(LoanReapplyPreset.custom),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Walang default: hangga't hindi pumili ang staff, paalala ito — hindi
        // ito basta-basta nag-a-apply ng 1 month sa likod ng user.
        Text(
          resolved == null
              ? 'No default — choose when the lender can apply again.'
              : isNow
                  ? 'The lender can apply again right away.'
                  : 'The lender can apply again on ${AppFormatters.date(resolved)}.',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: resolved == null
                  ? AppColors.warning
                  : AppColors.textSecondary),
        ),
      ],
    );
  }
}

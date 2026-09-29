// lib/presentation/features/head_manager/loans/widgets/loan_reapply_picker.dart
//
// 00176: "Kailan pwedeng mag-apply ulit ang lender?" chooser para sa reject
// flow ng HM at Employee. Ang staff ang nagde-decide ng re-apply window —
// dati kasi hard-coded na 1 buwan sa `loans-apply`.
//
// 00179: idinagdag ang PERMANENT REJECT — kapag ito ang pinili, hindi na
// makakapag-apply muli ang lender (`loans.permanently_rejected = true`).
//
// Isang beses lang ito naka-set (sa oras ng rejection) at ipinapadala sa
// `loans-manage?fn=reject` bilang `reapply_allowed_at` (ISO UTC) o
// `permanent: true`.
//
// Ginagamit ito ng:
//   * ApproveRejectModal (HM + Employee loan application screens / modals)
//   * EmpLoanDetailsModal (reject dialog na may free-text reason)
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/formatters.dart';

/// Mga pagpipilian ng staff. Ang [custom] ay bubukas ng calendar (date picker)
/// para sa eksaktong petsa; ang [permanent] ay hindi na papayagang mag-apply
/// muli ang lender.
enum LoanReapplyPreset {
  now,
  oneMonth,
  threeMonths,
  sixMonths,
  custom,
  permanent,
}

/// Ang napili ng staff sa reject modal (`null` = wala pa).
class LoanReapplyChoice {
  /// Permanenteng rejection — hindi na makakapag-apply muli ang lender.
  const LoanReapplyChoice.permanent()
      : permanent = true,
        allowedAt = null;

  /// Pwedeng mag-apply muli ang lender sa [allowedAt].
  const LoanReapplyChoice.at(DateTime this.allowedAt) : permanent = false;

  final bool permanent;

  /// Kailan pwedeng mag-apply muli (`null` kapag permanent).
  final DateTime? allowedAt;
}

/// Picks kung kailan pwedeng mag-apply ulit ang lender pagkatapos ng rejection.
///
/// WALANG default na selection: ang staff ang kailangang pumili (preset,
/// calendar, o permanent) — hindi ito basta naka-1 month. Ang parent ang
/// humahawak ng napili sa pamamagitan ng [onChanged] (`null` = wala pa).
class LoanReapplyPicker extends StatefulWidget {
  /// Tinatawag kada magbago ang pinili (`null` kapag wala pa) — ito ang
  /// ipapasa sa `rejectLoan(..., reapplyAllowedAt:, permanent:)`.
  final ValueChanged<LoanReapplyChoice?> onChanged;

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

  DateTime? get _resolvedDate {
    final preset = _preset;
    final now = DateTime.now();
    switch (preset) {
      case null:
      case LoanReapplyPreset.permanent:
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
        return _customDate ?? _addMonths(now, 1);
    }
  }

  LoanReapplyChoice? get _choice {
    final preset = _preset;
    if (preset == null) return null;
    if (preset == LoanReapplyPreset.permanent) {
      return const LoanReapplyChoice.permanent();
    }
    return LoanReapplyChoice.at(_resolvedDate!);
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
    widget.onChanged(_choice);
  }

  void _select(LoanReapplyPreset preset) {
    if (preset == LoanReapplyPreset.custom) {
      _pickCustomDate();
      return;
    }
    setState(() => _preset = preset);
    widget.onChanged(_choice);
  }

  String? _hintFor(LoanReapplyPreset preset) {
    switch (preset) {
      case LoanReapplyPreset.now:
        return 'Can apply again right away';
      case LoanReapplyPreset.oneMonth:
        return 'From ${AppFormatters.date(_addMonths(DateTime.now(), 1))}';
      case LoanReapplyPreset.threeMonths:
        return 'From ${AppFormatters.date(_addMonths(DateTime.now(), 3))}';
      case LoanReapplyPreset.sixMonths:
        return 'From ${AppFormatters.date(_addMonths(DateTime.now(), 6))}';
      case LoanReapplyPreset.custom:
        return _customDate == null
            ? 'Pick an exact date'
            : 'From ${AppFormatters.date(_customDate!)}';
      case LoanReapplyPreset.permanent:
        return 'Can never apply again — permanent block';
    }
  }

  @override
  Widget build(BuildContext context) {
    final choice = _choice;
    final isPermanent = _preset == LoanReapplyPreset.permanent;
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
        // Naka-listahan nang patayo (isa kada linya) para malinaw ang
        // napili at madaling tapikin — dati ay magkakatabing pills na
        // mahirap basahin sa maliit na modal.
        _ReapplyOption(
          icon: Icons.bolt_rounded,
          label: 'Immediately',
          hint: _hintFor(LoanReapplyPreset.now),
          active: _preset == LoanReapplyPreset.now,
          onTap: () => _select(LoanReapplyPreset.now),
        ),
        const SizedBox(height: 8),
        _ReapplyOption(
          icon: Icons.calendar_month_rounded,
          label: '1 month',
          hint: _hintFor(LoanReapplyPreset.oneMonth),
          active: _preset == LoanReapplyPreset.oneMonth,
          onTap: () => _select(LoanReapplyPreset.oneMonth),
        ),
        const SizedBox(height: 8),
        _ReapplyOption(
          icon: Icons.date_range_rounded,
          label: '3 months',
          hint: _hintFor(LoanReapplyPreset.threeMonths),
          active: _preset == LoanReapplyPreset.threeMonths,
          onTap: () => _select(LoanReapplyPreset.threeMonths),
        ),
        const SizedBox(height: 8),
        _ReapplyOption(
          icon: Icons.event_available_rounded,
          label: '6 months',
          hint: _hintFor(LoanReapplyPreset.sixMonths),
          active: _preset == LoanReapplyPreset.sixMonths,
          onTap: () => _select(LoanReapplyPreset.sixMonths),
        ),
        const SizedBox(height: 8),
        _ReapplyOption(
          icon: Icons.edit_calendar_rounded,
          label: 'Other date',
          hint: _hintFor(LoanReapplyPreset.custom),
          active: _preset == LoanReapplyPreset.custom,
          onTap: () => _select(LoanReapplyPreset.custom),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1),
        ),
        // Destructive na pagpipilian — hiwalay sa ibaba at may pulang
        // kulay para hindi ito mapindot nang hindi sinasadya.
        _ReapplyOption(
          icon: Icons.block_rounded,
          label: 'Permanent reject',
          hint: _hintFor(LoanReapplyPreset.permanent),
          active: isPermanent,
          danger: true,
          onTap: () => _select(LoanReapplyPreset.permanent),
        ),
        const SizedBox(height: 12),
        // Buod ng pinili — dating hubad na text, ngayon ay naka-callout para
        // kitang-kita bago pindutin ang Reject. Walang default: hangga't hindi
        // pumili ang staff, paalala ito.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: choice == null
                ? AppColors.warning.withValues(alpha: 0.10)
                : isPermanent
                    ? AppColors.error.withValues(alpha: 0.08)
                    : AppColors.successLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: choice == null
                  ? AppColors.warning.withValues(alpha: 0.35)
                  : isPermanent
                      ? AppColors.error.withValues(alpha: 0.35)
                      : AppColors.success.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                choice == null
                    ? Icons.info_outline_rounded
                    : isPermanent
                        ? Icons.block_rounded
                        : Icons.check_circle_outline_rounded,
                size: 16,
                color: choice == null
                    ? AppColors.warning
                    : isPermanent
                        ? AppColors.error
                        : AppColors.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  choice == null
                      ? 'No default — choose when the lender can apply again.'
                      : isPermanent
                          ? 'Permanent: the lender can no longer apply for a '
                              'new loan.'
                          : _preset == LoanReapplyPreset.now
                              ? 'The lender can apply again right away.'
                              : 'The lender can apply again on '
                                  '${AppFormatters.date(choice.allowedAt!)}.',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: choice == null
                          ? AppColors.warning
                          : isPermanent
                              ? AppColors.error
                              : AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Isang naka-card na pagpipilian: icon sa loob ng bilog, label + hint, at
/// check kapag napili. [danger] = destructive (Permanent reject).
class _ReapplyOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? hint;
  final bool active;
  final bool danger;
  final VoidCallback onTap;

  const _ReapplyOption({
    required this.icon,
    required this.label,
    required this.hint,
    required this.active,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = danger ? AppColors.error : AppColors.deepNavy;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: danger ? 0.06 : 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? accent : AppColors.border,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: (active ? accent : AppColors.textTertiary)
                    .withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 16,
                color: active ? accent : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        color: active ? accent : AppColors.textPrimary),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      hint!,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (active)
              Icon(danger ? Icons.block_rounded : Icons.check_circle_rounded,
                  size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

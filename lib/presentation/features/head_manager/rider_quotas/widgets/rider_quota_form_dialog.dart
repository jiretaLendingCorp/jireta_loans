// lib/presentation/features/head_manager/rider_quotas/widgets/rider_quota_form_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/input_formatters.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../data/models/rider_quota_model.dart';
import '../providers/hm_rider_quotas_provider.dart';

/// Assign (existing == null) o edit (existing != null) na rider quota.
///
/// Ang validation dito ay pre-check lang para mabilis ang feedback; ang
/// server (collections-manage) pa rin ang humuhusga sa overlap, period span
/// at sa "tapos nang period" na edit.
class RiderQuotaFormDialog extends ConsumerStatefulWidget {
  final RiderQuota? existing;

  const RiderQuotaFormDialog({super.key, this.existing});

  @override
  ConsumerState<RiderQuotaFormDialog> createState() =>
      _RiderQuotaFormDialogState();
}

class _RiderQuotaFormDialogState extends ConsumerState<RiderQuotaFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String? _riderId;
  String _period = RiderQuotaPeriod.daily;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _localError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final q = widget.existing;
    if (q != null) {
      _riderId = q.riderId;
      _period = RiderQuotaPeriod.all.contains(q.period)
          ? q.period
          : RiderQuotaPeriod.daily;
      _startDate = q.startDate;
      _endDate = q.endDate;
      // Currency format agad (hal. `₱` 100,000.00) — pareho ng itsura ng
      // halaga sa buong app at ng habang nagta-type.
      _amountCtrl.text = ThousandsSeparatorInputFormatter.format(
        q.targetAmount,
        decimalDigits: 2,
      );
      _notesCtrl.text = q.notes ?? '';
    } else {
      final range = riderQuotaDefaultRange(_period, nowManila());
      _startDate = range.start;
      _endDate = range.end;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onPeriodChanged(String period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      final range = riderQuotaDefaultRange(period, nowManila());
      _startDate = range.start;
      _endDate = range.end;
    });
  }

  /// Ibalik sa default na window ng napiling period (hal. buong week/month).
  void _useDefaultRange() {
    final range = riderQuotaDefaultRange(_period, nowManila());
    setState(() {
      _startDate = range.start;
      _endDate = range.end;
    });
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = (start ? _startDate : _endDate) ?? nowManila();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = picked;
        if (_endDate == null || _endDate!.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _localError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;
    final validation = validateRiderQuotaInput(
      period: _period,
      targetAmount: amount,
      startDate: _startDate,
      endDate: _endDate,
    );
    if (validation != null) {
      setState(() => _localError = validation);
      return;
    }
    if (!_isEdit && (_riderId == null || _riderId!.isEmpty)) {
      setState(() => _localError = 'Select a rider.');
      return;
    }

    final fmt = DateFormat('yyyy-MM-dd');
    final notifier = ref.read(hmRiderQuotasProvider.notifier);
    final notes = _notesCtrl.text.trim();

    final ok = _isEdit
        ? await notifier.updateQuota(
            quotaId: widget.existing!.quotaId,
            period: _period,
            targetAmount: amount,
            startDate: fmt.format(_startDate!),
            endDate: fmt.format(_endDate!),
            notes: notes.isEmpty ? null : notes,
          )
        : await notifier.createQuota(
            riderId: _riderId!,
            period: _period,
            targetAmount: amount,
            startDate: fmt.format(_startDate!),
            endDate: fmt.format(_endDate!),
            notes: notes.isEmpty ? null : notes,
          );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _localError = ref.read(hmRiderQuotasProvider).actionError ??
            'Could not save the quota. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hmRiderQuotasProvider);
    final saving = state.isSaving;
    final ridersAsync = ref.watch(riderQuotaRiderOptionsProvider);

    return Dialog(
      backgroundColor: context.cSurface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, saving),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 6),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_isEdit) ...[
                        _sectionLabel(context, 'Rider'),
                        const SizedBox(height: 8),
                        ridersAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                          error: (e, _) => Text(
                            'Could not load riders. $e',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.error),
                          ),
                          data: (riders) => DropdownButtonFormField<String>(
                            initialValue: _riderId,
                            isExpanded: true,
                            hint: const Text('Select a rider'),
                            items: riders
                                .map((r) => DropdownMenuItem(
                                      value: r.riderId,
                                      // Pangalan lang ang ipinapakita —
                                      // walang numero, para malinis at madaling
                                      // i-scan ang listahan ng rider.
                                      child: Text(
                                        r.riderName.isEmpty
                                            ? 'Unnamed rider'
                                            : r.riderName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                            onChanged: saving
                                ? null
                                : (v) => setState(() => _riderId = v),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Select a rider'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      _sectionLabel(context, 'Quota period'),
                      const SizedBox(height: 8),
                      _PeriodSelector(
                        value: _period,
                        enabled: !saving,
                        onChanged: _onPeriodChanged,
                      ),
                      const SizedBox(height: 18),
                      _sectionLabel(context, 'Target amount'),
                      const SizedBox(height: 8),
                      // Live currency preview: habang nagta-type, nakikita
                      // agad ang halaga sa tamang peso format (hal.
                      // ₱100,000.00), kaya hindi na pagtatakhan kung tama ba
                      // ang mga zero.
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _amountCtrl,
                        builder: (context, value, _) {
                          final parsed = double.tryParse(
                              value.text.replaceAll(',', '').trim());
                          final preview = (parsed != null && parsed > 0)
                              ? AppFormatters.currency(parsed)
                              : null;
                          return TextFormField(
                            controller: _amountCtrl,
                            enabled: !saving,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: const [
                              ThousandsSeparatorInputFormatter(decimalDigits: 2)
                            ],
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: context.cTextPrimary,
                            ),
                            decoration: InputDecoration(
                              // Sariling prefix widget — hindi dumidikit ang
                              // ₱ sa unang digit at kapantay ang laki ng
                              // 20px na halaga.
                              prefixIcon: Padding(
                                padding:
                                    const EdgeInsets.only(left: 14, right: 8),
                                child: Text(
                                  '₱',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: context.cTextSecondary,
                                  ),
                                ),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                  minWidth: 0, minHeight: 0),
                              hintText: '0.00',
                              helperText: preview == null
                                  ? 'Amount the rider must collect within this window.'
                                  : 'Rider must collect $preview',
                              helperMaxLines: 2,
                            ),
                            validator: (v) {
                              final parsed = double.tryParse(
                                  (v ?? '').replaceAll(',', '').trim());
                              if (parsed == null || parsed <= 0) {
                                return 'Enter a positive target amount';
                              }
                              return null;
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      _sectionLabel(context, 'Quota window'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _DateTile(
                              label: 'Start date',
                              value: _startDate == null
                                  ? 'Select date'
                                  : DateFormat('MMM d, y').format(_startDate!),
                              placeholder: _startDate == null,
                              onTap:
                                  saving ? null : () => _pickDate(start: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DateTile(
                              label: 'End date',
                              value: _endDate == null
                                  ? 'Select date'
                                  : DateFormat('MMM d, y').format(_endDate!),
                              placeholder: _endDate == null,
                              onTap:
                                  saving ? null : () => _pickDate(start: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildRangeSummary(context),
                      const SizedBox(height: 18),
                      _sectionLabel(context, 'Notes (optional)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _notesCtrl,
                        enabled: !saving,
                        maxLength: 500,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Optional context for this quota…',
                        ),
                      ),
                      if (_localError != null) ...[
                        const SizedBox(height: 4),
                        _ErrorBanner(message: _localError!),
                      ],
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ),
            _buildFooter(context, saving),
          ],
        ),
      ),
    );
  }

  /// Header na naka-brand (deep navy + gold) — rider name ang subtitle para
  /// agad malinaw kung kaninong quota ang binabago. Fixed ito habang
  /// nagsa-scroll ang body.
  Widget _buildHeader(BuildContext context, bool saving) {
    final riderName = widget.existing?.riderName.trim() ?? '';
    final subtitle = _isEdit
        ? (riderName.isEmpty ? 'Rider quota' : riderName)
        : 'Set a collection target and window for a rider.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 10, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.deepNavy, Color(0xFF16293D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
            ),
            child:
                const Icon(Icons.flag_rounded, color: AppColors.gold, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEdit ? 'Edit rider quota' : 'Assign rider quota',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: saving ? null : () => Navigator.of(context).pop(false),
            icon: Icon(Icons.close_rounded,
                size: 20, color: Colors.white.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  /// Maliit na label sa itaas ng bawat field group — mas madaling i-scan
  /// kaysa sa floating labels ng lahat ng input.
  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: context.cTextSecondary,
      ),
    );
  }

  /// Buod ng napiling window (haba + petsa) at shortcut pabalik sa default.
  Widget _buildRangeSummary(BuildContext context) {
    final start = _startDate;
    final end = _endDate;
    final dateFmt = DateFormat('MMM d, y');
    final days = (start != null && end != null)
        ? end.difference(start).inDays + 1
        : null;
    final summary = (start == null || end == null)
        ? 'Select the first and last day of the quota.'
        : '${dateFmt.format(start)} — ${dateFmt.format(end)}'
            '${days != null ? '  ·  $days day${days == 1 ? '' : 's'}' : ''}';

    return Row(
      children: [
        Icon(Icons.event_available_outlined,
            size: 14, color: context.cTextTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: context.cTextSecondary),
          ),
        ),
        TextButton(
          onPressed: _useDefaultRange,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Use default', style: TextStyle(fontSize: 11.5)),
        ),
      ],
    );
  }

  /// Fixed footer — hindi gumagalaw habang nagsa-scroll ang body, kaya laging
  /// maabot ang Save.
  Widget _buildFooter(BuildContext context, bool saving) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
      decoration: BoxDecoration(
        color: context.cSurface,
        border: Border(top: BorderSide(color: context.cDivider)),
      ),
      // Wrap — sa makitid na mobile dialog ay bumaba sa ilalim ang Save sa
      // halip na umapaw.
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: saving ? null : () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: context.cTextSecondary,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: saving ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.deepNavy,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded, size: 16),
            label: Text(
              _isEdit ? 'Save changes' : 'Assign quota',
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tatlong pill para sa Daily / Weekly / Monthly — isang tap lang, hindi na
/// kailangang mag-dropdown.
class _PeriodSelector extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _PeriodSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  static const _icons = <String, IconData>{
    RiderQuotaPeriod.daily: Icons.today_rounded,
    RiderQuotaPeriod.weekly: Icons.date_range_rounded,
    RiderQuotaPeriod.monthly: Icons.calendar_month_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final period in RiderQuotaPeriod.all) ...[
          if (period != RiderQuotaPeriod.all.first) const SizedBox(width: 8),
          Expanded(child: _pill(context, period)),
        ],
      ],
    );
  }

  Widget _pill(BuildContext context, String period) {
    final selected = period == value;
    return InkWell(
      onTap: enabled ? () => onChanged(period) : null,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.deepNavy : context.cSurfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.deepNavy : context.cBorder,
          ),
        ),
        child: Column(
          children: [
            Icon(
              _icons[period] ?? Icons.flag_outlined,
              size: 18,
              color: selected ? AppColors.gold : context.cTextSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              RiderQuotaPeriod.label(period),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? Colors.white : context.cTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Date picker tile — label sa itaas, petsa sa ibaba, kalendaryo sa kanan.
class _DateTile extends StatelessWidget {
  final String label;
  final String value;
  final bool placeholder;
  final VoidCallback? onTap;

  const _DateTile({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.cSurfaceVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.cBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style:
                        TextStyle(fontSize: 10.5, color: context.cTextTertiary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: placeholder
                          ? context.cTextTertiary
                          : context.cTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.calendar_today_outlined,
                size: 16, color: context.cTextTertiary),
          ],
        ),
      ),
    );
  }
}

/// Error mula sa server o sa local validation — kitang-kita bago ang footer.
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

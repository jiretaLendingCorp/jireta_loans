// lib/presentation/shared/widgets/security/mpin_dialog.dart
//
// Ang MPIN dialog na ginagamit ng rider at lender para:
//   * mag-set ng 4-digit MPIN (setup mode), at
//   * i-verify ang MPIN bago ang anumang submission (verify mode).
//
// Auto-submit kapag napuno na ang 4 na kahon (gaya ng OTP screen) para isang
// hakbang lang ang flow. Kapag setup mode na may `requireCurrent`, hihingin
// muna ang lumang MPIN bago papayagang magpalit — iisang dialog lang ito.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/security/mpin_service.dart';
import '../../../../core/theme/app_colors.dart';

enum MpinDialogMode {
  /// I-verify ang naka-set na MPIN.
  verify,

  /// Gumawa (o magpalit) ng MPIN.
  setup,
}

/// Hihingin ang MPIN at magbabalik ng `true` kapag na-verify.
///
/// `false` kapag kinansela, mali ang MPIN nang sunod-sunod (naka-lock), o
/// wala pang naka-set na MPIN.
Future<bool> showMpinVerifyDialog(
  BuildContext context, {
  String? reason,
  MpinService? mpin,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MpinDialog(
      mode: MpinDialogMode.verify,
      reason: reason,
      mpin: mpin,
    ),
  );
  return result == true;
}

/// Hihingin ang bagong MPIN at magbabalik ng `true` kapag na-save.
///
/// Kapag `requireCurrent` at may naka-set nang MPIN, hihingin muna ang luma
/// bago payagang magpalit.
Future<bool> showMpinSetupDialog(
  BuildContext context, {
  bool requireCurrent = false,
  String? reason,
  MpinService? mpin,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MpinDialog(
      mode: MpinDialogMode.setup,
      requireCurrent: requireCurrent,
      reason: reason,
      mpin: mpin,
    ),
  );
  return result == true;
}

class MpinDialog extends StatefulWidget {
  const MpinDialog({
    super.key,
    required this.mode,
    this.requireCurrent = false,
    this.reason,
    this.mpin,
  });

  final MpinDialogMode mode;

  /// Kapag true sa setup mode, hihingin muna ang kasalukuyang MPIN.
  final bool requireCurrent;

  /// Extra na paliwanag na ipinapakita sa ilalim ng title.
  final String? reason;

  /// Opsyonal na service (pang-test / shared instance). Kapag null, gumagawa
  /// ito ng sarili nitong [MpinService].
  final MpinService? mpin;

  @override
  State<MpinDialog> createState() => _MpinDialogState();
}

/// Ang kasalukuyang hakbang ng dialog.
enum _Step { current, create, confirm }

class _MpinDialogState extends State<MpinDialog> {
  late final MpinService _service = widget.mpin ?? MpinService();
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  _Step _step = _Step.current;
  String? _error;
  String _firstEntry = '';
  bool _busy = false;
  bool _verifiedCurrent = false;
  Timer? _lockTimer;
  int _lockSecondsLeft = 0;

  bool get _isSetup => widget.mode == MpinDialogMode.setup;

  @override
  void initState() {
    super.initState();
    _controllers =
        List.generate(MpinService.pinLength, (_) => TextEditingController());
    _focusNodes = List.generate(MpinService.pinLength, (_) => FocusNode());
    _step = _isSetup
        ? (widget.requireCurrent ? _Step.current : _Step.create)
        : _Step.current;
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirst());
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _focusFirst() {
    if (!mounted) return;
    _focusNodes.first.requestFocus();
  }

  void _clearBoxes() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusFirst();
  }

  void _startLockCountdown(Duration remaining) {
    _lockTimer?.cancel();
    setState(() => _lockSecondsLeft = remaining.inSeconds.clamp(1, 600));
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_lockSecondsLeft <= 1) {
        t.cancel();
        setState(() {
          _lockSecondsLeft = 0;
          _error = null;
        });
        _clearBoxes();
      } else {
        setState(() => _lockSecondsLeft--);
      }
    });
  }

  String get _pin => _controllers.map((c) => c.text).join();

  void _onChanged(int index, String value) {
    if (_error != null) setState(() => _error = null);
    if (_lockSecondsLeft > 0) return;

    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      for (int i = 0;
          i < digits.length && (index + i) < MpinService.pinLength;
          i++) {
        _controllers[index + i].text = digits[i];
      }
      final next = (index + digits.length).clamp(0, MpinService.pinLength - 1);
      _focusNodes[next].requestFocus();
    } else if (value.isNotEmpty) {
      if (index < MpinService.pinLength - 1) {
        _focusNodes[index + 1].requestFocus();
      }
    } else if (index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    // Isang digit lang ang laman ng bawat kahon, kaya kapag 4 na ang haba ng
    // pinagsamang `_pin` ay puno na lahat. (HUWAG gamitin ang
    // `!pin.contains('')` — laging `true` ang `contains('')` sa Dart kaya
    // hindi ito kailanman mag-a-auto-submit.)
    if (_pin.length == MpinService.pinLength) {
      _handleComplete();
    }
  }

  Future<void> _handleComplete() async {
    if (_busy || _lockSecondsLeft > 0) return;
    final pin = _pin;
    if (!MpinService.isValidFormat(pin)) return;
    FocusManager.instance.primaryFocus?.unfocus();

    switch (_step) {
      case _Step.current:
        await _verifyCurrent(pin);
        break;
      case _Step.create:
        setState(() {
          _firstEntry = pin;
          _step = _Step.confirm;
          _error = null;
        });
        _clearBoxes();
        break;
      case _Step.confirm:
        await _confirmNew(pin);
        break;
    }
  }

  /// Verify mode, o ang unang hakbang ng setup-with-current.
  Future<void> _verifyCurrent(String pin) async {
    setState(() => _busy = true);
    final result = await _service.verify(pin);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result.status) {
      case MpinStatus.success:
        if (_isSetup) {
          setState(() {
            _verifiedCurrent = true;
            _step = _Step.create;
            _error = null;
          });
          _clearBoxes();
        } else {
          Navigator.of(context).pop(true);
        }
        break;
      case MpinStatus.wrong:
        final left = result.attemptsLeft ?? 0;
        setState(() {
          _error = left > 0
              ? 'Incorrect MPIN. $left attempt${left == 1 ? '' : 's'} left.'
              : 'Incorrect MPIN.';
        });
        _clearBoxes();
        break;
      case MpinStatus.locked:
        setState(() => _error = 'Too many attempts.');
        _startLockCountdown(
            result.lockRemaining ?? MpinService.lockoutDuration);
        _clearBoxes();
        break;
      case MpinStatus.notSet:
        // Nawala/mabura ang MPIN habang bukas ang dialog — huwag i-claim na
        // na-verify, isara na lang para makapag-set muli ang caller.
        Navigator.of(context).pop(false);
        break;
    }
  }

  Future<void> _confirmNew(String pin) async {
    if (pin != _firstEntry) {
      setState(() {
        _error = 'MPIN did not match. Please enter it again.';
        _firstEntry = '';
        _step = _Step.create;
      });
      _clearBoxes();
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.setMpin(pin);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on MpinChangeLimitException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Naabot na ang limitasyon: '
            '${MpinService.maxChangesPerWindow} palit lang ng MPIN sa loob ng '
            '15 araw. Puwede kang magpalit muli sa ${_formatRetry(e.retryAfter)}.';
      });
      _clearBoxes();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Hindi na-save ang MPIN. Subukan ulit.';
      });
      _clearBoxes();
    }
  }

  /// "3 days and 4 hours" / "5 hours" / "12 minutes" — para sa limitasyon.
  String _formatRetry(Duration d) {
    if (d.inDays >= 1) {
      final days = d.inDays;
      final hours = d.inHours % 24;
      final dayLabel = '$days day${days == 1 ? '' : 's'}';
      return hours > 0
          ? '$dayLabel and $hours hour${hours == 1 ? '' : 's'}'
          : dayLabel;
    }
    if (d.inHours >= 1) {
      return '${d.inHours} hour${d.inHours == 1 ? '' : 's'}';
    }
    final mins = d.inMinutes < 1 ? 1 : d.inMinutes;
    return '$mins minute${mins == 1 ? '' : 's'}';
  }

  // ── Copy ────────────────────────────────────────────────────────────────

  String get _title {
    if (_step == _Step.create) {
      return _isSetup && _verifiedCurrent ? 'New MPIN' : 'Set MPIN';
    }
    if (_step == _Step.confirm) return 'Confirm MPIN';
    return _isSetup ? 'Current MPIN' : 'Enter MPIN';
  }

  String get _subtitle {
    switch (_step) {
      case _Step.create:
        // May `reason` sa "required" flow ng SubmissionGuard (walang device
        // password) — iyon ang ipinapakita para malinaw kung bakit kailangan.
        return widget.reason ??
            'Gumawa ng 4-digit MPIN. Ito ang gagamitin para kumpirmahin ang '
                'mga submission kapag walang password o biometrics ang phone mo.';
      case _Step.confirm:
        return 'I-type muli ang MPIN para makumpirma.';
      case _Step.current:
        return widget.reason ??
            'I-type ang iyong 4-digit MPIN para magpatuloy.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _error != null;
    // Ang system back button ay nag-pop ng `null` → itinuturing na `false`
    // (kinansela), kaya hindi na kailangan ng PopScope dito.
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.deepNavy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.lock_outline_rounded,
                        size: 20, color: AppColors.deepNavy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.cTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: context.cTextSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  MpinService.pinLength,
                  (i) => _MpinBox(
                    controller: _controllers[i],
                    focusNode: _focusNodes[i],
                    hasError: hasError,
                    enabled: !_busy && _lockSecondsLeft == 0,
                    onChanged: (v) => _onChanged(i, v),
                  ),
                ),
              ),
              if (_error != null && _lockSecondsLeft == 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 16, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_lockSecondsLeft > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined,
                        size: 16, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Naka-lock muna. Subukan ulit sa ${_lockSecondsLeft}s.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: context.cTextSecondary,
                    ),
                    child: const Text('Cancel'),
                  ),
                  if (_busy) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Isang kahon ng MPIN — sadyang hindi pinapakita ang digit (obscured) dahil
/// security credential ito na madalas i-type sa harap ng ibang tao.
class _MpinBox extends StatefulWidget {
  const _MpinBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.hasError,
    required this.enabled,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool hasError;
  final bool enabled;

  @override
  State<_MpinBox> createState() => _MpinBoxState();
}

class _MpinBoxState extends State<_MpinBox> {
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() => _hasFocus = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filled = widget.controller.text.isNotEmpty;
    Color borderColor;
    Color fillColor;
    double borderWidth;
    if (widget.hasError) {
      borderColor = AppColors.error;
      fillColor = AppColors.errorLight;
      borderWidth = 1.6;
    } else if (_hasFocus) {
      borderColor = AppColors.deepNavy;
      fillColor = context.cSurface;
      borderWidth = 1.8;
    } else if (filled) {
      borderColor = AppColors.deepNavy.withValues(alpha: 0.22);
      fillColor = context.cSurface;
      borderWidth = 1.4;
    } else {
      borderColor = context.cBorder;
      fillColor = context.cSurfaceVariant;
      borderWidth = 1.2;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        width: 50,
        height: 56,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        alignment: Alignment.center,
        child: TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          obscureText: true,
          obscuringCharacter: '\u2022',
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: context.cTextPrimary,
          ),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

// lib/presentation/shared/widgets/security/mpin_keypad.dart
//
// Ang MPIN input na ginagamit ng login (rider / lender): 4 na tuldok na
// napupuno habang nag-ta-type at numeric keypad sa ibaba na may nakabox na
// numero — 1 2 3 / 4 5 6 / 7 8 9 / ⌫ 0.
//
// Sadyang HINDI ginagamit ang system keyboard: iwas sa leak ng digits sa
// keyboard suggestions, at hindi na tumatakip ang keyboard sa MPIN boxes.
//
// Hinihiwalay ang tuldok ([MpinDots]) at ang keypad ([MpinKeypadField]) para
// maiayos ang mga ito nang magkatabi ng numero (tingnan ang MPIN setup screen).
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// "+63 917 123 4567" — ang BUONG numero (hindi naka-dot) na ipinapakita sa
/// itaas ng MPIN boxes, para malinaw kung aling account ang binubuksan nito.
///
/// Ginagamit ang +63 (Pilipinas) na format sa halip na `09...`, kaya pareho
/// ito sa itinatawag/itinatawag-tawag na pambansang format.
String formatMpinPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  // 09XXXXXXXXX → 9XXXXXXXXX; +63 9XXXXXXXXX → 9XXXXXXXXX
  final String? local;
  if (digits.length == 11 && digits.startsWith('0')) {
    local = digits.substring(1);
  } else if (digits.length == 12 && digits.startsWith('63')) {
    local = digits.substring(2);
  } else {
    local = null;
  }
  if (local == null) return phone;
  return '+63 ${local.substring(0, 3)} ${local.substring(3, 6)} '
      '${local.substring(6)}';
}

/// Hawak ng controller ang naipasok na digit — para pareho ang nakikitang
/// tuldok ([MpinDots]) at keypad ([MpinKeypadField]) kahit magkahiwalay sila sa
/// layout, at para ma-clear ito mula sa labas (hal. pagkatapos ng maling MPIN
/// o kapag nag-lock).
class MpinPadController extends ChangeNotifier {
  final List<String> _digits = [];

  /// Ilang digit na ang naipasok.
  int get length => _digits.length;

  /// Ang buong naipasok (hal. `1234`).
  String get pin => _digits.join();

  void clear() {
    if (_digits.isEmpty) return;
    _digits.clear();
    notifyListeners();
  }

  /// Nagdaragdag ng digit — walang epekto kapag puno na ang [max].
  void push(String digit, {required int max}) {
    if (_digits.length >= max) return;
    _digits.add(digit);
    notifyListeners();
  }

  void backspace() {
    if (_digits.isEmpty) return;
    _digits.removeLast();
    notifyListeners();
  }
}

/// Ang 4 na tuldok na napupuno habang nag-ta-type.
///
/// Hiwalay na widget para mailagay sa tabi ng numero sa MPIN setup screen at
/// sa itaas ng keypad sa login page.
class MpinDots extends StatelessWidget {
  const MpinDots({
    super.key,
    required this.controller,
    this.length = 4,
    this.hasError = false,
    this.spacing = 9,
    this.size = 16,
  });

  final MpinPadController controller;

  /// Haba ng MPIN (4 ayon sa [MpinService.pinLength]).
  final int length;

  /// Nagpapapula sa mga tuldok kapag mali ang naipasok.
  final bool hasError;

  /// Pagitan ng mga tuldok (bawat gilid).
  final double spacing;

  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(length, (i) {
          final filled = i < controller.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.symmetric(horizontal: spacing),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasError
                  ? AppColors.error
                  : filled
                      ? AppColors.deepNavy
                      : Colors.transparent,
              border: Border.all(
                color: hasError
                    ? AppColors.error
                    : filled
                        ? AppColors.deepNavy
                        : AppColors.textTertiary.withValues(alpha: 0.55),
                width: 1.6,
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Ang numeric keypad (at, bilang default, ang mga tuldok sa itaas nito).
///
/// Tinatawag ang [onCompleted] kapag napuno na ang lahat ng [length] na digit.
/// Ang pag-clear pagkatapos ng maling try ay responsibilidad ng parent (gamit
/// ang [controller]).
class MpinKeypadField extends StatefulWidget {
  const MpinKeypadField({
    super.key,
    required this.onCompleted,
    this.controller,
    this.length = 4,
    this.enabled = true,
    this.hasError = false,
    this.showDots = true,
  });

  /// Tinatawag isang beses kapag puno na ang MPIN.
  final ValueChanged<String> onCompleted;

  /// Opsyonal — para ma-clear ang boxes mula sa parent.
  final MpinPadController? controller;

  /// Haba ng MPIN (4 ayon sa [MpinService.pinLength]).
  final int length;

  /// `false` habang nag-ve-verify o naka-lock.
  final bool enabled;

  /// Nagpapapula sa mga tuldok kapag mali ang naipasok.
  final bool hasError;

  /// `false` kapag ang mga tuldok ay ipinapakita sa ibang lugar (hal. katabi
  /// ng numero) at hindi na kailangan dito sa ibabaw ng keypad.
  final bool showDots;

  @override
  State<MpinKeypadField> createState() => _MpinKeypadFieldState();
}

class _MpinKeypadFieldState extends State<MpinKeypadField> {
  late MpinPadController _pad;

  /// True kapag tayo ang gumawa ng controller — tayo rin ang magdi-dispose.
  late bool _ownsPad;

  @override
  void initState() {
    super.initState();
    _attachPad(widget.controller);
    _pad.addListener(_onPadChanged);
  }

  void _attachPad(MpinPadController? external) {
    _ownsPad = external == null;
    _pad = external ?? MpinPadController();
  }

  void _onPadChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant MpinKeypadField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _pad.removeListener(_onPadChanged);
      if (_ownsPad) _pad.dispose();
      _attachPad(widget.controller);
      _pad.addListener(_onPadChanged);
    }
  }

  @override
  void dispose() {
    _pad.removeListener(_onPadChanged);
    if (_ownsPad) _pad.dispose();
    super.dispose();
  }

  void _press(String digit) {
    if (!widget.enabled || _pad.length >= widget.length) return;
    _pad.push(digit, max: widget.length);
    if (_pad.length == widget.length) {
      final pin = _pad.pin;
      // Hayaan munang ma-render ang huling tuldok bago i-submit — kung hindi,
      // parang hindi tumugma ang ika-4 na pindot.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCompleted(pin);
      });
    }
  }

  void _backspace() {
    if (!widget.enabled) return;
    _pad.backspace();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showDots) ...[
          MpinDots(
            controller: _pad,
            length: widget.length,
            hasError: widget.hasError,
          ),
          const SizedBox(height: 26),
        ],
        // ── Numeric keypad ──
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
                [null, '0', '__back__'],
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final key in row)
                        _KeypadKey(
                          label: key,
                          enabled: widget.enabled,
                          onTap: key == null
                              ? null
                              : key == '__back__'
                                  ? _backspace
                                  : () => _press(key),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Isang boxed na keypad button (o backspace).
class _KeypadKey extends StatelessWidget {
  const _KeypadKey({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  /// `null` = blangkong espasyo, `'__back__'` = backspace.
  final String? label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (label == null) {
      return const SizedBox(width: 74, height: 58);
    }
    final isBack = label == '__back__';
    final isEnabled = enabled && onTap != null;

    return SizedBox(
      width: 74,
      height: 58,
      child: Material(
        color: isBack
            ? Colors.transparent
            : isEnabled
                ? Colors.white
                : const Color(0xFFF0F0F3),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: isEnabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isBack ? Colors.transparent : const Color(0xFFE3E5EB),
              ),
            ),
            child: Center(
              child: isBack
                  ? Icon(
                      Icons.backspace_outlined,
                      size: 21,
                      color: isEnabled
                          ? AppColors.deepNavy
                          : AppColors.textTertiary.withValues(alpha: 0.5),
                    )
                  : Text(
                      label!,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: isEnabled
                            ? AppColors.deepNavy
                            : AppColors.textTertiary.withValues(alpha: 0.5),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

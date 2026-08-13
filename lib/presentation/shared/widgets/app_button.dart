// lib/presentation/shared/widgets/app_button.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

enum AppButtonVariant { primary, secondary, danger, ghost, gold, outlined }

class AppButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onTap;
  final AppButtonVariant variant;
  final bool isLoading;
  final bool isExpanded;
  final bool outlined;
  final bool isDanger;
  final bool compact;
  final IconData? icon;
  final double? height;
  final double? fontSize;
  final Color? color;
  final Color? backgroundColor;
  final Color? outlineColor;
  final Color? textColor;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.onTap,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.isExpanded = false,
    this.outlined = false,
    this.isDanger = false,
    this.compact = false,
    this.icon,
    this.height,
    this.fontSize,
    this.color,
    this.backgroundColor,
    this.outlineColor,
    this.textColor,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scale = Tween<double>(begin: 1, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _bgColor {
    final effectiveVariant =
        widget.isDanger ? AppButtonVariant.danger : widget.variant;
    if (widget.outlined || effectiveVariant == AppButtonVariant.outlined) {
      return Colors.transparent;
    }
    if (widget.backgroundColor != null) return widget.backgroundColor!;
    if (widget.color != null) return widget.color!;
    switch (effectiveVariant) {
      case AppButtonVariant.primary:
        return AppColors.deepNavy;
      case AppButtonVariant.secondary:
        return Colors.white;
      case AppButtonVariant.danger:
        return AppColors.error;
      case AppButtonVariant.ghost:
        return Colors.transparent;
      case AppButtonVariant.gold:
        return AppColors.gold;
      case AppButtonVariant.outlined:
        return Colors.transparent;
    }
  }

  Color get _fgColor {
    if (widget.textColor != null) return widget.textColor!;
    if (widget.outlined || widget.variant == AppButtonVariant.outlined) {
      return widget.outlineColor ?? widget.color ?? AppColors.deepNavy;
    }
    final effectiveVariant =
        widget.isDanger ? AppButtonVariant.danger : widget.variant;
    switch (effectiveVariant) {
      case AppButtonVariant.primary:
        return Colors.white;
      case AppButtonVariant.secondary:
        return AppColors.deepNavy;
      case AppButtonVariant.danger:
        return Colors.white;
      case AppButtonVariant.ghost:
        return AppColors.textSecondary;
      case AppButtonVariant.gold:
        return AppColors.textOnGold;
      case AppButtonVariant.outlined:
        return AppColors.deepNavy;
    }
  }

  Border? get _border {
    if (widget.outlined || widget.variant == AppButtonVariant.outlined) {
      return Border.all(
        color: widget.outlineColor ?? widget.color ?? AppColors.border,
        width: 1.5,
      );
    }
    if (widget.variant == AppButtonVariant.secondary) {
      return Border.all(color: AppColors.border, width: 1.5);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final child = AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(
        scale: _scale.value,
        child: child,
      ),
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) => _ctrl.reverse(),
        onTapCancel: () => _ctrl.reverse(),
        child: Container(
          height: widget.compact ? 34 : widget.height ?? 48,
          decoration: BoxDecoration(
            color: (widget.onPressed ?? widget.onTap) == null
                ? _bgColor.withValues(alpha: 0.5)
                : _bgColor,
            borderRadius: BorderRadius.circular(widget.compact ? 8 : 10),
            border: _border,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.isLoading ? null : widget.onPressed ?? widget.onTap,
              borderRadius: BorderRadius.circular(widget.compact ? 8 : 10),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? 12 : 20,
                    vertical: widget.compact ? 4 : 0),
                child: widget.isLoading
                    ? Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _fgColor,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisSize: widget.isExpanded
                            ? MainAxisSize.max
                            : MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon,
                                size: widget.compact ? 15 : 18,
                                color: _fgColor),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            widget.label,
                            style: TextStyle(
                              fontSize: widget.compact
                                  ? (widget.fontSize ?? 12.5)
                                  : widget.fontSize ?? 14,
                              fontWeight: FontWeight.w600,
                              color: _fgColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );

    return widget.isExpanded
        ? SizedBox(width: double.infinity, child: child)
        : child;
  }
}

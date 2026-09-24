// lib/presentation/shared/widgets/dialogs/confirmation_dialog.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../utils/error_suppression.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_toast.dart';

/// Lapad at radius ng confirmation dialog card. Nasa isang lugar lang para
/// pantay ang lahat ng variant (sync / async / danger).
const double _kDialogWidth = 420;
const double _kDialogRadius = 18;

/// Default na icon kapag walang ipinasang [icon] ang caller — warning kapag
/// destructive (pula) ang confirm, info kung hindi.
IconData _defaultConfirmIcon(Color color) => color == AppColors.error
    ? Icons.warning_amber_rounded
    : Icons.info_outline;

Future<bool?> showConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  Color confirmColor = AppColors.deepNavy,
  bool isDangerous = false,
  IconData? icon,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ConfirmationDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      confirmColor: isDangerous ? AppColors.error : confirmColor,
      icon: icon,
    ),
  );
}

class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String? confirmText;
  final String cancelLabel;
  final Color confirmColor;
  final Widget? extra;

  /// Optional na icon sa header — kapag wala, awtomatikong warning (pula ang
  /// confirm) o info. Hal. `Icons.verified_rounded` para sa "Verify All".
  final IconData? icon;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.confirmText,
    this.cancelLabel = 'Cancel',
    this.confirmColor = AppColors.deepNavy,
    this.extra,
    this.icon,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    Color confirmColor = AppColors.deepNavy,
    bool isDangerous = false,
    Widget? extra,
    IconData? icon,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConfirmationDialog(
        title: title,
        message: message,
        confirmLabel: isDangerous ? 'Confirm' : confirmLabel,
        cancelLabel: cancelLabel,
        confirmColor: isDangerous ? AppColors.error : confirmColor,
        extra: extra,
        icon: icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ConfirmDialogShell(
      title: title,
      message: message,
      icon: icon ?? _defaultConfirmIcon(confirmColor),
      accent: confirmColor,
      extra: extra,
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: cancelLabel,
            variant: AppButtonVariant.ghost,
            height: 42,
            fontSize: 13.5,
            textColor: context.cTextSecondary,
            onTap: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: confirmText ?? confirmLabel,
            color: confirmColor,
            height: 42,
            fontSize: 13.5,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}

/// Shows a confirmation dialog whose confirm button runs [onConfirm] and shows
/// a spinner while it is in flight. The dialog stays open during the operation
/// (so the loading state is visible on the Yes/Submit button), pops with `true`
/// when [onConfirm] completes successfully, and shows [errorMessage] (if any)
/// before re-enabling the button when it fails.
Future<bool?> showAsyncConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  required Future<String?> Function() onConfirm,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  Color confirmColor = AppColors.deepNavy,
  IconData? icon,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AsyncConfirmationDialog(
      title: title,
      message: message,
      onConfirm: onConfirm,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      confirmColor: confirmColor,
      icon: icon,
    ),
  );
}

class AsyncConfirmationDialog extends StatefulWidget {
  final String title;
  final String message;
  final Future<String?> Function() onConfirm;
  final String confirmLabel;
  final String cancelLabel;
  final Color confirmColor;
  final IconData? icon;

  const AsyncConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.onConfirm,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.confirmColor = AppColors.deepNavy,
    this.icon,
  });

  @override
  State<AsyncConfirmationDialog> createState() =>
      _AsyncConfirmationDialogState();
}

class _AsyncConfirmationDialogState extends State<AsyncConfirmationDialog> {
  bool _loading = false;
  String? _error;

  Future<void> _handleConfirm() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await widget.onConfirm();
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ConfirmDialogShell(
      title: widget.title,
      message: widget.message,
      icon: widget.icon ?? _defaultConfirmIcon(widget.confirmColor),
      accent: widget.confirmColor,
      // Error mula sa server: nakalagay sa ilalim ng message para makita agad
      // bago pa ang buttons.
      extra: _error == null
          ? null
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 16, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.error),
                  ),
                ),
              ],
            ),
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: widget.cancelLabel,
            variant: AppButtonVariant.ghost,
            height: 42,
            fontSize: 13.5,
            textColor: context.cTextSecondary,
            onTap: _loading ? null : () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: widget.confirmLabel,
            color: widget.confirmColor,
            height: 42,
            fontSize: 13.5,
            isLoading: _loading,
            onTap: _loading ? null : _handleConfirm,
          ),
        ],
      ),
    );
  }
}

/// Ang mismong card ng confirmation dialog: icon tile + title sa header, body
/// message, manipis na divider, tapos ang actions sa kanang ibaba.
///
/// Pinagsasaluhan ito ng sync ([ConfirmationDialog]) at async
/// ([AsyncConfirmationDialog]) na variant para pantay ang hitsura.
class _ConfirmDialogShell extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color accent;
  final Widget? extra;
  final Widget actions;

  const _ConfirmDialogShell({
    required this.title,
    required this.message,
    required this.icon,
    required this.accent,
    required this.actions,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      // antiAlias para hindi lumabas ang corners ng full-width na divider sa
      // ilalim ng body.
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kDialogRadius),
      ),
      child: SizedBox(
        width: _kDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon tile — tinted na background + border para malinaw
                      // itong elemento ng design, hindi washed-out na glyph.
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Icon(icon, color: accent, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Padding(
                          // Bahagyang pababa para pantay ang unang linya ng
                          // title sa icon tile.
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              letterSpacing: -0.2,
                              color: context.cTextPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: context.cTextSecondary,
                    ),
                  ),
                  if (extra != null) ...[
                    const SizedBox(height: 16),
                    extra!,
                  ],
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: context.cDivider),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showSuccessSnackBar(BuildContext context, String message) {
  AppToast.show(context, message, type: AppToastType.success);
}

void showErrorSnackBar(BuildContext context, String message) {
  if (shouldSuppressNetworkError(context, message)) return;
  AppToast.show(context, message, type: AppToastType.error);
}

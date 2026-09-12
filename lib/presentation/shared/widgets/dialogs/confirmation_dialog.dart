// lib/presentation/shared/widgets/dialogs/confirmation_dialog.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../utils/error_suppression.dart';
import '../../widgets/app_toast.dart';

Future<bool?> showConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  Color confirmColor = AppColors.deepNavy,
  bool isDangerous = false,
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

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.confirmText,
    this.cancelLabel = 'Cancel',
    this.confirmColor = AppColors.deepNavy,
    this.extra,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: confirmColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      confirmColor == AppColors.error
                          ? Icons.warning_outlined
                          : Icons.info_outline,
                      color: confirmColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.cTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  color: context.cTextSecondary,
                  height: 1.5,
                ),
              ),
              if (extra != null) ...[const SizedBox(height: 16), extra!],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(cancelLabel),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: confirmColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(confirmText ?? confirmLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
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

  const AsyncConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.onConfirm,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.confirmColor = AppColors.deepNavy,
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.confirmColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      widget.confirmColor == AppColors.error
                          ? Icons.warning_outlined
                          : Icons.info_outline,
                      color: widget.confirmColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.cTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                widget.message,
                style: TextStyle(
                  fontSize: 14,
                  color: context.cTextSecondary,
                  height: 1.5,
                ),
              ),
              if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(fontSize: 12.5, color: AppColors.error))],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text(widget.cancelLabel),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.confirmColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          widget.confirmColor.withValues(alpha: 0.6),
                    ),
                    onPressed: _loading ? null : _handleConfirm,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(widget.confirmLabel),
                  ),
                ],
              ),
            ],
          ),
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

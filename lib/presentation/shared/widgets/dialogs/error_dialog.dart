// lib/presentation/shared/widgets/dialogs/error_dialog.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../utils/error_suppression.dart';
import '../app_button.dart';

Future<void> showErrorDialog(
  BuildContext context, {
  required String message,
  String title = 'Error',
}) async {
  if (shouldSuppressNetworkError(context, message)) return;
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => _AppDialog(
      icon: Icons.error_outline,
      iconColor: AppColors.error,
      iconBg: AppColors.errorLight,
      title: title,
      message: message,
      actions: [
        AppButton(
          label: 'OK',
          onPressed: () => Navigator.of(context).pop(),
          variant: AppButtonVariant.danger,
        ),
      ],
    ),
  );
}

Future<void> showSuccessDialog(
  BuildContext context, {
  required String message,
  String title = 'Success',
  VoidCallback? onDone,
}) async {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AppDialog(
      icon: Icons.check_circle_outline,
      iconColor: AppColors.success,
      iconBg: AppColors.successLight,
      title: title,
      message: message,
      actions: [
        AppButton(
          label: 'Done',
          onPressed: () {
            Navigator.of(context).pop();
            onDone?.call();
          },
          variant: AppButtonVariant.primary,
        ),
      ],
    ),
  );
}

Future<void> showInfoDialog(
  BuildContext context, {
  required String message,
  String title = 'Information',
}) async {
  return showDialog(
    context: context,
    builder: (_) => _AppDialog(
      icon: Icons.info_outline,
      iconColor: AppColors.info,
      iconBg: AppColors.infoLight,
      title: title,
      message: message,
      actions: [
        AppButton(
          label: 'OK',
          onPressed: () => Navigator.of(context).pop(),
          variant: AppButtonVariant.primary,
        ),
      ],
    ),
  );
}

class ErrorDialog extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onDone;

  const ErrorDialog({
    super.key,
    this.title = 'Error',
    required this.message,
    this.onDone,
  });

  static Future<void> show(
    BuildContext context, {
    String title = 'Error',
    required String message,
    VoidCallback? onDone,
  }) {
    if (shouldSuppressNetworkError(context, message)) return Future.value();
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => ErrorDialog(
        title: title,
        message: message,
        onDone: onDone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AppDialog(
      icon: Icons.error_outline,
      iconColor: AppColors.error,
      iconBg: AppColors.errorLight,
      title: title,
      message: message,
      actions: [
        AppButton(
          label: 'OK',
          onPressed: () {
            Navigator.of(context).pop();
            onDone?.call();
          },
          variant: AppButtonVariant.danger,
        ),
      ],
    );
  }
}

class _AppDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String message;
  final List<Widget> actions;

  const _AppDialog({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.message,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: actions.map((a) => Expanded(child: a)).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

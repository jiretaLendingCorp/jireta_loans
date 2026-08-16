// lib/core/extensions/context_extensions.dart
import 'package:flutter/material.dart';
import '../../presentation/shared/widgets/app_toast.dart';
import '../theme/app_colors.dart';

extension ContextExtensions on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => Theme.of(this).textTheme;
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  bool get isWeb => screenWidth > 900;
  bool get isTablet => screenWidth > 600 && screenWidth <= 900;
  bool get isMobile => screenWidth <= 600;
  EdgeInsets get padding => MediaQuery.of(this).padding;

  /// Shows a proper toast at the upper-right corner, sized to its content.
  void showToast(String message, {AppToastType type = AppToastType.info}) {
    AppToast.show(this, message, type: type);
  }

  void showSuccessToast(String message) =>
      AppToast.show(this, message, type: AppToastType.success);

  void showErrorToast(String message) =>
      AppToast.show(this, message, type: AppToastType.error);

  // Backwards-compatible aliases so existing callers keep working.
  void showSnackBar(String message, {bool isError = false}) {
    AppToast.show(
      this,
      message,
      type: isError ? AppToastType.error : AppToastType.success,
    );
  }

  void showErrorSnack(String message) =>
      AppToast.show(this, message, type: AppToastType.error);
  void showSuccessSnack(String message) =>
      AppToast.show(this, message, type: AppToastType.success);

  /// Translates an existing `SnackBar` argument into a proper toast, so legacy
  /// `context.showSnackBarAsToast(SnackBar(...))` call sites can
  /// be migrated in place. Message and type are read from the SnackBar itself.
  void showSnackBarAsToast(SnackBar snackBar) {
    final content = snackBar.content;
    String? message;
    if (content is Text) {
      message = content.data;
    } else if (content is Row) {
      for (final child in content.children) {
        if (child is Text) {
          message = child.data;
          break;
        }
      }
    }
    final bg = snackBar.backgroundColor;
    var type = AppToastType.info;
    if (bg == AppColors.error) {
      type = AppToastType.error;
    } else if (bg == AppColors.success || bg == AppColors.riderGreen) {
      type = AppToastType.success;
    }
    AppToast.show(this, message ?? 'Notification', type: type);
  }
}
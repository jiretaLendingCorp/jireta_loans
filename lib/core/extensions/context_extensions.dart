// lib/core/extensions/context_extensions.dart
import 'package:flutter/material.dart';

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

  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(this).colorScheme.error
            : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void showErrorSnack(String message) => showSnackBar(message, isError: true);
  void showSuccessSnack(String message) =>
      showSnackBar(message, isError: false);
}

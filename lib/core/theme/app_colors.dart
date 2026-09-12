// lib/core/theme/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0D1B2A);
  static const Color deepNavy = Color(0xFF0D1B2A);
  static const Color navyLight = Color(0xFF1A2E45);
  static const Color navyDark = Color(0xFF071018);

  static const Color gold = Color(0xFFC9A84C);
  static const Color goldLight = Color(0xFFE0C270);
  static const Color goldDark = Color(0xFFA88A30);

  static const Color riderGreen = Color(0xFF2E7D32);
  static const Color riderGreenLight = Color(0xFF4CAF50);
  static const Color riderGreenDark = Color(0xFF1B5E20);

  static const Color employeeOrange = Color(0xFFEF6C00);

  static const Color lenderBlue = Color(0xFF0D1B2A);
  static const Color lenderBlueLight = Color(0xFF1A3658);
  static const Color lenderBlueDark = Color(0xFF071018);

  static const Color surfaceWhite = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF5F5F5);

  static const Color error = Color(0xFFD32F2F);
  static const Color errorLight = Color(0xFFFFEBEE);
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color warning = Color(0xFFF57C00);
  static const Color warningLight = Color(0xFFFFF8E1);
  static const Color info = Color(0xFF1565C0);
  static const Color infoLight = Color(0xFFE3F2FD);

  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF555568);
  static const Color textTertiary = Color(0xFF888899);
  static const Color textOnDark = Color(0xFFFFFFFF);
  static const Color textOnGold = Color(0xFF1A1A1A);

  static const Color border = Color(0xFFE0E0E0);
  static const Color borderDark = Color(0xFFBDBDBD);
  static const Color divider = Color(0xFFF0F0F0);

  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color sidebarBg = Color(0xFF0D1B2A);
  static const Color sidebarItem = Color(0xFF1A2E45);
  static const Color sidebarActive = Color(0xFF2A3F5C);

  static const Color shimmerBase = Color(0xFFE0E0E0);
  static const Color shimmerHighlight = Color(0xFFF5F5F5);

  static const Color statusPending = Color(0xFFF57C00);
  static const Color statusPendingBg = Color(0xFFFFF8E1);
  static const Color statusActive = Color(0xFF2E7D32);
  static const Color statusActiveBg = Color(0xFFE8F5E9);
  static const Color statusRejected = Color(0xFFD32F2F);
  static const Color statusRejectedBg = Color(0xFFFFEBEE);
  static const Color statusCompleted = Color(0xFF1565C0);
  static const Color statusCompletedBg = Color(0xFFE3F2FD);
  static const Color statusOverdue = Color(0xFFB71C1C);
  static const Color statusOverdueBg = Color(0xFFFFCDD2);

  static const Color surfaceGray = Color(0xFFF5F5F7);
  static const Color textHint = Color(0xFFB0B0C0);
  static const Color statusApproved = Color(0xFF2E7D32);
  static const Color statusApprovedBg = Color(0xFFE8F5E9);

  // ─── DARK MODE palette ─────────────────────────────────────────────────
  // Ginagamit ng [AppThemeColors] extension sa ibaba. Ang mga screen na
  // naka-migrate na sa `context.cSurface` / `context.cTextPrimary` atbp. ang
  // nag-a-adapt kapag naka-dark mode.
  static const Color darkPageBg = Color(0xFF0D1117);
  static const Color darkSurface = Color(0xFF161B22);
  static const Color darkSurfaceVariant = Color(0xFF1C232C);
  static const Color darkBorder = Color(0xFF2A323C);
  static const Color darkDivider = Color(0xFF232A33);
  static const Color darkTextPrimary = Color(0xFFE6EAF0);
  static const Color darkTextSecondary = Color(0xFFA9B2BF);
  static const Color darkTextTertiary = Color(0xFF7C8798);

  /// Header/AppBar sa dark mode — itim.
  static const Color darkAppBar = Color(0xFF000000);

  /// Shimmer (skeleton loading) sa dark mode.
  static const Color darkShimmerBase = Color(0xFF1B222B);
  static const Color darkShimmerHighlight = Color(0xFF2C3641);
}

/// Theme-aware color tokens (light + dark).
///
/// Gamitin sa loob ng `build()` ng mga screen na sumusuporta sa dark mode:
/// `color: context.cSurface`, `color: context.cTextPrimary`, atbp.
/// Hindi ito `const` kaya alisin ang `const` sa `TextStyle`/`BoxDecoration`
/// na gumagamit nito.
extension AppThemeColors on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Card / sheet surface.
  Color get cSurface =>
      isDarkMode ? AppColors.darkSurface : Colors.white;

  /// Page background.
  Color get cPageBg =>
      isDarkMode ? AppColors.darkPageBg : const Color(0xFFF0F2F5);

  Color get cSurfaceVariant =>
      isDarkMode ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant;

  Color get cTextPrimary =>
      isDarkMode ? AppColors.darkTextPrimary : AppColors.textPrimary;

  Color get cTextSecondary =>
      isDarkMode ? AppColors.darkTextSecondary : AppColors.textSecondary;

  Color get cTextTertiary =>
      isDarkMode ? AppColors.darkTextTertiary : AppColors.textTertiary;

  Color get cBorder => isDarkMode ? AppColors.darkBorder : AppColors.border;

  Color get cDivider => isDarkMode ? AppColors.darkDivider : AppColors.divider;

  /// Soft shadows are almost invisible on dark surfaces.
  Color get cShadow =>
      isDarkMode ? Colors.black.withValues(alpha: 0.5) : Colors.black;

  /// Header/AppBar: itim sa dark mode, kulay ng role (accent) sa light mode.
  Color headerColor(Color accent) =>
      isDarkMode ? AppColors.darkAppBar : accent;

  /// Rider green na nababasa sa dark surfaces (mas maliwanag sa dark mode).
  Color get cBrandGreen =>
      isDarkMode ? AppColors.riderGreenLight : AppColors.riderGreen;
}

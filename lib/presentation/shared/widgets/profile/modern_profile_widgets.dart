// lib/presentation/shared/widgets/profile/modern_profile_widgets.dart
// Shared Modern Minimalist profile kit used by lender + rider profiles.
// Principles: neutral palette, hairline borders, no heavy shadows,
// Inter type scale, generous whitespace, single accent color per role.
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../profile_avatar_upload.dart';

class ModernProfileStyles {
  ModernProfileStyles._();

  static const Color cardBorder = Color(0xFFE8EAED);
  static const Color hairline = Color(0xFFF1F2F4);
  static const Color iconBg = Color(0xFFF3F4F6);
  static const Color iconColor = Color(0xFF5B6472);
  static const double cardRadius = 14;

  static BoxDecoration get card => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(color: cardBorder),
      );

  static TextStyle get sectionLabel => const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: AppColors.textTertiary,
      );

  static TextStyle get name => const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: AppColors.textPrimary,
      );

  static TextStyle get sub => const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  static TextStyle get rowLabel => const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textTertiary,
      );

  static TextStyle get rowValue => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.35,
      );

  static TextStyle get menuTitle => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get menuSubtitle => const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );
}

/// Centered header: avatar with subtle ring, name, subtitle lines,
/// minimal status pill. No serif fonts, no colored name text.
class ModernProfileHeader extends StatelessWidget {
  final String name;
  final List<String> subtitles;
  final String? photoUrl;
  final Color accent;
  final Future<void> Function(String url)? onAvatarUploaded;
  final String statusLabel;
  final Color statusColor;
  final Color statusBg;

  const ModernProfileHeader({
    super.key,
    required this.name,
    this.subtitles = const [],
    this.photoUrl,
    required this.accent,
    this.onAvatarUploaded,
    required this.statusLabel,
    required this.statusColor,
    required this.statusBg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: ModernProfileStyles.card,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: ModernProfileStyles.cardBorder, width: 1.5),
              ),
              child: onAvatarUploaded != null
                  ? ProfileAvatarUpload(
                      photoUrl: photoUrl,
                      name: name,
                      color: accent,
                      radius: 36,
                      onUploaded: onAvatarUploaded!,
                    )
                  : CircleAvatar(
                      radius: 36,
                      backgroundColor: accent.withValues(alpha: 0.1),
                      child: Text(
                        _initials(name),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name.isEmpty ? '—' : name,
            textAlign: TextAlign.center,
            style: ModernProfileStyles.name,
          ),
          for (final s in subtitles) ...[
            const SizedBox(height: 3),
            Text(s, textAlign: TextAlign.center,
                style: ModernProfileStyles.sub),
          ],
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String value) {
    final parts =
        value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.length >= 2
          ? (parts.first[0] + parts.first[1]).toUpperCase()
          : parts.first[0].toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

/// Minimal info card: icon rows separated by hairlines.
/// No collapsible animation, no colored icon tiles — calm and scannable.
class ModernInfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<ModernInfoRowData> rows;

  const ModernInfoCard({
    super.key,
    required this.title,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: ModernProfileStyles.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: ModernProfileStyles.iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon,
                      size: 16,
                      color: ModernProfileStyles.iconColor),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(
              height: 1, color: ModernProfileStyles.hairline),
          for (var i = 0; i < rows.length; i++) ...[
            _Row(entry: rows[i]),
            if (i != rows.length - 1)
              const Divider(
                height: 1,
                indent: 58,
                endIndent: 16,
                color: ModernProfileStyles.hairline,
              ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class ModernInfoRowData {
  final IconData icon;
  final String label;
  final String value;
  const ModernInfoRowData({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _Row extends StatelessWidget {
  final ModernInfoRowData entry;
  const _Row({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(entry.icon,
              size: 16, color: ModernProfileStyles.iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.label,
                    style: ModernProfileStyles.rowLabel),
                const SizedBox(height: 2),
                Text(
                  entry.value.isEmpty ? '—' : entry.value,
                  style: ModernProfileStyles.rowValue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal menu list: single white card, hairline dividers,
/// quiet icons, chevron affordance.
class ModernMenuCard extends StatelessWidget {
  final List<ModernMenuItem> items;
  const ModernMenuCard({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ModernProfileStyles.card,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _MenuRow(item: items[i]),
            if (i != items.length - 1)
              const Divider(
                height: 1,
                indent: 58,
                endIndent: 0,
                color: ModernProfileStyles.hairline,
              ),
          ],
        ],
      ),
    );
  }
}

class ModernMenuItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const ModernMenuItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
}

class _MenuRow extends StatelessWidget {
  final ModernMenuItem item;
  const _MenuRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: ModernProfileStyles.iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(item.icon,
                  size: 17, color: ModernProfileStyles.iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: ModernProfileStyles.menuTitle),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(item.subtitle!,
                        style: ModernProfileStyles.menuSubtitle),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Full-width minimal primary button. Single accent, no elevation.
class ModernPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onPressed;
  final bool loading;

  const ModernPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.color,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : icon != null
                ? Icon(icon, size: 18)
                : const SizedBox.shrink(),
        label: Text(
          loading ? 'Please wait…' : label,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Minimal section label used above each group.
class ModernSectionLabel extends StatelessWidget {
  final String text;
  const ModernSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(text.toUpperCase(),
          style: ModernProfileStyles.sectionLabel),
    );
  }
}

/// Minimal bottom sheet: drag handle, quiet title row, clean sections.
class ModernInfoSheet extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<ModernSheetSection> sections;

  const ModernInfoSheet({
    super.key,
    required this.title,
    required this.icon,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ModernProfileStyles.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: ModernProfileStyles.iconBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon,
                        size: 17,
                        color: ModernProfileStyles.iconColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        size: 20,
                        color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            const Divider(
                height: 1, color: ModernProfileStyles.hairline),
            Flexible(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in sections) ...[
                      Text(
                        s.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.body,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.65,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModernSheetSection {
  final String title;
  final String body;
  const ModernSheetSection({required this.title, required this.body});
}

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

  // ── DARK MODE variants ────────────────────────────────────────────────
  // Sa light mode, kapareho lang ng static values sa itaas (walang visual
  // change); sa dark mode, kumukuha sa AppThemeColors tokens.
  static BoxDecoration cardOf(BuildContext context) => BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(color: context.cBorder),
      );

  static Color hairlineOf(BuildContext context) => context.cDivider;

  static Color iconBgOf(BuildContext context) => context.cSurfaceVariant;

  static Color iconColorOf(BuildContext context) =>
      context.isDarkMode ? AppColors.darkTextSecondary : iconColor;

  static TextStyle sectionLabelOf(BuildContext context) =>
      sectionLabel.copyWith(color: context.cTextTertiary);

  static TextStyle nameOf(BuildContext context) =>
      name.copyWith(color: context.cTextPrimary);

  static TextStyle subOf(BuildContext context) =>
      sub.copyWith(color: context.cTextSecondary);

  static TextStyle rowLabelOf(BuildContext context) =>
      rowLabel.copyWith(color: context.cTextTertiary);

  static TextStyle rowValueOf(BuildContext context) =>
      rowValue.copyWith(color: context.cTextPrimary);

  static TextStyle menuTitleOf(BuildContext context) =>
      menuTitle.copyWith(color: context.cTextPrimary);

  static TextStyle menuSubtitleOf(BuildContext context) =>
      menuSubtitle.copyWith(color: context.cTextSecondary);
}

/// Centered header: avatar with subtle ring, name, subtitle lines,
/// minimal status pill (or plain text when [statusAsText] is true).
/// No serif fonts, no colored name text.
class ModernProfileHeader extends StatelessWidget {
  final String name;
  final List<String> subtitles;
  final String? photoUrl;
  final Color accent;
  final Future<void> Function(String url)? onAvatarUploaded;
  final String statusLabel;
  final Color statusColor;
  final Color statusBg;
  final bool statusAsText;

  /// When true the header is drawn directly on the page background without
  /// the white card (and the ring "plate" behind the avatar is removed).
  /// Defaults to false so every existing profile page keeps its card look.
  final bool flat;

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
    this.statusAsText = false,
    this.flat = false,
  });

  Widget _buildAvatar() {
    if (onAvatarUploaded != null) {
      return ProfileAvatarUpload(
        photoUrl: photoUrl,
        name: name,
        color: accent,
        radius: 36,
        onUploaded: onAvatarUploaded!,
      );
    }
    return CircleAvatar(
      radius: 36,
      backgroundColor: accent.withValues(alpha: 0.12),
      child: Text(
        _initials(name),
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatar = flat
        // Clean look: the photo sits directly on the page, no card behind it.
        ? _buildAvatar()
        : Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.cSurface,
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: context.cBorder, width: 1.5),
              ),
              child: _buildAvatar(),
            ),
          );

    final content = Column(
      children: [
        avatar,
        const SizedBox(height: 12),
        Text(
          name.isEmpty ? '—' : name,
          textAlign: TextAlign.center,
          style: ModernProfileStyles.nameOf(context),
        ),
        for (final s in subtitles) ...[
          const SizedBox(height: 3),
          Text(s,
              textAlign: TextAlign.center,
              style: ModernProfileStyles.subOf(context)),
        ],
        const SizedBox(height: 10),
        if (statusAsText)
          Text(
            statusLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              color: statusColor,
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
    );

    if (flat) {
      // Full width so the avatar + name + status block is centered on the
      // page (like the card variant) instead of hugging the left edge.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: SizedBox(
          width: double.infinity,
          child: content,
        ),
      );
    }
    return Container(
      width: double.infinity,
      decoration: ModernProfileStyles.cardOf(context),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: content,
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
/// Kapag [collapsible] = true, pwedeng i-tap ang header para i-toggle
/// (expand/collapse) ang mga rows. Default: laging bukas (dating look).
class ModernInfoCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<ModernInfoRowData> rows;

  /// Kapag true, tappable ang header at pwedeng itago ang rows.
  final bool collapsible;

  /// Simula sa expanded state (kapag [collapsible]).
  final bool initiallyExpanded;

  /// Walang card box (puting background/border) — plain na nakalapat lang
  /// sa page, hairlines pa rin ang naghihiwalay sa rows.
  final bool flat;

  const ModernInfoCard({
    super.key,
    required this.title,
    required this.icon,
    required this.rows,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.flat = false,
  });

  @override
  State<ModernInfoCard> createState() => _ModernInfoCardState();
}

class _ModernInfoCardState extends State<ModernInfoCard> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    if (!widget.collapsible) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    // Flat: kaunting indent lang para pantay sa section label (4px).
    final pad = widget.flat ? 4.0 : 16.0;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(pad, 14, pad, 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: ModernProfileStyles.iconBgOf(context),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon,
                size: 16, color: ModernProfileStyles.iconColorOf(context)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.cTextPrimary,
              ),
            ),
          ),
          if (widget.collapsible)
            AnimatedRotation(
              turns: _expanded ? 0 : 0.5,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              child: Icon(Icons.expand_more_rounded,
                  size: 20, color: context.cTextTertiary),
            ),
        ],
      ),
    );

    final rowsSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 1, color: ModernProfileStyles.hairlineOf(context)),
        for (var i = 0; i < widget.rows.length; i++) ...[
          _Row(entry: widget.rows[i], horizontal: pad),
          if (i != widget.rows.length - 1)
            Divider(
              height: 1,
              indent: pad + 42,
              endIndent: pad,
              color: ModernProfileStyles.hairlineOf(context),
            ),
        ],
        const SizedBox(height: 4),
      ],
    );

    return Container(
      width: double.infinity,
      decoration: widget.flat ? null : ModernProfileStyles.cardOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.collapsible)
            InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(ModernProfileStyles.cardRadius),
              child: header,
            )
          else
            header,
          if (widget.collapsible)
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeInOut,
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: rowsSection,
            )
          else
            rowsSection,
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
  final double horizontal;
  const _Row({required this.entry, this.horizontal = 16});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(entry.icon,
              size: 16, color: ModernProfileStyles.iconColorOf(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.label,
                    style: ModernProfileStyles.rowLabelOf(context)),
                const SizedBox(height: 2),
                Text(
                  entry.value.isEmpty ? '—' : entry.value,
                  style: ModernProfileStyles.rowValueOf(context),
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
      decoration: ModernProfileStyles.cardOf(context),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _MenuRow(item: items[i]),
            if (i != items.length - 1)
              Divider(
                height: 1,
                indent: 58,
                endIndent: 0,
                color: ModernProfileStyles.hairlineOf(context),
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

  /// Optional na widget sa dulong kanan (hal. `Switch` para sa settings row).
  /// Kapag null, chevron ang ipapakita.
  final Widget? trailing;

  const ModernMenuItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.trailing,
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
                color: ModernProfileStyles.iconBgOf(context),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(item.icon,
                  size: 17,
                  color: ModernProfileStyles.iconColorOf(context)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: ModernProfileStyles.menuTitleOf(context)),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(item.subtitle!,
                        style: ModernProfileStyles.menuSubtitleOf(context)),
                  ],
                ],
              ),
            ),
            item.trailing ??
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: context.cTextTertiary),
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
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
          style: ModernProfileStyles.sectionLabelOf(context)),
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
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  color: context.cBorder,
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
                      color: ModernProfileStyles.iconBgOf(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon,
                        size: 17,
                        color: ModernProfileStyles.iconColorOf(context)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.cTextPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded,
                        size: 20, color: context.cTextTertiary),
                  ),
                ],
              ),
            ),
            Divider(
                height: 1, color: ModernProfileStyles.hairlineOf(context)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in sections) ...[
                      Text(
                        s.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.cTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.body,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.65,
                          color: context.cTextSecondary,
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

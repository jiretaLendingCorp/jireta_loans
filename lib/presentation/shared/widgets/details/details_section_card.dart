// lib/presentation/shared/widgets/details/details_section_card.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class DetailsItem {
  final String label;
  final String value;
  final Widget? valueWidget;
  const DetailsItem(this.label, this.value, {this.valueWidget});
}

class DetailsSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final List<DetailsItem> items;
  final Widget? footer;

  const DetailsSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.items,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 17, color: accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.deepNavy,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 28,
              runSpacing: 18,
              children: items.map(_buildTile).toList(),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 18),
            footer!,
          ],
        ],
      ),
    );
  }

  Widget _buildTile(DetailsItem item) {
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          if (item.valueWidget != null)
            item.valueWidget!
          else
            Text(
              item.value,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
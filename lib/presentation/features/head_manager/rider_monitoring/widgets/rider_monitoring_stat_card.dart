// lib/presentation/features/head_manager/rider_monitoring/widgets/rider_monitoring_stat_card.dart
import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';

/// Summary card para sa Rider Collection Monitoring.
///
/// Kapareho ng visual language ng `KpiStatCard` (puting card, 12px radius,
/// colored icon tile) pero EXACT ang value — hindi ito nag-a-abbreviate sa
/// `₱1.2K`, dahil ang monitoring page ay ginagamit para i-reconcile ang
/// expected, confirmed at remaining collections.
///
/// Nasa SARILING linya ang subtitle (hindi katabi ng icon) para hindi ito
/// maputol sa makitid na card — dati, "8 installm…" at "108.8% o…" lang ang
/// nakikita sa 1366px desktop.
class RiderMonitoringStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const RiderMonitoringStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  /// Taas ng subtitle slot — nakalaan kahit walang subtitle para pantay-pantay
  /// ang lahat ng card sa isang row.
  static const double _subtitleHeight = 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.cBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.cTextPrimary,
                fontFamily: 'Inter',
              ),
            ),
          ),
          const SizedBox(height: 1),
          // Buong lapad ng card ang subtitle ngayon — hindi na kasama ang
          // icon sa parehong Row, kaya hindi na nag-e-ellipsis.
          SizedBox(
            height: _subtitleHeight,
            width: double.infinity,
            child: subtitle == null
                ? null
                : Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
          ),
          const SizedBox(height: 1),
          // Fixed na taas para pantay-pantay ang lahat ng compact card kahit
          // isa o dalawang linya ang title.
          SizedBox(
            height: 27,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: context.cTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kulay ng performance indicator — walang "quota pass/fail" na kahulugan;
/// visual aid lang para mabilis makita ang riders na may malaking gap sa
/// confirmed collections.
Color riderPerformanceColor(double? percent) {
  if (percent == null) return AppColors.textTertiary;
  if (percent >= 80) return AppColors.success;
  if (percent >= 50) return AppColors.warning;
  return AppColors.statusRejected;
}

/// Display na porsyento ng performance — NAKA-CAP sa 100%.
///
/// BAKIT: `confirmed / expected` ay pwedeng lumampas sa 100% kapag mas
/// malaking halaga ang naitala kaysa sa expected (advance/partial na bayad, o
/// late-posted na installment). Nasa data pa rin ang totoong value; display
/// lang ang cap para hindi lumabas ang "166.7%" na parang mali sa table.
String riderPerformanceLabel(double? percent) {
  if (percent == null) return '—';
  final capped = percent.clamp(0, 100).toDouble();
  return '${capped.toStringAsFixed(1)}%';
}

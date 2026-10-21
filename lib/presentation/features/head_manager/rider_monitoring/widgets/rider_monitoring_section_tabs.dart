// lib/presentation/features/head_manager/rider_monitoring/widgets/rider_monitoring_section_tabs.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/route_constants.dart';
import '../../../../shared/widgets/filter_pill_tab.dart';

/// Mga tab ng Rider Monitoring section — nasa TAAS ng page.
///
/// Bawat tab ay may SARILING URI (`/hm/rider-monitoring` at
/// `/hm/rider-monitoring/quotas`) para deep-linkable, tama pa rin pagkatapos
/// ng refresh/bookmark/browser back, at hindi ito basta client-side state.
class RiderMonitoringSectionTabs extends StatelessWidget {
  /// Kasalukuyang path (`RouteConstants.hmRiderMonitoring*`).
  final String activeRoute;

  const RiderMonitoringSectionTabs({super.key, required this.activeRoute});

  static const _monitoring = FilterTabDef(
    'monitoring',
    'Monitoring',
    Icons.insights_outlined,
  );
  static const _quotas = FilterTabDef(
    'quotas',
    'Quotas',
    Icons.flag_outlined,
  );

  Widget _pill(BuildContext context, FilterTabDef def, String route) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterPillTab(
        def: def,
        active: activeRoute == route,
        onTap: () {
          if (activeRoute == route) return;
          context.go(route);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _pill(context, _monitoring, RouteConstants.hmRiderMonitoring),
          _pill(context, _quotas, RouteConstants.hmRiderMonitoringQuotas),
        ],
      ),
    );
  }
}

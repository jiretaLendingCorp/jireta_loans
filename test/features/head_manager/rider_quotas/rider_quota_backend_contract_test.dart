// test/features/head_manager/rider_quotas/rider_quota_backend_contract_test.dart
//
// Contract checks para sa Rider Quota Management backend (00187):
//   • HM lang ang makakapag-create/update/close; Rider lang ang my-quota at ang
//     rider id ay galing sa token.
//   • Service-role only ang table at RPC (walang anon/authenticated).
//   • `confirmed` ay verified payments lang, nasa loob ng quota window
//     (Asia/Manila), at hindi binibilang ang labas ng period.
//   • Walang financial penalty / wage deduction / loan update sa feature.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readNormalized(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

/// Tanggalin ang SQL line comments bago mag-assert — ang header ng migration ay
/// nagdo-dokumento ng "walang wage deduction", kaya kung hindi ito tinanggal
/// ay nag-fa-false positive ang "walang deduct" na check.
String stripSqlComments(String sql) => sql
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('--'))
    .join('\n');

void main() {
  group('collections-view — quota read access', () {
    late String src;
    setUpAll(() {
      src = readNormalized('supabase/functions/collections-view/index.ts');
    });

    test('rider-quotas ay HM/Employee read-only na endpoint', () {
      expect(src, contains("case 'rider-quotas':"));
      expect(src, contains("case 'rider-quota-riders':"));
      expect(src, contains("case 'my-quota':"));
      expect(
        src,
        contains(
          'requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE)',
        ),
      );
      expect(src, contains('db.rpc(\'rider_quota_monitoring\''));
    });

    test('my-quota ay rider only at token ang source ng rider id', () {
      expect(src, contains('requireRole(authResult, ROLES.RIDER)'));
      expect(src, contains('db.rpc(\'rider_quota_self\''));
      final block = src.substring(src.indexOf('async function handleMyQuota'));
      expect(block, contains('p_rider_id: authResult.id'));
      expect(block, isNot(contains("searchParams.get('rider_id')")));
    });
  });

  group('collections-manage — quota write access', () {
    late String src;
    setUpAll(() {
      src = readNormalized('supabase/functions/collections-manage/index.ts');
    });

    test('create/update/close ay Head Manager only', () {
      expect(src, contains("case 'create-rider-quota':"));
      expect(src, contains("case 'update-rider-quota':"));
      expect(src, contains("case 'close-rider-quota':"));
      for (final fn in [
        'handleRiderQuotaCreate',
        'handleRiderQuotaUpdate',
        'handleRiderQuotaClose',
      ]) {
        final start = src.indexOf('async function $fn');
        expect(start, greaterThan(-1), reason: '$fn must exist');
        final next = src.indexOf('async function ', start + 10);
        final block = src.substring(start, next == -1 ? src.length : next);
        expect(block, contains('requireRole(authResult, ROLES.HEAD_MANAGER)'));
        expect(block, contains('writeAuditLog('));
      }
    });

    test('overlap at period rules ay naka-validate sa server', () {
      expect(src, contains('QUOTA_OVERLAP'));
      expect(src, contains('findOverlappingActiveQuota'));
      expect(src, contains("daily: { min: 1, max: 1 }"));
      expect(src, contains("weekly: { min: 7, max: 7 }"));
      expect(src, contains("monthly: { min: 28, max: 31 }"));
      expect(src, contains('QUOTA_PERIOD_ENDED'));
      expect(src, contains('RIDER_IMMUTABLE'));
    });

    test('quota write ay hindi gumagawa ng penalty o wage deduction', () {
      final lower = src.toLowerCase();
      expect(lower, isNot(contains('deduct')));
      expect(lower, isNot(contains('penalty_logs')));
      expect(lower, isNot(contains('update public.loans')));
    });
  });

  group('migration 00187 — schema, derivation at grants', () {
    late String sql;
    setUpAll(() {
      sql =
          readNormalized('supabase/migrations/00187_rider_quotas.sql');
    });

    test('table + overlap trigger + derived statuses', () {
      expect(sql, contains('CREATE TABLE IF NOT EXISTS public.rider_quotas'));
      expect(sql, contains('trg_rider_quota_no_overlap'));
      expect(sql, contains('fn_rider_quota_no_overlap'));
      expect(sql, contains("'daily', 'weekly', 'monthly'"));
      expect(sql, contains("'upcoming'"));
      expect(sql, contains("'completed'"));
      expect(sql, contains("'expired'"));
      expect(sql, contains("'inactive'"));
    });

    test('verified payments lang at loob ng quota window', () {
      expect(sql, contains("pay.status = 'verified'"));
      expect(
        sql,
        contains(
          "(pay.paid_at AT TIME ZONE 'Asia/Manila')::date BETWEEN rb.start_date AND rb.end_date",
        ),
      );
      expect(sql, contains('GREATEST(rb.target_amount - COALESCE(cf.confirmed, 0), 0)'));
      expect(sql, contains('ROUND(COALESCE(cf.confirmed, 0) / rb.target_amount * 100, 2)'));
    });

    test('service-role only — walang anon/authenticated access', () {
      expect(sql, contains('REVOKE ALL ON TABLE public.rider_quotas FROM anon, authenticated'));
      expect(
        sql,
        contains('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.rider_quotas TO service_role'),
      );
      expect(sql, contains('REVOKE ALL ON FUNCTION public.rider_quota_monitoring'));
      expect(sql, contains('REVOKE ALL ON FUNCTION public.rider_quota_self'));
      expect(sql, contains('TO service_role'));
    });

    test('walang penalty o loan mutation sa feature', () {
      final code = stripSqlComments(sql).toLowerCase();
      expect(code, isNot(contains('deduct')));
      expect(code, isNot(contains('update public.loans')));
      expect(code, isNot(contains('update public.loan_schedules')));
      expect(code, isNot(contains('insert into public.payments')));
    });
  });

  group('routes at navigation', () {
    test('quota tab ay may sariling URI sa ilalim ng rider-monitoring', () {
      final routes = readNormalized('lib/core/constants/route_constants.dart');
      expect(
        routes,
        contains("hmRiderMonitoringQuotas = '/hm/rider-monitoring/quotas'"),
      );
      expect(routes, contains("riderMyQuota = '/rider/my-quota'"));

      final router = readNormalized('lib/core/router/app_router.dart');
      // Naka-register BAGO ang `:id` route — kung hindi, ang "quotas" ay
      // mababasa bilang rider id at 404 ang tab.
      final quotasIdx =
          router.indexOf('RouteConstants.hmRiderMonitoringQuotas');
      final detailsIdx =
          router.indexOf('RouteConstants.hmRiderMonitoringDetails');
      expect(quotasIdx, greaterThan(-1));
      expect(detailsIdx, greaterThan(-1));
      expect(quotasIdx, lessThan(detailsIdx));
      // Lumang link ay redirect, hindi puting screen.
      expect(
        router,
        contains(
          'redirect: (ctx, s) => RouteConstants.hmRiderMonitoringQuotas',
        ),
      );
      expect(router, contains('RouteConstants.riderMyQuota'));
    });

    test('Rider Quotas ang nasa sidebar, hindi Rider Monitoring', () {
      final nav = readNormalized(
          'lib/presentation/shared/widgets/layout/web_scaffold.dart');
      expect(nav, contains("'Rider Quotas'"));
      expect(nav, isNot(contains("'Rider Monitoring'")));
      // Naka-link ang sidebar entry sa Quotas URI ng HM at employee.
      expect(nav, contains('RouteConstants.hmRiderMonitoringQuotas'));
      expect(nav, contains('RouteConstants.empRiderMonitoringQuotas'));

      final tabs = readNormalized(
          'lib/presentation/features/head_manager/rider_monitoring/widgets/rider_monitoring_section_tabs.dart');
      expect(tabs, contains('class RiderMonitoringSectionTabs'));
      expect(tabs, contains('RouteConstants.hmRiderMonitoringQuotas'));
      expect(tabs, contains('context.go(route)'));

      final monitoring = readNormalized(
          'lib/presentation/features/head_manager/rider_monitoring/screens/hm_rider_monitoring_screen.dart');
      final quotas = readNormalized(
          'lib/presentation/features/head_manager/rider_quotas/screens/hm_rider_quotas_screen.dart');
      expect(monitoring, contains('RiderMonitoringSectionTabs'));
      expect(quotas, contains('RiderMonitoringSectionTabs'));
      expect(quotas, contains("title: 'Rider Collection Monitoring'"));
    });

    test('nakatago ang Monitoring view — Quotas ang lumalabas sa base route',
        () {
      final router = readNormalized('lib/core/router/app_router.dart');
      final base = router.indexOf('path: RouteConstants.hmRiderMonitoring,');
      expect(base, greaterThan(-1));
      expect(
        router.substring(base, base + 200),
        contains('redirect: (ctx, s) => RouteConstants.hmRiderMonitoringQuotas'),
        reason: 'Dapat Quotas ang buksan ng /hm/rider-monitoring',
      );

      final tabs = readNormalized(
          'lib/presentation/features/head_manager/rider_monitoring/widgets/rider_monitoring_section_tabs.dart');
      expect(tabs, contains('static const bool _showMonitoringTab = false;'));
      // Quotas tab pa rin ang dapat lumabas, hindi buong strip ang tinanggal.
      expect(tabs, contains('if (_showMonitoringTab)'));
      expect(tabs, contains('_pill(context, _quotas, quotasRoute!)'));
    });
  });
}

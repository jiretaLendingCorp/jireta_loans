// test/features/head_manager/rider_monitoring/rider_monitoring_backend_contract_test.dart
//
// Contract checks para sa Rider Collection Monitoring backend:
//   • HM/Employee lang ang monitoring endpoints; rider lang ang my-summary at
//     ang rider id ay galing sa token (hindi sa query string).
//   • Ang RPC ay service-role only (walang anon/authenticated access).
//   • `confirmed` ay verified payments lang — hindi pending/rejected.
//   • Read-only ang feature (walang INSERT/UPDATE/DELETE sa RPC).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readNormalized(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

void main() {
  group('collections-view — rider monitoring access', () {
    late String src;
    setUpAll(() {
      src = readNormalized('supabase/functions/collections-view/index.ts');
    });

    test('monitoring at detail ay HM/Employee only', () {
      expect(src, contains("case 'rider-monitoring':"));
      expect(src, contains("case 'rider-monitoring-detail':"));
      expect(
        src,
        contains(
          'requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE)',
        ),
      );
    });

    test('my-summary ay rider only at token ang source ng rider id', () {
      expect(src, contains("case 'my-collection-summary':"));
      expect(src, contains('if (authResult.role !== ROLES.RIDER)'));
      expect(src, contains('p_rider_id: authResult.id'));
      // Walang query-string na rider_id sa my-summary.
      // Hanggang sa SUSUNOD na function lang — may mga handler na
      // naka-append pagkatapos nito (hal. rider quotas) at may sarili silang
      // `rider_id` query param na lehitimo.
      final start = src.indexOf('async function handleMyCollectionSummary');
      final next = src.indexOf('async function ', start + 10);
      final mySummaryBlock =
          src.substring(start, next == -1 ? src.length : next);
      expect(
        mySummaryBlock,
        isNot(contains("searchParams.get('rider_id')")),
      );
    });

    test('validated ang date range at rider uuid', () {
      expect(src, contains('date_from must be a valid YYYY-MM-DD date'));
      expect(src, contains('date_from must not be after date_to'));
      expect(src, contains('Invalid rider_id'));
    });
  });

  group('migration 00186 — read-only at service-role only', () {
    late String sql;
    setUpAll(() {
      sql = readNormalized(
          'supabase/migrations/00186_rider_collection_monitoring.sql');
    });

    test('RPC at view ay hindi accessible sa anon/authenticated', () {
      expect(
        sql,
        contains('REVOKE ALL ON FUNCTION public.rider_collection_monitoring'),
      );
      expect(sql, contains('FROM anon, authenticated'));
      expect(
        sql,
        contains(
          'GRANT EXECUTE ON FUNCTION public.rider_collection_monitoring',
        ),
      );
      expect(sql, contains('TO service_role'));
    });

    test('verified lang ang confirmed; walang pending/rejected', () {
      expect(sql, contains("AND p.status = 'verified'"));
      expect(sql, contains("pay.status = 'verified'"));
    });

    test('walang write operation sa monitoring SQL', () {
      final lower = sql.toLowerCase();
      expect(lower, isNot(contains('insert into public.payments')));
      expect(lower, isNot(contains('update public.loans')));
      expect(lower, isNot(contains('update public.loan_schedules')));
      expect(lower, isNot(contains('delete from public.collection')));
    });

    test('report template ay naka-seed at naka-register', () {
      expect(sql, contains("'rider_collection_summary'"));
      final reportsView =
          readNormalized('supabase/functions/reports-view/index.ts');
      final reportsGenerate =
          readNormalized('supabase/functions/reports-generate/index.ts');
      expect(reportsView, contains("key: 'rider_collection_summary'"));
      expect(reportsGenerate, contains("case 'rider_collection_summary':"));
      expect(reportsGenerate, contains("'rider_collection_summary',"));
    });
  });
}

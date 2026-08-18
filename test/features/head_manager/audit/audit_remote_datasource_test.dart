import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/audit_test_helpers.dart';

void main() {
  setUpAll(loadTestEnv);

  group('AuditRemoteDataSource.getAuditLogs', () {
    test('sends performed_by_name (not performed_by) for the search box', () async {
      late RequestOptions captured;
      final ds = fakeAuditDataSource((options) async {
        captured = options;
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: auditResponse(logs: [auditLogRow()]),
        );
      });

      await ds.getAuditLogs(performedBy: 'Jane Doe');

      expect(captured.queryParameters['performed_by_name'], 'Jane Doe');
      expect(captured.queryParameters['performed_by'], isNull);
    });

    test('sends action, page and limit query params', () async {
      late RequestOptions captured;
      final ds = fakeAuditDataSource((options) async {
        captured = options;
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: auditResponse(logs: [auditLogRow()]),
        );
      });

      await ds.getAuditLogs(action: 'loan_approve', page: 3, limit: 10);

      expect(captured.queryParameters['action'], 'loan_approve');
      expect(captured.queryParameters['page'], 3);
      expect(captured.queryParameters['limit'], 10);
    });

    test('omits null filter params', () async {
      late RequestOptions captured;
      final ds = fakeAuditDataSource((options) async {
        captured = options;
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: auditResponse(),
        );
      });

      await ds.getAuditLogs();

      expect(captured.queryParameters.containsKey('action'), isFalse);
      expect(captured.queryParameters.containsKey('performed_by_name'),
          isFalse);
    });

    test('parses data and meta into the response map', () async {
      final row = auditLogRow(action: 'loan_reject');
      final ds = fakeAuditDataSource((options) async {
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: auditResponse(logs: [row], page: 2, limit: 20),
        );
      });

      final res = await ds.getAuditLogs(page: 2);

      final data = res['data'] as List;
      expect(data, hasLength(1));
      expect((data.first as Map)['action'], 'loan_reject');
      final meta = res['meta'] as Map<String, dynamic>;
      expect(meta['page'], 2);
      expect(meta['total_pages'], 1);
      expect(meta['total'], 1);
    });

    test('computes total_pages when the backend omits meta', () async {
      final ds = fakeAuditDataSource((options) async {
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'data': List.generate(50, (_) => auditLogRow()),
          },
        );
      });

      final res = await ds.getAuditLogs(limit: 20);
      final meta = res['meta'] as Map<String, dynamic>;
      expect(meta['total_pages'], 3);
      expect(meta['total'], 50);
    });

    test('throws through when the transport fails', () async {
      final ds = fakeAuditDataSource((options) async {
        throw DioException(
          requestOptions: options,
          message: 'No internet connection.',
          type: DioExceptionType.connectionError,
        );
      });

      await expectLater(
        ds.getAuditLogs(),
        throwsA(isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.connectionError,
        )),
      );
    });
  });

  group('AuditRemoteDataSource.getLogs', () {
    test('delegates to getAuditLogs with the same filters', () async {
      late RequestOptions captured;
      final ds = fakeAuditDataSource((options) async {
        captured = options;
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: auditResponse(),
        );
      });

      await ds.getLogs(
          action: 'collection_assign',
          performedBy: 'Rider',
          tableName: 'collection_assignments',
          page: 4);

      expect(captured.queryParameters['action'], 'collection_assign');
      expect(captured.queryParameters['performed_by_name'], 'Rider');
      expect(captured.queryParameters['table_name'], 'collection_assignments');
      expect(captured.queryParameters['page'], 4);
    });
  });
}

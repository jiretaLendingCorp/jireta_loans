// test/rest_api_debug_test.dart
// Debug harness for all REST API endpoints.
// Verifies that every RemoteDataSource makes a Dio call with the correct
// path/method and correctly parses the expected JSON shape without throwing
// on happy-path data. Uses a fake DioClient that records calls.

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:jireta_loans/core/network/api_endpoints.dart';
import 'package:jireta_loans/core/network/dio_client.dart';
import 'package:jireta_loans/data/datasources/remote/audit_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/ci_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/disbursement_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/kpi_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/loan_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/location_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/payment_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/report_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/system_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/account_upgrade_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/in_office_remote_datasource.dart';

class FakeDioClient implements DioClient {
  String? lastPath;
  String? lastMethod;
  dynamic lastData;
  Map<String, dynamic>? lastQuery;

  dynamic _mockGetData(String path) {
    if (path.contains('audit-get-logs')) {
      return {'data': [], 'meta': {'total': 0, 'total_pages': 0}, 'total': 0};
    } else if (path.contains('users-admin')) {
      return {'data': [], 'total': 0, 'page': 1, 'limit': 20, 'totalPages': 0};
    } else if (path.contains('loans-view')) {
      if (path.contains('get-details')) {
        return {'id': 'loan_1', 'lender_id': 'u1', 'principal_amount': 10000, 'status': 'pending'};
      } else {
        return {'data': [], 'total': 0, 'page': 1, 'limit': 20, 'totalPages': 0};
      }
    } else if (path.contains('kpi-view')) {
      return <String, dynamic>{'total_employees': 0, 'total_riders': 0, 'total_lenders': 0, 'total_loan_applications': 0, 'total_approved_loans': 0, 'total_rejected_loans': 0, 'total_active_loans': 0, 'total_completed_loans': 0, 'total_overdue_loans': 0, 'total_loan_amount_released': 0, 'total_amount_collected': 0, 'total_outstanding_balance': 0, 'total_interest_earned': 0, 'total_penalties_collected': 0, 'total_revenue': 0, 'total_collection_transactions': 0, 'total_ci_assignments': 0, 'total_report_exports': 0, 'total_pending_account_upgrade': 0, 'monthly_series': <dynamic>[], 'loan_status_breakdown': <String, dynamic>{}, 'pending_bucket': 0};
    } else if (path.contains('payments-view')) {
      return {'data': [], 'total': 0, 'page': 1, 'limit': 20, 'totalPages': 0};
    } else if (path.contains('collections-view')) {
      return {'data': [], 'total': 0, 'page': 1, 'limit': 20, 'totalPages': 0};
    } else if (path.contains('ci-view')) {
      return {'data': [], 'total': 0, 'page': 1, 'limit': 20, 'totalPages': 0};
    } else if (path.contains('disbursements-view')) {
      return {'data': [], 'total': 0, 'page': 1, 'limit': 20, 'totalPages': 0};
    } else if (path.contains('reports-view')) {
      return {'data': []};
    } else if (path.contains('system-view')) {
      return {'configs': []};
    } else if (path.contains('notifications-view')) {
      return {'data': [], 'unread_count': 0, 'total': 0};
    } else if (path.contains('location-manage')) {
      return {'riders': []};
    } else if (path.contains('in-office-view')) {
      return {'data': []};
    } else if (path.contains('kyc-view')) {
      return {'data': [], 'total': 0, 'totalPages': 0};
    } else {
      return {'data': []};
    }
  }

  @override
  Future<Response> get(String path, {Map<String, dynamic>? queryParams}) async {
    lastPath = path;
    lastMethod = 'GET';
    lastQuery = queryParams;
    return Response(requestOptions: RequestOptions(path: path), data: _mockGetData(path), statusCode: 200);
  }

  @override
  Future<Response> post(String path, {dynamic data, Map<String, String>? headers}) async {
    lastPath = path;
    lastMethod = 'POST';
    lastData = data;
    if (path.contains('auth-login')) {
      return Response(requestOptions: RequestOptions(path: path), data: {'access_token': 'tok', 'refresh_token': 'ref', 'user': {'id': 'u1', 'role': 'employee', 'email': 'a@b.com', 'first_name': 'A', 'last_name': 'B', 'force_password_change': false}}, statusCode: 200);
    }
    return Response(requestOptions: RequestOptions(path: path), data: {'success': true}, statusCode: 200);
  }

  @override
  Future<Response> patch(String path, {dynamic data, Map<String, String>? headers}) async {
    lastPath = path;
    lastMethod = 'PATCH';
    lastData = data;
    return Response(requestOptions: RequestOptions(path: path), data: {'success': true}, statusCode: 200);
  }

  @override
  Future<Response> delete(String path, {dynamic data}) async {
    lastPath = path;
    lastMethod = 'DELETE';
    lastData = data;
    return Response(requestOptions: RequestOptions(path: path), data: {'success': true}, statusCode: 200);
  }

  @override
  Future<Response> postWithIdempotency(String path, {required data, required String idempotencyKey}) async {
    lastPath = path;
    lastMethod = 'POST';
    lastData = data;
    return Response(requestOptions: RequestOptions(path: path), data: {'success': true}, statusCode: 200);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('REST API debug — all datasources use correct HTTP method + path', () {
    late FakeDioClient fake;
    setUp(() => fake = FakeDioClient());

    test('AuthRemoteDataSource.login posts to auth-login?fn=login', () async {
      final ds = AuthRemoteDataSource(fake);
      await ds.login(email: 'a@b.com', password: 'pass');
      expect(fake.lastPath, ApiEndpoints.authLogin);
      expect(fake.lastMethod, 'POST');
    });

    test('UserRemoteDataSource.getUsers GETs users-admin?fn=get-list', () async {
      final ds = UserRemoteDataSource(fake);
      await ds.getUsers(role: 'rider', page: 1);
      expect(fake.lastPath, ApiEndpoints.usersGetList);
      expect(fake.lastMethod, 'GET');
      expect(fake.lastQuery?['role'], 'rider');
    });

    test('LoanRemoteDataSource.getLoanList GETs loans-view?fn=get-list', () async {
      final ds = LoanRemoteDataSource(fake);
      await ds.getLoanList(status: 'pending', page: 1);
      expect(fake.lastPath, ApiEndpoints.loansGetList);
      expect(fake.lastQuery?['status'], 'pending');
    });

    test('KpiRemoteDataSource.getHeadManagerKpi GETs kpi-view?fn=head-manager', () async {
      final ds = KpiRemoteDataSource(fake);
      await ds.getHeadManagerKpi();
      expect(fake.lastPath, ApiEndpoints.kpiHeadManager);
      expect(fake.lastMethod, 'GET');
    });

    test('CollectionRemoteDataSource.getCollectionList GETs collections-view?fn=get-list', () async {
      final ds = CollectionRemoteDataSource(fake);
      await ds.getCollectionList(status: 'assigned');
      expect(fake.lastPath, ApiEndpoints.collectionsGetList);
    });

    test('CiRemoteDataSource.getCiList GETs ci-view?fn=get-list', () async {
      final ds = CiRemoteDataSource(fake);
      await ds.getCiList(status: 'assigned');
      expect(fake.lastPath, ApiEndpoints.ciGetList);
    });

    test('PaymentRemoteDataSource.getPaymentList GETs payments-view?fn=get-list', () async {
      final ds = PaymentRemoteDataSource(fake);
      await ds.getPaymentList(method: 'office_cash');
      expect(fake.lastPath, ApiEndpoints.paymentsGetList);
    });

    test('DisbursementRemoteDataSource.getDisbursementList GETs disbursements-view', () async {
      final ds = DisbursementRemoteDataSource(fake);
      await ds.getDisbursementList(status: 'pending');
      expect(fake.lastPath, ApiEndpoints.disbursementsGetList);
    });

    test('NotificationRemoteDataSource.getList GETs notifications-view', () async {
      final ds = NotificationRemoteDataSource(fake);
      await ds.getList(page: 1);
      expect(fake.lastPath, ApiEndpoints.notificationsGetList);
    });

    test('AuditRemoteDataSource.getAuditLogs GETs audit-get-logs', () async {
      final ds = AuditRemoteDataSource(fake);
      await ds.getAuditLogs(page: 1);
      expect(fake.lastPath, ApiEndpoints.auditGetLogs);
    });

    test('LocationRemoteDataSource.getTrackedRiders GETs location-manage?fn=list-tracked', () async {
      final ds = LocationRemoteDataSource(fake);
      await ds.getTrackedRiders();
      expect(fake.lastPath, ApiEndpoints.locationListTracked);
    });

    test('AccountUpgradeRemoteDataSource.getList GETs kyc-view?fn=get-list', () async {
      final ds = AccountUpgradeRemoteDataSource(fake);
      await ds.getList(page: 1);
      expect(fake.lastPath, ApiEndpoints.accountUpgradeGetList);
    });

    test('InOfficeRemoteDataSource.getList GETs in-office-view?fn=get-list', () async {
      final ds = InOfficeRemoteDataSource(fake);
      await ds.getList(page: 1);
      expect(fake.lastPath, ApiEndpoints.inOfficeGetList);
    });

    test('ReportRemoteDataSource.getReportTemplates GETs reports-view?fn=get-list', () async {
      final ds = ReportRemoteDataSource(fake);
      await ds.getReportTemplates();
      expect(fake.lastPath, ApiEndpoints.reportsGetList);
    });

    test('SystemRemoteDataSource.getSystemConfig GETs system-view?fn=get-config', () async {
      final ds = SystemRemoteDataSource(fake);
      await ds.getSystemConfig();
      expect(fake.lastPath, ApiEndpoints.systemGetConfig);
    });

    test('All ApiEndpoints are well-formed', () {
      final all = [
        ApiEndpoints.authLogin,
        ApiEndpoints.authRegister,
        ApiEndpoints.authRefreshSession,
        ApiEndpoints.usersGetList,
        ApiEndpoints.usersArchive,
        ApiEndpoints.loansGetList,
        ApiEndpoints.loansApprove,
        ApiEndpoints.ciGetList,
        ApiEndpoints.ciAssign,
        ApiEndpoints.collectionsGetList,
        ApiEndpoints.collectionsAssign,
        ApiEndpoints.paymentsGetList,
        ApiEndpoints.paymentsRecordOffice,
        ApiEndpoints.disbursementsGetList,
        ApiEndpoints.locationListTracked,
        ApiEndpoints.notificationsGetList,
        ApiEndpoints.reportsGetList,
        ApiEndpoints.kpiHeadManager,
        ApiEndpoints.auditGetLogs,
      ];
      for (final ep in all) {
        expect(ep, isNotEmpty);
        expect(ep.contains('?fn=') || ep.startsWith('system-update'), isTrue, reason: ep);
      }
    });
  });
}

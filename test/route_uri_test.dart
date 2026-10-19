// test/route_uri_test.dart
//
// Bawat tab ng Loan Records (HM at Employee) ay may SARILING URI para
// deep-linkable/refresh-safe. Sinusuri dito ang exact paths, ang pagka-register
// nila BAGO ang `:id` route (kung hindi, masasapol sila ng details route), at
// ang legacy redirects para hindi mabreak ang lumang link.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readNormalized(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('Loan Records URIs', () {
    late String routes;
    late String router;

    setUpAll(() {
      routes = readNormalized('lib/core/constants/route_constants.dart');
      router = readNormalized('lib/core/router/app_router.dart');
    });

    test('HM: /hm/loan-records + sariling URI kada tab', () {
      expect(routes, contains("hmLoanApplications = '/hm/loan-records'"));
      expect(routes,
          contains("hmLoanApplicationsInOffice =\n      '/hm/loan-records/in-office'"));
      expect(routes,
          contains("hmLoanApplicationsDisbursements =\n      '/hm/loan-records/disbursements'"));
      // "Previous Loan" tab — dating `/history`, `/previous-loan` na ngayon.
      expect(
          routes,
          contains("hmLoanApplicationsHistory =\n"
              "      '/hm/loan-records/previous-loan'"));
      expect(
          routes,
          contains("hmLoanApplicationsHistoryLegacy =\n"
              "      '/hm/loan-records/history'"));
      expect(routes,
          contains("hmLoanRecordsOngoing = '/hm/loan-records/ongoing'"));
      expect(routes,
          contains("hmLoanRecordsCompleted = '/hm/loan-records/completed'"));
      expect(routes,
          contains("hmLoanRecordsPipeline =\n      '/hm/loan-records/pipeline/:status'"));
      expect(routes,
          contains("hmLoanApplicationDetails = '/hm/loan-records/:id'"));
    });

    test('Employee: /employee/loan-records + parehong tabs', () {
      expect(routes, contains("empLoans = '/employee/loan-records'"));
      expect(routes,
          contains("empLoansInOffice = '/employee/loan-records/in-office'"));
      expect(routes,
          contains("empLoansDisbursements =\n      '/employee/loan-records/disbursements'"));
      expect(
          routes,
          contains("empLoansHistory =\n"
              "      '/employee/loan-records/previous-loan'"));
      expect(
          routes,
          contains("empLoansHistoryLegacy =\n"
              "      '/employee/loan-records/history'"));
      expect(routes,
          contains("empLoansOngoing = '/employee/loan-records/ongoing'"));
      expect(routes,
          contains("empLoansCompleted = '/employee/loan-records/completed'"));
      expect(routes,
          contains("empLoansPipeline =\n      '/employee/loan-records/pipeline/:status'"));
    });

    test('Employee tabs ay EMPLOYEE paths — hindi HM (dashboard bug)', () {
      final src = readNormalized(
          'lib/presentation/features/employee/loans/screens/emp_loan_applications_screen.dart');
      // Kapag HM path ang ginamit mula sa employee session, nire-redirect ng
      // role guard sa dashboard — kaya kailangang employee constants.
      expect(src, isNot(contains('RouteConstants.hmLoanRecords')));
      expect(src, contains('RouteConstants.empLoansOngoing'));
      expect(src, contains('RouteConstants.empLoansCompleted'));
      expect(src, contains('RouteConstants.empLoansPipeline'));
    });

    test('legacy paths ay may redirect (hindi 404)', () {
      expect(routes,
          contains("hmLoanApplicationsLegacy = '/hm/loan-applications'"));
      expect(routes,
          contains("empLoansLegacy = '/employee/loans'"));
      // Nakarehistro ang redirect routes sa router.
      expect(router, contains('RouteConstants.hmLoanApplicationsLegacy'));
      expect(router, contains('RouteConstants.empLoansLegacy'));
      // Lumang `/history` URI ng Previous Loan tab → redirect sa bagong path.
      expect(
          router, contains('RouteConstants.hmLoanApplicationsHistoryLegacy'));
      expect(router, contains('RouteConstants.empLoansHistoryLegacy'));
    });

    test('static tab paths ay NAUNA sa :id details routes', () {
      for (final pair in [
        [
          'RouteConstants.hmLoanApplicationsInOffice',
          'RouteConstants.hmLoanApplicationDetails',
        ],
        [
          'RouteConstants.hmLoanRecordsOngoing',
          'RouteConstants.hmLoanApplicationDetails',
        ],
        [
          'RouteConstants.hmLoanApplicationsHistory',
          'RouteConstants.hmLoanApplicationDetails',
        ],
        [
          'RouteConstants.hmLoanApplicationsHistoryLegacy',
          'RouteConstants.hmLoanApplicationDetails',
        ],
        [
          'RouteConstants.hmLoanRecordsPipeline',
          'RouteConstants.hmLoanApplicationDetails',
        ],
        [
          'RouteConstants.empLoansInOffice',
          'RouteConstants.empLoanApplicationDetails',
        ],
        [
          'RouteConstants.empLoansHistory',
          'RouteConstants.empLoanApplicationDetails',
        ],
        [
          'RouteConstants.empLoansHistoryLegacy',
          'RouteConstants.empLoanApplicationDetails',
        ],
        [
          'RouteConstants.empLoansPipeline',
          'RouteConstants.empLoanApplicationDetails',
        ],
      ]) {
        final tabIdx = router.indexOf(pair[0]);
        final detailsIdx = router.indexOf(pair[1]);
        expect(tabIdx, greaterThan(-1), reason: '${pair[0]} hindi naka-register');
        expect(detailsIdx, greaterThan(-1),
            reason: '${pair[1]} hindi naka-register');
        expect(tabIdx, lessThan(detailsIdx),
            reason: '${pair[0]} dapat mauna sa ${pair[1]}');
      }
    });
  });
}

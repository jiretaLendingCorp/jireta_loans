// test/date_range_filter_test.dart
//
// DATE RANGE FILTER ng Loan Records screen (HM + Employee).
//
// MGA BUG NA NAAYOS
//   • In-Office tab: may napiling petsa sa Filter Date pero WALANG nangyayari —
//     ang `_onDateRangeChanged` ay tumatawag lang ng `hmLoanProvider` /
//     `empLoanProvider`. Ang in-office provider ay walang date fields at hindi
//     rin ipinapasa ang `date_from` / `date_to` sa backend (sinusuportahan naman
//     ito ng `in-office-view?fn=list`).
//   • Disbursements tab (HM): `hmDisbursementProvider.setDateRange` ay may
//     support (at `disbursements-view` ay may `date_from`/`date_to`), pero hindi
//     ito tinatawag ng screen.
//   • Pag-CLEAR ng filter (×): `copyWith(dateFrom: null)` ay `??` ang gamit,
//     kaya `null ?? oldValue` = oldValue — nananatiling filtered ang query
//     (`date_from`/`date_to` ay ipinapadala pa rin) kahit nakita nang walang
//     filter ang UI chip.
//
// Sinusuri ng test na ito ang buong daan: state copyWith → provider →
// datasource params, at ang Manila-day conversion ng SearchDateFilter.

import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/datasources/remote/disbursement_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/in_office_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/loan_remote_datasource.dart';
import 'package:jireta_loans/data/models/disbursement_model.dart';
import 'package:jireta_loans/presentation/features/employee/in_office/providers/emp_in_office_provider.dart';
import 'package:jireta_loans/presentation/features/employee/loans/providers/emp_loan_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/disbursements/providers/hm_disbursement_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/in_office/providers/hm_in_office_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/loans/providers/hm_loan_provider.dart';
import 'package:jireta_loans/presentation/shared/widgets/search_date_filter.dart';

// ── Fakes: itinatala lang ang natanggap na date params ───────────────────────

class _FakeInOfficeDs implements InOfficeRemoteDataSource {
  int calls = 0;
  String? dateFrom;
  String? dateTo;

  @override
  Future<List<Map<String, dynamic>>> getList({
    String? status,
    int page = 1,
    int limit = 20,
    String? dateFrom,
    String? dateTo,
  }) async {
    calls++;
    this.dateFrom = dateFrom;
    this.dateTo = dateTo;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLoanDs implements LoanRemoteDataSource {
  int calls = 0;
  String? dateFrom;
  String? dateTo;

  @override
  Future<Map<String, dynamic>> getList({
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
    String? lenderId,
    String? dateFrom,
    String? dateTo,
  }) async {
    calls++;
    this.dateFrom = dateFrom;
    this.dateTo = dateTo;
    return {'data': const [], 'meta': const {}};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDisbursementDs implements DisbursementRemoteDataSource {
  int calls = 0;
  String? dateFrom;
  String? dateTo;

  @override
  Future<List<DisbursementModel>> getDisbursements({
    String? method,
    String? status,
    String? search,
    String? dateFrom,
    String? dateTo,
    int page = 1,
    int limit = 20,
  }) async {
    calls++;
    this.dateFrom = dateFrom;
    this.dateTo = dateTo;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _from = '2026-08-31T16:00:00.000Z'; // Manila Sep 1, 00:00
const _to = '2026-09-07T15:59:59.999Z'; // Manila Sep 7, 23:59:59.999

void main() {
  group('In-Office tab: date_from/date_to ay ipinapasa sa backend', () {
    test('Head Manager provider', () {
      final ds = _FakeInOfficeDs();
      final notifier = HmInOfficeNotifier(ds, _FakeLoanDs());

      expect(ds.calls, 1, reason: 'initial load');
      expect(ds.dateFrom, isNull);

      notifier.setDateRange(_from, _to);
      expect(ds.dateFrom, _from);
      expect(ds.dateTo, _to);

      // Pag-clear: hindi dapat manatili ang lumang dates sa query.
      notifier.setDateRange(null, null);
      expect(ds.dateFrom, isNull);
      expect(ds.dateTo, isNull);
    });

    test('Employee provider', () {
      final ds = _FakeInOfficeDs();
      final notifier = EmpInOfficeNotifier(ds, _FakeLoanDs());

      notifier.setDateRange(_from, _to);
      expect(ds.dateFrom, _from);
      expect(ds.dateTo, _to);

      notifier.setDateRange(null, null);
      expect(ds.dateFrom, isNull);
      expect(ds.dateTo, isNull);
    });
  });

  group('Disbursements tab: date range ay umabot sa datasource', () {
    test('Head Manager provider', () {
      final ds = _FakeDisbursementDs();
      final notifier = HmDisbursementNotifier(ds);

      notifier.setDateRange(_from, _to);
      expect(ds.dateFrom, _from);
      expect(ds.dateTo, _to);

      notifier.setDateRange(null, null);
      expect(ds.dateFrom, isNull, reason: 'dapat ma-clear ang filter');
      expect(ds.dateTo, isNull);
    });
  });

  group('Loan list: date range ay umabot sa datasource', () {
    test('Head Manager provider', () {
      final ds = _FakeLoanDs();
      final notifier = HmLoanNotifier(ds);

      notifier.setDateRange(_from, _to);
      expect(ds.dateFrom, _from);
      expect(ds.dateTo, _to);

      notifier.setDateRange(null, null);
      expect(ds.dateFrom, isNull, reason: 'dapat ma-clear ang filter');
      expect(ds.dateTo, isNull);
    });

    test('Employee provider', () {
      final ds = _FakeLoanDs();
      final notifier = EmpLoanNotifier(ds);

      notifier.setDateRange(_from, _to);
      expect(ds.dateFrom, _from);
      expect(ds.dateTo, _to);

      notifier.setDateRange(null, null);
      expect(ds.dateFrom, isNull, reason: 'dapat ma-clear ang filter');
      expect(ds.dateTo, isNull);
    });
  });

  group('copyWith: hindi ipinasa ≠ ipinasang null', () {
    test('HmLoanState', () {
      const base = HmLoanState(dateFrom: _from, dateTo: _to);
      // Hindi ipinasa → panatilihin (ginagamit ng search/tab/pagination).
      expect(base.copyWith(search: 'juan').dateFrom, _from);
      // Ipinasang null → i-clear (ginagamit ng pag-alis ng date filter).
      expect(base.copyWith(dateFrom: null, dateTo: null).dateFrom, isNull);
      expect(base.copyWith(dateFrom: null, dateTo: null).dateTo, isNull);
    });

    test('HmDisbursementState', () {
      const base = HmDisbursementState(dateFrom: _from, dateTo: _to);
      expect(base.copyWith(search: 'x').dateTo, _to);
      expect(base.copyWith(dateFrom: null, dateTo: null).dateFrom, isNull);
    });

    test('HmInOfficeState', () {
      const base = HmInOfficeState(dateFrom: _from, dateTo: _to);
      expect(base.copyWith(isLoading: true).dateFrom, _from);
      expect(base.copyWith(dateFrom: null, dateTo: null).dateTo, isNull);
    });

    test('EmpLoanState', () {
      const base = EmpLoanState(dateFrom: _from, dateTo: _to);
      expect(base.copyWith(search: 'x').dateFrom, _from);
      expect(base.copyWith(dateFrom: null, dateTo: null).dateTo, isNull);
    });
  });

  group('SearchDateFilter: Manila day bounds', () {
    test('fromParam = Manila 00:00 ng piniling araw', () {
      final parsed =
          DateTime.parse(SearchDateFilter.fromParam(DateTime(2026, 9, 1)));
      expect(parsed.toUtc(), DateTime.utc(2026, 8, 31, 16));
    });

    test('toParam = Manila 23:59:59.999 ng piniling araw', () {
      final parsed =
          DateTime.parse(SearchDateFilter.toParam(DateTime(2026, 9, 7)));
      expect(parsed.toUtc(), DateTime.utc(2026, 9, 7, 15, 59, 59, 999));
    });
  });
}

// test/fcm_route_for_test.dart
//
// Notification deep-link routing: ang `loan_applied` (New Loan Application)
// ay dapat bumukas sa Loan Application Details (review screen), hindi sa
// Loan Details ng existing/active loan.
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/services/fcm_service.dart';

void main() {
  group('FcmService.routeFor — loan_applied', () {
    test('HM: Loan Application Details, hindi Loan Details', () {
      final path = FcmService.routeFor(
        type: 'loan_applied',
        referenceId: 'loan-123',
        role: 'head_manager',
      );

      expect(path, '/hm/loan-records/loan-123');
      expect(path, isNot('/hm/loans/loan-123'));
    });

    test('Employee: Loan Application Details, hindi Loan Details', () {
      final path = FcmService.routeFor(
        type: 'loan_applied',
        referenceId: 'loan-123',
        role: 'employee',
      );

      expect(path, '/employee/loan-records/loan-123');
      expect(path, isNot('/employee/loan-details/loan-123'));
    });
  });

  group('FcmService.routeFor — ibang loan notifications', () {
    test('HM: penalty_applied ay nananatili sa Loan Details', () {
      final path = FcmService.routeFor(
        type: 'penalty_applied',
        referenceId: 'loan-123',
        role: 'head_manager',
      );

      expect(path, '/hm/loans/loan-123');
    });
  });
}

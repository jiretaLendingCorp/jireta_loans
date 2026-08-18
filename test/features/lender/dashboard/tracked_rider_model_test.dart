import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/models/tracked_rider_model.dart';

void main() {
  group('TrackedRiderModel.fromJson', () {
    test('maps every field from a full row', () {
      final model = TrackedRiderModel.fromJson({
        'rider_id': 'r-1',
        'rider_name': 'Juan Dela Cruz',
        'assignment_type': 'collection',
        'assignment_id': 'ca-1',
        'assignment_status': 'accepted',
        'loan_id': 'l-1',
        'loan_number': 'L-2026-0001',
        'latitude': 14.5995,
        'longitude': 120.9842,
        'accuracy': 12.5,
        'location_updated_at': '2026-08-18T10:30:00.000Z',
        'is_stale': false,
      });

      expect(model.riderId, 'r-1');
      expect(model.riderName, 'Juan Dela Cruz');
      expect(model.assignmentType, 'collection');
      expect(model.assignmentId, 'ca-1');
      expect(model.assignmentStatus, 'accepted');
      expect(model.loanId, 'l-1');
      expect(model.loanNumber, 'L-2026-0001');
      expect(model.latitude, 14.5995);
      expect(model.longitude, 120.9842);
      expect(model.accuracy, 12.5);
      expect(model.locationUpdatedAt, DateTime.parse('2026-08-18T10:30:00.000Z'));
      expect(model.isStale, isFalse);
      expect(model.hasLocation, isTrue);
    });

    test('tolerates missing location fields', () {
      final model = TrackedRiderModel.fromJson({
        'rider_id': 'r-2',
        'rider_name': 'Maria Santos',
        'assignment_type': 'ci',
        'assignment_id': 'ci-1',
        'assignment_status': 'in_progress',
        'loan_id': 'l-2',
        'loan_number': 'L-2026-0002',
        'latitude': null,
        'longitude': null,
        'is_stale': true,
      });

      expect(model.latitude, isNull);
      expect(model.longitude, isNull);
      expect(model.accuracy, isNull);
      expect(model.locationUpdatedAt, isNull);
      expect(model.isStale, isTrue);
      expect(model.hasLocation, isFalse);
    });

    test('parses disbursement rider deliveries as stale when no fix', () {
      final model = TrackedRiderModel.fromJson({
        'rider_id': 'r-3',
        'assignment_type': 'disbursement',
        'assignment_status': 'pending',
        'loan_number': 'L-2026-0003',
      });
      expect(model.assignmentType, 'disbursement');
      expect(model.hasLocation, isFalse);
    });
  });
}

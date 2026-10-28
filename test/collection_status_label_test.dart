// test/collection_status_label_test.dart
//
// Ang status column ng Collections list (HM at Employee) ay dating hilaw na
// `status` na basta naka-capitalize — kaya "Failed" ang lumalabas sa isang
// koleksyong hindi nakolekta. Proper name na ngayon: "Uncollected", pareho
// sa rider side at sa History.
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/presentation/shared/utils/collection_status_label.dart';

void main() {
  test('failed → Uncollected, hindi "Failed"', () {
    expect(collectionStatusLabel('failed'), 'Uncollected');
    expect(collectionStatusLabel('FAILED'), 'Uncollected');
  });

  test('buong status ng collection assignment ay may proper name', () {
    const expected = {
      'pending': 'Pending',
      'requested': 'Requested',
      'assigned': 'Assigned',
      'accepted': 'Accepted',
      'in_progress': 'In Progress',
      'pending_approval': 'Pending Approval',
      'completed': 'Completed',
      'rejected': 'Rejected',
      'declined': 'Declined',
      'cancelled': 'Cancelled',
      'expired': 'Expired',
      'failed': 'Uncollected',
    };
    expected.forEach((status, label) {
      expect(collectionStatusLabel(status), label, reason: status);
    });
  });

  test('hindi kilalang status: capitalize pa rin ang bawat salita', () {
    expect(collectionStatusLabel('on_hold'), 'On Hold');
    expect(collectionStatusLabel(''), '');
  });

  group('collectionCloseReason — bakit na-failed', () {
    test('48h request expiry', () {
      expect(
        collectionCloseReason('failed', 'expired: no action within 48h'),
        'No action within 48h',
      );
    });

    test('overdue auto-expiry (may naunang note)', () {
      expect(
        collectionCloseReason(
            'failed', 'Borrower not home [auto-expired: overdue]'),
        'Overdue — auto-closed',
      );
    });

    test('walang system note → walang haka-hakang dahilan', () {
      expect(collectionCloseReason('failed', null), isNull);
      expect(collectionCloseReason('failed', 'Borrower not home'), isNull);
    });

    test('hindi failed/expired → walang dahilan', () {
      expect(collectionCloseReason('completed', 'expired: no action within 48h'),
          isNull);
      expect(collectionCloseReason('rejected', 'overdue'), isNull);
    });
  });
}

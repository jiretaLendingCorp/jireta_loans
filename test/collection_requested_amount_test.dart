// test/collection_requested_amount_test.dart
//
// REGRESSION: "nag request ng amount si lender pero bakit naka default parin"
//
// Nag-request ang lender ng ₱5,000 (partial/advance) pero ₱200 lang ang
// installment na due. Tama ang notification ("requested a rider to collect of
// ₱5,000") pero ₱200.00 pa rin ang nasa AMOUNT column ng HM/Employee
// Collections — dahil `amount_collected ?? loan_schedule.amount_due` lang ang
// binabasa, at hindi kailanman ang `requested_amount`.
//
// Ang tamang order: actual na nakolekta → hininging halaga → installment due.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/models/collection_assignment_model.dart';

const _hmList =
    'lib/presentation/features/head_manager/collections/screens/hm_collection_list_screen.dart';
const _empList =
    'lib/presentation/features/employee/collections/screens/emp_collection_list_screen.dart';
const _hmDetails =
    'lib/presentation/features/head_manager/collections/screens/hm_collection_details_screen.dart';
const _empDetails =
    'lib/presentation/features/employee/collections/screens/emp_collection_details_screen.dart';

String _read(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

void main() {
  group('Collections list: hininging halaga ang ipinapakita', () {
    for (final path in {_hmList, _empList}) {
      final name = path.split('/').last;

      test('$name: `requestedAmount` bago ang `amount_due`', () {
        final src = _read(path);

        // Ang requested amount ay bahagi ng fallback chain.
        expect(src, contains('col.requestedAmount'),
            reason: 'Hindi binabasa ang requested_amount ng assignment');
        // ...at mas nauna kaysa sa installment amount. Kung baliktad, ₱200
        // (default) pa rin ang lumalabas sa isang ₱5,000 na request.
        final requestedIdx = src.indexOf('col.requestedAmount');
        final dueIdx = src.indexOf("(schedule['amount_due']");
        expect(requestedIdx, greaterThan(-1));
        expect(dueIdx, greaterThan(-1));
        expect(requestedIdx, lessThan(dueIdx),
            reason: 'Dapat mauna ang requested amount sa installment amount');
        // Ang actual na nakolekta pa rin ang pinakamataas na priority.
        final collectedIdx = src.indexOf('col.amountCollected');
        expect(collectedIdx, greaterThan(-1));
        expect(collectedIdx, lessThan(requestedIdx));
      });
    }
  });

  group('Collection details: nakikita ang hininging halaga', () {
    for (final path in {_hmDetails, _empDetails}) {
      final name = path.split('/').last;

      test('$name: may "Requested Amount" row', () {
        expect(_read(path), contains("_InfoRow('Requested Amount'"));
      });
    }
  });

  test('CollectionAssignmentModel: nababasa ang requested_amount', () {
    final col = CollectionAssignmentModel.fromJson({
      'id': 'c1',
      'loan_schedule_id': 's1',
      'status': 'requested',
      'collection_type': 'rider',
      'requested_amount': 5000,
      'amount_collected': null,
      'created_at': '2026-10-21T08:00:00.000Z',
      'loan_schedule': {'id': 's1', 'amount_due': 200},
    });

    expect(col.requestedAmount, 5000);
    expect(col.amountCollected, isNull);
  });

  group('expectedAmount / collectibleAmount', () {
    CollectionAssignmentModel build({
      double due = 200,
      double? requested,
      double? collected,
    }) =>
        CollectionAssignmentModel.fromJson({
          'id': 'c1',
          'loan_schedule_id': 's1',
          'status': 'assigned',
          'collection_type': 'rider',
          'requested_amount': requested,
          'amount_collected': collected,
          'created_at': '2026-10-21T08:00:00.000Z',
          'loan_schedule': {'id': 's1', 'amount_due': due},
        });

    test('ang HININGI ng lender ang gamit, hindi ang installment due', () {
      final col = build(requested: 5000);
      expect(col.amountDue, 200, reason: 'installment due pa rin ang ₱200');
      expect(col.expectedAmount, 5000);
      expect(col.collectibleAmount, 5000);
    });

    test('walang hiningi → installment due ang fallback', () {
      final col = build();
      expect(col.expectedAmount, 200);
      expect(col.collectibleAmount, 200);
    });

    test('may nakolekta na → actual na nakolekta ang gamit', () {
      final col = build(requested: 5000, collected: 2500);
      expect(col.expectedAmount, 5000);
      expect(col.collectibleAmount, 2500);
    });
  });

  group('Rider screens: requested amount ang ipinapakita', () {
    const details =
        'lib/presentation/features/rider/collections/screens/rider_collection_details_screen.dart';
    const list =
        'lib/presentation/features/rider/collections/screens/rider_collection_list_screen.dart';
    const record =
        'lib/presentation/features/rider/collections/screens/rider_record_collection_screen.dart';
    const card =
        'lib/presentation/features/rider/collections/widgets/rider_collection_card.dart';

    test('wala nang `Amount Due` na naka-default sa rider screens', () {
      for (final path in {details, list, record, card}) {
        final src = _read(path);
        // Ang halagang ipinapakita ay galing sa requested/collectible amount.
        expect(
          src.contains('expectedAmount') ||
              src.contains('collectibleAmount') ||
              src.contains('requestedAmount'),
          isTrue,
          reason: '$path: hindi ginagamit ang requested amount',
        );
      }
    });
  });
}

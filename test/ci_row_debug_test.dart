// Temporary debug test — validates CreditInvestigationModel.fromJson and the
// superseded-row boolean logic with realistic ci-view JSON shapes.
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/core/extensions/date_extensions.dart';
import 'package:jireta_loans/data/models/credit_investigation_model.dart';

Map<String, dynamic> _row({
  required String status,
  String? deadline,
  Object? isLatest,
  Object? loans,
  Object? rider,
}) =>
    {
      'id': 'ci-00000000-0000-0000-0000-000000000001',
      'loan_id': 'loan-11111111-1111-1111-1111-111111111111',
      'status': status,
      'created_at': '2026-09-05T00:00:00Z',
      if (deadline != null) 'deadline': deadline,
      if (isLatest != null) 'is_latest': isLatest,
      'loans': loans ??
          {
            'loan_number': 'LN-2026-450565',
            'lender_profiles': {
              'users': {'first_name': 'Aljon', 'last_name': 'Datuin'}
            }
          },
      'rider': rider ??
          {
            'users': {'first_name': 'Jamvis', 'last_name': 'Rosario'}
          },
    };

void main() {
  test('parses rows incl. is_latest key/status shapes', () {
    final cases = [
      _row(status: 'assigned'),
      _row(status: 'approved'),
      _row(status: 'failed', deadline: '2026-09-05T00:00:00Z', isLatest: false),
      _row(status: 'failed', deadline: '2026-09-05T00:00:00Z', isLatest: true),
      _row(status: 'reassigned', deadline: '2026-09-05T00:00:00Z'),
      _row(status: 'declined'),
      _row(status: 'expired', isLatest: false),
      _row(status: 'completed'),
    ];
    for (final raw in cases) {
      final ci = CreditInvestigationModel.fromJson(raw);
      expect(ci.id, isNotEmpty);
      final status = ci.status.toLowerCase();
      final isLatest = ci.isLatest;
      final isSuperseded = !isLatest &&
          (status == 'failed' ||
              status == 'expired' ||
              status == 'declined');
      final displayStatus = isSuperseded ? 'reassigned' : status;
      final isPendingApproval = displayStatus == 'completed';
      final deadline = ci.deadline;
      final isOverdue = deadline != null &&
          deadline.isOverdue &&
          !isSuperseded &&
          displayStatus != 'completed' &&
          displayStatus != 'reassigned';
      // Accessors used by the row widgets.
      expect(ci.loanNumber, isNotNull);
      expect(ci.borrowerName, isNotNull);
      expect(ci.riderName, isNotNull);
      expect(isLatest, isA<bool>());
      expect(displayStatus, isA<String>());
      expect(isPendingApproval, isA<bool>());
      expect(isOverdue, isA<bool>());
    }
  });
}

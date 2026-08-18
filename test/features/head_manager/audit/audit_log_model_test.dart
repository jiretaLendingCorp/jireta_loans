import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/models/audit_log_model.dart';

void main() {
  group('AuditLogModel.fromJson', () {
    test('maps every field from a full row', () {
      final model = AuditLogModel.fromJson({
        'id': 'aaa-bbb',
        'action': 'loan_approve',
        'performed_by': 'u-1',
        'table_name': 'loans',
        'record_id': 'r-1',
        'old_values': {'status': 'pending'},
        'new_values': {'status': 'approved'},
        'ip_address': '127.0.0.1',
        'created_at': '2026-08-01T10:30:00.000Z',
        'performed_by_user': {
          'first_name': 'Jane',
          'last_name': 'Doe',
          'roles': {'name': 'head_manager'},
        },
      });

      expect(model.id, 'aaa-bbb');
      expect(model.action, 'loan_approve');
      expect(model.performedBy, 'u-1');
      expect(model.tableName, 'loans');
      expect(model.recordId, 'r-1');
      expect(model.oldValues, {'status': 'pending'});
      expect(model.newValues, {'status': 'approved'});
      expect(model.ipAddress, '127.0.0.1');
      expect(model.createdAt, DateTime.parse('2026-08-01T10:30:00.000Z'));
      expect(model.performedByName, 'Jane Doe');
      expect(model.actionLabel, 'LOAN APPROVE');
    });

    test('tolerates missing optional values', () {
      final model = AuditLogModel.fromJson({
        'id': 'x',
        'action': 'payment_recorded',
        'created_at': '2026-08-01T10:30:00.000Z',
      });
      expect(model.performedBy, isNull);
      expect(model.tableName, isNull);
      expect(model.recordId, isNull);
      expect(model.oldValues, isNull);
      expect(model.newValues, isNull);
      expect(model.performedByUser, isNull);
      expect(model.performedByName, 'System');
    });

    test('falls back to now when created_at is missing', () {
      final before = DateTime.now().subtract(const Duration(seconds: 5));
      final model = AuditLogModel.fromJson({'id': 'y', 'action': 'login'});
      expect(model.createdAt.isAfter(before), isTrue);
    });

    test('system user renders as System', () {
      final model = AuditLogModel.fromJson({
        'id': 'z',
        'action': 'xendit_payment_verified',
        'performed_by_user': null,
        'created_at': '2026-08-01T10:30:00.000Z',
      });
      expect(model.performedByName, 'System');
    });
  });
}

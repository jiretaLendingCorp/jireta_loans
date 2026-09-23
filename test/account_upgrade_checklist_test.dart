// test/account_upgrade_checklist_test.dart
// Ang reviewer screens (HM/Employee) ay nagpapakita na ngayon ng LAHAT ng
// inaasahang dokumento — "Not submitted" kapag wala sa DB. Dati, tahimik na
// nawawala ang tile (hal. Face Recognition na na-skip sa web/desktop) kaya
// hindi malalaman ng reviewer kung kulang ito.
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/utils/account_upgrade_checklist.dart';

Map<String, dynamic> _doc(String type, {String status = 'pending'}) =>
    {'document_type': type, 'status': status, 'file_url': '$type.jpg'};

void main() {
  group('buildAccountUpgradeChecklist', () {
    test('laging kasama ang lahat ng inaasahang dokumento', () {
      final items = buildAccountUpgradeChecklist([]);
      expect(
        items.map((i) => i.type).toList(),
        ['valid_id', 'selfie', 'mayors_permit', 'lender_signature', 'face_recognition'],
      );
      expect(items.every((i) => !i.submitted), isTrue);
      // Required lang: valid_id at mayors_permit (Business Permit). Ang
      // selfie, lender_signature, at face_recognition ay optional.
      expect(items.map((i) => i.missingRequired).toList(),
          [true, false, true, false, false]);
    });

    test('nandiyan pa rin ang Face Recognition kahit wala sa DB (optional)', () {
      // Ito ang totoong kaso sa screenshot: may ID/permit/signature
      // pero walang face_recognition row.
      final items = buildAccountUpgradeChecklist([
        _doc('valid_id', status: 'verified'),
        _doc('selfie', status: 'verified'),
        _doc('mayors_permit', status: 'verified'),
        _doc('lender_signature', status: 'verified'),
      ]);

      final face = items.firstWhere((i) => i.type == 'face_recognition');
      expect(face.submitted, isFalse);
      expect(face.doc, isNull);
      // Hindi na required ang Face Recognition — supporting document na lang.
      expect(face.required, isFalse);
      expect(items.length, 5);
    });

    test('isang tile lang ang valid_id front + back', () {
      final items = buildAccountUpgradeChecklist([
        _doc('valid_id'),
        _doc('valid_id_back'),
      ]);
      expect(items.where((i) => i.type.startsWith('valid_id')).length, 1);
      expect(items.firstWhere((i) => i.type == 'valid_id').submitted, isTrue);
    });

    test('ang hindi inaasahang type (walk-in docs) ay naipapakita pa rin', () {
      final items = buildAccountUpgradeChecklist([
        _doc('itr'),
        _doc('business_registration'),
        _doc('co_maker'),
      ]);
      expect(items.length, 5 + 3);
      final itr = items.firstWhere((i) => i.type == 'itr');
      expect(itr.submitted, isTrue);
      expect(itr.required, isFalse);
      // Nasa dulo sila, hindi nakikialam sa order ng checklist.
      expect(items[5].type, 'itr');
    });

    test('status ay lowercase para hindi sumabit ang paghahambing', () {
      final items = buildAccountUpgradeChecklist([_doc('valid_id', status: 'Pending')]);
      expect(items.firstWhere((i) => i.type == 'valid_id').status, 'pending');
      final empty = buildAccountUpgradeChecklist([]);
      expect(empty.first.status, '');
    });

    test('ang duplicate type ay isang tile lang (unang row ang panalo)', () {
      final items = buildAccountUpgradeChecklist([
        _doc('mayors_permit', status: 'pending'),
        _doc('mayors_permit', status: 'verified'),
      ]);
      expect(items.where((i) => i.type == 'mayors_permit').length, 1);
      expect(items.firstWhere((i) => i.type == 'mayors_permit').status, 'pending');
    });

    test('hindi pumapasok ang malformed / walang type na row', () {
      final items = buildAccountUpgradeChecklist([
        'not-a-map',
        {'status': 'verified'},
        _doc('valid_id'),
      ]);
      expect(items.length, 5);
      expect(items.firstWhere((i) => i.type == 'valid_id').submitted, isTrue);
    });
  });
}

// test/people_email_edit_test.dart
//
// EMAIL SA PEOPLE (Edit User modal)
//
// Dati, read-only ang Email para sa lahat maliban sa head manager — kaya kahit
// blangko o mali ang naka-record na email ng lender/rider, hindi ito maitatama
// ng staff. Ngayon, editable na ito sa lahat ng role at ipinapadala lang kapag
// talagang binago (para hindi mabura ang email o ang internal na
// `@jireta.temp` credential kapag hindi ginalaw).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _editUserModal = 'lib/presentation/shared/widgets/edit_user_modal.dart';
const _empEditLenderModal =
    'lib/presentation/features/employee/lenders/widgets/emp_edit_lender_modal.dart';

String _read(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

void main() {
  group('People: na-e-edit ang email', () {
    test('Edit User modal: editable ang email sa lahat ng role', () {
      final src = _read(_editUserModal);

      expect(src, contains('bool get _canEditEmail => true;'),
          reason: 'dati: head manager lang ang puwedeng mag-edit ng email');
      expect(src, isNot(contains('_canEditEmail => widget.initialRole')));
      expect(src, contains("'email': _emailCtrl.text.trim()"));
      expect(src, contains('@jireta.temp'),
          reason: 'hindi dapat ipakita ang internal credential bilang email');
      expect(src, contains('Enter a valid email address'));
    });

    test('Employee Edit Lender: may email field din', () {
      final src = _read(_empEditLenderModal);

      expect(src, contains('_emailCtrl'));
      expect(src, contains("labelText: 'Email'"));
      expect(src, contains("'email': _emailCtrl.text.trim()"));
      expect(src, contains('@jireta.temp'));
    });
  });
}

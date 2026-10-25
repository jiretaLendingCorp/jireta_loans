// test/emp_profile_email_editable_test.dart
//
// Source guard: ang Email field sa Edit Profile ng employee (My Profile) ay
// DAPAT ma-edit na. Dati itong `readOnly: true` at wala sa update payload, kaya
// kahit sinusuportahan ng backend ang email change (`users-manage?
// fn=update-profile`: format check, `uq_users_email_lower` uniqueness at GoTrue
// credential sync) ay hindi ito magagamit ng staff.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File(
    'lib/presentation/features/employee/profile/screens/emp_profile_screen.dart',
  ).readAsStringSync();

  int emailFieldStart() {
    final i = src.indexOf("controller: email,");
    expect(i, greaterThan(0), reason: 'Email field hindi nahanap');
    return i;
  }

  test('hindi na readOnly ang Email field', () {
    final block = src.substring(emailFieldStart(), emailFieldStart() + 400);
    expect(block.contains('readOnly: true'), isFalse,
        reason: 'Binalik ang read-only na Email — hindi na ma-edit ng staff.');
  });

  test('may email format validation ang Email field', () {
    final block = src.substring(emailFieldStart(), emailFieldStart() + 400);
    expect(block.contains('AppValidators.email'), isTrue);
  });

  test('ipinapadala ang email sa update payload kapag nagbago', () {
    expect(src.contains("'email': AppValidators.normalizeEmail(email.text)"),
        isTrue);
    // Idempotent: hindi ito ipinapadala kung pareho lang sa dating email, para
    // hindi mag-trigger ng GoTrue sync sa bawat "Save Changes".
    expect(
        src.contains('AppValidators.normalizeEmail(user.email)'), isTrue);
  });
}

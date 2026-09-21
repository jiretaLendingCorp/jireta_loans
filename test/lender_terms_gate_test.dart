// test/lender_terms_gate_test.dart
//
// Ang one-time Terms & Conditions + "Fill In Information" na modal ay dapat
// lumabas LANG sa mga lender na wala pang account record. Ang bug na
// sinasaklaw nito:
//
//   * nag-switch ng account ang user (MPIN screen → "Use another number" →
//     OTP ng ibang numero), at
//   * may existing nang account ang nalipatan (may pangalan na sa file),
//
// pero dahil STUB lang ang user na itinatakda sa auth state kapag nag-unlock
// gamit ang MPIN (walang `firstName` / `lastName`), lumalabas pa rin ang Terms
// & Conditions at ang "Fill In Information" — imbes na deretso sa Home.
//
// Ang `lenderHasExistingAccount` (na siyang basehan ng dashboard) ay dapat
// tumingin sa TOTOONG profile na galing sa server, kaya ang mga test na ito ay
// nagpapatunay na ang desisyon ay hindi nakasalalay sa stub ng auth state.
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/lender/dashboard/screens/lender_dashboard_screen.dart';

UserModel _user({
  String firstName = '',
  String lastName = '',
  String? accountUpgradeStatus,
}) =>
    UserModel(
      id: 'u-1',
      role: 'lender',
      firstName: firstName,
      lastName: lastName,
      accountStatus: 'active',
      forcePasswordChange: false,
      accountUpgradeStatus: accountUpgradeStatus,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('lenderHasExistingAccount', () {
    test('existing account na may pangalan sa file → hindi na lalabas ang Terms',
        () {
      final user = _user(firstName: 'Juan', lastName: 'Dela Cruz');
      expect(lenderHasExistingAccount(user), isTrue);
      expect(lenderHasNameOnFile(user), isTrue);
    });

    test('bagong account (walang pangalan at walang upgrade record) → lalabas',
        () {
      final user = _user();
      expect(lenderHasExistingAccount(user), isFalse);
    });

    test('may account-upgrade record kahit walang pangalan → existing account',
        () {
      for (final status in const [
        'submitted',
        'under_review',
        'verified',
        'rejected',
      ]) {
        final user = _user(accountUpgradeStatus: status);
        expect(lenderHasExistingAccount(user), isTrue,
            reason: 'Dapat ituring na existing ang status=$status');
      }
    });

    test('hindi binibilang ang hindi kilalang upgrade status', () {
      final user = _user(accountUpgradeStatus: 'none');
      expect(lenderHasExistingAccount(user), isFalse);
    });

    test('puwang lang o kalahating pangalan ay hindi sapat', () {
      expect(lenderHasExistingAccount(_user(firstName: '   ', lastName: '  ')),
          isFalse);
      expect(lenderHasExistingAccount(_user(firstName: 'Juan')), isFalse);
      expect(lenderHasExistingAccount(_user(lastName: 'Dela Cruz')), isFalse);
    });

    test('null (hal. wala pang profile) → hindi ituturing na existing', () {
      expect(lenderHasExistingAccount(null), isFalse);
    });

    test('hindi naapektuhan ng malalaking titik ang upgrade status', () {
      expect(
        lenderHasExistingAccount(_user(accountUpgradeStatus: 'UNDER_REVIEW')),
        isTrue,
      );
    });
  });
}

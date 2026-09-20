// test/staff_onboarding_test.dart
//
// Regression tests para sa "laging lumalabas ang Personal Details dialog"
// bug ng head manager / employee.
//
// Dalawang bagay ang sinusuri:
//   1. Ang flatten ng role-specific profile — dati ay NESTED ang gender /
//      civil_status / date_of_birth sa tugon ng server pero TOP-LEVEL ang
//      binabasa ng UserModel, kaya laging null ang mga ito at hindi malaman
//      kung kumpleto na ang account.
//   2. Ang "kumpleto na ba?" check na humaharang sa dialog — isang beses lang
//      dapat itong lumabas, kapag bagong gawa pa lang ang account.
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/shared/widgets/profile/personal_details_dialog.dart';

void main() {
  group('flattenRoleProfile (get-profile → UserModel)', () {
    test('inilalabas sa top level ang employee_profiles (Map)', () {
      final row = <String, dynamic>{
        'id': 'u-1',
        'first_name': 'Juan',
        'last_name': 'Dela Cruz',
        'employee_profiles': {
          'position': 'Head Manager',
          'gender': 'male',
          'civil_status': 'single',
          'date_of_birth': '1990-05-01',
        },
      };

      final flat = UserRemoteDataSource.flattenRoleProfile(row);
      expect(flat['gender'], 'male');
      expect(flat['civil_status'], 'single');
      expect(flat['date_of_birth'], '1990-05-01');
      expect(flat['position'], 'Head Manager');
      // Nananatili pa rin ang nested key para sa mga caller na nagbabasa nito.
      expect(flat['employee_profiles'], isA<Map>());
    });

    test('ginagamot ang List na embed (unang row)', () {
      final row = <String, dynamic>{
        'id': 'u-2',
        'employee_profiles': [
          {'gender': 'female', 'civil_status': 'married'},
        ],
      };
      final flat = UserRemoteDataSource.flattenRoleProfile(row);
      expect(flat['gender'], 'female');
      expect(flat['civil_status'], 'married');
    });

    test('hindi pinapatungan ang existing na top-level value', () {
      final row = <String, dynamic>{
        'id': 'u-3',
        'gender': 'male',
        'employee_profiles': {'gender': 'female'},
      };
      expect(UserRemoteDataSource.flattenRoleProfile(row)['gender'], 'male');
    });

    test('hindi sumasabog kapag null o kulang ang embed', () {
      final flat = UserRemoteDataSource.flattenRoleProfile(<String, dynamic>{
        'id': 'u-4',
        'employee_profiles': null,
      });
      expect(flat['id'], 'u-4');
      expect(flat['gender'], isNull);
    });
  });

  group('staffProfileDetailsComplete', () {
    UserModel staff({
      String first = 'Juan',
      String last = 'Dela Cruz',
      String? phone = '09171234567',
      String? gender = 'male',
      String? civilStatus = 'single',
      bool noDob = false,
    }) {
      return UserModel(
        id: 'u-1',
        role: 'head_manager',
        firstName: first,
        lastName: last,
        accountStatus: 'active',
        forcePasswordChange: false,
        createdAt: DateTime(2026, 1, 1),
        phoneNumber: phone,
        gender: gender,
        civilStatus: civilStatus,
        dateOfBirth: noDob ? null : DateTime(1990, 5, 1),
      );
    }

    test('kumpleto kapag puno ang lahat ng required na field', () {
      expect(staffProfileDetailsComplete(staff()), isTrue);
    });

    test('HINDI kumpleto kapag placeholder pa ang pangalan', () {
      // Ito ang estado ng bagong gawang account ("Head Manager" / "Head").
      expect(staffProfileDetailsComplete(staff(first: 'Head', last: 'Manager')),
          isFalse);
      expect(staffProfileDetailsComplete(staff(first: '', last: '')), isFalse);
    });

    test('HINDI kumpleto kapag kulang ang gender / civil status / DOB', () {
      expect(staffProfileDetailsComplete(staff(gender: null)), isFalse);
      expect(staffProfileDetailsComplete(staff(civilStatus: null)), isFalse);
      expect(staffProfileDetailsComplete(staff(noDob: true)), isFalse);
    });

    test('HINDI kumpleto kapag walang numero', () {
      expect(staffProfileDetailsComplete(staff(phone: '')), isFalse);
      expect(staffProfileDetailsComplete(staff(phone: null)), isFalse);
    });
  });
}

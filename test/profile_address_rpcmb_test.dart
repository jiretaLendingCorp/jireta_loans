// test/profile_address_rpcmb_test.dart
//
// ADDRESS SA PEOPLE → DETAILS / EDIT AT SA MGA PROFILE
//
//   • Ang `PhilippinesAddressField` (PSA data via philippines_rpcmb) ay
//     naka-prefill mula sa naka-save na address — kailangan ito ng People →
//     Edit User at ng New Walk-in (in-office) address step.
//   • Ang Region ay HINDI nakaimbak sa `addresses` table (street / barangay /
//     city / province lang), kaya hinahanap ito mula sa city gamit ang PSA
//     data — kung hindi, mali-flag na "incomplete" ang kumpletong address.
//   • Si HM / Employee / Rider ay dapat makita ang SARILING address sa Profile
//     (UserModel.formattedAddress).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philippines_rpcmb/philippines_rpcmb.dart';

import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/shared/widgets/philippines_address_field.dart';

void main() {
  group('UserModel.formattedAddress', () {
    test('pinagsama ang structured parts (street → zip)', () {
      final u = UserModel(
        id: '1',
        role: 'rider',
        firstName: 'Juan',
        lastName: 'Dela Cruz',
        accountStatus: 'active',
        forcePasswordChange: false,
        createdAt: DateTime(2026, 1, 1),
        streetAddress: '098 Mabini St',
        barangay: 'Poblacion',
        city: 'Cebu City',
        province: 'Cebu',
        zipCode: '6000',
      );
      expect(u.formattedAddress,
          '098 Mabini St, Poblacion, Cebu City, Cebu, 6000');
    });

    test('fallback sa composed one-liner kapag walang structured parts', () {
      final u = UserModel(
        id: '1',
        role: 'rider',
        firstName: 'Juan',
        lastName: 'Dela Cruz',
        accountStatus: 'active',
        forcePasswordChange: false,
        createdAt: DateTime(2026, 1, 1),
        address: 'Old one-line address',
      );
      expect(u.formattedAddress, 'Old one-line address');
    });

    test('blangko kapag walang address sa dalawa', () {
      final u = UserModel(
          id: '1',
          role: 'head_manager',
          firstName: 'A',
          lastName: 'B',
          accountStatus: 'active',
          forcePasswordChange: false,
          createdAt: DateTime(2026, 1, 1));
      expect(u.formattedAddress, '');
    });
  });

  group('philippineRegionForCity (prefill ng Region mula sa city)', () {
    // Totoong PSA data — hindi hardcoded na pangalan para hindi brittle.
    late final Municipality city;
    late final Province province;
    late final Region region;

    setUpAll(() {
      outer:
      for (final r in philippineRegions) {
        for (final p in r.provinces) {
          for (final m in p.municipalities) {
            if (m.barangays.isNotEmpty) {
              region = r;
              province = p;
              city = m;
              break outer;
            }
          }
        }
      }
    });

    test('nahahanap ang region ng isang city', () {
      expect(philippineRegionForCity(city.name), region.regionName);
      expect(philippineRegionForCity('  ${city.name.toUpperCase()}  '),
          region.regionName);
    });

    test('null kapag wala/blangko', () {
      expect(philippineRegionForCity('Walang Ganitong Lugar'), isNull);
      expect(philippineRegionForCity(''), isNull);
      expect(philippineRegionForCity(null), isNull);
    });

    testWidgets('prefill: kumpleto ang address kahit walang Region sa DB',
        (tester) async {
      final key = GlobalKey<PhilippinesAddressFieldState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PhilippinesAddressField(
              key: key,
              // Walang initialRegion — tulad ng galing sa `addresses` table.
              initialStreet: '098 Mabini St',
              initialCity: city.name,
              initialProvince: province.name,
              initialBarangay: city.barangays.first,
            ),
          ),
        ),
      ));

      final state = key.currentState!;
      expect(find.text('098 Mabini St'), findsOneWidget);
      expect(state.street, '098 Mabini St');
      expect(state.barangay, city.barangays.first);
      expect(state.city, city.name);
      expect(state.province, province.name);
      expect(state.region, region.regionName,
          reason: 'dapat na-derive ang Region mula sa city (PSA data)');
      expect(state.isValid, isTrue,
          reason: 'kumpleto ang naka-prefill na address — hindi dapat '
              'maging error sa Next/Save');
    });
  });
}

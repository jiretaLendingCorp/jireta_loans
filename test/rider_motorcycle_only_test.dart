// test/rider_motorcycle_only_test.dart
//
// RIDER VEHICLE — MOTORCYCLE LANG
//
// Ang lahat ng rider ng Jireta ay motorcycle messenger, pero:
//   • "Vehicle Type" dropdown: may Bicycle at Car pa;
//   • "Vehicle Brand" dropdown: naghalo ang motor brands (Honda, Yamaha, …) at
//     CAR brands (Toyota, Mitsubishi, Nissan, Hyundai, Isuzu, Ford, Chevrolet).
//
// Ngayon: motorcycle lang ang uri, at puro MOTOR brand ang listahan ng brand
// (may 'Other' pa rin para sa hindi nakalista).
//
// Saklaw: HM + Employee create rider modal, HM edit rider modal, at ang
// rider's own profile edit screen (doon naka-save ang lumang halaga).
//
// MAHALAGA: ang dropdown na may value na WALA sa `items` ay nag-a-assert, kaya
// ang mga EDIT form ay may defensive na items getter para sa legacy na
// 'Bicycle'/'Car' — hindi basta-basta nawawala o nasisira ang lumang record.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _createScreens = {
  'lib/presentation/features/head_manager/riders/widgets/create_rider_modal.dart',
  'lib/presentation/features/employee/riders/widgets/emp_create_rider_modal.dart',
};

const _editRider =
    'lib/presentation/features/head_manager/riders/widgets/edit_rider_modal.dart';
const _riderProfile =
    'lib/presentation/features/rider/profile/screens/rider_edit_profile_screen.dart';

const _carBrands = [
  'Toyota',
  'Mitsubishi',
  'Nissan',
  'Hyundai',
  'Isuzu',
  'Ford',
  'Chevrolet',
];

const _motorcycleBrands = [
  'Honda',
  'Yamaha',
  'Suzuki',
  'Kawasaki',
  'Kymco',
  'Mio',
  'Vespa',
  'Piaggio',
  'Bajaj',
  'TVS',
  'Benelli',
  'Rusi',
  'Royal Enfield',
];

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

void main() {
  group('Create Rider modal (HM + Employee): motorcycle lang', () {
    for (final path in _createScreens) {
      final name = path.split('/').last;

      test('$name: walang Bicycle/Car sa Vehicle Type', () {
        final src = _read(path);

        expect(src, contains("value: 'motorcycle'"));
        expect(src, isNot(contains("value: 'bicycle'")),
            reason: 'May Bicycle pa sa Vehicle Type');
        expect(src, isNot(contains("value: 'car'")),
            reason: 'May Car pa sa Vehicle Type');
      });

      test('$name: puro motor brand ang Vehicle Brand listahan', () {
        final src = _read(path);

        expect(src, contains('_motorcycleBrands = ['));
        for (final brand in _motorcycleBrands) {
          expect(src, contains("'$brand'"),
              reason: 'Nawala ang motor brand na $brand');
        }
        for (final brand in _carBrands) {
          expect(src, isNot(contains("'$brand'")),
              reason: 'Nasa listahan pa ang car brand na $brand');
        }
        // May 'Other' pa rin para sa hindi nakalista.
        expect(src, contains("value: 'other'"));
      });
    }
  });

  group('Edit Rider modal (HM): motorcycle lang', () {
    test('isang uri na lang, at hindi masisira ang legacy na halaga', () {
      final src = _read(_editRider);

      expect(src, contains("static const _vehicleTypes = ['Motorcycle'];"));
      for (final other in ["'Bicycle',", "'Car',", "'Van',", "'Truck'"]) {
        expect(src, isNot(contains(other)),
            reason: 'Nandiyan pa ang $other sa vehicle types');
      }
      // Defensive: isinasama ang kasalukuyang (legacy) halaga sa items.
      expect(src, contains('_vehicleTypeItems'));
      expect(src, contains('items: _vehicleTypeItems'));
    });
  });

  group('Rider profile edit: motorcycle lang', () {
    test('motorcycle lang ang uri, motor brands lang ang brand', () {
      final src = _read(_riderProfile);

      expect(src, contains('_motorcycleBrands = ['));
      expect(src, contains("_vehicleTypes = ['motorcycle']"));
      expect(src, isNot(contains("value: 'bicycle'")));
      expect(src, isNot(contains("value: 'car'")));
      for (final brand in _carBrands) {
        expect(src, isNot(contains("'$brand'")),
            reason: 'Nasa listahan pa ang car brand na $brand');
      }
      // Ang legacy na 'bicycle'/'car' ay pinapanatili (kasama sa dropdown).
      expect(src, contains('_vehicleTypeItems'));
      expect(src, contains("_motorcycleBrands.contains(brand)"),
          reason: 'Dapat legacy car brand → Other (hindi mawawala ang brand)');
    });
  });
}

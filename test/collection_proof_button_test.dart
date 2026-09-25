// test/collection_proof_button_test.dart
//
// "VIEW COLLECTION PROOF" BUTTON (Collection Details — HM + Employee)
//
// BUG: ang button ay nakabalot sa `Container(width: double.infinity)` kaya
// humahaba ito sa BUONG lapad ng "Payment Info" card — mahigit 700px para sa
// apat na salitang label, at tumatakbo pakanan ang itsura nito sa desktop.
//
// FIX: `Align(centerLeft) + SizedBox(width: isNarrow ? double.infinity : null)`
// — sa desktop, kasya lang ang button sa nilalaman nito at naka-left align; sa
// makitid na screen (< 860px) buong lapad pa rin para madaling tapikin.
//
// Tinitignan ng test na ito ang DALAWANG bagay:
//   1. Source guard — hindi na maibabalik ang `width: double.infinity` sa
//      desktop path (at pareho ang HM at Employee).
//   2. Widget test — pinapatunayan na ang compact na bersyon ay talagang
//      humihigpit sa nilalaman at hindi buong lapad (hindi lang basta inaasahan
//      na ang `Container` na walang `width` ay mag-hu-hug).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _hmScreen =
    'lib/presentation/features/head_manager/collections/screens/hm_collection_details_screen.dart';
const _empScreen =
    'lib/presentation/features/employee/collections/screens/emp_collection_details_screen.dart';

String _readNormalized(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

/// Ang block ng proof button sa screen (mula sa `if (hasProof)`), normalize sa
/// isang linya para hindi dipende sa formatting ang mga assertion.
String _proofButtonBlock(String source) {
  // Ang aktwal na label widget (hindi ang anumang pagbanggit nito sa comment).
  final labelIndex = source.indexOf("Text('View Collection Proof'");
  expect(labelIndex, greaterThanOrEqualTo(0),
      reason: 'walang View Collection Proof button sa screen');
  // Ang `if (hasProof) ...[` na PINAKAMALAPIT bago ang label — hindi na
  // dipende sa haba ng block (lumalaki ito kapag may nadagdag na paliwanag).
  final start = source.lastIndexOf('if (hasProof) ...[', labelIndex);
  expect(start, greaterThanOrEqualTo(0), reason: 'walang proof button block');
  return source
      .substring(start, labelIndex + 64)
      .replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  group('Source guard: compact na proof button', () {
    for (final screen in {_hmScreen, _empScreen}) {
      final name = screen.split('/').last;

      test('$name: hindi buong lapad sa desktop, buong lapad sa mobile', () {
        final block = _proofButtonBlock(_readNormalized(screen));

        expect(
          block,
          contains('width: isNarrow ? double.infinity : null'),
          reason: 'Nawala ang compact/desktop switch ng button',
        );
        expect(
          block,
          contains('alignment: Alignment.centerLeft'),
          reason: 'Dapat naka-left align ang compact na button',
        );
        expect(
          block,
          isNot(contains('width: double.infinity, decoration')),
          reason: 'Bumalik ang bug: buong lapad na button sa desktop',
        );
      });
    }
  });

  group('Widget: ang compact na button ay humihigpit sa nilalaman', () {
    /// Kaparehong estruktura ng button sa screen (hindi kasama ang buong page).
    Widget buildProofButton({required bool desktop}) {
      return MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: desktop ? null : double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF0B2545), Color(0xFF1A2E4A)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    label: const Text('View Collection Proof'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> pump(WidgetTester tester, double width,
        {required bool desktop}) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildProofButton(desktop: desktop));
      await tester.pumpAndSettle();
    }

    testWidgets('desktop (1000px): hindi buong lapad at naka-left align',
        (tester) async {
      await pump(tester, 1000, desktop: true);
      expect(tester.takeException(), isNull);

      final btn = tester.getRect(find.byType(ElevatedButton));
      // Hug sa nilalaman: wala kahit kalahati ng available na lapad.
      expect(btn.width, lessThan(600),
          reason: 'Buong lapad pa rin ang button (${btn.width}px)');
      // Naka-left align (sa 24px na page padding), hindi naka-center.
      expect(btn.left, closeTo(24, 1),
          reason: 'Hindi naka-left align ang button (${btn.left}px)');
    });

    testWidgets('mobile (420px): buong lapad pa rin (thumb-friendly)',
        (tester) async {
      await pump(tester, 420, desktop: false);
      expect(tester.takeException(), isNull);

      final btn = tester.getRect(find.byType(ElevatedButton));
      expect(btn.width, closeTo(420 - 48, 1),
          reason: 'Dapat buong lapad ng card ang button sa mobile');
    });
  });
}

// test/document_preview_carousel_test.dart
// Ang preview ng documentation ng Account Upgrade ay CAROUSEL na ngayon
// (isa-isa ang titignan: Front Side tapos Back Side), hindi na magkatabi.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/widgets/document_preview_dialog.dart';
import 'package:jireta_loans/presentation/shared/widgets/document_viewer.dart';

/// 1x1 PNG — ginagamit para sa in-memory (base64) na dokumento.
const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

Future<void> _open(
  WidgetTester tester,
  List<DocumentPreviewPage> pages, {
  int initialIndex = 0,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showDocumentPreviewDialog(
              ctx,
              title: 'Valid Government ID',
              pages: pages,
              initialIndex: initialIndex,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Walang URL (blangko) para hindi mag-network ang test — ang kino-verify natin
/// ay ang carousel navigation, labels, at counter.
const _pages = [
  DocumentPreviewPage(label: 'Front Side', url: ''),
  DocumentPreviewPage(label: 'Back Side', url: ''),
];

void main() {
  testWidgets('isa lang ang nakikita sa isang pagkakataon', (tester) async {
    await _open(tester, _pages);

    expect(find.text('Valid Government ID'), findsOneWidget);
    expect(find.text('Front Side'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    // Hindi sabay na nakikita ang back side.
    expect(find.text('Back Side'), findsNothing);
    // Nasa unang pahina pa — walang Previous arrow (hindi disabled, WALA).
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('ang −, +, ⟳ ay nasa toolbar tabi ng counter, hindi sa litrato',
      (tester) async {
    await _open(tester, _pages);

    expect(find.byIcon(Icons.rotate_right_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);

    // Gumagana ang rotate nang hindi nag-e-error (4 na pindot = balik sa 0°).
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byIcon(Icons.rotate_right_rounded));
      await tester.pump();
    }
    expect(find.text('1 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lumilipat sa susunod at bumabalik sa nauna', (tester) async {
    await _open(tester, _pages);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Back Side'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    // Huling pahina na — wala na ang Next arrow.
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Front Side'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('swipe pakanan → susunod na dokumento', (tester) async {
    await _open(tester, _pages);

    // I-drag pakanan ang carousel (PageView) papunta sa Back Side.
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text('Back Side'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('walang arrows/dots kapag isang dokumento lang', (tester) async {
    await _open(tester, const [
      DocumentPreviewPage(label: 'Document', url: ''),
    ]);

    expect(find.text('Document'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(find.text('1 / 1'), findsNothing);
  });

  testWidgets('nagbubukas agad sa pinindot na pahina (initialIndex)',
      (tester) async {
    // Ito ang gawi ng grid ng evidence photos: ang AGAD na pinindot na
    // thumbnail ang nakikita, hindi laging ang una.
    await _open(tester, _pages, initialIndex: 1);

    expect(find.text('Back Side'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Front Side'), findsNothing);
  });

  testWidgets('in-memory (base64) na pahina: hindi lumalabas ang "No document"',
      (tester) async {
    // Ang co-maker signature ay RAW base64 PNG sa DB — hindi URL — kaya
    // `bytes` ang ipinapasa ng Loan Application Details screen.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DocumentViewer(
          bytes: Uint8List.fromList(base64Decode(_onePixelPng)),
          showZoomControls: false,
          showRotateControl: false,
          height: 300,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('No document'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clamped ang initialIndex na lampas sa range', (tester) async {
    await _open(tester, _pages, initialIndex: 99);

    // Dapat nasa huling pahina lang, walang crash.
    expect(find.text('Back Side'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

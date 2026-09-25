// test/features/shared/proof_signature_background_test.dart
//
// "LENDER SIGNATURE" SA FULLSCREEN PROOF VIEWER
//
// TANONG: bakit puro itim ang Lender Signature sa proof viewer?
//
// DAHILAN: ang signature na ini-upload ng rider ay TRANSPARENT na PNG na
// MADILIM ang tinta (naka-save na stroke, walang puting papel sa likod), at ang
// fullscreen viewer ay may ITIM na background (`Dialog.fullscreen` black +
// `Image` na `BoxFit.contain`). Itim-sa-itim kaya halos hindi ito makita.
//
// FIX: `CollectionProofItem.looksLikeSignature` — kapag signature ang item
// (auto-detect mula sa label, o explicit na `isSignature: true`), PUTI ang
// background ng page at itim ang caption. Nananatiling itim ang mga litrato
// (Payment Proof / Scene Photo / Proof Photo 1-2).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/widgets/details/collection_proof_viewer.dart';

Future<void> openViewer(
    WidgetTester tester, List<CollectionProofItem> items) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showCollectionProofFullscreen(context, items),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Ang PINAKAMALAPIT na background (ColoredBox) sa likod ng larawan.
Color pageBackground(WidgetTester tester) {
  final boxes = tester
      .widgetList<ColoredBox>(
        find.ancestor(of: find.byType(Image), matching: find.byType(ColoredBox)),
      )
      .toList();
  expect(boxes, isNotEmpty, reason: 'Walang background sa likod ng larawan');
  return boxes.first.color;
}

void main() {
  group('CollectionProofItem.looksLikeSignature', () {
    test('auto-detect mula sa label (walang kailangang baguhin sa call sites)',
        () {
      const sig = CollectionProofItem(
          label: 'Lender Signature', url: 'https://example.com/sig.png');
      const photo = CollectionProofItem(
          label: 'Payment Proof', url: 'https://example.com/photo.jpg');

      expect(sig.looksLikeSignature, isTrue);
      expect(photo.looksLikeSignature, isFalse);
    });

    test('explicit na isSignature ang nananaig sa label', () {
      const forced = CollectionProofItem(
          label: 'Proof Photo 2',
          url: 'https://example.com/x.png',
          isSignature: true);
      const cleared = CollectionProofItem(
          label: 'Lender Signature',
          url: 'https://example.com/x.jpg',
          isSignature: false);

      expect(forced.looksLikeSignature, isTrue);
      expect(cleared.looksLikeSignature, isFalse);
    });
  });

  group('Fullscreen viewer: background ng bawat uri ng proof', () {
    testWidgets('signature → PUTING background (kita ang madilim na tinta)',
        (tester) async {
      await openViewer(tester, const [
        CollectionProofItem(
            label: 'Lender Signature', url: 'https://example.com/sig.png'),
      ]);
      expect(tester.takeException(), isNull);

      expect(pageBackground(tester), Colors.white,
          reason: 'Itim-sa-itim pa rin ang signature');

      // Basahin ang caption sa puting background.
      final caption = tester.widget<Text>(find.textContaining('Lender Signature'));
      expect(caption.style?.color, Colors.black87,
          reason: 'Hindi mababasa ang puting caption sa puting background');
    });

    testWidgets('litrato → itim pa rin ang background (hindi nabago)',
        (tester) async {
      await openViewer(tester, const [
        CollectionProofItem(
            label: 'Payment Proof', url: 'https://example.com/photo.jpg'),
      ]);
      expect(tester.takeException(), isNull);

      expect(pageBackground(tester), Colors.black);

      final caption = tester.widget<Text>(find.textContaining('Payment Proof'));
      expect(caption.style?.color, Colors.white70);
    });

    testWidgets('naka-zoom pa rin ang signature page (hindi nasira ang pan)',
        (tester) async {
      await openViewer(tester, const [
        CollectionProofItem(
            label: 'Lender Signature', url: 'https://example.com/sig.png'),
      ]);

      final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer));
      expect(viewer.minScale, 1);
      expect(viewer.maxScale, 5);
      // Nananatiling naka-center ang larawan (letterboxed sa `contain`).
      final center = tester.getCenter(find.byType(Image));
      expect(center.dx, closeTo(400, 0.5));
      expect(center.dy, closeTo(300, 0.5));
    });
  });
}

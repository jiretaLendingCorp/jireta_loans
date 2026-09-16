// test/features/shared/proof_fullscreen_zoom_test.dart
// Coverage para sa fullscreen proof viewer (Collections / Disbursement COD):
//   • Naka-center at fitted (BoxFit.contain) ang larawan sa viewport, kaya
//     hindi ito gumagalaw sa sarili nitong direksyon kapag nag-zoom.
//   • Nakasara ang PageView swipe habang naka-zoom — kung bukas ito, ang
//     drag ay napupunta sa PageView imbis na sa pan ng naka-zoom na larawan
//     (dating bug: parang baliktad/maling direksyon ang galaw).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/widgets/details/collection_proof_viewer.dart';

void main() {
  const items = [
    CollectionProofItem(
        label: 'Proof Photo 1', url: 'https://example.com/proof-1.jpg'),
    CollectionProofItem(
        label: 'Lender Signature', url: 'https://example.com/signature.jpg'),
  ];

  Future<void> openViewer(WidgetTester tester) async {
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

  InteractiveViewer currentViewer(WidgetTester tester) =>
      tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));

  PageView currentPageView(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView));

  testWidgets('naka-center at BoxFit.contain ang larawan', (tester) async {
    await openViewer(tester);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);

    // Gitna ng viewport ang gitna ng larawan (800x600 ang test screen).
    final center = tester.getCenter(find.byType(Image));
    expect(center.dx, closeTo(400, 0.5));
    expect(center.dy, closeTo(300, 0.5));
  });

  testWidgets('zoom + pan settings', (tester) async {
    await openViewer(tester);

    final viewer = currentViewer(tester);
    expect(viewer.minScale, 1);
    expect(viewer.maxScale, 5);
    // Desktop: wheel/trackpad = zoom, hindi pan.
    expect(viewer.trackpadScrollCausesScale, isTrue);
    // Default (zero) boundary margin: hindi mailalabas ng pan ang larawan
    // sa labas ng viewport kaya naka-center pa rin ito.
    expect(viewer.boundaryMargin, EdgeInsets.zero);
  });

  testWidgets('habang naka-zoom, hindi nakaw ang swipe ng PageView',
      (tester) async {
    await openViewer(tester);

    expect(currentPageView(tester).physics, isA<PageScrollPhysics>());

    final controller = currentViewer(tester).transformationController!;
    controller.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();
    expect(currentPageView(tester).physics,
        isA<NeverScrollableScrollPhysics>());

    // Balik sa fit → bukas ulit ang page swipe.
    controller.value = Matrix4.identity();
    await tester.pump();
    expect(currentPageView(tester).physics, isA<PageScrollPhysics>());
  });

  testWidgets('swipe papuntang kasunod na proof kapag hindi naka-zoom',
      (tester) async {
    await openViewer(tester);

    // Higit sa kalahati ng lapad ng page (>400px sa 800px na test screen) para
    // tuluyang lumipat sa kasunod na proof.
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.textContaining('Lender Signature'), findsOneWidget);
    expect(find.textContaining('2/2'), findsOneWidget);
  });

  testWidgets('tap sa thumbnail → direkta sa fullscreen, walang maliit na dialog',
      (tester) async {
    await openViewer(tester);

    // Ang unang page ay ang pinindot na proof; may caption at close button.
    expect(find.textContaining('Proof Photo 1'), findsOneWidget);
    expect(find.textContaining('1/2'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Cash on Delivery Proof'), findsNothing);
  });
}

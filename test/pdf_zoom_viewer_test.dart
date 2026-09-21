// test/pdf_zoom_viewer_test.dart
// Pinch-to-zoom ng report preview (`PdfZoomViewer`).
//
// Ang aktwal na rasterization (`Printing.raster`) ay platform channel, kaya ang
// transformations math (`fitMatrix` / `zoomAboutPoint`) ang sinusuri dito —
// iyon ang nagpapatakbo ng pinch, wheel, double-tap at ng +/− buttons.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/widgets/pdf_zoom_viewer.dart';

/// Ang isang punto sa child ay lumalabas sa viewport sa `scale * p + t`
/// (walang rotation sa InteractiveViewer).
Offset _apply(Matrix4 m, Offset p) {
  final t = m.getTranslation();
  final s = uniformScale(m);
  return Offset(s * p.dx + t.x, s * p.dy + t.y);
}

void main() {
  group('fitMatrix (cover = puno ang preview, walang space)', () {
    test('pinupuno ang lapad kapag landscape ang dokumento', () {
      final m = fitMatrix(const Size(920, 490), const Size(1684, 1190),
          cover: true);

      // Lapad ang nag-limit (920/1684 = 0.546 > 490/1190 = 0.412).
      final s = uniformScale(m);
      expect(s, closeTo(920 / 1684, 0.0001));
      // Naka-top align patayo at naka-center ang pahalang na crop.
      final t = m.getTranslation();
      expect(t.y, closeTo(0, 0.0001));
      expect(t.x, closeTo((920 - 1684 * s) / 2, 0.0001));
    });

    test('kumakapit sa viewport kahit maliit na page', () {
      final m = fitMatrix(const Size(400, 300), const Size(200, 200),
          cover: true);
      expect(uniformScale(m), closeTo(2.0, 0.0001));
    });

    test('naka-center at kasya ang dokumento sa viewport', () {
      final m = fitMatrix(const Size(400, 300), const Size(800, 600));

      expect(uniformScale(m), closeTo(0.5, 0.0001));
      // 800×600 sa 0.5 = 400×300 → eksaktong kasya, walang offset.
      final t = m.getTranslation();
      expect(t.x, closeTo(0, 0.0001));
      expect(t.y, closeTo(0, 0.0001));
    });

    test('naka-center nang patayo kapag mababa ang dokumento', () {
      final m = fitMatrix(const Size(400, 300), const Size(800, 400));

      expect(uniformScale(m), closeTo(0.5, 0.0001));
      expect(m.getTranslation().y, closeTo(50, 0.0001)); // (300 - 200) / 2
    });

    test('identity kapag blangko ang sukat', () {
      expect(
        uniformScale(fitMatrix(Size.zero, const Size(800, 600))),
        1.0,
      );
      expect(
        uniformScale(fitMatrix(const Size(400, 300), Size.zero)),
        1.0,
      );
    });
  });

  group('clampToViewport (walang blangkong space)', () {
    const viewport = Size(920, 490);
    const doc = Size(1684, 1190);

    test('hindi lumalabas ang dokumento sa itaas', () {
      // Nag-pan pataas nang sobra — dapat naka-clamp sa `y = 0`.
      final panned = panBy(fitMatrix(viewport, doc, cover: true),
          const Offset(0, 400));
      final clamped = clampToViewport(panned, viewport, doc);

      expect(clamped.getTranslation().y, closeTo(0, 0.0001));
      expect(uniformScale(clamped),
          closeTo(uniformScale(fitMatrix(viewport, doc, cover: true)), 0.0001));
    });

    test('hindi lumalabas sa ibaba — umaabot lang sa dulo ng dokumento', () {
      final cover = fitMatrix(viewport, doc, cover: true);
      final scale = uniformScale(cover);
      final panned = panBy(cover, const Offset(0, -5000));
      final clamped = clampToViewport(panned, viewport, doc);

      expect(
        clamped.getTranslation().y,
        closeTo(viewport.height - doc.height * scale, 0.0001),
      );
    });

    test('hindi lumalabas sa gilid — clamp sa lapad', () {
      final cover = fitMatrix(viewport, doc, cover: true);
      final scale = uniformScale(cover);
      // Malapad ang dokumento laban sa makitid na viewport.
      const narrow = Size(300, 400);
      final wide = fitMatrix(narrow, doc, cover: true);
      final wideScale = uniformScale(wide);
      final panned = panBy(wide, const Offset(9999, 0));
      final clamped = clampToViewport(panned, narrow, doc);

      expect(uniformScale(clamped), closeTo(wideScale, 0.0001));
      expect(clamped.getTranslation().x, closeTo(0, 0.0001));
      // Ang patayong posisyon ay hindi ginalaw (puno naman ito).
      expect(scale, closeTo(uniformScale(cover), 0.0001));
    });

    test('naka-center kapag mas maliit ang dokumento sa viewport', () {
      final clamped = clampToViewport(
          Matrix4.identity(), const Size(400, 300), const Size(200, 100));
      final t = clamped.getTranslation();
      expect(t.x, closeTo(100, 0.0001));
      expect(t.y, closeTo(100, 0.0001));
    });

    test('hindi ginalaw kapag nasa loob na', () {
      final cover = fitMatrix(viewport, doc, cover: true);
      expect(clampToViewport(cover, viewport, doc), same(cover));
    });
  });

  group('zoomAboutPoint', () {
    test('hindi gumagalaw ang child point sa ilalim ng anchor', () {
      final fit = fitMatrix(const Size(400, 300), const Size(800, 600));
      const anchor = Offset(120, 90);
      final childPoint = Offset(
        (anchor.dx - fit.getTranslation().x) / uniformScale(fit),
        (anchor.dy - fit.getTranslation().y) / uniformScale(fit),
      );

      final zoomed = zoomAboutPoint(fit, 2.0, anchor, 0.1, 10);

      expect(uniformScale(zoomed), closeTo(1.0, 0.0001));
      final after = _apply(zoomed, childPoint);
      expect(after.dx, closeTo(anchor.dx, 0.0001));
      expect(after.dy, closeTo(anchor.dy, 0.0001));
    });

    test('naka-clamp sa maxScale', () {
      final zoomed = zoomAboutPoint(
          Matrix4.identity(), 1000, const Offset(10, 10), 0.1, 4.0);
      expect(uniformScale(zoomed), closeTo(4.0, 0.0001));
    });

    test('naka-clamp sa minScale', () {
      final zoomed = zoomAboutPoint(
          Matrix4.identity(), 0.001, const Offset(10, 10), 0.2, 4.0);
      expect(uniformScale(zoomed), closeTo(0.2, 0.0001));
    });

    test('hindi ginalaw ang matrix kapag nasa limit na', () {
      final at = Matrix4.identity()..scaleByDouble(4.0, 4.0, 1, 1);
      expect(zoomAboutPoint(at, 2.0, Offset.zero, 0.1, 4.0), same(at));
    });
  });

  group('panBy (plain wheel / drag scroll)', () {
    test('nagpapalit ng eksaktong delta sa viewport space', () {
      final start = fitMatrix(const Size(400, 300), const Size(800, 600));
      const p = Offset(200, 150);
      const delta = Offset(0, -40);

      final after = _apply(panBy(start, delta), p);
      final before = _apply(start, p);

      expect(after.dx - before.dx, closeTo(delta.dx, 0.0001));
      expect(after.dy - before.dy, closeTo(delta.dy, 0.0001));
    });

    test('hindi nagbabago ang scale', () {
      final start = zoomAboutPoint(
          Matrix4.identity(), 2.0, Offset.zero, 0.1, 10);
      expect(
        uniformScale(panBy(start, const Offset(10, 10))),
        closeTo(2.0, 0.0001),
      );
    });
  });

  group('scaleGestureMatrix (pinch at drag)', () {
    test('purong drag: lumilipat ang scene point sa bagong focal', () {
      final start = fitMatrix(const Size(400, 300), const Size(800, 600));
      final scene = Offset(
        (100 - start.getTranslation().x) / uniformScale(start),
        (100 - start.getTranslation().y) / uniformScale(start),
      );

      final after = scaleGestureMatrix(
        start,
        startFocal: const Offset(100, 100),
        currentFocal: const Offset(160, 130),
        factor: 1,
        minScale: 0.1,
        maxScale: 10,
      );

      final at = _apply(after, scene);
      expect(at.dx, closeTo(160, 0.0001));
      expect(at.dy, closeTo(130, 0.0001));
      expect(uniformScale(after), closeTo(0.5, 0.0001));
    });

    test('pinch: naka-angkla sa focal at dumoble ang scale', () {
      final start = fitMatrix(const Size(400, 300), const Size(800, 600));
      final scene = Offset(
        (200 - start.getTranslation().x) / uniformScale(start),
        (150 - start.getTranslation().y) / uniformScale(start),
      );

      final after = scaleGestureMatrix(
        start,
        startFocal: const Offset(200, 150),
        currentFocal: const Offset(200, 150),
        factor: 2,
        minScale: 0.1,
        maxScale: 10,
      );

      expect(uniformScale(after), closeTo(1.0, 0.0001));
      final at = _apply(after, scene);
      expect(at.dx, closeTo(200, 0.0001));
      expect(at.dy, closeTo(150, 0.0001));
    });

    test('naka-clamp sa maxScale kahit sobrang lakas ng pinch', () {
      final after = scaleGestureMatrix(
        Matrix4.identity(),
        startFocal: Offset.zero,
        currentFocal: Offset.zero,
        factor: 999,
        minScale: 0.1,
        maxScale: 4,
      );
      expect(uniformScale(after), closeTo(4, 0.0001));
    });
  });

  testWidgets('spinner lang ang nakikita habang ginagawa ang preview',
      (tester) async {
    final pending = Completer<Uint8List>();
    addTearDown(() => pending.complete(Uint8List(0)));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: PdfZoomViewer(buildDocument: () => pending.future),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Walang zoom controls/hint na nakikita — gesture lang ang nag-zoom.
    expect(find.byType(IconButton), findsNothing);
    expect(find.textContaining('zoom'), findsNothing);
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}

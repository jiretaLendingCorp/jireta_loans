// test/landing_page_test.dart
//
// The landing page is the public entry page, so it has to hold up at every
// breakpoint without layout overflows. These tests pump the real screen (no
// stubbing) at desktop, laptop, tablet and phone sizes, scroll through the
// whole page and assert that no layout error is reported.
//
// Real fonts are loaded so the measurements match production instead of the
// fixed-width fallback font used by `flutter test`.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/core/theme/app_theme.dart';
import 'package:jireta_loans/presentation/features/landing/screens/landing_screen.dart';

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/Inter/Inter-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Inter/Inter-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Inter/Inter-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Inter/Inter-Bold.ttf'));
  await inter.load();

  final playfair = FontLoader('PlayfairDisplay')
    ..addFont(rootBundle
        .load('assets/fonts/Playfair_Display/PlayfairDisplay-Regular.ttf'))
    ..addFont(rootBundle
        .load('assets/fonts/Playfair_Display/PlayfairDisplay-Bold.ttf'));
  await playfair.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  const breakpoints = <String, Size>{
    'desktop': Size(1440, 900),
    'small laptop': Size(1024, 768),
    'tablet': Size(800, 1000),
    'phone': Size(390, 844),
    'small phone': Size(320, 640),
  };

  for (final entry in breakpoints.entries) {
    testWidgets('landing page renders on ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const LandingScreen()),
      );
      // Float cards animate forever, so pump fixed durations instead of
      // pumpAndSettle.
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 800));

      expect(tester.takeException(), isNull);

      // Hero content is always present — and once more inside the browser
      // mockup, which previews this same public page.
      expect(find.text('Lending Management System'), findsWidgets);
      expect(find.text('Get Started'), findsWidgets);
      expect(find.text('Sign In'), findsWidgets);

      // The laptop lid only exists on desktop, and it must paint the page on
      // white — otherwise the dark backdrop bleeds through the hero copy.
      final frameSurface = find.byKey(
        const ValueKey<String>('landing-frame-surface'),
      );
      if (entry.value.width >= 1024) {
        expect(frameSurface, findsOneWidget);
      } else {
        expect(frameSurface, findsNothing);
      }

      // The two hero CTAs must sit side by side, never stacked (a full-width
      // ghost button used to force the Wrap to break to a second row).
      if (entry.value.width >= 390) {
        final cta = find.byKey(const ValueKey<String>('landing-hero-cta'));
        final heroGetStarted = find.descendant(
          of: cta,
          matching: find.text('Get Started'),
        );
        final heroSignIn = find.descendant(of: cta, matching: find.text('Sign In'));
        expect(heroGetStarted, findsOneWidget);
        expect(heroSignIn, findsOneWidget);
        expect(
          tester.getCenter(heroGetStarted).dy,
          moreOrLessEquals(tester.getCenter(heroSignIn).dy, epsilon: 1),
        );
      }

      // Scroll through the whole page: every section must lay out cleanly.
      final scrollable = find.byType(Scrollable).first;
      final position =
          tester.widget<Scrollable>(scrollable).controller!.position;
      for (var i = 0; i <= 10; i++) {
        position.jumpTo(position.maxScrollExtent * i / 10);
        await tester.pump(const Duration(milliseconds: 220));
        expect(tester.takeException(), isNull);
      }
    });
  }
}

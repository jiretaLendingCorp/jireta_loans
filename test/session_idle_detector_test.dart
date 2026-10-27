// test/session_idle_detector_test.dart
//
// BUG na sinusuri nito: ang lender dashboard ay may 4-second auto-play na
// promo carousel (`PageController.animateToPage`). Naglalabas iyon ng
// ScrollNotification na WALANG drag — kung itinuturing itong user activity,
// nire-reset nito ang idle deadline kada 4 segundo at HINDI kailanman
// nag-a-auto logout.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/core/security/session_idle_detector.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';

/// Kapalit ng tunay na notifier: binibilang lang kung ilang beses itinuring
/// na "activity" ang isang event.
class _RecordingAuthNotifier extends AuthStateNotifier {
  int activityCalls = 0;

  @override
  Future<void> notifyActivity() async {
    activityCalls++;
  }
}

ScrollMetrics _metrics() => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 100,
      pixels: 0,
      viewportDimension: 100,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

/// Isang simpleng widget para makakuha ng [BuildContext] para sa mga
/// notification (required ito ng constructor sa Flutter na ito).
Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.shrink();
      }),
    ),
  );
  return ctx;
}

void main() {
  group('ScrollNotification → idle activity', () {
    testWidgets('programmatic scroll (auto-play carousel) ay HINDI activity',
        (tester) async {
      final ctx = await _pumpContext(tester);
      final metrics = _metrics();

      expect(
        isUserDrivenScroll(
          ScrollStartNotification(metrics: metrics, context: ctx),
        ),
        isFalse,
      );
      expect(
        isUserDrivenScroll(
          ScrollUpdateNotification(metrics: metrics, context: ctx),
        ),
        isFalse,
      );
      expect(
        isUserDrivenScroll(
          ScrollEndNotification(metrics: metrics, context: ctx),
        ),
        isFalse,
      );
      expect(
        isUserDrivenScroll(
          OverscrollNotification(
            metrics: metrics,
            context: ctx,
            overscroll: 10,
          ),
        ),
        isFalse,
      );
    });

    testWidgets('scroll na may drag ng user ay activity', (tester) async {
      final ctx = await _pumpContext(tester);
      final metrics = _metrics();

      expect(
        isUserDrivenScroll(
          ScrollStartNotification(
            metrics: metrics,
            context: ctx,
            dragDetails: DragStartDetails(globalPosition: Offset.zero),
          ),
        ),
        isTrue,
      );
      expect(
        isUserDrivenScroll(
          ScrollUpdateNotification(
            metrics: metrics,
            context: ctx,
            dragDetails: DragUpdateDetails(
              globalPosition: Offset.zero,
              delta: const Offset(0, -10),
            ),
          ),
        ),
        isTrue,
      );
      expect(
        isUserDrivenScroll(
          OverscrollNotification(
            metrics: metrics,
            context: ctx,
            overscroll: 10,
            dragDetails: DragUpdateDetails(
              globalPosition: Offset.zero,
              delta: const Offset(0, -10),
            ),
          ),
        ),
        isTrue,
      );
    });
  });

  testWidgets('totoong drag ng user ay activity', (tester) async {
    final notifier = _RecordingAuthNotifier();
    final controller = PageController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: SessionIdleDetector(
            child: Scaffold(
              body: PageView(
                controller: controller,
                children: const [
                  Center(child: Text('one')),
                  Center(child: Text('two')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(PageView), const Offset(-250, 0));
    await tester.pump(const Duration(milliseconds: 200));

    expect(notifier.activityCalls, greaterThan(0),
        reason: 'Dapat nagre-reset ng idle window ang totoong gesture.');

    await tester.pumpAndSettle();
    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

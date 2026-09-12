// test/sidebar_toggle_test.dart
//
// Tapping the sidebar toggle (collapse <-> expand) must never produce a
// layout overflow — during the width animation or in the steady state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jireta_loans/presentation/shared/widgets/layout/web_scaffold.dart';

Future<void> pumpScaffold(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const WebScaffold(
          title: 'Dashboard',
          body: Center(child: Text('content')),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: router)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('WebScaffold sidebar toggle', () {
    testWidgets('collapse then expand at 1280px never overflows',
        (tester) async {
      await pumpScaffold(tester, 1280);
      expect(tester.takeException(), isNull);

      // Collapse.
      await tester.tap(find.byTooltip('Toggle Sidebar'));
      await tester.pump(); // mid-animation frame
      expect(tester.takeException(), isNull,
          reason: 'Overflow during collapse animation');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'Overflow in collapsed steady state');

      // Expand again.
      await tester.tap(find.byTooltip('Toggle Sidebar'));
      await tester.pump(); // mid-animation frame
      expect(tester.takeException(), isNull,
          reason: 'Overflow during expand animation');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'Overflow in expanded steady state');
    });

    testWidgets('collapse with People flyout open never overflows',
        (tester) async {
      await pumpScaffold(tester, 1280);
      expect(tester.takeException(), isNull);

      // Open the People flyout, then collapse the sidebar.
      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Toggle Sidebar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'Overflow collapsing with flyout open');
    });

    testWidgets('mobile drawer opens without overflow at 360px',
        (tester) async {
      await pumpScaffold(tester, 360);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Open Menu'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'Overflow opening the mobile drawer');
    });
  });
}

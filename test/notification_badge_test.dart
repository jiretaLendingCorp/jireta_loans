// test/notification_badge_test.dart
//
// Regression tests for the header notification badge.
//
// Bug: the badge `Positioned` used to be wrapped inside the `AnimatedSwitcher`,
// so it landed under the switcher's internal `Stack` (behind
// FadeTransition/KeyedSubtree) instead of being a direct child of the outer
// `Stack`. As soon as there was an unread notification the framework threw
// "Incorrect use of ParentDataWidget" and replaced the bell/avatar area with a
// gray `ErrorWidget`, which in release builds swallows the whole remaining
// width of the top bar (the month filter gets pushed next to the page title
// and the bell + avatar disappear).
//
// The badge is laid out inside a `Row` (exactly like `_TopBar` in
// web_scaffold.dart), which hands non-flex children UNBOUNDED width — that is
// what made the bad subtree blow up.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/widgets/notification_badge.dart';

/// Mirrors the top-bar structure: bell button + avatar in a `Row`, so the
/// badge subtree receives unbounded horizontal constraints.
Widget buildHeader({required int count}) {
  return MaterialApp(
    home: Scaffold(
      body: Row(
        children: [
          const Spacer(),
          IconButton(
            onPressed: () {},
            tooltip: 'Notifications',
            icon: NotificationBadge(
              count: count,
              child: const Icon(Icons.notifications_outlined, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          const CircleAvatar(radius: 18),
        ],
      ),
    ),
  );
}

void main() {
  group('NotificationBadge', () {
    testWidgets('renders without exceptions inside a Row (unbounded width)',
        (tester) async {
      await tester.pumpWidget(buildHeader(count: 3));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'Badge threw while there is an unread notification');
      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      // The avatar next to the bell must still be laid out on screen.
      final avatarRight = tester.getTopRight(find.byType(CircleAvatar)).dx;
      final screenWidth = tester.getSize(find.byType(Scaffold)).width;
      expect(avatarRight, lessThanOrEqualTo(screenWidth + 1),
          reason: 'Avatar was pushed off-screen by a broken badge subtree');
    });

    testWidgets('stays clean when the badge appears (0 -> N) and clears (N -> 0)',
        (tester) async {
      // Start with no notifications: the switcher has a non-positioned child.
      await tester.pumpWidget(buildHeader(count: 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('3'), findsNothing);

      // A notification arrives. Once the outgoing (zero-size) child is
      // dropped, the old code was left with only a positioned child and
      // collapsed into a gray error box.
      await tester.pumpWidget(buildHeader(count: 3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'Badge threw after a notification arrived');
      expect(find.text('3'), findsOneWidget);

      // Back to zero: the badge disappears again, no leftovers.
      await tester.pumpWidget(buildHeader(count: 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('3'), findsNothing);
    });

    testWidgets('badge is pinned to the top-right, outside the icon bounds',
        (tester) async {
      await tester.pumpWidget(buildHeader(count: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final iconRect = tester.getRect(find.byIcon(Icons.notifications_outlined));
      // Measure the badge pill itself (the text sits inside its padding).
      final badgeRect = tester.getRect(
        find
            .ancestor(of: find.text('5'), matching: find.byType(Container))
            .first,
      );

      expect(badgeRect.right, greaterThan(iconRect.right),
          reason: 'Badge is not on the right edge of the icon');
      expect(badgeRect.top, lessThan(iconRect.top),
          reason: 'Badge is not on the top edge of the icon');
    });

    testWidgets('caps the label at 99+', (tester) async {
      await tester.pumpWidget(buildHeader(count: 4321));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('99+'), findsOneWidget);
    });
  });
}

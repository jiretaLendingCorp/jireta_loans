// test/anchored_dropdown_test.dart
//
// POSISYON NG DROPDOWN MENU ([AnchoredDropdownField])
//
//   * Bumubukas ang menu sa IBABA ng field kapag may sapat na espasyo — hindi
//     sa ibabaw ng field (dating ganoon ang `DropdownButtonFormField` kaya
//     natatakpan ang kasunod na form fields).
//   * Kapag kulang ang espasyo sa ibaba, awtomatikong sa ITAAS ito lumalabas.
//   * Parehong lapad ng field ang menu at napipili ang value.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/presentation/shared/widgets/forms/anchored_dropdown.dart';

const _options = [
  AnchoredDropdownOption('employed', 'Employed'),
  AnchoredDropdownOption('self_employed', 'Self-Employed'),
  AnchoredDropdownOption('business_owner', 'Business Owner'),
];

class _Host extends StatefulWidget {
  final double topSpacer;
  final ValueChanged<String?>? onChanged;
  const _Host({required this.topSpacer, this.onChanged});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String? _value;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SizedBox(height: widget.topSpacer),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AnchoredDropdownField(
                key: const ValueKey('employment'),
                label: 'Employment Type',
                value: _value,
                options: _options,
                onChanged: (v) {
                  setState(() => _value = v);
                  widget.onChanged?.call(v);
                },
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: InputDecoration(labelText: 'Employer / Business'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _pump(WidgetTester tester, {required double height, double topSpacer = 100, ValueChanged<String?>? onChanged}) async {
  tester.view.physicalSize = Size(800, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_Host(topSpacer: topSpacer, onChanged: onChanged));
  await tester.pumpAndSettle();
}

Rect _fieldRect(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('employment')));

void main() {
  testWidgets('may espasyo sa ibaba: sa IBABA bumubukas ang menu',
      (tester) async {
    await _pump(tester, height: 900);

    await tester.tap(find.byKey(const ValueKey('employment')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final field = _fieldRect(tester);
    final firstItem = tester.getRect(find.text('Employed'));
    final lastItem = tester.getRect(find.text('Business Owner'));

    // Nasa ibaba ng field ang buong menu — hindi nito natatakpan ang field.
    expect(firstItem.top, greaterThanOrEqualTo(field.bottom));
    expect(lastItem.bottom, greaterThan(field.bottom));
    // Naka-align sa kaliwa ng field ang laman ng menu (parehong lapad ito).
    expect(firstItem.left, greaterThanOrEqualTo(field.left));
    expect(firstItem.left - field.left, lessThan(32));
  });

  testWidgets('kulang ang espasyo sa ibaba: sa ITAAS lumalabas ang menu',
      (tester) async {
    await _pump(tester, height: 400, topSpacer: 280);

    await tester.tap(find.byKey(const ValueKey('employment')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final field = _fieldRect(tester);
    final firstItem = tester.getRect(find.text('Employed'));
    final lastItem = tester.getRect(find.text('Business Owner'));

    // Buong menu sa ITAAS ng field.
    expect(firstItem.top, lessThan(field.top));
    expect(lastItem.bottom, lessThanOrEqualTo(field.top));
  });

  testWidgets('napipili ang option at lumalabas ang label nito',
      (tester) async {
    String? picked;
    await _pump(tester, height: 900, onChanged: (v) => picked = v);

    await tester.tap(find.byKey(const ValueKey('employment')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Self-Employed'));
    await tester.pumpAndSettle();

    expect(picked, 'self_employed');
    expect(find.text('Self-Employed'), findsOneWidget);
    expect(find.text('Employed'), findsNothing);
  });
}

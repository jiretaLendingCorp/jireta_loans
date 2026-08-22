// Reproduction test for overflow when toggling profile collapsible sections.
// Mirrors the exact layout of lender_profile_screen.dart:
// SingleChildScrollView > ConstrainedBox(minHeight) > IntrinsicHeight > Column(+Spacer)
// with _CollapsibleSection (AnimatedSize) children.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class CollapsibleSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool isExpanded;
  final VoidCallback onToggle;

  const CollapsibleSection({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title)),
                  Icon(isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Column(
                    children: [
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Column(children: children),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

Widget infoRow(String label) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(width: 34, height: 34, color: Colors.blue),
        const SizedBox(width: 12),
        Expanded(child: Text('$label value line')),
      ]),
    );

Widget buildPage(int expandedSection, VoidCallback toggle0) {
  return MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      bottomNavigationBar: SizedBox(
        height: 62,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          ElevatedButton(onPressed: () {}, child: const Text('Home')),
        ]),
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
            child: IntrinsicHeight(
              child: Column(children: [
                // header content ~ same bulk as real screen
                Container(height: 140, color: Colors.amber),
                const SizedBox(height: 22),
                Container(height: 60, color: Colors.green), // verification card
                const SizedBox(height: 16),
                CollapsibleSection(
                  icon: Icons.person_outline,
                  title: 'Personal Details',
                  isExpanded: expandedSection == 0,
                  onToggle: toggle0,
                  children: [
                    infoRow('Full Name'),
                    infoRow('Phone'),
                    infoRow('Gender'),
                    infoRow('Civil Status'),
                    infoRow('Date of Birth'),
                    infoRow('Address'),
                  ],
                ),
                const SizedBox(height: 12),
                CollapsibleSection(
                  icon: Icons.wallet,
                  title: 'Financial Details',
                  isExpanded: expandedSection == 1,
                  onToggle: () {},
                  children: [
                    infoRow('GCash'),
                    infoRow('Employment'),
                    infoRow('Employer'),
                    infoRow('Monthly Income'),
                    infoRow('Source of Funds'),
                  ],
                ),
                const SizedBox(height: 12),
                CollapsibleSection(
                  icon: Icons.emergency,
                  title: 'Emergency Contact',
                  isExpanded: expandedSection == 2,
                  onToggle: () {},
                  children: [infoRow('Name'), infoRow('Phone')],
                ),
                const SizedBox(height: 22),
                Container(height: 100, color: Colors.purple), // legal card
                const Spacer(),
                const Text('Version 1.0.0'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                      onPressed: () {}, child: const Text('Log Out')),
                ),
              ]),
            ),
          ),
        );
      }),
    ),
  );
}

void main() {
  testWidgets('toggling sections does not overflow', (tester) async {
    int expanded = -1;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => buildPage(expanded, () {
          setState(() => expanded = expanded == 0 ? -1 : 0);
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // expand personal details (mid-animation frames are where overflow shows)
    await tester.tap(find.text('Personal Details'));
    await tester.pump(); // one frame into animation
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // collapse personal details
    await tester.tap(find.text('Personal Details'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // expand financial details (collapses personal simultaneously)
    await tester.tap(find.text('Financial Details'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // expand emergency contact
    await tester.tap(find.text('Emergency Contact'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

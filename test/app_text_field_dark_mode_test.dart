// test/app_text_field_dark_mode_test.dart
//
// Ang `minimal` (text-like) na AppTextField ay WALANG fill, kaya dapat
// theme-aware ang value color. Dati static na `AppColors.textPrimary` ito —
// itim — kaya hindi mabasa ang existing details sa dark mode (mukhang walang
// laman ang Rider Profile popups).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/theme/app_colors.dart';
import 'package:jireta_loans/presentation/shared/widgets/forms/app_text_field.dart';

void main() {
  Future<Color?> valueColor(
      WidgetTester tester, ThemeData theme, {required bool minimal}) async {
    final controller = TextEditingController(text: 'Jay Shin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AppTextField(
            label: 'First Name',
            controller: controller,
            minimal: minimal,
          ),
        ),
      ),
    );
    return tester.widget<EditableText>(find.byType(EditableText)).style.color;
  }

  testWidgets('dark mode: mababasa ang value ng minimal field',
      (tester) async {
    final color = await valueColor(
      tester,
      ThemeData(brightness: Brightness.dark),
      minimal: true,
    );
    expect(color, AppColors.darkTextPrimary);
  });

  testWidgets('light mode: dating color pa rin ang minimal field',
      (tester) async {
    final color = await valueColor(
      tester,
      ThemeData(brightness: Brightness.light),
      minimal: true,
    );
    expect(color, AppColors.textPrimary);
  });

  testWidgets('boxed field: nananatiling dark ang text kahit dark mode',
      (tester) async {
    final color = await valueColor(
      tester,
      ThemeData(brightness: Brightness.dark),
      minimal: false,
    );
    // May light fill ang boxed variant kaya dapat dark pa rin ang text.
    expect(color, AppColors.textPrimary);
  });
}

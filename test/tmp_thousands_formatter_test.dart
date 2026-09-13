import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/core/utils/input_formatters.dart';

void main() {
  const f = ThousandsSeparatorInputFormatter();

  TextEditingValue type(String oldText, String newText) => f.formatEditUpdate(
        TextEditingValue(
            text: oldText,
            selection: TextSelection.collapsed(offset: oldText.length)),
        TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newText.length)),
      );

  test('adds commas while typing', () {
    expect(type('', '3').text, '3');
    expect(type('3', '32').text, '32');
    expect(type('32', '320').text, '320');
    expect(type('320', '3200').text, '3,200');
    expect(type('3,200', '3,2000').text, '32,000');
    expect(type('32,000', '32,0000').text, '320,000');
  });

  test('keeps decimals and strips extra separators', () {
    expect(type('32,000', '32,000.').text, '32,000.');
    expect(type('32,000.', '32,000.0').text, '32,000.0');
    expect(type('32,000.0', '32,000.05').text, '32,000.05');
    expect(type('32,000.05', '32,000.059').text, '32,000.05');
    expect(type('3,200', '3,2,00').text, '3,200');
  });

  test('cursor stays near the edit point (backspace)', () {
    final v = f.formatEditUpdate(
      const TextEditingValue(
          text: '32,000', selection: TextSelection.collapsed(offset: 6)),
      const TextEditingValue(
          text: '32,00', selection: TextSelection.collapsed(offset: 5)),
    );
    expect(v.text, '3,200');
    expect(v.selection.baseOffset, 4);
  });

  test('drops non numeric input and leading zeros', () {
    expect(type('', 'abc').text, '');
    expect(type('', '032').text, '32');
    expect(type('0', '0.5').text, '0.5');
  });

  test('programmatic format matches typed look', () {
    expect(ThousandsSeparatorInputFormatter.format(32000), '32,000.00');
    expect(ThousandsSeparatorInputFormatter.format(1234.5), '1,234.50');
  });
}

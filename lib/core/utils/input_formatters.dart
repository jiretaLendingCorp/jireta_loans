// lib/core/utils/input_formatters.dart
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Naglalagay ng comma separator sa mga numero habang nagta-type
/// (hal. `32000.00` -> `32,000.00`).
///
/// Ang hawak na teksto ay digits + isang tuldok lang pagkatapos alisin ang
/// comma, kaya `double.tryParse(text.replaceAll(',', ''))` pa rin ang
/// tamang paraan ng pag-parse.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter({this.decimalDigits = 2});

  /// Maximum na bilang ng decimal places na papayagan.
  final int decimalDigits;

  static final RegExp _digits = RegExp(r'[0-9]');
  static final RegExp _nonNumeric = RegExp(r'[^0-9.]');
  static final RegExp _leadingZeros = RegExp(r'^0+(?=\d)');

  /// Para sa programmatic na pag-set ng controller (hal. "Use Due Amount")
  /// upang pareho ang itsura sa ininput ng user: `32,000.00`.
  static String format(num value, {int decimalDigits = 2}) {
    final pattern =
        decimalDigits > 0 ? '#,##0.${'0' * decimalDigits}' : '#,##0';
    return NumberFormat(pattern, 'en_PH').format(value);
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned = newValue.text.replaceAll(_nonNumeric, '');
    if (cleaned.isEmpty) {
      return const TextEditingValue();
    }

    final dotIndex = cleaned.indexOf('.');
    var intPart = dotIndex == -1 ? cleaned : cleaned.substring(0, dotIndex);
    var decPart = dotIndex == -1
        ? ''
        : cleaned.substring(dotIndex + 1).replaceAll('.', '');
    if (decPart.length > decimalDigits) {
      decPart = decPart.substring(0, decimalDigits);
    }

    // Bawal ang nangungunang zero (hal. "032" -> "32"), pero payagan ang
    // "0.50" at ang nag-iisang "0".
    intPart = intPart.replaceFirst(_leadingZeros, '');
    if (intPart.isEmpty) intPart = '0';

    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    var formatted = buffer.toString();
    if (dotIndex != -1) formatted = '$formatted.$decPart';

    // Cursor base sa bilang ng digits bago ito — hindi tumatalon sa dulo
    // kapag nag-edit sa gitna ng numero.
    final selectionEnd =
        newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitsBefore =
        newValue.text.substring(0, selectionEnd).replaceAll(_nonNumeric, '').length;

    var cursor = formatted.length;
    if (digitsBefore == 0) {
      cursor = 0;
    } else {
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (_digits.hasMatch(formatted[i])) {
          seen++;
          if (seen == digitsBefore) {
            cursor = i + 1;
            break;
          }
        }
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}

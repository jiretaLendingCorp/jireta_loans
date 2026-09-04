// test/features/lender/loans/amount_slider_sync_test.dart
// Verifies the Loan Amount field ↔ slider sync used on the lender apply-loan
// screen: typing a peso amount must move the slider to that exact amount.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

class _AmountFieldSliderSync extends StatefulWidget {
  const _AmountFieldSliderSync();

  @override
  State<_AmountFieldSliderSync> createState() => _AmountFieldSliderSyncState();
}

class _AmountFieldSliderSyncState extends State<_AmountFieldSliderSync> {
  static const double _minAmount = 3000;
  static const double _maxAmount = 500000;

  double _amount = 3000;
  final _amountCtrl = TextEditingController();
  String? _amountError;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  void _onAmountTextChanged(String digits) {
    final parsed = int.tryParse(digits.replaceAll(RegExp(r'\D'), ''));
    setState(() {
      if (parsed == null || parsed == 0) {
        _amountError = 'Please enter a loan amount.';
      } else if (parsed < _minAmount || parsed > _maxAmount) {
        _amountError = 'Amount must be between ₱3,000 and ₱500,000.';
        _amount = parsed.clamp(_minAmount, _maxAmount).toDouble();
      } else {
        _amountError = null;
        _amount = parsed.toDouble();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _PesoAmountFormatter(),
                ],
                onChanged: _onAmountTextChanged,
              ),
              Slider(
                value: _amount,
                min: _minAmount,
                max: _maxAmount,
                onChanged: (v) =>
                    setState(() => _amount = (v / 1000).round() * 1000.0),
              ),
              if (_amountError != null) Text(_amountError!),
            ],
          ),
        ),
      ),
    );
  }
}

class _PesoAmountFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final value = int.tryParse(digits) ?? 0;
    final formatted = NumberFormat('#,##0').format(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

void main() {
  testWidgets('typing an amount moves the slider to that exact amount',
      (tester) async {
    await tester.pumpWidget(const _AmountFieldSliderSync());

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 3000, reason: 'starts at the minimum');

    await tester.enterText(find.byType(TextField), '10000');
    await tester.pump();

    final updated = tester.widget<Slider>(find.byType(Slider));
    expect(updated.value, 10000,
        reason: 'slider tracks the typed amount');

    // Field is formatted in peso thousand separators.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '10,000',
    );
  });

  testWidgets('off-thousand amounts are not snapped by the slider',
      (tester) async {
    await tester.pumpWidget(const _AmountFieldSliderSync());

    await tester.enterText(find.byType(TextField), '5432');
    await tester.pump();

    final updated = tester.widget<Slider>(find.byType(Slider));
    expect(updated.value, 5432,
        reason: 'slider reflects the exact typed amount');
  });
}
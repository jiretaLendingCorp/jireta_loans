// lib/data/models/loan_settings.dart
import 'package:intl/intl.dart';

/// Minimum/maximum na loan amount at interest rate mula sa System Settings ng
/// Head Manager (`system-view?fn=get-loan-settings`).
///
/// Ginagamit ito ng Apply Loan at In-Office wizard para pantay ang UI sa
/// server validation — kapag pinalitan ng HM ang ₱3,000–₱500,000, doon na
/// naka-base ang slider, label, at error message.
class LoanSettings {
  final double minAmount;
  final double maxAmount;
  final double interestRate;

  const LoanSettings({
    required this.minAmount,
    required this.maxAmount,
    required this.interestRate,
  });

  /// Fallback kapag hindi makuha ang config (o lumang backend) — kapareho ng
  /// dating hardcoded na values para walang biglang pagbabago sa UI.
  static const defaults = LoanSettings(
    minAmount: 3000,
    maxAmount: 500000,
    interestRate: 20,
  );

  factory LoanSettings.fromJson(Map<String, dynamic> json) {
    final min = _toDouble(json['min_amount']);
    final max = _toDouble(json['max_amount']);
    if (min == null || max == null || min <= 0 || max <= 0 || min > max) {
      return defaults;
    }
    final rate = _toDouble(json['interest_rate']);
    return LoanSettings(
      minAmount: min,
      maxAmount: max,
      interestRate:
          (rate != null && rate >= 0 && rate <= 100) ? rate : defaults.interestRate,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}'.trim());
  }

  static final _peso = NumberFormat('#,##0', 'en_PH');

  String get minLabel => '₱${_peso.format(minAmount)}';
  String get maxLabel => '₱${_peso.format(maxAmount)}';
}

// lib/core/utils/loan_frequency.dart
//
// Resolves the repayment frequency (daily / weekly / monthly) from a
// loan-details map, whatever shape the API returns.
import 'timezone.dart';

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool _isUuid(String s) => _uuidPattern.hasMatch(s);

String _cleanCode(dynamic v) {
  if (v is! String) return '';
  final s = v.trim().toLowerCase();
  if (s.isEmpty || _isUuid(s)) return '';
  return s;
}

/// Hinahanap ang frequency sa varchar `payment_frequency`, sa joined
/// `payment_frequencies.code`, o sa legacy `frequency` — at kung wala lahat,
/// hinihinuha mula sa pagitan ng mga schedule due date
/// (7 days apart => weekly, atbp.).
String resolveLoanFrequency(Map<String, dynamic> loan) {
  var f = _cleanCode(loan['payment_frequency']);
  if (f.isNotEmpty) return f;

  final join = loan['payment_frequencies'];
  if (join is Map) {
    f = _cleanCode(join['code']);
    if (f.isNotEmpty) return f;
    f = _cleanCode(join['name']);
    if (f.isNotEmpty) return f;
  }

  f = _cleanCode(loan['payment_frequency_id']);
  if (f.isNotEmpty) return f;

  f = _cleanCode(loan['frequency']);
  if (f.isNotEmpty) return f;

  return inferFrequencyFromSchedules(loan);
}

/// Hinuhulaan ang frequency mula sa agwat ng mga schedule due date.
/// ~1 araw => daily, ~7 araw => weekly, ~30 araw => monthly.
String inferFrequencyFromSchedules(Map<String, dynamic> loan) {
  final list = (loan['loan_schedules'] as List? ?? [])
      .whereType<Map<String, dynamic>>()
      .toList();
  final dates = <DateTime>[];
  for (final s in list) {
    final dt = parseManila(s['due_date']);
    if (dt != null) dates.add(dt);
  }
  if (dates.length < 2) return '';
  dates.sort();
  var totalGap = 0;
  for (var i = 1; i < dates.length; i++) {
    totalGap += dates[i].difference(dates[i - 1]).inDays;
  }
  final avg = totalGap / (dates.length - 1);
  if (avg <= 2) return 'daily';
  if (avg <= 10) return 'weekly';
  return 'monthly';
}

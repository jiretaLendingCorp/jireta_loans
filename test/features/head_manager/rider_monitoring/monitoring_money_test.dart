// test/features/head_manager/rider_monitoring/monitoring_money_test.dart
//
// REGRESSION: `NoSuchMethodError: 'toPeso'` sa Rider Monitoring details.
// Ang dahilan: `dynamic` ang receiver ng extension method, kaya dynamic
// dispatch ang nangyari. Ang `monitoringPeso` ay nagko-convert muna sa `num`
// → `double` bago tawagin ang extension.
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/presentation/features/head_manager/rider_monitoring/utils/monitoring_money.dart';

void main() {
  test('int JSON value → piso', () {
    expect(monitoringPeso(20000), '₱20,000.00');
  });

  test('double at numeric string', () {
    expect(monitoringPeso(9299.5), '₱9,299.50');
    expect(monitoringPeso('1234.5'), '₱1,234.50');
  });

  test('null / empty → fallback, hindi exception', () {
    expect(monitoringPeso(null), '—');
    expect(monitoringPeso(''), '—');
    expect(monitoringAmount(null), 0);
  });
}

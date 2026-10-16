// test/interest_label_test.dart
//
// Ang interest rate ay itinatakda na ng Head Manager, kaya ang label sa mga
// loan screen ay dapat sumunod sa aktwal na rate (hindi naka-hardcode sa 20%).
// Kapag wala/kulang ang value, bumalik sa generic na "Interest" — hindi
// kailanman magpapakita ng maling porsyento.
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/utils/interest_label.dart';

void main() {
  group('interestRateLabel', () {
    test('renders whole-number rates without decimals', () {
      expect(interestRateLabel(20), 'Interest (20%)');
      expect(interestRateLabel(30), 'Interest (30%)');
    });

    test('renders fractional rates with one decimal', () {
      expect(interestRateLabel(22.5), 'Interest (22.5%)');
    });

    test('accepts string / whole-double values from JSON', () {
      expect(interestRateLabel('30'), 'Interest (30%)');
      expect(interestRateLabel(30.0), 'Interest (30%)');
    });

    test('falls back to a generic label when the rate is missing', () {
      expect(interestRateLabel(null), 'Interest');
      expect(interestRateLabel(''), 'Interest');
      expect(interestRateLabel('abc'), 'Interest');
    });
  });
}

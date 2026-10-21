// test/time_ago_manila_test.dart
//
// REGRESSION: "bakit naka-Just now lang lahat sa Recent Activity?"
//
// Ang `parseManila` ay nagdadagdag ng +8h sa tunay na UTC instant pero
// UTC-flagged pa rin ang DateTime. Kapag `DateTime.now()` (local) ang batayan
// ng "time ago", ang bawat timestamp ay 8 oras na "nasa hinaharap" kaya
// negatibo ang difference at laging "Just now" ang lumalabas.
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/utils/timezone.dart';

void main() {
  test('seconds lang ang lumipas → Just now', () {
    final now = nowManila();
    expect(
      timeAgoManila(now.subtract(const Duration(seconds: 20)), now: now),
      'Just now',
    );
  });

  test('5 minuto → "5m ago", hindi "Just now"', () {
    final now = nowManila();
    expect(
      timeAgoManila(now.subtract(const Duration(minutes: 5)), now: now),
      '5m ago',
    );
  });

  test('timestamp mula sa backend (dumaan sa parseManila) ay tama ang label',
      () {
    final now = nowManila();
    // Tunay na UTC instant na 3 oras ang nakalipas.
    final utcIso = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 3))
        .toIso8601String();
    final createdAt = parseManila(utcIso)!;
    expect(timeAgoManila(createdAt, now: now), '3h ago');
  });

  test('2 araw → "2d ago"; 10 araw → petsa', () {
    final now = nowManila();
    expect(
      timeAgoManila(now.subtract(const Duration(days: 2)), now: now),
      '2d ago',
    );
    final tenDays = now.subtract(const Duration(days: 10));
    expect(
      timeAgoManila(tenDays, now: now),
      '${tenDays.month}/${tenDays.day}/${tenDays.year}',
    );
  });
}

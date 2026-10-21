// lib/presentation/features/head_manager/rider_monitoring/utils/monitoring_money.dart
import '../../../../../core/extensions/num_extensions.dart';

/// Converts a `dynamic` JSON number/string into a `double` without relying on
/// dynamic dispatch.
///
/// Mahalaga ito: ang `toPeso()` ay EXTENSION method. Kapag `dynamic` ang
/// receiver, dynamic dispatch ang nangyayari at hindi ito makikita —
/// `NoSuchMethodError: 'toPeso'` sa runtime. Dito explicit na `num` muna bago
/// `double`, kaya laging tama ang uri bago tawagin ang extension.
double monitoringAmount(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return num.tryParse(value.replaceAll(',', ''))?.toDouble() ?? 0;
  }
  return 0;
}

/// `₱`-formatted na halaga mula sa JSON, o `—` kapag wala.
String monitoringPeso(dynamic value, {String fallback = '—'}) {
  if (value == null || value == '') return fallback;
  return monitoringAmount(value).toPeso();
}

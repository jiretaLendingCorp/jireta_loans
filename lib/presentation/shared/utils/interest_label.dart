// lib/presentation/shared/utils/interest_label.dart

/// Label para sa interest row ng isang loan.
///
/// Ang interest rate ay itinatakda na ng Head Manager (System Settings →
/// `system_config.interest_rate`) kaya HINDI na ito naka-hardcode sa 20%.
/// Ipinapasa ang aktwal na rate ng loan (`loans.interest_rate`) para tumugma
/// ang label sa sinisingil.
///
/// Kapag wala/kulang ang rate (hal. lumang record, o preview na wala pang
/// value), bumalik sa generic na "Interest" na label — hindi kailanman
/// magpapakita ng maling porsyento.
String interestRateLabel(dynamic rate) {
  final value =
      rate is num ? rate.toDouble() : double.tryParse('${rate ?? ''}');
  if (value == null) return 'Interest';
  final text =
      value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
  return 'Interest ($text%)';
}

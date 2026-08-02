// lib/core/extensions/num_extensions.dart
import 'package:intl/intl.dart';
import '../utils/formatters.dart';

extension NumExtensions on num {
  String get toCurrency {
    final f = NumberFormat('#,##0.00', 'en_PH');
    return '₱${f.format(this)}';
  }

  String toPeso() => AppFormatters.currency(this);

  String get toCurrencyShort {
    if (this >= 1000000) return '₱${(this / 1000000).toStringAsFixed(1)}M';
    if (this >= 1000) return '₱${(this / 1000).toStringAsFixed(1)}K';
    return toCurrency;
  }

  String get toCompact {
    final f = NumberFormat.compact();
    return f.format(this);
  }
}

extension DoubleExtensions on double {
  String get toCurrency {
    final f = NumberFormat('#,##0.00', 'en_PH');
    return '₱${f.format(this)}';
  }

  String toPeso() => AppFormatters.currency(this);
}

extension StringCurrencyExtensions on String {
  String toPeso() {
    final value = num.tryParse(replaceAll(',', ''));
    if (value == null) return this;
    return AppFormatters.currency(value);
  }
}

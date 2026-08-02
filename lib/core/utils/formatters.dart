// lib/core/utils/formatters.dart
import 'package:intl/intl.dart';

class AppFormatters {
  AppFormatters._();

  static final _currencyFmt = NumberFormat.currency(
    symbol: '₱',
    decimalDigits: 2,
    locale: 'en_PH',
  );

  static final _shortCurrencyFmt = NumberFormat.currency(
    symbol: '₱',
    decimalDigits: 0,
    locale: 'en_PH',
  );

  static final _dateFmt = DateFormat('MMM d, y', 'en_PH');
  static final _datetimeFmt = DateFormat('MMM d, y h:mm a', 'en_PH');
  static final _timeFmt = DateFormat('h:mm a', 'en_PH');
  static final _dateInputFmt = DateFormat('yyyy-MM-dd');

  static String currency(num amount) => _currencyFmt.format(amount);

  static String currencyShort(num amount) => _shortCurrencyFmt.format(amount);

  static String date(DateTime dt) => _dateFmt.format(dt);

  static String dateTime(DateTime dt) => _datetimeFmt.format(dt);

  static String time(DateTime dt) => _timeFmt.format(dt);

  static String dateInput(DateTime dt) => _dateInputFmt.format(dt);

  static String maskPhone(String phone) {
    if (phone.length < 7) return phone;
    return '${phone.substring(0, 4)}****${phone.substring(phone.length - 3)}';
  }

  static String maskName(String name) {
    if (name.isEmpty) return name;
    final parts = name.trim().split(' ');
    if (parts.length == 1) {
      final p = parts[0];
      if (p.length <= 2) return p;
      return '${p[0]}${'*' * (p.length - 1)}';
    }
    return parts.map((p) {
      if (p.isEmpty) return p;
      if (p.length <= 1) return p;
      return '${p[0]}${'*' * (p.length - 1)}';
    }).join(' ');
  }

  static String maskGcash(String gcash) {
    if (gcash.length < 4) return gcash;
    return '${gcash[0]}${gcash[1]}*******${gcash[gcash.length - 1]}';
  }

  static String formatNumber(num value) =>
      NumberFormat.compact(locale: 'en_PH').format(value);

  static String relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return date(dt);
  }
}

// lib/core/extensions/date_extensions.dart
import 'package:intl/intl.dart';
import '../utils/formatters.dart';
import '../utils/timezone.dart';

extension DateExtensions on DateTime {
  String get formatted => DateFormat('MMM dd, yyyy').format(this);
  String get formattedWithTime =>
      DateFormat('MMM dd, yyyy h:mm a').format(this);
  String get formattedShort => DateFormat('MM/dd/yyyy').format(this);
  String get formattedMonth => DateFormat('MMMM yyyy').format(this);
  String toDisplay() => AppFormatters.date(this);
  String toDateString() => AppFormatters.date(this);
  String toPhilippineDate() => AppFormatters.date(this);
  String toDateTimeString() => AppFormatters.dateTime(this);

  String get toDisplayDate => AppFormatters.date(this);
  String get toShortDate => AppFormatters.date(this);

  bool get isToday {
    final now = nowManila();
    return year == now.year && month == now.month && day == now.day;
  }

  bool get isPast => isBefore(nowManila());
  bool get isOverdue => isPast && !isToday;

  String get timeAgo {
    final now = nowManila();
    final diff = now.difference(this);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formatted;
  }
}

extension NullableDateExtensions on DateTime? {
  String get formattedOrEmpty => this?.formatted ?? '—';
  String? get toDisplayDate => this?.toDisplayDate;
  String? get toShortDate => this?.toShortDate;
}

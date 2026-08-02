// lib/core/extensions/string_extensions.dart
import '../utils/formatters.dart';

extension StringExtensions on String {
  String get maskedPhone {
    if (length < 7) return this;
    return '${substring(0, 4)}****${substring(length - 3)}';
  }

  String maskPhone() => AppFormatters.maskPhone(this);

  String get maskedName {
    final parts = trim().split(' ');
    return parts.map((p) {
      if (p.length <= 1) return p;
      return '${p[0]}${'*' * (p.length - 1)}';
    }).join(' ');
  }

  String get maskedGcash {
    if (length < 4) return this;
    return '${substring(0, 2)}${'*' * (length - 3)}${substring(length - 1)}';
  }

  String get initials {
    final parts = trim().split(' ');
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String get capitalizeFirst {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }

  String get titleCase {
    return split(' ').map((w) => w.capitalizeFirst).join(' ');
  }

  bool get isValidEmail {
    return RegExp(r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+').hasMatch(this);
  }

  bool get isValidPhone {
    return RegExp(r'^(09|\+639)\d{9}$').hasMatch(replaceAll(' ', ''));
  }
}

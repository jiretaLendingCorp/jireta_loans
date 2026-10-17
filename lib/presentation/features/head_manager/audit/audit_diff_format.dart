// lib/presentation/features/head_manager/audit/audit_diff_format.dart
//
// Formatting ng BEFORE / AFTER diff sa Audit Logs. Hiwalay sa screen para
// masubukan (unit test) at para isa lang ang pinagmumulan ng rules.
import 'package:jireta_loans/core/extensions/date_extensions.dart';
import 'package:jireta_loans/core/utils/timezone.dart';

/// Mga token na may sariling spelling (acronym / brand) — kung wala ito,
/// "Account Status Id", "Profile Photo Url", "Gcash" ang lumalabas.
const Map<String, String> auditKeyTokens = {
  'id': 'ID',
  'url': 'URL',
  'uri': 'URI',
  'ip': 'IP',
  'fcm': 'FCM',
  'kyc': 'KYC',
  'ci': 'CI',
  'mfa': 'MFA',
  'sms': 'SMS',
  'ai': 'AI',
  'gcash': 'GCash',
  'xendit': 'Xendit',
};

/// `account_status_id` → `Account Status ID`
String humanizeAuditKey(String key) {
  if (key.isEmpty) return key;
  return key
      .split(RegExp(r'[_\\-\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) =>
          auditKeyTokens[w.toLowerCase()] ?? '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

final RegExp _isoDateTime = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');

/// Value → readable text. ISO timestamp ay ginagawang Manila date/time;
/// boolean ay Yes/No; null/empty ay `—`.
String formatAuditValue(dynamic value) {
  if (value == null) return '—';
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is List) {
    if (value.isEmpty) return '—';
    return value.map(formatAuditValue).join(', ');
  }
  if (value is Map) {
    return value.entries
        .map((e) => '${humanizeAuditKey(e.key.toString())}: '
            '${formatAuditValue(e.value)}')
        .join(', ');
  }
  final text = value.toString().trim();
  if (text.isEmpty) return '—';
  if (_isoDateTime.hasMatch(text)) {
    final parsed = parseManila(text);
    if (parsed != null) return parsed.formattedWithTime;
  }
  return text;
}

/// Ang mga field na ipapakita sa diff: lahat ng nagbago (ayos ng AFTER), kasama
/// ang mga nasa BEFORE lang — bahagi iyon ng dating row at hindi tinatanggal.
List<String> changedAuditKeys(
    Map<String, dynamic>? before, Map<String, dynamic>? after) {
  if (before == null || after == null) return const [];
  final keys = <String>[];
  after.forEach((key, value) {
    if (!before.containsKey(key) ||
        formatAuditValue(before[key]) != formatAuditValue(value)) {
      keys.add(key);
    }
  });
  before.forEach((key, _) {
    if (!after.containsKey(key)) keys.add(key);
  });
  return keys;
}

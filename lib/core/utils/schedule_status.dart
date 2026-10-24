// lib/core/utils/schedule_status.dart
//
// Status label ng isang installment sa Payment Schedule (HM at Employee).
//
// Mahalaga: kapag binayaran ng lender ang isang LUMPAS nang installment, hindi
// dapat basta "Paid" ang nakalagay — dapat "Overdue paid", para makita ng Head
// Manager at Employee na may dating overdue na nabayaran na (at kailan, sa
// `paid_at`). Iisa ang helper na ito para pantay ang label sa lahat ng
// Payment Schedule table (details page, side panel, at modals).
import 'package:intl/intl.dart';

import 'timezone.dart';

/// Bayad na ang installment PERO pagkalampas ng due date (Manila calendar
/// date ang paghahambing ng `paid_at` at `due_date`).
///
/// `false` kapag hindi pa bayad, kapag walang `paid_at`, o kapag on-time
/// (kasama ang bayad sa mismong due date).
bool isLatePaidSchedule(Map<String, dynamic> schedule) {
  final status = (schedule['status'] as String? ?? '').toLowerCase();
  final amountDue = (schedule['amount_due'] as num?)?.toDouble() ?? 0;
  final amountPaid = (schedule['amount_paid'] as num?)?.toDouble() ?? 0;
  final settled = status == 'paid' ||
      status == 'completed' ||
      (amountDue > 0 && amountPaid >= amountDue);
  if (!settled) return false;

  final dueDate = parseManila(schedule['due_date']);
  final paidAt = parseManila(schedule['paid_at']);
  if (dueDate == null || paidAt == null) return false;

  final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
  final paidDay = DateTime(paidAt.year, paidAt.month, paidAt.day);
  return paidDay.isAfter(dueDay);
}

/// Petsa AT ORAS ng bayad na nag-settle ng dating overdue (Manila), hal.
/// `Sep 27, 2026 9:32 PM`. `null` kapag on-time, hindi pa bayad, o walang
/// `paid_at`.
String? latePaidDateLabel(Map<String, dynamic> schedule) {
  if (!isLatePaidSchedule(schedule)) return null;
  final paidAt = parseManila(schedule['paid_at']);
  if (paidAt == null) return null;
  return DateFormat('MMM dd, yyyy h:mm a').format(paidAt);
}

/// Label ng Status cell ng Payment Schedule table.
///
/// Late paid → `Overdue paid · Sep 27, 2026 9:32 PM` (petsa at oras ng bayad);
/// kung hindi, capitalized na hilaw na status (`Paid`, `Overdue`, `Partial`,
/// `Pending`, …).
String scheduleStatusLabel(Map<String, dynamic> schedule, {String fallback = '-'}) {
  if (isLatePaidSchedule(schedule)) {
    final date = latePaidDateLabel(schedule);
    return date == null ? 'Overdue paid' : 'Overdue paid · $date';
  }
  final status = (schedule['status'] as String? ?? '').trim();
  if (status.isEmpty) return fallback;
  final lower = status.toLowerCase();
  return '${lower[0].toUpperCase()}${lower.substring(1).replaceAll('_', ' ')}';
}

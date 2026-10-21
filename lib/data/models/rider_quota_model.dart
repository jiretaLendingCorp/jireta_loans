// lib/data/models/rider_quota_model.dart
//
// Read-only na modelo para sa Rider Quota Management (HM/Employee) at
// "My Quota" (rider). Ang `confirmed`, `remaining` at `completion` ay galing
// sa `rider_quota_monitoring` / `rider_quota_self` RPC (migration 00187) —
// walang financial computation sa client. Verified payments lang ang
// binibilang ng server, at hindi kasama ang labas ng quota window.
import '../../core/utils/timezone.dart';

/// Status na DERIVED ng server mula sa dates at sa nakolekta.
abstract final class RiderQuotaStatus {
  static const String upcoming = 'upcoming';
  static const String active = 'active';
  static const String completed = 'completed';
  static const String expired = 'expired';
  static const String inactive = 'inactive';

  static const List<String> all = [
    upcoming,
    active,
    completed,
    expired,
    inactive,
  ];

  static const Map<String, String> labels = {
    upcoming: 'Upcoming',
    active: 'Active',
    completed: 'Completed',
    expired: 'Expired',
    inactive: 'Inactive',
  };

  static String label(String status) => labels[status] ?? status;
}

abstract final class RiderQuotaPeriod {
  static const String daily = 'daily';
  static const String weekly = 'weekly';
  static const String monthly = 'monthly';

  static const List<String> all = [daily, weekly, monthly];

  static const Map<String, String> labels = {
    daily: 'Daily',
    weekly: 'Weekly',
    monthly: 'Monthly',
  };

  static String label(String period) => labels[period] ?? period;
}

class RiderQuotaSummary {
  final int activeRiders;
  final double assignedQuota;
  final double confirmedTotal;
  final double remainingTotal;
  final int ridersMet;
  final int openQuotas;
  final int totalQuotas;
  final int expiredQuotas;

  const RiderQuotaSummary({
    this.activeRiders = 0,
    this.assignedQuota = 0,
    this.confirmedTotal = 0,
    this.remainingTotal = 0,
    this.ridersMet = 0,
    this.openQuotas = 0,
    this.totalQuotas = 0,
    this.expiredQuotas = 0,
  });

  factory RiderQuotaSummary.fromJson(Map<String, dynamic> json) =>
      RiderQuotaSummary(
        activeRiders: (json['active_riders'] as num?)?.toInt() ?? 0,
        assignedQuota: (json['assigned_quota'] as num?)?.toDouble() ?? 0,
        confirmedTotal: (json['confirmed_total'] as num?)?.toDouble() ?? 0,
        remainingTotal: (json['remaining_total'] as num?)?.toDouble() ?? 0,
        ridersMet: (json['riders_met'] as num?)?.toInt() ?? 0,
        openQuotas: (json['open_quotas'] as num?)?.toInt() ?? 0,
        totalQuotas: (json['total_quotas'] as num?)?.toInt() ?? 0,
        expiredQuotas: (json['expired_quotas'] as num?)?.toInt() ?? 0,
      );
}

class RiderQuota {
  final String quotaId;
  final String riderId;
  final String riderName;
  final String? phoneNumber;
  final String period;
  final double targetAmount;
  final double confirmedCollection;
  final double remainingTarget;
  final double? completionPercentage;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;
  final bool isActive;
  final bool achieved;
  final int paymentCount;
  final DateTime? lastPaidAt;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RiderQuota({
    required this.quotaId,
    required this.riderId,
    this.riderName = '',
    this.phoneNumber,
    this.period = RiderQuotaPeriod.daily,
    this.targetAmount = 0,
    this.confirmedCollection = 0,
    this.remainingTarget = 0,
    this.completionPercentage,
    this.startDate,
    this.endDate,
    this.status = RiderQuotaStatus.active,
    this.isActive = true,
    this.achieved = false,
    this.paymentCount = 0,
    this.lastPaidAt,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory RiderQuota.fromJson(Map<String, dynamic> json) {
    final paidAt = json['last_paid_at'];
    return RiderQuota(
      quotaId: (json['quota_id'] ?? json['id'] ?? '').toString(),
      riderId: (json['rider_id'] ?? '').toString(),
      riderName: (json['rider_name'] ?? '').toString(),
      phoneNumber: json['phone_number']?.toString(),
      period: (json['period'] ?? RiderQuotaPeriod.daily).toString(),
      targetAmount: (json['target_amount'] as num?)?.toDouble() ?? 0,
      confirmedCollection:
          (json['confirmed_collection'] as num?)?.toDouble() ?? 0,
      remainingTarget: (json['remaining_target'] as num?)?.toDouble() ?? 0,
      completionPercentage:
          (json['completion_percentage'] as num?)?.toDouble(),
      startDate: _parseDateOnly(json['start_date']),
      endDate: _parseDateOnly(json['end_date']),
      status: (json['status'] ?? RiderQuotaStatus.active).toString(),
      isActive: json['is_active'] as bool? ?? true,
      achieved: json['achieved'] as bool? ?? false,
      paymentCount: (json['payment_count'] as num?)?.toInt() ?? 0,
      lastPaidAt: paidAt == null ? null : parseManila(paidAt),
      notes: json['notes']?.toString(),
      createdAt: parseManila(json['created_at']),
      updatedAt: parseManila(json['updated_at']),
    );
  }

  /// Progress bar value — capped sa 1.0, pero nananatili ang totoong
  /// `confirmedCollection` kahit lumampas sa target.
  double get progress =>
      ((completionPercentage ?? 0) / 100).clamp(0.0, 1.0).toDouble();

  bool get isOpen =>
      status == RiderQuotaStatus.active || status == RiderQuotaStatus.upcoming;

  bool get isEditable => isOpen && isActive;

  bool get isOverTarget =>
      targetAmount > 0 && confirmedCollection > targetAmount;
}

class RiderQuotaPage {
  final List<RiderQuota> rows;
  final RiderQuotaSummary summary;
  final int total;
  final int page;
  final int totalPages;

  const RiderQuotaPage({
    this.rows = const [],
    this.summary = const RiderQuotaSummary(),
    this.total = 0,
    this.page = 1,
    this.totalPages = 1,
  });

  factory RiderQuotaPage.fromJson(Map<String, dynamic> json) {
    final list = (json['data'] as List?) ?? const [];
    return RiderQuotaPage(
      rows: list
          .whereType<Map>()
          .map((e) => RiderQuota.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      summary: RiderQuotaSummary.fromJson(
          Map<String, dynamic>.from((json['summary'] as Map?) ?? const {})),
      total: (json['total'] as num?)?.toInt() ?? list.length,
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Isang rider sa assign form — active account lang ang ipinapadala ng server.
class RiderQuotaRiderOption {
  final String riderId;
  final String riderName;
  final String? phoneNumber;
  final bool? isAvailable;

  const RiderQuotaRiderOption({
    required this.riderId,
    this.riderName = '',
    this.phoneNumber,
    this.isAvailable,
  });

  factory RiderQuotaRiderOption.fromJson(Map<String, dynamic> json) =>
      RiderQuotaRiderOption(
        riderId: (json['rider_id'] ?? '').toString(),
        riderName: (json['rider_name'] ?? '').toString(),
        phoneNumber: json['phone_number']?.toString(),
        isAvailable: json['is_available'] as bool?,
      );
}

/// Verified payment na bahagi ng kasalukuyang quota window.
class RiderQuotaPayment {
  final String paymentId;
  final double amount;
  final DateTime? paidAt;
  final String? paymentMethod;
  final String? loanNumber;
  final int? installmentNumber;

  const RiderQuotaPayment({
    required this.paymentId,
    this.amount = 0,
    this.paidAt,
    this.paymentMethod,
    this.loanNumber,
    this.installmentNumber,
  });

  factory RiderQuotaPayment.fromJson(Map<String, dynamic> json) =>
      RiderQuotaPayment(
        paymentId: (json['payment_id'] ?? '').toString(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        paidAt: parseManila(json['paid_at']),
        paymentMethod: json['payment_method']?.toString(),
        loanNumber: json['loan_number']?.toString(),
        installmentNumber: (json['installment_number'] as num?)?.toInt(),
      );
}

/// Rider self payload: kasalukuyang quota, mga dating resulta at ang mga
/// verified payment na bumubuo sa kasalukuyang quota.
class RiderQuotaSelf {
  final RiderQuota? current;
  final List<RiderQuota> history;
  final List<RiderQuotaPayment> payments;

  const RiderQuotaSelf({
    this.current,
    this.history = const [],
    this.payments = const [],
  });

  factory RiderQuotaSelf.fromJson(Map<String, dynamic> json) {
    final currentRaw = json['current'];
    final historyRaw = (json['history'] as List?) ?? const [];
    final paymentsRaw = (json['payments'] as List?) ?? const [];
    return RiderQuotaSelf(
      current: currentRaw is Map
          ? RiderQuota.fromJson(Map<String, dynamic>.from(currentRaw))
          : null,
      history: historyRaw
          .whereType<Map>()
          .map((e) => RiderQuota.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      payments: paymentsRaw
          .whereType<Map>()
          .map((e) => RiderQuotaPayment.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }
}

/// `YYYY-MM-DD` ay isang calendar date — huwag i-shift ang timezone.
DateTime? _parseDateOnly(dynamic value) {
  if (value == null) return null;
  final raw = value.toString();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw);
}

/// Default na window kapag pumili ng period sa assign/edit form — mas mabilis
/// kaysa manu-manong pagpili ng dalawang petsa. Pwede pa ring baguhin.
({DateTime start, DateTime end}) riderQuotaDefaultRange(
  String period,
  DateTime today,
) {
  final day = DateTime(today.year, today.month, today.day);
  switch (period) {
    case RiderQuotaPeriod.daily:
      return (start: day, end: day);
    case RiderQuotaPeriod.weekly:
      final monday = day.subtract(Duration(days: day.weekday - 1));
      return (start: monday, end: monday.add(const Duration(days: 6)));
    default:
      final first = DateTime(day.year, day.month, 1);
      final last = DateTime(day.year, day.month + 1, 0);
      return (start: first, end: last);
  }
}

/// Client-side pre-validation para sa assign/edit form. Kapareho ng rules ng
/// backend (period span, positive target, date order) para mabilis ang
/// feedback — ang server pa rin ang huling nagva-validate.
String? validateRiderQuotaInput({
  required String period,
  required num targetAmount,
  required DateTime? startDate,
  required DateTime? endDate,
}) {
  if (!RiderQuotaPeriod.all.contains(period)) {
    return 'Choose a quota period.';
  }
  if (targetAmount <= 0) {
    return 'Target amount must be greater than zero.';
  }
  if (startDate == null || endDate == null) {
    return 'Set the quota start and end dates.';
  }
  final start = DateTime(startDate.year, startDate.month, startDate.day);
  final end = DateTime(endDate.year, endDate.month, endDate.day);
  if (end.isBefore(start)) {
    return 'End date must not be before the start date.';
  }
  final span = end.difference(start).inDays + 1;
  final (min, max) = switch (period) {
    RiderQuotaPeriod.daily => (1, 1),
    RiderQuotaPeriod.weekly => (7, 7),
    _ => (28, 31),
  };
  if (span < min || span > max) {
    final expected = period == RiderQuotaPeriod.daily
        ? '1 day'
        : period == RiderQuotaPeriod.weekly
            ? '7 days'
            : '28–31 days';
    return 'A $period quota must cover exactly $expected.';
  }
  return null;
}

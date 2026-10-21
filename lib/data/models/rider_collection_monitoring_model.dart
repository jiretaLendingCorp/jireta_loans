// lib/data/models/rider_collection_monitoring_model.dart
//
// Read-only na modelo para sa Rider Collection Monitoring (HM/Employee) at
// "My Collections" summary (rider). Lahat ng halaga ay galing sa
// `collections-view?fn=rider-monitoring*` — walang client-side na financial
// computation na ginagawa (server ang source of truth).
import '../../core/utils/timezone.dart';

class RiderMonitoringSummary {
  final int activeRiders;
  final int assignedAccounts;
  final int assignedInstallments;
  final double expectedCollection;
  final double confirmedCollection;
  final double remainingDue;
  final int overdueAccounts;
  final int overdueInstallments;
  final int openAssignments;
  final int confirmedPayments;

  /// `confirmed / expected` — monitoring indicator lang, HINDI quota.
  final double? collectionPerformance;

  const RiderMonitoringSummary({
    this.activeRiders = 0,
    this.assignedAccounts = 0,
    this.assignedInstallments = 0,
    this.expectedCollection = 0,
    this.confirmedCollection = 0,
    this.remainingDue = 0,
    this.overdueAccounts = 0,
    this.overdueInstallments = 0,
    this.openAssignments = 0,
    this.confirmedPayments = 0,
    this.collectionPerformance,
  });

  factory RiderMonitoringSummary.fromJson(Map<String, dynamic> json) =>
      RiderMonitoringSummary(
        activeRiders: (json['active_riders'] as num?)?.toInt() ?? 0,
        assignedAccounts: (json['assigned_accounts'] as num?)?.toInt() ?? 0,
        assignedInstallments:
            (json['assigned_installments'] as num?)?.toInt() ?? 0,
        expectedCollection:
            (json['expected_collection'] as num?)?.toDouble() ?? 0,
        confirmedCollection:
            (json['confirmed_collection'] as num?)?.toDouble() ?? 0,
        remainingDue: (json['remaining_due'] as num?)?.toDouble() ?? 0,
        overdueAccounts: (json['overdue_accounts'] as num?)?.toInt() ?? 0,
        overdueInstallments:
            (json['overdue_installments'] as num?)?.toInt() ?? 0,
        openAssignments: (json['open_assignments'] as num?)?.toInt() ?? 0,
        confirmedPayments:
            (json['confirmed_payment_count'] as num?)?.toInt() ?? 0,
        collectionPerformance:
            (json['collection_performance'] as num?)?.toDouble(),
      );
}

class RiderMonitoringRow {
  final String riderId;
  final String riderName;
  final String? phoneNumber;
  final String? plateNumber;
  final String? vehicleType;
  final bool? isAvailable;
  final DateTime? joinedAt;
  final int assignedAccounts;
  final int assignedInstallments;
  final double expectedCollection;
  final double confirmedCollection;
  final double remainingDue;
  final int overdueAccounts;
  final int overdueInstallments;
  final int openAssignments;
  final DateTime? nextDueDate;
  final DateTime? lastActivityAt;
  final double? collectionPerformance;

  const RiderMonitoringRow({
    required this.riderId,
    required this.riderName,
    this.phoneNumber,
    this.plateNumber,
    this.vehicleType,
    this.isAvailable,
    this.joinedAt,
    this.assignedAccounts = 0,
    this.assignedInstallments = 0,
    this.expectedCollection = 0,
    this.confirmedCollection = 0,
    this.remainingDue = 0,
    this.overdueAccounts = 0,
    this.overdueInstallments = 0,
    this.openAssignments = 0,
    this.nextDueDate,
    this.lastActivityAt,
    this.collectionPerformance,
  });

  factory RiderMonitoringRow.fromJson(Map<String, dynamic> json) =>
      RiderMonitoringRow(
        riderId: (json['rider_id'] ?? '').toString(),
        riderName: (json['rider_name'] ?? '').toString(),
        phoneNumber: json['phone_number']?.toString(),
        plateNumber: json['plate_number']?.toString(),
        vehicleType: json['vehicle_type']?.toString(),
        isAvailable: json['is_available'] as bool?,
        joinedAt: parseManila(json['joined_at']),
        assignedAccounts: (json['assigned_accounts'] as num?)?.toInt() ?? 0,
        assignedInstallments:
            (json['assigned_installments'] as num?)?.toInt() ?? 0,
        expectedCollection:
            (json['expected_collection'] as num?)?.toDouble() ?? 0,
        confirmedCollection:
            (json['confirmed_collection'] as num?)?.toDouble() ?? 0,
        remainingDue: (json['remaining_due'] as num?)?.toDouble() ?? 0,
        overdueAccounts: (json['overdue_accounts'] as num?)?.toInt() ?? 0,
        overdueInstallments:
            (json['overdue_installments'] as num?)?.toInt() ?? 0,
        openAssignments: (json['open_assignments'] as num?)?.toInt() ?? 0,
        nextDueDate: json['next_due_date'] == null
            ? null
            : DateTime.tryParse(json['next_due_date'].toString()),
        lastActivityAt: parseManila(json['last_activity_at']),
        collectionPerformance:
            (json['collection_performance'] as num?)?.toDouble(),
      );
}

class RiderMonitoringPage {
  final List<RiderMonitoringRow> rows;
  final RiderMonitoringSummary summary;
  final int total;
  final int page;
  final int totalPages;

  const RiderMonitoringPage({
    this.rows = const [],
    this.summary = const RiderMonitoringSummary(),
    this.total = 0,
    this.page = 1,
    this.totalPages = 1,
  });

  factory RiderMonitoringPage.fromJson(Map<String, dynamic> json) {
    final list = (json['data'] as List?) ?? const [];
    return RiderMonitoringPage(
      rows: list
          .whereType<Map>()
          .map((e) => RiderMonitoringRow.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      summary: RiderMonitoringSummary.fromJson(
          Map<String, dynamic>.from((json['summary'] as Map?) ?? const {})),
      total: (json['total'] as num?)?.toInt() ?? list.length,
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Detail payload ng isang rider: profile, accounts, verified payments at
/// collection history. Ang nested maps ay direktang galing sa Edge Function
/// (`rider`, `accounts[].schedules`, `payments`, `history`) — display-only.
class RiderMonitoringDetail {
  final Map<String, dynamic> rider;
  final RiderMonitoringSummary summary;
  final RiderMonitoringRow? monitoring;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> history;
  final DateTime? generatedAt;

  const RiderMonitoringDetail({
    this.rider = const {},
    this.summary = const RiderMonitoringSummary(),
    this.monitoring,
    this.accounts = const [],
    this.payments = const [],
    this.history = const [],
    this.generatedAt,
  });

  factory RiderMonitoringDetail.fromJson(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from((json['data'] as Map?) ?? const {});
    List<Map<String, dynamic>> listOf(dynamic value) =>
        ((value as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
    return RiderMonitoringDetail(
      rider: Map<String, dynamic>.from((data['rider'] as Map?) ?? const {}),
      summary: RiderMonitoringSummary.fromJson(
          Map<String, dynamic>.from((data['summary'] as Map?) ?? const {})),
      monitoring: data['monitoring'] is Map
          ? RiderMonitoringRow.fromJson(
              Map<String, dynamic>.from(data['monitoring'] as Map))
          : null,
      accounts: listOf(data['accounts']),
      payments: listOf(data['payments']),
      history: listOf(data['history']),
      generatedAt: parseManila(json['generated_at']),
    );
  }
}

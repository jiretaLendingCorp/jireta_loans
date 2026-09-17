// lib/data/models/disbursement_model.dart
import '../../core/utils/timezone.dart';

class DisbursementModel {
  final String id;
  final String loanId;
  final String method;
  final double amount;
  final String status;
  final String? xenditDisbursementId;
  final String? xenditStatus;
  final String? gcashNumber;
  final String? riderId;
  final String? disbursedBy;
  /// Pangalan ng nag-release (mula sa `authorized_by` → users join). Ang
  /// `disbursedBy` ay UUID ng user, kaya ito ang dapat ipakita sa UI.
  final String? disbursedByName;
  final DateTime? disbursedAt;
  final DateTime? deliveryDate;
  final String? notes;
  final DateTime createdAt;
  final Map<String, dynamic>? loan;
  final Map<String, dynamic>? rider;
  // Rider-delivery COD proofs (signed URLs mula sa disbursements-view).
  final String? deliveryProof;
  final String? deliveryProof2;
  final String? borrowerSignature;

  const DisbursementModel({
    required this.id,
    required this.loanId,
    required this.method,
    required this.amount,
    required this.status,
    this.xenditDisbursementId,
    this.xenditStatus,
    this.gcashNumber,
    this.riderId,
    this.disbursedBy,
    this.disbursedByName,
    this.disbursedAt,
    this.deliveryDate,
    this.notes,
    required this.createdAt,
    this.loan,
    this.rider,
    this.deliveryProof,
    this.deliveryProof2,
    this.borrowerSignature,
  });

  // Forward-compat: canonical columns are method_id + status_id (uuid FK -> lookup.id).
  static String _resolveCode(Map<String, dynamic> json, String codeKey, String idKey, String joinKey) {
    final code = json[codeKey];
    if (code is String && code.isNotEmpty) return code;
    final join = json[joinKey];
    if (join is Map && join['code'] is String && (join['code'] as String).isNotEmpty) return join['code'] as String;
    final id = json[idKey];
    if (id is String && id.isNotEmpty) return id;
    return '';
  }

  factory DisbursementModel.fromJson(Map<String, dynamic> json) =>
      DisbursementModel(
        id: json['id'] ?? '',
        loanId: json['loan_id'] ?? '',
        method: _resolveCode(json, 'method', 'method_id', 'disbursement_methods').isNotEmpty
            ? _resolveCode(json, 'method', 'method_id', 'disbursement_methods')
            : 'gcash',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        status: _resolveCode(json, 'status', 'status_id', 'disbursement_statuses').isNotEmpty
            ? _resolveCode(json, 'status', 'status_id', 'disbursement_statuses')
            : 'pending',
        xenditDisbursementId: json['xendit_disbursement_id'],
        xenditStatus: json['xendit_status'],
        gcashNumber: json['gcash_number'],
        riderId: json['rider_id'],
        disbursedBy: json['disbursed_by'],
        disbursedByName: (json['disbursed_by_name'] as String?)?.trim(),
        disbursedAt: json['disbursed_at'] != null
            ? parseManila(json['disbursed_at'])
            : null,
        deliveryDate: json['delivery_date'] != null
            ? parseManila(json['delivery_date'])
            : null,
        notes: json['notes'],
        createdAt: json['created_at'] != null
            ? parseManila(json['created_at'])!
            : DateTime.now(),
        loan: json['loan'] as Map<String, dynamic>?,
        rider: json['rider'] as Map<String, dynamic>?,
        deliveryProof: json['delivery_proof'] as String?,
        deliveryProof2: json['delivery_proof_2'] as String?,
        borrowerSignature: json['borrower_signature'] as String?,
      );

  String get loanNumber => loan?['loan_number'] ?? '';

  /// Rider display name mula sa `rider` join (users.first_name + last_name).
  /// Fallback sa `disbursedBy` kapag walang join (UUID man ito o pangalan).
  String get riderName {
    final r = rider;
    if (r != null) {
      final u = r['users'];
      Map<String, dynamic>? user;
      if (u is Map<String, dynamic>) {
        user = u;
      } else if (u is List && u.isNotEmpty && u.first is Map) {
        user = Map<String, dynamic>.from(u.first as Map);
      }
      if (user != null) {
        final name =
            '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
        if (name.isNotEmpty) return name;
      }
      for (final k in ['name', 'full_name', 'rider_name']) {
        final v = (r[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
    }
    return disbursedBy ?? '';
  }  String get lenderName {
    final flat = loan?['lender_name'] as String?;
    if (flat != null && flat.trim().isNotEmpty) return flat;
    final lp = loan?['lender_profiles'] as Map<String, dynamic>?;
    final u = lp?['users'] as Map<String, dynamic>?;
    if (u == null) return '';
    return '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
  }

  String get methodLabel {
    switch (method) {
      case 'gcash':
        return 'GCash';
      case 'office_cash':
        return 'Office Cash';
      case 'rider_delivery':
        return 'Cash on Delivery';
      default:
        return method;
    }
  }

  static final _uuidRe = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  /// Pangalan ng nag-release ng Office Cash (`authorized_by` → users join).
  /// Ang `disbursed_by` ay UUID ng user kaya hindi ito ipinapakita — 'N/A'
  /// na lang kapag wala ang name join (hal. lumang row o hindi pa deployed
  /// ang `disbursements-view` na may `disbursed_by_name`).
  String get disbursedByLabel {
    final name = (disbursedByName ?? '').trim();
    if (name.isNotEmpty) return name;
    final raw = (disbursedBy ?? '').trim();
    if (raw.isEmpty || _uuidRe.hasMatch(raw)) return 'N/A';
    return raw; // legacy rows na pangalan mismo ang nakaimbak
  }

  String get disbursementMethod => method;
  String get reference => xenditDisbursementId ?? '';
}

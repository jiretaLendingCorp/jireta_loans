// lib/data/models/penalty_log_model.dart
import '../../domain/entities/penalty_log_entity.dart';

class PenaltyLogModel extends PenaltyLogEntity {
  const PenaltyLogModel({
    required super.id,
    required super.loanId,
    super.loanNumber,
    super.lenderName,
    required super.basisAmount,
    required super.penaltyRate,
    required super.penaltyAmount,
    required super.appliedById,
    super.appliedByName,
    required super.createdAt,
  });

  factory PenaltyLogModel.fromJson(Map<String, dynamic> json) =>
      PenaltyLogModel(
        id: json['id'] ?? '',
        loanId: json['loan_id'] ?? '',
        loanNumber: json['loan']?['loan_number'],
        lenderName: json['loan']?['lender'] != null
            ? '${json['loan']['lender']['first_name']} ${json['loan']['lender']['last_name']}'
            : null,
        basisAmount: (json['basis_amount'] as num?)?.toDouble() ?? 0,
        penaltyRate: (json['penalty_rate'] as num?)?.toDouble() ?? 0.20,
        penaltyAmount: (json['penalty_amount'] as num?)?.toDouble() ?? 0,
        appliedById: json['applied_by'] ?? '',
        appliedByName: json['applier'] != null
            ? '${json['applier']['first_name']} ${json['applier']['last_name']}'
            : null,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : DateTime.now(),
      );
}

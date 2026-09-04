// lib/data/models/terms_consent_log_model.dart
import '../../core/utils/helpers.dart';
import '../../core/utils/timezone.dart';
class TermsConsentLogModel {
  final String id;
  final String? userId;
  final String deviceId;
  final String termsVersion;
  final bool accepted;
  final String? ipAddress;
  final DateTime createdAt;

  const TermsConsentLogModel({
    required this.id,
    this.userId,
    required this.deviceId,
    required this.termsVersion,
    required this.accepted,
    this.ipAddress,
    required this.createdAt,
  });

  factory TermsConsentLogModel.fromJson(Map<String, dynamic> json) {
    return TermsConsentLogModel(
      id: json['id'] ?? '',
      userId: json['user_id'],
      deviceId: json['device_id'] ?? '',
      termsVersion: json['terms_version'] ?? '1.0',
      accepted: parseBool(json['accepted'], fallback: false),
      ipAddress: json['ip_address'],
      createdAt: json['created_at'] != null
          ? parseManila(json['created_at'])!
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'device_id': deviceId,
        'terms_version': termsVersion,
        'accepted': accepted,
        'ip_address': ipAddress,
        'created_at': createdAt.toIso8601String(),
      };
}

// lib/data/models/auth_log_model.dart
import '../../core/utils/timezone.dart';

class AuthLogModel {
  final String id;
  final String? userId;
  final String event;
  final String? ipAddress;
  final String? userAgent;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const AuthLogModel({
    required this.id,
    this.userId,
    required this.event,
    this.ipAddress,
    this.userAgent,
    this.metadata,
    required this.createdAt,
  });

  factory AuthLogModel.fromJson(Map<String, dynamic> json) {
    return AuthLogModel(
      id: json['id'] ?? '',
      userId: json['user_id'],
      event: json['event'] ?? '',
      ipAddress: json['ip_address'],
      userAgent: json['user_agent'],
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: json['created_at'] != null
          ? parseManila(json['created_at'])!
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'event': event,
        'ip_address': ipAddress,
        'user_agent': userAgent,
        'metadata': metadata,
        'created_at': createdAt.toIso8601String(),
      };
}

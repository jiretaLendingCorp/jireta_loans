// lib/data/models/sms_log_model.dart
class SmsLogModel {
  final String id;
  final String? userId;
  final String phoneNumber;
  final String message;
  final String status;
  final String? provider;
  final String? messageId;
  final DateTime createdAt;

  const SmsLogModel({
    required this.id,
    this.userId,
    required this.phoneNumber,
    required this.message,
    required this.status,
    this.provider,
    this.messageId,
    required this.createdAt,
  });

  factory SmsLogModel.fromJson(Map<String, dynamic> json) => SmsLogModel(
        id: json['id'] ?? '',
        userId: json['user_id'],
        phoneNumber: json['phone_number'] ?? '',
        message: json['message'] ?? '',
        status: json['status'] ?? 'sent',
        provider: json['provider'],
        messageId: json['message_id'],
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : DateTime.now(),
      );
}

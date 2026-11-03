// lib/data/models/account_deletion_request_model.dart
//
// Isang row mula sa `public.account_deletion_requests` (Head Manager queue).
// Ang `identifier`/`full_name` ay binubura ng server pagkatapos ma-process —
// kaya nullable ang dalawang iyon.
class AccountDeletionRequestModel {
  final String id;
  final String reference;
  final String? userId;
  final String? role;
  final String? identifier;
  final String identifierType;
  final String? fullName;
  final String? reason;
  final String source;
  final String status;
  final DateTime? requestedAt;
  final DateTime? processedAt;
  final String? processedBy;
  final String? notes;

  const AccountDeletionRequestModel({
    required this.id,
    required this.reference,
    this.userId,
    this.role,
    this.identifier,
    required this.identifierType,
    this.fullName,
    this.reason,
    required this.source,
    required this.status,
    this.requestedAt,
    this.processedAt,
    this.processedBy,
    this.notes,
  });

  factory AccountDeletionRequestModel.fromJson(Map<String, dynamic> json) {
    return AccountDeletionRequestModel(
      id: (json['id'] ?? '').toString(),
      reference: (json['reference'] ?? '').toString(),
      userId: _stringOrNull(json['user_id']),
      role: _stringOrNull(json['role']),
      identifier: _stringOrNull(json['identifier']),
      identifierType: (json['identifier_type'] ?? 'phone').toString(),
      fullName: _stringOrNull(json['full_name']),
      reason: _stringOrNull(json['reason']),
      source: (json['source'] ?? 'web').toString(),
      status: (json['status'] ?? 'pending').toString(),
      requestedAt: _dateOrNull(json['requested_at']),
      processedAt: _dateOrNull(json['processed_at']),
      processedBy: _stringOrNull(json['processed_by']),
      notes: _stringOrNull(json['notes']),
    );
  }

  static String? _stringOrNull(Object? value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  static DateTime? _dateOrNull(Object? value) =>
      DateTime.tryParse((value ?? '').toString());

  bool get isPending => status == 'pending' || status == 'processing';

  String get displayName {
    if (fullName != null && fullName!.trim().isNotEmpty) return fullName!;
    // Binubura ng server ang full_name/identifier kapag na-DELETE talaga ang
    // account. Ang rejected na request ay hindi nagbura ng account, kaya hindi
    // "Deleted account" ang tamang label doon.
    if (status == 'completed') return 'Deleted account';
    return isPending ? 'Unknown' : 'Unnamed requester';
  }

  String get sourceLabel => source == 'in_app' ? 'In-app' : 'Public page';

  String get statusLabel => switch (status) {
        'pending' => 'Pending',
        'processing' => 'Processing',
        'completed' => 'Completed',
        'rejected' => 'Rejected',
        _ => status,
      };

  String get roleLabel => switch (role) {
        'lender' => 'Lendee',
        'rider' => 'Rider',
        'employee' => 'Employee',
        'head_manager' => 'Head Manager',
        _ => 'Unknown',
      };
}

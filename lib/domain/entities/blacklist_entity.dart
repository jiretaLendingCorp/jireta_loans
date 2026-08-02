// lib/domain/entities/blacklist_entity.dart
class BlacklistEntity {
  final String id;
  final String lenderId;
  final String? lenderName;
  final String reason;
  final String addedById;
  final String? addedByName;
  final bool isActive;
  final String? removedById;
  final String? removedByName;
  final DateTime? removedAt;
  final DateTime createdAt;

  const BlacklistEntity({
    required this.id,
    required this.lenderId,
    this.lenderName,
    required this.reason,
    required this.addedById,
    this.addedByName,
    required this.isActive,
    this.removedById,
    this.removedByName,
    this.removedAt,
    required this.createdAt,
  });
}

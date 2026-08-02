// lib/domain/entities/co_maker_entity.dart
class CoMakerEntity {
  final String id;
  final String loanId;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String relationship;
  final String? contactNumber;
  final String? address;
  final DateTime? birthday;
  final List<Map<String, dynamic>>? documents;
  final DateTime createdAt;

  const CoMakerEntity({
    required this.id,
    required this.loanId,
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.relationship,
    this.contactNumber,
    this.address,
    this.birthday,
    this.documents,
    required this.createdAt,
  });

  String get fullName => [firstName, middleName, lastName]
      .where((p) => p != null && p.isNotEmpty)
      .join(' ');
}

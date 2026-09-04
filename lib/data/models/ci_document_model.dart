// lib/data/models/ci_document_model.dart
import '../../core/utils/helpers.dart';
import '../../core/utils/timezone.dart';
class CiDocumentModel {
  final String id;
  final String ciId;
  final String riderId;
  final String documentType;
  final String fileUrl;
  final String? caption;
  final double? latitude;
  final double? longitude;
  final bool gpsSpoof;
  final DateTime createdAt;

  const CiDocumentModel({
    required this.id,
    required this.ciId,
    required this.riderId,
    required this.documentType,
    required this.fileUrl,
    this.caption,
    this.latitude,
    this.longitude,
    required this.gpsSpoof,
    required this.createdAt,
  });

  factory CiDocumentModel.fromJson(Map<String, dynamic> json) {
    return CiDocumentModel(
      id: json['id'] ?? '',
      ciId: json['ci_id'] ?? '',
      riderId: json['rider_id'] ?? '',
      documentType: json['document_type'] ?? '',
      fileUrl: json['file_url'] ?? '',
      caption: json['caption'],
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      gpsSpoof: parseBool(json['gps_spoof'], fallback: false),
      createdAt: json['created_at'] != null
          ? parseManila(json['created_at'])!
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ci_id': ciId,
        'rider_id': riderId,
        'document_type': documentType,
        'file_url': fileUrl,
        'caption': caption,
        'latitude': latitude,
        'longitude': longitude,
        'gps_spoof': gpsSpoof,
        'created_at': createdAt.toIso8601String(),
      };
}

// lib/presentation/features/lender/documents/providers/lender_documents_provider.dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/network/dio_client.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/services/supabase_storage_service.dart';
import '../../../../../data/models/kyc_document_model.dart';

class LenderDocumentsState {
  final List<KycDocumentModel> documents;
  final bool isLoading;
  final bool isUploading;
  final double uploadProgress;
  final String? error;

  const LenderDocumentsState({
    this.documents = const [],
    this.isLoading = false,
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.error,
  });

  LenderDocumentsState copyWith({
    List<KycDocumentModel>? documents,
    bool? isLoading,
    bool? isUploading,
    double? uploadProgress,
    String? error,
  }) =>
      LenderDocumentsState(
        documents: documents ?? this.documents,
        isLoading: isLoading ?? this.isLoading,
        isUploading: isUploading ?? this.isUploading,
        uploadProgress: uploadProgress ?? this.uploadProgress,
        error: error,
      );
}

class LenderDocumentsNotifier extends StateNotifier<LenderDocumentsState> {
  final DioClient _client;
  final SupabaseStorageService _storage;

  LenderDocumentsNotifier(this._client, this._storage)
      : super(const LenderDocumentsState());

  Future<void> loadDocuments() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _client.get(ApiEndpoints.kycGetStatus);
      final data = res.data as Map<String, dynamic>;
      final docs = (data['documents'] as List?)
              ?.map((d) => KycDocumentModel.fromJson(d as Map<String, dynamic>))
              .toList() ??
          [];
      state = state.copyWith(documents: docs, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> uploadDocument({
    required File file,
    required String docType,
    required String mimeType,
  }) async {
    state = state.copyWith(isUploading: true, uploadProgress: 0.0, error: null);
    try {
      state = state.copyWith(uploadProgress: 0.3);
      final url = await _storage.uploadFile(
        bucket: 'kyc-documents',
        file: file,
        folder: 'kyc',
      );
      state = state.copyWith(uploadProgress: 0.7);

      await _client.post(ApiEndpoints.kycSubmit, data: {
        'documents': [
          {
            'document_type': docType,
            'file_url': url,
            'file_name': file.path.split('\\').last.split('/').last,
            'file_size': file.lengthSync(),
            'mime_type': mimeType,
          },
        ],
      });

      state = state.copyWith(uploadProgress: 1.0, isUploading: false);
      await loadDocuments();
      return true;
    } catch (e) {
      state = state.copyWith(isUploading: false, error: e.toString());
      return false;
    }
  }

  Future<void> refresh() => loadDocuments();
}

final lenderDocumentsProvider =
    StateNotifierProvider<LenderDocumentsNotifier, LenderDocumentsState>((ref) {
  return LenderDocumentsNotifier(sl<DioClient>(), sl<SupabaseStorageService>());
});

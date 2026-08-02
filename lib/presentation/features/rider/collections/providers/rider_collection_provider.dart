// lib/presentation/features/rider/collections/providers/rider_collection_provider.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/utils/helpers.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/models/collection_assignment_model.dart';

class RiderCollectionState {
  final List<CollectionAssignmentModel> collections;
  final CollectionAssignmentModel? selectedCollection;
  final bool isLoading;
  final String? error;
  final String activeTab;
  final bool isSubmitting;

  const RiderCollectionState({
    this.collections = const [],
    this.selectedCollection,
    this.isLoading = false,
    this.error,
    this.activeTab = 'pending',
    this.isSubmitting = false,
  });

  RiderCollectionState copyWith({
    List<CollectionAssignmentModel>? collections,
    CollectionAssignmentModel? selectedCollection,
    bool? isLoading,
    String? error,
    String? activeTab,
    bool? isSubmitting,
  }) =>
      RiderCollectionState(
        collections: collections ?? this.collections,
        selectedCollection: selectedCollection ?? this.selectedCollection,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        activeTab: activeTab ?? this.activeTab,
        isSubmitting: isSubmitting ?? this.isSubmitting,
      );
}

class RiderCollectionNotifier extends StateNotifier<RiderCollectionState> {
  final CollectionRemoteDataSource _ds;

  RiderCollectionNotifier(this._ds)
      : super(const RiderCollectionState()) {
    load();
  }

  Future<void> load({String? status}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final list = await _ds.getCollectionList(
        status: status ?? state.activeTab,
        page: 1,
      );
      state = state.copyWith(collections: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setTab(String tab) {
    state = state.copyWith(activeTab: tab);
    load(status: tab);
  }

  Future<void> loadDetails(String assignmentId) async {
    try {
      final list = await _ds.getCollectionList(page: 1, limit: 100);
      final matches = list.where((c) => c.id == assignmentId);
      state = state.copyWith(
        selectedCollection: matches.isEmpty ? null : matches.first,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> accept(String assignmentId) async {
    state = state.copyWith(isSubmitting: true);
    try {
      await _ds.acceptCollection(assignmentId: assignmentId);
      state = state.copyWith(isSubmitting: false);
      await load();
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  Future<bool> decline(String assignmentId) async {
    state = state.copyWith(isSubmitting: true);
    try {
      await _ds.declineCollection(assignmentId: assignmentId);
      state = state.copyWith(isSubmitting: false);
      await load();
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  Future<bool> recordCollection({
    required String assignmentId,
    required double amountCollected,
    String? notes,
  }) async {
    state = state.copyWith(isSubmitting: true);
    try {
      final key = AppHelpers.generateIdempotencyKey();
      await _ds.recordCollection(
        assignmentId: assignmentId,
        amountCollected: amountCollected,
        notes: notes,
        idempotencyKey: key,
      );
      state = state.copyWith(isSubmitting: false);
      await load();
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  Future<bool> uploadProof({
    required String assignmentId,
    required XFile proofPhoto,
    XFile? scenePhoto,
    String? signatureBase64,
  }) async {
    state = state.copyWith(isSubmitting: true);
    try {
      final proofs = <Map<String, dynamic>>[];
      proofs.add(await _fileToProof(proofPhoto, 'proof_photo'));
      if (scenePhoto != null) {
        proofs.add(await _fileToProof(scenePhoto, 'scene_photo'));
      }
      if (signatureBase64 != null) {
        proofs.add({'type': 'signature', 'content_base64': signatureBase64});
      }
      await _ds.uploadProof(assignmentId: assignmentId, proofs: proofs);
      state = state.copyWith(isSubmitting: false);
      await load();
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  Future<Map<String, dynamic>> _fileToProof(XFile file, String type) async {
    final bytes = await file.readAsBytes();
    return {
      'type': type,
      'file_name': file.name,
      'mime_type': 'image/jpeg',
      'content_base64': base64Encode(bytes),
    };
  }

  Future<void> refresh() => load();
}

final riderCollectionProvider =
    StateNotifierProvider<RiderCollectionNotifier, RiderCollectionState>((ref) {
  return RiderCollectionNotifier(
    sl<CollectionRemoteDataSource>(),
  );
});

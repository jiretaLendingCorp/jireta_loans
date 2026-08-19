// lib/presentation/features/rider/collections/providers/rider_collection_provider.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/utils/helpers.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/models/collection_assignment_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';
import '../../location/providers/rider_location_provider.dart';

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
    this.activeTab = 'assigned',
    this.isSubmitting = false,
  });

  RiderCollectionState copyWith({
    List<CollectionAssignmentModel>? collections,
    CollectionAssignmentModel? selectedCollection,
    bool clearSelection = false,
    bool? isLoading,
    String? error,
    String? activeTab,
    bool? isSubmitting,
  }) =>
      RiderCollectionState(
        collections: collections ?? this.collections,
        selectedCollection: clearSelection
            ? null
            : selectedCollection ?? this.selectedCollection,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        activeTab: activeTab ?? this.activeTab,
        isSubmitting: isSubmitting ?? this.isSubmitting,
      );
}

class RiderCollectionNotifier extends StateNotifier<RiderCollectionState>
    with RealtimeRefreshMixin {
  final CollectionRemoteDataSource _ds;
  final Ref _ref;

  RiderCollectionNotifier(this._ds, this._ref)
      : super(const RiderCollectionState()) {
    bindRealtimeRefresh(['collection_assignments', 'payments'],
        refresh: () => load(silent: true));
    load();
  }

  Future<void> load({String? status, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final list = await _ds.getCollectionList(
        status: status ?? state.activeTab,
        page: 1,
      );
      state = state.copyWith(collections: list, isLoading: false);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setTab(String tab) {
    state = state.copyWith(activeTab: tab);
    load(status: tab);
  }

  Future<void> loadDetails(String assignmentId, {bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(
          isLoading: true, error: null, clearSelection: true);
    }
    try {
      final list = await _ds.getCollectionList(page: 1, limit: 100);
      final matches = list.where((c) => c.id == assignmentId);
      state = state.copyWith(
        selectedCollection: matches.isEmpty ? null : matches.first,
        isLoading: false,
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  Future<bool> accept(String assignmentId) async {
    state = state.copyWith(isSubmitting: true);
    try {
      await _ds.acceptCollection(assignmentId: assignmentId);
      _ref.read(riderLocationProvider.notifier).startTracking();
      state = state.copyWith(isSubmitting: false);
      await load();
      await loadDetails(assignmentId, silent: true);
      return true;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
      return false;
    }
  }

  Future<bool> decline(String assignmentId) async {
    state = state.copyWith(isSubmitting: true);
    try {
      await _ds.declineCollection(assignmentId: assignmentId);
      _ref.read(riderLocationProvider.notifier).stopTracking();
      state = state.copyWith(isSubmitting: false);
      await load();
      await loadDetails(assignmentId, silent: true);
      return true;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
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
      await loadDetails(assignmentId, silent: true);
      return true;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
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
      _ref.read(riderLocationProvider.notifier).stopTracking();
      state = state.copyWith(isSubmitting: false);
      await load();
      await loadDetails(assignmentId, silent: true);
      return true;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
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

final riderCollectionProvider = AutoDisposeStateNotifierProvider<
    RiderCollectionNotifier, RiderCollectionState>((ref) {
  return RiderCollectionNotifier(
    sl<CollectionRemoteDataSource>(),
    ref,
  );
});

// ignore_for_file: avoid_print
// lib/presentation/features/rider/collections/providers/rider_collection_provider.dart
import 'dart:async';
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
    } catch (e, st) {
      print('load collections failed: $e');
      print(st);
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setTab(String tab) {
    state = state.copyWith(activeTab: tab);
    load(status: tab);
  }

  /// Autoritatibong bersyon ng assignment, direkta sa `getCollectionById`.
  ///
  /// Hindi tulad ng [loadDetails], hindi ito tumitingin sa naka-cache na
  /// listahan. Kailangan ito sa submit (Step 3) para ang `status` AT ang
  /// `amountCollected` na gagamitin ay galing talaga sa server — hindi sa
  /// lumang cached id na puwedeng may ibang halaga (maling amount ang
  /// maire-record, o makumpirma/ma-deny ang completion nang mali).
  Future<CollectionAssignmentModel?> fetchFresh(String assignmentId) async {
    try {
      final exact = await _ds.getCollectionById(assignmentId);
      if (exact != null) {
        state = state.copyWith(selectedCollection: exact);
        return exact;
      }
    } catch (e) {
      print('fetchFresh failed for $assignmentId: $e');
    }
    return null;
  }

  /// Status lamang mula sa autoritatibong fetch (para sa success verification).
  Future<String?> fetchStatus(String assignmentId) async {
    final fresh = await fetchFresh(assignmentId);
    return fresh?.status;
  }

  Future<void> loadDetails(String assignmentId, {bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(
          isLoading: true, error: null, clearSelection: true);
    }
    try {
      // Accepted collections are stored under status='accepted'/'in_progress', 
      // so fetching without status (which defaults to 'assigned' on some backends) 
      // makes accepted items appear as "not found". Try multiple statuses and
      // fallback to unfiltered fetch. Also check already-loaded lists first.
      CollectionAssignmentModel? found;
      // 1) check already-loaded collections (assigned/accepted tabs)
      try {
        found = state.collections.firstWhere((c) => c.id == assignmentId);
      } catch (_) {}
      if (found != null) {
        state = state.copyWith(selectedCollection: found, isLoading: false);
        return;
      }
      // 2) EKSAKTONG fetch by id (collections-view?fn=get). Ito ang dapat unahin:
      // isang query lang, at walang "not found" na dulot ng isang tahimik na
      // nabigong status-scan sa ibaba (katulad ng dati na nagpapakita ng
      // "Collection not found" bago pa dumating ang totoong data).
      try {
        final exact = await _ds.getCollectionById(assignmentId);
        if (exact != null) {
          state = state.copyWith(selectedCollection: exact, isLoading: false);
          return;
        }
      } catch (e) {
        // Fall through sa list-based search sa ibaba.
        print('loadDetails exact fetch failed, falling back to list scan: $e');
      }
      // 3) try unfiltered fetch
      var list = await _ds.getCollectionList(page: 1, limit: 100);
      var matches = list.where((c) => c.id == assignmentId);
      if (matches.isNotEmpty) {
        state = state.copyWith(selectedCollection: matches.first, isLoading: false);
        return;
      }
      // 4) try each status tab that rider uses
      for (final status in ['accepted', 'in_progress', 'assigned', 'completed', 'declined']) {
        try {
          list = await _ds.getCollectionList(status: status, page: 1, limit: 100);
          matches = list.where((c) => c.id == assignmentId);
          if (matches.isNotEmpty) {
            state = state.copyWith(selectedCollection: matches.first, isLoading: false);
            return;
          }
        } catch (_) {}
      }
      // Not found in any status
      state = state.copyWith(selectedCollection: null, isLoading: false);
    } catch (e, st) {
      if (!silent) {
        // Log full type error for String vs bool debugging
        print('loadDetails failed: $e');
        print(st);
      }
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
      await _safeRefresh(assignmentId);
      return true;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
      return false;
    }
  }

  /// Refresh pagkatapos ng mutation — best-effort at HINDI hinihintay.
  ///
  /// Dati, ang `load()` (buong listahan) at `loadDetails()` ay nasa loob ng
  /// parehong `try` ng POST: kapag nabigo ang alinman sa kanila (mabagal na
  /// network, timeout), ang isang MATAGUMPAY na record/upload ay nagreresulta
  /// ng "Failed to record/upload" sa rider — kahit naisave na sa server ang
  /// amount at proof. Ngayon, hiwalay na sila at nasa background, kaya mabilis
  /// ding bumalik ang Submit.
  Future<void> _safeRefresh(String assignmentId) async {
    try {
      await loadDetails(assignmentId, silent: true);
    } catch (_) {}
    // Ang buong listahan ay sa background — hindi hinihintay para hindi mabagal
    // ang Submit (bawat row kasi doon ay may proof URL signing sa server).
    unawaited(() async {
      try {
        await load();
      } catch (_) {}
    }());
  }

  Future<String?> uploadProof({
    required String assignmentId,
    required XFile proofPhoto,
    XFile? scenePhoto,
    String? signatureBase64,
    /// Ipinapasa sa backend bilang `amount_collected` — kapag wala pang
    /// verified payment, ito ang itatala ng `fn=upload-proof` (self-heal) kaya
    /// hindi na ma-stuck ang rider sa PAYMENT_NOT_RECORDED.
    ///
    /// Ito rin ang tanging tawag sa Step 3 Submit: dito na nagse-save ang
    /// amount AT ang proof nang sabay — hindi na kailangang mag-record muna ng
    /// hiwalay (mas mabilis, walang kalahating-saved na state).
    double? amountCollected,
    String? notes,
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
      final status = await _ds.uploadProof(
        assignmentId: assignmentId,
        proofs: proofs,
        amountCollected: amountCollected,
        notes: notes,
      );
      _ref.read(riderLocationProvider.notifier).stopTracking();
      state = state.copyWith(isSubmitting: false);
      unawaited(_safeRefresh(assignmentId));
      return status;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
      return null;
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

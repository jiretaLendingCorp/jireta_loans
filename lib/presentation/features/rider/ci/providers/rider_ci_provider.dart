// lib/presentation/features/rider/ci/providers/rider_ci_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/ci_remote_datasource.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';
import '../../location/providers/rider_location_provider.dart';

class RiderCiState {
  final List<CreditInvestigationModel> ciList;
  final CreditInvestigationModel? selectedCi;
  final bool isLoading;
  final String? error;
  final String activeTab;
  final bool isSubmitting;

  const RiderCiState({
    this.ciList = const [],
    this.selectedCi,
    this.isLoading = false,
    this.error,
    this.activeTab = 'assigned',
    this.isSubmitting = false,
  });

  List<CreditInvestigationModel> get investigations => ciList;

  RiderCiState copyWith({
    List<CreditInvestigationModel>? ciList,
    CreditInvestigationModel? selectedCi,
    bool? isLoading,
    String? error,
    String? activeTab,
    bool? isSubmitting,
  }) =>
      RiderCiState(
        ciList: ciList ?? this.ciList,
        selectedCi: selectedCi ?? this.selectedCi,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        activeTab: activeTab ?? this.activeTab,
        isSubmitting: isSubmitting ?? this.isSubmitting,
      );
}

class RiderCiNotifier extends StateNotifier<RiderCiState>
    with RealtimeRefreshMixin {
  final CiRemoteDataSource _ds;
  final Ref _ref;

  RiderCiNotifier(this._ds, this._ref) : super(const RiderCiState()) {
    bindRealtimeRefresh(['credit_investigations', 'ci_documents'],
        refresh: () => load(silent: true));
    load();
  }

  /// Statuses na sakop ng bawat tab.
  ///
  /// Mahalaga: kapag na-review ng staff ang isang CI, nagiging `approved` o
  /// `rejected` ito (hindi na `completed`) — kaya kasama pa rin sila sa
  /// "Completed" tab ng rider at hindi nawawala sa listahan.
  static const Map<String, String> _tabStatusQuery = {
    'assigned': 'assigned',
    'in_progress': 'in_progress',
    'completed': 'completed,approved,rejected',
    'declined': 'declined',
  };

  static const Map<String, Set<String>> _tabStatuses = {
    'assigned': {'assigned', 'accepted'},
    'in_progress': {'in_progress', 'accepted'},
    'completed': {'completed', 'approved', 'rejected'},
    'declined': {'declined'},
  };

  /// Ang `status` ay kadalasang TAB NAME ('assigned' / 'in_progress' /
  /// 'completed') galing sa `setTab()` — kaya dapat i-map muna ito sa tunay
  /// na query bago ang request. Kung raw lang ito ipapasa, mababalewala ang
  /// mapping at hindi lalabas ang `approved` / `rejected` sa Completed tab.
  Future<void> load({String? status, bool silent = false}) async {
    final tab = status ?? state.activeTab;
    final query = tab == 'all' ? null : (_tabStatusQuery[tab] ?? tab);
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final list = await _ds.getCiList(status: query, page: 1);
      // Guard: maaaring na-dispose na ang notifier habang tumatakbo ang
      // background refresh (hal. umalis na sa screen ang rider) — huwag nang
      // mag-set ng state pagkatapos ng dispose.
      if (!mounted) return;
      state = state.copyWith(ciList: list, isLoading: false);
    } catch (e) {
      if (silent || !mounted) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setTab(String tab) {
    state = state.copyWith(activeTab: tab);
    load(status: tab == 'all' ? null : tab);
  }

  void setFilter(String status) => setTab(status);

  Future<void> loadDetails(String ciId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final detail = await _ds.getCiDetails(ciId);
      // Directly construct new state to allow explicit null for selectedCi (not found)
      state = RiderCiState(
        ciList: state.ciList,
        selectedCi: detail == null ? null : CreditInvestigationModel.fromJson(detail),
        isLoading: false,
        activeTab: state.activeTab,
        isSubmitting: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  /// Applies a status change locally (optimistic) so the UI updates the
  /// instant the rider taps Accept / Decline / Submit instead of waiting for
  /// the follow-up list fetch. The server call + reload still run after.
  ///
  /// Items whose new status no longer belongs to the active tab are dropped
  /// from the list right away — that is what makes a declined/assigned card
  /// disappear without waiting for the network round trip.
  void _applyStatusLocally(String ciId, String status) {
    bool matchesActiveTab(String s) {
      final allowed = _tabStatuses[state.activeTab];
      return allowed == null ? true : allowed.contains(s);
    }

    final updatedList = state.ciList
        .where((ci) =>
            matchesActiveTab(ci.id == ciId ? status : ci.status))
        .map((ci) =>
            ci.id == ciId ? ci.copyWith(status: status) : ci)
        .toList();
    final selected = state.selectedCi;
    state = state.copyWith(
      ciList: updatedList,
      selectedCi: selected != null && selected.id == ciId
          ? selected.copyWith(status: status)
          : selected,
    );
  }

  Future<bool> accept(String ciId) async {
    state = state.copyWith(isSubmitting: true);
    // Instant UI: the card / wizard unlocks right away (accepted → in_progress).
    _applyStatusLocally(ciId, 'in_progress');
    try {
      await _ds.acceptCi(ciId: ciId);
      _ref.read(riderLocationProvider.notifier).startTracking();
      state = state.copyWith(isSubmitting: false);
      // Silent refresh — ang optimistikong update na ang nag-unlock sa UI, kaya
      // hindi na dapat mag-shimmer ang listahan habang nag-aantay ng network.
      await load(silent: true);
      return true;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
      // The optimistic update may have removed the item from the current tab;
      // reload from the server so the true state is restored.
      await _restoreAfterFailure(ciId);
      return false;
    }
  }

  Future<bool> decline(String ciId) async {
    state = state.copyWith(isSubmitting: true);
    // Instant UI: the assignment card/design disappears right away.
    _applyStatusLocally(ciId, 'declined');
    try {
      await _ds.declineCi(ciId: ciId);
      _ref.read(riderLocationProvider.notifier).stopTracking();
      state = state.copyWith(isSubmitting: false);
      await load(silent: true);
      return true;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
      await _restoreAfterFailure(ciId);
      return false;
    }
  }

  Future<bool> submitReport({
    required String ciId,
    required String reportSummary,
  }) async {
    state = state.copyWith(isSubmitting: true);
    // NO optimistic 'completed' here: the confirm dialog's Yes button shows a
    // spinner while the upload + submit run, and the wizard must NOT flip to
    // the completed view until that loading finishes and the server confirms.
    // The completed state appears via the loadDetails() reload after success.
    try {
      await _ds.submitCiReport(ciId: ciId, reportSummary: reportSummary);
      _ref.read(riderLocationProvider.notifier).stopTracking();
      if (!mounted) return true;
      state = state.copyWith(isSubmitting: false);
      // HINDI na hinihintay ang list reload — ang server confirmation na ang
      // nagtatapos sa loading ng Submit. Dating `await load(silent: true)` ito
      // kaya dagdag na 2-5s na paghihintay sa spinner bago mag-success dialog.
      unawaited(load(silent: true));
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
      await _restoreAfterFailure(ciId);
      return false;
    }
  }

  /// Restores the server truth after a failed action: reloads the selected
  /// CI details when this provider is showing a detail screen, otherwise
  /// silently refreshes the list.
  Future<void> _restoreAfterFailure(String ciId) async {
    if (state.selectedCi?.id == ciId) {
      await loadDetails(ciId);
    } else {
      await load(silent: true);
    }
  }

  Future<void> refresh() => load();

  Future<bool> uploadDocument({
    required String ciId,
    required XFile file,
    required String documentType,
    String? caption,
  }) async {
    state = state.copyWith(isSubmitting: true);
    try {
      final bytes = await file.readAsBytes();
      await _ds.uploadDocuments(
        ciId: ciId,
        docs: [
          {
            'file_name': file.name,
            'mime_type': 'image/jpeg',
            'content_base64': base64Encode(bytes),
            'document_type': documentType,
            if (caption != null) 'caption': caption,
          }
        ],
      );
      state = state.copyWith(isSubmitting: false);
      await load();
      return true;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
      return false;
    }
  }

  /// ISANG request para sa LAHAT ng photo — may sariling document type at
  /// caption kada isa.
  ///
  /// Dating per-photo ang upload sa "Upload CI Documents" screen (N request),
  /// at KADA photo ay may kasamang buong list reload — kaya napakabagal
  /// (N × [upload + heavy `ci-view` refetch]). Ngayon: isang batch request +
  /// isang background refresh na lang.
  /// Returns ang bilang ng na-upload (0 kapag may error).
  Future<int> uploadPhotoBatch({
    required String ciId,
    required List<({XFile file, String type, String? caption})> photos,
  }) async {
    if (photos.isEmpty) return 0;
    state = state.copyWith(isSubmitting: true);
    try {
      final docs = <Map<String, dynamic>>[];
      for (final photo in photos) {
        final bytes = await photo.file.readAsBytes();
        docs.add({
          'file_name': photo.file.name,
          'mime_type': 'image/jpeg',
          'content_base64': base64Encode(bytes),
          'document_type': photo.type,
          if (photo.caption != null && photo.caption!.isNotEmpty)
            'caption': photo.caption,
        });
      }
      await _ds.uploadDocuments(ciId: ciId, docs: docs);
      if (!mounted) return docs.length;
      state = state.copyWith(isSubmitting: false);
      // Isang background refresh lang (hindi hinihintay) para hindi na
      // humaba pa ang loading ng Upload button.
      unawaited(load(silent: true));
      return docs.length;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
            isSubmitting: false, error: ErrorHandler.handle(e).message);
      }
      return 0;
    }
  }

  Future<bool> uploadDocuments({
    required String ciId,
    required List<XFile> images,
  }) async {
    state = state.copyWith(isSubmitting: true);
    try {
      final docs = <Map<String, dynamic>>[];
      for (final image in images) {
        final bytes = await image.readAsBytes();
        docs.add({
          'file_name': image.name,
          'mime_type': 'image/jpeg',
          'content_base64': base64Encode(bytes),
          'document_type': 'site_photo',
        });
      }
      await _ds.uploadDocuments(ciId: ciId, docs: docs);
      _ref.read(riderLocationProvider.notifier).stopTracking();
      state = state.copyWith(isSubmitting: false);
      // WALANG list reload dito: ang tanging caller nito (CI wizard
      // _performSubmit) ay agad namang tumatawag ng loadDetails() at pagkatapos
      // ng submitReport() ay may sariling refresh — dagdag na round trip lang
      // ito na nagpapabagal sa Submit button.
      return true;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
      return false;
    }
  }
}

final riderCiProvider =
    AutoDisposeStateNotifierProvider<RiderCiNotifier, RiderCiState>((ref) {
  return RiderCiNotifier(sl<CiRemoteDataSource>(), ref);
});

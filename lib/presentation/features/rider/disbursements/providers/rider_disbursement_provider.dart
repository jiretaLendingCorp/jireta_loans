// lib/presentation/features/rider/disbursements/providers/rider_disbursement_provider.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/disbursement_remote_datasource.dart';
import '../../../../../data/models/disbursement_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class RiderDisbursementState {
  final List<DisbursementModel> disbursements;
  final bool isLoading;
  final String? error;
  final bool isSubmitting;

  const RiderDisbursementState({
    this.disbursements = const [],
    this.isLoading = false,
    this.error,
    this.isSubmitting = false,
  });

  RiderDisbursementState copyWith({
    List<DisbursementModel>? disbursements,
    bool? isLoading,
    String? error,
    bool? isSubmitting,
  }) =>
      RiderDisbursementState(
        disbursements: disbursements ?? this.disbursements,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isSubmitting: isSubmitting ?? this.isSubmitting,
      );
}

/// Resulta ng `uploadProof`.
///
/// Hindi na umaasa sa provider state ang mensahe: kapag galing sa Dashboard
/// ang rider (walang widget na nagmamatyag sa provider), ang autoDispose
/// provider ay maaaring ma-dispose HABANG tumatakbo ang mabigat na upload — at
/// kapag ini-read muli ang state, bagong notifier ang nabubuo (null ang error)
/// kaya generic na "Failed to upload proof" ang lumalabas kahit may tunay na
/// dahilan. Sa pamamagitan ng outcome, ang SAME object na nagsagawa ng submit
/// ang nagbabalik ng tamang success/error.
class ProofUploadOutcome {
  final bool success;

  /// True kapag natanggap na ng server ang proof (idempotent replay) — success
  /// pa rin ito, hindi dapat mag-error ang modal.
  final bool alreadySubmitted;

  final String? error;

  const ProofUploadOutcome({
    required this.success,
    this.alreadySubmitted = false,
    this.error,
  });
}

class RiderDisbursementNotifier extends StateNotifier<RiderDisbursementState>
    with RealtimeRefreshMixin {
  final DisbursementRemoteDataSource _ds;

  RiderDisbursementNotifier(this._ds) : super(const RiderDisbursementState()) {
    bindRealtimeRefresh(['disbursements', 'loans'],
        refresh: () => load(silent: true));
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final list = await _ds.getDisbursements(status: 'pending');
      state = state.copyWith(disbursements: list, isLoading: false);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  /// Rider uploads proof (max 2 photos + optional signature) that the cash
  /// was handed to the lender for a rider-delivery disbursement.
  /// Ang unang photo ay `proof_photo`, ang pangalawa ay `proof_photo_2`.
  ///
  /// HINDI ito nag-t-throw kahit ma-dispose ang provider habang tumatakbo —
  /// ang lahat ng state write ay dumadaan sa `if (mounted)`.
  Future<ProofUploadOutcome> uploadProof({
    required String disbursementId,
    required List<XFile> proofPhotos,
    String? signatureBase64,
  }) async {
    if (mounted) {
      state = state.copyWith(isSubmitting: true, error: null);
    }
    try {
      final proofs = <Map<String, dynamic>>[
        for (var i = 0; i < proofPhotos.length; i++)
          await _fileToProof(
              proofPhotos[i], i == 0 ? 'proof_photo' : 'proof_photo_2'),
        if (signatureBase64 != null)
          {'type': 'signature', 'content_base64': signatureBase64},
      ];
      await _ds.uploadDeliveryProof(
          disbursementId: disbursementId, proofs: proofs);
      if (mounted) state = state.copyWith(isSubmitting: false, error: null);
      // Best-effort lang ang reload ng listahan — hindi ito hinihintay at
      // hindi kasama sa try, para hindi maging "failed" ang isang matagumpay
      // na upload kahit mabagal/nabigo ang refresh.
      _safeRefresh();
      return const ProofUploadOutcome(success: true);
    } catch (e) {
      final message = ErrorHandler.handle(e).message;
      // Posibleng naisave na ng server ang proof pero nag-timeout/nabigo ang
      // response sa client (mabigat ang base64 ng 1–2 larawan). Kumpirmahin
      // muna sa server bago mag-report ng failure — kaya valid pa rin ang 1
      // o 2 na na-upload na proof.
      if (await _isAlreadySubmitted(disbursementId)) {
        if (mounted) state = state.copyWith(isSubmitting: false, error: null);
        _safeRefresh();
        return const ProofUploadOutcome(
            success: true, alreadySubmitted: true);
      }
      if (mounted) {
        state = state.copyWith(isSubmitting: false, error: message);
      }
      return ProofUploadOutcome(success: false, error: message);
    }
  }

  /// Pampublikong verification (ginagamit ng upload screen kapag may hindi
  /// inaasahang error bago mag-report ng failure).
  Future<bool> verifyProofSubmitted(String disbursementId) =>
      _isAlreadySubmitted(disbursementId);

  /// Hindi hinihintay ang reload ng listahan (background) — hindi nito dapat
  /// pahabain o gawing "failed" ang submit.
  void _safeRefresh() {
    if (!mounted) return;
    unawaited(() async {
      try {
        await load();
      } catch (_) {}
    }());
  }

  /// Sinuri sa server kung completed na ang disbursement kahit "failed" ang
  /// response na natanggap ng client (lost response / timeout).
  ///
  /// Apat na beses itong sinusubukan (may 1.5s pagitan): kapag nag-timeout ang
  /// client habang tumatakbo PA ang upload sa server (hal. ang default na 30s
  /// na timeout ay hindi naipasa sa 401-refresh retry), saka pa lang lumalabas
  /// ang `completed` na status — kung maikli ang window, mali ang "Failed to
  /// upload proof" na lumalabas kahit matagumpay naman ang submit.
  Future<bool> _isAlreadySubmitted(String disbursementId) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final d = await _ds.getDisbursementDetail(disbursementId);
        if (d != null &&
            (d.status == 'completed' ||
                d.disbursedAt != null ||
                (d.deliveryProof != null && d.deliveryProof!.isNotEmpty) ||
                (d.deliveryProof2 != null && d.deliveryProof2!.isNotEmpty))) {
          return true;
        }
      } catch (_) {}
      if (attempt == 3) break;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    return false;
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

final riderDisbursementProvider = AutoDisposeStateNotifierProvider<
    RiderDisbursementNotifier, RiderDisbursementState>((ref) {
  return RiderDisbursementNotifier(sl<DisbursementRemoteDataSource>());
});

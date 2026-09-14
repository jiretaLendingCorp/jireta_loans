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
  Future<bool> uploadProof({
    required String disbursementId,
    required List<XFile> proofPhotos,
    String? signatureBase64,
  }) async {
    state = state.copyWith(isSubmitting: true);
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
      state = state.copyWith(isSubmitting: false);
      // Best-effort lang ang reload ng listahan — hindi ito hinihintay at
      // hindi kasama sa try, para hindi maging "failed" ang isang matagumpay
      // na upload kahit mabagal/nabigo ang refresh.
      _safeRefresh();
      return true;
    } catch (e) {
      // Posibleng naisave na ng server ang proof pero nag-timeout/nabigo ang
      // response sa client (mabigat ang base64 ng 1–2 larawan). Kumpirmahin
      // muna sa server bago mag-report ng failure — kaya valid pa rin ang 1
      // o 2 na na-upload na proof.
      if (await _isAlreadySubmitted(disbursementId)) {
        state = state.copyWith(isSubmitting: false);
        _safeRefresh();
        return true;
      }
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
      return false;
    }
  }

  /// Hindi hinihintay ang reload ng listahan (background) — hindi nito dapat
  /// pahabain o gawing "failed" ang submit.
  void _safeRefresh() {
    unawaited(() async {
      try {
        await load();
      } catch (_) {}
    }());
  }

  /// Sinuri sa server kung completed na ang disbursement kahit "failed" ang
  /// response na natanggap ng client (lost response / timeout).
  ///
  /// Ilang beses itong sinusubukan (may pagitan): kapag nag-timeout ang client
  /// habang tumatakbo pa ang upload sa server, kailangan ng maliit na palugit
  /// bago lumabas ang `completed` na status.
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
      await Future<void>.delayed(const Duration(milliseconds: 1200));
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

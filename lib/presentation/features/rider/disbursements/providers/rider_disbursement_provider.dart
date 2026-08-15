// lib/presentation/features/rider/disbursements/providers/rider_disbursement_provider.dart
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

  Future<bool> uploadProof({
    required String disbursementId,
    required XFile proofPhoto,
    String? signatureBase64,
  }) async {
    state = state.copyWith(isSubmitting: true);
    try {
      final proofs = <Map<String, dynamic>>[
        await _fileToProof(proofPhoto, 'proof_photo'),
        if (signatureBase64 != null)
          {'type': 'signature', 'content_base64': signatureBase64},
      ];
      await _ds.uploadDeliveryProof(
          disbursementId: disbursementId, proofs: proofs);
      state = state.copyWith(isSubmitting: false);
      await load();
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

final riderDisbursementProvider = AutoDisposeStateNotifierProvider<
    RiderDisbursementNotifier, RiderDisbursementState>((ref) {
  return RiderDisbursementNotifier(sl<DisbursementRemoteDataSource>());
});

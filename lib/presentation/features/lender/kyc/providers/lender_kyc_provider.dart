// lib/presentation/features/lender/kyc/providers/lender_kyc_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/kyc_remote_datasource.dart';
import '../../../../../data/models/kyc_document_model.dart';

class LenderKycState {
  final KycStatusModel? kycStatus;
  final bool isLoading;
  final String? error;
  final bool isSubmitting;

  const LenderKycState({
    this.kycStatus,
    this.isLoading = false,
    this.error,
    this.isSubmitting = false,
  });

  LenderKycState copyWith({
    KycStatusModel? kycStatus,
    bool? isLoading,
    String? error,
    bool? isSubmitting,
  }) =>
      LenderKycState(
        kycStatus: kycStatus ?? this.kycStatus,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isSubmitting: isSubmitting ?? this.isSubmitting,
      );

  String get status => kycStatus?.kycStatus ?? 'pending';
  List<KycDocumentModel> get documents => kycStatus?.documents ?? const [];
  String? get rejectionNotes {
    for (final d in documents) {
      if (d.rejectionNotes != null) return d.rejectionNotes;
    }
    return null;
  }
}

class LenderKycNotifier extends StateNotifier<LenderKycState> {
  final KycRemoteDataSource _ds;

  LenderKycNotifier(this._ds) : super(const LenderKycState()) {
    loadStatus();
  }

  Future<void> loadStatus() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final status = await _ds.getKycStatus();
      state = state.copyWith(kycStatus: status, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> submitKyc(
    List<Map<String, dynamic>> documents, {
    Map<String, dynamic>? info,
  }) async {
    state = state.copyWith(isSubmitting: true);
    try {
      await _ds.submitKyc(documents, info: info);
      state = state.copyWith(isSubmitting: false);
      await loadStatus();
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  Future<void> refresh() => loadStatus();
}

final lenderKycProvider =
    StateNotifierProvider<LenderKycNotifier, LenderKycState>((ref) {
  return LenderKycNotifier(sl<KycRemoteDataSource>());
});

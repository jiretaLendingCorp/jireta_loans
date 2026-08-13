// lib/presentation/features/lender/account_upgrade/providers/lender_account_upgrade_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/account_upgrade_remote_datasource.dart';
import '../../../../../data/models/account_upgrade_document_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class LenderAccountUpgradeState {
  final AccountUpgradeStatusModel? accountUpgradeStatus;
  final bool isLoading;
  final String? error;
  final bool isSubmitting;

  const LenderAccountUpgradeState({
    this.accountUpgradeStatus,
    this.isLoading = false,
    this.error,
    this.isSubmitting = false,
  });

  LenderAccountUpgradeState copyWith({
    AccountUpgradeStatusModel? accountUpgradeStatus,
    bool? isLoading,
    String? error,
    bool? isSubmitting,
  }) =>
      LenderAccountUpgradeState(
        accountUpgradeStatus: accountUpgradeStatus ?? this.accountUpgradeStatus,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isSubmitting: isSubmitting ?? this.isSubmitting,
      );

  String get status =>
      accountUpgradeStatus?.accountUpgradeStatus ?? 'not_submitted';
  List<AccountUpgradeDocumentModel> get documents =>
      accountUpgradeStatus?.documents ?? const [];
  String? get rejectionNotes {
    for (final d in documents) {
      if (d.rejectionNotes != null) return d.rejectionNotes;
    }
    return null;
  }
}

class LenderAccountUpgradeNotifier
    extends StateNotifier<LenderAccountUpgradeState> with RealtimeRefreshMixin {
  final AccountUpgradeRemoteDataSource _ds;

  LenderAccountUpgradeNotifier(this._ds)
      : super(const LenderAccountUpgradeState()) {
    bindRealtimeRefresh(['account_upgrade_documents', 'lender_profiles'],
        refresh: loadStatus);
    loadStatus();
  }

  Future<void> loadStatus() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final status = await _ds.accountUpgradeGetStatus();
      state = state.copyWith(accountUpgradeStatus: status, isLoading: false);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  Future<bool> submitAccountUpgrade(
    List<Map<String, dynamic>> documents, {
    Map<String, dynamic>? info,
  }) async {
    state = state.copyWith(isSubmitting: true);
    try {
      await _ds.submitAccountUpgrade(documents, info: info);
      state = state.copyWith(isSubmitting: false);
      await loadStatus();
      return true;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
      return false;
    }
  }

  Future<void> refresh() => loadStatus();
}

final lenderAccountUpgradeProvider = AutoDisposeStateNotifierProvider<
    LenderAccountUpgradeNotifier, LenderAccountUpgradeState>((ref) {
  return LenderAccountUpgradeNotifier(sl<AccountUpgradeRemoteDataSource>());
});

// lib/presentation/features/employee/account_upgrade/providers/emp_account_upgrade_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/account_upgrade_remote_datasource.dart';
import '../../../../../data/models/account_upgrade_document_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class EmpAccountUpgradeState {
  final List<AccountUpgradeDocumentModel> docs;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final String statusFilter;
  final String search;

  const EmpAccountUpgradeState({
    this.docs = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.statusFilter = 'all',
    this.search = '',
  });

  EmpAccountUpgradeState copyWith({
    List<AccountUpgradeDocumentModel>? docs,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    String? statusFilter,
    String? search,
  }) =>
      EmpAccountUpgradeState(
        docs: docs ?? this.docs,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        totalCount: totalCount ?? this.totalCount,
        statusFilter: statusFilter ?? this.statusFilter,
        search: search ?? this.search,
      );
}

class EmpAccountUpgradeNotifier extends StateNotifier<EmpAccountUpgradeState>
    with RealtimeRefreshMixin {
  final AccountUpgradeRemoteDataSource _ds;

  EmpAccountUpgradeNotifier(this._ds) : super(const EmpAccountUpgradeState()) {
    bindRealtimeRefresh(['account_upgrade_documents', 'lender_profiles'],
        refresh: () => fetch(silent: true));
    fetch();
  }

  Future<void> fetch({int page = 1, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.accountUpgradeGetList(
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        page: page,
        lenderName: state.search.isEmpty ? null : state.search,
      );
      final list = (res['data'] as List? ?? [])
          .map((e) =>
              AccountUpgradeDocumentModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
        docs: list,
        isLoading: false,
        currentPage: (meta['page'] as num?)?.toInt() ?? 1,
        totalPages: (meta['total_pages'] as num?)?.toInt() ?? 1,
        totalCount: (meta['total'] as num?)?.toInt() ?? list.length,
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  // Legacy alias for existing callers
  Future<void> loadList(
      {String? status, String? search, int page = 1, bool silent = false}) async {
    if (status != null) state = state.copyWith(statusFilter: status);
    if (search != null) state = state.copyWith(search: search);
    await fetch(page: page, silent: silent);
  }

  void setStatus(String s) {
    state = state.copyWith(statusFilter: s);
    fetch();
  }

  void setSearch(String s) {
    state = state.copyWith(search: s);
    fetch();
  }

  Future<bool> verifyDoc({
    required String accountUpgradeDocId,
    required String action,
    String? rejectionNotes,
  }) async {
    try {
      await _ds.verifyAccountUpgrade(
        accountUpgradeDocId: accountUpgradeDocId,
        action: action,
        rejectionNotes: rejectionNotes,
      );
      await fetch(page: state.currentPage);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verify({
      required String accountUpgradeDocId,
      required String action,
      String? rejectionNotes}) =>
      verifyDoc(
          accountUpgradeDocId: accountUpgradeDocId,
          action: action,
          rejectionNotes: rejectionNotes);

  Future<bool> verifyAll({
    required String lenderId,
    required String action,
    String? rejectionNotes,
  }) async {
    try {
      await _ds.verifyAllAccountUpgrade(
        lenderId: lenderId,
        action: action,
        rejectionNotes: rejectionNotes,
      );
      await fetch(page: state.currentPage);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getStatus(String lenderId) async {
    try {
      return await _ds.getStatus(lenderId: lenderId);
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getDetails(
      {String? accountUpgradeDocId, String? lenderId}) async {
    try {
      return await _ds.getDetails(
          accountUpgradeDocId: accountUpgradeDocId, lenderId: lenderId);
    } catch (e) {
      return null;
    }
  }
}

// New primary provider mirroring HM naming
final empAccountUpgradeProvider = AutoDisposeStateNotifierProvider<
    EmpAccountUpgradeNotifier, EmpAccountUpgradeState>((ref) {
  return EmpAccountUpgradeNotifier(sl<AccountUpgradeRemoteDataSource>());
});

// Keep legacy name as alias for any existing imports that expect AsyncValue
// (not used after migration but prevents break if external code still imports it)
final empAccountUpgradeLegacyProvider = empAccountUpgradeProvider;

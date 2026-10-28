import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/lenders/providers/hm_lender_provider.dart';

import '../../../helpers/audit_test_helpers.dart';

class _FakeLenderDs extends UserRemoteDataSource {
  _FakeLenderDs(this.rows)
      : super(FakeDioClient((_) async => throw UnimplementedError()));

  List<UserModel> rows;
  final List<String> archivedIds = [];
  int listCalls = 0;

  @override
  Future<PagedUsers> getUsersPaged({
    String? role,
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
    String? dateFrom,
    String? dateTo,
  }) async {
    listCalls++;
    return PagedUsers(
      items: List.of(rows),
      total: rows.length,
      totalPages: 1,
      page: page,
    );
  }

  @override
  Future<void> archive(String userId) async {
    archivedIds.add(userId);
    rows = rows.where((r) => r.id != userId).toList();
  }
}

UserModel _lender(String id) => UserModel(
      id: id,
      role: 'lender',
      firstName: 'Test',
      lastName: id,
      accountStatus: 'active',
      forcePasswordChange: false,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HmLenderNotifier.archive', () {
    test('removes the row locally without reloading the whole list', () async {
      await loadTestEnv();
      final ds = _FakeLenderDs([_lender('l1'), _lender('l2')]);
      final notifier = HmLenderNotifier(ds);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.state.lenders.map((l) => l.id), ['l1', 'l2']);
      final listCallsAfterInitialLoad = ds.listCalls;

      await notifier.archive('l1');

      expect(ds.archivedIds, ['l1']);
      expect(notifier.state.lenders.map((l) => l.id), ['l2']);
      // Walang bagong getUsersPaged — hindi nag-reload ng buong paged data.
      expect(ds.listCalls, listCallsAfterInitialLoad);

      notifier.dispose();
    });
  });
}

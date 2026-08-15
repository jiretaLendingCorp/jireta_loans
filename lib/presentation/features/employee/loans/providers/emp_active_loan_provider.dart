// lib/presentation/features/employee/loans/providers/emp_active_loan_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/loan_remote_datasource.dart';
import '../../../../features/head_manager/loans/providers/hm_loan_provider.dart';

/// Active-loans list for the employee portal. Reuses the generic
/// [HmLoanNotifier] (role-agnostic: it only talks to LoanRemoteDataSource)
/// seeded on the 'active' tab, which surfaces both `active` and just-approved
/// (`approved`) loans so the employee sees the same book as the head manager.
final empActiveLoanProvider =
    AutoDisposeStateNotifierProvider<HmLoanNotifier, HmLoanState>((ref) {
  return HmLoanNotifier(sl<LoanRemoteDataSource>(), initialFilter: 'active');
});
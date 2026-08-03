// lib/core/di/injection.dart
import 'package:get_it/get_it.dart';

import '../../data/datasources/remote/audit_remote_datasource.dart';
import '../../data/datasources/remote/auth_remote_datasource.dart';
import '../../data/datasources/remote/blacklist_remote_datasource.dart';
import '../../data/datasources/remote/ci_remote_datasource.dart';
import '../../data/datasources/remote/collection_remote_datasource.dart';
import '../../data/datasources/remote/disbursement_remote_datasource.dart';
import '../../data/datasources/remote/in_office_remote_datasource.dart';
import '../../data/datasources/remote/kpi_remote_datasource.dart';
import '../../data/datasources/remote/kyc_remote_datasource.dart';
import '../../data/datasources/remote/loan_remote_datasource.dart';
import '../../data/datasources/remote/location_remote_datasource.dart';
import '../../data/datasources/remote/notification_remote_datasource.dart';
import '../../data/datasources/remote/payment_remote_datasource.dart';
import '../../data/datasources/remote/report_remote_datasource.dart';
import '../../data/datasources/remote/system_remote_datasource.dart'; // FIX: was missing — sl<SystemRemoteDataSource>() would throw StateError at runtime
import '../../data/datasources/remote/user_remote_datasource.dart';
import '../network/dio_client.dart';

final GetIt sl = GetIt.instance;

Future<void> setupDependencies() async {
  sl.registerLazySingleton<DioClient>(() => DioClient());

  sl.registerLazySingleton<AuthRemoteDataSource>(
    () => AuthRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<UserRemoteDataSource>(
    () => UserRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<KpiRemoteDataSource>(
    () => KpiRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<LoanRemoteDataSource>(
    () => LoanRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<NotificationRemoteDataSource>(
    () => NotificationRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<KycRemoteDataSource>(
    () => KycRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<CiRemoteDataSource>(
    () => CiRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<CollectionRemoteDataSource>(
    () => CollectionRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<PaymentRemoteDataSource>(
    () => PaymentRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<BlacklistRemoteDataSource>(
    () => BlacklistRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<DisbursementRemoteDataSource>(
    () => DisbursementRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<AuditRemoteDataSource>(
    () => AuditRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<ReportRemoteDataSource>(
    () => ReportRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<LocationRemoteDataSource>(
    () => LocationRemoteDataSource(sl()),
  );
  sl.registerLazySingleton<InOfficeRemoteDataSource>(
    () => InOfficeRemoteDataSource(sl()),
  );
  // FIX: SystemRemoteDataSource existed but was never registered — added here.
  sl.registerLazySingleton<SystemRemoteDataSource>(
    () => SystemRemoteDataSource(sl()),
  );
}

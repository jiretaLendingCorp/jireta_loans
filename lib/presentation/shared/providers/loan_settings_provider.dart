// lib/presentation/shared/providers/loan_settings_provider.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/realtime_service.dart';
import '../../../core/utils/logger.dart';
import '../../../data/models/loan_settings.dart';
import '../../../domain/repositories/i_system_repository.dart';

/// Min/max loan amount + interest rate mula sa System Settings ng Head Manager.
///
/// `autoDispose` ito para **sariwa ang value tuwing bubuksan ang Apply Loan /
/// In-Office wizard** — kapag nag-save ng bagong limit ang Head Manager,
/// makikita agad ito sa susunod na pagbukas ng form (hindi na kailangang
/// i-restart ang app).
///
/// Bukod doon, naka-subscribe ito sa realtime changes ng `system_config`, kaya
/// habang bukas ang form, awtomatikong nagre-refresh ang limits kapag may
/// nag-save ng config (staff/head-manager sessions na may read access).
final loanSettingsProvider =
    FutureProvider.autoDispose<LoanSettings>((ref) async {
  var disposed = false;
  ref.onDispose(() => disposed = true);

  void onConfigChanged() {
    if (disposed) return;
    ref.invalidateSelf();
  }

  // Best-effort realtime: hindi dapat mabara ang initial load kung walang
  // socket/session (tests, offline).
  unawaited(
    RealtimeService.instance
        .subscribe('system_config', onConfigChanged)
        .catchError((Object e) {
      AppLogger.debug('[LoanSettings] Realtime subscribe failed: $e');
    }),
  );
  ref.onDispose(() {
    try {
      RealtimeService.instance.unsubscribe('system_config', onConfigChanged);
    } catch (_) {
      // Ignore — provider is already disposing.
    }
  });

  final repo = sl<ISystemRepository>();
  try {
    return LoanSettings.fromJson(await repo.getLoanSettings());
  } catch (e) {
    AppLogger.debug('[LoanSettings] Falling back to defaults: $e');
    return LoanSettings.defaults;
  }
});

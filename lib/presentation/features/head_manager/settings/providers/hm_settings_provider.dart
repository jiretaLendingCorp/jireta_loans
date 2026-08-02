// lib/presentation/features/head_manager/settings/providers/hm_settings_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../domain/repositories/i_system_repository.dart';

final systemConfigProvider = FutureProvider<List<dynamic>>((ref) async {
  final repo = sl<ISystemRepository>();
  return repo.getSystemConfig();
});

final smsTemplatesProvider = FutureProvider<List<dynamic>>((ref) async {
  final repo = sl<ISystemRepository>();
  return repo.getSmsTemplates();
});

class HmSettingsNotifier extends StateNotifier<AsyncValue<void>> {
  final ISystemRepository _repo;

  HmSettingsNotifier(this._repo) : super(const AsyncValue.data(null));

  Future<bool> updateConfig(String configKey, String configValue) async {
    state = const AsyncValue.loading();
    try {
      await _repo.updateSystemConfig(configKey, configValue);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<bool> updateSmsTemplate(String templateId, String content) async {
    state = const AsyncValue.loading();
    try {
      await _repo.updateSmsTemplate(templateId, content);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final hmSettingsProvider =
    StateNotifierProvider<HmSettingsNotifier, AsyncValue<void>>(
  (ref) => HmSettingsNotifier(sl<ISystemRepository>()),
);

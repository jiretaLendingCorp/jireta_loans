// lib/presentation/shared/providers/app_settings_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// Local app settings na hindi kailangan ng server:
//   - Theme mode (System / Light / Dark) — naka-persist sa SharedPreferences
//     at direktang naka-wire sa MaterialApp (app.dart).
//   - FCM push notifications ON/OFF — kapag OFF, ide-delete ang device token
//     (idina-deactivate sa backend) kaya hindi na makaka-receive ng push ang
//     device na ito. Ang in-app notification center ay hindi apektado (ito
//     pa rin ang source of truth).
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/utils/logger.dart';

class AppSettingsState {
  final ThemeMode themeMode;
  final bool pushNotificationsEnabled;

  const AppSettingsState({
    this.themeMode = ThemeMode.system,
    this.pushNotificationsEnabled = true,
  });

  bool get isDark => themeMode == ThemeMode.dark;

  AppSettingsState copyWith({
    ThemeMode? themeMode,
    bool? pushNotificationsEnabled,
  }) =>
      AppSettingsState(
        themeMode: themeMode ?? this.themeMode,
        pushNotificationsEnabled:
            pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      );
}

class AppSettingsNotifier extends StateNotifier<AppSettingsState> {
  AppSettingsNotifier() : super(const AppSettingsState()) {
    _load();
  }

  static ThemeMode themeModeFromString(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode =
          themeModeFromString(prefs.getString(AppConstants.prefThemeMode));
      final push =
          prefs.getBool(AppConstants.prefPushNotifications) ?? true;
      state = AppSettingsState(
        themeMode: mode,
        pushNotificationsEnabled: push,
      );

      // Ipatupad ang saved push preference sa FCM (device token on/off).
      if (push) {
        await FcmService.instance.enable();
      } else {
        await FcmService.instance.disable();
      }
    } catch (e) {
      AppLogger.debug('[Settings] Load failed: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          AppConstants.prefThemeMode, themeModeToString(mode));
    } catch (e) {
      AppLogger.debug('[Settings] Save theme failed: $e');
    }
  }

  /// Convenience para sa switch sa Profile.
  Future<void> setDarkMode(bool dark) =>
      setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);

  Future<void> setPushNotifications(bool enabled) async {
    state = state.copyWith(pushNotificationsEnabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.prefPushNotifications, enabled);
    } catch (e) {
      AppLogger.debug('[Settings] Save push pref failed: $e');
    }
    if (enabled) {
      await FcmService.instance.enable();
    } else {
      await FcmService.instance.disable();
    }
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettingsState>(
        (ref) => AppSettingsNotifier());

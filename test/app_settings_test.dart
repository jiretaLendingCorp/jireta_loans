// test/app_settings_test.dart
// Regression test para sa Profile settings: theme mode (light/dark/system) at
// FCM push on/off — naka-persist sa SharedPreferences.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jireta_loans/core/constants/app_constants.dart';
import 'package:jireta_loans/presentation/shared/providers/app_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults: system theme + push notifications ON', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = AppSettingsNotifier();

    // _load() ay async — hintayin ang microtask/prefs read.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifier.state.themeMode, ThemeMode.system);
    expect(notifier.state.isDark, isFalse);
    expect(notifier.state.pushNotificationsEnabled, isTrue);
    notifier.dispose();
  });

  test('loads saved values from prefs', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefThemeMode: 'dark',
      AppConstants.prefPushNotifications: false,
    });
    final notifier = AppSettingsNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifier.state.themeMode, ThemeMode.dark);
    expect(notifier.state.isDark, isTrue);
    expect(notifier.state.pushNotificationsEnabled, isFalse);
    notifier.dispose();
  });

  test('setDarkMode persists and updates state', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = AppSettingsNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await notifier.setDarkMode(true);
    expect(notifier.state.themeMode, ThemeMode.dark);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppConstants.prefThemeMode), 'dark');

    await notifier.setDarkMode(false);
    expect(notifier.state.themeMode, ThemeMode.light);
    expect(prefs.getString(AppConstants.prefThemeMode), 'light');
    notifier.dispose();
  });

  test('setPushNotifications persists the FCM toggle', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = AppSettingsNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await notifier.setPushNotifications(false);
    expect(notifier.state.pushNotificationsEnabled, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppConstants.prefPushNotifications), isFalse);

    await notifier.setPushNotifications(true);
    expect(prefs.getBool(AppConstants.prefPushNotifications), isTrue);
    notifier.dispose();
  });

  test('theme mode string mapping round-trips', () {
    for (final mode in ThemeMode.values) {
      final raw = AppSettingsNotifier.themeModeToString(mode);
      expect(AppSettingsNotifier.themeModeFromString(raw), mode);
    }
    // Unknown / null -> system (safe default).
    expect(AppSettingsNotifier.themeModeFromString(null), ThemeMode.system);
    expect(AppSettingsNotifier.themeModeFromString('nonsense'),
        ThemeMode.system);
  });
}

// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/router/app_router.dart';
import 'core/security/session_idle_detector.dart';
import 'core/services/fcm_service.dart';
import 'core/theme/app_theme.dart';
import 'presentation/shared/widgets/account_paused_overlay.dart';
import 'presentation/shared/widgets/connectivity_overlay.dart';
import 'presentation/shared/widgets/logout_overlay.dart';

class JiretaApp extends ConsumerWidget {
  const JiretaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // FCM taps navigate through the app's router (role-aware redirects).
    FcmService.instance.attachRouter(router);
    return MaterialApp.router(
      title: 'Jireta Loans & Credit Corp 1966',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
      // Global overlays: Connectivity (offline) + Logout passthrough +
      // Account Paused (escalation block, lender only).
      // Logout no longer shows a full-screen modal — the pressed logout
      // button itself shows the loading spinner.
      // Ang AccountPausedOverlay ay nasa labas ng ConnectivityOverlay para
      // ito ang pinakatuktok at hindi ma-tap ang app sa likod niya.
      builder: (context, child) => SessionIdleDetector(
        child: LogoutOverlay(
          child: AccountPausedOverlay(
            child: ConnectivityOverlay(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'PH')],
    );
  }
}

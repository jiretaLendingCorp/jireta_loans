// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/router/app_router.dart';
import 'core/security/session_idle_detector.dart';
import 'core/theme/app_theme.dart';
import 'presentation/shared/widgets/connectivity_overlay.dart';
import 'presentation/shared/widgets/logout_overlay.dart';

class JiretaApp extends ConsumerWidget {
  const JiretaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Jireta Loans & Credit Corp 1966',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
      // Global overlays: Connectivity (offline) + Logout passthrough.
      // Logout no longer shows a full-screen modal — the pressed logout
      // button itself shows the loading spinner. Both wrappers are
      // role-agnostic and sit above every route.
      builder: (context, child) => SessionIdleDetector(
        child: LogoutOverlay(
          child: ConnectivityOverlay(child: child ?? const SizedBox.shrink()),
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

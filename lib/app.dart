// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'presentation/shared/widgets/connectivity_overlay.dart';

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
      // Global connectivity overlay: renders above every screen so any logged
      // in role (lender, rider, employee, head manager) sees a centered
      // loading spinner then "No Internet Connection" when offline.
      builder: (context, child) =>
          ConnectivityOverlay(child: child ?? const SizedBox.shrink()),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'PH')],
    );
  }
}

// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/constants/role_constants.dart';
import 'core/router/app_router.dart';
import 'core/security/session_idle_detector.dart';
import 'core/services/fcm_service.dart';
import 'core/theme/app_theme.dart';
import 'presentation/features/lender/account_upgrade/providers/lender_account_upgrade_provider.dart';
import 'presentation/features/lender/collections/providers/lender_collection_provider.dart';
import 'presentation/features/lender/dashboard/providers/lender_dashboard_provider.dart';
import 'presentation/features/lender/dashboard/providers/lender_rider_tracking_provider.dart';
import 'presentation/features/lender/documents/providers/lender_documents_provider.dart';
import 'presentation/features/lender/loans/providers/lender_loan_provider.dart';
import 'presentation/features/lender/notifications/providers/lender_notification_provider.dart';
import 'presentation/features/lender/payments/providers/lender_payment_provider.dart';
import 'presentation/features/lender/profile/providers/lender_profile_provider.dart';
import 'presentation/shared/providers/app_settings_provider.dart';
import 'presentation/shared/providers/auth_state_provider.dart';
import 'presentation/shared/widgets/account_paused_overlay.dart';
import 'presentation/shared/widgets/connectivity_overlay.dart';
import 'presentation/shared/widgets/logout_overlay.dart';

/// Wipes every account-scoped LENDER provider so a brand-new account can never
/// inherit the previous lender's cached data (Recent Activity, balances,
/// payments, collections, ...). AutoDispose providers can outlive the route
/// swap that happens on logout/login, which is exactly how another lender's
/// activity leaked into a fresh account's dashboard.
void _resetLenderSessionProviders(WidgetRef ref) {
  ref.invalidate(lenderProfileProvider);
  ref.invalidate(lenderDashboardProvider);
  ref.invalidate(lenderLoanProvider);
  ref.invalidate(lenderPaymentProvider);
  ref.invalidate(lenderCollectionProvider);
  ref.invalidate(lenderAccountUpgradeProvider);
  ref.invalidate(lenderNotificationProvider);
  ref.invalidate(lenderDocumentsProvider);
  ref.invalidate(lenderRiderTrackingProvider);
}

class JiretaApp extends ConsumerWidget {
  const JiretaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // Light / Dark mode — naka-persist na setting mula sa Profile.
    final settings = ref.watch(appSettingsProvider);
    // RIDER lang ang may dark mode: kahit naka-on ang setting, mananatiling
    // light ang lender / employee / head manager (per role).
    final role = ref.watch(authStateProvider.select((s) => s.role));
    final isRider = role == RoleConstants.rider;
    // Kapag nagpalit ng account (logout → bagong login), i-reset ang lahat ng
    // account-scoped lender providers. Kung hindi, nananatili ang Recent
    // Activity / datos ng naunang lender account sa bagong account.
    ref.listen<String?>(
      authStateProvider.select((s) => s.user?.id),
      (prev, next) {
        if (prev == next) return;
        // Microtask para hindi mag-modify ng provider habang nagbu-build
        // ang widget tree (nagpapatakbo ng invalidation pagkatapos ng frame).
        Future.microtask(() => _resetLenderSessionProviders(ref));
      },
    );
    // FCM taps navigate through the app's router (role-aware redirects).
    FcmService.instance.attachRouter(router);
    return MaterialApp.router(
      title: 'Jireta Loans & Credit Corp 1966',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: isRider ? settings.themeMode : ThemeMode.light,
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

// lib/presentation/features/auth/screens/splash_screen.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/asset_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_state_provider.dart';
import '../../../shared/providers/connectivity_provider.dart';
import '../../../shared/widgets/offline_toast.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  /// True while this splash is blocked on the splash screen waiting for
  /// internet access to return.
  bool _waitingForConnection = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _scaleAnim = Tween<double>(
      begin: 0.7,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _controller.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;

    // Stay on the splash screen until the app actually has internet access.
    // Without this, a freshly-opened offline app would still navigate to the
    // login/dashboard behind the "No Internet Connection" toast. While waiting,
    // the build method's ref.listen re-triggers _navigate when connectivity
    // comes back.
    if (!(ref.read(connectivityProvider).valueOrNull ?? false)) {
      _waitingForConnection = true;
      return;
    }
    _waitingForConnection = false;
    if (!mounted) return;

    // Make sure secure-storage session check finishes before deciding where to
    // go. Otherwise a logged-in mobile user briefly lands on the login screen
    // (and on the wrong platform's login at that) before the redirect fires.
    var authState = ref.read(authStateProvider);
    if (authState.isLoading) {
      for (var i = 0; i < 50 && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        authState = ref.read(authStateProvider);
        if (!authState.isLoading) break;
      }
    }
    if (!mounted) return;

    const loginRoute =
        kIsWeb ? RouteConstants.webLogin : RouteConstants.mobileLogin;
    final prefs = await SharedPreferences.getInstance();
    final termsAccepted = prefs.getBool(AppConstants.termsAcceptedKey) ?? false;
    authState = ref.read(authStateProvider);
    if (!mounted) return;
    if (authState.isAuthenticated && !authState.forcePasswordChange) {
      final role = authState.role;
      switch (role) {
        case AppConstants.roleHeadManager:
          context.go(RouteConstants.hmDashboard);
          break;
        case AppConstants.roleEmployee:
          context.go(RouteConstants.empDashboard);
          break;
        case AppConstants.roleRider:
          context.go(RouteConstants.riderDashboard);
          break;
        case AppConstants.roleLender:
          context.go(RouteConstants.lenderDashboard);
          break;
        default:
          context.go(loginRoute);
      }
    } else if (authState.isAuthenticated && authState.forcePasswordChange) {
      final role = authState.role;
      if (role != AppConstants.roleRider && role != AppConstants.roleLender) {
        context.go(RouteConstants.forceChangePassword);
      } else {
        switch (role) {
          case AppConstants.roleHeadManager:
            context.go(RouteConstants.hmDashboard);
            break;
          case AppConstants.roleEmployee:
            context.go(RouteConstants.empDashboard);
            break;
          case AppConstants.roleRider:
            context.go(RouteConstants.riderDashboard);
            break;
          case AppConstants.roleLender:
            context.go(RouteConstants.lenderDashboard);
            break;
          default:
            context.go(loginRoute);
        }
      }
    } else if (!termsAccepted && !kIsWeb) {
      context.go(RouteConstants.terms);
    } else {
      context.go(loginRoute);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(
      connectivityProvider.select((v) => v.valueOrNull ?? true),
    );

    // When the app was opened offline, re-attempt navigation once real
    // internet access is confirmed again.
    ref.listen(connectivityProvider, (prev, next) {
      if (_waitingForConnection &&
          (next.valueOrNull ?? false) &&
          !(prev?.valueOrNull ?? false)) {
        _waitingForConnection = false;
        _navigate();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.deepNavy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.gold, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(AssetConstants.logoJpg,
                              fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'JIRETA',
                        style: TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold,
                          letterSpacing: 6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'LOANS & CREDIT CORP',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white54,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '1966',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: AppColors.goldLight,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 48),
                      SizedBox(
                        width: 160,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            color: AppColors.gold,
                            backgroundColor:
                                AppColors.gold.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!isOnline)
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(left: 24, right: 24, bottom: 32),
                child: OfflineToast(),
              ),
            ),
        ],
      ),
    );
  }
}

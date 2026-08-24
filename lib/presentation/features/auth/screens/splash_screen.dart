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
  late Animation<Offset> _slideAnim;
  late Animation<double> _glowAnim;

  /// True while this splash is blocked on the splash screen waiting for
  /// internet access to return.
  bool _waitingForConnection = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );
    _scaleAnim = Tween<double>(begin: 0.88, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    // Subtle pulsing glow behind logo
    _glowAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;

    // Stay on the splash screen until the app actually has internet access.
    // Web: always wait. Mobile: only wait if unauthenticated — authenticated
    // users have a cached session and can reach their dashboard offline
    // (global offline overlay will show). While waiting, the build method's
    // ref.listen re-triggers _navigate when connectivity comes back.
    final isOnline = ref.read(connectivityProvider).valueOrNull ?? false;
    final authSnap = ref.read(authStateProvider);
    final shouldWaitForConnection =
        kIsWeb ? !isOnline : (!isOnline && !authSnap.isAuthenticated);
    if (shouldWaitForConnection) {
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D1B2A), // deepNavy
              Color(0xFF132A42),
              Color(0xFF0A1420),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // ── Premium decorative layers ──────────────────────────────
            // Subtle gold radial glow top-right
            Positioned(
              top: -80,
              right: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.gold.withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Bottom-left navy-gold glow
            Positioned(
              bottom: -100,
              left: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.gold.withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Hairline top accent (gold)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      AppColors.gold.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Fine grid pattern (very subtle)
            Positioned.fill(
              child: Opacity(
                opacity: 0.025,
                child: CustomPaint(painter: _GridPainter()),
              ),
            ),

            // ── Center brand block ─────────────────────────────────────
            SafeArea(
              child: Center(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (_, __) {
                    return FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: ScaleTransition(
                          scale: _scaleAnim,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Logo with premium double-ring + glow
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Outer glow pulse
                                      FadeTransition(
                                        opacity: _glowAnim,
                                        child: Container(
                                          width: 126,
                                          height: 126,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.gold
                                                    .withValues(alpha: 0.18),
                                                blurRadius: 32,
                                                spreadRadius: 4,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Thin gold outer ring
                                      Container(
                                        width: 114,
                                        height: 114,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppColors.gold
                                                .withValues(alpha: 0.9),
                                            width: 1.2,
                                          ),
                                        ),
                                      ),
                                      // White inner circle with logo
                                      Container(
                                        width: 100,
                                        height: 100,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppColors.gold
                                                .withValues(alpha: 0.25),
                                            width: 1,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 24,
                                              offset: const Offset(0, 10),
                                            ),
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.15),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        padding: const EdgeInsets.all(3),
                                        child: ClipOval(
                                          child: Image.asset(
                                            AssetConstants.logoJpg,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 28),
                                  // Brand name - JIRETA
                                  const Text(
                                    'JIRETA',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'PlayfairDisplay',
                                      fontSize: 39,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.gold,
                                      letterSpacing: 7.5,
                                      height: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Elegant thin gold divider (premium minimal)
                                  Container(
                                    width: 38,
                                    height: 1.2,
                                    decoration: BoxDecoration(
                                      color:
                                          AppColors.gold.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'LOANS & CREDIT CORP.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: 3.2,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Trusted • Secured • Professional',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          Colors.white.withValues(alpha: 0.48),
                                      letterSpacing: 1.6,
                                    ),
                                  ),
                                  const SizedBox(height: 42),
                                  // Premium progress capsule
                                  Column(
                                    children: [
                                      SizedBox(
                                        width: 148,
                                        height: 3,
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(99),
                                          child: Stack(
                                            children: [
                                              Container(
                                                color: Colors.white
                                                    .withValues(alpha: 0.08),
                                              ),
                                              // Animated shimmer bar (indeterminate simulation via gradient)
                                              LayoutBuilder(
                                                builder: (ctx, c) {
                                                  return Container(
                                                    decoration: BoxDecoration(
                                                      gradient:
                                                          LinearGradient(
                                                        colors: [
                                                          AppColors.gold
                                                              .withValues(
                                                                  alpha: 0.0),
                                                          AppColors.gold,
                                                          AppColors.goldLight,
                                                          AppColors.gold,
                                                          AppColors.gold
                                                              .withValues(
                                                                  alpha: 0.0),
                                                        ],
                                                        stops: const [
                                                          0.0,
                                                          0.25,
                                                          0.5,
                                                          0.75,
                                                          1.0
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                              const LinearProgressIndicator(
                                                minHeight: 3,
                                                color: Colors.transparent,
                                                backgroundColor:
                                                    Colors.transparent,
                                              ),
                                              // Actual moving indicator on top with gold color
                                              Positioned.fill(
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(99),
                                                  child:
                                                      const LinearProgressIndicator(
                                                    minHeight: 3,
                                                    color: AppColors.gold,
                                                    backgroundColor:
                                                        Colors.transparent,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.6,
                                              color: AppColors.gold
                                                  .withValues(alpha: 0.9),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _waitingForConnection
                                                ? 'Waiting for connection…'
                                                : 'Preparing your experience…',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.white
                                                  .withValues(alpha: 0.62),
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── Bottom footer — premium minimal ────────────────────────
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isOnline)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 14),
                          child: OfflineToast(),
                        ),
                      // Divider
                      Container(
                        height: 1,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.08),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '© 1966–2026 JIRETA Loans & Credit Corp. All rights reserved.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.32),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v1.0.0  •  Secure & Encrypted',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.28),
                          letterSpacing: 0.9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC9A84C)
      ..strokeWidth = 0.4
      ..style = PaintingStyle.stroke;
    const gap = 28.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

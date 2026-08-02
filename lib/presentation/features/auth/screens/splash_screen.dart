// lib/presentation/features/auth/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/route_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_state_provider.dart';

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
    final prefs = await SharedPreferences.getInstance();
    final termsAccepted = prefs.getBool(AppConstants.termsAcceptedKey) ?? false;
    final authState = ref.read(authStateProvider);
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
          context.go(RouteConstants.webLogin);
      }
    } else if (authState.isAuthenticated && authState.forcePasswordChange) {
      context.go(RouteConstants.forceChangePassword);
    } else if (!termsAccepted) {
      context.go(RouteConstants.terms);
    } else {
      context.go(RouteConstants.webLogin);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepNavy,
      body: Center(
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
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.gold, width: 2),
                    ),
                    child: const Icon(
                      Icons.account_balance,
                      size: 56,
                      color: AppColors.gold,
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
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.gold.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

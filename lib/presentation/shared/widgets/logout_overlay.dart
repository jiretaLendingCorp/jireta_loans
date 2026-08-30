// lib/presentation/shared/widgets/logout_overlay.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/auth_state_provider.dart';
import '../../features/auth/providers/auth_provider.dart';

/// Global full-screen loading overlay shown while the user is logging out.
///
/// Watches [authStateProvider.isLoggingOut] and [authProvider] `isLoading`
/// (when the async value was triggered by logout). While visible it blocks
/// ALL interaction (AbsorbPointer + dim) so the user cannot double-tap logout
/// or navigate elsewhere until the session is fully cleared and the router
/// redirects to the login screen. Works for every role: head_manager,
/// employee (web) and lender/rider (mobile) because it lives at [JiretaApp]
/// level above [ConnectivityOverlay] / the router child.
class LogoutOverlay extends ConsumerWidget {
  final Widget child;

  const LogoutOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggingOut =
        ref.watch(authStateProvider.select((s) => s.isLoggingOut));
    // Also consider AuthNotifier logout loading — if authProvider is loading
    // due to logout (and authState hasn't flipped yet) keep overlay visible.
    // We check both so whichever provider the caller used, the UI covers it.
    final authAsync = ref.watch(authProvider);
    final isAuthLogoutLoading = authAsync.isLoading && isLoggingOut;

    final show = isLoggingOut || isAuthLogoutLoading;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (show) ...[
          // Dim + block interaction
          const Positioned.fill(
            child: ColoredBox(color: Color(0x66000000)),
          ),
          // Absorb all pointers so nothing behind is tappable
          const Positioned.fill(child: AbsorbPointer(child: SizedBox.expand())),
          Positioned.fill(
            child: Center(
              // ignore: prefer_const_constructors
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.deepNavy),
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Logging out...',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.deepNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

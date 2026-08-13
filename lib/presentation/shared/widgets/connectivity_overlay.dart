// lib/presentation/shared/widgets/connectivity_overlay.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/router/app_router.dart';
import '../providers/auth_state_provider.dart';
import '../providers/connectivity_provider.dart';
import 'offline_toast.dart';

/// Global offline banner shown whenever an authenticated user (ANY role) loses
/// internet connection.
///
/// Reuses the login page's offline-banner look (light red container + border +
/// spinner + "No Internet Connection" text) but as a persistent centered toast
/// rendered above every route. While offline the ENTIRE app is blocked
/// (AbsorbPointer + dim) so nothing is tappable, and all connection-level
/// error dialogs/snackbars are suppressed in favor of this single toast. It
/// CANNOT be dismissed — it stays visible in the CENTER of the app until
/// connectivity is restored, so lenders, riders, employees and head managers
/// all see identical behavior regardless of which screen they're on.
class ConnectivityOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const ConnectivityOverlay({super.key, required this.child});

  @override
  ConsumerState<ConnectivityOverlay> createState() =>
      _ConnectivityOverlayState();
}

class _ConnectivityOverlayState extends ConsumerState<ConnectivityOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 0,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    // ref.listen does not fire for the initial provider value, so check the
    // state once after the first frame (app may already be offline).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateAnimation();
    });
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  void _updateAnimation() {
    final isOnline = ref.read(
      connectivityProvider.select((v) => v.valueOrNull ?? true),
    );
    final isAuthenticated = ref.read(authStateProvider).isAuthenticated;
    final show = isAuthenticated && !isOnline;

    if (show && _slideCtrl.isDismissed) {
      _slideCtrl.forward();
    } else if (!show && !_slideCtrl.isDismissed) {
      _slideCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(
      connectivityProvider.select((v) => v.valueOrNull ?? true),
    );
    final isAuthenticated = ref.watch(
      authStateProvider.select((s) => s.isAuthenticated),
    );

    ref.listen(
      connectivityProvider.select((v) => v.valueOrNull ?? true),
      (prev, next) => _updateAnimation(),
    );
    ref.listen(
      authStateProvider.select((s) => s.isAuthenticated),
      (prev, next) => _updateAnimation(),
    );

    // The splash screen shows its own bottom-aligned offline toast, so don't
    // duplicate it with the overlay's centered toast while on the splash.
    final currentPath = ref.watch(currentRoutePathProvider).valueOrNull ??
        RouteConstants.splash;
    final onSplash = currentPath == RouteConstants.splash;

    final showToast = isAuthenticated && !isOnline && !onSplash;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Block ALL interaction with the app while offline — the toast is the
        // only thing the user can see/do until connectivity is restored.
        AbsorbPointer(
          absorbing: showToast,
          child: widget.child,
        ),
        if (showToast) ...[
          // Dim the app behind the toast so it reads as a locked state.
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
            ),
          ),
          Positioned.fill(
            child: SlideTransition(
              position: _slide,
              child: const Align(
                alignment: Alignment.center,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: OfflineToast(),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

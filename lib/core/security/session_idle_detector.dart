// lib/core/security/session_idle_detector.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../presentation/shared/providers/auth_state_provider.dart';
import 'secure_storage.dart';

/// Wraps the whole app and resets the idle timer on ANY user
/// interaction (tap, drag, key press, scroll). Ang haba ng idle window ay
/// nakabatay sa role: 15 minuto para sa head manager / employee (auto logout),
/// 3 minuto para sa rider / lender (MPIN lock). Programmatic/animated scrolls
/// (auto-play carousels) ay HINDI activity — tingnan ang
/// [isUserDrivenScroll].
///
/// Sa pag-resume mula sa background, muling sinusuri ang idle deadline: doon
/// hindi garantisadong tumakbo ang Dart timer (o natigil ang app), kaya kung
/// lumampas na ang idle window ay magla-lock/logout ito agad sa pagbalik.
///
/// Totoong scroll ng user lang ang activity. Ang auto-play carousel
/// (`PageController.animateToPage`) at iba pang programmatic scroll ay
/// naglalabas din ng [ScrollNotification] pero WALANG drag — kung bubump ang
/// mga iyon, hindi umaabot sa idle timeout ang session (ito ang dahilan ng
/// "hindi nag-a-auto logout" sa lender dashboard, kung saan may 4-second
/// auto-play na promo carousel).
@visibleForTesting
bool isUserDrivenScroll(ScrollNotification n) {
  if (n is ScrollStartNotification) return n.dragDetails != null;
  if (n is ScrollUpdateNotification) return n.dragDetails != null;
  if (n is OverscrollNotification) return n.dragDetails != null;
  if (n is ScrollEndNotification) return n.dragDetails != null;
  return false;
}

/// Throttled to once per 10 seconds so a fling-scroll storm does not flood
/// SecureStorage writes; the throttle error (≤10s) is negligible for the idle
/// window and keeps storage / event-loop pressure low.
class SessionIdleDetector extends ConsumerStatefulWidget {
  final Widget child;
  const SessionIdleDetector({super.key, required this.child});

  @override
  ConsumerState<SessionIdleDetector> createState() =>
      _SessionIdleDetectorState();
}

class _SessionIdleDetectorState extends ConsumerState<SessionIdleDetector>
    with WidgetsBindingObserver {
  DateTime? _lastBump;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Walang dumaan na gesture habang naka-background ang app, kaya dito
    // na kapag bumalik ito: expired na ba ang idle window?
    if (state == AppLifecycleState.resumed) {
      try {
        unawaited(ref.read(authStateProvider.notifier).checkIdleNow());
      } catch (_) {}
    }
  }

  void _onActivity([_]) {
    final now = DateTime.now().toUtc();
    if (_lastBump != null && now.difference(_lastBump!).inSeconds < 10) return;
    _lastBump = now;
    // Fire-and-forget: never block the gesture thread on storage I/O.
    unawaited(SecureStorage.saveLastActivity(now));
    // Notify the notifier so it can reschedule the expiry timer immediately.
    // Throttled inside the notifier as well for safety.
    try {
      ref.read(authStateProvider.notifier).notifyActivity();
    } catch (_) {}
  }

  void _schedDebounce() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _onActivity);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listener catches low-level pointer events (tap, drag, scroll).
    // FocusScope catches key presses on web/desktop. NotificationListener
    // catches ScrollNotification (ListView, PageView) which Listener misses.
    return Listener(
      onPointerDown: _onActivity,
      onPointerMove: (_) => _schedDebounce(),
      onPointerHover: (_) => _schedDebounce(),
      onPointerSignal: (_) => _schedDebounce(),
      onPointerPanZoomStart: (_) => _onActivity(),
      onPointerPanZoomUpdate: (_) => _schedDebounce(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (!isUserDrivenScroll(n)) return false;
          _schedDebounce();
          return false;
        },
        child: FocusScope(
          onKeyEvent: (_, __) {
            _onActivity();
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _onActivity,
            onPanDown: (_) => _onActivity(),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

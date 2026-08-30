// lib/core/security/session_idle_detector.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../presentation/shared/providers/auth_state_provider.dart';
import 'secure_storage.dart';

/// Wraps the whole app and resets the 10-minute idle timer on ANY user
/// interaction (tap, drag, key press, scroll).  Also bumps on authenticated
/// API calls via [AuthInterceptor].
///
/// Throttled to once per 10 seconds so a fling-scroll storm does not flood
/// SecureStorage writes; the throttle error (≤10s) is negligible for a 10-min
/// window and keeps storage / event-loop pressure low.
class SessionIdleDetector extends ConsumerStatefulWidget {
  final Widget child;
  const SessionIdleDetector({super.key, required this.child});

  @override
  ConsumerState<SessionIdleDetector> createState() => _SessionIdleDetectorState();
}

class _SessionIdleDetectorState extends ConsumerState<SessionIdleDetector> {
  DateTime? _lastBump;
  Timer? _debounce;

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

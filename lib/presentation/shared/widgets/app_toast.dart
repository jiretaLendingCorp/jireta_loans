// lib/presentation/shared/widgets/app_toast.dart
//
// Proper toast system. Every toast is rendered by an OverlayEntry pinned to
// the top-right corner of the screen and sized to its own text content (never
// stretched to full width). Types:
//   - success  (green, check icon)
//   - error    (red, alert icon)
//   - info     (navy, info icon)
//
// Toasts auto-dismiss after [AppToast.duration] and stack downward when more
// than one is shown at once. [AppToast.showWidget] renders a custom, icon-less
// widget (used for the live lockout countdown, which stays until it expires).
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

enum AppToastType { success, error, info }

class AppToast {
  AppToast._();

  /// How long each toast stays on screen before dismissing.
  static const Duration duration = Duration(seconds: 3);

  static final List<AppToastEntry> _active = [];
  static OverlayEntry? _entry;
  static _ToastHostState? _host;

  static void show(
    BuildContext context,
    String message, {
    AppToastType type = AppToastType.info,
    Duration? displayDuration,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = AppToastEntry(
      message: message,
      type: type,
      remaining: displayDuration ?? duration,
    );
    _active.add(entry);

    _ensureHost(overlay);

    Timer(entry.remaining!, () => _remove(entry));
  }

  /// Renders a custom [content] widget in the same top-right toast host, with
  /// no auto-dismiss (pass [displayDuration] to override) and no icon. Used by
  /// the lockout countdown, which refreshes itself every second and calls
  /// [dismissAll] when it expires.
  static void showWidget(
    BuildContext context,
    Widget content, {
    Duration? displayDuration,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = AppToastEntry(
      message: '',
      type: AppToastType.info,
      remaining: displayDuration,
      content: content,
    );
    _active.add(entry);

    _ensureHost(overlay);

    if (displayDuration != null) {
      Timer(displayDuration, () => _remove(entry));
    }
  }

  /// Removes every active toast. Used when a new lockout starts so stale
  /// countdowns never stack.
  static void dismissAll() {
    _active.clear();
    if (_entry != null) {
      _entry!.remove();
      _entry = null;
      _host = null;
    }
  }

  static void _ensureHost(OverlayState overlay) {
    if (_entry == null) {
      _entry = OverlayEntry(
        builder: (_) => _ToastHost(
          active: _active,
          onState: (state) => _host = state,
        ),
      );
      overlay.insert(_entry!);
    } else {
      _host?._refresh();
    }
  }

  static void _remove(AppToastEntry entry) {
    _active.remove(entry);
    if (_active.isEmpty && _entry != null) {
      _entry!.remove();
      _entry = null;
      _host = null;
    } else {
      _host?._refresh();
    }
  }
}

class AppToastEntry {
  final String message;
  final AppToastType type;
  final Duration? remaining;
  final Widget? content;
  const AppToastEntry({
    required this.message,
    required this.type,
    this.remaining,
    this.content,
  });
}

/// The single always-on overlay widget hosting the active toasts at the
/// top-right of the screen.
class _ToastHost extends StatefulWidget {
  final List<AppToastEntry> active;
  final ValueChanged<_ToastHostState> onState;
  const _ToastHost({required this.active, required this.onState});

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost> {
  @override
  void initState() {
    super.initState();
    widget.onState(this);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final toasts = widget.active;
    if (toasts.isEmpty) return const SizedBox.shrink();

    final topPadding = MediaQuery.of(context).padding.top;
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth > 600 ? _ToastMaxWidth.value : screenWidth - 32;

    return Positioned(
      top: topPadding + 12,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(toasts.length, (i) {
          final toast = toasts[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AnimatedToast(
              message: toast.message,
              type: toast.type,
              index: i,
              maxWidth: maxWidth,
              content: toast.content,
            ),
          );
        }),
      ),
    );
  }
}

/// Named static so the const base stays simple.
class _ToastMaxWidth {
  static const double value = 380;
}

class _AnimatedToast extends StatelessWidget {
  final String message;
  final AppToastType type;
  final int index;
  final double maxWidth;
  final Widget? content;

  const _AnimatedToast({
    required this.message,
    required this.type,
    required this.index,
    required this.maxWidth,
    this.content,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      AppToastType.success => AppColors.success,
      AppToastType.error => AppColors.error,
      AppToastType.info => AppColors.deepNavy,
    };
    final icon = switch (type) {
      AppToastType.success => Icons.check_circle,
      AppToastType.error => Icons.error_outline,
      AppToastType.info => Icons.info_outline,
    };

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(24 * (1 - t), 0),
            child: child,
          ),
        );
      },
      child: content ?? Material(
        color: color,
        elevation: 6,
        shadowColor: color.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        child: IntrinsicWidth(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 19),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
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

/// Live lockout countdown shown as a top-right toast (no icon). Self-refreshes
/// every second and dismisses itself when the remaining time hits zero.
class LockoutCountdownToast extends StatefulWidget {
  final int seconds;
  final VoidCallback? onExpired;
  const LockoutCountdownToast({
    super.key,
    required this.seconds,
    this.onExpired,
  });

  @override
  State<LockoutCountdownToast> createState() => _LockoutCountdownToastState();
}

class _LockoutCountdownToastState extends State<LockoutCountdownToast> {
  late int _secondsLeft = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
        widget.onExpired?.call();
        AppToast.dismissAll();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _label {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.error,
      elevation: 6,
      shadowColor: AppColors.error.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Text(
          'Too many wrong attempts. Try again in $_label',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
// lib/presentation/shared/widgets/logout_overlay.dart
import 'package:flutter/material.dart';

/// Passthrough wrapper kept for backwards-compatibility.
///
/// Per request, the full-screen "Logging out..." modal was removed — the
/// logout button itself shows the loading spinner instead, so this widget
/// no longer blocks interaction or renders any overlay. It simply returns
/// [child] untouched. Callers ([JiretaApp]) can keep using it without changes.
class LogoutOverlay extends StatelessWidget {
  final Widget child;

  const LogoutOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

// lib/presentation/shared/widgets/animated/stagger_animation.dart
import 'package:flutter/material.dart';

class StaggerAnimation extends StatelessWidget {
  final List<Widget> children;
  final Duration itemDelay;
  final Duration itemDuration;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;

  const StaggerAnimation({
    super.key,
    required this.children,
    this.itemDelay = const Duration(milliseconds: 60),
    this.itemDuration = const Duration(milliseconds: 350),
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: children.asMap().entries.map((entry) {
        return _StaggerItem(
          delay: itemDelay * entry.key,
          duration: itemDuration,
          child: entry.value,
        );
      }).toList(),
    );
  }
}

class _StaggerItem extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  const _StaggerItem({
    required this.child,
    required this.delay,
    required this.duration,
  });

  @override
  State<_StaggerItem> createState() => _StaggerItemState();
}

class _StaggerItemState extends State<_StaggerItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

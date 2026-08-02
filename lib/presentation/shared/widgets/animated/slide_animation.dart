// lib/presentation/shared/widgets/animated/slide_animation.dart
import 'package:flutter/material.dart';

enum SlideDirection { fromLeft, fromRight, fromTop, fromBottom }

class SlideAnimation extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final SlideDirection direction;
  final double offset;

  const SlideAnimation({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 400),
    this.direction = SlideDirection.fromBottom,
    this.offset = 32,
  });

  @override
  State<SlideAnimation> createState() => _SlideAnimationState();
}

class _SlideAnimationState extends State<SlideAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);

    Offset begin;
    switch (widget.direction) {
      case SlideDirection.fromLeft:
        begin = Offset(-widget.offset / 100, 0);
        break;
      case SlideDirection.fromRight:
        begin = Offset(widget.offset / 100, 0);
        break;
      case SlideDirection.fromTop:
        begin = Offset(0, -widget.offset / 100);
        break;
      case SlideDirection.fromBottom:
        begin = Offset(0, widget.offset / 100);
        break;
    }

    _slide = Tween<Offset>(begin: begin, end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);

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
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

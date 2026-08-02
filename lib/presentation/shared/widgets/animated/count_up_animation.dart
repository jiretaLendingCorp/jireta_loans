// lib/presentation/shared/widgets/animated/count_up_animation.dart
import 'package:flutter/material.dart';

class CountUpAnimation extends StatefulWidget {
  final double value;
  final double begin;
  final Duration duration;
  final String prefix;
  final String suffix;
  final int decimalPlaces;
  final TextStyle? style;
  final bool compact;

  const CountUpAnimation({
    super.key,
    required this.value,
    this.begin = 0,
    this.duration = const Duration(milliseconds: 1500),
    this.prefix = '',
    this.suffix = '',
    this.decimalPlaces = 0,
    this.style,
    this.compact = false,
  });

  @override
  State<CountUpAnimation> createState() => _CountUpAnimationState();
}

class _CountUpAnimationState extends State<CountUpAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(begin: widget.begin, end: widget.value).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(CountUpAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.value,
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _format(double value) {
    if (widget.decimalPlaces == 0) return value.toInt().toString();
    return value.toStringAsFixed(widget.decimalPlaces);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.compact
        ? (widget.style ?? const TextStyle(fontSize: 14))
            .copyWith(fontSize: widget.style?.fontSize != null
                ? (widget.style!.fontSize! * 0.7).clamp(9, 14)
                : 11)
        : widget.style;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => Text(
        '${widget.prefix}${_format(_animation.value)}${widget.suffix}',
        style: style,
      ),
    );
  }
}

class CountUpText extends StatefulWidget {
  final double endValue;
  final String prefix;
  final String suffix;
  final Duration duration;
  final int decimalPlaces;
  final TextStyle? style;

  const CountUpText({
    super.key,
    required this.endValue,
    this.prefix = '',
    this.suffix = '',
    this.duration = const Duration(milliseconds: 1500),
    this.decimalPlaces = 0,
    this.style,
  });

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(begin: 0, end: widget.endValue).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(CountUpText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endValue != widget.endValue) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.endValue,
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _format(double value) {
    if (widget.decimalPlaces == 0) return value.toInt().toString();
    return value.toStringAsFixed(widget.decimalPlaces);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => Text(
        '${widget.prefix}${_format(_animation.value)}${widget.suffix}',
        style: widget.style,
      ),
    );
  }
}

class FadeAnimation extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  const FadeAnimation({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 400),
  });

  @override
  State<FadeAnimation> createState() => _FadeAnimationState();
}

class _FadeAnimationState extends State<FadeAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
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
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: widget.child,
      );
}

class SlideAnimation extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Offset beginOffset;

  const SlideAnimation({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.beginOffset = const Offset(0, 0.1),
  });

  @override
  State<SlideAnimation> createState() => _SlideAnimationState();
}

class _SlideAnimationState extends State<SlideAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slide = Tween<Offset>(
      begin: widget.beginOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
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
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

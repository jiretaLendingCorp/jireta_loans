// lib/presentation/shared/widgets/layout/mobile_refresh.dart
//
// Pull-to-refresh helpers para sa lender at rider screens.
//
// BAKIT KAILANGAN: ang `RefreshIndicator` ay dapat MANATILI sa widget tree
// habang tumatakbo ang refresh. Sa dating pattern:
//
//   body: state.isLoading ? const ShimmerLoader() : RefreshIndicator(...)
//
// ...napapalitan ng skeleton ang RefreshIndicator sa sandaling mag-
// `isLoading = true` ang provider — at nangyayari iyon AGAD kapag nag-pull
// down (dahil non-silent ang `refresh()` ng provider). Bunga: nawawala ang
// spinner sa gitna ng gesture at lumalabas ang skeleton sa halip na refresh.
//
// TAMANG GAMIT:
//   1. Sa `onRefresh`, gamitin ang SILENT load (`load(silent: true)`) para
//      hindi mag-flash ang skeleton habang nagre-refresh — ang drop-down na
//      spinner na ang feedback.
//   2. Kapag HINDI scrollable ang nilalaman (empty state, error, skeleton),
//      kailangan itong palooban ng scroll view para may magawang pull-down:
//        * [RefreshableFill] — kapag nasa LOOB na ng isang RefreshIndicator;
//        * [MobileRefresh] na may `fill: true` — kapag ito ang buong body.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// `SingleChildScrollView` na laging umaabot sa buong available na taas.
///
/// Ginagamit ito para maging pull-able ang NON-scrollable na nilalaman
/// (empty state / error / skeleton) — kapag mas maikli ang content sa screen,
/// wala sanang overscroll kaya hindi gagana ang pull-down.
class RefreshableFill extends StatelessWidget {
  const RefreshableFill({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.hasBoundedHeight
            ? constraints.maxHeight - padding.vertical
            : 0.0;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewport < 0 ? 0 : viewport),
            child: child,
          ),
        );
      },
    );
  }
}

/// `RefreshIndicator` na hindi nawawala kahit mag-refresh.
///
/// Itago ito sa `body` ng screen bilang ISANG widget lang — ang `child` ang
/// magbabago base sa data, hindi ang indicator mismo.
class MobileRefresh extends StatelessWidget {
  const MobileRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color,
    this.fill = false,
    this.padding = EdgeInsets.zero,
    this.feedback = true,
  });

  /// Ginagawa habang nakabitin ang indicator — hintayin ang aktwal na load
  /// para tama ang timing ng pagbagsak ng spinner.
  final Future<void> Function() onRefresh;

  final Widget child;

  /// Kulay ng spinner — karaniwang role accent (rider green / lender blue).
  final Color? color;

  /// `true` kapag HINDI scrollable ang [child] (empty / error / skeleton).
  final bool fill;

  /// Padding ng panlabas na scroll view kapag `fill: true`.
  final EdgeInsetsGeometry padding;

  /// Tunog + haptic sa tuwing mag-trigger ang pull-to-refresh. Naka-ON by
  /// default para may pakiramdam na "kumagat" ang pull.
  ///
  /// NOTE: system click sound ito ([SystemSoundType.click]) kaya Android lang
  /// ang tumutunog (at nakadepende pa rin sa "touch sounds" setting ng phone);
  /// hindi ito tumutunog sa iOS. Kapag kailangan ng tunog sa BOTH platforms,
  /// kailangan ng audio asset (`.mp3`) sa `pubspec.yaml` assets at isang audio
  /// package (hal. `audioplayers`) — wala pa sa app ang dalawang iyon.
  final bool feedback;

  /// Ang aktwal na itinatawag ng RefreshIndicator — may feedback muna bago ang
  /// load para agad ang tunog/haptic pag-trigger ng pull.
  Future<void> _trigger() async {
    if (feedback) {
      unawaited(SystemSound.play(SystemSoundType.click));
      unawaited(HapticFeedback.mediumImpact());
    }
    await onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: color ?? AppColors.deepNavy,
      backgroundColor: Theme.of(context).colorScheme.surface,
      onRefresh: _trigger,
      child: fill
          ? RefreshableFill(padding: padding, child: child)
          : child,
    );
  }
}

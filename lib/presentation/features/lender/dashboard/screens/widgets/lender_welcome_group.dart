// lib/presentation/features/lender/dashboard/screens/widgets/lender_welcome_group.dart
//
// Ang Rive (fox) at ang greeting dialog ("Good morning/afternoon/evening, ...")
// bilang ISANG grupo. Hiwalay ito sa dashboard screen para:
//
//   * isang lugar lang ang nagtatakda ng AYOS ng dalawa — hindi na kailangang
//     hanapin sa malaking screen file kung saan naka-position ang dialog;
//   * nate-test ang ayos nang hindi umaasa sa Rive asset (`rive` ay ipinapasa ng
//     caller, kaya pwedeng placeholder sa widget test — ang tunay na Rive ay
//     hindi naglo-load sa test host).
//
// [riveFirst]: kapag true, ang FOX ang pinaka-kaliwa at ang dialog ang nasa
// KANAN nito (desktop). Kapag false, nasa KALIWA ng fox ang dialog (mobile).
import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_colors.dart';
import '../../../../../../core/utils/timezone.dart';

class LenderWelcomeGroup extends StatelessWidget {
  final String? firstName;

  /// Ang Rive widget ng fox (hal. 118x118 na `SizedBox` na may Rive sa loob).
  final Widget rive;

  /// true = fox sa kaliwa, dialog sa kanan; false = dialog sa kaliwa, fox sa
  /// kanan (default, ang mobile na ayos).
  final bool riveFirst;

  const LenderWelcomeGroup({
    super.key,
    required this.rive,
    this.firstName,
    this.riveFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    // Nakabaling sa fox ang buntot ng dialog — kaliwa o kanan depende sa ayos.
    final bubble = _GoodMorningBubble(
      name: firstName,
      tailOnLeft: riveFirst,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: riveFirst
          ? [rive, const SizedBox(width: 6), bubble]
          : [bubble, const SizedBox(width: 6), rive],
    );
  }
}

/// Ang greeting dialog na may 700ms na slide/fade-in at maliit na buntot.
class _GoodMorningBubble extends StatefulWidget {
  final String? name;

  /// Kapag true, nasa KALIWANG ilalim ng bubble ang buntot (patungo sa fox na
  /// nasa kaliwa nito); kapag false, nasa kanang ibaba — gaya ng dati.
  final bool tailOnLeft;

  const _GoodMorningBubble({this.name, this.tailOnLeft = false});

  @override
  State<_GoodMorningBubble> createState() => _GoodMorningBubbleState();
}

class _GoodMorningBubbleState extends State<_GoodMorningBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = nowManila().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final name = widget.name?.trim() ?? '';
    final message = name.isEmpty ? '$greeting!' : '$greeting, $name!';

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.6, 0.4),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack)),
      child: FadeTransition(
        opacity: _ctrl,
        child: Container(
          margin: const EdgeInsets.only(top: 26),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(
                message,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Positioned(
                left: widget.tailOnLeft ? -8 : null,
                right: widget.tailOnLeft ? null : -8,
                bottom: -10,
                child: ClipPath(
                  clipper: _BubbleTailClipper(mirror: widget.tailOnLeft),
                  child: Container(
                    width: 16,
                    height: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BubbleTailClipper extends CustomClipper<Path> {
  /// Nakabaling sa KANAN (default) o sa KALIWA ang buntot.
  final bool mirror;

  const _BubbleTailClipper({this.mirror = false});

  @override
  Path getClip(Size size) {
    final path = Path();
    if (mirror) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(0, size.height);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _BubbleTailClipper oldClipper) =>
      oldClipper.mirror != mirror;
}

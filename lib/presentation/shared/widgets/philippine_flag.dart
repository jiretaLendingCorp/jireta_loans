// lib/presentation/shared/widgets/philippine_flag.dart
//
// Watawat ng Pilipinas na iginuhit gamit ang `CustomPainter`.
//
// Bakit hindi `Text('🇵🇭')`? Ang flag emoji ay kulay lamang sa mga platform na
// may color-emoji font. Sa Windows/Chrome (at sa ilang Linux setup) walang
// glyph para sa regional-indicator pair, kaya lumalabas itong dalawang
// blangkong kahon. Ang iginuhit na watawat na ito ay pantay na lumalabas sa
// lahat ng platform at hindi umaasa sa font.
import 'package:flutter/material.dart';

class PhilippineFlag extends StatelessWidget {
  /// Lapad ng watawat; 2:1 ang proportion (height = width / 2).
  final double width;

  const PhilippineFlag({super.key, this.width = 20});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Philippines',
      child: SizedBox(
        width: width,
        height: width / 2,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: const CustomPaint(painter: _PhilippineFlagPainter()),
        ),
      ),
    );
  }
}

class _PhilippineFlagPainter extends CustomPainter {
  const _PhilippineFlagPainter();

  static const _blue = Color(0xFF0038A8);
  static const _red = Color(0xFFCE1126);
  static const _gold = Color(0xFFFCD116);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()..isAntiAlias = true;

    // Blue sa itaas, red sa ibaba.
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 2), paint..color = _blue);
    canvas.drawRect(Rect.fromLTWH(0, h / 2, w, h / 2), paint..color = _red);

    // Puting tatsulok sa hoist (kalahati ng haba).
    final triangle = Path()
      ..moveTo(0, 0)
      ..lineTo(h, h / 2)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(triangle, paint..color = Colors.white);

    // Araw sa gitna ng tatsulok at tatlong bituin sa sulok.
    canvas.drawCircle(Offset(h / 3, h / 2), h * 0.16, paint..color = _gold);
    for (final star in [
      Offset(h * 0.17, h * 0.18),
      Offset(h * 0.17, h * 0.82),
      Offset(h * 0.55, h * 0.5),
    ]) {
      canvas.drawCircle(star, h * 0.045, paint..color = _gold);
    }
  }

  @override
  bool shouldRepaint(covariant _PhilippineFlagPainter oldDelegate) => false;
}

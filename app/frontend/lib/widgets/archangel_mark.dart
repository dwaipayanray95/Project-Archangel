import 'package:flutter/material.dart';

/// Archangel's brand glyph — a shield outline with a checkmark inside,
/// from the "Archangel App Icon" Claude Design canvas. Traced directly
/// from that design's SVG path data (0..24 viewBox):
/// shield `M12 3 4 7v5.5c0 5 3.4 7.9 8 8.5 4.6-.6 8-3.5 8-8.5V7z`,
/// check `m9 12 2.2 2.2L15.5 10` — kept here as one small `CustomPainter`
/// rather than an image asset so it stays crisp at any size and recolors
/// with the app's theme.
class ArchangelMark extends StatelessWidget {
  final double size;
  final Color color;

  /// Wraps the glyph in the design's dark rounded-square tile (its own
  /// gradient background + bottom accent glow) instead of just the bare
  /// stroke — for standalone use (e.g. an about/splash screen). The top
  /// bar supplies its own solid-accent tile, so it passes `tile: false`.
  final bool tile;

  const ArchangelMark({super.key, this.size = 20, this.color = const Color(0xFF7EE787), this.tile = false});

  @override
  Widget build(BuildContext context) {
    final glyph = CustomPaint(size: Size.square(size), painter: _ArchangelMarkPainter(color));
    if (!tile) return glyph;

    final tileSize = size * 24 / 15; // glyph occupies ~15/24 of the tile in the source design
    return Container(
      width: tileSize,
      height: tileSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tileSize * 56 / 256),
        gradient: const RadialGradient(
          center: Alignment(-0.52, -0.76),
          radius: 1.2,
          colors: [Color(0xFF1D231C), Color(0xFF0E100E), Color(0xFF080908)],
          stops: [0.0, 0.58, 1.0],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tileSize * 56 / 256),
                gradient: RadialGradient(
                  center: const Alignment(0, 1.16),
                  radius: 0.6,
                  colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          glyph,
        ],
      ),
    );
  }
}

class _ArchangelMarkPainter extends CustomPainter {
  final Color color;
  const _ArchangelMarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    Offset p(double x, double y) => Offset(x * scale, y * scale);

    final shield = Path()
      ..moveTo(p(12, 3).dx, p(12, 3).dy)
      ..lineTo(p(4, 7).dx, p(4, 7).dy)
      ..lineTo(p(4, 12.5).dx, p(4, 12.5).dy)
      ..cubicTo(p(4, 17.5).dx, p(4, 17.5).dy, p(7.4, 20.4).dx, p(7.4, 20.4).dy, p(12, 21).dx, p(12, 21).dy)
      ..cubicTo(p(16.6, 20.4).dx, p(16.6, 20.4).dy, p(20, 17.5).dx, p(20, 17.5).dy, p(20, 12.5).dx, p(20, 12.5).dy)
      ..lineTo(p(20, 7).dx, p(20, 7).dy)
      ..close();

    final check = Path()
      ..moveTo(p(9, 12).dx, p(9, 12).dy)
      ..lineTo(p(11.2, 14.2).dx, p(11.2, 14.2).dy)
      ..lineTo(p(15.5, 10).dx, p(15.5, 10).dy);

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    canvas.drawPath(shield, fillPaint);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(shield, strokePaint);
    canvas.drawPath(check, strokePaint..strokeWidth = scale * 1.9);
  }

  @override
  bool shouldRepaint(covariant _ArchangelMarkPainter oldDelegate) => oldDelegate.color != color;
}

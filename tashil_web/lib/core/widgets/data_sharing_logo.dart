import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';

/// DataSharingLogo renders the official Tashil Data Sharing brand mark:
/// A Material Design 3 Medium Contrast Blue (#1B6EF3) squircle with a bold,
/// optically centered, pure white capital letter 'D'.
class DataSharingLogo extends StatelessWidget {
  final double size;
  final bool showSquircle;
  final bool showGlow;
  final bool? showShadow;
  final Color? primaryColor;
  final bool showText;
  final String? subtitle;

  const DataSharingLogo({
    super.key,
    this.size = 40.0,
    this.showSquircle = true,
    this.showGlow = true,
    this.showShadow,
    this.primaryColor,
    this.showText = false,
    this.subtitle,
  });

  /// Official Google Material Design 3 Standard Contrast Blue (#1565C0)
  static const Color m3StandardBlue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bgColor = primaryColor ?? m3StandardBlue;
    final effectiveGlow = showShadow ?? showGlow;

    final logoMark = Container(
      width: size,
      height: size,
      decoration: showSquircle
          ? BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(size * 0.24),
              boxShadow: effectiveGlow
                  ? [
                      BoxShadow(
                        color: bgColor.withValues(alpha: 0.28),
                        blurRadius: size * 0.25,
                        offset: Offset(0, size * 0.08),
                      ),
                    ]
                  : null,
            )
          : null,
      child: Center(
        child: SizedBox(
          width: size,
          height: size,
          child: const CustomPaint(
            painter: _DLogoPainter(color: Colors.white),
          ),
        ),
      ),
    );

    if (!showText) {
      return logoMark;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        logoMark,
        SizedBox(width: size * 0.25),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tashil Data Sharing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.15,
                ),
              ),
              Text(
                subtitle ?? 'Enterprise Retail Analytics',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: M3FontSize.labelSmall,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Mathematically centered, high-precision vector painter for capital letter 'D'.
/// Guarantees identical horizontal (25% left, 25% right) and vertical (20% top, 20% bottom)
/// margins across all devices, platforms, and screen densities without font-metrics variance.
class _DLogoPainter extends CustomPainter {
  final Color color;
  const _DLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100.0;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    final path = Path()..fillType = PathFillType.evenOdd;

    // Outer D: left edge at x=25, right edge at x=75 (width=50, centered in 100)
    // top edge at y=20, bottom edge at y=80 (height=60, centered in 100)
    path.moveTo(25.0 * scale, 20.0 * scale);
    path.lineTo(50.0 * scale, 20.0 * scale);
    path.cubicTo(
      65.5 * scale, 20.0 * scale,
      75.0 * scale, 32.0 * scale,
      75.0 * scale, 50.0 * scale,
    );
    path.cubicTo(
      75.0 * scale, 68.0 * scale,
      65.5 * scale, 80.0 * scale,
      50.0 * scale, 80.0 * scale,
    );
    path.lineTo(25.0 * scale, 80.0 * scale);
    path.close();

    // Inner counter (hole of the D):
    path.moveTo(38.0 * scale, 32.5 * scale);
    path.lineTo(48.0 * scale, 32.5 * scale);
    path.cubicTo(
      56.5 * scale, 32.5 * scale,
      62.0 * scale, 39.5 * scale,
      62.0 * scale, 50.0 * scale,
    );
    path.cubicTo(
      62.0 * scale, 60.5 * scale,
      56.5 * scale, 67.5 * scale,
      48.0 * scale, 67.5 * scale,
    );
    path.lineTo(38.0 * scale, 67.5 * scale);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DLogoPainter oldDelegate) => oldDelegate.color != color;
}


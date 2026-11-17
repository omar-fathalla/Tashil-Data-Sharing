import 'package:flutter/material.dart';

import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/theme/m3_typography.dart';
import 'login_mockup_copy.dart';

/// Abstract analytics panel drawn with shapes and icons. No external images.
class DataSharingMotif extends StatelessWidget {
  const DataSharingMotif({
    super.key,
    required this.ink,
    this.compact = false,
  });

  final Color ink;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ar = LoginMockupCopy.isArabic(context);
    if (compact) {
      return _CompactMotif(ink: ink, ar: ar);
    }
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.10),
        borderRadius: M3Shape.radiusXl,
        border: Border.all(color: ink.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? M3Spacing.sm : M3Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MetricTile(
                  ink: ink,
                  icon: Icons.analytics_rounded,
                  label: ar ? 'البيع' : 'Sell-out',
                ),
                const SizedBox(width: M3Spacing.s12),
                _MetricTile(
                  ink: ink,
                  icon: Icons.upload_file_rounded,
                  label: ar ? 'إكسل' : 'Excel',
                ),
                const SizedBox(width: M3Spacing.s12),
                _MetricTile(
                  ink: ink,
                  icon: Icons.sell_rounded,
                  label: ar ? 'السعر' : 'Price',
                ),
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: M3Spacing.md),
              SizedBox(
                height: 148,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.08),
                    borderRadius: M3Shape.radiusLg,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      M3Spacing.sm,
                      M3Spacing.md,
                      M3Spacing.sm,
                      M3Spacing.s12,
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: _BarRow(ink: ink),
                        ),
                        const SizedBox(height: M3Spacing.xs),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            LoginMockupCopy.motifCaption(ar),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: ink.withValues(alpha: 0.82),
                              fontSize: M3FontSize.bodySmall,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactMotif extends StatelessWidget {
  const _CompactMotif({required this.ink, required this.ar});

  final Color ink;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String)>[
      (Icons.analytics_rounded, ar ? 'البيع' : 'Sell-out'),
      (Icons.upload_file_rounded, ar ? 'إكسل' : 'Excel'),
      (Icons.sell_rounded, ar ? 'السعر' : 'Price'),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: M3Spacing.xs),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.12),
                borderRadius: M3Shape.radiusFull,
                border: Border.all(color: ink.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: M3Spacing.xs,
                  vertical: M3Spacing.xs,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(items[i].$1, color: ink, size: 16),
                    const SizedBox(width: M3Spacing.xxs),
                    Flexible(
                      child: Text(
                        items[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: ink,
                              fontWeight: FontWeight.w600,
                              fontSize: M3FontSize.bodySmall,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.ink,
    required this.icon,
    required this.label,
  });

  final Color ink;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ink.withValues(alpha: 0.12),
          borderRadius: M3Shape.radiusMd,
        ),
        child: Padding(
          padding: const EdgeInsets.all(M3Spacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: ink, size: 20),
              const SizedBox(height: M3Spacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w600,
                  fontSize: M3FontSize.bodySmall,
                ),
              ),
              const SizedBox(height: M3Spacing.xs),
              Container(
                height: M3Spacing.xxs,
                width: M3Spacing.xxl,
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.85),
                  borderRadius: M3Shape.radiusFull,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.ink});

  final Color ink;

  static const _heights = <double>[0.42, 0.68, 0.5, 0.88, 0.6, 0.78, 0.46];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < _heights.length; i++) ...[
          if (i > 0) const SizedBox(width: M3Spacing.xs),
          Expanded(
            child: FractionallySizedBox(
              heightFactor: _heights[i],
              alignment: Alignment.bottomCenter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: i == 3 ? 1 : 0.72),
                  borderRadius: M3Shape.radiusSm,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Soft dot grid for the centered-card background.
class LoginTonalPattern extends StatelessWidget {
  const LoginTonalPattern({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DotGridPainter(color),
      child: const SizedBox.expand(),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const gap = 28.0;
    for (var y = gap / 2; y < size.height; y += gap) {
      for (var x = gap / 2; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 1.15, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

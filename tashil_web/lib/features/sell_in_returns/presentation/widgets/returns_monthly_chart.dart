import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_shape.dart';
import 'package:tashil_web/core/theme/m3_spacing.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';

import '../../domain/sell_in_returns_models.dart';

/// Grouped monthly bars: gross / returns / net for the المرتجعات page.
class ReturnsMonthlyChart extends StatelessWidget {
  final List<SellInReturnsMonthPoint> points;

  const ReturnsMonthlyChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (points.isEmpty) {
      return Card.outlined(
        child: Padding(
          padding: M3Spacing.pMd,
          child: Text(
            'لا توجد بيانات شهرية للمرتجعات',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    final maxAbs = points.fold<double>(0, (m, p) {
      return math.max(
        m,
        math.max(p.grossValueEgp.abs(), math.max(p.returnsValueEgp.abs(), p.netValueEgp.abs())),
      );
    });
    final scale = maxAbs <= 0 ? 1.0 : maxAbs;

    return Card.outlined(
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الإجمالي · المرتجع · الصافي شهرياً',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Gross · Returns · Net by month',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _legend(cs.primary, 'إجمالي (Gross)'),
                _legend(cs.error, 'مرتجع (Returns)'),
                _legend(cs.tertiary, 'صافي (Net)'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final p in points)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _bar(cs.primary, p.grossValueEgp / scale),
                                  _bar(cs.error, p.returnsValueEgp / scale),
                                  _bar(cs.tertiary, p.netValueEgp.abs() / scale,
                                      muted: p.netValueEgp < 0),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              p.monthAr.isNotEmpty ? p.monthAr : '${p.monthNum}',
                              style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              CurrencyFormatter.formatCompactEGP(p.returnsValueEgp),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontSize: 10,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, borderRadius: M3Shape.radiusSm),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }

  Widget _bar(Color color, double frac, {bool muted = false}) {
    final h = (frac.clamp(0.0, 1.0) * 160).toDouble();
    return Expanded(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: math.max(2, h),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: muted ? color.withOpacity(0.45) : color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'package:tashil_web/core/theme/m3_typography.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import 'chain_share_pie.dart';

/// SelloutTrendChart renders an interactive monthly time-series curve
/// showing sell-out revenue trajectory and growth for each active retailer chain
/// in its own distinct brand color across all 12 months with a vertical financial axis.
class SelloutTrendChart extends StatefulWidget {
  final List<DailyTrendItem> trends;

  const SelloutTrendChart({
    super.key,
    required this.trends,
  });

  @override
  State<SelloutTrendChart> createState() => _SelloutTrendChartState();
}

class _ChainSeriesData {
  final String chainCode;
  final String displayName;
  final Color color;
  final List<double> values;
  final List<double> growthPcts;
  final double totalRevenue;

  const _ChainSeriesData({
    required this.chainCode,
    required this.displayName,
    required this.color,
    required this.values,
    required this.growthPcts,
    required this.totalRevenue,
  });
}

class _SelloutTrendChartState extends State<SelloutTrendChart> {
  int? hoveredIndex;

  static const _arabicMonthNames = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  static const _englishMonthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _formatYAxisLabel(double amount) {
    if (amount <= 0) return '0 ج.م';
    if (amount >= 1000000) {
      final inM = amount / 1000000.0;
      if (inM >= 10 || inM == inM.roundToDouble()) {
        return '${inM.toStringAsFixed(inM == inM.roundToDouble() ? 0 : 1)}M ج.م';
      }
      return '${inM.toStringAsFixed(1)}M ج.م';
    } else if (amount >= 1000) {
      final inK = amount / 1000.0;
      return '${inK.toStringAsFixed(0)}K ج.م';
    }
    return '${amount.round()} ج.م';
  }

  String _formatAxisLabel(DailyTrendItem item) {
    if (item.monthKey.trim().isNotEmpty) {
      final parts = item.monthKey.trim().split('-');
      if (parts.length >= 2) {
        final m = int.tryParse(parts[1]);
        if (m != null && m >= 1 && m <= 12) {
          return _arabicMonthNames[m - 1];
        }
      }
    }
    if (item.monthLabel.trim().isNotEmpty) {
      final parts = item.monthLabel.trim().split(' ');
      if (parts.isNotEmpty) return parts[0];
    }
    return item.date.trim();
  }

  String? _formatAxisLabelEn(DailyTrendItem item) {
    if (item.monthKey.trim().isNotEmpty) {
      final parts = item.monthKey.trim().split('-');
      if (parts.length >= 2) {
        final m = int.tryParse(parts[1]);
        if (m != null && m >= 1 && m <= 12) {
          return _englishMonthNames[m - 1];
        }
      }
    }
    final arLabel = _formatAxisLabel(item);
    final idx = _arabicMonthNames.indexOf(arLabel);
    if (idx != -1) return _englishMonthNames[idx];
    return null;
  }

  List<DailyTrendItem> _getEffectiveTrends() {
    if (widget.trends.isEmpty) return const [];

    // Filter out trends that have zero revenue, zero units, and zero chain revenues
    final validTrends = widget.trends.where((t) {
      if (t.revenue > 0 || t.units > 0) return true;
      return t.chainRevenues.values.any((v) => v > 0);
    }).toList();

    if (validTrends.isEmpty) {
      return widget.trends;
    }

    // Sort chronologically by monthKey or date
    validTrends.sort((a, b) {
      final keyA = a.monthKey.isNotEmpty ? a.monthKey : a.date;
      final keyB = b.monthKey.isNotEmpty ? b.monthKey : b.date;
      return keyA.compareTo(keyB);
    });

    return validTrends;
  }

  List<_ChainSeriesData> _extractSeries(List<DailyTrendItem> effectiveTrends, ColorScheme colorScheme) {
    final chainTotals = <String, double>{};
    for (final t in effectiveTrends) {
      t.chainRevenues.forEach((chain, rev) {
        if (rev > 0) {
          chainTotals[chain] = (chainTotals[chain] ?? 0.0) + rev;
        }
      });
      for (final d in t.chainDetails) {
        if (d.revenue > 0 && !chainTotals.containsKey(d.retailerChain)) {
          chainTotals[d.retailerChain] = (chainTotals[d.retailerChain] ?? 0.0) + d.revenue;
        }
      }
    }

    if (chainTotals.isEmpty) {
      final totalRev = effectiveTrends.fold<double>(0.0, (s, e) => s + e.revenue);
      return [
        _ChainSeriesData(
          chainCode: 'total',
          displayName: 'إجمالي المبيعات (Total Sell-Out)',
          color: colorScheme.primary,
          values: effectiveTrends.map((e) => e.revenue).toList(),
          growthPcts: List<double>.filled(effectiveTrends.length, 0.0),
          totalRevenue: totalRev,
        ),
      ];
    }

    const preferredOrder = ['fathalla', 'gomla', 'beet-elgomla', 'carrefour', 'spinneys', 'metro', 'seoudi', 'kazyon'];
    final activeChains = chainTotals.keys.where((k) => (chainTotals[k] ?? 0) > 0).toList()
      ..sort((a, b) {
        final idxA = preferredOrder.indexOf(a.toLowerCase());
        final idxB = preferredOrder.indexOf(b.toLowerCase());
        if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
        if (idxA != -1) return -1;
        if (idxB != -1) return 1;
        return (chainTotals[b] ?? 0).compareTo(chainTotals[a] ?? 0);
      });

    return activeChains.map((code) {
      final values = <double>[];
      final growths = <double>[];
      String? backendDisplayName;
      for (int i = 0; i < effectiveTrends.length; i++) {
        final t = effectiveTrends[i];
        double val = t.chainRevenues[code] ?? 0.0;
        double growth = 0.0;
        for (final d in t.chainDetails) {
          if (d.retailerChain.toLowerCase() == code.toLowerCase()) {
            if (val <= 0) val = d.revenue;
            growth = d.growthPct;
            if (d.displayName.trim().isNotEmpty &&
                d.displayName.trim().toLowerCase() != code.toLowerCase()) {
              backendDisplayName = d.displayName.trim();
            }
            break;
          }
        }
        if (growth == 0.0 && i > 0 && values[i - 1] > 0 && val > 0) {
          growth = ((val - values[i - 1]) / values[i - 1]) * 100.0;
        }
        values.add(val);
        growths.add(growth);
      }
      final resolvedLabel = ChainSharePie.labelForChain(code);
      final displayName = (resolvedLabel.toLowerCase() != code.toLowerCase())
          ? resolvedLabel
          : (backendDisplayName ?? resolvedLabel);
      return _ChainSeriesData(
        chainCode: code,
        displayName: displayName,
        color: ChainSharePie.colorForChain(code),
        values: values,
        growthPcts: growths,
        totalRevenue: chainTotals[code] ?? 0.0,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.trends.isEmpty) {
      return Card(
        child: Container(
          width: double.infinity,
          height: 320.0,
          alignment: Alignment.center,
          child: Text('لا توجد بيانات متاحة للمخطط الزمني في هذه الفترة', style: theme.textTheme.bodyMedium),
        ),
      );
    }

    final effectiveTrends = _getEffectiveTrends();
    final seriesList = _extractSeries(effectiveTrends, colorScheme);

    double maxVal = 0.0;
    for (final s in seriesList) {
      for (final v in s.values) {
        if (v > maxVal) maxVal = v;
      }
    }
    if (maxVal <= 0) {
      maxVal = effectiveTrends.map((e) => e.revenue).fold<double>(0.0, math.max);
    }
    if (maxVal <= 0) maxVal = 1.0;

    return Card(
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8.0,
              runSpacing: 8.0,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'منحنى نمو المبيعات الشهري حسب السلاسل',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      'Sell-Out Trend',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      'تتبع المبيعات ونمو الإيرادات شهرياً لكل سلسلة تجارية بلونها المميز',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                // Multi-chain legend pills with Arabic on line 1 and English on line 2
                Wrap(
                  spacing: 6.0,
                  runSpacing: 6.0,
                  children: seriesList.map((series) {
                    final parts = ChainSharePie.splitBilingualLabel(series.displayName);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
                      decoration: BoxDecoration(
                        color: series.color.withOpacity(0.12),
                        borderRadius: M3Shape.radiusLg,
                        border: Border.all(color: series.color.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 9.0,
                            height: 9.0,
                            decoration: BoxDecoration(
                              color: series.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6.0),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  parts.ar,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                if (parts.en != null)
                                  Text(
                                    parts.en!,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                      fontSize: M3FontSize.microPlus,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            M3Spacing.gapMD,
            // Chart Area with Financial Y-Axis on the left and Canvas on the right
            SizedBox(
              height: 240.0,
              child: Row(
                children: [
                  // Vertical Financial Axis (Y-Axis)
                  SizedBox(
                    width: 62.0,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10.0, bottom: 10.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(5, (i) {
                          final val = maxVal * (4 - i) / 4.0;
                          return Text(
                            _formatYAxisLabel(val),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withOpacity(0.85),
                              fontWeight: FontWeight.bold,
                              fontSize: M3FontSize.microPlus,
                              fontFamily: 'Cairo',
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  // Canvas Chart
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return MouseRegion(
                          onHover: (event) {
                            final count = effectiveTrends.length;
                            if (count <= 1) {
                              if (hoveredIndex != 0) setState(() => hoveredIndex = 0);
                              return;
                            }
                            final dx = event.localPosition.dx;
                            final step = constraints.maxWidth / count;
                            final index = (dx / step).floor().clamp(0, count - 1);
                            if (hoveredIndex != index) {
                              setState(() => hoveredIndex = index);
                            }
                          },
                          onExit: (_) => setState(() => hoveredIndex = null),
                          child: Stack(
                            children: [
                              CustomPaint(
                                size: Size(constraints.maxWidth, constraints.maxHeight),
                                painter: _TrendChartPainter(
                                  seriesList: seriesList,
                                  pointCount: effectiveTrends.length,
                                  maxVal: maxVal,
                                  hoveredIndex: hoveredIndex,
                                  gridColor: colorScheme.outlineVariant.withOpacity(0.35),
                                  surfaceColor: colorScheme.surface,
                                ),
                              ),
                              // Hover tooltip
                              if (hoveredIndex != null && hoveredIndex! < effectiveTrends.length)
                                _buildHoverIndicator(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                  maxVal,
                                  seriesList,
                                  effectiveTrends,
                                  colorScheme,
                                  theme,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8.0),
            // Month labels row (X-Axis) aligned precisely under each month's points
            Row(
              children: [
                const SizedBox(width: 68.0), // Matching 62.0 Y-Axis + 6.0 gap
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: List.generate(effectiveTrends.length, (index) {
                        final item = effectiveTrends[index];
                        final label = _formatAxisLabel(item);
                        final labelEn = _formatAxisLabelEn(item);
                        final isHovered = hoveredIndex == index;

                        return Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 1.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      label,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: isHovered ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                        fontWeight: isHovered ? FontWeight.bold : FontWeight.w600,
                                        fontSize: M3FontSize.tinyPlus,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    if (labelEn != null)
                                      Text(
                                        labelEn,
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: isHovered
                                              ? colorScheme.primary
                                              : colorScheme.onSurfaceVariant.withOpacity(0.75),
                                          fontWeight: isHovered ? FontWeight.bold : FontWeight.w500,
                                          fontSize: M3FontSize.micro,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoverIndicator(
    double width,
    double height,
    double maxVal,
    List<_ChainSeriesData> seriesList,
    List<DailyTrendItem> effectiveTrends,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final idx = hoveredIndex!;
    final item = effectiveTrends[idx];
    final count = effectiveTrends.length;
    final stepX = width / count;
    final x = (idx + 0.5) * stepX;

    double peakAtIdx = 0.0;
    for (final s in seriesList) {
      if (idx < s.values.length && s.values[idx] > peakAtIdx) {
        peakAtIdx = s.values[idx];
      }
    }
    if (peakAtIdx <= 0) peakAtIdx = item.revenue;
    const double topPad = 18.0;
    const double bottomPad = 18.0;
    final usableHeight = height - (topPad + bottomPad);
    final baselineY = height - bottomPad;
    final y = baselineY - (peakAtIdx / maxVal * usableHeight);
    final hasDistinctDate = item.monthLabel.isNotEmpty &&
        item.date.isNotEmpty &&
        item.monthLabel.trim() != item.date.trim();

    return Positioned(
      left: (x - 95).clamp(0.0, math.max(0.0, width - 210.0)),
      top: (y - 95).clamp(0.0, math.max(0.0, height - 135.0)),
      child: IgnorePointer(
        child: Container(
          constraints: const BoxConstraints(minWidth: 175.0, maxWidth: 230.0),
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: colorScheme.inverseSurface,
            borderRadius: M3Shape.radiusSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.monthLabel.isNotEmpty ? item.monthLabel : item.date,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onInverseSurface.withOpacity(0.95),
                  fontWeight: FontWeight.bold,
                  fontSize: M3FontSize.tinyPlus,
                ),
              ),
              if (hasDistinctDate)
                Text(
                  item.date,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onInverseSurface.withOpacity(0.72),
                    fontSize: M3FontSize.micro,
                  ),
                ),
              const SizedBox(height: 5.0),
              ...seriesList.map((s) {
                final val = idx < s.values.length ? s.values[idx] : 0.0;
                final growth = idx < s.growthPcts.length ? s.growthPcts[idx] : 0.0;
                final growthStr = (val > 0 && growth != 0.0)
                    ? ' (\u200E${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}%\u200E)'
                    : '';
                final valueLabel = val > 0
                    ? '${CurrencyFormatter.formatEGP(val)}$growthStr'
                    : 'لا توجد بيانات مرفوعة';
                final parts = ChainSharePie.splitBilingualLabel(s.displayName);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 5.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 7.0,
                        height: 7.0,
                        margin: const EdgeInsets.only(top: 4.0),
                        decoration: BoxDecoration(
                          color: val > 0 ? s.color : s.color.withOpacity(0.45),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5.0),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              parts.ar,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: val > 0
                                    ? colorScheme.onInverseSurface
                                    : colorScheme.onInverseSurface.withOpacity(0.65),
                                fontWeight: FontWeight.bold,
                                fontSize: M3FontSize.tinyPlus,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (parts.en != null)
                              Text(
                                parts.en!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onInverseSurface.withOpacity(0.7),
                                  fontSize: M3FontSize.micro,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 2.0),
                            Text(
                              valueLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: val > 0
                                    ? colorScheme.onInverseSurface.withOpacity(0.95)
                                    : colorScheme.onInverseSurface.withOpacity(0.65),
                                fontWeight: val > 0 ? FontWeight.w700 : FontWeight.normal,
                                fontSize: M3FontSize.tiny,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (seriesList.length > 1) ...[
                Divider(height: 6.0, color: colorScheme.onInverseSurface.withOpacity(0.2)),
                Text(
                  'الإجمالي',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onInverseSurface.withOpacity(0.85),
                    fontWeight: FontWeight.bold,
                    fontSize: M3FontSize.microPlus,
                  ),
                ),
                Text(
                  CurrencyFormatter.formatEGP(item.revenue),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onInverseSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: M3FontSize.tiny,
                  ),
                ),
                Text(
                  '${CurrencyFormatter.formatUnits(item.units)} عبوة',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onInverseSurface.withOpacity(0.8),
                    fontSize: M3FontSize.microPlus,
                  ),
                ),
              ] else
                Text(
                  '${CurrencyFormatter.formatUnits(item.units)} عبوة',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onInverseSurface.withOpacity(0.8),
                    fontSize: M3FontSize.tiny,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  final List<_ChainSeriesData> seriesList;
  final int pointCount;
  final double maxVal;
  final int? hoveredIndex;
  final Color gridColor;
  final Color surfaceColor;

  _TrendChartPainter({
    required this.seriesList,
    required this.pointCount,
    required this.maxVal,
    required this.hoveredIndex,
    required this.gridColor,
    required this.surfaceColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pointCount == 0 || seriesList.isEmpty) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    const double topPad = 18.0;
    const double bottomPad = 18.0;
    final double usableHeight = size.height - (topPad + bottomPad);
    final double baselineY = size.height - bottomPad;

    // Draw horizontal grid lines (5 lines: 0, 25%, 50%, 75%, 100%)
    const horizontalLines = 4;
    for (int i = 0; i <= horizontalLines; i++) {
      final y = baselineY - (i * (usableHeight / horizontalLines));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Single-month mode: draw horizontal reference bar + glowing point per chain
    if (pointCount == 1) {
      final centerX = size.width / 2.0;
      for (int sIdx = 0; sIdx < seriesList.length; sIdx++) {
        final series = seriesList[sIdx];
        final val = series.values.isNotEmpty ? series.values.first : 0.0;
        if (val <= 0) continue;
        final y = baselineY - (val / maxVal * usableHeight);
        final offsetX = (sIdx - (seriesList.length - 1) / 2.0) * 28.0;
        final pt = Offset((centerX + offsetX).clamp(24.0, size.width - 24.0), y);

        final guidePaint = Paint()
          ..color = series.color.withOpacity(0.25)
          ..strokeWidth = 2.0;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), guidePaint);

        final glowPaint = Paint()..color = series.color.withOpacity(0.22);
        final dotBgPaint = Paint()..color = surfaceColor;
        final dotPaint = Paint()..color = series.color;
        canvas.drawCircle(pt, 12.0, glowPaint);
        canvas.drawCircle(pt, 6.5, dotBgPaint);
        canvas.drawCircle(pt, 5.0, dotPaint);
      }
      return;
    }

    final double stepX = size.width / pointCount;

    // Draw vertical hover guide line
    if (hoveredIndex != null && hoveredIndex! >= 0 && hoveredIndex! < pointCount) {
      final hx = (hoveredIndex! + 0.5) * stepX;
      final hoverLinePaint = Paint()
        ..color = gridColor.withOpacity(0.85)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(hx, topPad), Offset(hx, baselineY), hoverLinePaint);
    }

    // Draw each chain's curve in its own brand color
    for (final series in seriesList) {
      final activeIndices = <int>[];
      final activePoints = <Offset>[];
      for (int i = 0; i < pointCount; i++) {
        final val = i < series.values.length ? series.values[i] : 0.0;
        if (val > 0) {
          final x = (i + 0.5) * stepX;
          final y = baselineY - (val / maxVal * usableHeight);
          activeIndices.add(i);
          activePoints.add(Offset(x, y));
        }
      }

      if (activePoints.isEmpty) continue;

      final fillGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          series.color.withOpacity(seriesList.length > 1 ? 0.16 : 0.25),
          series.color.withOpacity(0.0),
        ],
      );

      if (activePoints.length == 1) {
        final pt = activePoints.first;
        // Subtle dotted reference stem down to baseline
        final dashPaint = Paint()
          ..color = series.color.withOpacity(0.35)
          ..strokeWidth = 1.5;
        double curY = baselineY;
        while (curY > pt.dy + 8.0) {
          final nextY = math.max(pt.dy + 8.0, curY - 4.0);
          canvas.drawLine(Offset(pt.dx, curY), Offset(pt.dx, nextY), dashPaint);
          curY -= 8.0;
        }

        // Concentric glow rings for single recorded month
        canvas.drawCircle(pt, 14.0, Paint()..color = series.color.withOpacity(0.18));
        canvas.drawCircle(pt, 8.0, Paint()..color = series.color.withOpacity(0.35));
      } else {
        final path = Path();
        final fillPath = Path();

        path.moveTo(activePoints.first.dx, activePoints.first.dy);
        fillPath.moveTo(activePoints.first.dx, baselineY);
        fillPath.lineTo(activePoints.first.dx, activePoints.first.dy);

        for (int i = 0; i < activePoints.length - 1; i++) {
          final p0 = activePoints[i];
          final p1 = activePoints[i + 1];
          final controlX1 = p0.dx + (p1.dx - p0.dx) / 2.0;
          final controlY1 = p0.dy;
          final controlX2 = p0.dx + (p1.dx - p0.dx) / 2.0;
          final controlY2 = p1.dy;

          path.cubicTo(controlX1, controlY1, controlX2, controlY2, p1.dx, p1.dy);
          fillPath.cubicTo(controlX1, controlY1, controlX2, controlY2, p1.dx, p1.dy);
        }

        fillPath.lineTo(activePoints.last.dx, baselineY);
        fillPath.close();

        final fillPaint = Paint()
          ..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, size.width, baselineY))
          ..style = PaintingStyle.fill;
        canvas.drawPath(fillPath, fillPaint);

        final linePaint = Paint()
          ..color = series.color
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(path, linePaint);
      }

      final dotPaint = Paint()..color = series.color;
      final dotBgPaint = Paint()..color = surfaceColor;
      final isSingleActive = activePoints.length == 1;

      for (int k = 0; k < activePoints.length; k++) {
        final idx = activeIndices[k];
        final p = activePoints[k];
        final isHovered = hoveredIndex == idx;
        if (isHovered || isSingleActive) {
          canvas.drawCircle(
            p,
            isHovered ? 10.0 : 9.0,
            Paint()..color = series.color.withOpacity(0.28),
          );
        }
        canvas.drawCircle(p, (isHovered || isSingleActive) ? 5.6 : 4.0, dotBgPaint);
        canvas.drawCircle(p, (isHovered || isSingleActive) ? 4.2 : 2.8, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) => true;
}

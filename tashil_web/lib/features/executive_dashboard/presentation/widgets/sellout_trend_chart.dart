import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/widgets/m3_section_title.dart';
import 'package:tashil_web/core/widgets/m3_tonal_surface.dart';
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

  /// Optional net Sell-In (EGP) per chain (lowercase code) and month key (`YYYY-MM`).
  /// When present, each chain gets a dashed Sell-In line next to its solid Sell-Out line.
  final Map<String, Map<String, double>>? sellInByChain;

  const SelloutTrendChart({
    super.key,
    required this.trends,
    this.sellInByChain,
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

  /// Sell-In per month (null = no Sell-In data for that month).
  final List<double?> sellInValues;

  bool get hasSellIn => sellInValues.any((v) => v != null);

  const _ChainSeriesData({
    this.sellInValues = const [],
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

  static String _monthKeyOf(DailyTrendItem t) {
    final mk = t.monthKey.trim();
    if (mk.length >= 7) return mk.substring(0, 7);
    final d = t.date.trim();
    return d.length >= 7 ? d.substring(0, 7) : d;
  }

  /// Sell-In values aligned with [trends] for one chain code, or for all chains when null.
  List<double?> _sellInFor(String? chainCode, List<DailyTrendItem> trends) {
    final src = widget.sellInByChain;
    if (src == null || src.isEmpty) return const [];
    return trends.map((t) {
      final mk = _monthKeyOf(t);
      if (chainCode != null) return src[chainCode.toLowerCase()]?[mk];
      double? sum;
      for (final m in src.values) {
        final v = m[mk];
        if (v != null) sum = (sum ?? 0.0) + v;
      }
      return sum;
    }).toList();
  }

  List<_ChainSeriesData> _extractSeries(
      List<DailyTrendItem> effectiveTrends, ColorScheme colorScheme) {
    final chainTotals = <String, double>{};
    for (final t in effectiveTrends) {
      t.chainRevenues.forEach((chain, rev) {
        if (rev > 0) {
          chainTotals[chain] = (chainTotals[chain] ?? 0.0) + rev;
        }
      });
      for (final d in t.chainDetails) {
        if (d.revenue > 0 && !chainTotals.containsKey(d.retailerChain)) {
          chainTotals[d.retailerChain] =
              (chainTotals[d.retailerChain] ?? 0.0) + d.revenue;
        }
      }
    }

    if (chainTotals.isEmpty) {
      final totalRev =
          effectiveTrends.fold<double>(0.0, (s, e) => s + e.revenue);
      return [
        _ChainSeriesData(
          chainCode: 'total',
          displayName: 'الإجمالي',
          color: colorScheme.primary,
          values: effectiveTrends.map((e) => e.revenue).toList(),
          growthPcts: List<double>.filled(effectiveTrends.length, 0.0),
          totalRevenue: totalRev,
          sellInValues: _sellInFor(null, effectiveTrends),
        ),
      ];
    }

    const preferredOrder = [
      'fathalla',
      'gomla',
      'beet-elgomla',
      'carrefour',
      'spinneys',
      'metro',
      'seoudi',
      'kazyon'
    ];
    final activeChains =
        chainTotals.keys.where((k) => (chainTotals[k] ?? 0) > 0).toList()
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
        sellInValues: _sellInFor(code, effectiveTrends),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.trends.isEmpty) {
      return Card.outlined(
        child: Container(
          width: double.infinity,
          height: 320.0,
          alignment: Alignment.center,
          child: Text('لا توجد بيانات لهذه الفترة',
              style: theme.textTheme.bodyMedium),
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
      for (final v in s.sellInValues) {
        if (v != null && v > maxVal) maxVal = v;
      }
    }
    final showSellIn = seriesList.any((s) => s.hasSellIn);
    if (maxVal <= 0) {
      maxVal =
          effectiveTrends.map((e) => e.revenue).fold<double>(0.0, math.max);
    }
    if (maxVal <= 0) maxVal = 1.0;

    return Card.outlined(
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
                    const M3SectionTitle(
                      'الاتجاه الشهري (\u2068Sell-Out\u2069)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      'المبيعات الشهرية لكل سلسلة',
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
                  children: seriesList.map<Widget>((series) {
                    final parts =
                        ChainSharePie.splitBilingualLabel(series.displayName);
                    return M3ChipSurface(
                      // Neutral tonal pill; the series colour is shown by the
                      // dot (graphic ≥ 3:1); text stays onSurface.
                      color: colorScheme.surfaceContainerHigh,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                              radius: 4.5, backgroundColor: series.color),
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
                                    fontWeight: FontWeight.w600,
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
                  }).toList()
                    ..addAll(showSellIn
                        ? [
                            _lineStyleKey(theme, 'Sell-Out', dashed: false),
                            _lineStyleKey(theme, 'Sell-In صافي', dashed: true),
                          ]
                        : const <Widget>[]),
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
                    // "19.1 مليون ج.م" ≈ 69px at 11sp; 84 leaves a margin.
                    width: 84.0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(5, (i) {
                          final val = maxVal * (4 - i) / 4.0;
                          // Longer values (billions) scale down, never wrap.
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              CurrencyFormatter.formatCompactEGP(val,
                                  words: true, isolate: true),
                              maxLines: 1,
                              softWrap: false,
                              textDirection: TextDirection.rtl,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
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
                              if (hoveredIndex != 0) {
                                setState(() => hoveredIndex = 0);
                              }
                              return;
                            }
                            final dx = event.localPosition.dx;
                            final step = constraints.maxWidth / count;
                            final index =
                                (dx / step).floor().clamp(0, count - 1);
                            if (hoveredIndex != index) {
                              setState(() => hoveredIndex = index);
                            }
                          },
                          onExit: (_) => setState(() => hoveredIndex = null),
                          child: Stack(
                            children: [
                              CustomPaint(
                                size: Size(constraints.maxWidth,
                                    constraints.maxHeight),
                                painter: _TrendChartPainter(
                                  seriesList: seriesList,
                                  pointCount: effectiveTrends.length,
                                  maxVal: maxVal,
                                  hoveredIndex: hoveredIndex,
                                  gridColor: colorScheme.outlineVariant,
                                  surfaceColor: colorScheme.surface,
                                ),
                              ),
                              // Hover tooltip
                              if (hoveredIndex != null &&
                                  hoveredIndex! < effectiveTrends.length)
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
                        final isHovered = hoveredIndex == index;

                        return Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 1.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      label,
                                      maxLines: 1,
                                      softWrap: false,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: isHovered
                                            ? colorScheme.primary
                                            : colorScheme.onSurfaceVariant,
                                        fontWeight:
                                            isHovered ? FontWeight.w600 : null,
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

  /// Legend key showing the line style used for Sell-Out (solid) or Sell-In (dashed).
  Widget _lineStyleKey(ThemeData theme, String label, {required bool dashed}) {
    final colorScheme = theme.colorScheme;
    return M3ChipSurface(
      color: colorScheme.surfaceContainerHigh,
      borderColor: colorScheme.outlineVariant,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(22.0, 10.0),
            painter: _LineKeyPainter(
                color: colorScheme.onSurfaceVariant, dashed: dashed),
          ),
          const SizedBox(width: 6.0),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
    final showSellIn = seriesList.any((s) => s.hasSellIn);
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
        child: M3TonalSurface(
          color: colorScheme.inverseSurface,
          borderRadius: M3Shape.radiusSm,
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
          constraints: const BoxConstraints(minWidth: 175.0, maxWidth: 230.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.monthLabel.isNotEmpty ? item.monthLabel : item.date,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onInverseSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hasDistinctDate)
                Text(
                  item.date,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onInverseSurface,
                  ),
                ),
              const SizedBox(height: 5.0),
              ...seriesList.map((s) {
                final val = idx < s.values.length ? s.values[idx] : 0.0;
                final growth =
                    idx < s.growthPcts.length ? s.growthPcts[idx] : 0.0;
                final growthStr = (val > 0 && growth != 0.0)
                    ? ' (\u200E${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}%\u200E)'
                    : '';
                final sellOutText = val > 0
                    ? '${CurrencyFormatter.formatEGP(val)}$growthStr'
                    : 'لم تُرفع بيانات بعد';
                final valueLabel =
                    showSellIn ? 'Sell-Out: $sellOutText' : sellOutText;
                final sellIn =
                    idx < s.sellInValues.length ? s.sellInValues[idx] : null;
                final sellInLabel =
                    'Sell-In (صافي بعد المرتجعات): ${sellIn != null ? CurrencyFormatter.formatEGP(sellIn) : 'لا توجد بيانات'}';
                final parts = ChainSharePie.splitBilingualLabel(s.displayName);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 5.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: CircleAvatar(
                            radius: 3.5,
                            backgroundColor:
                                val > 0 ? s.color : colorScheme.outline),
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
                                    : colorScheme.onInverseSurface,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (parts.en != null)
                              Text(
                                parts.en!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onInverseSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 2.0),
                            Text(
                              valueLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: val > 0
                                    ? colorScheme.onInverseSurface
                                    : colorScheme.onInverseSurface,
                                fontWeight: val > 0 ? FontWeight.w600 : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (showSellIn)
                              Text(
                                sellInLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: sellIn != null
                                      ? colorScheme.onInverseSurface
                                      : colorScheme.onInverseSurface,
                                  fontWeight: sellIn != null
                                      ? FontWeight.w600
                                      : FontWeight.normal,
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
                Divider(height: 6.0, color: colorScheme.onInverseSurface),
                Text(
                  'الإجمالي',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  CurrencyFormatter.formatEGP(item.revenue),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${CurrencyFormatter.formatUnits(item.units)} وحدة',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onInverseSurface,
                  ),
                ),
              ] else
                Text(
                  '${CurrencyFormatter.formatUnits(item.units)} وحدة',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onInverseSurface,
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
        final pt =
            Offset((centerX + offsetX).clamp(24.0, size.width - 24.0), y);

        final guidePaint = Paint()
          ..color = series.color.withValues(alpha: 0.25)
          ..strokeWidth = 2.0;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), guidePaint);

        final glowPaint = Paint()..color = series.color.withValues(alpha: 0.22);
        final dotBgPaint = Paint()..color = surfaceColor;
        final dotPaint = Paint()..color = series.color;
        canvas.drawCircle(pt, 12.0, glowPaint);
        canvas.drawCircle(pt, 6.5, dotBgPaint);
        canvas.drawCircle(pt, 5.0, dotPaint);
      }
      for (int sIdx = 0; sIdx < seriesList.length; sIdx++) {
        final series = seriesList[sIdx];
        final v =
            series.sellInValues.isNotEmpty ? series.sellInValues.first : null;
        if (v == null || v <= 0) continue;
        final offsetX = (sIdx - (seriesList.length - 1) / 2.0) * 28.0 + 12.0;
        final pt = Offset((centerX + offsetX).clamp(24.0, size.width - 24.0),
            baselineY - (v / maxVal * usableHeight));
        _drawDashedPath(
            canvas,
            Path()
              ..moveTo(0, pt.dy)
              ..lineTo(size.width, pt.dy),
            Paint()
              ..color = series.color.withValues(alpha: 0.3)
              ..strokeWidth = 1.5
              ..style = PaintingStyle.stroke);
        _drawSellInDot(canvas, pt, series.color, true);
      }
      return;
    }

    final double stepX = size.width / pointCount;

    // Draw vertical hover guide line
    if (hoveredIndex != null &&
        hoveredIndex! >= 0 &&
        hoveredIndex! < pointCount) {
      final hx = (hoveredIndex! + 0.5) * stepX;
      final hoverLinePaint = Paint()
        ..color = gridColor
        ..strokeWidth = 1.2;
      canvas.drawLine(
          Offset(hx, topPad), Offset(hx, baselineY), hoverLinePaint);
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
          series.color.withValues(alpha: seriesList.length > 1 ? 0.16 : 0.25),
          series.color.withValues(alpha: 0.0),
        ],
      );

      if (activePoints.length == 1) {
        final pt = activePoints.first;
        // Subtle dotted reference stem down to baseline
        final dashPaint = Paint()
          ..color = series.color.withValues(alpha: 0.35)
          ..strokeWidth = 1.5;
        double curY = baselineY;
        while (curY > pt.dy + 8.0) {
          final nextY = math.max(pt.dy + 8.0, curY - 4.0);
          canvas.drawLine(Offset(pt.dx, curY), Offset(pt.dx, nextY), dashPaint);
          curY -= 8.0;
        }

        // Concentric glow rings for single recorded month
        canvas.drawCircle(
            pt, 14.0, Paint()..color = series.color.withValues(alpha: 0.18));
        canvas.drawCircle(
            pt, 8.0, Paint()..color = series.color.withValues(alpha: 0.35));
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

          path.cubicTo(
              controlX1, controlY1, controlX2, controlY2, p1.dx, p1.dy);
          fillPath.cubicTo(
              controlX1, controlY1, controlX2, controlY2, p1.dx, p1.dy);
        }

        fillPath.lineTo(activePoints.last.dx, baselineY);
        fillPath.close();

        final fillPaint = Paint()
          ..shader = fillGradient
              .createShader(Rect.fromLTWH(0, 0, size.width, baselineY))
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
            Paint()..color = series.color.withValues(alpha: 0.28),
          );
        }
        canvas.drawCircle(
            p, (isHovered || isSingleActive) ? 5.6 : 4.0, dotBgPaint);
        canvas.drawCircle(
            p, (isHovered || isSingleActive) ? 4.2 : 2.8, dotPaint);
      }
    }

    for (final series in seriesList) {
      _paintSellIn(canvas, series, stepX, baselineY, usableHeight);
    }
  }

  /// Dashed Sell-In curve in the chain's color, with hollow dots. Months without
  /// Sell-In data are skipped (the line joins the months that have data).
  void _paintSellIn(Canvas canvas, _ChainSeriesData series, double stepX,
      double baselineY, double usableHeight) {
    final pts = <Offset>[];
    final idxs = <int>[];
    for (int i = 0; i < pointCount && i < series.sellInValues.length; i++) {
      final v = series.sellInValues[i];
      if (v == null || v <= 0) continue;
      pts.add(
          Offset((i + 0.5) * stepX, baselineY - (v / maxVal * usableHeight)));
      idxs.add(i);
    }
    if (pts.isEmpty) return;
    if (pts.length > 1) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 0; i < pts.length - 1; i++) {
        final p0 = pts[i];
        final p1 = pts[i + 1];
        final cx = p0.dx + (p1.dx - p0.dx) / 2.0;
        path.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
      }
      _drawDashedPath(
        canvas,
        path,
        Paint()
          ..color = series.color.withValues(alpha: 0.9)
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    for (int k = 0; k < pts.length; k++) {
      _drawSellInDot(canvas, pts[k], series.color, hoveredIndex == idxs[k]);
    }
  }

  void _drawSellInDot(Canvas canvas, Offset p, Color color, bool emphasized) {
    canvas.drawCircle(p, emphasized ? 5.0 : 3.6, Paint()..color = surfaceColor);
    canvas.drawCircle(
      p,
      emphasized ? 5.0 : 3.6,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = emphasized ? 2.2 : 1.6,
    );
  }

  static void _drawDashedPath(Canvas canvas, Path path, Paint paint,
      {double dash = 7.0, double gap = 5.0}) {
    for (final metric in path.computeMetrics()) {
      double d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) => true;
}

class _LineKeyPainter extends CustomPainter {
  final Color color;
  final bool dashed;

  const _LineKeyPainter({required this.color, required this.dashed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = dashed ? 2.0 : 3.0
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2.0;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    double x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
          Offset(x, y), Offset(math.min(x + 5.0, size.width), y), paint);
      x += 8.0;
    }
  }

  @override
  bool shouldRepaint(covariant _LineKeyPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dashed != dashed;
}

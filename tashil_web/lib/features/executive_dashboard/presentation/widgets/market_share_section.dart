import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/theme/m3_status_colors.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../cpfr_replenishment/domain/cpfr_models.dart';

/// Market Share + Sell In vs Sell Out overview, shown above the existing
/// Executive Dashboard sections.
///
/// Every number here comes from real backend data:
/// * Share per SKU / per Category: the executive summary
///   (`category_contributions` + `pareto_skus`, sourced from
///   `tashil_analytics.sell_out_facts`, own-brand vs other suppliers).
/// * Sell In vs Sell Out: the CPFR reconciliation report
///   (`sell_in_records` joined with `sell_out_facts`).
/// Pieces without a real data source render an honest empty state.
class MarketShareSection extends StatelessWidget {
  const MarketShareSection({
    super.key,
    required this.kpis,
    required this.cpfr,
    required this.cpfrLoading,
    this.cpfrError,
    required this.periodMonths,
    required this.year,
  });

  final ExecutiveKPIsModel kpis;
  final CPFRDashboardModel? cpfr;
  final bool cpfrLoading;
  final String? cpfrError;

  /// Months (1-12) covered by the selected period.
  final Set<int> periodMonths;
  final int year;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final sku = _SkuShareCard(kpis: kpis);
      final cat = _CategoryShareCard(kpis: kpis);
      return Column(
        key: const ValueKey('market_share_section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            _EqualHeightRow(
              spacing: M3Spacing.md,
              textDirection: Directionality.of(context),
              children: [sku, cat],
            )
          else ...[
            sku,
            M3Spacing.gapMD,
            cat,
          ],
          M3Spacing.gapLG,
          _SellInVsSellOut(
            cpfr: cpfr,
            loading: cpfrLoading,
            error: cpfrError,
            periodMonths: periodMonths,
            year: year,
            wide: wide,
          ),
          M3Spacing.gapLG,
        ],
      );
    });
  }
}

String _fmtInt(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}$b';
}

String _pct(double v) => '${v.toStringAsFixed(v >= 10 || v == 0 ? 0 : 1)}%';

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.title, required this.subtitle, required this.count, this.badgeKey});
  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final Key? badgeKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 20.0, color: cs.primary),
          M3Spacing.gapXS,
          Flexible(
            child: Text(title,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          M3Spacing.gapXS,
          Badge.count(key: badgeKey, count: count, backgroundColor: cs.error, textColor: cs.onError),
        ]),
        M3Spacing.gapXXS,
        Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text, {this.keyName});
  final String text;
  final String? keyName;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: keyName == null ? null : ValueKey<String>(keyName!),
      padding: M3Spacing.pLg,
      child: Column(children: [
        Icon(AppIcons.empty, size: 32.0, color: theme.colorScheme.onSurfaceVariant),
        M3Spacing.gapSM,
        Text(text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.items);
  final List<(Color, String)> items;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(spacing: 12.0, runSpacing: 4.0, children: [
      for (final (c, l) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10.0, height: 10.0, decoration: BoxDecoration(color: c, borderRadius: M3Shape.radiusXs)),
          M3Spacing.gapXXS,
          Text(l, style: theme.textTheme.labelSmall),
        ]),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Share per SKU: each top own SKU's share of its category's market revenue,
// split into this SKU / our other SKUs in the category / competitors.
// ---------------------------------------------------------------------------
class _SkuShareCard extends StatelessWidget {
  const _SkuShareCard({required this.kpis});
  final ExecutiveKPIsModel kpis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final acc = M3StatusColors.of(context).accents;
    final cats = {for (final c in kpis.categoryContributions) c.category: c};
    final rows = <({ParetoSkuItemModel sku, double self, double ownOther, double comp})>[];
    final skus = [...kpis.paretoSkus]..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    for (final s in skus) {
      final c = cats[s.category];
      if (c == null || c.marketTotalRevenue <= 0) continue;
      final self = (s.totalRevenue / c.marketTotalRevenue).clamp(0.0, 1.0);
      final own = (c.totalRevenue / c.marketTotalRevenue).clamp(self, 1.0);
      rows.add((sku: s, self: self, ownOther: own - self, comp: 1.0 - own));
      if (rows.length == 6) break;
    }
    return Card.outlined(
      key: const ValueKey('share_per_sku_card'),
      child: Padding(
        padding: M3Spacing.pMd,
        child: _FillColumn(
          textDirection: Directionality.of(context),
          children: [
            _CardHeader(
              icon: AppIcons.analytics,
              title: 'الحصة حسب الصنف',
              subtitle: 'حصة أهم الأصناف من مبيعات الفئة',
              count: rows.length,
              badgeKey: const ValueKey('share_per_sku_badge'),
            ),
            M3Spacing.gapSM,
            _Legend([
              (cs.primary, 'هذا الصنف'),
              (cs.primaryContainer, 'أصنافنا الأخرى'),
              (acc.competitor, 'Competitors'),
            ]),
            M3Spacing.gapSM,
            if (rows.isEmpty)
              const _EmptyNote('لا توجد بيانات حصة للأصناف في هذه الفترة', keyName: 'share_per_sku_empty')
            else
              _GrowingColumn(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    _SkuRow(
                      title: Text(rows[i].sku.skuName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                      category: Text(rows[i].sku.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      bar: ClipRRect(
                        key: ValueKey('sku_share_bar_$i'),
                        borderRadius: M3Shape.radiusSm,
                        child: Row(children: [
                          _seg(context, rows[i].self, cs.primary, cs.onPrimary),
                          _seg(context, rows[i].ownOther, cs.primaryContainer, cs.onPrimaryContainer),
                          _seg(context, rows[i].comp, acc.competitor, cs.onSurface),
                        ]),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _seg(BuildContext context, double v, Color bg, Color fg) {
    final flex = (v * 1000).round();
    if (flex <= 0) return const SizedBox.shrink();
    return Expanded(
      flex: flex,
      child: Container(
        color: bg,
        alignment: Alignment.center,
        child: v >= 0.08
            ? Text(_pct(v * 100),
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700))
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Share per Category: our share of each category's total market revenue.
// ---------------------------------------------------------------------------
class _CategoryShareCard extends StatelessWidget {
  const _CategoryShareCard({required this.kpis});
  final ExecutiveKPIsModel kpis;

  @override
  Widget build(BuildContext context) {
    final cats = kpis.categoryContributions.where((c) => c.marketTotalRevenue > 0).toList()
      ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    final top = cats.take(4).toList();
    return Card.outlined(
      key: const ValueKey('share_per_category_card'),
      child: Padding(
        padding: M3Spacing.pMd,
        child: _FillColumn(
          textDirection: Directionality.of(context),
          children: [
            _CardHeader(
              icon: AppIcons.donutChart,
              title: 'الحصة حسب الفئة',
              subtitle: 'حصتنا في كل فئة',
              count: top.length,
              badgeKey: const ValueKey('share_per_category_badge'),
            ),
            M3Spacing.gapSM,
            if (top.isEmpty)
              const _EmptyNote('لا توجد بيانات للفئات في هذه الفترة', keyName: 'share_per_category_empty')
            else
              _GrowingGrid(
                spacing: 12.0,
                twoColumnMinWidth: 420.0,
                textDirection: Directionality.of(context),
                children: [for (final cat in top) _CategoryTile(cat: cat)],
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.cat});
  final CategoryContributionModel cat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final acc = M3StatusColors.of(context).accents;
    final ours = cat.tenantCategorySharePct.clamp(0.0, 100.0);
    return Card.filled(
      margin: EdgeInsets.zero,
      child: _ShareTile(
        textDirection: Directionality.of(context),
        donut: _Donut(
          key: ValueKey('category_donut_${cat.category}'),
          value: ours / 100.0,
          label: _pct(ours),
        ),
        details: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cat.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          M3Spacing.gapXXS,
          if (cat.tenantRank > 0)
            Text(
              'Rank #${cat.tenantRank}${cat.supplierCount > 0 ? ' of ${cat.supplierCount}' : ''}',
              key: ValueKey('category_rank_${cat.category}'),
              style: theme.textTheme.labelMedium?.copyWith(
                // tealBase (#009688) fails WCAG on surface (~3.33:1); use deep teal for text.
                color: cat.tenantRank == 1 ? acc.tealDeep : cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          M3Spacing.gapXXS,
          _CompetitorBar(cat: cat, ours: ours),
          M3Spacing.gapXXS,
          if (cat.topCompetitors.isEmpty)
            Text('Competitors ${_pct(100.0 - ours)}',
                style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant))
          else
            for (final (i, c) in cat.topCompetitors.take(3).indexed)
              Row(key: ValueKey('category_competitor_${cat.category}_$i'), children: [
                Container(
                  width: 8.0,
                  height: 8.0,
                  decoration: BoxDecoration(color: _competitorShade(acc, i), shape: BoxShape.circle),
                ),
                const SizedBox(width: 4.0),
                Expanded(
                  child: Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ),
                Text(_pct(c.sharePct), style: theme.textTheme.labelSmall),
              ]),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sell In vs Sell Out (CPFR reconciliation report).
// ---------------------------------------------------------------------------
class _SellInVsSellOut extends StatelessWidget {
  const _SellInVsSellOut({
    required this.cpfr,
    required this.loading,
    required this.error,
    required this.periodMonths,
    required this.year,
    required this.wide,
  });
  final CPFRDashboardModel? cpfr;
  final bool loading;
  final String? error;
  final Set<int> periodMonths;
  final int year;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Text('Sell-In vs Sell-Out',
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800));
    if (loading && cpfr == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        M3Spacing.gapSM,
        const LinearProgressIndicator(year2023: false),
      ]);
    }
    // Only months that have BOTH real Sell In and real Sell Out are compared.
    final months = (cpfr?.monthlyReconciliation ?? const <ReconciliationMonthModel>[])
        .where((m) =>
            m.year == year &&
            periodMonths.contains(m.monthNum) &&
            m.hasActualSellOut &&
            m.sellInUnits > 0 &&
            m.sellOutUnits > 0)
        .toList()
      ..sort((a, b) => a.monthNum.compareTo(b.monthNum));
    if (months.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        _EmptyNote(
          error != null
              ? 'تعذّر تحميل بيانات Sell-In/Sell-Out'
              : 'لا توجد شهور بها بيانات Sell-In وSell-Out معًا',
          keyName: 'sell_in_vs_out_empty',
        ),
      ]);
    }
    final sellIn = months.fold<int>(0, (a, m) => a + m.sellInUnits);
    final sellOut = months.fold<int>(0, (a, m) => a + m.sellOutUnits);
    final net = sellIn - sellOut;
    final through = sellIn > 0 ? sellOut / sellIn * 100.0 : 0.0;
    final acc = M3StatusColors.of(context).accents;
    final cs = theme.colorScheme;
    final monthLabel = months.map((m) => m.monthEn.length > 3 ? m.monthEn.substring(0, 3) : m.monthEn).join(', ');

    final tiles = [
      _KpiTile(label: 'Sell-In (وحدة)', value: _fmtInt(sellIn), color: cs.onSurface),
      _KpiTile(label: 'Sell-Out (وحدة)', value: _fmtInt(sellOut), color: cs.onSurface),
      _KpiTile(
          key: const ValueKey('kpi_net_accumulation'),
          label: 'تراكم المخزون (وحدة)',
          value: '${net > 0 ? '+' : ''}${_fmtInt(net)}',
          color: acc.orangeBase),
      _KpiTile(
          key: const ValueKey('kpi_sell_through'),
          label: 'نسبة التصريف',
          value: _pct(through),
          color: acc.tealBase),
    ];

    return Column(
      key: const ValueKey('sell_in_vs_out_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Text('الأصناف والشهور المتطابقة: $monthLabel $year',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        M3Spacing.gapSM,
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 700 ? 4 : 2;
          final w = (c.maxWidth - (cols - 1) * 12.0) / cols;
          return Wrap(spacing: 12.0, runSpacing: 12.0, children: [
            for (final t in tiles) SizedBox(width: w, child: t),
          ]);
        }),
        M3Spacing.gapMD,
        if (wide)
          // Equal height: the row takes the taller card's natural height
          // (usually the table) and the chart stretches to fill it.
          IntrinsicHeight(
            key: const ValueKey('sell_in_vs_out_row'),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 3, child: _StockTable(cpfr: cpfr!)),
              M3Spacing.gapMD,
              Expanded(flex: 2, child: _MonthlyBars(months: months, fill: true)),
            ]),
          )
        else ...[
          _StockTable(cpfr: cpfr!),
          M3Spacing.gapMD,
          _MonthlyBars(months: months),
        ],
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({super.key, required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          M3Spacing.gapXS,
          Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: color)),
        ]),
      ),
    );
  }
}

class _StockTable extends StatelessWidget {
  const _StockTable({required this.cpfr});
  final CPFRDashboardModel cpfr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Aggregate per SKU (the report can list a SKU per branch/region).
    final bySku = <String, ({String name, int sIn, int sOut, int stock, String status})>{};
    for (final i in cpfr.inventoryAndPoItems) {
      final k = i.barcode.isNotEmpty ? i.barcode : i.itemCode;
      final p = bySku[k];
      bySku[k] = (
        name: i.skuName,
        sIn: (p?.sIn ?? 0) + i.sellInUnits,
        sOut: (p?.sOut ?? 0) + i.sellOutUnits,
        stock: (p?.stock ?? 0) + i.estimatedStockUnits,
        status: _worse(p?.status, i.stockStatus),
      );
    }
    final rows = bySku.values.where((r) => r.sIn > 0).toList()
      ..sort((a, b) => b.sIn.compareTo(a.sIn));
    final top = rows.take(8).toList();
    final label = theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700);
    final cell = theme.textTheme.bodySmall;
    return Card.outlined(
      key: const ValueKey('stock_per_sku_table'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('المخزون حسب الصنف', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text('منذ بداية العام (وحدة) · الحالة من تقرير CPFR',
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          M3Spacing.gapSM,
          if (top.isEmpty)
            const _EmptyNote('لا توجد بيانات مخزون لهذه الفترة', keyName: 'stock_per_sku_empty')
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1.3),
                2: FlexColumnWidth(1.3),
                3: FlexColumnWidth(1.3),
                4: FlexColumnWidth(1),
                5: FlexColumnWidth(2.2),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(children: [
                  for (final h in ['الصنف', 'Sell-In', 'Sell-Out', 'الفرق', 'نسبة التصريف', 'الحالة'])
                    Padding(padding: const EdgeInsets.only(bottom: 6.0), child: Text(h, style: label)),
                ]),
                for (final r in top)
                  TableRow(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant))),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: cell?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      Text(_fmtInt(r.sIn), style: cell),
                      Text(_fmtInt(r.sOut), style: cell),
                      Text('${r.sIn - r.sOut > 0 ? '+' : ''}${_fmtInt(r.sIn - r.sOut)}', style: cell),
                      Text(_pct(r.sIn > 0 ? r.sOut / r.sIn * 100.0 : 0.0), style: cell),
                      Align(alignment: AlignmentDirectional.centerStart, child: _StatusChip(status: r.status)),
                    ],
                  ),
              ],
            ),
        ]),
      ),
    );
  }

  static const _rank = {'overstock': 3, 'urgent_replenishment': 2, 'optimal': 1};
  static String _worse(String? a, String b) =>
      a == null ? b : ((_rank[a] ?? 0) >= (_rank[b] ?? 0) ? a : b);
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final acc = M3StatusColors.of(context).accents;
    final (Color c, IconData icon, String text) = switch (status) {
      'optimal' => (acc.tealBase, AppIcons.success, 'Healthy'),
      'overstock' => (acc.redBase, AppIcons.warning, 'Overstock'),
      'urgent_replenishment' => (acc.orangeBase, AppIcons.info, 'Replenish'),
      _ => (M3StatusColors.of(context).accents.neutral, AppIcons.info, status.isEmpty ? 'Unknown' : status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        border: Border.all(color: c.withOpacity(0.6)),
        borderRadius: M3Shape.radiusSm,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14.0, color: c),
        M3Spacing.gapXXS,
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

class _MonthlyBars extends StatelessWidget {
  const _MonthlyBars({required this.months, this.fill = false});
  final List<ReconciliationMonthModel> months;

  /// When true (wide row), the plot area grows to fill the card's height.
  final bool fill;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final acc = M3StatusColors.of(context).accents;
    final maxV = months.fold<int>(1, (a, m) => [a, m.sellInUnits, m.sellOutUnits].reduce((x, y) => x > y ? x : y));
    const chartH = 180.0;
    return Card.outlined(
      key: const ValueKey('sell_in_vs_out_chart'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Monthly Sell-In vs Sell-Out (units)',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          M3Spacing.gapXS,
          _Legend([(cs.primary, 'Sell-In'), (acc.tealBase, 'Sell-Out')]),
          M3Spacing.gapMD,
          _plotArea(
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final m in months)
                Expanded(
                  child: Tooltip(
                    message: '${m.monthEn}: Sell-In ${_fmtInt(m.sellInUnits)} · Sell-Out ${_fmtInt(m.sellOutUnits)}',
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        _bar(m.sellInUnits / maxV * chartH, cs.primary),
                        const SizedBox(width: 3.0),
                        _bar(m.sellOutUnits / maxV * chartH, acc.tealBase),
                      ]),
                      M3Spacing.gapXXS,
                      Text(m.monthEn.length > 3 ? m.monthEn.substring(0, 3) : m.monthEn,
                          style: theme.textTheme.labelSmall),
                    ]),
                  ),
                ),
            ]),
            chartH + 20.0,
          ),
        ]),
      ),
    );
  }

  Widget _plotArea(Widget plot, double minH) => fill
      ? Expanded(child: ConstrainedBox(constraints: BoxConstraints(minHeight: minH), child: plot))
      : SizedBox(height: minH, child: plot);

  Widget _bar(double h, Color c) => Container(
        width: 16.0,
        height: h.clamp(2.0, 180.0),
        decoration: BoxDecoration(
          color: c,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4.0)),
        ),
      );
}

/// Grey shades for the named competitors (strongest first); MD3 theme roles only.
Color _competitorShade(M3AccentRoles acc, int i) =>
    [acc.competitorStrong, acc.competitor, acc.competitorSurface][i.clamp(0, 2)];

/// Category share bar: ours, then the top 3 named competitors, then everyone else.
class _CompetitorBar extends StatelessWidget {
  const _CompetitorBar({required this.cat, required this.ours});
  final CategoryContributionModel cat;
  final double ours;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final acc = M3StatusColors.of(context).accents;
    final named = cat.topCompetitors.take(3).toList();
    final namedSum = named.fold<double>(0, (a, c) => a + c.sharePct);
    final rest = (100.0 - ours - namedSum).clamp(0.0, 100.0);
    int f(double v) => (v * 10).round();
    final segs = <(double, Color)>[
      (ours, cs.primary),
      for (final (i, c) in named.indexed) (c.sharePct, _competitorShade(acc, i)),
      (rest, cs.surfaceContainerHighest),
    ].where((e) => f(e.$1) > 0).toList();
    return ClipRRect(
      borderRadius: M3Shape.radiusSm,
      child: SizedBox(
        height: 6.0,
        child: Row(children: [
          for (final e in segs) Expanded(flex: f(e.$1), child: ColoredBox(color: e.$2)),
        ]),
      ),
    );
  }
}

/// Donut whose stroke and percent grow with the tile, staying the compact
/// 64dp look when the tile is not stretched.
class _Donut extends StatelessWidget {
  const _Donut({super.key, required this.value, required this.label});
  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final acc = M3StatusColors.of(context).accents;
    return LayoutBuilder(builder: (context, c) {
      final s = c.biggest.shortestSide;
      final stroke = (s * 0.11).clamp(7.0, 14.0);
      final style = s >= 112
          ? theme.textTheme.titleLarge
          : s >= 88
              ? theme.textTheme.titleMedium
              : theme.textTheme.labelLarge;
      return Stack(alignment: Alignment.center, children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            year2023: false,
            value: value,
            strokeWidth: stroke,
            backgroundColor: acc.competitorSurface,
          ),
        ),
        Text(label, style: style?.copyWith(fontWeight: FontWeight.w800)),
      ]);
    });
  }
}

/// Side-by-side cards that share the height of the taller card.
class _EqualHeightRow extends MultiChildRenderObjectWidget {
  const _EqualHeightRow({
    required this.spacing,
    required this.textDirection,
    required super.children,
  });

  final double spacing;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualHeightRow(spacing: spacing, textDirection: textDirection);

  @override
  void updateRenderObject(BuildContext context, _RenderEqualHeightRow renderObject) {
    renderObject
      ..spacing = spacing
      ..textDirection = textDirection;
  }
}

/// Column whose last child absorbs any height beyond the children's natural size.
class _FillColumn extends MultiChildRenderObjectWidget {
  const _FillColumn({required this.textDirection, required super.children});

  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFillColumn(textDirection: textDirection);

  @override
  void updateRenderObject(BuildContext context, _RenderFillColumn renderObject) {
    renderObject.textDirection = textDirection;
  }
}

/// Vertical list that shares extra height across its children.
class _GrowingColumn extends MultiChildRenderObjectWidget {
  const _GrowingColumn({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGrowingColumn();
}

/// Category tile grid. Two columns from [twoColumnMinWidth], one below that.
class _GrowingGrid extends MultiChildRenderObjectWidget {
  const _GrowingGrid({
    required this.spacing,
    required this.twoColumnMinWidth,
    required this.textDirection,
    required super.children,
  });

  final double spacing;
  final double twoColumnMinWidth;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGrowingGrid(
        spacing: spacing,
        twoColumnMinWidth: twoColumnMinWidth,
        textDirection: textDirection,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderGrowingGrid renderObject) {
    renderObject
      ..spacing = spacing
      ..twoColumnMinWidth = twoColumnMinWidth
      ..textDirection = textDirection;
  }
}

/// One SKU share row. Extra height thickens the bar, then the padding.
class _SkuRow extends MultiChildRenderObjectWidget {
  _SkuRow({required Widget title, required Widget category, required Widget bar})
      : super(children: [title, category, bar]);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSkuRow();
}

/// Category tile: donut on the start side, copy beside it. Extra height
/// enlarges the donut (capped) and centers both in the tile.
class _ShareTile extends MultiChildRenderObjectWidget {
  _ShareTile({required Widget donut, required Widget details, required this.textDirection})
      : super(children: [donut, details]);

  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderShareTile(textDirection: textDirection);

  @override
  void updateRenderObject(BuildContext context, _RenderShareTile renderObject) {
    renderObject.textDirection = textDirection;
  }
}

class _OffsetParentData extends ContainerBoxParentData<RenderBox> {}

mixin _OffsetChildren on ContainerRenderObjectMixin<RenderBox, _OffsetParentData> {
  void setupOffsetParentData(RenderBox child) {
    if (child.parentData is! _OffsetParentData) {
      child.parentData = _OffsetParentData();
    }
  }

  List<RenderBox> offsetChildren() {
    final out = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      out.add(child);
      child = (child.parentData! as _OffsetParentData).nextSibling;
    }
    return out;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final pd = child.parentData! as _OffsetParentData;
      context.paintChild(child, offset + pd.offset);
      child = pd.nextSibling;
    }
  }

  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final current = child;
      final pd = current.parentData! as _OffsetParentData;
      final hit = result.addWithPaintOffset(
        offset: pd.offset,
        position: position,
        hitTest: (BoxHitTestResult result, Offset transformed) => current.hitTest(result, position: transformed),
      );
      if (hit) return true;
      child = pd.previousSibling;
    }
    return false;
  }
}

class _RenderEqualHeightRow extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _OffsetParentData>, _OffsetChildren {
  _RenderEqualHeightRow({required double spacing, required TextDirection textDirection})
      : _spacing = spacing,
        _textDirection = textDirection;

  double _spacing;
  double get spacing => _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) => setupOffsetParentData(child);

  double _childWidth(double width) {
    final n = childCount;
    if (n == 0) return 0;
    return math.max(0.0, (width - spacing * (n - 1)) / n);
  }

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final childW = _childWidth(width);
    var maxH = 0.0;
    for (final child in offsetChildren()) {
      maxH = math.max(maxH, child.getMaxIntrinsicHeight(childW));
    }
    return maxH;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final kids = offsetChildren();
    final childW = _childWidth(width);
    var maxH = 0.0;
    for (final child in kids) {
      maxH = math.max(maxH, child.getMaxIntrinsicHeight(childW));
    }
    final n = kids.length;
    for (var i = 0; i < n; i++) {
      final child = kids[i];
      child.layout(BoxConstraints.tightFor(width: childW, height: maxH), parentUsesSize: true);
      final slot = textDirection == TextDirection.rtl ? n - 1 - i : i;
      (child.parentData! as _OffsetParentData).offset = Offset(slot * (childW + spacing), 0);
    }
    size = constraints.constrain(Size(width.isFinite ? width : 0, maxH));
  }
}

class _RenderFillColumn extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _OffsetParentData>, _OffsetChildren {
  _RenderFillColumn({required TextDirection textDirection}) : _textDirection = textDirection;

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) => setupOffsetParentData(child);

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    var h = 0.0;
    for (final child in offsetChildren()) {
      h += child.getMaxIntrinsicHeight(width);
    }
    return h;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final kids = offsetChildren();
    if (kids.isEmpty) {
      size = constraints.constrain(Size(width, 0));
      return;
    }
    final flex = kids.last;
    var y = 0.0;
    for (final child in kids.sublist(0, kids.length - 1)) {
      child.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      final x = textDirection == TextDirection.rtl ? width - child.size.width : 0.0;
      (child.parentData! as _OffsetParentData).offset = Offset(x, y);
      y += child.size.height;
    }
    final flexNatural = flex.getMaxIntrinsicHeight(width);
    final flexH = constraints.hasBoundedHeight
        ? math.max(flexNatural, constraints.maxHeight - y)
        : flexNatural;
    flex.layout(BoxConstraints.tightFor(width: width, height: flexH), parentUsesSize: true);
    (flex.parentData! as _OffsetParentData).offset = Offset(0, y);
    size = constraints.constrain(Size(width, y + flex.size.height));
  }
}

class _RenderGrowingColumn extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _OffsetParentData>, _OffsetChildren {
  @override
  void setupParentData(RenderBox child) => setupOffsetParentData(child);

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    var h = 0.0;
    for (final child in offsetChildren()) {
      h += child.getMaxIntrinsicHeight(width);
    }
    return h;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final kids = offsetChildren();
    final naturals = [for (final child in kids) child.getMaxIntrinsicHeight(width)];
    final natural = naturals.fold<double>(0, (a, b) => a + b);
    final avail = constraints.hasBoundedHeight ? math.max(constraints.maxHeight, natural) : natural;
    final extra = kids.isEmpty ? 0.0 : (avail - natural) / kids.length;
    var y = 0.0;
    for (var i = 0; i < kids.length; i++) {
      final h = naturals[i] + extra;
      kids[i].layout(BoxConstraints.tightFor(width: width, height: h), parentUsesSize: true);
      (kids[i].parentData! as _OffsetParentData).offset = Offset(0, y);
      y += h;
    }
    size = constraints.constrain(Size(width, y));
  }
}

class _RenderGrowingGrid extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _OffsetParentData>, _OffsetChildren {
  _RenderGrowingGrid({
    required double spacing,
    required double twoColumnMinWidth,
    required TextDirection textDirection,
  })  : _spacing = spacing,
        _twoColumnMinWidth = twoColumnMinWidth,
        _textDirection = textDirection;

  double _spacing;
  double get spacing => _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  double _twoColumnMinWidth;
  double get twoColumnMinWidth => _twoColumnMinWidth;
  set twoColumnMinWidth(double value) {
    if (value == _twoColumnMinWidth) return;
    _twoColumnMinWidth = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) => setupOffsetParentData(child);

  int _columns(double width, int n) {
    if (n <= 1 || !width.isFinite || width < twoColumnMinWidth) return 1;
    return 2;
  }

  double _heightFor(double width, List<RenderBox> kids, int cols) {
    if (kids.isEmpty) return 0;
    final cellW = cols <= 1 ? width : (width - spacing * (cols - 1)) / cols;
    final rows = (kids.length + cols - 1) ~/ cols;
    final rowH = List<double>.filled(rows, 0);
    for (var i = 0; i < kids.length; i++) {
      final r = i ~/ cols;
      rowH[r] = math.max(rowH[r], kids[i].getMaxIntrinsicHeight(cellW));
    }
    return rowH.fold<double>(0, (a, b) => a + b) + spacing * (rows - 1);
  }

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final kids = offsetChildren();
    return _heightFor(width, kids, _columns(width, kids.length));
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final kids = offsetChildren();
    final cols = _columns(width, kids.length);
    final natural = _heightFor(width, kids, cols);
    final avail = constraints.hasBoundedHeight ? math.max(constraints.maxHeight, natural) : natural;
    if (kids.isEmpty) {
      size = constraints.constrain(Size(width, 0));
      return;
    }
    final cellW = cols <= 1 ? width : (width - spacing * (cols - 1)) / cols;
    final rows = (kids.length + cols - 1) ~/ cols;
    final rowH = List<double>.filled(rows, 0);
    for (var i = 0; i < kids.length; i++) {
      rowH[i ~/ cols] = math.max(rowH[i ~/ cols], kids[i].getMaxIntrinsicHeight(cellW));
    }
    final extra = (avail - natural) / rows;
    var y = 0.0;
    for (var r = 0; r < rows; r++) {
      final h = rowH[r] + extra;
      for (var c = 0; c < cols; c++) {
        final i = r * cols + c;
        if (i >= kids.length) break;
        kids[i].layout(BoxConstraints.tightFor(width: cellW, height: h), parentUsesSize: true);
        final x = textDirection == TextDirection.rtl
            ? width - (c + 1) * cellW - c * spacing
            : c * (cellW + spacing);
        (kids[i].parentData! as _OffsetParentData).offset = Offset(x, y);
      }
      y += h;
      if (r != rows - 1) y += spacing;
    }
    size = constraints.constrain(Size(width, y));
  }
}

class _RenderSkuRow extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _OffsetParentData>, _OffsetChildren {
  static const double _vPad = 6.0;
  static const double _gap = 4.0;
  static const double _barH = 18.0;
  static const double _barExtraMax = 18.0;

  @override
  void setupParentData(RenderBox child) => setupOffsetParentData(child);

  List<RenderBox>? _parts() {
    final kids = offsetChildren();
    if (kids.length != 3) return null;
    return kids;
  }

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final kids = _parts();
    if (kids == null) return 0;
    return _vPad * 2 +
        kids[0].getMaxIntrinsicHeight(width) +
        kids[1].getMaxIntrinsicHeight(width) +
        _gap +
        _barH;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final kids = _parts();
    if (kids == null) {
      size = constraints.constrain(Size(width, 0));
      return;
    }
    final loose = BoxConstraints(minWidth: width, maxWidth: width);
    kids[0].layout(loose, parentUsesSize: true);
    kids[1].layout(loose, parentUsesSize: true);
    final natural = _vPad * 2 + kids[0].size.height + kids[1].size.height + _gap + _barH;
    final used = constraints.hasBoundedHeight ? math.max(constraints.maxHeight, natural) : natural;
    final extra = math.max(0.0, used - natural);
    final barExtra = math.min(_barExtraMax, extra);
    final vPad = _vPad + (extra - barExtra) / 2;
    final barH = _barH + barExtra;
    kids[2].layout(BoxConstraints.tightFor(width: width, height: barH), parentUsesSize: true);
    var y = vPad;
    (kids[0].parentData! as _OffsetParentData).offset = Offset(0, y);
    y += kids[0].size.height;
    (kids[1].parentData! as _OffsetParentData).offset = Offset(0, y);
    y += kids[1].size.height + _gap;
    (kids[2].parentData! as _OffsetParentData).offset = Offset(0, y);
    size = constraints.constrain(Size(width, used));
  }
}

class _RenderShareTile extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _OffsetParentData>, _OffsetChildren {
  _RenderShareTile({required TextDirection textDirection}) : _textDirection = textDirection;

  static const double _minDonut = 64.0;
  static const double _maxDonut = 148.0;
  static const double _gap = 16.0;
  static const double _pad = 16.0;

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) => setupOffsetParentData(child);

  List<RenderBox>? _parts() {
    final kids = offsetChildren();
    if (kids.length != 2) return null;
    return kids;
  }

  double _textWidth(double width, double donut, double pad) =>
      math.max(0.0, width - pad * 2 - _gap - donut);

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final kids = _parts();
    if (kids == null) return 0;
    final textH = kids[1].getMaxIntrinsicHeight(_textWidth(width, _minDonut, _pad));
    return math.max(_minDonut, textH) + _pad * 2;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final kids = _parts();
    if (kids == null) {
      size = constraints.constrain(Size(width, 0));
      return;
    }
    final natural = getMaxIntrinsicHeight(width);
    final used = constraints.hasBoundedHeight ? math.max(constraints.maxHeight, natural) : natural;
    // Only the height added to match the sibling card enlarges the donut.
    // A tall competitor list keeps the compact 64dp ring.
    final extra = math.max(0.0, used - natural);
    final donut = (_minDonut + extra).clamp(_minDonut, _maxDonut);
    final textW = _textWidth(width, donut, _pad);
    kids[1].layout(BoxConstraints(minWidth: textW, maxWidth: textW), parentUsesSize: true);
    kids[0].layout(BoxConstraints.tightFor(width: donut, height: donut), parentUsesSize: true);
    final contentH = math.max(0.0, used - _pad * 2);
    final donutY = _pad + math.max(0.0, (contentH - donut) / 2);
    final textY = _pad + math.max(0.0, (contentH - kids[1].size.height) / 2);
    final rtl = textDirection == TextDirection.rtl;
    final donutX = rtl ? width - _pad - donut : _pad;
    final textX = rtl ? _pad : _pad + donut + _gap;
    (kids[0].parentData! as _OffsetParentData).offset = Offset(donutX, donutY);
    (kids[1].parentData! as _OffsetParentData).offset = Offset(textX, textY);
    size = constraints.constrain(Size(width, used));
  }
}

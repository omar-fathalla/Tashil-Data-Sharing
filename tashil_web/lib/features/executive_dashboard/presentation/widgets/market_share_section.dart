import 'package:flutter/material.dart';

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: sku),
                M3Spacing.gapMD,
                Expanded(child: cat),
              ],
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CardHeader(
              icon: AppIcons.analytics,
              title: 'Share per SKU',
              subtitle: 'Top SKUs: share of their category revenue vs competitors (100%)',
              count: rows.length,
              badgeKey: const ValueKey('share_per_sku_badge'),
            ),
            M3Spacing.gapSM,
            _Legend([
              (cs.primary, 'This SKU'),
              (cs.primaryContainer, 'Our other SKUs'),
              (acc.competitor, 'Competitors'),
            ]),
            M3Spacing.gapSM,
            if (rows.isEmpty)
              const _EmptyNote('No SKU-level category share data for this period.', keyName: 'share_per_sku_empty')
            else
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.sku.skuName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                      Text(r.sku.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      M3Spacing.gapXXS,
                      ClipRRect(
                        borderRadius: M3Shape.radiusSm,
                        child: SizedBox(
                          height: 18.0,
                          child: Row(children: [
                            _seg(context, r.self, cs.primary, cs.onPrimary),
                            _seg(context, r.ownOther, cs.primaryContainer, cs.onPrimaryContainer),
                            _seg(context, r.comp, acc.competitor, cs.onSurface),
                          ]),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CardHeader(
              icon: AppIcons.donutChart,
              title: 'Share per Category',
              subtitle: 'Our share of each category vs all other suppliers',
              count: top.length,
              badgeKey: const ValueKey('share_per_category_badge'),
            ),
            M3Spacing.gapSM,
            if (top.isEmpty)
              const _EmptyNote('No category market data for this period.', keyName: 'share_per_category_empty')
            else
              LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth >= 420 ? 2 : 1;
                final w = (c.maxWidth - (cols - 1) * 12.0) / cols;
                return Wrap(spacing: 12.0, runSpacing: 12.0, children: [
                  for (final cat in top) SizedBox(width: w, child: _CategoryTile(cat: cat)),
                ]);
              }),
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
      child: Padding(
        padding: M3Spacing.pSm,
        child: Row(children: [
          SizedBox(
            width: 64.0,
            height: 64.0,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  year2023: false,
                  value: ours / 100.0,
                  strokeWidth: 7.0,
                  backgroundColor: acc.competitorSurface,
                ),
              ),
              Text(_pct(ours), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            ]),
          ),
          M3Spacing.gapSM,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                    color: cat.tenantRank == 1 ? acc.tealBase : cs.onSurface,
                    fontWeight: FontWeight.w800,
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
    final header = Text('Sell In vs Sell Out',
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
              ? 'Could not load Sell In / Sell Out data.'
              : 'No months in this period have both Sell In and Sell Out data.',
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
      _KpiTile(label: 'Total Sell In (units)', value: _fmtInt(sellIn), color: cs.onSurface),
      _KpiTile(label: 'Total Sell Out (units)', value: _fmtInt(sellOut), color: cs.onSurface),
      _KpiTile(
          key: const ValueKey('kpi_net_accumulation'),
          label: 'Net accumulation (units)',
          value: '${net > 0 ? '+' : ''}${_fmtInt(net)}',
          color: acc.orangeBase),
      _KpiTile(
          key: const ValueKey('kpi_sell_through'),
          label: 'Sell-through',
          value: _pct(through),
          color: acc.tealBase),
    ];

    return Column(
      key: const ValueKey('sell_in_vs_out_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Text('Same SKUs, months with both Sell In and Sell Out: $monthLabel $year',
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
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: _StockTable(cpfr: cpfr!)),
            M3Spacing.gapMD,
            Expanded(flex: 2, child: _MonthlyBars(months: months)),
          ])
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
          Text('Stock per SKU', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text('Year to date, units; status from the CPFR stock report',
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          M3Spacing.gapSM,
          if (top.isEmpty)
            const _EmptyNote('No SKU stock data for this period.', keyName: 'stock_per_sku_empty')
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
                  for (final h in ['SKU', 'Sell In', 'Sell Out', 'Diff', 'Sell-through', 'Status'])
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
  const _MonthlyBars({required this.months});
  final List<ReconciliationMonthModel> months;
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
          Text('Sell In vs Sell Out per month (units)',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          M3Spacing.gapXS,
          _Legend([(cs.primary, 'Sell In'), (acc.tealBase, 'Sell Out')]),
          M3Spacing.gapMD,
          SizedBox(
            height: chartH + 20.0,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final m in months)
                Expanded(
                  child: Tooltip(
                    message: '${m.monthEn}: Sell In ${_fmtInt(m.sellInUnits)} · Sell Out ${_fmtInt(m.sellOutUnits)}',
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
          ),
        ]),
      ),
    );
  }

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

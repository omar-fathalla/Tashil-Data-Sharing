import 'package:flutter/material.dart';

import '../../../../core/data/result.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/theme/m3_status_colors.dart';
import '../../../../core/utils/bidi_text.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../data/target_breakdown_models.dart';
import '../../data/target_repository.dart';
import '../../domain/target_breakdown_export.dart';

const String _noSalesYet = 'لا توجد مبيعات بعد';

/// Opens the branch / SKU distribution of one Sell-Out target.
Future<void> showTargetBreakdownDialog(
  BuildContext context, {
  required TargetRepository repository,
  required TargetComparisonModel target,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16.0),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280.0, maxHeight: 820.0),
          child: TargetBreakdownView(repository: repository, target: target),
        ),
      ),
    ),
  );
}

/// Content of the breakdown dialog: back button, title, export, the baseline
/// caption, four summary cards and an expandable branch → SKU table.
class TargetBreakdownView extends StatefulWidget {
  const TargetBreakdownView({
    super.key,
    required this.repository,
    required this.target,
  });

  final TargetRepository repository;
  final TargetComparisonModel target;

  @override
  State<TargetBreakdownView> createState() => _TargetBreakdownViewState();
}

class _TargetBreakdownViewState extends State<TargetBreakdownView> {
  TargetBreakdownModel? _data;
  String? _error;
  bool _loading = true;
  final Set<String> _expanded = {};

  /// Relative column widths: name, share, target, target qty, cartons,
  /// actual, actual qty, achievement, gap.
  static const List<double> _flex = [2.6, 0.8, 1.35, 1.1, 0.9, 1.35, 1.1, 1.0, 1.35];
  static const double _minTableWidth = 1040.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await widget.repository.loadBreakdown(
      widget.target.id,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (res) {
        case Success<TargetBreakdownModel>(:final value):
          _data = value;
        case Failure<TargetBreakdownModel>():
          _error = 'تعذّر تحميل توزيع المستهدف. حاول مرة أخرى.';
      }
    });
  }

  void _export() {
    final m = _data;
    if (m == null) return;
    ExcelExportService.downloadCsv(
      targetBreakdownFileName(m),
      buildTargetBreakdownCsv(m),
    );
    M3Feedback.showSuccess(context, 'تم تصدير توزيع المستهدف');
  }

  String _egp(double v, TargetBreakdownModel m) =>
      CurrencyFormatter.formatEGP(v, showDecimals: m.showDecimals);

  String _signedEgp(double v, TargetBreakdownModel m) {
    final text = _egp(v.abs(), m);
    if (v > 0) return '\u2066+$text\u2069';
    if (v < 0) return '\u2066-$text\u2069';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = widget.target;
    final title = 'توزيع المستهدف • ${t.chainDisplayName} • ${t.monthLabel}';
    // The app locale is English, so a route opened with showDialog inherits
    // LTR. This dialog is Arabic: force RTL for the header, banner, KPI row
    // and table. Numeric strings keep an LTR paragraph so signs and «%» stay
    // on the correct side of the digits.
    return Directionality(
      key: const ValueKey('target_breakdown_direction'),
      textDirection: TextDirection.rtl,
      child: Column(
        key: const ValueKey('target_breakdown_dialog'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 16, 8),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('target_breakdown_back'),
                  tooltip: 'رجوع',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 4.0),
                Expanded(
                  child: Text(
                    title,
                    key: const ValueKey('target_breakdown_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('target_breakdown_export'),
                  onPressed: _data == null ? null : _export,
                  icon: const Icon(Icons.download_rounded, size: 18.0),
                  label: const Text('تصدير'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Flexible(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (_loading) {
      return const SizedBox(
        height: 260.0,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _data == null) {
      return SizedBox(
        height: 260.0,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: cs.error, size: 40.0),
              const SizedBox(height: 8.0),
              Text(_error ?? 'تعذّر تحميل توزيع المستهدف.'),
              const SizedBox(height: 12.0),
              FilledButton.tonal(
                key: const ValueKey('target_breakdown_retry'),
                onPressed: () => _load(forceRefresh: true),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    final m = _data!;
    final names = breakdownBranchDisplayNames(m);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCaption(context, m),
          M3Spacing.gapSM,
          _buildKpis(context, m),
          M3Spacing.gapMD,
          if (!m.hasBranches)
            _buildNoBaseline(context, m)
          else
            _buildTable(context, m, names),
          if (m.unattributedActualEgp > 0) ...[
            M3Spacing.gapSM,
            _note(
              context,
              'مبيعات فعلية بقيمة ${ltrIsolate(_egp(m.unattributedActualEgp, m))} غير منسوبة '
              'لفرع محدد، لذلك لا تظهر في صفوف الفروع.',
            ),
          ],
          if (m.hasBranches) ...[
            M3Spacing.gapSM,
            _note(
              context,
              'الكمية المستهدفة = القيمة المخصصة ÷ متوسط سعر الوحدة الصافي في فترة '
              'الأساس؛ «—» حيث لا يوجد سعر. الكراتين تظهر فقط حيث معامل الكرتونة معروف.',
            ),
          ],
          if (m.noHistory.isNotEmpty) ...[
            M3Spacing.gapMD,
            _buildNoHistory(context, m, names),
          ],
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildCaption(BuildContext context, TargetBreakdownModel m) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final caption = m.baseline.captionAr.isNotEmpty
        ? m.baseline.captionAr
        : 'لا توجد مبيعات سابقة لتوزيع المستهدف عليها';
    return Container(
      key: const ValueKey('target_breakdown_caption'),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withOpacity(0.5),
        borderRadius: M3Shape.radiusMd,
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18.0, color: cs.primary),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text(
              caption,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpis(BuildContext context, TargetBreakdownModel m) {
    final cs = Theme.of(context).colorScheme;
    final colors = M3StatusColors.of(context);
    final ach = m.achievementPct;
    final achColor = ach == null
        ? cs.onSurfaceVariant
        : ach >= 100
            ? colors.accents.positive
            : (ach >= 85 ? colors.accents.caution : cs.error);
    final noSales = !m.hasActuals;
    return LayoutBuilder(
      builder: (context, c) => M3EqualHeightGrid(
        columns: M3KpiGridColumns.forWidth(c.maxWidth),
        spacing: M3Spacing.sm,
        runSpacing: M3Spacing.sm,
        children: [
          M3SummaryKpiCard(
            key: const ValueKey('target_breakdown_kpi_target'),
            title: 'المستهدف',
            value: ltrIsolate(CurrencyFormatter.formatCompactEGP(m.targetRevenueEgp)),
            subtitle: ltrIsolate(_egp(m.targetRevenueEgp, m)),
            icon: Icons.flag_circle_rounded,
            color: cs.primary,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('target_breakdown_kpi_actual'),
            title: 'المحقق',
            value: noSales
                ? '—'
                : ltrIsolate(CurrencyFormatter.formatCompactEGP(m.actualRevenueEgp)),
            subtitle: noSales ? _noSalesYet : ltrIsolate(_egp(m.actualRevenueEgp, m)),
            icon: Icons.insights_rounded,
            color: colors.accents.teal,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('target_breakdown_kpi_achievement'),
            title: 'نسبة التحقيق',
            value: noSales || ach == null ? '—' : ltrIsolate('${ach.toStringAsFixed(1)}%'),
            subtitle: noSales ? _noSalesYet : 'من المستهدف',
            icon: Icons.pie_chart_rounded,
            color: achColor,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('target_breakdown_kpi_gap'),
            title: 'الفرق',
            value: noSales
                ? '—'
                : ltrIsolate(CurrencyFormatter.formatCompactEGP(m.gapEgp)),
            subtitle: noSales
                ? _noSalesYet
                : (m.gapEgp >= 0 ? 'فوق المستهدف' : 'المتبقي للمستهدف'),
            icon: Icons.account_tree_rounded,
            color: noSales
                ? cs.onSurfaceVariant
                : (m.gapEgp >= 0 ? colors.accents.positive : colors.accents.indigo),
          ),
        ],
      ),
    );
  }

  Widget _buildNoBaseline(BuildContext context, TargetBreakdownModel m) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: const ValueKey('target_breakdown_no_baseline'),
      padding: const EdgeInsets.all(28.0),
      decoration: BoxDecoration(
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.account_tree_rounded, size: 40.0, color: cs.primary),
          const SizedBox(height: 10.0),
          Text(
            'لا توجد مبيعات سابقة لهذه السلسلة لتوزيع المستهدف عليها',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6.0),
          Text(
            'ارفع ملف Sell-Out للسلسلة ليظهر توزيع المستهدف على الفروع والأصناف.',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTable(
    BuildContext context,
    TargetBreakdownModel m,
    Map<String, String> names,
  ) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth < _minTableWidth ? _minTableWidth : c.maxWidth;
        final table = SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _headerRow(context),
              for (final b in m.branches) ...[
                _branchRow(context, m, b, names[b.branchName] ?? b.branchName),
                if (_expanded.contains(b.branchKey))
                  for (final s in b.skus) _skuRow(context, m, b, s),
              ],
              _totalRow(context, m),
            ],
          ),
        );
        return Container(
          decoration: BoxDecoration(
            borderRadius: M3Shape.radiusLg,
            border: Border.all(color: cs.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: c.maxWidth < _minTableWidth
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: table,
                )
              : table,
        );
      },
    );
  }

  Widget _cell(BuildContext context, int i, Widget child) {
    return Expanded(
      flex: (_flex[i] * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0),
        child: Align(alignment: Alignment.center, child: child),
      ),
    );
  }

  Widget _text(
    BuildContext context,
    String text, {
    FontWeight? weight,
    Color? color,
    bool dim = false,
    TextDirection? textDirection,
  }) {
    final theme = Theme.of(context);
    return Text(
      text,
      textDirection: textDirection,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: weight,
        color: dim ? theme.colorScheme.onSurfaceVariant : color,
      ),
    );
  }

  /// A figure (money, qty, %, gap). LTR so a leading sign and a trailing
  /// «%» / «ج.م» stay beside the digits inside the RTL table.
  Widget _figure(
    BuildContext context,
    String text, {
    FontWeight? weight,
    Color? color,
    bool dim = false,
  }) =>
      _text(
        context,
        text,
        weight: weight,
        color: color,
        dim: dim,
        textDirection: TextDirection.ltr,
      );

  Widget _headerRow(BuildContext context) {
    final theme = Theme.of(context);
    const heads = [
      'الفرع / الصنف',
      'الحصة %',
      'المستهدف (ج.م)',
      'الكمية المستهدفة',
      'كراتين',
      'المحقق (ج.م)',
      'الكمية المحققة',
      'التحقيق %',
      'الفرق (ج.م)',
    ];
    return Container(
      key: const ValueKey('target_breakdown_header'),
      height: 48.0,
      color: theme.colorScheme.surfaceContainerHigh.withOpacity(0.5),
      child: Row(
        children: [
          for (var i = 0; i < heads.length; i++)
            _cell(
              context,
              i,
              Text(
                heads[i],
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }

  String _units(int? v) => v == null ? '—' : CurrencyFormatter.formatNumber(v);
  String _cartons(double? v) => v == null ? '—' : v.toStringAsFixed(1);
  String _pct(double v) => '${v.toStringAsFixed(1)}%';

  Color _achColor(BuildContext context, double? ach) {
    final cs = Theme.of(context).colorScheme;
    if (ach == null) return cs.onSurfaceVariant;
    final colors = M3StatusColors.of(context);
    return ach >= 100
        ? colors.accents.positive
        : (ach >= 85 ? colors.accents.caution : cs.error);
  }

  List<Widget> _valueCells(
    BuildContext context,
    TargetBreakdownModel m, {
    required double share,
    required double target,
    required int? units,
    required double? cartons,
    required double actual,
    required int actualUnits,
    required double? ach,
    required double gap,
    FontWeight? weight,
  }) {
    final noSales = !m.hasActuals;
    return [
      _cell(context, 1, _figure(context, _pct(share), weight: weight)),
      _cell(context, 2, _figure(context, _egp(target, m), weight: FontWeight.w800)),
      _cell(context, 3, _figure(context, _units(units), weight: weight, dim: units == null)),
      _cell(context, 4, _figure(context, _cartons(cartons), weight: weight, dim: cartons == null)),
      _cell(
        context,
        5,
        _figure(
          context,
          noSales ? '—' : _egp(actual, m),
          weight: weight,
          dim: noSales,
        ),
      ),
      _cell(
        context,
        6,
        _figure(
          context,
          noSales ? '—' : CurrencyFormatter.formatNumber(actualUnits),
          weight: weight,
          dim: noSales,
        ),
      ),
      _cell(
        context,
        7,
        _figure(
          context,
          noSales || ach == null ? '—' : _pct(ach),
          weight: FontWeight.w800,
          color: _achColor(context, noSales ? null : ach),
          dim: noSales || ach == null,
        ),
      ),
      _cell(
        context,
        8,
        _figure(
          context,
          noSales ? '—' : _signedEgp(gap, m),
          weight: weight,
          color: noSales
              ? null
              : (gap >= 0
                  ? M3StatusColors.of(context).accents.positive
                  : Theme.of(context).colorScheme.error),
          dim: noSales,
        ),
      ),
    ];
  }

  Widget _branchRow(
    BuildContext context,
    TargetBreakdownModel m,
    TargetBreakdownBranchModel b,
    String name,
  ) {
    final cs = Theme.of(context).colorScheme;
    final expanded = _expanded.contains(b.branchKey);
    return InkWell(
      key: ValueKey('target_breakdown_row_${b.branchKey}'),
      onTap: b.skus.isEmpty
          ? null
          : () => setState(() {
                if (!expanded) {
                  _expanded.add(b.branchKey);
                } else {
                  _expanded.remove(b.branchKey);
                }
              }),
      child: Container(
        height: 52.0,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.6))),
        ),
        child: Row(
          children: [
            _cell(
              context,
              0,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20.0,
                    color: b.skus.isEmpty ? cs.outlineVariant : cs.primary,
                  ),
                  const SizedBox(width: 4.0),
                  Flexible(
                    child: Tooltip(
                      message: b.branchName,
                      child: _text(context, name, weight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            ..._valueCells(
              context,
              m,
              share: b.sharePct,
              target: b.allocatedTargetEgp,
              units: b.allocatedUnits,
              cartons: b.allocatedCartons,
              actual: b.actualRevenueEgp,
              actualUnits: b.actualUnits,
              ach: b.achievementPct,
              gap: b.gapEgp,
              weight: FontWeight.w700,
            ),
          ],
        ),
      ),
    );
  }

  Widget _skuRow(
    BuildContext context,
    TargetBreakdownModel m,
    TargetBreakdownBranchModel b,
    TargetBreakdownSkuModel s,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('target_breakdown_sku_${b.branchKey}_${s.skuKey}'),
      height: 48.0,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
      ),
      child: Row(
        children: [
          _cell(
            context,
            0,
            Tooltip(
              message: s.skuName,
              child: _text(context, s.skuName, dim: false),
            ),
          ),
          ..._valueCells(
            context,
            m,
            share: s.sharePct,
            target: s.allocatedTargetEgp,
            units: s.allocatedUnits,
            cartons: s.allocatedCartons,
            actual: s.actualRevenueEgp,
            actualUnits: s.actualUnits,
            ach: s.achievementPct,
            gap: s.gapEgp,
          ),
        ],
      ),
    );
  }

  Widget _totalRow(BuildContext context, TargetBreakdownModel m) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('target_breakdown_total_row'),
      height: 52.0,
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.35),
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          _cell(context, 0, _text(context, 'الإجمالي', weight: FontWeight.w800)),
          ..._valueCells(
            context,
            m,
            share: 100,
            target: m.targetRevenueEgp,
            units: m.allocatedUnitsTotal,
            cartons: m.allocatedCartonsTotal,
            actual: m.actualRevenueEgp,
            actualUnits: m.actualUnits,
            ach: m.achievementPct,
            gap: m.gapEgp,
            weight: FontWeight.w800,
          ),
        ],
      ),
    );
  }

  Widget _buildNoHistory(
    BuildContext context,
    TargetBreakdownModel m,
    Map<String, String> names,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('target_breakdown_no_history'),
          title: Text(
            'بدون مبيعات سابقة (${m.noHistory.length})',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'لا تُخصَّص لها قيمة مستهدفة لأنه لا توجد لها مبيعات في فترة الأساس.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          children: [
            for (final n in m.noHistory)
              ListTile(
                dense: true,
                title: Text(
                  n.isBranch
                      ? (names[n.branchName] ?? n.branchName)
                      : '${names[n.branchName] ?? n.branchName} • ${n.skuName}',
                ),
                trailing: Text(
                  !m.hasActuals
                      ? '—'
                      : '${ltrIsolate(_egp(n.actualRevenueEgp, m))} • '
                          '${ltrIsolate(CurrencyFormatter.formatNumber(n.actualUnits))} وحدة',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/data/result.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/testing/test_semantics.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/theme/m3_status_colors.dart';
import '../../../../core/utils/bidi_text.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/shared_display_prefix.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_segmented_button_group.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../../../core/widgets/m3_table_surface.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../data/target_breakdown_models.dart';
import '../../data/target_repository.dart';
import '../../domain/target_achievement_status.dart';
import '../../domain/target_monthly_series.dart';
import 'target_status_pill.dart';

enum TargetDetailTab { monthly, branches, skus }

enum TargetMetricMode { value, units }

/// Full-page Sell-Out target detail (option B): replaces the explorer tab bar
/// while the app sidebar stays. Not a modal overlay.
class TargetDetailPage extends StatefulWidget {
  const TargetDetailPage({
    super.key,
    required this.repository,
    required this.target,
    this.siblings = const [],
    required this.onBack,
    this.initialTab = TargetDetailTab.monthly,
    this.initialMonth = 0,
  });

  final TargetRepository repository;
  final TargetComparisonModel target;
  final List<TargetComparisonModel> siblings;
  final VoidCallback onBack;
  final TargetDetailTab initialTab;
  final int initialMonth;

  @override
  State<TargetDetailPage> createState() => _TargetDetailPageState();
}

class _TargetDetailPageState extends State<TargetDetailPage> {
  late TargetDetailTab _tab;
  late int _monthFilter; // 0 = all months
  bool _monthLocked = false;
  String? _selectedBranchKey;
  TargetMetricMode _metric = TargetMetricMode.value;

  TargetBreakdownModel? _data;
  String? _error;
  bool _loading = true;
  String? _breakdownTargetId;

  late TargetMonthlySeries _series;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _monthFilter = widget.initialMonth;
    _monthLocked = widget.initialMonth > 0;
    _series = TargetMonthlySeries.build(
      target: widget.target,
      siblings: widget.siblings,
    );
    _loadBreakdown();
  }

  TargetComparisonModel get _effectiveTarget {
    if (_monthFilter >= 1 && _monthFilter <= 12) {
      for (final s in widget.siblings) {
        if (s.retailerChain == widget.target.retailerChain &&
            s.year == widget.target.year &&
            s.month == _monthFilter &&
            s.branchName == widget.target.branchName &&
            s.category == widget.target.category) {
          return s;
        }
      }
    }
    return widget.target;
  }

  Future<void> _loadBreakdown({bool forceRefresh = false}) async {
    final id = _effectiveTarget.id;
    setState(() {
      _loading = true;
      _error = null;
      _breakdownTargetId = id;
    });
    final res = await widget.repository.loadBreakdown(
      id,
      forceRefresh: forceRefresh,
    );
    if (!mounted || _breakdownTargetId != id) return;
    setState(() {
      _loading = false;
      switch (res) {
        case Success<TargetBreakdownModel>(:final value):
          final branches = [...value.branches]
            ..sort((a, b) {
              final aa = a.achievementPct ?? -1;
              final bb = b.achievementPct ?? -1;
              return aa.compareTo(bb);
            });
          _data = TargetBreakdownModel(
            targetId: value.targetId,
            retailerChain: value.retailerChain,
            chainDisplayName: value.chainDisplayName,
            year: value.year,
            month: value.month,
            monthLabel: value.monthLabel,
            branchScope: value.branchScope,
            categoryScope: value.categoryScope,
            targetRevenueEgp: value.targetRevenueEgp,
            targetUnits: value.targetUnits,
            baseline: value.baseline,
            hasActuals: value.hasActuals,
            actualRevenueEgp: value.actualRevenueEgp,
            actualUnits: value.actualUnits,
            achievementPct: value.achievementPct,
            gapEgp: value.gapEgp,
            allocatedUnitsTotal: value.allocatedUnitsTotal,
            allocatedCartonsTotal: value.allocatedCartonsTotal,
            unattributedActualEgp: value.unattributedActualEgp,
            noHistoryActualEgp: value.noHistoryActualEgp,
            allocationGranularityEgp: value.allocationGranularityEgp,
            branches: branches,
            noHistory: value.noHistory,
            source: value.source,
          );
          if (_selectedBranchKey == null && branches.isNotEmpty) {
            _selectedBranchKey = branches.first.branchKey;
          }
        case Failure<TargetBreakdownModel>():
          _error = 'تعذّر تحميل توزيع المستهدف. حاول مرة أخرى.';
      }
    });
  }

  Map<String, String> get _branchDisplay {
    final names = <String>{};
    for (final b in _data?.branches ?? const <TargetBreakdownBranchModel>[]) {
      if (b.branchName.trim().isNotEmpty) names.add(b.branchName);
    }
    return displayNamesWithoutSharedPrefix(names);
  }

  String _displayBranch(String raw) => _branchDisplay[raw] ?? raw;

  void _selectMonth(int month) {
    setState(() {
      _monthFilter = month;
      _monthLocked = true;
      _tab = TargetDetailTab.branches;
      _selectedBranchKey = null;
    });
    _loadBreakdown();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = widget.target;
    final title = '${t.chainDisplayName} · ${t.monthLabel}';

    // Bounded height so this page works inside the explorer's
    // SingleChildScrollView (Expanded would be unbounded there).
    final bodyHeight = (MediaQuery.sizeOf(context).height - 320).clamp(420.0, 900.0);

    return Directionality(
      key: const ValueKey('target_detail_page'),
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, title),
          M3Spacing.gapSM,
          _buildKpis(context),
          M3Spacing.gapSM,
          _buildFilters(context),
          M3Spacing.gapSM,
          SizedBox(height: bodyHeight, child: _buildBody(context, cs)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        TestSemantics.button(
          identifier: TestIds.selloutTargetDetailBack,
          label: 'رجوع',
          onPressed: widget.onBack,
          child: TextButton.icon(
            key: const ValueKey('target_detail_back'),
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('رجوع'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Text(
                'المستهدفات',
                key: const ValueKey('target_detail_crumb_root'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(Icons.chevron_left_rounded,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              Text(
                title,
                key: const ValueKey('target_detail_crumb_current'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKpis(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accents = M3StatusColors.of(context).accents;
    final yearly = widget.target.targetRevenueEgp;
    final actual = _series.hasActualsToDate
        ? _series.actualToDateRevenue
        : (widget.target.hasActuals ? widget.target.actualRevenueEgp : null);
    final ttd = _series.targetToDateRevenue > 0
        ? _series.targetToDateRevenue
        : yearly;
    final ach = _series.achievementToDatePct ??
        (widget.target.hasActuals && ttd > 0
            ? round1((actual ?? 0) / ttd * 100)
            : null);
    final status = TargetAchievementStatus.fromPct(
      ach,
      hasActuals: actual != null,
    );
    final gap = actual == null ? null : actual - ttd;

    return LayoutBuilder(
      builder: (context, c) => M3EqualHeightGrid(
        key: const ValueKey('target_detail_kpi_grid'),
        columns: M3KpiGridColumns.forWidth(c.maxWidth),
        spacing: M3Spacing.sm,
        runSpacing: M3Spacing.sm,
        children: [
          M3SummaryKpiCard(
            key: const ValueKey('target_detail_kpi_year'),
            title: 'مستهدف السنة',
            value: ltrIsolate(CurrencyFormatter.formatCompactEGP(yearly)),
            subtitle: 'حتى تاريخه: ${ltrIsolate(CurrencyFormatter.formatCompactEGP(ttd))}',
            icon: Icons.flag_circle_rounded,
            color: cs.primary,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('target_detail_kpi_actual'),
            title: 'المحقق',
            value: actual == null
                ? '—'
                : ltrIsolate(CurrencyFormatter.formatCompactEGP(actual)),
            subtitle: actual == null ? 'لا توجد مبيعات بعد' : 'حتى تاريخه',
            icon: Icons.insights_rounded,
            color: accents.teal,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('target_detail_kpi_achievement'),
            title: 'نسبة التحقيق',
            value: ach == null ? '—' : ltrIsolate('${ach.toStringAsFixed(1)}%'),
            subtitle: status.labelAr,
            icon: Icons.pie_chart_rounded,
            color: status.kind == TargetAchievementKind.achieved
                ? accents.positive
                : status.kind == TargetAchievementKind.near
                    ? accents.caution
                    : status.kind == TargetAchievementKind.below
                        ? cs.error
                        : cs.onSurfaceVariant,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('target_detail_kpi_gap'),
            title: 'الفرق',
            value: gap == null
                ? '—'
                : ltrIsolate(CurrencyFormatter.formatCompactEGP(gap)),
            subtitle: gap == null
                ? 'لا توجد مبيعات بعد'
                : (gap >= 0 ? 'فوق مستهدف حتى تاريخه' : 'المتبقي حتى تاريخه'),
            icon: Icons.account_tree_rounded,
            color: gap == null
                ? cs.onSurfaceVariant
                : (gap >= 0 ? accents.positive : accents.indigo),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final monthOptions = <DropdownMenuItem<int>>[
      const DropdownMenuItem(value: 0, child: Text('كل الشهور')),
      for (var m = 1; m <= 12; m++)
        DropdownMenuItem(value: m, child: Text(monthLabelsAr[m - 1])),
    ];
    final branchOptions = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('كل الفروع')),
      for (final b in _data?.branches ?? const <TargetBreakdownBranchModel>[])
        DropdownMenuItem(
          value: b.branchKey,
          child: Text(_displayBranch(b.branchName), overflow: TextOverflow.ellipsis),
        ),
    ];

    return Wrap(
      spacing: M3Spacing.sm,
      runSpacing: M3Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        M3SegmentedButtonGroup<TargetDetailTab>(
          key: const ValueKey('target_detail_tabs'),
          selectedValue: _tab,
          onSelectionChanged: (v) => setState(() => _tab = v),
          segments: const [
            M3SegmentItem(value: TargetDetailTab.monthly, label: 'شهري'),
            M3SegmentItem(value: TargetDetailTab.branches, label: 'الفروع'),
            M3SegmentItem(value: TargetDetailTab.skus, label: 'الأصناف'),
          ],
        ),
        M3Dropdown<int>(
          key: const ValueKey('target_detail_month_filter'),
          width: 160,
          fitOptions: true,
          enabled: !_monthLocked,
          value: _monthFilter,
          label: 'الشهر',
          options: m3OptionsFromMenuItems(monthOptions),
          onChanged: m3Legacy<int>((v) {
            if (v == null || _monthLocked) return;
            setState(() {
              _monthFilter = v;
              _selectedBranchKey = null;
            });
            _loadBreakdown();
          }),
        ),
        if (_monthLocked)
          TextButton(
            key: const ValueKey('target_detail_unlock_month'),
            onPressed: () {
              setState(() {
                _monthLocked = false;
                _monthFilter = 0;
              });
              _loadBreakdown();
            },
            child: const Text('إلغاء قفل الشهر'),
          ),
        M3Dropdown<String>(
          key: const ValueKey('target_detail_branch_filter'),
          width: 220,
          fitOptions: true,
          value: (_selectedBranchKey != null &&
                  branchOptions.any((o) => o.value == _selectedBranchKey))
              ? _selectedBranchKey!
              : '',
          label: 'الفرع',
          options: m3OptionsFromMenuItems(branchOptions),
          onChanged: m3Legacy<String>((v) {
            setState(() => _selectedBranchKey = (v == null || v.isEmpty) ? null : v);
          }),
        ),
        M3SegmentedButtonGroup<TargetMetricMode>(
          key: const ValueKey('target_detail_metric_mode'),
          selectedValue: _metric,
          onSelectionChanged: (v) => setState(() => _metric = v),
          segments: const [
            M3SegmentItem(value: TargetMetricMode.value, label: 'قيمة'),
            M3SegmentItem(value: TargetMetricMode.units, label: 'وحدات'),
          ],
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme cs) {
    if (_tab == TargetDetailTab.monthly) {
      return _buildMonthlyTab(context);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('target_detail_retry'),
              onPressed: () => _loadBreakdown(forceRefresh: true),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_tab == TargetDetailTab.branches) {
      return _buildBranchesTab(context);
    }
    return _buildSkusTab(context);
  }

  Widget _buildMonthlyTab(BuildContext context) {
    return ListView(
      key: const ValueKey('target_detail_monthly_tab'),
      children: [
        _CumulativeChart(
          key: const ValueKey('target_detail_cumulative_chart'),
          points: _series.cumulative,
        ),
        M3Spacing.gapMD,
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1100
                ? 4
                : c.maxWidth >= 800
                    ? 3
                    : 2;
            return Wrap(
              spacing: M3Spacing.sm,
              runSpacing: M3Spacing.sm,
              children: [
                for (final m in _series.months)
                  SizedBox(
                    width: (c.maxWidth - (cols - 1) * M3Spacing.sm) / cols,
                    child: _MonthCard(
                      key: ValueKey('target_detail_month_card_${m.month}'),
                      point: m,
                      metric: _metric,
                      onTap: () => _selectMonth(m.month),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildBranchesTab(BuildContext context) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final branches = data.branches;
    TargetBreakdownBranchModel? selected;
    for (final b in branches) {
      if (b.branchKey == _selectedBranchKey) {
        selected = b;
        break;
      }
    }
    selected ??= branches.isEmpty ? null : branches.first;

    return Row(
      key: const ValueKey('target_detail_branches_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              color: M3TableSurface.color(Theme.of(context).colorScheme),
              borderRadius: M3Shape.radiusLg,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: ListView.separated(
              itemCount: branches.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final b = branches[i];
                final selectedRow = b.branchKey == selected?.branchKey;
                final ach = b.achievementPct;
                final status = TargetAchievementStatus.fromPct(
                  ach,
                  hasActuals: data.hasActuals && ach != null,
                );
                return ListTile(
                  key: ValueKey('target_detail_branch_row_${b.branchKey}'),
                  selected: selectedRow,
                  onTap: () => setState(() => _selectedBranchKey = b.branchKey),
                  title: Text(
                    _displayBranch(b.branchName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _metric == TargetMetricMode.value
                        ? '${ltrIsolate(CurrencyFormatter.formatCompactEGP(b.allocatedTargetEgp))} → ${ltrIsolate(CurrencyFormatter.formatCompactEGP(b.actualRevenueEgp))}'
                        : '${b.allocatedUnits ?? '—'} → ${b.actualUnits}',
                  ),
                  trailing: TargetStatusPill(status: status, compact: true),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: M3Spacing.sm),
        Expanded(
          flex: 6,
          child: Container(
            key: const ValueKey('target_detail_branch_skus_panel'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: M3TableSurface.color(Theme.of(context).colorScheme),
              borderRadius: M3Shape.radiusLg,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: selected == null
                ? const Center(child: Text('اختر فرعاً لعرض أصنافه'))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'أصناف · ${_displayBranch(selected.branchName)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      M3Spacing.gapSM,
                      Expanded(child: _SkuTable(skus: selected.skus, metric: _metric)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkusTab(BuildContext context) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final skus = <TargetBreakdownSkuModel>[];
    for (final b in data.branches) {
      if (_selectedBranchKey != null &&
          _selectedBranchKey!.isNotEmpty &&
          b.branchKey != _selectedBranchKey) {
        continue;
      }
      skus.addAll(b.skus);
    }
    return Container(
      key: const ValueKey('target_detail_skus_tab'),
      decoration: BoxDecoration(
        color: M3TableSurface.color(Theme.of(context).colorScheme),
        borderRadius: M3Shape.radiusLg,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: _SkuTable(skus: skus, metric: _metric),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({
    super.key,
    required this.point,
    required this.metric,
    required this.onTap,
  });

  final TargetMonthPoint point;
  final TargetMetricMode metric;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetText = metric == TargetMetricMode.value
        ? ltrIsolate(CurrencyFormatter.formatCompactEGP(point.targetRevenue))
        : CurrencyFormatter.formatNumber(point.targetUnits.round());
    final actualText = !point.hasActuals
        ? '—'
        : metric == TargetMetricMode.value
            ? ltrIsolate(CurrencyFormatter.formatCompactEGP(point.actualRevenue))
            : CurrencyFormatter.formatNumber(point.actualUnits.round());
    final gapText = !point.hasActuals
        ? '—'
        : metric == TargetMetricMode.value
            ? ltrIsolate(CurrencyFormatter.formatCompactEGP(point.gapRevenue))
            : CurrencyFormatter.formatNumber(
                (point.actualUnits - point.targetUnits).round());

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: M3Shape.radiusMd,
      child: InkWell(
        borderRadius: M3Shape.radiusMd,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: M3Shape.radiusMd,
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      point.labelAr,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TargetStatusPill(status: point.status, compact: true),
                ],
              ),
              const SizedBox(height: 8),
              _kv(context, 'المستهدف', targetText),
              _kv(context, 'المحقق', actualText),
              _kv(
                context,
                'نسبة التحقيق',
                point.achievementPct == null
                    ? '—'
                    : '${point.achievementPct!.toStringAsFixed(1)}%',
              ),
              _kv(context, 'الفرق', gapText),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final body = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(child: Text(k, style: body)),
          Text(v, style: body?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CumulativeChart extends StatelessWidget {
  const _CumulativeChart({super.key, required this.points});

  final List<TargetCumulativePoint> points;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accents = M3StatusColors.of(context).accents;
    var maxY = 1.0;
    for (final p in points) {
      if (p.cumulativeTarget > maxY) maxY = p.cumulativeTarget;
      if (p.cumulativeActual > maxY) maxY = p.cumulativeActual;
    }

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      decoration: BoxDecoration(
        color: M3TableSurface.color(cs),
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'تراكمي: المستهدف مقابل المحقق',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: CustomPaint(
              painter: _CumulativePainter(
                points: points,
                maxY: maxY,
                targetColor: cs.primary,
                actualColor: accents.teal,
                gridColor: cs.outlineVariant.withOpacity(0.4),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _legend(context, cs.primary, 'المستهدف'),
              const SizedBox(width: 12),
              _legend(context, accents.teal, 'المحقق'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 3, color: c),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _CumulativePainter extends CustomPainter {
  _CumulativePainter({
    required this.points,
    required this.maxY,
    required this.targetColor,
    required this.actualColor,
    required this.gridColor,
  });

  final List<TargetCumulativePoint> points;
  final double maxY;
  final Color targetColor;
  final Color actualColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;
    const padL = 8.0;
    const padR = 8.0;
    const padT = 8.0;
    const padB = 18.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = padT + h * i / 4;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), grid);
    }

    Offset pt(int i, double v) {
      final x = padL + (points.length == 1 ? w / 2 : w * i / (points.length - 1));
      final y = padT + h * (1 - (v / maxY).clamp(0.0, 1.0));
      return Offset(x, y);
    }

    Path pathFor(double Function(TargetCumulativePoint) pick) {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final o = pt(i, pick(points[i]));
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      return path;
    }

    final targetPaint = Paint()
      ..color = targetColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    final actualPaint = Paint()
      ..color = actualColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(pathFor((p) => p.cumulativeTarget), targetPaint);
    canvas.drawPath(pathFor((p) => p.hasActuals ? p.cumulativeActual : 0), actualPaint);
  }

  @override
  bool shouldRepaint(covariant _CumulativePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.maxY != maxY;
}

class _SkuTable extends StatelessWidget {
  const _SkuTable({required this.skus, required this.metric});

  final List<TargetBreakdownSkuModel> skus;
  final TargetMetricMode metric;

  @override
  Widget build(BuildContext context) {
    return TableScrollContainer(
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 56,
        columns: const [
          DataColumn(label: Text('الصنف')),
          DataColumn(label: Text('المستهدف')),
          DataColumn(label: Text('المحقق')),
          DataColumn(label: Text('نسبة التحقيق')),
          DataColumn(label: Text('الفرق')),
        ],
        rows: [
          for (final s in skus)
            DataRow(
              key: ValueKey('target_detail_sku_${s.skuKey}'),
              cells: [
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        s.skuName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        ltrIsolate(s.skuKey),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                DataCell(Text(
                  metric == TargetMetricMode.value
                      ? ltrIsolate(CurrencyFormatter.formatCompactEGP(s.allocatedTargetEgp))
                      : '${s.allocatedUnits ?? '—'}',
                )),
                DataCell(Text(
                  metric == TargetMetricMode.value
                      ? ltrIsolate(CurrencyFormatter.formatCompactEGP(s.actualRevenueEgp))
                      : '${s.actualUnits}',
                )),
                DataCell(Text(
                  s.achievementPct == null
                      ? '—'
                      : '${s.achievementPct!.toStringAsFixed(1)}%',
                )),
                DataCell(Text(
                  ltrIsolate(CurrencyFormatter.formatCompactEGP(s.gapEgp)),
                )),
              ],
            ),
        ],
      ),
    );
  }
}

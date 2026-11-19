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
  /// Live branch filter for Monthly / KPIs / chart / Items (`null` = كل الفروع).
  String? _filterBranchKey;
  /// Which branch row is focused in the Branches tab SKU panel.
  String? _focusedBranchKey;
  TargetMetricMode _metric = TargetMetricMode.value;

  TargetBreakdownModel? _data;
  /// Full chain branch list for the filter dropdown (kept when a branch is selected).
  List<TargetBreakdownBranchModel> _allBranches = const [];
  String? _error;
  bool _loading = true;
  int _loadSeq = 0;

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

  /// Annual target id stays the source of truth; month/branch are query filters.
  String get _breakdownTargetId => widget.target.id;

  bool get _filtersActive =>
      (_filterBranchKey != null && _filterBranchKey!.isNotEmpty) ||
      (_monthFilter >= 1 && _monthFilter <= 12);

  Future<void> _loadBreakdown({bool forceRefresh = false}) async {
    final seq = ++_loadSeq;
    final id = _breakdownTargetId;
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await widget.repository.loadBreakdown(
      id,
      branch: _filterBranchKey,
      month: _monthFilter >= 1 && _monthFilter <= 12 ? _monthFilter : null,
      forceRefresh: forceRefresh,
    );
    if (!mounted || seq != _loadSeq) return;
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
            monthlyPhasing: value.monthlyPhasing,
            appliedBranch: value.appliedBranch,
            appliedMonth: value.appliedMonth,
          );
          if (_filterBranchKey == null || _filterBranchKey!.isEmpty) {
            _allBranches = branches;
          }
          if (value.monthlyPhasing.isNotEmpty) {
            _series = TargetMonthlySeries.build(
              target: widget.target,
              siblings: widget.siblings,
              phasingOverride: value.monthlyPhasing,
            );
          } else {
            _series = TargetMonthlySeries.build(
              target: widget.target,
              siblings: widget.siblings,
            );
          }
          if (_focusedBranchKey == null ||
              !branches.any((b) => b.branchKey == _focusedBranchKey)) {
            _focusedBranchKey =
                branches.isEmpty ? null : branches.first.branchKey;
          }
        case Failure<TargetBreakdownModel>():
          _error = 'تعذّر تحميل توزيع المستهدف. حاول مرة أخرى.';
      }
    });
  }

  Map<String, String> get _branchDisplay {
    final names = <String>{};
    final src = _allBranches.isNotEmpty
        ? _allBranches
        : (_data?.branches ?? const <TargetBreakdownBranchModel>[]);
    for (final b in src) {
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
    });
    _loadBreakdown();
  }

  void _onBranchFilterChanged(String? v) {
    setState(() {
      _filterBranchKey = (v == null || v.isEmpty) ? null : v;
      _focusedBranchKey = _filterBranchKey;
    });
    _loadBreakdown();
  }

  void _onMonthFilterChanged(int? v) {
    if (v == null || _monthLocked) return;
    setState(() => _monthFilter = v);
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
    final useFilterKpis = _filtersActive && _data != null;
    final yearly = useFilterKpis
        ? _data!.targetRevenueEgp
        : widget.target.targetRevenueEgp;

    double? actual;
    double ttd;
    double? ach;
    String targetTitle;
    String actualSubtitle;
    String gapAbove;
    String gapBelow;

    if (useFilterKpis) {
      final d = _data!;
      targetTitle = _monthFilter >= 1 && _monthFilter <= 12
          ? 'مستهدف الشهر'
          : (_filterBranchKey != null ? 'مستهدف الفرع' : 'المستهدف');
      ttd = d.targetRevenueEgp;
      actual = d.hasActuals ? d.actualRevenueEgp : null;
      ach = d.hasActuals ? d.achievementPct : null;
      actualSubtitle = d.hasActuals
          ? (_monthFilter >= 1 && _monthFilter <= 12
              ? monthLabelsAr[_monthFilter - 1]
              : 'ضمن النطاق')
          : 'لا توجد مبيعات بعد';
      gapAbove = 'فوق المستهدف';
      gapBelow = 'المتبقي للمستهدف';
    } else {
      targetTitle = 'مستهدف السنة';
      actual = _series.hasActualsToDate
          ? _series.actualToDateRevenue
          : (widget.target.hasActuals ? widget.target.actualRevenueEgp : null);
      ttd = _series.targetToDateRevenue > 0
          ? _series.targetToDateRevenue
          : yearly;
      ach = _series.achievementToDatePct ??
          (widget.target.hasActuals && ttd > 0
              ? round1((actual ?? 0) / ttd * 100)
              : null);
      actualSubtitle = actual == null ? 'لا توجد مبيعات بعد' : 'حتى تاريخه';
      gapAbove = 'فوق مستهدف حتى تاريخه';
      gapBelow = 'المتبقي حتى تاريخه';
    }

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
            title: targetTitle,
            value: ltrIsolate(CurrencyFormatter.formatCompactEGP(yearly)),
            subtitle: useFilterKpis
                ? (_filterBranchKey != null
                    ? 'نطاق الفرع المختار'
                    : 'حسب المرشّح')
                : 'حتى تاريخه: ${ltrIsolate(CurrencyFormatter.formatCompactEGP(ttd))}',
            icon: Icons.flag_circle_rounded,
            color: cs.primary,
          ),
          M3SummaryKpiCard(
            key: const ValueKey('target_detail_kpi_actual'),
            title: 'المحقق',
            value: actual == null
                ? '—'
                : ltrIsolate(CurrencyFormatter.formatCompactEGP(actual)),
            subtitle: actualSubtitle,
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
                : (gap >= 0 ? gapAbove : gapBelow),
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
    final branchSrc = _allBranches.isNotEmpty
        ? _allBranches
        : (_data?.branches ?? const <TargetBreakdownBranchModel>[]);
    final branchOptions = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('كل الفروع')),
      for (final b in branchSrc)
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
          onChanged: m3Legacy<int>(_onMonthFilterChanged),
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
          value: (_filterBranchKey != null &&
                  branchOptions.any((o) => o.value == _filterBranchKey))
              ? _filterBranchKey!
              : '',
          label: 'الفرع',
          options: m3OptionsFromMenuItems(branchOptions),
          onChanged: m3Legacy<String>(_onBranchFilterChanged),
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
    final visibleMonths = _monthFilter >= 1 && _monthFilter <= 12
        ? _series.months.where((m) => m.month == _monthFilter).toList()
        : _series.months;
    return ListView(
      key: const ValueKey('target_detail_monthly_tab'),
      children: [
        _CumulativeChart(
          key: const ValueKey('target_detail_cumulative_chart'),
          points: _series.cumulative,
          metric: _metric,
          monthPoints: _series.months,
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
                for (final m in visibleMonths)
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
      if (b.branchKey == _focusedBranchKey) {
        selected = b;
        break;
      }
    }
    selected ??= branches.isEmpty ? null : branches.first;

    // At 1280 (content ≈ 982) give the SKU panel enough width that its
    // 5 columns fit without horizontal scroll; branch list stays readable.
    return Row(
      key: const ValueKey('target_detail_branches_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
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
                  dense: true,
                  onTap: () => setState(() => _focusedBranchKey = b.branchKey),
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
          flex: 8,
          child: Container(
            key: const ValueKey('target_detail_branch_skus_panel'),
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
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
                      Expanded(
                        child: _SkuTable(
                          skus: selected.skus,
                          metric: _metric,
                          compact: true,
                        ),
                      ),
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

class _CumulativeChart extends StatefulWidget {
  const _CumulativeChart({
    super.key,
    required this.points,
    required this.monthPoints,
    required this.metric,
  });

  final List<TargetCumulativePoint> points;
  final List<TargetMonthPoint> monthPoints;
  final TargetMetricMode metric;

  @override
  State<_CumulativeChart> createState() => _CumulativeChartState();
}

class _CumulativeChartState extends State<_CumulativeChart> {
  int? _hoverIndex;

  static String _yTick(double v) =>
      CurrencyFormatter.formatCompactEGP(v, decimals: 0);

  static String _xTick(TargetCumulativePoint p) {
    final label = p.labelAr.trim();
    if (label.length <= 3) return label;
    return label.substring(0, 3);
  }

  static double _chartMaxY(List<TargetCumulativePoint> points) {
    var maxY = 1.0;
    for (final p in points) {
      if (p.cumulativeTarget > maxY) maxY = p.cumulativeTarget;
      if (p.hasActuals && p.cumulativeActual > maxY) {
        maxY = p.cumulativeActual;
      }
    }
    // ~12–15% headroom, rounded up slightly to avoid top clipping.
    return maxY * 1.14;
  }

  int? _indexForLocalX(double localX, double width) {
    final points = widget.points;
    if (points.isEmpty || width <= 0) return null;
    const padL = 4.0;
    const padR = 4.0;
    final w = width - padL - padR;
    if (w <= 0) return null;
    if (points.length == 1) return 0;
    final t = ((localX - padL) / w).clamp(0.0, 1.0);
    return (t * (points.length - 1)).round().clamp(0, points.length - 1);
  }

  String _fmtValue(double v) {
    if (widget.metric == TargetMetricMode.units) {
      return CurrencyFormatter.formatNumber(v.round());
    }
    return CurrencyFormatter.formatCompactEGP(v);
  }

  Widget? _tooltip(BuildContext context) {
    final i = _hoverIndex;
    if (i == null || i < 0 || i >= widget.points.length) return null;
    final cum = widget.points[i];
    final month = i < widget.monthPoints.length ? widget.monthPoints[i] : null;
    final has = month?.hasActuals ?? cum.hasActuals;
    final target = month?.targetRevenue ?? cum.cumulativeTarget;
    final targetUnits = month?.targetUnits ?? 0;
    final actual = month?.actualRevenue ?? cum.cumulativeActual;
    final actualUnits = month?.actualUnits ?? 0;
    final targetShow =
        widget.metric == TargetMetricMode.units ? targetUnits : target;
    final actualShow =
        widget.metric == TargetMetricMode.units ? actualUnits : actual;
    final ach = month?.achievementPct;
    final gap = !has
        ? null
        : (widget.metric == TargetMetricMode.units
            ? actualUnits - targetUnits
            : actual - target);
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('target_detail_chart_tooltip'),
      elevation: 4,
      borderRadius: M3Shape.radiusMd,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: DefaultTextStyle(
          style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(cum.labelAr, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('المستهدف: ${ltrIsolate(_fmtValue(targetShow))}'),
              Text(
                has
                    ? 'المحقق: ${ltrIsolate(_fmtValue(actualShow))}'
                    : 'المحقق: لا توجد بيانات',
              ),
              Text(
                ach == null
                    ? 'نسبة التحقيق: —'
                    : 'نسبة التحقيق: ${ach.toStringAsFixed(1)}%',
              ),
              Text(
                gap == null
                    ? 'الفرق: —'
                    : 'الفرق: ${ltrIsolate(_fmtValue(gap))}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accents = M3StatusColors.of(context).accents;
    // High contrast theme roles (not the old close primary/teal pair):
    // solid positiveStrong = المحقق; dashed indigo = المستهدف.
    final actualColor = accents.positiveStrong;
    final targetColor = accents.indigo;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        );
    final maxY = _chartMaxY(widget.points);
    final yTicks = <double>[maxY, maxY * 0.75, maxY * 0.5, maxY * 0.25, 0];

    return Container(
      height: 280,
      padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  key: const ValueKey('target_detail_chart_y_axis'),
                  width: 56,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final v in yTicks)
                        Text(
                          _yTick(v),
                          maxLines: 1,
                          softWrap: false,
                          style: labelStyle,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return MouseRegion(
                              onHover: (e) {
                                final idx = _indexForLocalX(
                                  e.localPosition.dx,
                                  constraints.maxWidth,
                                );
                                if (idx != _hoverIndex) {
                                  setState(() => _hoverIndex = idx);
                                }
                              },
                              onExit: (_) => setState(() => _hoverIndex = null),
                              child: GestureDetector(
                                onTapDown: (d) {
                                  setState(() {
                                    _hoverIndex = _indexForLocalX(
                                      d.localPosition.dx,
                                      constraints.maxWidth,
                                    );
                                  });
                                },
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _CumulativePainter(
                                          points: widget.points,
                                          maxY: maxY,
                                          targetColor: targetColor,
                                          actualColor: actualColor,
                                          gridColor: cs.outlineVariant
                                              .withOpacity(0.4),
                                          hoverIndex: _hoverIndex,
                                          crosshairColor: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    if (_tooltip(context) != null)
                                      Positioned(
                                        top: 4,
                                        left: 8,
                                        child: _tooltip(context)!,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        key: const ValueKey('target_detail_chart_x_axis'),
                        children: [
                          for (final p in widget.points)
                            Expanded(
                              child: Text(
                                _xTick(p),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.clip,
                                style: labelStyle,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _legend(context, targetColor, 'المستهدف', dashed: true),
              const SizedBox(width: 12),
              _legend(context, actualColor, 'المحقق', dashed: false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, Color c, String label,
      {required bool dashed}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(18, 4),
          painter: _LegendLinePainter(color: c, dashed: dashed),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _LegendLinePainter extends CustomPainter {
  _LegendLinePainter({required this.color, required this.dashed});
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    const dash = 3.0;
    const gap = 2.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, size.width), y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _LegendLinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dashed != dashed;
}

class _CumulativePainter extends CustomPainter {
  _CumulativePainter({
    required this.points,
    required this.maxY,
    required this.targetColor,
    required this.actualColor,
    required this.gridColor,
    required this.crosshairColor,
    this.hoverIndex,
  });

  final List<TargetCumulativePoint> points;
  final double maxY;
  final Color targetColor;
  final Color actualColor;
  final Color gridColor;
  final int? hoverIndex;
  final Color crosshairColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;
    const padL = 4.0;
    const padR = 4.0;
    const padT = 18.0;
    const padB = 4.0;
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

    // Target: dashed, all 12 months.
    final targetPaint = Paint()
      ..color = targetColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    final targetPath = Path();
    for (var i = 0; i < points.length; i++) {
      final o = pt(i, points[i].cumulativeTarget);
      if (i == 0) {
        targetPath.moveTo(o.dx, o.dy);
      } else {
        targetPath.lineTo(o.dx, o.dy);
      }
    }
    _drawDashedPath(canvas, targetPath, targetPaint);

    // Actual: solid, stop at last month with hasActuals.
    var lastActual = -1;
    for (var i = 0; i < points.length; i++) {
      if (points[i].hasActuals) lastActual = i;
    }
    if (lastActual >= 0) {
      final actualPaint = Paint()
        ..color = actualColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeJoin = StrokeJoin.round;
      final actualPath = Path();
      for (var i = 0; i <= lastActual; i++) {
        final o = pt(i, points[i].cumulativeActual);
        if (i == 0) {
          actualPath.moveTo(o.dx, o.dy);
        } else {
          actualPath.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(actualPath, actualPaint);
      final marker = Paint()..color = actualColor;
      for (var i = 0; i <= lastActual; i++) {
        if (!points[i].hasActuals) continue;
        canvas.drawCircle(pt(i, points[i].cumulativeActual), 3.2, marker);
      }
    }

    final hi = hoverIndex;
    if (hi != null && hi >= 0 && hi < points.length) {
      final x = pt(hi, 0).dx;
      final cross = Paint()
        ..color = crosshairColor.withOpacity(0.55)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, padT), Offset(x, padT + h), cross);
      canvas.drawCircle(pt(hi, points[hi].cumulativeTarget), 4, Paint()..color = targetColor);
      if (hi <= lastActual && points[hi].hasActuals) {
        canvas.drawCircle(
          pt(hi, points[hi].cumulativeActual),
          4.5,
          Paint()..color = actualColor,
        );
      }
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      const dashLen = 7.0;
      const gapLen = 5.0;
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLen).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CumulativePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.maxY != maxY ||
      oldDelegate.hoverIndex != hoverIndex ||
      oldDelegate.targetColor != targetColor ||
      oldDelegate.actualColor != actualColor;
}

class _SkuTable extends StatelessWidget {
  const _SkuTable({
    required this.skus,
    required this.metric,
    this.compact = false,
  });

  final List<TargetBreakdownSkuModel> skus;
  final TargetMetricMode metric;
  /// Branch-panel layout: flex columns that fit ~1280 without h-scroll.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildCompact(context);
    return TableScrollContainer(
      key: const ValueKey('target_detail_sku_table'),
      columnFlex: const [2.4, 1.2, 1.2, 1.3, 1.1],
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
          for (final s in skus) _dataRow(context, s),
        ],
      ),
    );
  }

  DataRow _dataRow(BuildContext context, TargetBreakdownSkuModel s) {
    return DataRow(
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
        DataCell(Text(_targetText(s))),
        DataCell(Text(_actualText(s))),
        DataCell(Text(_achText(s))),
        DataCell(Text(_gapText(s))),
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final cs = theme.colorScheme;
    return Container(
      key: const ValueKey('target_detail_branch_sku_table'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'الصنف',
                    key: const ValueKey('target_detail_sku_header_name'),
                    maxLines: 1,
                    softWrap: false,
                    style: headerStyle,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text('المستهدف', maxLines: 1, softWrap: false, style: headerStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('المحقق', maxLines: 1, softWrap: false, style: headerStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('التحقيق %', maxLines: 1, softWrap: false, style: headerStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('الفرق', maxLines: 1, softWrap: false, style: headerStyle),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withOpacity(0.5)),
          Expanded(
            child: ListView.separated(
              itemCount: skus.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: cs.outlineVariant.withOpacity(0.35),
              ),
              itemBuilder: (context, i) {
                final s = skus[i];
                return Padding(
                  key: ValueKey('target_detail_sku_${s.skuKey}'),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.skuName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              ltrIsolate(s.skuKey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(_targetText(s), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(_actualText(s), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(_achText(s), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(_gapText(s), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _targetText(TargetBreakdownSkuModel s) => metric == TargetMetricMode.value
      ? ltrIsolate(CurrencyFormatter.formatCompactEGP(s.allocatedTargetEgp))
      : '${s.allocatedUnits ?? '—'}';

  String _actualText(TargetBreakdownSkuModel s) => metric == TargetMetricMode.value
      ? ltrIsolate(CurrencyFormatter.formatCompactEGP(s.actualRevenueEgp))
      : '${s.actualUnits}';

  String _achText(TargetBreakdownSkuModel s) => s.achievementPct == null
      ? '—'
      : '${s.achievementPct!.toStringAsFixed(1)}%';

  String _gapText(TargetBreakdownSkuModel s) =>
      ltrIsolate(CurrencyFormatter.formatCompactEGP(s.gapEgp));
}


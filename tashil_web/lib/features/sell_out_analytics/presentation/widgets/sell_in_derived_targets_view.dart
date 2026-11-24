import 'package:flutter/material.dart';

import '../../../../core/data/result.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/theme/m3_status_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_section_title.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../../../core/widgets/m3_table_surface.dart';
import '../../../../core/widgets/m3_table_text.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../data/target_repository.dart';
import '../../domain/sell_in_targets_export.dart';
import '../../domain/target_table_format.dart';

/// Sell-In targets tab: read-only, derived on the server from the Sell-Out
/// targets (same product, branch, chain and period, 1:1 in pieces).
///
/// Quantity is the primary metric (pieces, then cases from the Product Master
/// pack size); value (quantity × Product Master cost) is secondary. There is
/// nothing to add, upload, edit or delete here: the targets are changed on the
/// Sell-Out targets tab ([onOpenSellOutTargets]).
class SellInDerivedTargetsView extends StatefulWidget {
  const SellInDerivedTargetsView({
    super.key,
    required this.apiClient,
    this.repository,
    this.onOpenSellOutTargets,
  });

  final ApiClient apiClient;

  /// Injected repository (tests); defaults to one wrapping [apiClient].
  final TargetRepository? repository;

  /// Opens the Sell-Out targets tab (edit / create the source targets).
  final VoidCallback? onOpenSellOutTargets;

  @override
  State<SellInDerivedTargetsView> createState() =>
      _SellInDerivedTargetsViewState();
}

class _SellInDerivedTargetsViewState extends State<SellInDerivedTargetsView> {
  late final TargetRepository _repo =
      widget.repository ?? TargetRepository(widget.apiClient);

  bool _loading = true;
  bool _failed = false;
  TargetsSummaryModel? _summary;
  List<RetailChainModel> _companyChains = const [];

  String _chain = 'all';
  int _year = 0;
  final Set<String> _brands = <String>{};
  String? _selectedTargetId;
  bool _showAllSkus = false;
  final Set<String> _expandedBranches = <String>{};
  final Set<String> _branchShowAll = <String>{};

  static const _skuPreview = 25;

  /// Caps that keep the 12-column table inside the live 1280 shell
  /// (250dp sidebar + 24dp page padding each side ≈ 982dp) without
  /// horizontal scrolling.
  static const _colMax = <double>[
    108, // السلسلة
    72, // الفترة
    84, // النطاق
    66, // مستهدف قطعة
    64, // مستهدف كرتونة
    66, // محقق قطعة
    66, // فرق قطعة
    62, // تحقيق الكمية
    70, // مستهدف ج.م
    70, // محقق ج.م
    70, // فرق ج.م
    62, // تحقيق القيمة
  ];

  static const _branchCaps = <double>[150, 78, 78, 78, 72, 84, 84, 72];

  static const _skuCaps = <double>[150, 88, 78, 78, 78, 72, 84, 84, 72];

  int get _baseYear {
    final y = DateTime.now().year;
    return y >= 2026 ? y : 2026;
  }

  List<int> get _years => [_baseYear, _baseYear + 1, _baseYear + 2];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final chains = await _repo.loadChains();
    if (chains case Success(:final value)) {
      if (mounted) setState(() => _companyChains = value);
    }
    await _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final loaded = await _repo.loadDerivedSellInSummary(
      chain: _chain == 'all' ? null : _chain,
      year: _year > 0 ? _year : null,
      brands: _brands.toList(),
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    if (loaded case Failure(:final error)) {
      debugPrint('Derived Sell-In targets load failed: $error');
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    final res = loaded.valueOrNull!;
    setState(() {
      _summary = res;
      _loading = false;
      if (!res.items.any((i) => i.id == _selectedTargetId)) {
        _selectedTargetId = null;
        _resetDrillDown();
      }
    });
  }

  List<({String code, String label})> get _chainOptions {
    final opts = <({String code, String label})>[
      (code: 'all', label: 'كل السلاسل'),
      (code: 'fathalla', label: 'أسواق فتح الله'),
      (code: 'gomla', label: 'جملة ماركت'),
      (code: 'beet-elgomla', label: 'بيت الجملة'),
      (code: 'chain-1080314', label: 'الوكالة'),
      (code: 'carrefour', label: 'كارفور'),
      (code: 'spinneys', label: 'سبينيس'),
    ];
    final seen = opts.map((e) => e.code.toLowerCase()).toSet();
    for (final c in _companyChains) {
      final code = c.code.trim().toLowerCase();
      if (code.isNotEmpty && !seen.contains(code)) {
        seen.add(code);
        opts.add((code: code, label: c.displayName));
      }
    }
    return opts;
  }

  List<String> get _brandOptions {
    final all = <String>{
      ...?_summary?.availableBrands,
      ..._brands,
    }.toList();
    all.sort((a, b) {
      if (a == kNoBrandLabelAr) return 1;
      if (b == kNoBrandLabelAr) return -1;
      return a.compareTo(b);
    });
    return all;
  }

  TargetComparisonModel? get _selectedTarget {
    final id = _selectedTargetId;
    if (id == null) return null;
    for (final i in _summary?.items ?? const <TargetComparisonModel>[]) {
      if (i.id == id) return i;
    }
    return null;
  }

  void _export() {
    final summary = _summary;
    final export = summary == null
        ? null
        : SellInTargetsExport.from(summary, brands: _brands);
    if (export == null || export.rows.isEmpty) {
      M3Feedback.showError(context, 'لا توجد مستهدفات للتصدير.');
      return;
    }
    final csv = ExcelExportService.generateCsv(
        headers: export.headers, rows: export.rows);
    ExcelExportService.downloadCsv(
        'tashil_sell_in_derived_targets_${DateTime.now().millisecondsSinceEpoch}.csv',
        csv);
    M3Feedback.showSuccess(
        context, 'تم تصدير مستهدفات Sell-In (${export.rows.length} صف).');
  }

  Color _pctColor(BuildContext context, double pct) {
    final cs = Theme.of(context).colorScheme;
    if (pct >= 100) return M3StatusColors.of(context).accents.positive;
    if (pct >= 85) return M3StatusColors.of(context).accents.caution;
    return cs.error;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final summary = _summary ?? TargetsSummaryModel.empty('sell_in');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDerivedBanner(context),
        M3Spacing.gapMD,
        _buildKpis(context, summary),
        M3Spacing.gapMD,
        _buildFilterBar(context),
        if (!_loading && !_failed) ..._buildNotices(context, summary),
        M3Spacing.gapMD,
        Container(
          key: const ValueKey('sellin_targets_table_section'),
          decoration: BoxDecoration(
            color: M3TableSurface.color(cs),
            borderRadius: M3Shape.radiusLg,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
          ),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(48.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _failed
                  ? _buildErrorState(context)
                  : summary.items.isEmpty
                      ? _buildEmptyState(context, summary)
                      : _buildTable(context, summary),
        ),
        if (!_loading && !_failed && _selectedTarget != null) ...[
          M3Spacing.gapMD,
          _buildDetail(context, _selectedTarget!),
        ],
      ],
    );
  }

  Widget _buildDerivedBanner(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: const ValueKey('sellin_derived_banner'),
      padding: M3Spacing.pSm,
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.35),
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.primary.withOpacity(0.25)),
      ),
      child: Wrap(
        spacing: M3Spacing.sm,
        runSpacing: M3Spacing.xs,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: M3Spacing.xs,
            runSpacing: M3Spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                key: const ValueKey('sellin_derived_badge'),
                avatar: Icon(Icons.auto_awesome_rounded,
                    size: 18.0, color: cs.primary),
                label: const Text('محسوب تلقائياً من مستهدف Sell-Out'),
              ),
              Text(
                'الكمية بالقطعة = مستهدف Sell-Out لنفس الصنف والفرع والسلسلة والفترة. '
                'القيمة = الكمية × سعر التكلفة.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          FilledButton.tonalIcon(
            key: const ValueKey('sellin_edit_sellout_targets'),
            onPressed: widget.onOpenSellOutTargets,
            icon: const Icon(Icons.edit_note_rounded,
                size: M3ToolbarButton.iconSize),
            label: const Text('تعديل مستهدف Sell-Out'),
            style: M3ToolbarButton.style,
          ),
        ],
      ),
    );
  }

  Widget _buildKpis(BuildContext context, TargetsSummaryModel s) {
    final cs = Theme.of(context).colorScheme;
    final accents = M3StatusColors.of(context).accents;
    final comparable = s.items
        .any((i) => i.hasActuals && !i.excludedFromTotals && i.targetUnits > 0);
    final hasTargets = s.items.isNotEmpty;
    final partialCases = s.packSizeMissingSkusCount > 0;

    String pieces(double v) =>
        '${CurrencyFormatter.formatNumber(v.round())} قطعة';
    String cases(double? v) {
      if (v == null) return '— كرتونة';
      final n = CurrencyFormatter.formatNumber(v.round());
      return partialCases ? '$n كرتونة (جزئي)' : '$n كرتونة';
    }

    final ach = comparable ? s.overallAchievementPct : null;
    final achRev = comparable ? s.overallAchievementRevPct : null;
    final achColor =
        ach == null ? cs.onSurfaceVariant : _pctColor(context, ach);

    final cards = <Widget>[
      M3SummaryKpiCard(
        key: const ValueKey('sellin_kpi_target_qty'),
        title: 'مستهدف التوريد (كمية)',
        value: hasTargets ? pieces(s.totalTargetUnits) : '—',
        subtitle:
            hasTargets ? cases(s.totalTargetCases) : 'لا توجد مستهدفات بعد',
        icon: Icons.flag_circle_rounded,
        color: cs.primary,
        shrinkOverflowingValue: true,
        titleMaxLines: 1,
        subtitleMaxLines: 1,
      ),
      M3SummaryKpiCard(
        key: const ValueKey('sellin_kpi_actual_qty'),
        title: 'المحقق (كمية)',
        value: comparable ? pieces(s.totalActualUnits) : '—',
        subtitle: !hasTargets
            ? 'لا توجد مستهدفات بعد'
            : comparable
                ? cases(s.totalActualCases)
                : 'لا توجد مبيعات بعد',
        icon: Icons.inventory_2_rounded,
        color: accents.teal,
        shrinkOverflowingValue: true,
        titleMaxLines: 1,
        subtitleMaxLines: 1,
      ),
      M3SummaryKpiCard(
        key: const ValueKey('sellin_kpi_achievement_qty'),
        title: 'نسبة تحقيق الكمية',
        value: ach == null ? '—' : '${ach.toStringAsFixed(1)}%',
        subtitle: !hasTargets
            ? 'لا توجد مستهدفات بعد'
            : ach == null
                ? 'لا توجد مبيعات بعد'
                : ach >= 100
                    ? 'فوق المستهدف'
                    : ach >= 85
                        ? 'قريب من المستهدف'
                        : 'أقل من المستهدف',
        icon: Icons.pie_chart_rounded,
        color: achColor,
        titleMaxLines: 1,
        subtitleMaxLines: 1,
      ),
      M3SummaryKpiCard(
        key: const ValueKey('sellin_kpi_value'),
        title: 'القيمة (سعر التكلفة)',
        value: hasTargets
            ? CurrencyFormatter.formatCompactEGP(s.totalTargetRevenueEgp)
            : '—',
        subtitle: !hasTargets
            ? 'لا توجد مستهدفات بعد'
            : comparable
                ? 'محقق ${CurrencyFormatter.formatCompactEGP(s.totalActualRevenueEgp)} • تحقيق ${achRev!.toStringAsFixed(1)}%'
                : 'لا توجد مبيعات بعد',
        subtitleTooltip: s.costMissingSkusCount > 0
            ? 'قيمة جزئية: ${s.costMissingSkusCount} صنف بدون سعر تكلفة'
            : null,
        icon: Icons.payments_rounded,
        color: accents.indigo,
        titleMaxLines: 1,
        subtitleMaxLines: 1,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) => M3EqualHeightGrid(
        key: const ValueKey('sellin_kpi_grid'),
        columns: M3KpiGridColumns.forWidth(c.maxWidth),
        spacing: M3Spacing.sm,
        runSpacing: M3Spacing.sm,
        children: cards,
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brandOptions = _brandOptions;
    return Container(
      key: const ValueKey('sellin_filter_bar'),
      padding: M3Spacing.pSm,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Wrap(
        spacing: M3Spacing.sm,
        runSpacing: M3Spacing.xs,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: M3Spacing.sm,
            runSpacing: M3Spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              M3Dropdown<int>(
                key: const ValueKey('sellin_year_filter'),
                width: 190.0,
                fitOptions: true,
                value: [0, ..._years].contains(_year) ? _year : 0,
                label: 'سنة البيانات',
                options: m3OptionsFromMenuItems<int>([
                  const DropdownMenuItem(value: 0, child: Text('كل السنوات')),
                  ..._years.map(
                    (yr) =>
                        DropdownMenuItem<int>(value: yr, child: Text('$yr')),
                  ),
                ]),
                onChanged: m3Legacy<int>((v) {
                  if (v != null && v != _year) {
                    setState(() => _year = v);
                    _load();
                  }
                }),
              ),
              M3Dropdown<String>(
                key: const ValueKey('sellin_chain_filter'),
                width: 240.0,
                fitOptions: true,
                value:
                    _chainOptions.any((c) => c.code == _chain) ? _chain : 'all',
                label: 'السلسلة',
                options: m3OptionsFromMenuItems<String>(_chainOptions
                    .map((c) => DropdownMenuItem<String>(
                          value: c.code,
                          child: Text(c.label, overflow: TextOverflow.ellipsis),
                        ))
                    .toList()),
                onChanged: m3Legacy<String>((v) {
                  if (v != null && v != _chain) {
                    setState(() => _chain = v);
                    _load();
                  }
                }),
              ),
              _buildBrandFilter(context, brandOptions),
            ],
          ),
          OutlinedButton.icon(
            key: const ValueKey('sellin_export_button'),
            onPressed: _loading || _failed ? null : _export,
            icon: const Icon(Icons.table_view_rounded,
                size: M3ToolbarButton.iconSize),
            label: const Text('تصدير'),
            style: M3ToolbarButton.style,
          ),
        ],
      ),
    );
  }

  Widget _buildBrandFilter(BuildContext context, List<String> options) {
    final active = _brands.isNotEmpty;
    final label = active
        ? 'العلامة التجارية (${_brands.length})'
        : 'كل العلامات التجارية';
    return MenuAnchor(
      key: const ValueKey('sellin_brand_filter'),
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('sellin_brand_clear'),
          closeOnActivate: false,
          onPressed: active
              ? () {
                  setState(_brands.clear);
                  _load();
                }
              : null,
          child: const Text('مسح الاختيار (كل العلامات)'),
        ),
        for (final b in options)
          CheckboxMenuButton(
            key: ValueKey('sellin_brand_option_$b'),
            closeOnActivate: false,
            value: _brands.contains(b),
            onChanged: (on) {
              setState(() {
                if (on ?? false) {
                  _brands.add(b);
                } else {
                  _brands.remove(b);
                }
              });
              _load();
            },
            child: Text(b),
          ),
        if (options.isEmpty)
          const MenuItemButton(
            closeOnActivate: false,
            child: Text('لا توجد علامات تجارية'),
          ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        const icon =
            Icon(Icons.sell_rounded, size: M3ToolbarButton.iconSize);
        return active
            ? FilledButton.tonalIcon(
                key: const ValueKey('sellin_brand_filter_button'),
                onPressed: toggle,
                icon: icon,
                label: Text(label),
                style: M3ToolbarButton.style,
              )
            : OutlinedButton.icon(
                key: const ValueKey('sellin_brand_filter_button'),
                onPressed: toggle,
                icon: icon,
                label: Text(label),
                style: M3ToolbarButton.style,
              );
      },
    );
  }

  List<Widget> _buildNotices(BuildContext context, TargetsSummaryModel s) {
    final notes = <(String, String)>[
      if (s.packSizeMissingSkusCount > 0)
        (
          'sellin_notice_pack_size',
          '${s.packSizeMissingSkusCount} صنف بدون حجم عبوة في Product Master: '
              'الكراتين تظهر «—» أو جزئية، والكمية بالقطعة كاملة.'
        ),
      if (s.costMissingSkusCount > 0)
        (
          'sellin_notice_cost',
          '${s.costMissingSkusCount} صنف بدون سعر تكلفة في Product Master: '
              'القيمة جزئية ولم يتم تقديرها.'
        ),
      if (s.excludedFromTotalsCount > 0)
        (
          'sellin_notice_excluded',
          '${s.excludedFromTotalsCount} مستهدف سنوي مستبعد من الإجماليات '
              'لوجود مستهدفات شهرية لنفس الفترة (لتفادي العدّ المزدوج).'
        ),
    ];
    if (notes.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      M3Spacing.gapSM,
      for (final (key, text) in notes)
        Padding(
          padding: const EdgeInsets.only(bottom: M3Spacing.xxs),
          child: Row(
            key: ValueKey(key),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 16.0, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: M3Spacing.xs),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _buildErrorState(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('sellin_targets_error'),
      padding: const EdgeInsets.symmetric(vertical: 42.0, horizontal: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 48.0, color: theme.colorScheme.error),
          const SizedBox(height: 14.0),
          Text('تعذّر تحميل مستهدفات Sell-In.',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14.0),
          FilledButton.icon(
            onPressed: () => _load(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, TargetsSummaryModel s) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final brandFiltered = _brands.isNotEmpty && s.sellOutTargetsCount > 0;
    return Padding(
      key: ValueKey(brandFiltered
          ? 'sellin_targets_empty_brand'
          : 'sellin_targets_empty'),
      padding: const EdgeInsets.symmetric(vertical: 42.0, horizontal: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree_rounded,
              size: 48.0, color: cs.primary.withOpacity(0.75)),
          const SizedBox(height: 14.0),
          Text(
            brandFiltered
                ? 'لا توجد مستهدفات للعلامات التجارية المختارة.'
                : 'لا يوجد مستهدف Sell-Out لهذه الفترة بعد.',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8.0),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680.0),
            child: Text(
              brandFiltered
                  ? 'غيّر اختيار العلامات التجارية أو امسح الفلتر لعرض كل المستهدفات.'
                  : 'مستهدفات Sell-In تُحسب تلقائياً من مستهدفات Sell-Out. '
                      'أنشئ مستهدف Sell-Out وستظهر هنا فوراً بالقطعة والكرتونة والقيمة.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 18.0),
          if (brandFiltered)
            FilledButton.icon(
              key: const ValueKey('sellin_clear_brand_filter'),
              onPressed: () {
                setState(_brands.clear);
                _load();
              },
              icon: const Icon(Icons.filter_alt_off_rounded),
              label: const Text('مسح فلتر العلامة التجارية'),
            )
          else
            FilledButton.icon(
              key: const ValueKey('sellin_create_sellout_target'),
              onPressed: widget.onOpenSellOutTargets,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('إنشاء مستهدف Sell-Out'),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Main table (12 columns, read-only)
  // ---------------------------------------------------------------------------

  Widget _cap(List<double> caps, int i, Widget child) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: caps[i]), child: child);

  Widget _line(
    List<double> caps,
    int i,
    String text, {
    String? tooltip,
    Key? key,
    TextStyle? style,
  }) {
    final t = Text(
      text,
      key: key,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: style,
    );
    return _cap(
      caps,
      i,
      Align(
        alignment: Alignment.center,
        child: tooltip == null ? t : Tooltip(message: tooltip, child: t),
      ),
    );
  }

  DataColumn _col(List<double> caps, int i, String label, {int maxLines = 2}) =>
      DataColumn(
        headingRowAlignment: M3TableText.headingAlignment,
        label: _cap(caps, i, M3TableText(label, maxLines: maxLines)),
      );

  Widget _table({
    Key? key,
    required List<double> caps,
    required List<String> headers,
    required List<DataRow> rows,
  }) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return TableScrollContainer(
      key: key,
      showSwipeHint: true,
      columnFlex: caps,
      child: DataTable(
        showCheckboxColumn: false,
        headingRowColor:
            WidgetStatePropertyAll(cs.surfaceContainerHigh.withOpacity(0.5)),
        columnSpacing: M3Spacing.xxs,
        horizontalMargin: M3Spacing.xxs,
        headingRowHeight: 48,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 56,
        headingTextStyle: theme.textTheme.labelMedium
            ?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
        dataTextStyle:
            theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
        columns: [
          for (final (i, h) in headers.indexed) _col(caps, i, h),
        ],
        rows: rows,
      ),
    );
  }

  String _casesText(double? v, {bool partial = false}) {
    if (v == null) return '—';
    final t = TargetTableFormat.count(v);
    return partial ? '$t*' : t;
  }

  String _casesExact(double? v, {bool partial = false}) {
    if (v == null) return 'لا يوجد حجم عبوة في Product Master';
    final t = '${CurrencyFormatter.formatNumber(v.round())} كرتونة';
    return partial ? '$t (جزئي: أصناف بدون حجم عبوة غير محسوبة)' : t;
  }

  Widget _buildTable(BuildContext context, TargetsSummaryModel summary) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const headers = [
      'السلسلة',
      'الفترة',
      'النطاق',
      'مستهدف قطعة',
      'مستهدف كرتونة',
      'محقق قطعة',
      'فرق قطعة',
      'تحقيق الكمية',
      'مستهدف ج.م',
      'محقق ج.م',
      'فرق ج.م',
      'تحقيق القيمة',
    ];

    final rows = summary.items.map((item) {
      final selected = item.id == _selectedTargetId;
      final noSales = !item.hasActuals;
      final dim = item.excludedFromTotals ? 0.55 : 1.0;
      final periodLabel = TargetTableFormat.period(
        year: item.year,
        month: item.month,
        monthLabel: item.monthLabel,
      );
      final scopeLabel = TargetTableFormat.scope(
          branch: item.branchName, category: item.category);
      final partialCases = item.packSizeMissingSkus > 0;
      final partialValue = item.costMissingSkus > 0;
      final qtyPct = item.achievementUnitsPct;
      final valPct = item.achievementRevPct;
      final varUnits = item.actualUnits - item.targetUnits;
      final varValue = item.actualRevenueEgp - item.targetRevenueEgp;

      Widget dimmed(Widget w) =>
          dim == 1.0 ? w : Opacity(opacity: dim, child: w);

      Widget dash(int i) =>
          _line(_colMax, i, '—', style: TextStyle(color: cs.onSurfaceVariant));

      DataCell cell(Widget w) => DataCell(Center(child: dimmed(w)));

      return DataRow(
        key: ValueKey('sellin_targets_row_${item.id}'),
        selected: selected,
        onSelectChanged: (_) => setState(() {
          _selectedTargetId = selected ? null : item.id;
          _resetDrillDown();
        }),
        cells: [
          cell(_line(_colMax, 0, item.chainDisplayName,
              tooltip: item.chainDisplayName,
              key: ValueKey('sellin_chain_${item.id}'),
              style: const TextStyle(fontWeight: FontWeight.w800))),
          cell(_line(_colMax, 1,
              item.excludedFromTotals ? '$periodLabel ⊘' : periodLabel,
              key: ValueKey('sellin_period_${item.id}'),
              tooltip: item.excludedFromTotals
                  ? 'مستبعد من الإجماليات: يوجد مستهدفات شهرية لنفس الفترة'
                  : (item.monthLabel.trim().isNotEmpty &&
                          item.monthLabel.trim() != periodLabel
                      ? item.monthLabel.trim()
                      : null))),
          cell(_line(_colMax, 2, scopeLabel, tooltip: scopeLabel)),
          cell(_line(_colMax, 3, TargetTableFormat.count(item.targetUnits),
              key: ValueKey('sellin_target_pieces_${item.id}'),
              tooltip:
                  '${CurrencyFormatter.formatNumber(item.targetUnits.round())} قطعة',
              style: const TextStyle(fontWeight: FontWeight.w800))),
          cell(_line(
              _colMax,
              4,
              _casesText(item.targetCases,
                  partial: partialCases && item.targetCases != null),
              key: ValueKey('sellin_target_cases_${item.id}'),
              tooltip: _casesExact(item.targetCases,
                  partial: partialCases && item.targetCases != null))),
          cell(noSales
              ? dash(5)
              : _line(_colMax, 5, TargetTableFormat.count(item.actualUnits),
                  key: ValueKey('sellin_actual_pieces_${item.id}'),
                  tooltip:
                      '${CurrencyFormatter.formatNumber(item.actualUnits.round())} قطعة',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: cs.primary))),
          cell(noSales
              ? dash(6)
              : _line(_colMax, 6, TargetTableFormat.signedCount(varUnits),
                  tooltip:
                      '${CurrencyFormatter.formatNumber(varUnits.round())} قطعة',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: varUnits >= 0
                          ? M3StatusColors.of(context).accents.positive
                          : cs.error))),
          cell(noSales
              ? dash(7)
              : _line(_colMax, 7, '${qtyPct.toStringAsFixed(1)}%',
                  key: ValueKey('sellin_qty_pct_${item.id}'),
                  tooltip: item.statusAr,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _pctColor(context, qtyPct)))),
          cell(_line(
              _colMax,
              8,
              TargetTableFormat.moneyNumber(item.targetRevenueEgp) +
                  (partialValue ? '*' : ''),
              key: ValueKey('sellin_target_value_${item.id}'),
              tooltip: partialValue
                  ? '${TargetTableFormat.moneyExact(item.targetRevenueEgp)} (جزئي: ${item.costMissingSkus} صنف بدون سعر تكلفة)'
                  : TargetTableFormat.moneyExact(item.targetRevenueEgp))),
          cell(noSales
              ? dash(9)
              : _line(_colMax, 9,
                  TargetTableFormat.moneyNumber(item.actualRevenueEgp),
                  tooltip: TargetTableFormat.moneyExact(item.actualRevenueEgp),
                  style: TextStyle(color: cs.primary))),
          cell(noSales
              ? dash(10)
              : _line(
                  _colMax, 10, TargetTableFormat.signedMoneyNumber(varValue),
                  tooltip: TargetTableFormat.moneyExact(varValue),
                  style: TextStyle(
                      color: varValue >= 0
                          ? M3StatusColors.of(context).accents.positive
                          : cs.error))),
          cell(noSales || item.targetRevenueEgp <= 0
              ? dash(11)
              : _line(_colMax, 11, '${valPct.toStringAsFixed(1)}%',
                  key: ValueKey('sellin_value_pct_${item.id}'),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _pctColor(context, valPct)))),
        ],
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(18.0, 16.0, 18.0, 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    Icon(Icons.layers_rounded, color: cs.primary, size: 24.0),
                    const SizedBox(width: 8.0),
                    const Flexible(
                        child: M3SectionTitle(
                            'مستهدف Sell-In (محسوب من Sell-Out)')),
                  ],
                ),
              ),
              const SizedBox(width: 8.0),
              Flexible(
                child: Text(
                  'اضغط على صف لعرض الفروع والأصناف. الجدول للقراءة فقط.',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.primary, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        _table(
          key: const ValueKey('sellin_targets_main_table'),
          caps: _colMax,
          headers: headers,
          rows: rows,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Drill-down: branches + SKUs of the selected target (read-only)
  // ---------------------------------------------------------------------------

  Widget _buildDetail(BuildContext context, TargetComparisonModel t) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final period = TargetTableFormat.period(
        year: t.year, month: t.month, monthLabel: t.monthLabel);

    final skus = t.chainSkuTotals;
    final shownSkus = _showAllSkus ? skus : skus.take(_skuPreview).toList();
    final skuRows = _skuRows(context, shownSkus,
        hasActuals: t.hasActuals, keyPrefix: 'sellin_sku');
    final allocated = t.branches.any((b) => b.actualAllocatedUnits > 0);

    return Container(
      key: const ValueKey('sellin_targets_detail'),
      padding: M3Spacing.pSm,
      decoration: BoxDecoration(
        color: M3TableSurface.color(cs),
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.primary.withOpacity(0.35), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_rounded, color: cs.primary, size: 22.0),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  'توزيع المستهدف: ${t.chainDisplayName} • $period',
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900, color: cs.primary),
                ),
              ),
              IconButton(
                tooltip: 'إغلاق التفاصيل',
                onPressed: () => setState(() {
                  _selectedTargetId = null;
                  _resetDrillDown();
                }),
                icon: const Icon(AppIcons.close),
              ),
            ],
          ),
          M3Spacing.gapSM,
          Wrap(
            spacing: M3Spacing.sm,
            runSpacing: M3Spacing.xs,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('الفروع (${t.branches.length})',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              if (t.branches.isNotEmpty)
                OutlinedButton.icon(
                  key: const ValueKey('sellin_branches_export_all'),
                  onPressed: () => _exportBranches(t),
                  icon: const Icon(Icons.table_view_rounded,
                      size: M3ToolbarButton.iconSize),
                  label: const Text('تصدير كل الفروع'),
                  style: M3ToolbarButton.style,
                ),
            ],
          ),
          if (t.branches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: M3Spacing.xxs),
              child: Text(
                allocated
                    ? 'اضغط على فرع لعرض أصنافه. المحقق لكل فرع = المسحوبات المسجلة على كود الفرع '
                        '+ نصيبه من مسحوبات مجمع الإقليم موزعة بنسبة مستهدف كل صنف.'
                    : 'اضغط على فرع لعرض أصنافه.',
                key: const ValueKey('sellin_branches_hint'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: M3Spacing.xs),
          if (t.branches.isEmpty)
            Text('لا توجد فروع.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant))
          else
            _buildBranchAccordion(context, t),
          M3Spacing.gapMD,
          Text('الأصناف (${skus.length})',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: M3Spacing.xs),
          if (skuRows.isEmpty)
            Text('لا توجد أصناف.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant))
          else
            _table(
              key: const ValueKey('sellin_skus_table'),
              caps: _skuCaps,
              headers: _skuHeaders,
              rows: skuRows,
            ),
          if (skus.length > _skuPreview)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const ValueKey('sellin_skus_toggle'),
                onPressed: () => setState(() => _showAllSkus = !_showAllSkus),
                child: Text(_showAllSkus
                    ? 'عرض أول $_skuPreview صنف فقط'
                    : 'عرض كل الأصناف (${skus.length})'),
              ),
            ),
        ],
      ),
    );
  }

  static const _branchHeaders = [
    'الفرع',
    'مستهدف قطعة',
    'مستهدف كرتونة',
    'محقق قطعة',
    'تحقيق الكمية',
    'مستهدف ج.م',
    'محقق ج.م',
    'تحقيق القيمة',
  ];

  static const _skuHeaders = [
    'الصنف',
    'العلامة التجارية',
    'مستهدف قطعة',
    'مستهدف كرتونة',
    'محقق قطعة',
    'تحقيق الكمية',
    'مستهدف ج.م',
    'محقق ج.م',
    'تحقيق القيمة',
  ];

  String _branchId(TargetBranchBreakdownModel b) =>
      '${b.branchCode}\u001f${b.branchName}';

  void _resetDrillDown() {
    _showAllSkus = false;
    _expandedBranches.clear();
    _branchShowAll.clear();
  }

  void _exportBranches(TargetComparisonModel t,
      {TargetBranchBreakdownModel? branch}) {
    final export = SellInTargetsExport.branches(
        t, branch == null ? t.branches : [branch],
        brands: _brands);
    if (export.rows.isEmpty) {
      M3Feedback.showError(context, 'لا توجد أصناف للتصدير.');
      return;
    }
    final csv = ExcelExportService.generateCsv(
        headers: export.headers, rows: export.rows);
    ExcelExportService.downloadCsv(
        SellInTargetsExport.branchFileName(t, branch: branch), csv);
    M3Feedback.showSuccess(
        context,
        branch == null
            ? 'تم تصدير أصناف كل الفروع (${export.rows.length} صف).'
            : 'تم تصدير أصناف ${branch.branchName} (${export.rows.length} صف).');
  }

  /// One row of cells sized like the branch table columns (fills the width).
  Widget _branchCells(List<Widget> cells) => Row(
        children: [
          for (final (i, w) in cells.indexed)
            Expanded(
              flex: _branchCaps[i].round(),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: M3Spacing.xxs / 2),
                child: Center(child: w),
              ),
            ),
        ],
      );

  /// Branches as an inline accordion: tapping a branch expands its SKUs
  /// (built only while expanded) with a per-branch export.
  Widget _buildBranchAccordion(BuildContext context, TargetComparisonModel t) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final headingStyle = theme.textTheme.labelMedium
        ?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600);
    return ClipRRect(
      key: const ValueKey('sellin_branches_table'),
      borderRadius: M3Shape.radiusMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xxs),
            color: cs.surfaceContainerHigh.withOpacity(0.5),
            child: _branchCells([
              for (final h in _branchHeaders)
                M3TableText(h, maxLines: 2, style: headingStyle),
            ]),
          ),
          for (final b in t.branches) _buildBranchRow(context, t, b),
        ],
      ),
    );
  }

  Widget _buildBranchRow(BuildContext context, TargetComparisonModel t,
      TargetBranchBreakdownModel b) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final id = _branchId(b);
    final open = _expandedBranches.contains(id);
    final has = SellInTargetsExport.branchHasActuals(b);
    Widget c(int i, String s, {String? tip, TextStyle? style, Key? key}) =>
        _line(_branchCaps, i, s, tooltip: tip, style: style, key: key);

    final direct = b.actualUnits - b.actualAllocatedUnits;
    final actualTip = !has
        ? 'لا توجد مسحوبات Sell-In لهذا الفرع'
        : b.actualAllocatedUnits > 0
            ? '${CurrencyFormatter.formatNumber(b.actualUnits.round())} قطعة\n'
                'مسجلة على كود الفرع: ${CurrencyFormatter.formatNumber(direct.round())} قطعة\n'
                'موزعة من مسحوبات الإقليم بنسبة المستهدف: '
                '${CurrencyFormatter.formatNumber(b.actualAllocatedUnits.round())} قطعة'
            : '${CurrencyFormatter.formatNumber(b.actualUnits.round())} قطعة';

    final cells = <Widget>[
      _cap(
        _branchCaps,
        0,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 18.0,
              color: cs.primary,
            ),
            const SizedBox(width: 2.0),
            Flexible(
              child: Tooltip(
                message: b.branchName,
                child: Text(
                  b.branchName,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
      c(1, TargetTableFormat.count(b.targetUnits),
          tip: '${CurrencyFormatter.formatNumber(b.targetUnits.round())} قطعة'),
      c(2, _casesText(b.targetCases), tip: _casesExact(b.targetCases)),
      c(3, has ? TargetTableFormat.count(b.actualUnits) : '—',
          key: ValueKey('sellin_branch_actual_${b.branchCode}'),
          tip: actualTip,
          style: has
              ? TextStyle(fontWeight: FontWeight.w800, color: cs.primary)
              : TextStyle(color: cs.onSurfaceVariant)),
      c(4, has ? '${b.achievementUnitsPct.toStringAsFixed(1)}%' : '—',
          key: ValueKey('sellin_branch_qty_pct_${b.branchCode}'),
          tip: has ? b.statusAr : null,
          style: has
              ? TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _pctColor(context, b.achievementUnitsPct))
              : TextStyle(color: cs.onSurfaceVariant)),
      c(5, TargetTableFormat.moneyNumber(b.targetRevenueEgp),
          tip: TargetTableFormat.moneyExact(b.targetRevenueEgp)),
      c(6, has ? TargetTableFormat.moneyNumber(b.actualRevenueEgp) : '—',
          key: ValueKey('sellin_branch_actual_value_${b.branchCode}'),
          tip: has ? TargetTableFormat.moneyExact(b.actualRevenueEgp) : null,
          style: has
              ? TextStyle(color: cs.primary)
              : TextStyle(color: cs.onSurfaceVariant)),
      c(7,
          has && b.targetRevenueEgp > 0
              ? '${b.achievementRevPct.toStringAsFixed(1)}%'
              : '—',
          key: ValueKey('sellin_branch_value_pct_${b.branchCode}'),
          style: has && b.targetRevenueEgp > 0
              ? TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _pctColor(context, b.achievementRevPct))
              : TextStyle(color: cs.onSurfaceVariant)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1.0, color: cs.outlineVariant.withOpacity(0.4)),
        Material(
          color: open
              ? cs.primaryContainer.withOpacity(0.28)
              : Colors.transparent,
          child: Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              key: ValueKey('sellin_branch_${b.branchCode}_${b.branchName}'),
              onTap: () => setState(() {
                if (!_expandedBranches.remove(id)) _expandedBranches.add(id);
              }),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44.0),
                padding: const EdgeInsets.symmetric(
                    horizontal: M3Spacing.xxs, vertical: M3Spacing.xxs),
                child: _branchCells(cells),
              ),
            ),
          ),
        ),
        if (open) _buildBranchSkus(context, t, b),
      ],
    );
  }

  Widget _buildBranchSkus(BuildContext context, TargetComparisonModel t,
      TargetBranchBreakdownModel b) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final id = _branchId(b);
    final skus = SellInTargetsExport.branchSkus(b, brands: _brands);
    final showAll = _branchShowAll.contains(id);
    final shown = showAll ? skus : skus.take(_skuPreview).toList();
    return Container(
      key: ValueKey('sellin_branch_skus_${b.branchCode}'),
      padding: const EdgeInsetsDirectional.fromSTEB(
          M3Spacing.sm, M3Spacing.xs, M3Spacing.sm, M3Spacing.sm),
      color: cs.primaryContainer.withOpacity(0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: M3Spacing.sm,
            runSpacing: M3Spacing.xs,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('أصناف ${b.branchName} (${skus.length})',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              OutlinedButton.icon(
                key: ValueKey('sellin_branch_export_${b.branchCode}'),
                onPressed:
                    skus.isEmpty ? null : () => _exportBranches(t, branch: b),
                icon: const Icon(Icons.table_view_rounded,
                    size: M3ToolbarButton.iconSize),
                label: const Text('تصدير الفرع'),
                style: M3ToolbarButton.style,
              ),
            ],
          ),
          const SizedBox(height: M3Spacing.xs),
          if (skus.isEmpty)
            Text('لا توجد أصناف لهذا الفرع.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant))
          else
            _table(
              key: ValueKey('sellin_branch_skus_table_${b.branchCode}'),
              caps: _skuCaps,
              headers: _skuHeaders,
              rows: _skuRows(context, shown,
                  hasActuals: SellInTargetsExport.branchHasActuals(b),
                  keyPrefix: 'sellin_branch_sku_${b.branchCode}'),
            ),
          if (skus.length > _skuPreview)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: ValueKey('sellin_branch_skus_toggle_${b.branchCode}'),
                onPressed: () => setState(() {
                  if (!_branchShowAll.remove(id)) _branchShowAll.add(id);
                }),
                child: Text(showAll
                    ? 'عرض أول $_skuPreview صنف فقط'
                    : 'عرض كل الأصناف (${skus.length})'),
              ),
            ),
        ],
      ),
    );
  }

  /// SKU rows (chain totals or one branch): name + code, brand, quantity
  /// first, then value. A missing cost price is flagged, never estimated.
  List<DataRow> _skuRows(
    BuildContext context,
    List<TargetSKUBreakdownModel> skus, {
    required bool hasActuals,
    required String keyPrefix,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final caution = M3StatusColors.of(context).accents.caution;
    return skus.map((s) {
      final has = hasActuals;
      Widget c(int i, String x, {String? tip, TextStyle? style}) =>
          _line(_skuCaps, i, x, tooltip: tip, style: style);
      final brand = SellInTargetsExport.brandOf(s);
      final code = s.itemCode.trim();
      final qtyPct = has && s.targetUnits > 0
          ? s.actualUnits / s.targetUnits * 100
          : null;
      final valPct = has && !s.costMissing && s.targetRevenueEgp > 0
          ? s.actualRevenueEgp / s.targetRevenueEgp * 100
          : null;
      final dim = TextStyle(color: cs.onSurfaceVariant);
      return DataRow(
        key: ValueKey('${keyPrefix}_${s.itemCode}_${s.skuName}'),
        cells: [
          DataCell(Center(
            child: _cap(
              _skuCaps,
              0,
              Tooltip(
                message: code.isEmpty ? s.skuName : '${s.skuName}\n$code',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.skuName,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (code.isNotEmpty)
                      Text(code,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          )),
          DataCell(Center(
              child: c(1, brand,
                  tip: brand, style: brand == kNoBrandLabelAr ? dim : null))),
          DataCell(Center(
              child: c(2, TargetTableFormat.count(s.targetUnits),
                  tip:
                      '${CurrencyFormatter.formatNumber(s.targetUnits.round())} قطعة'))),
          DataCell(Center(
              child: c(3, s.packSizeMissing ? '—' : _casesText(s.targetCases),
                  tip: s.packSizeMissing
                      ? 'لا يوجد حجم عبوة في Product Master'
                      : _casesExact(s.targetCases)))),
          DataCell(Center(
              child: c(4, has ? TargetTableFormat.count(s.actualUnits) : '—',
                  tip: has
                      ? '${CurrencyFormatter.formatNumber(s.actualUnits.round())} قطعة'
                      : null))),
          DataCell(Center(
              child: c(5, qtyPct == null ? '—' : '${qtyPct.toStringAsFixed(1)}%',
                  style: qtyPct == null
                      ? null
                      : TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _pctColor(context, qtyPct))))),
          DataCell(Center(
            child: s.costMissing
                ? Tooltip(
                    key: ValueKey('${keyPrefix}_cost_missing_${s.itemCode}'),
                    message:
                        'لا يوجد سعر تكلفة في Product Master — القيمة غير مقدّرة',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 14.0, color: caution),
                        const SizedBox(width: 2.0),
                        Text('—', style: dim),
                      ],
                    ),
                  )
                : c(6, TargetTableFormat.moneyNumber(s.targetRevenueEgp),
                    tip: TargetTableFormat.moneyExact(s.targetRevenueEgp)),
          )),
          DataCell(Center(
              child: c(
                  7,
                  has && !s.costMissing
                      ? TargetTableFormat.moneyNumber(s.actualRevenueEgp)
                      : '—',
                  tip: has && !s.costMissing
                      ? TargetTableFormat.moneyExact(s.actualRevenueEgp)
                      : null))),
          DataCell(Center(
              child: c(
                  8, valPct == null ? '—' : '${valPct.toStringAsFixed(1)}%',
                  style: valPct == null
                      ? null
                      : TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _pctColor(context, valPct))))),
        ],
      );
    }).toList();
  }
}

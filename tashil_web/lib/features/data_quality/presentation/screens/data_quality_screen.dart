import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/data/data_refresh_mixin.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/theme/m3_status_colors.dart';
import '../../../../core/theme/m3_typography.dart';
import '../../../../core/utils/arabic_plural.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/atomic_numeric_text.dart';
import '../../../../core/widgets/hyphenated_code_text.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_button_group.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_search_field.dart';
import '../../../../core/widgets/m3_states.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../../../core/widgets/m3_tonal_surface.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../../customer_registry/presentation/pending_customers_screen.dart';
import '../../../product_match/presentation/screens/product_match_review_screen.dart';
import '../../../sellin_assist/presentation/sellin_assist_screen.dart';
import '../../data/data_quality_repository.dart';

String _d(DateTime? t) => t == null
    ? ''
    : '${t.toLocal().year}-${t.toLocal().month.toString().padLeft(2, '0')}-${t.toLocal().day.toString().padLeft(2, '0')}';

/// "الأخطاء": per-tenant data-quality issues. Auto-refreshes when the backend re-runs checks.
class DataQualityScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final DataQualityDataSource? dataSource;
  final Duration pollInterval;

  const DataQualityScreen({
    super.key,
    this.apiClient,
    this.dataSource,
    this.pollInterval = const Duration(seconds: 30),
  }) : assert(apiClient != null || dataSource != null);

  @override
  State<DataQualityScreen> createState() => _DataQualityScreenState();
}

class _DataQualityScreenState extends State<DataQualityScreen>
    with DataRefreshMixin<DataQualityScreen> {
  @override
  void onBackendDataChanged() {
    _load();
  }

  late final DataQualityDataSource _repo =
      widget.dataSource ?? DataQualityRepository(widget.apiClient!);
  DataQualitySummary _summary = const DataQualitySummary();
  List<DataQualityIssue> _issues = const [];
  DataQualityFilter _filter = const DataQualityFilter();
  bool _loading = true;
  String? _error;
  DateTime? _version;
  Timer? _poll;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(widget.pollInterval, (_) => _checkForUpdates());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _repo.summary();
      final i = await _repo.issues(_filter);
      if (!mounted) return;
      setState(() {
        _summary = s;
        _issues = i;
        _version = s.updatedAt;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final s = await _repo.summary();
      if (!mounted || s.updatedAt == _version) return;
      final i = await _repo.issues(_filter);
      if (!mounted) return;
      setState(() {
        _summary = s;
        _issues = i;
        _version = s.updatedAt;
      });
    } catch (_) {}
  }

  void _setFilter(DataQualityFilter f) {
    _filter = f;
    _load();
  }

  List<DataQualityIssue> get _visibleIssues {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _issues;
    bool hit(DataQualityIssue i) => [
          i.itemName,
          i.itemCode,
          i.barcode,
          i.typeLabel,
          i.foundValue,
          i.expectedValue,
          i.sheet,
          dqSourceLabel(i.source),
        ].any((s) => s.toLowerCase().contains(q));
    return _issues.where(hit).toList();
  }

  Future<void> _changeStatus(DataQualityIssue issue) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _StatusDialog(issue: issue),
    );
    if (result == null) return;
    try {
      await _repo.updateStatus(issue.id, result.$1, result.$2);
      await _load();
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, e.toString());
    }
  }

  void _export() {
    final csv = ExcelExportService.generateCsv(
      headers: const [
        'المصدر',
        'النوع',
        'الخطورة',
        'الشيت',
        'الصف',
        'العمود',
        'كود الصنف',
        'الباركود',
        'اسم الصنف',
        'القيمة الموجودة',
        'القيمة المتوقعة',
        'التأثير (ج.م)',
        'الحالة',
        'السبب',
        'أول ظهور',
        'تاريخ الحل',
      ],
      rows: _visibleIssues
          .map((i) => [
                dqSourceLabel(i.source),
                i.typeLabel,
                i.severity,
                i.sheet,
                i.row,
                i.column,
                i.itemCode,
                i.barcode,
                i.itemName,
                i.foundValue,
                i.expectedValue,
                i.impactEgp?.toStringAsFixed(2) ?? '',
                i.status,
                i.statusReason,
                _d(i.firstSeen),
                _d(i.resolvedAt),
              ])
          .toList(),
    );
    ExcelExportService.downloadCsv('data_quality_issues.csv', csv);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visibleIssues;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: M3ToolbarButtonTheme(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: M3Spacing.pMd,
            children: [
              _Header(
                apiClient: widget.apiClient,
                canExport: visible.isNotEmpty,
                onRefresh: _load,
                onExport: _export,
              ),
              M3Spacing.gapSM,
              if (_error != null)
                M3ErrorState(
                  title: 'تعذر تحميل الأخطاء',
                  message: _error,
                  onRetry: _load,
                ),
              _SummaryRow(summary: _summary),
              M3Spacing.gapSM,
              _Filters(
                summary: _summary,
                filter: _filter,
                searchController: _searchController,
                searchQuery: _searchQuery,
                onSearch: (v) => setState(() => _searchQuery = v),
                onChanged: _setFilter,
              ),
              const SizedBox(height: M3Spacing.s12),
              if (_loading)
                const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: CircularProgressIndicator()))
              else if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Center(
                    child: Text(
                      'لا توجد أخطاء مطابقة للفلاتر',
                      key: const ValueKey('dq_empty'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                )
              else
                _IssuesTable(issues: visible, onChangeStatus: _changeStatus),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ApiClient? apiClient;
  final bool canExport;
  final VoidCallback onRefresh;
  final VoidCallback onExport;
  const _Header({
    required this.apiClient,
    required this.canExport,
    required this.onRefresh,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return M3PageHeader(
      titleEn: 'Errors',
      subtitleAr: 'الأخطاء وجودة البيانات',
      actions: M3ButtonGroup(
        maxVisibleCompact: 2,
        items: [
          M3GroupItem(
            key: const ValueKey('dq_refresh'),
            label: 'تحديث',
            icon: AppIcons.refresh,
            kind: M3GroupItemKind.tonal,
            tooltip: 'تحديث',
            onPressed: onRefresh,
          ),
          if (apiClient != null)
            M3GroupItem(
              key: const ValueKey('dq_pending_customers'),
              label: 'عملاء معلّقون',
              icon: AppIcons.pendingCustomers,
              kind: M3GroupItemKind.tonal,
              tooltip: 'عملاء محتاجين تأكيد',
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PendingCustomersScreen(apiClient: apiClient),
              )),
            ),
          if (apiClient != null)
            M3GroupItem(
              key: const ValueKey('dq_sellin_assist'),
              label: 'مساعدة التوريد',
              icon: AppIcons.sellInAssist,
              kind: M3GroupItemKind.tonal,
              tooltip: 'مساعدة Gemini للتوريد',
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SellInAssistScreen(apiClient: apiClient),
              )),
            ),
          if (apiClient != null)
            M3GroupItem(
              key: const ValueKey('dq_product_match_review'),
              label: 'مطابقة الأصناف',
              icon: AppIcons.productMatchReview,
              kind: M3GroupItemKind.tonal,
              tooltip: 'مراجعة مطابقة الأصناف',
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    ProductMatchReviewScreen(apiClient: apiClient),
              )),
            ),
          M3GroupItem(
            key: const ValueKey('dq_export'),
            label: 'تصدير Excel/CSV',
            icon: AppIcons.download,
            kind: M3GroupItemKind.tonal,
            onPressed: canExport ? onExport : null,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final DataQualitySummary summary;
  const _SummaryRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Defensive empty-state UI. Backend row totals when Runs are missing are
    // fixed in PR #86 / TDS-76 — keep this guard so 0 rows never show 100%.
    final hasRows = summary.totalRows > 0;
    final cleanlinessValue =
        hasRows ? '${summary.cleanlinessPct.toStringAsFixed(1)}%' : '—';
    // Display-only clarification: formula is critical-rows only
    // ((total − critical) / total). Open warnings do not lower it.
    // Short on-card (≤1 line at 1024/4-col); full wording in tooltip.
    final cleanlinessSubtitle = hasRows
        ? 'حرجة فقط — ${summary.criticalRows} حرجة'
        : 'مفيش صفوف اتفحصت';
    final cleanlinessSubtitleTooltip = hasRows
        ? 'محسوبة على الأخطاء الحرجة فقط — ${summary.criticalRows} حرجة'
        : null;
    final openSubtitle = countError(summary.open);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = M3KpiGridColumns.forWidthAndCount(
              constraints.maxWidth,
              4,
            );
            return M3EqualHeightGrid(
              key: const ValueKey('dq_kpi_grid'),
              columns: columns,
              spacing: M3Spacing.sm,
              runSpacing: M3Spacing.sm,
              children: [
                M3SummaryKpiCard(
                  key: const ValueKey('dq_cleanliness_card'),
                  valueKey: const ValueKey('dq_cleanliness'),
                  subtitleKey: const ValueKey('dq_cleanliness_subtitle'),
                  title: 'نظافة البيانات',
                  titleMaxLines: 2,
                  subtitleMaxLines: 1,
                  value: cleanlinessValue,
                  subtitle: cleanlinessSubtitle,
                  subtitleTooltip: cleanlinessSubtitleTooltip,
                  icon: AppIcons.verified,                  color: !hasRows
                      ? cs.onSurfaceVariant
                      : (summary.cleanlinessPct >= 95
                          ? cs.primary
                          : (summary.cleanlinessPct >= 85
                              ? cs.tertiary
                              : cs.error)),
                ),
                M3SummaryKpiCard(
                  key: const ValueKey('dq_open_card'),
                  valueKey: const ValueKey('dq_value_open'),
                  titleKey: const ValueKey('dq_title_open'),
                  title: 'مفتوحة',
                  titleMaxLines: 2,
                  subtitleMaxLines: 1,
                  value: CurrencyFormatter.formatNumber(summary.open),
                  subtitle: openSubtitle,
                  icon: AppIcons.error,
                  color: cs.error,
                ),
                M3SummaryKpiCard(
                  key: const ValueKey('dq_resolved_card'),
                  valueKey: const ValueKey('dq_value_resolved'),
                  title: 'اتصلّحت',
                  titleMaxLines: 2,
                  subtitleMaxLines: 1,
                  value: CurrencyFormatter.formatNumber(summary.resolved),
                  subtitle: countError(summary.resolved),
                  icon: AppIcons.verified,
                  color: cs.primary,
                ),
                M3SummaryKpiCard(
                  key: const ValueKey('dq_ignored_card'),
                  valueKey: const ValueKey('dq_value_ignored'),
                  title: 'متجاهلة',
                  titleMaxLines: 2,
                  subtitleMaxLines: 1,
                  value: CurrencyFormatter.formatNumber(summary.ignored),
                  subtitle: countError(summary.ignored),
                  icon: AppIcons.block,
                  color: cs.onSurfaceVariant,
                ),
              ],
            );
          },
        ),
        if (summary.types.where((t) => t.total > 0).isNotEmpty) ...[
          M3Spacing.gapSM,
          // Same tonal strip geometry as filter toolbars / other pages —
          // chips must not float bare under the KPI row.
          M3TonalSurface(
            key: const ValueKey('dq_type_summary_strip'),
            color: cs.surfaceContainerLow,
            borderRadius: M3Shape.radiusMd,
            padding: const EdgeInsets.all(M3Spacing.s12),
            child: _TypeChips(
              types: summary.types.where((t) => t.total > 0).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _TypeChips extends StatelessWidget {
  final List<DataQualityTypeSummary> types;
  const _TypeChips({required this.types});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Wrap(
      spacing: M3Spacing.sm,
      runSpacing: M3Spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        for (final t in types)
          ConstrainedBox(
            // minWidth keeps the type description from shrink-wrapping to
            // the short chip («ناقص») so «صنف مش موجود…» can use ≤3 lines.
            constraints: const BoxConstraints(minWidth: 168.0, maxWidth: 280.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                M3ChipSurface(
                  key: ValueKey('dq_type_chip_${t.type}'),
                  color: t.severity == kDqCritical
                      ? cs.errorContainer
                      : cs.tertiaryContainer,
                  child: Text(
                    dqTypeShort(t.type, t.typeLabel),
                    maxLines: 3,
                    softWrap: true,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: M3FontSize.labelSmallPlus,
                      fontWeight: FontWeight.w800,
                      color: t.severity == kDqCritical
                          ? cs.onErrorContainer
                          : cs.onTertiaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: M3Spacing.xxs),
                Text(
                  t.typeLabel,
                  key: ValueKey('dq_type_desc_${t.type}'),
                  maxLines: 3,
                  softWrap: true,
                  overflow: TextOverflow.clip,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  [
                    countError(t.open),
                    if (t.impactEgp > 0)
                      CurrencyFormatter.formatCompactEGP(t.impactEgp),
                  ].join(' · '),
                  key: ValueKey('dq_type_meta_${t.type}'),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.clip,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  final DataQualitySummary summary;
  final DataQualityFilter filter;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearch;
  final ValueChanged<DataQualityFilter> onChanged;
  const _Filters({
    required this.summary,
    required this.filter,
    required this.searchController,
    required this.searchQuery,
    required this.onSearch,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final types = <String, String>{
      for (final t in summary.types) t.type: t.typeLabel
    };
    final sources = <String>{for (final t in summary.types) t.source};
    const searchHint = 'بحث بالصنف أو الكود أو الباركود أو النوع...';
    final searchField = M3SearchFieldWidth(
      hintText: searchHint,
      child: TextField(
        key: const ValueKey('dq_search'),
        controller: searchController,
        onChanged: onSearch,
        decoration: InputDecoration(
          hintText: searchHint,
          prefixIcon: const Icon(Icons.search_rounded, size: 20.0),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18.0),
                  onPressed: () {
                    searchController.clear();
                    onSearch('');
                  },
                )
              : null,
        ),
      ),
    );
    final dropdowns = [
      M3Dropdown<String>(
        key: const ValueKey('dq_filter_status'),
        label: 'الحالة',
        width: 170.0,
        fitOptions: true,
        value: filter.status,
        options: const [
          M3DropdownOption('', kDqOpen),
          M3DropdownOption(kDqResolved, kDqResolved),
          M3DropdownOption(kDqIgnored, kDqIgnored),
          M3DropdownOption('all', 'الكل'),
        ],
        onChanged: (v) => onChanged(filter.copyWith(status: v)),
      ),
      M3Dropdown<String>(
        key: const ValueKey('dq_filter_severity'),
        label: 'الخطورة',
        width: 150.0,
        fitOptions: true,
        value: filter.severity,
        options: const [
          M3DropdownOption('', 'الكل'),
          M3DropdownOption(kDqCritical, kDqCritical),
          M3DropdownOption(kDqWarning, kDqWarning),
        ],
        onChanged: (v) => onChanged(filter.copyWith(severity: v)),
      ),
      M3Dropdown<String>(
        key: const ValueKey('dq_filter_source'),
        label: 'المصدر',
        width: 170.0,
        fitOptions: true,
        value: filter.source,
        options: [
          const M3DropdownOption('', 'الكل'),
          for (final s in sources) M3DropdownOption(s, dqSourceLabel(s)),
        ],
        onChanged: (v) => onChanged(filter.copyWith(source: v)),
      ),
      M3Dropdown<String>(
        key: const ValueKey('dq_filter_type'),
        label: 'النوع',
        width: 240.0,
        fitOptions: true,
        value: filter.type,
        options: [
          const M3DropdownOption('', 'الكل'),
          for (final e in types.entries) M3DropdownOption(e.key, e.value),
        ],
        onChanged: (v) => onChanged(filter.copyWith(type: v)),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 1100.0;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: M3Spacing.xs),
              Wrap(
                  spacing: M3Spacing.xs,
                  runSpacing: M3Spacing.xs,
                  children: dropdowns),
            ],
          );
        }
        return Wrap(
          spacing: M3Spacing.xs,
          runSpacing: M3Spacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [searchField, ...dropdowns],
        );
      },
    );
  }
}

class _IssuesTable extends StatelessWidget {
  // Headers and cells centred in every column (including اسم الصنف).
  // Pixel budget at the live 1030 shell (page padding 24, inner ~934
  // after xxs gutters), measured with real Cairo bodyMedium:
  //  - short words (الخطورة, مفتوحة, متجاهلة) never mid-word split
  //  - item codes stay on ONE line. Live v157 wrapped QA-NOT-IN-MASTER-999
  //    at flex 158: real Cairo bodyMedium advance is 159.7dp, not the
  //    earlier 154.7dp, so a 158.7dp column had no slack. Flex 178
  //    (178/930×934 ≈ 178.7dp) leaves ≥16dp slack.
  //  - Name (centered) needs ≥250dp for the live long SKU in ≤3 lines
  //    (233dp still didExceedMaxLines). Flex 256 ≈ 256/954×934 ≈ 250.6dp.
  //  - Type label «صنف مش موجود في كارتة الأصناف» exceeds 3 lines at
  //    ~80dp; flex 104 ≈ 104dp. Status stays 72 so «متجاهلة»+chip pad fits.
  //  - expected must fit the live phrase «الصنف يتضاف لكارتة الأصناف»
  //    in ≤3 lines. The wrapping bottleneck is «يتضاف لكارتة» (74.2dp);
  //    v158's flex 72 (72.3dp) clipped «الأصناف». Flex 88 (88.4dp) leaves
  //    ~14dp slack. Type/name share comes from severity / row / barcode /
  //    found / status / actions, which have slack beyond short chips.
  //  - Arabic space-separated "codes" wrap at words, ≤3 lines (see
  //    HyphenatedCodeText); they must not clip mid-word.
  //  - at 1024+sidebar (inner ~678) one-line SKUs plus the name floor
  //    cannot both fit, so hyphenated codes may wrap at '-' only
  // Shares ≈ dp at the live ~934 inner width (sum 936).
  static const _flex = [
    52.0, // الخطورة ≥46.5 one-line
    104.0, // type «صنف مش موجود…» ≤3 (80dp exceeded)
    36.0, // الصف
    178.0, // item code one-line floor
    36.0, // barcode
    256.0, // name centered ≥250
    50.0, // الموجود ≥47.8
    88.0, // expected
    36.0, // impact compact
    72.0, // status chip «متجاهلة» + 16dp pad
    28.0, // row actions
  ];

  final List<DataQualityIssue> issues;
  final ValueChanged<DataQualityIssue> onChangeStatus;
  const _IssuesTable({required this.issues, required this.onChangeStatus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = M3Spacing.xxs;
        const margin = M3Spacing.xxs;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final flexSum = _flex.fold<double>(0, (a, b) => a + b);
        final inner =
            availableWidth - (2 * margin) - ((_flex.length - 1) * spacing);
        // No per-column min clamp: 11 columns at the live 1030 content
        // width (minus page padding) cannot all be ≥56 without overflowing.
        double colMax(int i) => inner * _flex[i] / flexSum;
        // Tight width (not ConstrainedBox-as-max): DataTable otherwise
        // sizes from the one-line intrinsic width and horizontally scrolls.
        Widget cellBox(int i, Widget child) => SizedBox(
              width: colMax(i),
              child: child,
            );
        Widget cellText(int i, String text,
            {Key? key, TextAlign align = TextAlign.center}) {
          return cellBox(
            i,
            Text(
              text,
              key: key,
              maxLines: 3,
              overflow: TextOverflow.clip,
              textAlign: align,
              softWrap: true,
            ),
          );
        }

        // Short severity chip only (color encodes critical vs warning). An
        // in-chip icon steals width from the 52-flex column and mid-splits
        // «تحذير» / «حرجة» at the live 1030 shell. Status column already
        // uses short chip + description underneath.
        Widget wrapSeverity(int i, String label,
            {required Color color, required Color onColor}) {
          return cellBox(
            i,
            M3ChipSurface(
              color: color,
              child: Text(
                label,
                maxLines: 3,
                softWrap: true,
                overflow: TextOverflow.clip,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: onColor,
                  fontSize: M3FontSize.labelSmallPlus,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        }

        // Type: short chip + full label underneath (TM / summary-chip pattern).
        // Centered in the cell with vertical/horizontal padding so the
        // ≤3-line description never hugs the row edges. UnconstrainedBox
        // keeps the chip at intrinsic width so short words never mid-split
        // inside the 104-flex column.
        Widget wrapType(int i, DataQualityIssue issue) {
          return cellBox(
            i,
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: M3Spacing.xxs,
                vertical: M3Spacing.xs,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  UnconstrainedBox(
                    child: M3ChipSurface(
                      color: cs.surfaceContainerLowest,
                      borderColor: cs.outlineVariant,
                      child: Text(
                        dqTypeShort(issue.type, issue.typeLabel),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: M3FontSize.labelSmallPlus,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: M3Spacing.xxs),
                  Text(
                    issue.typeLabel,
                    maxLines: 3,
                    softWrap: true,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final columns = [
          DataColumn(
              headingRowAlignment: MainAxisAlignment.center,
              label: cellText(0, 'الخطورة')),
          DataColumn(
              headingRowAlignment: MainAxisAlignment.center,
              label: cellText(1, 'النوع')),
          DataColumn(
              headingRowAlignment: MainAxisAlignment.center,
              label: cellText(2, 'الصف')),
          DataColumn(
              headingRowAlignment: MainAxisAlignment.center,
              label: cellText(3, 'كود الصنف')),
          DataColumn(
              headingRowAlignment: MainAxisAlignment.center,
              label: cellText(4, 'الباركود')),
          DataColumn(
              headingRowAlignment: MainAxisAlignment.center,
              label: cellText(5, 'اسم الصنف')),
          DataColumn(
              headingRowAlignment: MainAxisAlignment.center,
              label: cellText(6, 'الموجود')),
          DataColumn(
              headingRowAlignment: MainAxisAlignment.center,
              label: cellText(7, 'المتوقع')),
          DataColumn(
              headingRowAlignment: MainAxisAlignment.center,
              numeric: true,
              label: cellText(8, 'التأثير')),
          DataColumn(
              headingRowAlignment: MainAxisAlignment.center,
              label: cellText(9, 'الحالة')),
          DataColumn(
              headingRowAlignment: MainAxisAlignment.center,
              label: cellBox(10, const SizedBox.shrink())),
        ];

        return SizedBox(
          width: availableWidth,
          child: TableScrollContainer(
            key: const ValueKey('dq_table_scroll'),
            showSwipeHint: true,
            columnFlex: _flex,
            child: DataTable(
              key: const ValueKey('dq_table'),
              columnSpacing: spacing,
              horizontalMargin: margin,
              // Chip (32) + gap + ≤3-line description + vertical pad.
              dataRowMinHeight: 72.0,
              dataRowMaxHeight: double.infinity,
              headingRowHeight: 72.0,
              headingTextStyle: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
              columns: columns,
              rows: centerCellsUnderCenteredHeadings(
                columns,
                issues.map((i) {
                  final critical = i.severity == kDqCritical;
                  final statusDesc = [
                    if (i.autoClosed) 'تلقائي',
                    if (i.statusReason.isNotEmpty) i.statusReason,
                  ].join(' · ');
                  return DataRow(cells: [
                    DataCell(wrapSeverity(
                      0,
                      i.severity,
                      color:
                          critical ? cs.errorContainer : cs.tertiaryContainer,
                      onColor: critical
                          ? cs.onErrorContainer
                          : cs.onTertiaryContainer,
                    )),
                    DataCell(wrapType(1, i)),
                    DataCell(cellText(
                      2,
                      i.row > 0
                          ? '${i.row}${i.column.isNotEmpty ? ' · ${i.column}' : ''}'
                          : '',
                    )),
                    DataCell(cellBox(
                      3,
                      HyphenatedCodeText(
                        i.itemCode,
                        key: ValueKey('dq_item_code_${i.itemCode}'),
                      ),
                    )),
                    DataCell(cellText(4, i.barcode)),
                    DataCell(cellText(5, i.itemName,
                        key: const ValueKey('dq_item_name'))),
                    DataCell(cellText(6, i.foundValue)),
                    DataCell(cellText(7, i.expectedValue)),
                    DataCell(cellBox(
                      8,
                      AtomicNumericText(
                        i.impactEgp == null
                            ? '—'
                            : CurrencyFormatter.formatCompactEGP(i.impactEgp!),
                        maxWidth: colMax(8),
                        textAlign: TextAlign.center,
                      ),
                    )),
                    DataCell(cellBox(
                      9,
                      Builder(builder: (context) {
                        final status = M3StatusColors.of(context);
                        final (Color bg, Color fg) = i.status == kDqOpen
                            ? (cs.errorContainer, cs.onErrorContainer)
                            : (i.status == kDqResolved
                                ? (
                                    status.successContainer,
                                    status.onSuccessContainer
                                  )
                                : (
                                    cs.surfaceContainerLowest,
                                    cs.onSurfaceVariant
                                  ));
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            M3ChipSurface(
                              color: bg,
                              borderColor: i.status == kDqIgnored
                                  ? cs.outlineVariant
                                  : null,
                              child: Text(
                                i.status,
                                maxLines: 3,
                                softWrap: true,
                                overflow: TextOverflow.clip,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: fg,
                                  fontSize: M3FontSize.labelSmallPlus,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (statusDesc.isNotEmpty)
                              Text(
                                statusDesc,
                                maxLines: 3,
                                overflow: TextOverflow.clip,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        );
                      }),
                    )),
                    DataCell(cellBox(
                      10,
                      IconButton(
                        key: ValueKey('dq_status_${i.id}'),
                        tooltip: 'تغيير الحالة',
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(40, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(AppIcons.edit, size: 18.0),
                        onPressed: () => onChangeStatus(i),
                      ),
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusDialog extends StatefulWidget {
  final DataQualityIssue issue;
  const _StatusDialog({required this.issue});
  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  late String _status = widget.issue.status == kDqOpen ? kDqIgnored : kDqOpen;
  final _reason = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: M3ToolbarButtonTheme(
        child: AlertDialog(
          title: const Text('تغيير حالة الخطأ'),
          content: SizedBox(
            width: 380.0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${widget.issue.typeLabel} — ${widget.issue.itemCode}',
                  maxLines: 3,
                  softWrap: true,
                  overflow: TextOverflow.clip,
                ),
                if (widget.issue.itemName.isNotEmpty) ...[
                  const SizedBox(height: M3Spacing.xs),
                  Text(
                    widget.issue.itemName,
                    maxLines: 3,
                    softWrap: true,
                    overflow: TextOverflow.clip,
                  ),
                ],
                M3Spacing.gapSM,
                M3Dropdown<String>(
                  key: const ValueKey('dq_status_select'),
                  label: 'الحالة الجديدة',
                  expand: true,
                  fitOptions: true,
                  value: _status,
                  options: const [
                    M3DropdownOption(kDqOpen, kDqOpen),
                    M3DropdownOption(kDqResolved, kDqResolved),
                    M3DropdownOption(kDqIgnored, kDqIgnored),
                  ],
                  onChanged: (v) => setState(() => _status = v),
                ),
                const SizedBox(height: M3Spacing.s12),
                TextField(
                  key: const ValueKey('dq_status_reason'),
                  controller: _reason,
                  maxLines: 3,
                  decoration:
                      InputDecoration(labelText: 'السبب', errorText: _err),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
              key: const ValueKey('dq_status_save'),
              onPressed: () {
                final r = _reason.text.trim();
                if (_status == kDqIgnored && r.isEmpty) {
                  setState(() => _err = 'السبب مطلوب عند التجاهل');
                  return;
                }
                Navigator.pop(context, (_status, r));
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

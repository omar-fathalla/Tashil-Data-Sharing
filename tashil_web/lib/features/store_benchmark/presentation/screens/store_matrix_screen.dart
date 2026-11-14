import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_palette.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../data/store_benchmark_repository.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/arabic_plural.dart';
import '../../../../core/utils/shared_display_prefix.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_search_field.dart';
import '../../../../core/widgets/m3_section_title.dart';
import '../../../../core/widgets/m3_segmented_button_group.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../../../core/data/data_refresh_mixin.dart';

/// StoreMatrixScreen displays store benchmarking across Egyptian retail regions,
/// tier categorization (Tier A/B/C), and sales velocity metrics.
class StoreMatrixScreen extends StatefulWidget {
  final ApiClient apiClient;

  /// Optional injected repository (tests); defaults to one wrapping [apiClient].
  final StoreBenchmarkRepository? repository;

  const StoreMatrixScreen({
    super.key,
    required this.apiClient,
    this.repository,
  });

  @override
  State<StoreMatrixScreen> createState() => _StoreMatrixScreenState();
}

class _StoreMatrixScreenState extends State<StoreMatrixScreen>
    with DataRefreshMixin<StoreMatrixScreen> {
  @override
  void onBackendDataChanged() {
    _loadStoreMatrix();
  }

  bool _isLoading = true;
  late StoreBenchmarkRepository _repo;
  String _selectedRegion = 'الكل';
  String _selectedTier = 'الكل';
  int _selectedYear = 2026;
  int _selectedMonth = 0; // 0 = All months
  String _selectedChain =
      'all'; // 'all', 'fathalla', 'gomla', 'beet-elgomla', etc.
  List<StoreBenchmarkItem> _stores = [];

  /// Stable name list for display-only prefix stripping, so labels do not
  /// grow a prefix back when a region/tier filter returns a smaller set.
  final Set<String> _prefixNameCorpus = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const List<double> _tableColumnFlex = [
    0.45, // الترتيب
    2.2, // اسم الفرع
    1.0, // المنطقة
    0.9, // الفئة
    1.0, // المبيعات
    0.9, // الوحدات
    1.0, // السرعة
  ];
  static const double _tableHeadingHeight = 48.0;
  static const double _tableRowHeight = 120.0;

  List<StoreBenchmarkItem> get _visibleStores {
    final q = _searchQuery.trim();
    if (q.isEmpty) return _stores;
    bool matches(StoreBenchmarkItem s) {
      return s.storeName.contains(q) ||
          _displayStoreName(s).contains(q) ||
          s.region.contains(q) ||
          s.tier.contains(q) ||
          _getChainDisplayName(s.retailerChain).contains(q);
    }

    return _stores.where(matches).toList();
  }

  /// Display-only map: uses the shared prefix helper (multiple clusters,
  /// ≥2 names, typo-tolerant, never empty, never colliding). Never changes
  /// stored or uploaded data.
  Map<String, String> get _storeDisplayNames => displayNamesWithoutSharedPrefix(
        _prefixNameCorpus.isEmpty
            ? _stores.map((s) => s.storeName)
            : _prefixNameCorpus,
      );

  String _displayStoreName(StoreBenchmarkItem store) =>
      _storeDisplayNames[store.storeName] ?? store.storeName;

  final List<M3SegmentItem<String>> _regionSegments = const [
    M3SegmentItem(
      value: 'الكل',
      label: 'كافة المناطق',
      icon: Icons.public_rounded,
    ),
    M3SegmentItem(
      value: 'شرق الإسكندرية',
      label: 'شرق الإسكندرية',
      icon: Icons.location_city_rounded,
    ),
    M3SegmentItem(
      value: 'غرب الإسكندرية',
      label: 'غرب الإسكندرية',
      icon: Icons.location_on_rounded,
    ),
    M3SegmentItem(
      value: 'الدلتا والبحيرة',
      label: 'الدلتا والبحيرة',
      icon: Icons.map_rounded,
    ),
    M3SegmentItem(
      value: 'القاهرة الكبرى',
      label: 'القاهرة الكبرى',
      icon: Icons.apartment_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? StoreBenchmarkRepository(widget.apiClient);
    _lastTenantId = widget.apiClient.tenantId;
    _loadStoreMatrix();
  }

  late String _lastTenantId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StoreMatrixScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient ||
        _lastTenantId != widget.apiClient.tenantId) {
      _lastTenantId = widget.apiClient.tenantId;
      _repo = widget.repository ?? StoreBenchmarkRepository(widget.apiClient);
      _selectedRegion = 'الكل';
      _selectedTier = 'الكل';
      _selectedYear = 2026;
      _selectedMonth = 0;
      _selectedChain = 'all';
      _prefixNameCorpus.clear();
      _loadStoreMatrix();
    }
  }

  Future<void> _loadStoreMatrix({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    final result = await _repo.loadMatrix(
      region: _selectedRegion == 'الكل' ? null : _selectedRegion,
      tier: _selectedTier == 'الكل' ? null : _selectedTier,
      chain: _selectedChain == 'all' ? null : _selectedChain,
      year: _selectedYear == 0 ? null : _selectedYear,
      month: _selectedMonth == 0 ? null : _selectedMonth,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    result.when(
      success: (results) => setState(() {
        _stores = results;
        if (_selectedRegion == 'الكل' &&
            _selectedTier == 'الكل' &&
            _selectedChain == 'all') {
          _prefixNameCorpus
            ..clear()
            ..addAll(results.map((s) => s.storeName));
        } else {
          _prefixNameCorpus.addAll(results.map((s) => s.storeName));
        }

        _isLoading = false;
      }),
      failure: (error) {
        setState(() => _isLoading = false);
        M3Feedback.showError(
          context,
          'تعذر تحميل بيانات مقارنة الفروع: $error',
        );
      },
    );
  }

  void _onRegionChanged(String newRegion) {
    setState(() => _selectedRegion = newRegion);
    _loadStoreMatrix();
  }

  void _onTierFilterChanged(String newTier) {
    setState(() => _selectedTier = newTier);
    _loadStoreMatrix();
  }

  String get _activePeriodLabel {
    final yearPart = _selectedYear == 0 ? 'كافة السنوات' : 'عام $_selectedYear';
    String monthPart = '';
    if (_selectedMonth > 0) {
      const monthNames = [
        '',
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
      if (_selectedMonth < monthNames.length) {
        monthPart = ' - ${monthNames[_selectedMonth]}';
      }
    }
    String chainPart = '';
    if (_selectedChain != 'all') {
      chainPart = ' • ${_getChainDisplayName(_selectedChain)}';
    }
    return '$yearPart$monthPart$chainPart';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Aggregate Tier KPI stats from current stores (or national base)
    final visible = _visibleStores;
    final tierAStores = visible.where((s) => s.tier == 'Tier A').toList();
    final tierBStores = visible.where((s) => s.tier == 'Tier B').toList();
    final tierCStores = visible.where((s) => s.tier == 'Tier C').toList();

    final tierARevenue = tierAStores.fold<double>(
      0.0,
      (sum, s) => sum + s.totalRevenue,
    );
    final tierBRevenue = tierBStores.fold<double>(
      0.0,
      (sum, s) => sum + s.totalRevenue,
    );
    final tierCRevenue = tierCStores.fold<double>(
      0.0,
      (sum, s) => sum + s.totalRevenue,
    );

    final isCompactScreen = MediaQuery.sizeOf(context).width < 600.0;

    return M3ToolbarButtonTheme(
      child: SingleChildScrollView(
        padding: isCompactScreen ? M3Spacing.pSm : M3Spacing.pMd,
        child: M3ContentBoundary(
          maxWidth: 1440.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Section (Unified M3 Left English Title + Right Arabic Subtitle)
              M3PageHeader(
                titleEn: 'Store Matrix Benchmarking',
                subtitleAr:
                    'مقارنة الأداء المعياري وتصنيف الفروع إلى فئات (Tier A / B / C) ومعدلات سرعة البيع اليومية',
                actions: M3Button.tonal(
                  label: 'تحديث',
                  icon: Icons.refresh_rounded,
                  onPressed: _isLoading
                      ? null
                      : () => _loadStoreMatrix(forceRefresh: true),
                ),
              ),

              M3Spacing.gapMD,

              // Filter Toolbar (Temporal, Chain, Regional & Tier Selectors)
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: M3Shape.radiusLg,
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(
                    isCompactScreen ? M3Spacing.sm : M3Spacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Row 1: Time & Chain Dimensions (Year, Month, Chain)
                      Wrap(
                        spacing: M3Spacing.md,
                        runSpacing: M3Spacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Year Selector
                          _buildFilterDropdown<int>(
                            context: context,
                            label: 'السنة',
                            icon: Icons.calendar_today_rounded,
                            value: _selectedYear,
                            items: const [
                              DropdownMenuItem(
                                value: 0,
                                child: Text('كافة السنوات (إجمالي)'),
                              ),
                              DropdownMenuItem(
                                value: 2026,
                                child: Text('عام 2026'),
                              ),
                              DropdownMenuItem(
                                value: 2025,
                                child: Text('عام 2025'),
                              ),
                              DropdownMenuItem(
                                value: 2024,
                                child: Text('عام 2024'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null && val != _selectedYear) {
                                setState(() => _selectedYear = val);
                                _loadStoreMatrix();
                              }
                            },
                          ),

                          // Month Selector
                          _buildFilterDropdown<int>(
                            context: context,
                            label: 'الشهر',
                            icon: Icons.event_note_rounded,
                            value: _selectedMonth,
                            items: const [
                              DropdownMenuItem(
                                value: 0,
                                child: Text('كافة الشهور (إجمالي السنة)'),
                              ),
                              DropdownMenuItem(
                                value: 1,
                                child: Text('01 - يناير'),
                              ),
                              DropdownMenuItem(
                                value: 2,
                                child: Text('02 - فبراير'),
                              ),
                              DropdownMenuItem(
                                value: 3,
                                child: Text('03 - مارس'),
                              ),
                              DropdownMenuItem(
                                value: 4,
                                child: Text('04 - أبريل'),
                              ),
                              DropdownMenuItem(
                                value: 5,
                                child: Text('05 - مايو'),
                              ),
                              DropdownMenuItem(
                                value: 6,
                                child: Text('06 - يونيو'),
                              ),
                              DropdownMenuItem(
                                value: 7,
                                child: Text('07 - يوليو'),
                              ),
                              DropdownMenuItem(
                                value: 8,
                                child: Text('08 - أغسطس'),
                              ),
                              DropdownMenuItem(
                                value: 9,
                                child: Text('09 - سبتمبر'),
                              ),
                              DropdownMenuItem(
                                value: 10,
                                child: Text('10 - أكتوبر'),
                              ),
                              DropdownMenuItem(
                                value: 11,
                                child: Text('11 - نوفمبر'),
                              ),
                              DropdownMenuItem(
                                value: 12,
                                child: Text('12 - ديسمبر'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null && val != _selectedMonth) {
                                setState(() => _selectedMonth = val);
                                _loadStoreMatrix();
                              }
                            },
                          ),

                          // Chain Selector
                          _buildFilterDropdown<String>(
                            context: context,
                            label: 'السلسلة',
                            icon: Icons.storefront_rounded,
                            value: _selectedChain,
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text('كافة السلاسل'),
                              ),
                              DropdownMenuItem(
                                value: 'fathalla',
                                child: Text('أسواق فتح الله'),
                              ),
                              DropdownMenuItem(
                                value: 'gomla',
                                child: Text('جملة ماركت'),
                              ),
                              DropdownMenuItem(
                                value: 'beet-elgomla',
                                child: Text('بيت الجملة'),
                              ),
                              DropdownMenuItem(
                                value: 'carrefour',
                                child: Text('كارفور'),
                              ),
                              DropdownMenuItem(
                                value: 'spinneys',
                                child: Text('سبينيس'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null && val != _selectedChain) {
                                setState(() => _selectedChain = val);
                                _loadStoreMatrix();
                              }
                            },
                          ),
                        ],
                      ),

                      M3Spacing.gapSM,
                      M3SearchFieldWidth(
                        hintText: 'ابحث باسم الفرع أو السلسلة أو المنطقة...',
                        child: TextField(
                          key: const ValueKey('store_matrix_search'),
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText:
                                'ابحث باسم الفرع أو السلسلة أو المنطقة...',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 18.0,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                      size: 18.0,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            isDense: true,
                            filled: true,
                            fillColor: colorScheme.surface,
                            border: const OutlineInputBorder(
                              borderRadius: M3Shape.radiusMd,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 8.0,
                            ),
                            constraints: const BoxConstraints(
                              maxHeight: M3ToolbarButton.height,
                            ),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                      const Divider(height: 20.0),

                      // Row 2: Regional & Tier Selectors (Both M3 Connected Segmented Button Groups)
                      Wrap(
                        spacing: M3Spacing.sm,
                        runSpacing: M3Spacing.sm,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Regional Segmented Button
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تصفية حسب المنطقة الجغرافية:',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: M3Spacing.xs),
                              LayoutBuilder(
                                builder: (context, tabConstraints) {
                                  final maxW =
                                      tabConstraints.maxWidth.isFinite &&
                                              tabConstraints.maxWidth > 0
                                          ? tabConstraints.maxWidth
                                          : 280.0;
                                  return Wrap(
                                    spacing: M3Spacing.xs,
                                    runSpacing: M3Spacing.xs,
                                    children: [
                                      for (final s in _regionSegments)
                                        _filterTab(
                                          value: s.value,
                                          label: s.label,
                                          icon: s.icon ?? Icons.public_rounded,
                                          selected: _selectedRegion == s.value,
                                          onSelected: _onRegionChanged,
                                          maxWidth: maxW,
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),

                          // Tier Segmented Button Group
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'فئة الفرع:',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: M3Spacing.xs),
                              LayoutBuilder(
                                builder: (context, tabConstraints) {
                                  final maxW =
                                      tabConstraints.maxWidth.isFinite &&
                                              tabConstraints.maxWidth > 0
                                          ? tabConstraints.maxWidth
                                          : 280.0;
                                  const tiers = <M3SegmentItem<String>>[
                                    M3SegmentItem(
                                      value: 'الكل',
                                      label: 'الكل',
                                      icon: Icons.apps_rounded,
                                    ),
                                    M3SegmentItem(
                                      value: 'Tier A',
                                      label: 'Tier A',
                                      icon: Icons.star_rounded,
                                    ),
                                    M3SegmentItem(
                                      value: 'Tier B',
                                      label: 'Tier B',
                                      icon: Icons.storefront_rounded,
                                    ),
                                    M3SegmentItem(
                                      value: 'Tier C',
                                      label: 'Tier C',
                                      icon: Icons.store_mall_directory_rounded,
                                    ),
                                  ];
                                  return Wrap(
                                    spacing: M3Spacing.xs,
                                    runSpacing: M3Spacing.xs,
                                    children: [
                                      for (final s in tiers)
                                        _filterTab(
                                          value: s.value,
                                          label: s.label,
                                          icon: s.icon ?? Icons.apps_rounded,
                                          selected: _selectedTier == s.value,
                                          onSelected: _onTierFilterChanged,
                                          maxWidth: maxW,
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              M3Spacing.gapMD,

              // Tier Summary KPI Cards — shared Sell-Out tokens
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = M3KpiGridColumns.forWidthAndCount(
                    constraints.maxWidth,
                    3,
                  );
                  return M3EqualHeightGrid(
                    key: const ValueKey('store_matrix_kpi_grid'),
                    columns: columns,
                    spacing: M3Spacing.sm,
                    runSpacing: M3Spacing.sm,
                    children: [
                      _buildTierKpiCard(
                        context,
                        tierKey: 'Tier A',
                        title: 'Tier A (الفئة الأولى - الرائدة)',
                        stores: tierAStores,
                        revenue: tierARevenue,
                        icon: Icons.star_rounded,
                        color: colorScheme.primary,
                      ),
                      _buildTierKpiCard(
                        context,
                        tierKey: 'Tier B',
                        title: 'Tier B (الفئة المتوسطة)',
                        stores: tierBStores,
                        revenue: tierBRevenue,
                        icon: Icons.storefront_rounded,
                        color: colorScheme.secondary,
                      ),
                      _buildTierKpiCard(
                        context,
                        tierKey: 'Tier C',
                        title: 'Tier C (الفئة القياسية / الناشئة)',
                        stores: tierCStores,
                        revenue: tierCRevenue,
                        icon: Icons.store_mall_directory_rounded,
                        color: colorScheme.tertiary,
                      ),
                    ],
                  );
                },
              ),

              M3Spacing.gapMD,

              // Comparative Store Ranking Table Card
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: M3Shape.radiusLg,
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(isCompactScreen ? 12.0 : 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isDesktop = constraints.maxWidth >= 600.0;
                          if (isDesktop) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.leaderboard_rounded,
                                        color: colorScheme.primary,
                                        size: 24.0,
                                      ),
                                      const SizedBox(width: M3Spacing.xs),
                                      Expanded(
                                        child: M3SectionTitle(
                                          'جدول المقارنة المعيارية وترتيب الفروع (${countBranches(visible.length)})',
                                          maxLines: 3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: M3Spacing.sm),
                                Wrap(
                                  spacing: 8.0,
                                  runSpacing: 4.0,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: _buildTableMetaChips(context),
                                ),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.leaderboard_rounded,
                                    color: colorScheme.primary,
                                    size: 22.0,
                                  ),
                                  const SizedBox(width: M3Spacing.xs),
                                  Expanded(
                                    child: M3SectionTitle(
                                      'جدول المقارنة المعيارية وترتيب الفروع (${countBranches(visible.length)})',
                                      maxLines: 3,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: M3Spacing.xs),
                              Wrap(
                                spacing: 8.0,
                                runSpacing: 4.0,
                                children: _buildTableMetaChips(context),
                              ),
                            ],
                          );
                        },
                      ),
                      const Divider(height: 24.0),
                      M3FadeThroughSwitcher(
                        duration: M3Motion.medium1,
                        child: _isLoading
                            ? const Padding(
                                key: ValueKey('store_matrix_loading'),
                                padding: EdgeInsets.all(40.0),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            : visible.isEmpty
                                ? Padding(
                                    key: const ValueKey('store_matrix_empty'),
                                    padding: const EdgeInsets.all(40.0),
                                    child: Center(
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.search_off_rounded,
                                            size: 48.0,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(height: 12.0),
                                          Text(
                                            'لا توجد فروع مطابقة لمعايير البحث الحالية',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : LayoutBuilder(
                                    key: ValueKey(
                                      'store_matrix_table_${_selectedRegion}_${_selectedTier}_${visible.length}',
                                    ),
                                    builder: (context, tableConstraints) {
                                      final availableWidth = tableConstraints
                                              .maxWidth.isFinite
                                          ? tableConstraints.maxWidth
                                          : MediaQuery.sizeOf(context).width;
                                      final isCompact = availableWidth < 580.0;
                                      if (isCompact) {
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: visible.map((store) {
                                            return Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 10.0,
                                              ),
                                              padding:
                                                  const EdgeInsets.all(14.0),
                                              decoration: BoxDecoration(
                                                color: colorScheme.surface,
                                                borderRadius: M3Shape.radiusMd,
                                                border: Border.all(
                                                  color: colorScheme
                                                      .outlineVariant
                                                      .withOpacity(0.55),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Container(
                                                        width: 32.0,
                                                        height: 32.0,
                                                        decoration:
                                                            BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          color: store.rank == 1
                                                              ? colorScheme
                                                                  .primaryContainer
                                                              : store.rank == 2
                                                                  ? colorScheme
                                                                      .secondaryContainer
                                                                  : store.rank ==
                                                                          3
                                                                      ? colorScheme
                                                                          .tertiaryContainer
                                                                      : colorScheme
                                                                          .surfaceContainerHighest,
                                                        ),
                                                        child: Center(
                                                          child: Text(
                                                            '#${store.rank}',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  M3FontSize
                                                                      .bodySmall,
                                                              color: store.rank ==
                                                                      1
                                                                  ? colorScheme
                                                                      .onPrimaryContainer
                                                                  : store.rank ==
                                                                          2
                                                                      ? colorScheme
                                                                          .onSecondaryContainer
                                                                      : store.rank ==
                                                                              3
                                                                          ? colorScheme
                                                                              .onTertiaryContainer
                                                                          : colorScheme
                                                                              .onSurfaceVariant,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                          width: 10.0),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              _displayStoreName(
                                                                store,
                                                              ),
                                                              maxLines: 3,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              textAlign:
                                                                  TextAlign
                                                                      .start,
                                                              style: theme
                                                                  .textTheme
                                                                  .bodyMedium
                                                                  ?.copyWith(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 2.0,
                                                            ),
                                                            Wrap(
                                                              spacing: 8.0,
                                                              runSpacing: 2.0,
                                                              crossAxisAlignment:
                                                                  WrapCrossAlignment
                                                                      .center,
                                                              children: [
                                                                Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    Container(
                                                                      width:
                                                                          8.0,
                                                                      height:
                                                                          8.0,
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        shape: BoxShape
                                                                            .circle,
                                                                        color:
                                                                            _getChainColor(
                                                                          store
                                                                              .retailerChain,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width:
                                                                          5.0,
                                                                    ),
                                                                    Flexible(
                                                                      child:
                                                                          Text(
                                                                        _getChainDisplayName(
                                                                          store
                                                                              .retailerChain,
                                                                        ),
                                                                        maxLines:
                                                                            3,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        style: theme
                                                                            .textTheme
                                                                            .bodySmall
                                                                            ?.copyWith(
                                                                          color:
                                                                              colorScheme.onSurfaceVariant,
                                                                          fontSize:
                                                                              M3FontSize.labelSmallPlus,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .location_on_rounded,
                                                                      size:
                                                                          13.0,
                                                                      color: colorScheme
                                                                          .onSurfaceVariant,
                                                                    ),
                                                                    const SizedBox(
                                                                      width:
                                                                          2.0,
                                                                    ),
                                                                    Flexible(
                                                                      child:
                                                                          Text(
                                                                        store
                                                                            .region,
                                                                        maxLines:
                                                                            3,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        style: theme
                                                                            .textTheme
                                                                            .bodySmall
                                                                            ?.copyWith(
                                                                          color:
                                                                              colorScheme.onSurfaceVariant,
                                                                          fontSize:
                                                                              M3FontSize.labelSmallPlus,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ],
                                                            ),
                                                            const SizedBox(
                                                              height: 4.0,
                                                            ),
                                                            _buildTierBadge(
                                                              context,
                                                              store.tier,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                      vertical: 8.0,
                                                    ),
                                                    child: Divider(height: 1.0),
                                                  ),
                                                  Wrap(
                                                    alignment: WrapAlignment
                                                        .spaceBetween,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment
                                                            .center,
                                                    spacing: 12.0,
                                                    runSpacing: 6.0,
                                                    children: [
                                                      Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            'إجمالي المبيعات',
                                                            style: theme
                                                                .textTheme
                                                                .labelSmall
                                                                ?.copyWith(
                                                              color: colorScheme
                                                                  .onSurfaceVariant,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 2.0,
                                                          ),
                                                          Text(
                                                            CurrencyFormatter
                                                                .formatCompactEGP(
                                                              store
                                                                  .totalRevenue,
                                                            ),
                                                            style: theme
                                                                .textTheme
                                                                .bodyMedium
                                                                ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: colorScheme
                                                                  .primary,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        children: [
                                                          Text(
                                                            'الوحدات',
                                                            style: theme
                                                                .textTheme
                                                                .labelSmall
                                                                ?.copyWith(
                                                              color: colorScheme
                                                                  .onSurfaceVariant,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 2.0,
                                                          ),
                                                          Text(
                                                            '${CurrencyFormatter.formatUnits(store.totalUnits)} وحدة',
                                                            style: theme
                                                                .textTheme
                                                                .bodySmall
                                                                ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      _buildVelocityChip(
                                                        context,
                                                        store.velocityUnitsPerDay,
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        );
                                      }

                                      const spacing = M3Spacing.xs;
                                      const nameFlex = 2.2;
                                      const otherFlex =
                                          0.45 + 1.0 + 0.9 + 1.0 + 0.9 + 1.0;
                                      final inner = availableWidth -
                                          (2 * spacing) -
                                          (6 * spacing);
                                      final nameMaxWidth = (inner *
                                              nameFlex /
                                              (nameFlex + otherFlex))
                                          .clamp(140.0, 420.0);

                                      return TableScrollContainer(
                                        key: const ValueKey(
                                            'store_matrix_table'),
                                        showSwipeHint: true,
                                        columnFlex: _tableColumnFlex,
                                        child: DataTable(
                                          columnSpacing: spacing,
                                          horizontalMargin: spacing,
                                          dataRowMinHeight: _tableRowHeight,
                                          dataRowMaxHeight: _tableRowHeight,
                                          headingRowHeight: _tableHeadingHeight,
                                          headingRowColor:
                                              WidgetStateProperty.all(
                                            colorScheme.surfaceContainerHighest
                                                .withOpacity(0.4),
                                          ),
                                          columns: const [
                                            DataColumn(
                                              headingRowAlignment:
                                                  MainAxisAlignment.center,
                                              label: Text('الترتيب'),
                                            ),
                                            DataColumn(
                                              headingRowAlignment:
                                                  MainAxisAlignment.center,
                                              label: Text('اسم الفرع والسلسلة'),
                                            ),
                                            DataColumn(
                                              headingRowAlignment:
                                                  MainAxisAlignment.center,
                                              label: Text('المنطقة الجغرافية'),
                                            ),
                                            DataColumn(
                                              headingRowAlignment:
                                                  MainAxisAlignment.center,
                                              label: Text('تصنيف الفئة'),
                                            ),
                                            DataColumn(
                                              headingRowAlignment:
                                                  MainAxisAlignment.center,
                                              label: Text('إجمالي المبيعات'),
                                            ),
                                            DataColumn(
                                              headingRowAlignment:
                                                  MainAxisAlignment.center,
                                              label: Text('إجمالي الوحدات'),
                                            ),
                                            DataColumn(
                                              headingRowAlignment:
                                                  MainAxisAlignment.center,
                                              label: Text('معدل السرعة اليومي'),
                                            ),
                                          ],
                                          rows: [
                                            for (final store in visible)
                                              _buildStoreDataRow(
                                                context,
                                                store,
                                                nameMaxWidth: nameMaxWidth,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _buildStoreDataRow(
    BuildContext context,
    StoreBenchmarkItem store, {
    required double nameMaxWidth,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DataRow(
      cells: [
        DataCell(
          Center(
            child: Container(
              width: 32.0,
              height: 32.0,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: store.rank == 1
                    ? colorScheme.primaryContainer
                    : store.rank == 2
                        ? colorScheme.secondaryContainer
                        : store.rank == 3
                            ? colorScheme.tertiaryContainer
                            : colorScheme.surfaceContainerHighest,
              ),
              child: Center(
                child: Text(
                  '#${store.rank}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: M3FontSize.bodySmall,
                    color: store.rank == 1
                        ? colorScheme.onPrimaryContainer
                        : store.rank == 2
                            ? colorScheme.onSecondaryContainer
                            : store.rank == 3
                                ? colorScheme.onTertiaryContainer
                                : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        DataCell(
          KeyedSubtree(
            key: ValueKey('store_name_${store.storeId}'),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: nameMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Tooltip(
                    message: store.storeName,
                    child: Text(
                      _displayStoreName(store),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8.0,
                        height: 8.0,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _getChainColor(store.retailerChain),
                        ),
                      ),
                      const SizedBox(width: 6.0),
                      Flexible(
                        child: Text(
                          _getChainDisplayName(store.retailerChain),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        DataCell(
          Center(
            child: Text(
              store.region,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
        DataCell(Center(child: _buildTierBadge(context, store.tier))),
        DataCell(
          Center(
            child: Text(
              CurrencyFormatter.formatCompactEGP(store.totalRevenue),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
        DataCell(
          Center(
            child: Text(
              '${CurrencyFormatter.formatUnits(store.totalUnits)} وحدة',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        DataCell(
          Center(
            child: _buildVelocityChip(context, store.velocityUnitsPerDay),
          ),
        ),
      ],
    );
  }

  /// Tier KPI: skeleton while loading; «—» + Arabic note when the tier has
  /// no stores (never fake `0 ج.م` / `0 فرع`).
  Widget _buildTierKpiCard(
    BuildContext context, {
    required String tierKey,
    required String title,
    required List<StoreBenchmarkItem> stores,
    required double revenue,
    required IconData icon,
    required Color color,
  }) {
    final empty = stores.isEmpty;
    return M3SummaryKpiCard(
      key: ValueKey('kpi_card_$tierKey'),
      valueKey: ValueKey('kpi_value_$tierKey'),
      subtitleKey: ValueKey('kpi_subtitle_$tierKey'),
      loadingKey: ValueKey('kpi_loading_$tierKey'),
      title: title,
      titleMaxLines: 3,
      subtitleMaxLines: 3,
      value: empty ? '—' : CurrencyFormatter.formatCompactEGP(revenue),
      textValue: empty,
      subtitle: empty ? 'لا توجد فروع في هذه الفئة' : countBranches(stores.length),
      icon: icon,
      color: color,
      isLoading: _isLoading,
    );
  }

  /// Period + sort chips share M3ChipSurface geometry with Sell-Out / TM.
  List<Widget> _buildTableMetaChips(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return [
      M3ChipSurface(
        key: const ValueKey('store_matrix_period_chip'),
        color: colorScheme.primaryContainer.withOpacity(0.4),
        borderColor: colorScheme.primary.withOpacity(0.2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 13.0,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 4.0),
            Flexible(
              child: Text(
                _activePeriodLabel,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
      Column(
        key: const ValueKey('store_matrix_sort_chip'),
        mainAxisSize: MainAxisSize.min,
        children: [
          M3ChipSurface(
            color: colorScheme.surfaceContainerHighest,
            child: Text(
              'ترتيب',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2.0),
          Text(
            'حسب إجمالي المبيعات تنازلياً',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ];
  }

  /// Short rate chip + «وحدة / يوم» description; «—» when velocity is absent.
  Widget _buildVelocityChip(BuildContext context, double velocity) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final missing = velocity <= 0;
    final chipColor = missing
        ? colorScheme.surfaceContainerHighest
        : colorScheme.secondaryContainer.withOpacity(0.5);
    final fg = missing
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSecondaryContainer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        M3ChipSurface(
          color: chipColor,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!missing) ...[
                Icon(Icons.trending_up_rounded, size: 14.0, color: fg),
                const SizedBox(width: 4.0),
              ],
              Text(
                missing ? '—' : velocity.toStringAsFixed(1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2.0),
        Text(
          missing ? 'لا توجد بيانات سرعة' : 'وحدة / يوم',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildTierBadge(BuildContext context, String tier) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    late final Color bg;
    late final Color fg;
    late final String description;

    switch (tier.toUpperCase()) {
      case 'TIER A':
        bg = colorScheme.primaryContainer;
        fg = colorScheme.onPrimaryContainer;
        description = 'الفئة الأولى - الرائدة';
        break;
      case 'TIER B':
        bg = colorScheme.secondaryContainer;
        fg = colorScheme.onSecondaryContainer;
        description = 'الفئة المتوسطة';
        break;
      case 'TIER C':
      default:
        bg = colorScheme.tertiaryContainer;
        fg = colorScheme.onTertiaryContainer;
        description = 'الفئة القياسية / الناشئة';
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        M3ChipSurface(
          color: bg,
          child: Text(
            tier,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 2.0),
        Text(
          description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _getChainDisplayName(String chain) {
    switch (chain.toLowerCase()) {
      case 'carrefour':
        return 'كارفور (Carrefour)';
      case 'fathalla':
        return 'أسواق فتح الله (Fathalla)';
      case 'gomla':
        return 'جملة ماركت (Gomla)';
      case 'spinneys':
        return 'سبينيس (Spinneys)';
      case 'beet-elgomla':
      case 'beet_elgomla':
        return 'بيت الجملة (Beet El Gomla)';
      default:
        return chain;
    }
  }

  Color _getChainColor(String chain) {
    switch (chain.toLowerCase()) {
      case 'fathalla':
        return M3Palette.emerald; // Emerald Green
      case 'gomla':
        return M3Palette.amber; // Amber / Orange
      case 'beet-elgomla':
      case 'beet_elgomla':
        return M3Palette.violet; // Royal Violet
      case 'carrefour':
        return M3Palette.blue; // Royal Blue
      case 'spinneys':
        return M3Palette.rose; // Rose / Red
      default:
        return M3Palette.neutral;
    }
  }

  Widget _filterTab({
    required String value,
    required String label,
    required IconData icon,
    required bool selected,
    required ValueChanged<String> onSelected,
    required double maxWidth,
  }) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: M3ToolbarButton.iconSize),
        const SizedBox(width: 8.0),
        Flexible(
          child: Text(
            label,
            maxLines: 3,
            overflow: TextOverflow.visible,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
    final button = selected
        ? FilledButton.tonal(onPressed: () => onSelected(value), child: child)
        : OutlinedButton(onPressed: () => onSelected(value), child: child);
    return KeyedSubtree(
      key: ValueKey('store_matrix_filter_$value'),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: button,
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required BuildContext context,
    required String label,
    required IconData icon,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 600.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14.0, color: colorScheme.primary),
            const SizedBox(width: 4.0),
            Flexible(
              child: Text(
                label,
                maxLines: 3,
                overflow: TextOverflow.visible,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: M3Spacing.xs),
        M3Dropdown<T>(
          expand: isCompact,
          fitOptions: true,
          width: label.startsWith('السنة') ? kYearDropdownWidth : null,
          value: value,
          options: m3OptionsFromMenuItems(items),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

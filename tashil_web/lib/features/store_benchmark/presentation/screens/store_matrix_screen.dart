import 'package:flutter/material.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_segmented_button_group.dart';
import '../../../../core/widgets/table_scroll_container.dart';

/// StoreMatrixScreen displays store benchmarking across Egyptian retail regions,
/// tier categorization (Tier A/B/C), and sales velocity metrics.
class StoreMatrixScreen extends StatefulWidget {
  final ApiClient apiClient;

  const StoreMatrixScreen({
    super.key,
    required this.apiClient,
  });

  @override
  State<StoreMatrixScreen> createState() => _StoreMatrixScreenState();
}

class _StoreMatrixScreenState extends State<StoreMatrixScreen> {
  bool _isLoading = true;
  String _selectedRegion = 'الكل';
  String _selectedTier = 'الكل';
  int _selectedYear = 2026;
  int _selectedMonth = 0; // 0 = All months
  String _selectedChain = 'all'; // 'all', 'fathalla', 'gomla', 'beet-elgomla', etc.
  List<StoreBenchmarkItem> _stores = [];

  final List<M3SegmentItem<String>> _regionSegments = const [
    M3SegmentItem(value: 'الكل', label: 'كافة المناطق', icon: Icons.public_rounded),
    M3SegmentItem(value: 'شرق الإسكندرية', label: 'شرق الإسكندرية', icon: Icons.location_city_rounded),
    M3SegmentItem(value: 'غرب الإسكندرية', label: 'غرب الإسكندرية', icon: Icons.location_on_rounded),
    M3SegmentItem(value: 'الدلتا والبحيرة', label: 'الدلتا والبحيرة', icon: Icons.map_rounded),
    M3SegmentItem(value: 'القاهرة الكبرى', label: 'القاهرة الكبرى', icon: Icons.apartment_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _lastTenantId = widget.apiClient.tenantId;
    _loadStoreMatrix();
  }

  late String _lastTenantId;

  @override
  void didUpdateWidget(covariant StoreMatrixScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient ||
        _lastTenantId != widget.apiClient.tenantId) {
      _lastTenantId = widget.apiClient.tenantId;
      _selectedRegion = 'الكل';
      _selectedTier = 'الكل';
      _selectedYear = 2026;
      _selectedMonth = 0;
      _selectedChain = 'all';
      _loadStoreMatrix();
    }
  }

  Future<void> _loadStoreMatrix() async {
    setState(() => _isLoading = true);
    final results = await widget.apiClient.getStoreBenchmarkMatrix(
      region: _selectedRegion == 'الكل' ? null : _selectedRegion,
      tier: _selectedTier == 'الكل' ? null : _selectedTier,
      chain: _selectedChain == 'all' ? null : _selectedChain,
      year: _selectedYear == 0 ? null : _selectedYear,
      month: _selectedMonth == 0 ? null : _selectedMonth,
    );
    if (mounted) {
      setState(() {
        _stores = results;
        _isLoading = false;
      });
    }
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
    final tierAStores = _stores.where((s) => s.tier == 'Tier A').toList();
    final tierBStores = _stores.where((s) => s.tier == 'Tier B').toList();
    final tierCStores = _stores.where((s) => s.tier == 'Tier C').toList();

    final tierARevenue = tierAStores.fold<double>(0.0, (sum, s) => sum + s.totalRevenue);
    final tierBRevenue = tierBStores.fold<double>(0.0, (sum, s) => sum + s.totalRevenue);
    final tierCRevenue = tierCStores.fold<double>(0.0, (sum, s) => sum + s.totalRevenue);

    final isCompactScreen = MediaQuery.sizeOf(context).width < 600.0;

    return SingleChildScrollView(
      padding: isCompactScreen ? M3Spacing.pSm : M3Spacing.pMd,
      child: M3ContentBoundary(
        maxWidth: 1440.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Section (Unified M3 Left English Title + Right Arabic Subtitle)
            M3PageHeader(
              titleEn: 'Store Matrix Benchmarking',
              subtitleAr: 'مقارنة الأداء المعياري وتصنيف الفروع إلى فئات (Tier A / B / C) ومعدلات سرعة البيع اليومية',
              actions: M3Button.tonal(
                label: 'تحديث',
                icon: Icons.refresh_rounded,
                onPressed: _isLoading ? null : _loadStoreMatrix,
              ),
            ),

            M3Spacing.gapMD,

            // Filter Toolbar (Temporal, Chain, Regional & Tier Selectors)
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
                side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
              ),
              child: Padding(
                padding: EdgeInsets.all(isCompactScreen ? M3Spacing.sm : M3Spacing.md),
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
                          label: 'السنة المالية:',
                          icon: Icons.calendar_today_rounded,
                          value: _selectedYear,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('كافة السنوات (إجمالي)')),
                            DropdownMenuItem(value: 2026, child: Text('عام 2026')),
                            DropdownMenuItem(value: 2025, child: Text('عام 2025')),
                            DropdownMenuItem(value: 2024, child: Text('عام 2024')),
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
                          label: 'الشهر:',
                          icon: Icons.event_note_rounded,
                          value: _selectedMonth,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('كافة الشهور (إجمالي السنة)')),
                            DropdownMenuItem(value: 1, child: Text('01 - يناير')),
                            DropdownMenuItem(value: 2, child: Text('02 - فبراير')),
                            DropdownMenuItem(value: 3, child: Text('03 - مارس')),
                            DropdownMenuItem(value: 4, child: Text('04 - أبريل')),
                            DropdownMenuItem(value: 5, child: Text('05 - مايو')),
                            DropdownMenuItem(value: 6, child: Text('06 - يونيو')),
                            DropdownMenuItem(value: 7, child: Text('07 - يوليو')),
                            DropdownMenuItem(value: 8, child: Text('08 - أغسطس')),
                            DropdownMenuItem(value: 9, child: Text('09 - سبتمبر')),
                            DropdownMenuItem(value: 10, child: Text('10 - أكتوبر')),
                            DropdownMenuItem(value: 11, child: Text('11 - نوفمبر')),
                            DropdownMenuItem(value: 12, child: Text('12 - ديسمبر')),
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
                          label: 'سلسلة التجزئة:',
                          icon: Icons.storefront_rounded,
                          value: _selectedChain,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('كافة السلاسل')),
                            DropdownMenuItem(value: 'fathalla', child: Text('أسواق فتح الله')),
                            DropdownMenuItem(value: 'gomla', child: Text('جملة ماركت')),
                            DropdownMenuItem(value: 'beet-elgomla', child: Text('بيت الجملة')),
                            DropdownMenuItem(value: 'carrefour', child: Text('كارفور')),
                            DropdownMenuItem(value: 'spinneys', child: Text('سبينيس')),
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
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: M3SegmentedButtonGroup<String>(
                                segments: _regionSegments,
                                selectedValue: _selectedRegion,
                                onSelectionChanged: _onRegionChanged,
                                showSelectedCheckmark: false,
                              ),
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
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: M3SegmentedButtonGroup<String>(
                                segments: const [
                                  M3SegmentItem(value: 'الكل', label: 'الكل', icon: Icons.apps_rounded),
                                  M3SegmentItem(value: 'Tier A', label: 'Tier A', icon: Icons.star_rounded),
                                  M3SegmentItem(value: 'Tier B', label: 'Tier B', icon: Icons.storefront_rounded),
                                  M3SegmentItem(value: 'Tier C', label: 'Tier C', icon: Icons.store_mall_directory_rounded),
                                ],
                                selectedValue: _selectedTier,
                                onSelectionChanged: _onTierFilterChanged,
                                showSelectedCheckmark: false,
                              ),
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

            // Tier Summary KPI Cards (Responsive Reflow >= 840dp)
            LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 840.0;
                final cards = [
                  _buildTierKpiCard(
                    context: context,
                    tierName: 'Tier A (الفئة الأولى - الرائدة)',
                    storeCount: tierAStores.length,
                    totalRevenue: tierARevenue,
                    containerColor: colorScheme.primaryContainer,
                    onContainerColor: colorScheme.onPrimaryContainer,
                    icon: Icons.star_rounded,
                    badgeColor: colorScheme.primary,
                  ),
                  _buildTierKpiCard(
                    context: context,
                    tierName: 'Tier B (الفئة المتوسطة)',
                    storeCount: tierBStores.length,
                    totalRevenue: tierBRevenue,
                    containerColor: colorScheme.secondaryContainer,
                    onContainerColor: colorScheme.onSecondaryContainer,
                    icon: Icons.storefront_rounded,
                    badgeColor: colorScheme.secondary,
                  ),
                  _buildTierKpiCard(
                    context: context,
                    tierName: 'Tier C (الفئة القياسية / الناشئة)',
                    storeCount: tierCStores.length,
                    totalRevenue: tierCRevenue,
                    containerColor: colorScheme.tertiaryContainer,
                    onContainerColor: colorScheme.onTertiaryContainer,
                    icon: Icons.store_mall_directory_rounded,
                    badgeColor: colorScheme.tertiary,
                  ),
                ];

                if (isDesktop) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cards[0]),
                        M3Spacing.hGapMD,
                        Expanded(child: cards[1]),
                        M3Spacing.hGapMD,
                        Expanded(child: cards[2]),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    cards[0],
                    M3Spacing.gapSM,
                    cards[1],
                    M3Spacing.gapSM,
                    cards[2],
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
                borderRadius: BorderRadius.circular(16.0),
                side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
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
                                    Icon(Icons.leaderboard_rounded, color: colorScheme.primary, size: 24.0),
                                    const SizedBox(width: M3Spacing.xs),
                                    Expanded(
                                      child: Text(
                                        'جدول المقارنة المعيارية وترتيب الفروع (${_stores.length} فرع)',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
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
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer.withOpacity(0.4),
                                      borderRadius: BorderRadius.circular(12.0),
                                      border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.calendar_today_rounded, size: 13.0, color: colorScheme.primary),
                                        const SizedBox(width: 4.0),
                                        Text(
                                          _activePeriodLabel,
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(12.0),
                                    ),
                                    child: Text(
                                      'الترتيب حسب إجمالي المبيعات تنازلياً',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.leaderboard_rounded, color: colorScheme.primary, size: 22.0),
                                const SizedBox(width: M3Spacing.xs),
                                Expanded(
                                  child: Text(
                                    'جدول المقارنة المعيارية وترتيب الفروع (${_stores.length} فرع)',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: M3Spacing.xs),
                            Wrap(
                              spacing: 8.0,
                              runSpacing: 4.0,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(12.0),
                                    border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.calendar_today_rounded, size: 13.0, color: colorScheme.primary),
                                      const SizedBox(width: 4.0),
                                      Text(
                                        _activePeriodLabel,
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: Text(
                                    'الترتيب حسب إجمالي المبيعات تنازلياً',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
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
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : _stores.isEmpty
                              ? Padding(
                                  key: const ValueKey('store_matrix_empty'),
                                  padding: const EdgeInsets.all(40.0),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.search_off_rounded, size: 48.0, color: colorScheme.onSurfaceVariant),
                                        const SizedBox(height: 12.0),
                                        Text(
                                          'لا توجد فروع مطابقة لمعايير البحث الحالية',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : LayoutBuilder(
                                  key: ValueKey('store_matrix_table_${_selectedRegion}_${_selectedTier}_${_stores.length}'),
                                  builder: (context, tableConstraints) {
                                    final availableWidth = tableConstraints.maxWidth.isFinite
                                        ? tableConstraints.maxWidth
                                        : MediaQuery.sizeOf(context).width;
                                    final isCompact = availableWidth < 580.0;
                                    if (isCompact) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: _stores.map((store) {
                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 10.0),
                                            padding: const EdgeInsets.all(14.0),
                                            decoration: BoxDecoration(
                                              color: colorScheme.surface,
                                              borderRadius: BorderRadius.circular(14.0),
                                              border: Border.all(
                                                color: colorScheme.outlineVariant.withOpacity(0.55),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Container(
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
                                                            fontSize: 12.0,
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
                                                    const SizedBox(width: 10.0),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            store.storeName,
                                                            style: theme.textTheme.bodyMedium?.copyWith(
                                                              fontWeight: FontWeight.w800,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 2.0),
                                                          Wrap(
                                                            spacing: 8.0,
                                                            runSpacing: 2.0,
                                                            crossAxisAlignment: WrapCrossAlignment.center,
                                                            children: [
                                                              Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  Container(
                                                                    width: 8.0,
                                                                    height: 8.0,
                                                                    decoration: BoxDecoration(
                                                                      shape: BoxShape.circle,
                                                                      color: _getChainColor(store.retailerChain),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(width: 5.0),
                                                                  Flexible(
                                                                    child: Text(
                                                                      _getChainDisplayName(store.retailerChain),
                                                                      maxLines: 1,
                                                                      overflow: TextOverflow.ellipsis,
                                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                                        color: colorScheme.onSurfaceVariant,
                                                                        fontSize: 11.5,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  Icon(
                                                                    Icons.location_on_outlined,
                                                                    size: 13.0,
                                                                    color: colorScheme.outline,
                                                                  ),
                                                                  const SizedBox(width: 2.0),
                                                                  Flexible(
                                                                    child: Text(
                                                                      store.region,
                                                                      maxLines: 1,
                                                                      overflow: TextOverflow.ellipsis,
                                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                                        color: colorScheme.onSurfaceVariant,
                                                                        fontSize: 11.5,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8.0),
                                                    _buildTierBadge(context, store.tier),
                                                  ],
                                                ),
                                                const Padding(
                                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                                  child: Divider(height: 1.0),
                                                ),
                                                Wrap(
                                                  alignment: WrapAlignment.spaceBetween,
                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                  spacing: 12.0,
                                                  runSpacing: 6.0,
                                                  children: [
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          'إجمالي المبيعات',
                                                          style: theme.textTheme.labelSmall?.copyWith(
                                                            color: colorScheme.onSurfaceVariant,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 2.0),
                                                        Text(
                                                          CurrencyFormatter.formatEGP(store.totalRevenue),
                                                          style: theme.textTheme.bodyMedium?.copyWith(
                                                            fontWeight: FontWeight.w800,
                                                            color: colorScheme.primary,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.center,
                                                      children: [
                                                        Text(
                                                          'الوحدات',
                                                          style: theme.textTheme.labelSmall?.copyWith(
                                                            color: colorScheme.onSurfaceVariant,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 2.0),
                                                        Text(
                                                          '${CurrencyFormatter.formatUnits(store.totalUnits)} وحدة',
                                                          style: theme.textTheme.bodySmall?.copyWith(
                                                            fontWeight: FontWeight.w700,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 8.0,
                                                        vertical: 4.0,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: colorScheme.secondaryContainer.withOpacity(0.5),
                                                        borderRadius: BorderRadius.circular(8.0),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.trending_up_rounded,
                                                            size: 14.0,
                                                            color: colorScheme.onSecondaryContainer,
                                                          ),
                                                          const SizedBox(width: 4.0),
                                                          Text(
                                                            '${store.velocityUnitsPerDay.toStringAsFixed(1)} / يوم',
                                                            style: TextStyle(
                                                              fontSize: 11.5,
                                                              fontWeight: FontWeight.w700,
                                                              color: colorScheme.onSecondaryContainer,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      );
                                    }

                                    final isMedium = availableWidth >= 580.0 && availableWidth < 960.0;
                                    final double dynamicColumnSpacing = isMedium
                                        ? 24.0
                                        : ((availableWidth - 540.0) / 6.0).clamp(24.0, 64.0);
                                    const double horizontalMargin = 20.0;

                                    return SizedBox(
                                      width: availableWidth,
                                      child: TableScrollContainer(
                                        showSwipeHint: true,
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(minWidth: availableWidth),
                                          child: DataTable(
                                            columnSpacing: dynamicColumnSpacing,
                                            horizontalMargin: horizontalMargin,
                                            dataRowMinHeight: 56.0,
                                            dataRowMaxHeight: 68.0,
                                            headingRowHeight: 52.0,
                                            headingRowColor: WidgetStateProperty.all(
                                              colorScheme.surfaceContainerHighest.withOpacity(0.4),
                                            ),
                                            columns: const [
                                              DataColumn(label: Text('الترتيب')),
                                              DataColumn(label: Text('اسم الفرع والسلسلة')),
                                              DataColumn(label: Text('المنطقة الجغرافية')),
                                              DataColumn(label: Text('تصنيف الفئة')),
                                              DataColumn(label: Text('إجمالي المبيعات')),
                                              DataColumn(label: Text('إجمالي الوحدات')),
                                              DataColumn(label: Text('معدل السرعة اليومي')),
                                            ],
                                            rows: _stores.map((store) {
                            return DataRow(
                              cells: [
                                // Rank Badge
                                DataCell(
                                  Container(
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
                                          fontSize: 12.0,
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

                                // Store Name & Chain
                                DataCell(
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        store.storeName,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2.0),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
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
                                          Text(
                                            _getChainDisplayName(store.retailerChain),
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: colorScheme.onSurfaceVariant,
                                              fontSize: 11.0,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Region
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.location_on_outlined, size: 16.0, color: colorScheme.outline),
                                      const SizedBox(width: 4.0),
                                      Text(store.region, style: theme.textTheme.bodyMedium),
                                    ],
                                  ),
                                ),

                                // Tier Badge
                                DataCell(_buildTierBadge(context, store.tier)),

                                // Total Revenue
                                DataCell(
                                  Text(
                                    CurrencyFormatter.formatEGP(store.totalRevenue),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),

                                // Units Sold
                                DataCell(
                                  Text(
                                    '${CurrencyFormatter.formatUnits(store.totalUnits)} وحدة',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),

                                // Velocity (Units / Day)
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                                        decoration: BoxDecoration(
                                          color: colorScheme.secondaryContainer.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(8.0),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.trending_up_rounded,
                                              size: 14.0,
                                              color: colorScheme.onSecondaryContainer,
                                            ),
                                            const SizedBox(width: 4.0),
                                            Text(
                                              '${store.velocityUnitsPerDay.toStringAsFixed(1)} / يوم',
                                              style: TextStyle(
                                                fontSize: 12.0,
                                                fontWeight: FontWeight.w600,
                                                color: colorScheme.onSecondaryContainer,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                                            }).toList(),
                                          ),
                                        ),
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
    );
  }

  Widget _buildTierKpiCard({
    required BuildContext context,
    required String tierName,
    required int storeCount,
    required double totalRevenue,
    required Color containerColor,
    required Color onContainerColor,
    required IconData icon,
    required Color badgeColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: containerColor,
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Icon(icon, color: onContainerColor, size: 22.0),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                  decoration: BoxDecoration(
                    color: containerColor.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: Text(
                    '$storeCount فروع',
                    style: TextStyle(
                      color: onContainerColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: M3Spacing.sm),
            Text(
              tierName,
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6.0),
            Text(
              CurrencyFormatter.formatEGP(totalRevenue),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: badgeColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierBadge(BuildContext context, String tier) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color bg;
    Color fg;

    switch (tier.toUpperCase()) {
      case 'TIER A':
        bg = colorScheme.primaryContainer;
        fg = colorScheme.onPrimaryContainer;
        break;
      case 'TIER B':
        bg = colorScheme.secondaryContainer;
        fg = colorScheme.onSecondaryContainer;
        break;
      case 'TIER C':
      default:
        bg = colorScheme.tertiaryContainer;
        fg = colorScheme.onTertiaryContainer;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xs, vertical: M3Spacing.xxs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Text(
        tier,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 11.0,
        ),
      ),
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
        return const Color(0xFF10B981); // Emerald Green
      case 'gomla':
        return const Color(0xFFF59E0B); // Amber / Orange
      case 'beet-elgomla':
      case 'beet_elgomla':
        return const Color(0xFF7C3AED); // Royal Violet
      case 'carrefour':
        return const Color(0xFF2563EB); // Royal Blue
      case 'spinneys':
        return const Color(0xFFE11D48); // Rose / Red
      default:
        return const Color(0xFF6B7280);
    }
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: M3Spacing.xs),
        Container(
          height: 40.0,
          width: isCompact ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.6)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: isCompact,
              isDense: true,
              borderRadius: BorderRadius.circular(12.0),
              icon: Icon(Icons.arrow_drop_down_rounded, color: colorScheme.primary),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_segmented_button_group.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../../product_master/presentation/screens/product_master_screen.dart';

/// PricingComplianceScreen monitors SKU-level price compliance against Recommended Retail Price (RRP)
/// and measures promotional uplift percentages across retail chains.
class PricingComplianceScreen extends StatefulWidget {
  final ApiClient apiClient;

  const PricingComplianceScreen({
    super.key,
    required this.apiClient,
  });

  @override
  State<PricingComplianceScreen> createState() => _PricingComplianceScreenState();
}

class _PricingComplianceScreenState extends State<PricingComplianceScreen> {
  bool _isLoading = true;
  String _selectedFilter = 'الكل';
  String _selectedCategory = 'الكل';
  int _selectedYear = 0;
  int _selectedMonth = 0;
  String _selectedChain = 'all';
  bool _showPriceImpact = false;
  final TextEditingController _searchController = TextEditingController();
  List<MonthlyPriceElasticityPoint> _elasticityPoints = [];
  PriceElasticitySummaryModel? _elasticitySummary;
  int? _selectedMonthIndex;
  List<PricingComplianceItem> _pageItems = [];
  List<String> _availableCategories = const [];

  int _pageSize = 25;
  int _currentPage = 0;
  int _totalMatchingCount = 0;
  int _summaryTotalCount = 0;
  int _compliantCount = 0;
  int _violationCount = 0;
  double _complianceRate = 100.0;
  double _avgPromoUplift = 0.0;

  static const List<int> _pageSizeOptions = [25, 50];

  final List<M3SegmentItem<String>> _filterSegments = const [
    M3SegmentItem(value: 'الكل', label: 'الكل', icon: Icons.view_list_rounded),
    M3SegmentItem(value: 'عروض نشطة فقط', label: 'عروض نشطة', icon: Icons.local_offer_rounded),
    M3SegmentItem(value: 'مخالفات سعرية فقط', label: 'مخالفات سعرية', icon: Icons.warning_amber_rounded),
  ];

  late String _lastTenantId;

  @override
  void initState() {
    super.initState();
    _lastTenantId = widget.apiClient.tenantId;
    _loadPricingCompliance();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PricingComplianceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient ||
        _lastTenantId != widget.apiClient.tenantId) {
      _lastTenantId = widget.apiClient.tenantId;
      _selectedFilter = 'الكل';
      _selectedCategory = 'الكل';
      _selectedYear = 0;
      _selectedMonth = 0;
      _selectedChain = 'all';
      _showPriceImpact = false;
      _searchController.clear();
      _selectedMonthIndex = null;
      _currentPage = 0;
      _availableCategories = const [];
      _loadPricingCompliance();
    }
  }

  Future<void> _loadPricingCompliance() async {
    setState(() => _isLoading = true);
    final isUnfilteredCategory = _selectedCategory == 'الكل';
    final isViolationOnly = _selectedFilter == 'مخالفات سعرية فقط';
    final isPromoOnly = _selectedFilter == 'عروض نشطة فقط';
    final searchQuery = _searchController.text.trim();

    final results = await widget.apiClient.getPricingCompliance(
      chain: _selectedChain == 'all' ? null : _selectedChain,
      category: isUnfilteredCategory ? null : _selectedCategory,
      search: searchQuery.isEmpty ? null : searchQuery,
      violationOnly: isViolationOnly ? true : null,
      promoOnly: isPromoOnly ? true : null,
      year: _selectedYear > 0 ? _selectedYear : null,
      month: _selectedMonth > 0 ? _selectedMonth : null,
      limit: _pageSize,
      offset: _currentPage * _pageSize,
    );

    if (mounted) {
      setState(() {
        final meta = widget.apiClient.lastPricingComplianceMeta;
        _pageItems = results;

        if (meta != null) {
          _totalMatchingCount = meta.totalCount;
          _summaryTotalCount = meta.summaryTotalCount;
          _compliantCount = meta.compliantCount;
          _violationCount = meta.violationCount;
          _complianceRate = meta.complianceRatePct;
          _avgPromoUplift = meta.avgPromoUpliftPct;
          _elasticityPoints = meta.monthlyElasticity;
          _elasticitySummary = meta.elasticitySummary;
          if (_selectedMonthIndex != null &&
              (_selectedMonthIndex! < 0 || _selectedMonthIndex! >= _elasticityPoints.length)) {
            _selectedMonthIndex = null;
          }
          if (meta.availableCategories.isNotEmpty || isUnfilteredCategory) {
            final seen = <String>{};
            final cats = <String>[];
            for (final c in meta.availableCategories) {
              final norm = ApiClient.normalizeCategoryName(c);
              if (norm.isNotEmpty && seen.add(norm)) {
                cats.add(norm);
              }
            }
            _availableCategories = cats;
          }
        } else {
          _totalMatchingCount = results.length;
          _summaryTotalCount = results.length;
          _compliantCount = results.where((i) => i.violationType == 'compliant').length;
          _violationCount = results.where((i) => i.violationType != 'compliant').length;
          _complianceRate = _summaryTotalCount > 0
              ? (_compliantCount / _summaryTotalCount) * 100.0
              : 100.0;
          final activePromos = results.where((i) => i.isPromoActive && i.promoUpliftPct > 0).toList();
          _avgPromoUplift = activePromos.isNotEmpty
              ? activePromos.fold<double>(0.0, (sum, i) => sum + i.promoUpliftPct) / activePromos.length
              : 0.0;
          _elasticityPoints = [];
          _elasticitySummary = null;
          if (isUnfilteredCategory || _availableCategories.isEmpty) {
            final seen = <String>{};
            final cats = <String>[];
            for (final item in results) {
              final norm = ApiClient.normalizeCategoryName(item.category);
              if (norm.isNotEmpty && seen.add(norm)) {
                cats.add(norm);
              }
            }
            _availableCategories = cats;
          }
        }

        if (_selectedCategory != 'الكل' &&
            _availableCategories.isNotEmpty &&
            !_availableCategories.contains(_selectedCategory)) {
          _selectedCategory = 'الكل';
        }

        final maxPage = _totalMatchingCount > 0
            ? ((_totalMatchingCount - 1) ~/ _pageSize)
            : 0;
        if (_currentPage > maxPage) {
          _currentPage = maxPage;
        }

        _isLoading = false;
      });
    }
  }

  void _openProductMasterDialog({String? initialQuery}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('كارتة الأصناف والأسعار المعتمدة (Product Master)'),
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            body: ProductMasterScreen(
              apiClient: widget.apiClient,
              initialSearchQuery: initialQuery,
            ),
          ),
        ),
      ),
    ).then((_) => _loadPricingCompliance());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final totalCount = _summaryTotalCount;
    final compliantCount = _compliantCount;
    final violationCount = _violationCount;
    final complianceRate = _complianceRate;
    final avgPromoUplift = _avgPromoUplift;

    final displayedItems = _pageItems;
    final totalMatching = _totalMatchingCount;
    final totalPages = totalMatching > 0 ? ((totalMatching - 1) ~/ _pageSize) + 1 : 1;
    final startItem = totalMatching == 0 ? 0 : (_currentPage * _pageSize) + 1;
    final endItem = totalMatching == 0
        ? 0
        : ((_currentPage * _pageSize) + displayedItems.length).clamp(startItem, totalMatching);

    final isCompactScreen = MediaQuery.sizeOf(context).width < 600.0;

    return SingleChildScrollView(
      padding: isCompactScreen ? M3Spacing.pSm : M3Spacing.pMd,
      child: M3ContentBoundary(
        maxWidth: 1440.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Unified M3 Page Header (English Left, Arabic Right)
            M3PageHeader(
              titleEn: 'Pricing & Promo Compliance',
              subtitleAr:
                  'كشف الفروق السعرية عن السعر الاسترشادي (RRP) وكارتة أسعار المصنع وتتبع الأثر البيعي للعروض',
              actions: M3ActionButtonGroup(
                actions: [
                  M3ActionItem(
                    label: _showPriceImpact ? 'إخفاء المؤشر' : 'أثر الأسعار',
                    icon: _showPriceImpact
                        ? Icons.visibility_off_outlined
                        : Icons.insights_rounded,
                    isPrimary: _showPriceImpact,
                    onPressed: () {
                      setState(() => _showPriceImpact = !_showPriceImpact);
                    },
                  ),
                  M3ActionItem(
                    label: 'تحديث',
                    icon: Icons.refresh_rounded,
                    onPressed: _isLoading ? null : _loadPricingCompliance,
                  ),
                ],
              ),
            ),

            M3Spacing.gapMD,

            // Summary KPI Cards (Responsive Reflow >= 840dp)
            LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 840.0;
                final cards = [
                  _buildKpiCard(
                    context: context,
                    title: 'معدل الالتزام السعري (Compliance Rate)',
                    value: '${complianceRate.toStringAsFixed(1)}%',
                    subtitle: '$compliantCount من أصل $totalCount صنف مطابق',
                    icon: Icons.verified_outlined,
                    containerColor: colorScheme.primaryContainer,
                    onContainerColor: colorScheme.onPrimaryContainer,
                  ),
                  _buildKpiCard(
                    context: context,
                    title: 'إجمالي المخالفات السعرية (Price Violations)',
                    value: '$violationCount مخالفة',
                    subtitle: 'حالات حرق أسعار وزيادة غير معتمدة',
                    icon: Icons.error_outline_rounded,
                    containerColor: colorScheme.errorContainer,
                    onContainerColor: colorScheme.onErrorContainer,
                  ),
                  _buildKpiCard(
                    context: context,
                    title: 'متوسط الأثر الترويجي (Avg Promo Uplift)',
                    value: '+${avgPromoUplift.toStringAsFixed(1)}%',
                    subtitle: 'زيادة في حجم المبيعات خلال فترات العروض',
                    icon: Icons.rocket_launch_rounded,
                    containerColor: colorScheme.tertiaryContainer,
                    onContainerColor: colorScheme.onTertiaryContainer,
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

            // Filter Toolbar with Temporal (Year/Month), Chain, Status & Category Selectors
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
                side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(M3Spacing.sm),
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
                              setState(() {
                                _selectedYear = val;
                                _currentPage = 0;
                              });
                              _loadPricingCompliance();
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
                              setState(() {
                                _selectedMonth = val;
                                _currentPage = 0;
                              });
                              _loadPricingCompliance();
                            }
                          },
                        ),

                        // Chain Selector
                        _buildFilterDropdown<String>(
                          context: context,
                          label: 'سلسلة التجزئة:',
                          icon: Icons.storefront_rounded,
                          value: _selectedChain,
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('كافة السلاسل')),
                            _buildChainDropdownItem('fathalla', 'أسواق فتح الله'),
                            _buildChainDropdownItem('gomla', 'جملة ماركت'),
                            _buildChainDropdownItem('beet-elgomla', 'بيت الجملة'),
                            _buildChainDropdownItem('carrefour', 'كارفور'),
                            _buildChainDropdownItem('spinneys', 'سبينيس'),
                          ],
                          onChanged: (val) {
                            if (val != null && val != _selectedChain) {
                              setState(() {
                                _selectedChain = val;
                                _currentPage = 0;
                              });
                              _loadPricingCompliance();
                            }
                          },
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('open_product_master_from_pricing_btn'),
                          onPressed: _openProductMasterDialog,
                          icon: const Icon(Icons.qr_code_2_rounded, size: 18.0),
                          label: const Text('كارتة الأصناف والأسعار'),
                        ),
                      ],
                    ),

                    const Divider(height: 20.0),

                    // Search Bar by Item Code (كود الصنف), Barcode (الباركود), SKU Name, or Branch
                    TextField(
                      key: const ValueKey('pricing_compliance_search_input'),
                      controller: _searchController,
                      onSubmitted: (_) {
                        setState(() => _currentPage = 0);
                        _loadPricingCompliance();
                      },
                      onChanged: (val) {
                        if (val.isEmpty) {
                          setState(() => _currentPage = 0);
                          _loadPricingCompliance();
                        } else {
                          setState(() {});
                        }
                      },
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded, size: 20.0),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_searchController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18.0),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _currentPage = 0);
                                  _loadPricingCompliance();
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded, size: 18.0),
                              tooltip: 'بحث',
                              onPressed: () {
                                setState(() => _currentPage = 0);
                                _loadPricingCompliance();
                              },
                            ),
                          ],
                        ),
                        hintText:
                            'ابحث بكود الصنف (FGCL-0550-0001 / FGSL) أو الباركود (6221133...) أو اسم الصنف أو الفرع...',
                        isDense: true,
                        filled: true,
                        fillColor: colorScheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14.0,
                          vertical: 10.0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                    ),
                    const SizedBox(height: M3Spacing.sm),

                    // Row 2: Status & Category Selectors
                    Text(
                      'تصفية الأصناف والعروض:',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: M3Spacing.xs),
                    M3SegmentedButtonGroup<String>(
                      segments: _filterSegments,
                      selectedValue: _selectedFilter,
                      onSelectionChanged: (val) {
                        setState(() {
                          _selectedFilter = val;
                          _currentPage = 0;
                        });
                        _loadPricingCompliance();
                      },
                      showSelectedCheckmark: false,
                    ),
                    const SizedBox(height: M3Spacing.sm),
                    // Category Filter Chips Header
                    Text(
                      'التصنيف:',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: M3Spacing.xs),
                    _buildCategoryGrid(context),
                  ],
                ),
              ),
            ),

            if (_showPriceImpact) ...[
              M3Spacing.gapMD,
              _buildElasticitySection(context),
            ],

            M3Spacing.gapMD,

            // Tabular View Card
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
                        final isDesktop = constraints.maxWidth >= 720.0;
                        final titleRow = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.price_check_rounded, color: colorScheme.primary, size: 22.0),
                            const SizedBox(width: M3Spacing.xs),
                            Flexible(
                              child: Text(
                                'جدول مراقبة الامتثال السعري والعروض ($totalMatching عنصر)',
                                style: (isCompactScreen
                                        ? theme.textTheme.titleSmall
                                        : theme.textTheme.titleMedium)
                                    ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );

                        final toleranceBadge = Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: M3Spacing.xxs),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          child: Text(
                            'هامش السماح المعتمد: ±2.0%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );

                        if (isDesktop) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: titleRow),
                              const SizedBox(width: M3Spacing.sm),
                              toleranceBadge,
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            titleRow,
                            const SizedBox(height: M3Spacing.xs),
                            toleranceBadge,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: M3Spacing.xs),
                    _buildPaginationToolbar(
                      context: context,
                      totalItems: totalMatching,
                      startItem: startItem,
                      endItem: endItem,
                      totalPages: totalPages,
                    ),
                    const Divider(height: 24.0),
                    M3FadeThroughSwitcher(
                      child: _isLoading
                          ? const Padding(
                              key: ValueKey('pricing_loading'),
                              padding: EdgeInsets.all(40.0),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : displayedItems.isEmpty
                              ? Padding(
                                  key: const ValueKey('pricing_empty'),
                                  padding: const EdgeInsets.all(40.0),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.check_circle_outline_rounded, size: 48.0, color: colorScheme.primary),
                                        const SizedBox(height: M3Spacing.xs),
                                        Text(
                                          'لا توجد عناصر مطابقة لمعايير البحث والفلترة المحددة',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : LayoutBuilder(
                                  key: ValueKey('pricing_table_${_selectedFilter}_${_selectedCategory}_${_currentPage}_${_pageSize}_${displayedItems.length}'),
                                  builder: (context, tableConstraints) {
                                    final availableWidth = tableConstraints.maxWidth.isFinite
                                        ? tableConstraints.maxWidth
                                        : MediaQuery.sizeOf(context).width;
                                    final isCompact = availableWidth < 580.0;
                                    if (isCompact) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: displayedItems.map((item) {
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
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            item.skuName,
                                                            style: theme.textTheme.bodyMedium?.copyWith(
                                                              fontWeight: FontWeight.w800,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 2.0),
                                                          Text(
                                                            '${item.itemCode.isNotEmpty ? '[${item.itemCode}] • ' : ''}GTIN: ${item.barcode} | ${item.category}',
                                                            style: theme.textTheme.bodySmall?.copyWith(
                                                              color: colorScheme.onSurfaceVariant,
                                                              fontSize: 11.0,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8.0),
                                                    _buildPriceDeltaBadge(context, item),
                                                  ],
                                                ),
                                                const SizedBox(height: 6.0),
                                                Row(
                                                  children: [
                                                    Container(
                                                      width: 8.0,
                                                      height: 8.0,
                                                      decoration: BoxDecoration(
                                                        color: _getChainColor(item.retailerChain),
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6.0),
                                                    Flexible(
                                                      child: Text(
                                                        _getChainDisplayName(item.retailerChain),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: theme.textTheme.bodySmall?.copyWith(
                                                          color: colorScheme.onSurfaceVariant,
                                                          fontWeight: FontWeight.w700,
                                                          fontSize: 11.5,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8.0),
                                                    Text('•', style: TextStyle(color: colorScheme.outline)),
                                                    const SizedBox(width: 8.0),
                                                    Expanded(
                                                      child: Text(
                                                        item.storeName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: theme.textTheme.bodySmall?.copyWith(
                                                          color: colorScheme.onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const Padding(
                                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                                  child: Divider(height: 1.0),
                                                ),
                                                Wrap(
                                                  alignment: WrapAlignment.spaceBetween,
                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                  spacing: 16.0,
                                                  runSpacing: 8.0,
                                                  children: [
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          'السعر الفعلي',
                                                          style: theme.textTheme.labelSmall?.copyWith(
                                                            color: colorScheme.onSurfaceVariant,
                                                          ),
                                                        ),
                                                        Text(
                                                          CurrencyFormatter.formatEGP(
                                                            item.actualPrice,
                                                            showDecimals: true,
                                                          ),
                                                          style: theme.textTheme.bodyMedium?.copyWith(
                                                            fontWeight: FontWeight.w800,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          'السعر الاسترشادي RRP',
                                                          style: theme.textTheme.labelSmall?.copyWith(
                                                            color: colorScheme.onSurfaceVariant,
                                                          ),
                                                        ),
                                                        Text(
                                                          CurrencyFormatter.formatEGP(
                                                            item.recommendedPrice,
                                                            showDecimals: true,
                                                          ),
                                                          style: theme.textTheme.bodyMedium?.copyWith(
                                                            color: colorScheme.onSurfaceVariant,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    _buildPromoUpliftBadge(context, item),
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
                                        : ((availableWidth - 620.0) / 5.0).clamp(24.0, 72.0);
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
                                              DataColumn(label: Text('الصنف والباركود')),
                                              DataColumn(label: Text('السلسلة والفرع')),
                                              DataColumn(label: Text('السعر الفعلي')),
                                              DataColumn(label: Text('السعر الموصى به (RRP)')),
                                              DataColumn(label: Text('الفارق السعري (Delta)')),
                                              DataColumn(label: Text('حالة العرض والأثر البيعي')),
                                            ],
                                            rows: displayedItems.map((item) {
                                              return DataRow(
                                                cells: [
                                                  // SKU Name, Item Code & Barcode
                                                  DataCell(
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Text(
                                                          item.skuName,
                                                          style: theme.textTheme.bodyMedium?.copyWith(
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                        Text(
                                                          '${item.itemCode.isNotEmpty ? 'كود: ${item.itemCode} | ' : ''}GTIN: ${item.barcode} | ${item.category}${item.unitsPerCarton > 0 ? ' (${item.unitsPerCarton} ش)' : ''}',
                                                          style: theme.textTheme.bodySmall?.copyWith(
                                                            color: colorScheme.onSurfaceVariant,
                                                            fontSize: 11.0,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),

                                                  // Chain & Store
                                                  DataCell(
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Text(item.storeName, style: theme.textTheme.bodyMedium),
                                                        Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Container(
                                                              width: 8.0,
                                                              height: 8.0,
                                                              decoration: BoxDecoration(
                                                                color: _getChainColor(item.retailerChain),
                                                                shape: BoxShape.circle,
                                                              ),
                                                            ),
                                                            const SizedBox(width: 6.0),
                                                            Text(
                                                              _getChainDisplayName(item.retailerChain),
                                                              style: theme.textTheme.bodySmall?.copyWith(
                                                                color: colorScheme.onSurfaceVariant,
                                                                fontSize: 11.0,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),

                                                  // Actual Price & Margin
                                                  DataCell(
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Text(
                                                          CurrencyFormatter.formatEGP(item.actualPrice, showDecimals: true),
                                                          style: theme.textTheme.bodyMedium?.copyWith(
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                        if (item.retailerMarginPct != 0)
                                                          Text(
                                                            'هامش السلسلة: ${item.retailerMarginPct.toStringAsFixed(1)}%',
                                                            style: theme.textTheme.labelSmall?.copyWith(
                                                              fontSize: 10.0,
                                                              color: colorScheme.primary,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),

                                                  // Recommended Price (RRP) & Factory Cost
                                                  DataCell(
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Text(
                                                          CurrencyFormatter.formatEGP(item.recommendedPrice, showDecimals: true),
                                                          style: theme.textTheme.bodyMedium?.copyWith(
                                                            color: colorScheme.onSurfaceVariant,
                                                          ),
                                                        ),
                                                        if (item.factoryUnitCost > 0)
                                                          Text(
                                                            'صافي المصنع: ${item.factoryUnitCost.toStringAsFixed(2)} ج.م',
                                                            style: theme.textTheme.labelSmall?.copyWith(
                                                              fontSize: 10.0,
                                                              color: colorScheme.onSurfaceVariant,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),

                                                  // Price Delta % Badge
                                                  DataCell(_buildPriceDeltaBadge(context, item)),

                                                  // Promo Uplift Badge
                                                  DataCell(_buildPromoUpliftBadge(context, item)),
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
                    if (!_isLoading && displayedItems.isNotEmpty) ...[
                      const Divider(height: 24.0),
                      _buildPaginationToolbar(
                        context: context,
                        totalItems: totalMatching,
                        startItem: startItem,
                        endItem: endItem,
                        totalPages: totalPages,
                        isFooter: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationToolbar({
    required BuildContext context,
    required int totalItems,
    required int startItem,
    required int endItem,
    required int totalPages,
    bool isFooter = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canGoPrev = !_isLoading && _currentPage > 0;
    final canGoNext = !_isLoading && (_currentPage + 1) < totalPages;
    final keyPrefix = isFooter ? 'footer' : 'header';

    return Wrap(
      spacing: M3Spacing.sm,
      runSpacing: M3Spacing.xs,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Page Size Selector (25 / 50) as M3 Connected Segmented Button Group
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'عرض بكل صفحة:',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            M3SegmentedButtonGroup<int>(
              selectedValue: _pageSize,
              segments: _pageSizeOptions
                  .map(
                    (size) => M3SegmentItem<int>(
                      value: size,
                      label: '$size صنف',
                    ),
                  )
                  .toList(),
              onSelectionChanged: (size) {
                if (_pageSize != size) {
                  setState(() {
                    _pageSize = size;
                    _currentPage = 0;
                  });
                  _loadPricingCompliance();
                }
              },
            ),
          ],
        ),

        // Range Indicator & Prev/Next Controls
        Wrap(
          spacing: 4.0,
          runSpacing: 4.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                totalItems > 0
                    ? 'عرض $startItem-$endItem من $totalItems'
                    : '0 عنصر',
                key: ValueKey('${keyPrefix}_pricing_range_label'),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: ValueKey('${keyPrefix}_pricing_prev_page'),
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: 'الصفحة السابقة',
                  visualDensity: VisualDensity.compact,
                  onPressed: canGoPrev
                      ? () {
                          setState(() => _currentPage--);
                          _loadPricingCompliance();
                        }
                      : null,
                ),
                Text(
                  'صفحة ${_currentPage + 1} من $totalPages',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  key: ValueKey('${keyPrefix}_pricing_next_page'),
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'الصفحة التالية',
                  visualDensity: VisualDensity.compact,
                  onPressed: canGoNext
                      ? () {
                          setState(() => _currentPage++);
                          _loadPricingCompliance();
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color containerColor,
    required Color onContainerColor,
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
        padding: const EdgeInsets.all(M3Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: containerColor,
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Icon(icon, color: onContainerColor, size: 20.0),
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12.0),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4.0),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceDeltaBadge(BuildContext context, PricingComplianceItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color bg;
    Color fg;
    String label;
    IconData icon;

    final delta = item.priceDeltaPct;
    final deltaPrefix = delta > 0 ? '+$delta%' : '$delta%';

    switch (item.violationType) {
      case 'under_cutting':
        bg = colorScheme.errorContainer;
        fg = colorScheme.onErrorContainer;
        label = '$deltaPrefix حرق سعر';
        icon = Icons.arrow_downward_rounded;
        break;
      case 'price_gouging':
        bg = colorScheme.tertiaryContainer;
        fg = colorScheme.onTertiaryContainer;
        label = '$deltaPrefix زيادة سعر';
        icon = Icons.arrow_upward_rounded;
        break;
      case 'compliant':
      default:
        bg = colorScheme.primaryContainer;
        fg = colorScheme.onPrimaryContainer;
        label = '$deltaPrefix مطابق';
        icon = Icons.check_circle_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xs, vertical: M3Spacing.xxs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14.0, color: fg),
          const SizedBox(width: M3Spacing.xxs),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.bold,
                fontSize: 12.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoUpliftBadge(BuildContext context, PricingComplianceItem item) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!item.isPromoActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xs, vertical: 3.0),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Text(
          'بدون عرض',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 11.0,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xs, vertical: M3Spacing.xxs),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 14.0, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: M3Spacing.xxs),
          Flexible(
            child: Text(
              '+${item.promoUpliftPct.toStringAsFixed(1)}% أثر ترويجي',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
                fontSize: 11.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildElasticitySection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_elasticityPoints.isEmpty && !_isLoading) {
      return const SizedBox.shrink();
    }

    final summary = _elasticitySummary;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section Header with Close Button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Icon(Icons.insights_rounded, color: colorScheme.onPrimaryContainer, size: 22.0),
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مؤشر أثر حركة الأسعار على المبيعات الشهرية',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16.0,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        'مقارنة مباشرة بين حركة متوسط الأسعار ونمو الإيرادات الفعلية عبر الشهور',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12.0,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selectedChain != 'all' || _selectedYear > 0)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8.0),
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Text(
                      '${_selectedChain != 'all' ? _getChainDisplayName(_selectedChain) : 'كافة السلاسل'} • ${_selectedYear > 0 ? '$_selectedYear' : 'كل السنوات'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'إخفاء هذا القسم',
                  onPressed: () {
                    setState(() => _showPriceImpact = false);
                  },
                ),
              ],
            ),

            const SizedBox(height: 16.0),

            // Strategic Verdict Banner
            if (summary != null)
              Container(
                padding: const EdgeInsets.all(14.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, size: 22.0, color: colorScheme.primary),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            summary.overallVerdict,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.0,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12.0),
                    Wrap(
                      spacing: 12.0,
                      runSpacing: 8.0,
                      children: [
                        _buildMiniStatChip(
                          context,
                          'متوسط السعر الحالي',
                          CurrencyFormatter.formatEGP(summary.avgPriceCurrent, showDecimals: true),
                          Icons.sell_rounded,
                        ),
                        _buildMiniStatChip(
                          context,
                          'صافي تغير السعر',
                          '${summary.netPriceChangePct >= 0 ? '+' : ''}${summary.netPriceChangePct.toStringAsFixed(1)}%',
                          summary.netPriceChangePct >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          color: summary.netPriceChangePct >= 0 ? colorScheme.tertiary : colorScheme.error,
                        ),
                        _buildMiniStatChip(
                          context,
                          'نمو الإيرادات الإجمالي',
                          '${summary.netRevenueGrowthPct >= 0 ? '+' : ''}${summary.netRevenueGrowthPct.toStringAsFixed(1)}%',
                          summary.netRevenueGrowthPct >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                          color: summary.netRevenueGrowthPct >= 0 ? colorScheme.primary : colorScheme.error,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16.0),

            // Responsive Full-Width Monthly Breakdown Cards
            LayoutBuilder(
              builder: (context, constraints) {
                return Wrap(
                  spacing: 12.0,
                  runSpacing: 12.0,
                  children: List.generate(_elasticityPoints.length, (idx) {
                    final point = _elasticityPoints[idx];
                    final isRevUp = point.revenueChangePct > 0;
                    final isRevDown = point.revenueChangePct < 0;
                    final isPriceUp = point.priceChangePct > 0;

                    // Responsive card width so they fill space naturally
                    final double cardWidth = constraints.maxWidth >= 900
                        ? ((constraints.maxWidth - (12.0 * 3) - 1.0) / 4.0).clamp(200.0, 340.0)
                        : (constraints.maxWidth >= 600
                            ? ((constraints.maxWidth - 12.0 - 1.0) / 2.0).clamp(200.0, 400.0)
                            : constraints.maxWidth);

                    return Container(
                      width: cardWidth,
                      padding: const EdgeInsets.all(14.0),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withOpacity(0.6),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Row: Month Label & Growth Pill
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.calendar_today_rounded, size: 14.0, color: colorScheme.primary),
                                  const SizedBox(width: 6.0),
                                  Text(
                                    point.monthLabel,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.0,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                                decoration: BoxDecoration(
                                  color: isRevUp
                                      ? colorScheme.primaryContainer
                                      : (isRevDown ? colorScheme.errorContainer : colorScheme.surfaceContainerHighest),
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                child: Text(
                                  point.revenueChangePct == 0
                                      ? 'مستقر'
                                      : '${isRevUp ? '▲ +' : '▼ '}${point.revenueChangePct.toStringAsFixed(1)}% إيراد',
                                  style: TextStyle(
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.bold,
                                    color: isRevUp
                                        ? colorScheme.onPrimaryContainer
                                        : (isRevDown ? colorScheme.onErrorContainer : colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const Divider(height: 16.0),

                          // Price Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'متوسط سعر البيع:',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12.0,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    CurrencyFormatter.formatEGP(point.averagePrice, showDecimals: true),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.0,
                                    ),
                                  ),
                                  if (point.priceChangePct != 0) ...[
                                    const SizedBox(width: 4.0),
                                    Text(
                                      '(${isPriceUp ? '+' : ''}${point.priceChangePct.toStringAsFixed(1)}%)',
                                      style: TextStyle(
                                        fontSize: 11.0,
                                        fontWeight: FontWeight.w600,
                                        color: isPriceUp ? colorScheme.tertiary : colorScheme.error,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 6.0),

                          // Revenue Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'إجمالي المبيعات:',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12.0,
                                ),
                              ),
                              Text(
                                CurrencyFormatter.formatEGP(point.totalRevenue),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.0,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8.0),

                          // Verdict Footer
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(6.0),
                            ),
                            child: Text(
                              point.elasticityVerdict,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStatChip(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveColor = color ?? colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14.0, color: effectiveColor),
          const SizedBox(width: 4.0),
          Text(
            '$label: ',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: effectiveColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(BuildContext context) {
    final allCategories = ['الكل', ..._availableCategories];

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        // 3 columns on mobile (< 600dp), 4 columns on tablet (600 - 899dp), 6 on desktop
        final int crossAxisCount = availableWidth < 600.0
            ? 3
            : (availableWidth < 900.0 ? 4 : (availableWidth < 1200.0 ? 6 : 8));

        final isCompact = availableWidth < 600.0;
        const double horizontalSpacing = 6.0;
        const double verticalSpacing = 6.0;

        // Chunk categories into groups of crossAxisCount
        final chunks = <List<String>>[];
        for (var i = 0; i < allCategories.length; i += crossAxisCount) {
          chunks.add(
            allCategories.sublist(
              i,
              (i + crossAxisCount > allCategories.length)
                  ? allCategories.length
                  : i + crossAxisCount,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: chunks.map((chunk) {
            return Padding(
              padding: const EdgeInsets.only(bottom: verticalSpacing),
              child: Row(
                children: [
                  for (var col = 0; col < crossAxisCount; col++) ...[
                    if (col > 0) const SizedBox(width: horizontalSpacing),
                    if (col < chunk.length) ...[
                      Expanded(
                        child: SizedBox(
                          height: 38.0,
                          child: FilterChip(
                            label: Center(
                              child: Text(
                                chunk[col],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: isCompact ? 11.0 : 12.0,
                                  fontWeight: _selectedCategory == chunk[col]
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                            selected: _selectedCategory == chunk[col],
                            showCheckmark: false,
                            padding: EdgeInsets.zero,
                            labelPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                            onSelected: (_) {
                              setState(() {
                                _selectedCategory = chunk[col];
                                _currentPage = 0;
                              });
                              _loadPricingCompliance();
                            },
                          ),
                        ),
                      ),
                    ] else ...[
                      // Empty placeholder to preserve column alignment and width in the last row
                      const Expanded(child: SizedBox()),
                    ],
                  ],
                ],
              ),
            );
          }).toList(),
        );
      },
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
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
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
              isDense: true,
              isExpanded: isCompact,
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

  DropdownMenuItem<String> _buildChainDropdownItem(String key, String label) {
    return DropdownMenuItem<String>(
      value: key,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8.0,
            height: 8.0,
            decoration: BoxDecoration(
              color: _getChainColor(key),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8.0),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _getChainColor(String chain) {
    final c = chain.toLowerCase().trim();
    if (c.contains('fathalla') || c.contains('فتح الله')) return const Color(0xFF10B981);
    if (c.contains('beet') || c.contains('بيت الجملة')) return const Color(0xFF7C3AED);
    if (c.contains('gomla') || c.contains('جملة')) return const Color(0xFFF59E0B);
    if (c.contains('carrefour') || c.contains('كارفور')) return const Color(0xFF2563EB);
    if (c.contains('spinneys') || c.contains('سبينيس')) return const Color(0xFFE11D48);
    return const Color(0xFF6B7280);
  }

  String _getChainDisplayName(String chain) {
    final c = chain.toLowerCase().trim();
    if (c.contains('fathalla') || c.contains('فتح الله')) {
      return 'أسواق فتح الله (Fathalla)';
    }
    if (c.contains('beet') || c.contains('بيت الجملة')) {
      return 'بيت الجملة (Beet El Gomla)';
    }
    if (c.contains('gomla') || c.contains('جملة')) {
      return 'جملة ماركت (Gomla)';
    }
    if (c.contains('carrefour') || c.contains('كارفور')) {
      return 'كارفور (Carrefour)';
    }
    if (c.contains('spinneys') || c.contains('سبينيس')) {
      return 'سبينيس (Spinneys)';
    }
    return chain;
  }
}

import 'package:flutter/material.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_segmented_button_group.dart';
import '../../../../core/widgets/table_scroll_container.dart';

/// CompetitorComparisonScreen (Compare / المنافسة)
/// Allows the user to select any Own SKU and immediately inspect all competing SKUs
/// from rival companies, comparing selling price (Higher / Lower / Equal),
/// normalized price per Liter/Kg, chain-by-chain prices, market share impact,
/// and an interactive "What-If" price simulator.
class CompetitorComparisonScreen extends StatefulWidget {
  final ApiClient apiClient;

  const CompetitorComparisonScreen({
    super.key,
    required this.apiClient,
  });

  @override
  State<CompetitorComparisonScreen> createState() =>
      _CompetitorComparisonScreenState();
}

class _CompetitorComparisonScreenState
    extends State<CompetitorComparisonScreen> {
  bool _isLoading = true;
  List<OwnSkuCompetitiveGroupModel> _allGroups = [];
  List<OwnSkuCompetitiveGroupModel> _filteredGroups = [];
  String? _selectedOwnBarcode;
  String _selectedChain = 'all';
  String _selectedCategory = 'الكل';
  String _competitorFilter = 'all'; // 'all', 'higher', 'lower', 'equal'
  String _searchQuery = '';
  bool _showWhatIfSimulator = false;
  double? _simulatedOwnPrice;

  final TextEditingController _searchController = TextEditingController();
  late String _lastTenantId;

  final List<M3SegmentItem<String>> _compPositionSegments = const [
    M3SegmentItem(
      value: 'all',
      label: 'كل المنافسين',
      icon: Icons.compare_arrows_rounded,
    ),
    M3SegmentItem(
      value: 'higher',
      label: 'المنافس أغلى (أعلى)',
      icon: Icons.trending_up_rounded,
    ),
    M3SegmentItem(
      value: 'lower',
      label: 'المنافس أرخص (أقل)',
      icon: Icons.trending_down_rounded,
    ),
  ];

  static const List<({String code, String labelAr})> _chainOptions = [
    (code: 'all', labelAr: 'كل السلاسل التجارية'),
    (code: 'fathalla', labelAr: 'أسواق فتح الله'),
    (code: 'carrefour', labelAr: 'كارفور مصر'),
    (code: 'beet-elgomla', labelAr: 'بيت الجملة'),
    (code: 'gomla', labelAr: 'جملة ماركت'),
    (code: 'spinneys', labelAr: 'سبينيس مصر'),
  ];

  @override
  void initState() {
    super.initState();
    _lastTenantId = widget.apiClient.tenantId;
    _loadCompetitiveData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CompetitorComparisonScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient ||
        _lastTenantId != widget.apiClient.tenantId) {
      _lastTenantId = widget.apiClient.tenantId;
      _selectedChain = 'all';
      _selectedCategory = 'الكل';
      _competitorFilter = 'all';
      _searchQuery = '';
      _searchController.clear();
      _simulatedOwnPrice = null;
      _loadCompetitiveData();
    }
  }

  Future<void> _loadCompetitiveData() async {
    setState(() => _isLoading = true);
    final groups = await widget.apiClient.getCompetitiveComparisonGroups(
      chain: _selectedChain == 'all' ? null : _selectedChain,
    );

    if (!mounted) return;
    setState(() {
      _allGroups = groups;
      _applyLocalFilters();
      _isLoading = false;
    });
  }

  void _applyLocalFilters() {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _allGroups.where((g) {
      if (_selectedCategory != 'الكل' && g.category != _selectedCategory) {
        return false;
      }
      if (q.isNotEmpty) {
        final matchOwn = g.ownSkuName.toLowerCase().contains(q) ||
            g.ownBarcode.toLowerCase().contains(q) ||
            g.ownBrand.toLowerCase().contains(q) ||
            g.category.toLowerCase().contains(q);
        final matchComp = g.competitors.any(
          (c) =>
              c.skuName.toLowerCase().contains(q) ||
              c.brand.toLowerCase().contains(q) ||
              c.supplierName.toLowerCase().contains(q),
        );
        if (!matchOwn && !matchComp) return false;
      }
      return true;
    }).toList();

    _filteredGroups = filtered;
    if (_filteredGroups.isNotEmpty) {
      final stillExists = _filteredGroups
          .any((g) => g.ownBarcode == _selectedOwnBarcode);
      if (!stillExists) {
        _selectedOwnBarcode = _filteredGroups.first.ownBarcode;
        _simulatedOwnPrice = null;
      }
    } else {
      _selectedOwnBarcode = null;
      _simulatedOwnPrice = null;
    }
  }

  OwnSkuCompetitiveGroupModel? get _selectedGroup {
    if (_filteredGroups.isEmpty) return null;
    for (final g in _filteredGroups) {
      if (g.ownBarcode == _selectedOwnBarcode) return g;
    }
    return _filteredGroups.first;
  }

  List<String> get _availableCategories {
    final seen = <String>{};
    final list = <String>['الكل'];
    for (final g in _allGroups) {
      if (g.category.isNotEmpty && seen.add(g.category)) {
        list.add(g.category);
      }
    }
    return list;
  }

  void _openAddCompetitorDialog(OwnSkuCompetitiveGroupModel currentGroup) {
    final nameCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final supplierCtrl = TextEditingController();
    final volumeCtrl = TextEditingController(
        text: currentGroup.packVolumeUnits.toStringAsFixed(1));
    final priceCtrl = TextEditingController();
    bool isPromo = false;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colorScheme = theme.colorScheme;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24.0),
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Icon(
                        Icons.add_chart_rounded,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إضافة صنف منافس مرصود بالسوق',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'ربط مباشر مع: ${currentGroup.ownSkuName}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 480.0,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'اسم الصنف المنافس (مثال: بريل ليمون 2.5 لتر)',
                            prefixIcon: Icon(Icons.inventory_2_outlined),
                          ),
                        ),
                        const SizedBox(height: 12.0),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: brandCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'العلامة التجارية (Brand)',
                                  prefixIcon: Icon(Icons.sell_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              child: TextField(
                                controller: supplierCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'الشركة المنافسة (Supplier)',
                                  prefixIcon: Icon(Icons.business_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12.0),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: priceCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                  labelText:
                                      'سعر بيع المنافس بالجنيه (سعرنا: ${currentGroup.ownUnitPrice.toStringAsFixed(0)} ج.م)',
                                  prefixIcon:
                                      const Icon(Icons.payments_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              child: TextField(
                                controller: volumeCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                  labelText:
                                      'الوزن/الحجم بالـ (${currentGroup.volumeUnitLabel})',
                                  prefixIcon: const Icon(Icons.scale_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12.0),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'هذا السعر خاضع لعرض ترويجي حالياً لدى المنافس (Promo Price)',
                            style: TextStyle(
                                fontSize: 13.0, fontWeight: FontWeight.w600),
                          ),
                          value: isPromo,
                          onChanged: (v) => setDialogState(() => isPromo = v),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  M3Button.text(
                    label: 'إلغاء',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  M3Button.primary(
                    label: 'إضافة للمقارنة',
                    icon: Icons.check_rounded,
                    onPressed: () {
                      final compName = nameCtrl.text.trim();
                      final compPrice =
                          double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                      final compVol =
                          double.tryParse(volumeCtrl.text.trim()) ??
                              currentGroup.packVolumeUnits;
                      if (compName.isEmpty || compPrice <= 0) return;

                      widget.apiClient.addCustomCompetitorSku(
                        ownBarcode: currentGroup.ownBarcode,
                        ownSkuName: currentGroup.ownSkuName,
                        ownUnitPrice: currentGroup.ownUnitPrice,
                        ownVolumeUnits: currentGroup.packVolumeUnits,
                        ownVolumeUnitLabel: currentGroup.volumeUnitLabel,
                        competitorSkuName: compName,
                        competitorBrand: brandCtrl.text.trim().isNotEmpty
                            ? brandCtrl.text.trim()
                            : 'براند منافس',
                        competitorSupplier: supplierCtrl.text.trim().isNotEmpty
                            ? supplierCtrl.text.trim()
                            : 'شركة منافسة',
                        category: currentGroup.category,
                        packSizeLabel:
                            '${compVol.toStringAsFixed(compVol == compVol.roundToDouble() ? 0 : 1)} ${currentGroup.volumeUnitLabel}',
                        packVolumeUnits: compVol,
                        competitorPrice: compPrice,
                        retailerChain: _selectedChain == 'all'
                            ? 'fathalla'
                            : _selectedChain,
                        isPromoActive: isPromo,
                      );
                      Navigator.pop(ctx);
                      _loadCompetitiveData();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompactScreen = MediaQuery.sizeOf(context).width < 600.0;

    // Aggregate KPIs across all Own SKUs
    final totalOwnSkus = _allGroups.length;
    int totalCompetitorSkus = 0;
    int advantageSkusCount = 0;
    int undercutRiskSkusCount = 0;
    double sumPriceIndex = 0.0;

    for (final g in _allGroups) {
      totalCompetitorSkus += g.competitors.length;
      sumPriceIndex += g.priceIndex;
      if (g.ownUnitPrice < g.avgCompetitorPrice) {
        advantageSkusCount++;
      }
      if (g.lowerPricedCompetitorsCount > 0) {
        undercutRiskSkusCount++;
      }
    }
    final avgPriceIndex =
        totalOwnSkus > 0 ? sumPriceIndex / totalOwnSkus : 100.0;

    final selectedGroup = _selectedGroup;

    return SingleChildScrollView(
      padding: isCompactScreen ? M3Spacing.pSm : M3Spacing.pMd,
      child: M3ContentBoundary(
        maxWidth: 1440.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Unified Page Header
            M3PageHeader(
              titleEn: 'Compare & Competitor Intelligence',
              subtitleAr:
                  'المنافسة ومقارنة أصناف الشركة بالأصناف المنافسة (سعر البيع: أعلى / أقل، سعر اللتر/الكجم، ومصفوفة السلاسل)',
              actions: M3ActionButtonGroup(
                actions: [
                  if (selectedGroup != null)
                    M3ActionItem(
                      label: _showWhatIfSimulator
                          ? 'إخفاء المحاكي'
                          : 'محاكي السعر',
                      icon: Icons.tune_rounded,
                      isPrimary: _showWhatIfSimulator,
                      onPressed: () {
                        setState(() {
                          _showWhatIfSimulator = !_showWhatIfSimulator;
                          if (_showWhatIfSimulator &&
                              _simulatedOwnPrice == null) {
                            _simulatedOwnPrice = selectedGroup.ownUnitPrice;
                          }
                        });
                      },
                    ),
                  if (selectedGroup != null)
                    M3ActionItem(
                      label: 'إضافة منافس',
                      icon: Icons.add_rounded,
                      onPressed: () => _openAddCompetitorDialog(selectedGroup),
                    ),
                  M3ActionItem(
                    label: 'تحديث',
                    icon: Icons.refresh_rounded,
                    onPressed: _isLoading ? null : _loadCompetitiveData,
                  ),
                ],
              ),
            ),

            M3Spacing.gapMD,

            // 2. Top 4 Competitive Summary KPI Cards
            LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 900.0;
                final cards = [
                  _buildKpiCard(
                    context: context,
                    title: 'أصنافنا في المقارنة (My SKUs)',
                    value: '$totalOwnSkus صنف أساسي',
                    subtitle: 'أمام $totalCompetitorSkus صنف منافس بالسوق',
                    icon: Icons.inventory_2_outlined,
                    containerColor: colorScheme.primaryContainer,
                    onContainerColor: colorScheme.onPrimaryContainer,
                  ),
                  _buildKpiCard(
                    context: context,
                    title: 'ميزة سعرية تنافسية (نحن الأرخص 🟢)',
                    value: '$advantageSkusCount من $totalOwnSkus أصناف',
                    subtitle: 'سعر بيعنا أقل من متوسط أسعار المنافسين',
                    icon: Icons.trending_down_rounded,
                    containerColor: const Color(0xFFE6F4EA),
                    onContainerColor: const Color(0xFF0D652D),
                  ),
                  _buildKpiCard(
                    context: context,
                    title: 'تهديد سعري من منافس أرخص (🔴)',
                    value: '$undercutRiskSkusCount أصناف معرضة',
                    subtitle: 'يوجد منافس واحد على الأقل يبيع بسعر أقل منا',
                    icon: Icons.warning_amber_rounded,
                    containerColor: const Color(0xFFFCE8E6),
                    onContainerColor: const Color(0xFFA50E0E),
                  ),
                  _buildKpiCard(
                    context: context,
                    title: 'مؤشر السعر التنافسي (Price Index)',
                    value: '${avgPriceIndex.toStringAsFixed(1)}%',
                    subtitle: avgPriceIndex < 100
                        ? 'أقل من متوسط السوق بـ ${(100.0 - avgPriceIndex).toStringAsFixed(1)}%'
                        : 'أعلى من متوسط السوق بـ ${(avgPriceIndex - 100.0).toStringAsFixed(1)}%',
                    icon: Icons.speed_rounded,
                    containerColor: colorScheme.secondaryContainer,
                    onContainerColor: colorScheme.onSecondaryContainer,
                  ),
                ];

                if (isDesktop) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < cards.length; i++) ...[
                          Expanded(child: cards[i]),
                          if (i < cards.length - 1) M3Spacing.gapSM,
                        ],
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    for (int i = 0; i < cards.length; i++) ...[
                      cards[i],
                      if (i < cards.length - 1) M3Spacing.gapSM,
                    ],
                  ],
                );
              },
            ),

            M3Spacing.gapMD,

            // 3. Filters Bar (Chain Selector + Category Chips + Search)
            _buildFilterToolbar(context),

            M3Spacing.gapMD,

            // 4. Master-Detail Split Layout
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64.0),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_filteredGroups.isEmpty || selectedGroup == null)
              _buildEmptyState(context)
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 960.0;
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Right side in RTL: Master list of Own SKUs (360dp)
                        SizedBox(
                          width: 370.0,
                          child: _buildOwnSkusMasterPanel(
                            context,
                            selectedGroup,
                          ),
                        ),
                        M3Spacing.gapMD,
                        // Left side in RTL: Detailed Competitor Comparison for Selected Own SKU
                        Expanded(
                          child: _buildCompetitorDetailPanel(
                            context,
                            selectedGroup,
                          ),
                        ),
                      ],
                    );
                  } else {
                    // Compact / Tablet stacked view
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildOwnSkusMasterPanel(
                          context,
                          selectedGroup,
                          isCompactList: true,
                        ),
                        M3Spacing.gapMD,
                        _buildCompetitorDetailPanel(
                          context,
                          selectedGroup,
                        ),
                      ],
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final categories = _availableCategories;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              // Search input
              SizedBox(
                width: 320.0,
                height: 42.0,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                      _applyLocalFilters();
                    });
                  },
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم الصنف، البراند، أو المنافس...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20.0),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18.0),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _applyLocalFilters();
                              });
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 8.0,
                    ),
                    filled: true,
                    fillColor: colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999.0),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999.0),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                  ),
                ),
              ),

              // Retail Chain Selector
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: 18.0,
                    color: colorScheme.primary,
                  ),
                  Text(
                    'السلسلة التجارية:',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final ch in _chainOptions)
                    ChoiceChip(
                      label: Text(ch.labelAr),
                      selected: _selectedChain == ch.code,
                      onSelected: (sel) {
                        if (!sel) return;
                        setState(() => _selectedChain = ch.code);
                        _loadCompetitiveData();
                      },
                    ),
                ],
              ),
            ],
          ),

          if (categories.length > 1) ...[
            const SizedBox(height: 12.0),
            const Divider(height: 1.0),
            const SizedBox(height: 10.0),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Icon(
                    Icons.category_outlined,
                    size: 18.0,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    'الفئة:',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  for (final cat in categories)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8.0),
                      child: FilterChip(
                        label: Text(cat),
                        selected: _selectedCategory == cat,
                        onSelected: (_) {
                          setState(() {
                            _selectedCategory = cat;
                            _applyLocalFilters();
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Master List Panel showing the company's own SKUs.
  /// Clicking any SKU selects it and updates the Competitor Detail Panel.
  Widget _buildOwnSkusMasterPanel(
    BuildContext context,
    OwnSkuCompetitiveGroupModel selectedGroup, {
    bool isCompactList = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24.0),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(18.0, 16.0, 18.0, 14.0),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(23.0)),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Icon(
                    Icons.touch_app_rounded,
                    size: 18.0,
                    color: colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'اختر صنفك للمقارنة (Select SKU)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'اضغط على الصنف لعرض الأصناف المنافسة له وأسعارها',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10.0,
                    vertical: 4.0,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(999.0),
                  ),
                  child: Text(
                    '${_filteredGroups.length} صنف',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // List of Own SKUs
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                for (final group in _filteredGroups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: _buildOwnSkuSelectorCard(
                      context,
                      group: group,
                      isSelected: group.ownBarcode == selectedGroup.ownBarcode,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnSkuSelectorCard(
    BuildContext context, {
    required OwnSkuCompetitiveGroupModel group,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Calculate our price gap vs average competitor
    final vsAvgDiffEgp = group.ownUnitPrice - group.avgCompetitorPrice;
    final vsAvgDiffPct = group.avgCompetitorPrice > 0
        ? (vsAvgDiffEgp / group.avgCompetitorPrice) * 100.0
        : 0.0;

    final bool weAreCheaper = vsAvgDiffPct < -1.5;
    final bool weAreMoreExpensive = vsAvgDiffPct > 1.5;

    final Color badgeBg = weAreCheaper
        ? const Color(0xFFE6F4EA)
        : weAreMoreExpensive
            ? const Color(0xFFFCE8E6)
            : colorScheme.secondaryContainer;
    final Color badgeFg = weAreCheaper
        ? const Color(0xFF0D652D)
        : weAreMoreExpensive
            ? const Color(0xFFA50E0E)
            : colorScheme.onSecondaryContainer;
    final String badgeText = weAreCheaper
        ? 'سعرنا أقل من السوق بـ ${vsAvgDiffPct.abs().toStringAsFixed(1)}%'
        : weAreMoreExpensive
            ? 'سعرنا أعلى من السوق بـ +${vsAvgDiffPct.toStringAsFixed(1)}%'
            : 'مساوي لمتوسط السوق';

    return Material(
      color: isSelected ? colorScheme.primaryContainer : colorScheme.surface,
      borderRadius: BorderRadius.circular(18.0),
      elevation: isSelected ? 2.0 : 0.0,
      child: InkWell(
        borderRadius: BorderRadius.circular(18.0),
        onTap: () {
          setState(() {
            _selectedOwnBarcode = group.ownBarcode;
            _simulatedOwnPrice = group.ownUnitPrice;
          });
        },
        child: AnimatedContainer(
          duration: M3Motion.short4,
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: isSelected ? 2.0 : 1.0,
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
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                                vertical: 2.0,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6.0),
                              ),
                              child: Text(
                                group.ownBrand,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6.0),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                                vertical: 2.0,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(6.0),
                              ),
                              child: Text(
                                group.packSizeLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6.0),
                        Text(
                          group.ownSkuName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: isSelected
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  // Price pill
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${group.ownUnitPrice.toStringAsFixed(0)} ج.م',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: colorScheme.primary,
                        ),
                      ),
                      Text(
                        '${group.ownPricePerUnitVolume.toStringAsFixed(1)} ج/${group.volumeUnitLabel}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 3.0,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(999.0),
                    ),
                    child: Text(
                      badgeText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: badgeFg,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${group.competitors.length} منافسين',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4.0),
                      Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 13.0,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Detail Panel showing the Selected Own SKU at the top and all competing SKUs below it.
  Widget _buildCompetitorDetailPanel(
    BuildContext context,
    OwnSkuCompetitiveGroupModel group,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final effectiveOwnPrice = (_showWhatIfSimulator && _simulatedOwnPrice != null)
        ? _simulatedOwnPrice!
        : group.ownUnitPrice;
    final effectiveOwnPricePerVol = group.packVolumeUnits > 0
        ? double.parse(
            (effectiveOwnPrice / group.packVolumeUnits).toStringAsFixed(2))
        : effectiveOwnPrice;

    // Recompute competitor price differences dynamically if simulator is active
    final adjustedCompetitors = group.competitors.map((c) {
      final diffEgp = c.unitPrice - effectiveOwnPrice;
      final diffPct =
          effectiveOwnPrice > 0 ? (diffEgp / effectiveOwnPrice) * 100.0 : 0.0;
      final String pos;
      if (diffPct > 1.5) {
        pos = 'higher';
      } else if (diffPct < -1.5) {
        pos = 'lower';
      } else {
        pos = 'equal';
      }
      return c.copyWithPriceContext(
        priceDiffEgp: double.parse(diffEgp.toStringAsFixed(2)),
        priceDiffPct: double.parse(diffPct.toStringAsFixed(1)),
        pricePosition: pos,
      );
    }).toList();

    final visibleCompetitors = adjustedCompetitors.where((c) {
      if (_competitorFilter == 'higher') return c.pricePosition == 'higher';
      if (_competitorFilter == 'lower') return c.pricePosition == 'lower';
      return true;
    }).toList();

    final higherCount =
        adjustedCompetitors.where((c) => c.pricePosition == 'higher').length;
    final lowerCount =
        adjustedCompetitors.where((c) => c.pricePosition == 'lower').length;
    final equalCount =
        adjustedCompetitors.where((c) => c.pricePosition == 'equal').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A. Selected Own SKU Benchmark Spotlight Card
        _buildSelectedOwnSkuSpotlight(
          context,
          group: group,
          effectiveOwnPrice: effectiveOwnPrice,
          effectiveOwnPricePerVol: effectiveOwnPricePerVol,
          higherCount: higherCount,
          lowerCount: lowerCount,
          equalCount: equalCount,
        ),

        // B. Interactive What-If Price Simulator (if toggled)
        if (_showWhatIfSimulator) ...[
          M3Spacing.gapMD,
          _buildWhatIfPriceSimulatorCard(
            context,
            group: group,
            effectiveOwnPrice: effectiveOwnPrice,
            adjustedCompetitors: adjustedCompetitors,
          ),
        ],

        M3Spacing.gapMD,

        // C. Filter Header for Competitors + Cards Grid
        Container(
          padding: const EdgeInsets.all(18.0),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24.0),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12.0,
                runSpacing: 12.0,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.compare_arrows_rounded,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8.0),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الأصناف المنافسة المباشرة (${visibleCompetitors.length} من ${adjustedCompetitors.length})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'مقارنة سعر البيع للمستهلك (أعلى أم أقل من سعرك) + سعر الـ ${group.volumeUnitLabel} الصافي',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  M3SegmentedButtonGroup<String>(
                    segments: _compPositionSegments,
                    selectedValue: _competitorFilter,
                    onSelectionChanged: (val) {
                      setState(() => _competitorFilter = val);
                    },
                  ),
                ],
              ),

              M3Spacing.gapMD,

              if (visibleCompetitors.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32.0),
                  child: Center(
                    child: Text(
                      'لا توجد أصناف منافسة تطابق هذا الفلتر حالياً.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                Column(
                  children: [
                    for (final comp in visibleCompetitors) ...[
                      _buildCompetitorComparisonCard(
                        context,
                        group: group,
                        competitor: comp,
                        effectiveOwnPrice: effectiveOwnPrice,
                        effectiveOwnPricePerVol: effectiveOwnPricePerVol,
                      ),
                      const SizedBox(height: 12.0),
                    ],
                  ],
                ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // D. Chain-by-Chain Price Matrix Table (Fathalla, Carrefour, Beet El-Gomla, Gomla, Spinneys)
        _buildChainByChainMatrixCard(
          context,
          group: group,
          competitors: adjustedCompetitors,
        ),
      ],
    );
  }

  Widget _buildSelectedOwnSkuSpotlight(
    BuildContext context, {
    required OwnSkuCompetitiveGroupModel group,
    required double effectiveOwnPrice,
    required double effectiveOwnPricePerVol,
    required int higherCount,
    required int lowerCount,
    required int equalCount,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.85),
            colorScheme.surfaceContainerLow,
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(24.0),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 6.0,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10.0,
                            vertical: 4.0,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(999.0),
                          ),
                          child: Text(
                            'صنف شركتي (My Selected SKU)',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10.0,
                            vertical: 4.0,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(999.0),
                          ),
                          child: Text(
                            'الفئة: ${group.category}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10.0,
                            vertical: 4.0,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(999.0),
                          ),
                          child: Text(
                            'العبوة: ${group.packSizeLabel}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          'باركود: ${group.ownBarcode}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10.0),
                    Text(
                      group.ownSkuName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),

              // Summary Price Boxes
              Wrap(
                spacing: 10.0,
                runSpacing: 10.0,
                children: [
                  _buildSpotlightMetricBox(
                    context,
                    label: 'سعر بيعنا الحالي',
                    value: '${effectiveOwnPrice.toStringAsFixed(1)} ج.م',
                    subValue:
                        '${effectiveOwnPricePerVol.toStringAsFixed(1)} ج.م / ${group.volumeUnitLabel}',
                    isHighlighted: true,
                  ),
                  _buildSpotlightMetricBox(
                    context,
                    label: 'متوسط سعر المنافسين',
                    value: '${group.avgCompetitorPrice.toStringAsFixed(1)} ج.م',
                    subValue:
                        'المدى: ${group.minCompetitorPrice.toStringAsFixed(0)} - ${group.maxCompetitorPrice.toStringAsFixed(0)} ج.م',
                  ),
                  _buildSpotlightMetricBox(
                    context,
                    label: 'حصتنا داخل الفئة',
                    value: '${group.ownCategorySharePct.toStringAsFixed(1)}%',
                    subValue: '${group.ownUnitsSold} عبوة مباعة',
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16.0),
          const Divider(height: 1.0),
          const SizedBox(height: 12.0),

          // Quick Verdict Chips (How many competitors are higher vs lower)
          Wrap(
            spacing: 10.0,
            runSpacing: 8.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'ملخص الموقف التنافسي لهذا الصنف:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              _buildStatusCountPill(
                label: '$higherCount منافس سعره أعلى منك (أنت أرخص)',
                bgColor: const Color(0xFFE6F4EA),
                fgColor: const Color(0xFF0D652D),
                icon: Icons.arrow_upward_rounded,
              ),
              _buildStatusCountPill(
                label: '$lowerCount منافس سعره أقل منك (أنت أغلى)',
                bgColor: const Color(0xFFFCE8E6),
                fgColor: const Color(0xFFA50E0E),
                icon: Icons.arrow_downward_rounded,
              ),
              if (equalCount > 0)
                _buildStatusCountPill(
                  label: '$equalCount منافس مساوي لسعرك',
                  bgColor: colorScheme.secondaryContainer,
                  fgColor: colorScheme.onSecondaryContainer,
                  icon: Icons.drag_handle_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpotlightMetricBox(
    BuildContext context, {
    required String label,
    required String value,
    required String subValue,
    bool isHighlighted = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: isHighlighted ? colorScheme.primary : colorScheme.surface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isHighlighted
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isHighlighted
                  ? colorScheme.onPrimary.withValues(alpha: 0.9)
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2.0),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: isHighlighted
                  ? colorScheme.onPrimary
                  : colorScheme.onSurface,
            ),
          ),
          Text(
            subValue,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isHighlighted
                  ? colorScheme.onPrimary.withValues(alpha: 0.85)
                  : colorScheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCountPill({
    required String label,
    required Color bgColor,
    required Color fgColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15.0, color: fgColor),
          const SizedBox(width: 6.0),
          Text(
            label,
            style: TextStyle(
              color: fgColor,
              fontWeight: FontWeight.w800,
              fontSize: 12.0,
            ),
          ),
        ],
      ),
    );
  }

  /// Interactive What-If Price Simulator Card
  Widget _buildWhatIfPriceSimulatorCard(
    BuildContext context, {
    required OwnSkuCompetitiveGroupModel group,
    required double effectiveOwnPrice,
    required List<CompetitorSkuComparisonModel> adjustedCompetitors,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final minSlider = (group.ownUnitPrice * 0.70).roundToDouble();
    final maxSlider = (group.ownUnitPrice * 1.30).roundToDouble();
    final currentVal = effectiveOwnPrice.clamp(minSlider, maxSlider);

    // Estimate volume elasticity (-1.35 elasticity coefficient typical in Egyptian FMCG)
    final pctChange = group.ownUnitPrice > 0
        ? (currentVal - group.ownUnitPrice) / group.ownUnitPrice
        : 0.0;
    final projectedUnits =
        (group.ownUnitsSold * (1.0 - (pctChange * 1.35))).round().clamp(10, 999999);
    final projectedRev = projectedUnits * currentVal;
    final revDiff = projectedRev - group.ownNetRevenue;

    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: colorScheme.primary),
                  const SizedBox(width: 8.0),
                  Text(
                    'محاكي تعديل السعر التفاعلي (What-If Price Simulator)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              M3Button.text(
                label: 'إعادة للسعر الأصلي (${group.ownUnitPrice.toStringAsFixed(0)} ج.م)',
                icon: Icons.restart_alt_rounded,
                onPressed: () {
                  setState(() => _simulatedOwnPrice = group.ownUnitPrice);
                },
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          Row(
            children: [
              Text(
                '${minSlider.toStringAsFixed(0)} ج.م',
                style: theme.textTheme.labelMedium,
              ),
              Expanded(
                child: Slider(
                  value: currentVal,
                  min: minSlider,
                  max: maxSlider,
                  divisions: (maxSlider - minSlider).toInt().clamp(1, 200),
                  label: '${currentVal.toStringAsFixed(0)} ج.م',
                  onChanged: (v) {
                    setState(() => _simulatedOwnPrice = v.roundToDouble());
                  },
                ),
              ),
              Text(
                '${maxSlider.toStringAsFixed(0)} ج.م',
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
          Wrap(
            spacing: 16.0,
            runSpacing: 8.0,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'السعر التجريبي: ${currentVal.toStringAsFixed(0)} ج.م (${(pctChange * 100).toStringAsFixed(1)}%)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                ),
              ),
              Text(
                'الكمية المتوقعة: $projectedUnits عبوة (بدلاً من ${group.ownUnitsSold})',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'الأثر على الإيرادات: ${revDiff >= 0 ? '+' : ''}${revDiff.toStringAsFixed(0)} ج.م',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: revDiff >= 0
                      ? const Color(0xFF0D652D)
                      : const Color(0xFFA50E0E),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Individual Competitor SKU Card showing Higher/Lower badge, price gap, normalized liter/kg price, and volume share.
  Widget _buildCompetitorComparisonCard(
    BuildContext context, {
    required OwnSkuCompetitiveGroupModel group,
    required CompetitorSkuComparisonModel competitor,
    required double effectiveOwnPrice,
    required double effectiveOwnPricePerVol,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bool isCompHigher = competitor.pricePosition == 'higher';
    final bool isCompLower = competitor.pricePosition == 'lower';

    // Color semantics:
    // If competitor is HIGHER than us -> Green (We have a price advantage / we are cheaper)
    // If competitor is LOWER than us -> Red (Competitor undercuts our price)
    // If equal -> Blue
    final Color statusBg = isCompHigher
        ? const Color(0xFFE6F4EA)
        : isCompLower
            ? const Color(0xFFFCE8E6)
            : colorScheme.secondaryContainer;
    final Color statusFg = isCompHigher
        ? const Color(0xFF0D652D)
        : isCompLower
            ? const Color(0xFFA50E0E)
            : colorScheme.onSecondaryContainer;
    final IconData statusIcon = isCompHigher
        ? Icons.arrow_upward_rounded
        : isCompLower
            ? Icons.arrow_downward_rounded
            : Icons.drag_handle_rounded;

    final String verdictTitle = isCompHigher
        ? 'المنافس أعلى من سعرك بـ +${competitor.priceDiffEgp.abs().toStringAsFixed(1)} ج.م (+${competitor.priceDiffPct.abs().toStringAsFixed(1)}%)'
        : isCompLower
            ? 'المنافس أقل من سعرك بـ -${competitor.priceDiffEgp.abs().toStringAsFixed(1)} ج.م (-${competitor.priceDiffPct.abs().toStringAsFixed(1)}%)'
            : 'سعر المنافس مساوي لسعرك تقريباً';

    final String verdictSubtitle = isCompHigher
        ? 'صنفك أرخص للمستهلك (ميزة تنافسية لصالحك)'
        : isCompLower
            ? 'المنافس يبيع بسعر أرخص منك (انتبه لسحب الحصة السوقية)'
            : 'تطابق سعري مباشر على الرف';

    // Compare price per Liter / Kg to detect Shrinkflation
    final double volDiff =
        competitor.pricePerUnitVolume - effectiveOwnPricePerVol;
    final bool shrinkflationDetected =
        isCompLower && competitor.pricePerUnitVolume > effectiveOwnPricePerVol;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(
          color: isCompLower
              ? const Color(0xFFA50E0E).withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.7),
          width: isCompLower ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Competitor Info
              SizedBox(
                width: 380.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6.0,
                      runSpacing: 6.0,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 3.0,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6.0),
                          ),
                          child: Text(
                            competitor.brand,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                        Text(
                          competitor.supplierName,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 2.0,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6.0),
                          ),
                          child: Text(
                            'عبوة: ${competitor.packSizeLabel}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (competitor.isPromoActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                              vertical: 2.0,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF7E0),
                              borderRadius: BorderRadius.circular(6.0),
                              border:
                                  Border.all(color: const Color(0xFFEA8600)),
                            ),
                            child: const Text(
                              'عرض ترويجي نشط (Promo)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFB06000),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6.0),
                    Text(
                      competitor.skuName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),

              // Big Higher / Lower Verdict Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14.0,
                  vertical: 10.0,
                ),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(14.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusFg, size: 22.0),
                    const SizedBox(width: 8.0),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          verdictTitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: statusFg,
                          ),
                        ),
                        Text(
                          verdictSubtitle,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusFg.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Price & Normalized Price & Volume Metrics
              Wrap(
                spacing: 16.0,
                runSpacing: 8.0,
                children: [
                  _buildMiniMetricColumn(
                    context,
                    label: 'سعر بيع المنافس',
                    value: '${competitor.unitPrice.toStringAsFixed(1)} ج.م',
                    subText:
                        'مقابل ${effectiveOwnPrice.toStringAsFixed(1)} ج.م عندنا',
                    valueColor: statusFg,
                  ),
                  _buildMiniMetricColumn(
                    context,
                    label: 'سعر الـ ${competitor.volumeUnitLabel} الصافي',
                    value:
                        '${competitor.pricePerUnitVolume.toStringAsFixed(1)} ج/${competitor.volumeUnitLabel}',
                    subText: volDiff > 0
                        ? 'أغلى بـ +${volDiff.toStringAsFixed(1)} ج/${competitor.volumeUnitLabel}'
                        : volDiff < 0
                            ? 'أرخص بـ ${volDiff.toStringAsFixed(1)} ج/${competitor.volumeUnitLabel}'
                            : 'نفس سعر الـ ${competitor.volumeUnitLabel}',
                  ),
                  _buildMiniMetricColumn(
                    context,
                    label: 'مبيعات وحصة المنافس',
                    value: '${competitor.categorySharePct.toStringAsFixed(1)}%',
                    subText: '${competitor.unitsSold} عبوة مباعة',
                  ),
                ],
              ),
            ],
          ),

          // Shrinkflation Alert if competitor pack price looks cheaper only because of smaller pack volume!
          if (shrinkflationDetected) ...[
            const SizedBox(height: 10.0),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF7E0),
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(
                  color: const Color(0xFFEA8600).withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 18.0,
                    color: Color(0xFFB06000),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      'تنبيه ذكي (Shrinkflation): رغم أن سعر عبوة المنافس (${competitor.unitPrice.toStringAsFixed(0)} ج.م) يبدو أقل من عبوتك (${effectiveOwnPrice.toStringAsFixed(0)} ج.م)، إلا أن عبوة المنافس أصغر حجماً (${competitor.packSizeLabel})، وبالتالي سعر الـ ${competitor.volumeUnitLabel} عندك أرخص فعلياً (${effectiveOwnPricePerVol.toStringAsFixed(1)} مقابل ${competitor.pricePerUnitVolume.toStringAsFixed(1)} ج.م)!',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF8A4B00),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniMetricColumn(
    BuildContext context, {
    required String label,
    required String value,
    required String subText,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: valueColor ?? colorScheme.onSurface,
          ),
        ),
        Text(
          subText,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }

  /// Chain-by-Chain Price Comparison Table for the selected Own SKU and its Competitors
  Widget _buildChainByChainMatrixCard(
    BuildContext context, {
    required OwnSkuCompetitiveGroupModel group,
    required List<CompetitorSkuComparisonModel> competitors,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    const chains = [
      (key: 'fathalla', name: 'أسواق فتح الله'),
      (key: 'carrefour', name: 'كارفور مصر'),
      (key: 'beet-elgomla', name: 'بيت الجملة'),
      (key: 'gomla', name: 'جملة ماركت'),
      (key: 'spinneys', name: 'سبينيس مصر'),
    ];

    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24.0),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.grid_view_rounded, color: colorScheme.primary),
              const SizedBox(width: 8.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مصفوفة مقارنة الأسعار عبر السلاسل التجارية (Chain-by-Chain Price Matrix)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'مقارنة سعر بيع صنفك أمام كل منافس داخل كل سلسلة تجارية على حدة',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          M3Spacing.gapMD,
          TableScrollContainer(
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              ),
              columns: [
                const DataColumn(label: Text('الصنف / العلامة التجارية')),
                const DataColumn(label: Text('العبوة')),
                for (final ch in chains) DataColumn(label: Text(ch.name)),
              ],
              rows: [
                // Row 0: Our Own SKU
                DataRow(
                  color: WidgetStateProperty.all(
                    colorScheme.primaryContainer.withValues(alpha: 0.35),
                  ),
                  cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.stars_rounded,
                            size: 18.0,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6.0),
                          Text(
                            '${group.ownBrand} — ${group.ownSkuName}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      Text(
                        group.packSizeLabel,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    for (final ch in chains)
                      DataCell(
                        Text(
                          '${(group.ownChainPrices[ch.key] ?? group.ownUnitPrice).toStringAsFixed(0)} ج.م',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),

                // Competitor Rows
                for (final comp in competitors)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          '${comp.brand} — ${comp.skuName}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(Text(comp.packSizeLabel)),
                      for (final ch in chains)
                        DataCell(
                          Builder(
                            builder: (context) {
                              final ownP = group.ownChainPrices[ch.key] ??
                                  group.ownUnitPrice;
                              final compP =
                                  comp.chainPrices[ch.key] ?? comp.unitPrice;
                              final diff = compP - ownP;
                              final isHigher = diff > 1.0;
                              final isLower = diff < -1.0;
                              final color = isHigher
                                  ? const Color(0xFF0D652D)
                                  : isLower
                                      ? const Color(0xFFA50E0E)
                                      : colorScheme.onSurface;
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${compP.toStringAsFixed(0)} ج.م',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: color,
                                    ),
                                  ),
                                  const SizedBox(width: 4.0),
                                  Text(
                                    isHigher
                                        ? '(+${diff.toStringAsFixed(0)})'
                                        : isLower
                                            ? '(${diff.toStringAsFixed(0)})'
                                            : '(=)',
                                    style: TextStyle(
                                      fontSize: 11.0,
                                      fontWeight: FontWeight.w700,
                                      color: color,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(48.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24.0),
      ),
      child: Column(
        children: [
          Icon(
            Icons.compare_arrows_rounded,
            size: 48.0,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 12.0),
          Text(
            'لا توجد أصناف مطابقة لبحثك حالياً',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8.0),
          M3Button.tonal(
            label: 'إعادة ضبط الفلاتر',
            icon: Icons.restart_alt_rounded,
            onPressed: () {
              _searchController.clear();
              setState(() {
                _selectedCategory = 'الكل';
                _searchQuery = '';
                _applyLocalFilters();
              });
            },
          ),
        ],
      ),
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

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(14.0),
            ),
            child: Icon(icon, color: onContainerColor, size: 24.0),
          ),
          const SizedBox(width: 14.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

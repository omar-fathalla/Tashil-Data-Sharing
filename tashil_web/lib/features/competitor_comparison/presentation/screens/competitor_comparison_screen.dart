import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_segmented_button_group.dart';
import '../../../../core/widgets/table_scroll_container.dart';

/// CompetitorComparisonScreen (Compare)
/// Displays 100% real uploaded branch sell-out data (Fathalla Market 2025 & 2026)
/// with temporal filtering (Year 2026 default / Year 2025 + Month 1..4),
/// an interactive Monthly Price Trajectory Chart (رسم بياني لحركة السعر شهرياً صعوداً وهبوطاً)
/// for both the selected Own SKU and its competing SKUs, and a Monthly Evolution Matrix.
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

  // Temporal State: Default to Year 2026 as requested
  int _selectedYear = 2026;
  int _selectedMonth = 0; // 0 = All Months (Jan - Apr), 1..4 = specific month
  bool _showFullTwoYearTimeline = false; // Toggle between Selected Year (4m) vs 2025+2026 (8m)
  String? _highlightedCompetitorBarcode; // Optional focus on a specific competitor on the chart

  String _selectedChain = 'fathalla';
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

  // Only real uploaded chains are shown (Fathalla Market from 2025 out.xlsx & 2026 out.xlsx)
  static const List<({String code, String labelAr})> _chainOptions = [
    (code: 'fathalla', labelAr: 'أسواق فتح الله (بيانات فعلية مرفوعة)'),
  ];

  static const List<({int year, String labelAr})> _yearOptions = [
    (year: 2026, labelAr: 'سنة 2026 (الحالية)'),
    (year: 2025, labelAr: 'سنة 2025 (السابقة)'),
  ];

  static const List<({int month, String labelAr})> _monthOptions = [
    (month: 0, labelAr: 'كل الشهور (يناير - أبريل)'),
    (month: 1, labelAr: 'يناير (01)'),
    (month: 2, labelAr: 'فبراير (02)'),
    (month: 3, labelAr: 'مارس (03)'),
    (month: 4, labelAr: 'أبريل (04)'),
  ];

  static const List<Color> _competitorSeriesColors = [
    Color(0xFFD93025), // Red
    Color(0xFFEA8600), // Amber/Orange
    Color(0xFF9334E6), // Purple
    Color(0xFF007B83), // Teal
    Color(0xFFC5221F), // Crimson
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
      _selectedYear = 2026;
      _selectedMonth = 0;
      _selectedChain = 'fathalla';
      _selectedCategory = 'الكل';
      _competitorFilter = 'all';
      _searchQuery = '';
      _searchController.clear();
      _simulatedOwnPrice = null;
      _highlightedCompetitorBarcode = null;
      _loadCompetitiveData();
    }
  }

  Future<void> _loadCompetitiveData() async {
    setState(() => _isLoading = true);
    final groups = await widget.apiClient.getCompetitiveComparisonGroups(
      chain: _selectedChain,
      year: _selectedYear,
      month: _selectedMonth,
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
        _highlightedCompetitorBarcode = null;
      }
    } else {
      _selectedOwnBarcode = null;
      _simulatedOwnPrice = null;
      _highlightedCompetitorBarcode = null;
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

  String get _activePeriodLabelAr {
    final monthName = _monthOptions
        .firstWhere(
          (m) => m.month == _selectedMonth,
          orElse: () => _monthOptions.first,
        )
        .labelAr;
    return '$monthName — $_selectedYear';
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
                            'إضافة صنف منافس مرصود بالسوق ($_selectedYear)',
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
                            labelText:
                                'اسم الصنف المنافس (مثال: بريل ليمون 2.5 لتر)',
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
                                      'سعر بيع المنافس بالجنيه (سعرنا: ${currentGroup.ownUnitPrice.toStringAsFixed(1)} ج.م)',
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
                        retailerChain: 'fathalla',
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

    // Aggregate KPIs across all Own SKUs in the selected temporal period
    final totalOwnSkus = _allGroups.length;
    int totalCompetitorSkus = 0;
    int advantageSkusCount = 0;
    int undercutRiskSkusCount = 0;
    int priceIncreasedSkusCount = 0;
    int priceDecreasedSkusCount = 0;
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
      if (g.periodPriceChangePct > 0.5) {
        priceIncreasedSkusCount++;
      } else if (g.periodPriceChangePct < -0.5) {
        priceDecreasedSkusCount++;
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
              titleEn: 'Compare',
              subtitleAr:
                  'مقارنة أسعار أصنافنا أمام المنافسين بالتاريخ والشهور ($_activePeriodLabelAr) — بيانات أسواق فتح الله الفعلية',
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

            // 2. Top 4 Competitive & Temporal Summary KPI Cards
            LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 900.0;
                final cards = [
                  _buildKpiCard(
                    context: context,
                    title: 'الفترة الزمنية النشطة ($_selectedYear)',
                    value: '$totalOwnSkus صنف أساسي',
                    subtitle:
                        'أمام $totalCompetitorSkus منافس في $_activePeriodLabelAr',
                    icon: Icons.calendar_month_rounded,
                    containerColor: colorScheme.primaryContainer,
                    onContainerColor: colorScheme.onPrimaryContainer,
                  ),
                  _buildKpiCard(
                    context: context,
                    title: 'ميزة سعرية تنافسية (نحن الأرخص 🟢)',
                    value: '$advantageSkusCount من $totalOwnSkus أصناف',
                    subtitle: 'سعر بيعنا أقل من متوسط المنافسين في هذه الفترة',
                    icon: Icons.trending_down_rounded,
                    containerColor: const Color(0xFFE6F4EA),
                    onContainerColor: const Color(0xFF0D652D),
                  ),
                  _buildKpiCard(
                    context: context,
                    title: 'حركة الأسعار عبر شهور $_selectedYear',
                    value: '▲ $priceIncreasedSkusCount زاد | ▼ $priceDecreasedSkusCount نزل',
                    subtitle: 'تتبع شهري لارتفاع وانخفاض الأسعار (يناير - أبريل)',
                    icon: Icons.show_chart_rounded,
                    containerColor: const Color(0xFFFEF7E0),
                    onContainerColor: const Color(0xFFB06000),
                  ),
                  _buildKpiCard(
                    context: context,
                    title: 'مؤشر السعر التنافسي (Price Index)',
                    value: '${avgPriceIndex.toStringAsFixed(1)}%',
                    subtitle:
                        'تهديد سعري مباشر في $undercutRiskSkusCount أصناف',
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

            // 3. Temporal & Chain Filter Toolbar (Year 2026 / 2025 + Month 1..4 + Real Chain + Category + Search)
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
                        // Right side in RTL: Master list of Own SKUs (370dp)
                        SizedBox(
                          width: 370.0,
                          child: _buildOwnSkusMasterPanel(
                            context,
                            selectedGroup,
                          ),
                        ),
                        M3Spacing.gapMD,
                        // Left side in RTL: Detailed Competitor Comparison + Monthly Trajectory Chart
                        Expanded(
                          child: _buildCompetitorDetailPanel(
                            context,
                            selectedGroup,
                          ),
                        ),
                      ],
                    );
                  } else {
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
          // Row 1: Temporal Logic (Year Selector + Month Selector)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14.0),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Wrap(
              spacing: 16.0,
              runSpacing: 10.0,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                // Year Selector (Default 2026)
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.event_note_rounded,
                      size: 19.0,
                      color: colorScheme.primary,
                    ),
                    Text(
                      'السنة المالية:',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.primary,
                      ),
                    ),
                    for (final yr in _yearOptions)
                      ChoiceChip(
                        label: Text(
                          yr.labelAr,
                          style: TextStyle(
                            fontWeight: _selectedYear == yr.year
                                ? FontWeight.w900
                                : FontWeight.w600,
                          ),
                        ),
                        selected: _selectedYear == yr.year,
                        onSelected: (sel) {
                          if (!sel || _selectedYear == yr.year) return;
                          setState(() {
                            _selectedYear = yr.year;
                            _simulatedOwnPrice = null;
                          });
                          _loadCompetitiveData();
                        },
                      ),
                  ],
                ),

                // Month Selector (All Months or Jan / Feb / Mar / Apr)
                Wrap(
                  spacing: 6.0,
                  runSpacing: 6.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.timeline_rounded,
                      size: 18.0,
                      color: colorScheme.primary,
                    ),
                    Text(
                      'تصفية بالشهر:',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    for (final m in _monthOptions)
                      ChoiceChip(
                        label: Text(m.labelAr),
                        selected: _selectedMonth == m.month,
                        onSelected: (sel) {
                          if (!sel || _selectedMonth == m.month) return;
                          setState(() {
                            _selectedMonth = m.month;
                            _simulatedOwnPrice = null;
                          });
                          _loadCompetitiveData();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12.0),

          // Row 2: Search Input + Real Uploaded Chain Badge
          Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              // Search input
              SizedBox(
                width: 340.0,
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
                    hintText: 'ابحث باسم الصنف، الباركود، أو المنافس...',
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

              // Real Chain Indicator (Only real uploaded Fathalla Market data)
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    size: 18.0,
                    color: Color(0xFF0D652D),
                  ),
                  Text(
                    'السلسلة التجارية المعتمدة:',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final ch in _chainOptions)
                    ChoiceChip(
                      avatar: const Icon(
                        Icons.storefront_rounded,
                        size: 16.0,
                      ),
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
                        'اختر صنفك للمقارنة ($_selectedYear)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'اضغط لعرض منحنى الأسعار الشهري والمنافسين',
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
        ? 'أرخص من السوق بـ ${vsAvgDiffPct.abs().toStringAsFixed(1)}%'
        : weAreMoreExpensive
            ? 'أغلى من السوق بـ +${vsAvgDiffPct.toStringAsFixed(1)}%'
            : 'مساوي لمتوسط السوق';

    // Monthly trend badge for our own SKU across the selected year
    final double momPct = group.periodPriceChangePct;
    final bool priceRose = momPct > 0.5;
    final bool priceDropped = momPct < -0.5;

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
            _highlightedCompetitorBarcode = null;
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
                        Wrap(
                          spacing: 6.0,
                          runSpacing: 4.0,
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
                            if (priceRose || priceDropped)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7.0,
                                  vertical: 2.0,
                                ),
                                decoration: BoxDecoration(
                                  color: priceRose
                                      ? const Color(0xFFFEF7E0)
                                      : const Color(0xFFE8F0FE),
                                  borderRadius: BorderRadius.circular(6.0),
                                ),
                                child: Text(
                                  priceRose
                                      ? '▲ +${momPct.toStringAsFixed(1)}% في $_selectedYear'
                                      : '▼ ${momPct.toStringAsFixed(1)}% في $_selectedYear',
                                  style: TextStyle(
                                    fontSize: 10.0,
                                    fontWeight: FontWeight.w800,
                                    color: priceRose
                                        ? const Color(0xFFB06000)
                                        : const Color(0xFF1967D2),
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
                        '${group.ownUnitPrice.toStringAsFixed(1)} ج.م',
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

  /// Detail Panel showing:
  /// A. Selected Own SKU Benchmark Spotlight Card
  /// B. Interactive What-If Price Simulator (if toggled)
  /// C. Monthly Price Trajectory Chart (رسم بياني لحركة سعر الصنف والمنافسين عبر الشهور - زاد إمتى ونزل إمتى)
  /// D. Direct Competitor Cards with Monthly Price Movement Strips
  /// E. Monthly Price & Volume Evolution Matrix Table
  Widget _buildCompetitorDetailPanel(
    BuildContext context,
    OwnSkuCompetitiveGroupModel group,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final effectiveOwnPrice =
        (_showWhatIfSimulator && _simulatedOwnPrice != null)
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

        // C. Monthly Price Trajectory Chart Card (رسم بياني لحركة السعر شهرياً صعوداً وهبوطاً)
        _buildMonthlyPriceTrajectoryChartCard(
          context,
          group: group,
          competitors: adjustedCompetitors,
        ),

        M3Spacing.gapMD,

        // D. Filter Header for Competitors + Cards Grid
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
                            'الأصناف المنافسة المباشرة في $_activePeriodLabelAr (${visibleCompetitors.length} من ${adjustedCompetitors.length})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'مقارنة سعر البيع الفعلي (أعلى أم أقل من سعرك) + شريط تحرك السعر شهرياً لكل منافس',
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
                    for (int idx = 0;
                        idx < visibleCompetitors.length;
                        idx++) ...[
                      _buildCompetitorComparisonCard(
                        context,
                        group: group,
                        competitor: visibleCompetitors[idx],
                        seriesColor: _competitorSeriesColors[
                            idx % _competitorSeriesColors.length],
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

        // E. Monthly Price & Volume Evolution Matrix Table (مصفوفة تطور الأسعار والكميات الشهرية)
        _buildMonthlyEvolutionMatrixCard(
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

    // Identify in which month our price increased or decreased the most in the selected year
    String monthlyMovementSummary = 'استقرار سعري خلال شهور $_selectedYear';
    Color movementBg = colorScheme.secondaryContainer;
    Color movementFg = colorScheme.onSecondaryContainer;
    IconData movementIcon = Icons.timeline_rounded;

    final changes = group.monthlyPrices.where((m) => m.priceChangePct.abs() >= 0.5).toList();
    if (changes.isNotEmpty) {
      final upMonths = changes
          .where((m) => m.priceChangePct > 0.5)
          .map((m) => '${m.monthNameAr} (+${m.priceChangePct.toStringAsFixed(1)}%)')
          .toList();
      final downMonths = changes
          .where((m) => m.priceChangePct < -0.5)
          .map((m) => '${m.monthNameAr} (${m.priceChangePct.toStringAsFixed(1)}%)')
          .toList();

      final parts = <String>[];
      if (upMonths.isNotEmpty) {
        parts.add('ارتفع في: ${upMonths.join('، ')}');
      }
      if (downMonths.isNotEmpty) {
        parts.add('انخفض في: ${downMonths.join('، ')}');
      }
      monthlyMovementSummary = parts.join(' | ');
      if (group.periodPriceChangePct > 0.5) {
        movementBg = const Color(0xFFFEF7E0);
        movementFg = const Color(0xFFB06000);
        movementIcon = Icons.trending_up_rounded;
      } else if (group.periodPriceChangePct < -0.5) {
        movementBg = const Color(0xFFE8F0FE);
        movementFg = const Color(0xFF1967D2);
        movementIcon = Icons.trending_down_rounded;
      }
    }

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
                            'صنف شركتي ($_activePeriodLabelAr)',
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
                    label: _selectedMonth == 0
                        ? 'متوسط سعر بيعنا ($_selectedYear)'
                        : 'سعر بيعنا في $_activePeriodLabelAr',
                    value: '${effectiveOwnPrice.toStringAsFixed(2)} ج.م',
                    subValue:
                        '${effectiveOwnPricePerVol.toStringAsFixed(1)} ج.م / ${group.volumeUnitLabel}',
                    isHighlighted: true,
                  ),
                  _buildSpotlightMetricBox(
                    context,
                    label: 'متوسط سعر المنافسين',
                    value: '${group.avgCompetitorPrice.toStringAsFixed(2)} ج.م',
                    subValue:
                        'المدى: ${group.minCompetitorPrice.toStringAsFixed(0)} - ${group.maxCompetitorPrice.toStringAsFixed(0)} ج.م',
                  ),
                  _buildSpotlightMetricBox(
                    context,
                    label: 'التغير السعري في $_selectedYear',
                    value:
                        '${group.periodPriceChangePct >= 0 ? '+' : ''}${group.periodPriceChangePct.toStringAsFixed(1)}%',
                    subValue:
                        '${group.periodPriceChangeEgp >= 0 ? '+' : ''}${group.periodPriceChangeEgp.toStringAsFixed(1)} ج.م (يناير ← أبريل)',
                  ),
                  _buildSpotlightMetricBox(
                    context,
                    label: 'حصتنا داخل الفئة',
                    value: '${group.ownCategorySharePct.toStringAsFixed(1)}%',
                    subValue: '${group.ownUnitsSold} عبوة مباعة فعلياً',
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16.0),
          const Divider(height: 1.0),
          const SizedBox(height: 12.0),

          // Quick Verdict Chips (How many competitors are higher vs lower + Monthly trajectory summary)
          Wrap(
            spacing: 10.0,
            runSpacing: 8.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'الموقف التنافسي وحركة السعر:',
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
              _buildStatusCountPill(
                label: monthlyMovementSummary,
                bgColor: movementBg,
                fgColor: movementFg,
                icon: movementIcon,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Interactive Monthly Price Trajectory Chart Card (رسم بياني لحركة سعر الصنف والمنافسين عبر الشهور)
  /// Shows when our SKU and each competing SKU increased or decreased in price across months.
  Widget _buildMonthlyPriceTrajectoryChartCard(
    BuildContext context, {
    required OwnSkuCompetitiveGroupModel group,
    required List<CompetitorSkuComparisonModel> competitors,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final List<SkuMonthlyPricePointModel> ownSeries = _showFullTwoYearTimeline
        ? group.allMonthlyPrices
        : group.monthlyPrices;

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24.0),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header + Timeline Toggle (Selected Year 4 Months vs Full 2025-2026 8 Months)
          Wrap(
            spacing: 12.0,
            runSpacing: 10.0,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10.0),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Icon(
                      Icons.auto_graph_rounded,
                      color: colorScheme.primary,
                      size: 22.0,
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _showFullTwoYearTimeline
                            ? 'منحنى حركة الأسعار الشهرية المقارن (2025 + 2026 — 8 شهور فعلية)'
                            : 'منحنى حركة الأسعار الشهرية المقارن لسنة $_selectedYear (زاد إمتى ونزل إمتى؟)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'يرسم اتجاه سعر بيع صنفك (خط أزرق عريض) أمام أسعار المنافسين شهراً بشهر مع نسب الارتفاع (▲) والانخفاض (▼)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Toggle between 4 months of selected year vs 8 months (2025 + 2026)
              Wrap(
                spacing: 8.0,
                children: [
                  FilterChip(
                    avatar: Icon(
                      _showFullTwoYearTimeline
                          ? Icons.visibility_rounded
                          : Icons.date_range_rounded,
                      size: 16.0,
                    ),
                    label: Text(
                      _showFullTwoYearTimeline
                          ? 'عرض شهور $_selectedYear فقط (4 شهور)'
                          : 'دمج مسار 2025 + 2026 (8 شهور)',
                    ),
                    selected: _showFullTwoYearTimeline,
                    onSelected: (v) {
                      setState(() => _showFullTwoYearTimeline = v);
                    },
                  ),
                  if (_highlightedCompetitorBarcode != null)
                    ActionChip(
                      avatar: const Icon(Icons.layers_clear_rounded, size: 16.0),
                      label: const Text('إظهار كل المنافسين'),
                      onPressed: () {
                        setState(() => _highlightedCompetitorBarcode = null);
                      },
                    ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14.0),

          // Interactive Legend (Our SKU + Competitors - Click a competitor to isolate/highlight its curve)
          Wrap(
            spacing: 10.0,
            runSpacing: 8.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Own SKU Legend Pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 6.0,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999.0),
                  border: Border.all(color: colorScheme.primary, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14.0,
                      height: 4.0,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(2.0),
                      ),
                    ),
                    const SizedBox(width: 6.0),
                    Text(
                      'صنفنا: ${group.ownBrand} (${group.ownUnitPrice.toStringAsFixed(1)} ج.م)',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

              // Competitor Legend Pills
              for (int i = 0; i < competitors.length; i++)
                Builder(
                  builder: (context) {
                    final comp = competitors[i];
                    final cColor = _competitorSeriesColors[
                        i % _competitorSeriesColors.length];
                    final isHighlighted = _highlightedCompetitorBarcode == null ||
                        _highlightedCompetitorBarcode == comp.barcode;

                    return InkWell(
                      borderRadius: BorderRadius.circular(999.0),
                      onTap: () {
                        setState(() {
                          if (_highlightedCompetitorBarcode == comp.barcode) {
                            _highlightedCompetitorBarcode = null;
                          } else {
                            _highlightedCompetitorBarcode = comp.barcode;
                          }
                        });
                      },
                      child: AnimatedOpacity(
                        duration: M3Motion.short3,
                        opacity: isHighlighted ? 1.0 : 0.35,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12.0,
                            vertical: 6.0,
                          ),
                          decoration: BoxDecoration(
                            color: cColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999.0),
                            border: Border.all(
                              color: cColor,
                              width: _highlightedCompetitorBarcode ==
                                      comp.barcode
                                  ? 2.0
                                  : 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12.0,
                                height: 12.0,
                                decoration: BoxDecoration(
                                  color: cColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6.0),
                              Text(
                                '${comp.brand} — ${comp.packSizeLabel} (${comp.unitPrice.toStringAsFixed(1)} ج.م)',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 4.0),
                              Text(
                                comp.periodPriceChangePct > 0.5
                                    ? '▲+${comp.periodPriceChangePct.toStringAsFixed(1)}%'
                                    : comp.periodPriceChangePct < -0.5
                                        ? '▼${comp.periodPriceChangePct.toStringAsFixed(1)}%'
                                        : '• مستقر',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: comp.periodPriceChangePct > 0.5
                                      ? const Color(0xFFB06000)
                                      : comp.periodPriceChangePct < -0.5
                                          ? const Color(0xFF1967D2)
                                          : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),

          const SizedBox(height: 18.0),

          // Multi-line Price Trajectory Canvas Chart
          Container(
            height: 270.0,
            padding: const EdgeInsets.fromLTRB(16.0, 20.0, 20.0, 12.0),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(18.0),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: CustomPaint(
              painter: _MonthlyPriceTrajectoryPainter(
                ownSeries: ownSeries,
                competitorSeriesList: [
                  for (int i = 0; i < competitors.length; i++)
                    if (_highlightedCompetitorBarcode == null ||
                        _highlightedCompetitorBarcode ==
                            competitors[i].barcode)
                      (
                        points: _showFullTwoYearTimeline
                            ? competitors[i].allMonthlyPrices
                            : competitors[i].monthlyPrices,
                        color: _competitorSeriesColors[
                            i % _competitorSeriesColors.length],
                        label: competitors[i].brand,
                      ),
                ],
                ownColor: colorScheme.primary,
                gridColor: colorScheme.outlineVariant.withValues(alpha: 0.4),
                textColor: colorScheme.onSurfaceVariant,
                selectedMonth: _selectedMonth,
              ),
              child: const SizedBox.expand(),
            ),
          ),

          const SizedBox(height: 16.0),

          // Month-by-Month Breakdown Cards for Our Own SKU (متى زاد ومتى نزل + الكمية المباعة)
          Text(
            'تفاصيل حركة سعر صنفنا شهراً بشهر (${_showFullTwoYearTimeline ? "2025 - 2026" : "سنة $_selectedYear"}) وأثرها على المبيعات:',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10.0),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final pt in ownSeries)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 10.0),
                    child: _buildOwnMonthStepCard(
                      context,
                      point: pt,
                      isSelectedMonth:
                          _selectedMonth == pt.monthNum &&
                          _selectedYear == pt.year,
                      onTap: () {
                        setState(() {
                          _selectedYear = pt.year;
                          _selectedMonth =
                              _selectedMonth == pt.monthNum ? 0 : pt.monthNum;
                        });
                        _loadCompetitiveData();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnMonthStepCard(
    BuildContext context, {
    required SkuMonthlyPricePointModel point,
    required bool isSelectedMonth,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bool isUp = point.trendDirection == 'up';
    final bool isDown = point.trendDirection == 'down';
    final bool isBaseline = point.trendDirection == 'baseline';

    final Color badgeBg = isUp
        ? const Color(0xFFFEF7E0)
        : isDown
            ? const Color(0xFFE6F4EA)
            : colorScheme.surfaceContainerHighest;
    final Color badgeFg = isUp
        ? const Color(0xFFB06000)
        : isDown
            ? const Color(0xFF0D652D)
            : colorScheme.onSurfaceVariant;

    final String deltaLabel = isBaseline
        ? 'شهر الأساس (بداية الفترة)'
        : isUp
            ? '▲ زاد +${point.priceChangeEgp.toStringAsFixed(1)} ج (+${point.priceChangePct.toStringAsFixed(1)}%)'
            : isDown
                ? '▼ نزل ${point.priceChangeEgp.toStringAsFixed(1)} ج (${point.priceChangePct.toStringAsFixed(1)}%)'
                : '• مستقر (بدون تغير)';

    return InkWell(
      borderRadius: BorderRadius.circular(16.0),
      onTap: onTap,
      child: Container(
        width: 195.0,
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: isSelectedMonth
              ? colorScheme.primaryContainer.withValues(alpha: 0.7)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: isSelectedMonth
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.7),
            width: isSelectedMonth ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  point.monthLabelAr,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colorScheme.primary,
                  ),
                ),
                Text(
                  '${point.unitsSold} عبوة',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6.0),
            Text(
              '${point.unitPrice.toStringAsFixed(2)} ج.م',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6.0),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 3.0,
              ),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                deltaLabel,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: badgeFg,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
                label:
                    'إعادة للسعر الأصلي (${group.ownUnitPrice.toStringAsFixed(1)} ج.م)',
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
                'السعر التجريبي: ${currentVal.toStringAsFixed(1)} ج.م (${(pctChange * 100).toStringAsFixed(1)}%)',
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

  /// Individual Competitor SKU Card showing Higher/Lower badge, price gap,
  /// normalized liter/kg price, volume share, AND its Monthly Price Trajectory Strip.
  Widget _buildCompetitorComparisonCard(
    BuildContext context, {
    required OwnSkuCompetitiveGroupModel group,
    required CompetitorSkuComparisonModel competitor,
    required Color seriesColor,
    required double effectiveOwnPrice,
    required double effectiveOwnPricePerVol,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bool isCompHigher = competitor.pricePosition == 'higher';
    final bool isCompLower = competitor.pricePosition == 'lower';

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
        ? 'صنفك أرخص للمستهلك في $_activePeriodLabelAr (ميزة تنافسية لصالحك)'
        : isCompLower
            ? 'المنافس يبيع بسعر أرخص منك في $_activePeriodLabelAr'
            : 'تطابق سعري مباشر على الرف';

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
                width: 370.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6.0,
                      runSpacing: 6.0,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          width: 10.0,
                          height: 10.0,
                          decoration: BoxDecoration(
                            color: seriesColor,
                            shape: BoxShape.circle,
                          ),
                        ),
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
                              'تخفيض سعري نشط (Promo)',
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
                    value: '${competitor.unitPrice.toStringAsFixed(2)} ج.م',
                    subText:
                        'مقابل ${effectiveOwnPrice.toStringAsFixed(2)} ج.م عندنا',
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

          // Monthly Price Trajectory Strip for this Competitor (متى زاد أو نزل سعر هذا المنافس عبر شهور السنة)
          if (competitor.monthlyPrices.isNotEmpty) ...[
            const SizedBox(height: 12.0),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 9.0,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Icon(
                      Icons.timeline_rounded,
                      size: 16.0,
                      color: seriesColor,
                    ),
                    const SizedBox(width: 6.0),
                    Text(
                      'حركة سعر المنافس في شهور $_selectedYear:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10.0),
                    for (int mIdx = 0;
                        mIdx < competitor.monthlyPrices.length;
                        mIdx++) ...[
                      Builder(
                        builder: (context) {
                          final mp = competitor.monthlyPrices[mIdx];
                          final isUp = mp.trendDirection == 'up';
                          final isDown = mp.trendDirection == 'down';
                          final isBase = mp.trendDirection == 'baseline';
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10.0,
                              vertical: 4.0,
                            ),
                            decoration: BoxDecoration(
                              color: isUp
                                  ? const Color(0xFFFEF7E0)
                                  : isDown
                                      ? const Color(0xFFE6F4EA)
                                      : colorScheme.surface,
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(
                                color: _selectedMonth == mp.monthNum
                                    ? seriesColor
                                    : colorScheme.outlineVariant
                                        .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${mp.monthNameAr}: ',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${mp.unitPrice.toStringAsFixed(1)} ج.م',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (!isBase) ...[
                                  const SizedBox(width: 5.0),
                                  Text(
                                    isUp
                                        ? '▲+${mp.priceChangePct.toStringAsFixed(1)}%'
                                        : isDown
                                            ? '▼${mp.priceChangePct.toStringAsFixed(1)}%'
                                            : '•0%',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                      color: isUp
                                          ? const Color(0xFFB06000)
                                          : isDown
                                              ? const Color(0xFF0D652D)
                                              : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 5.0),
                                Text(
                                  '(${mp.unitsSold}u)',
                                  style: TextStyle(
                                    fontSize: 10.0,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      if (mIdx < competitor.monthlyPrices.length - 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Icon(
                            Icons.arrow_back_rounded,
                            size: 13.0,
                            color: colorScheme.outline,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],

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
                      'تنبيه ذكي (Shrinkflation): رغم أن سعر عبوة المنافس (${competitor.unitPrice.toStringAsFixed(1)} ج.م) يبدو أقل من عبوتك (${effectiveOwnPrice.toStringAsFixed(1)} ج.م)، إلا أن عبوة المنافس أصغر حجماً (${competitor.packSizeLabel})، وبالتالي سعر الـ ${competitor.volumeUnitLabel} عندك أرخص فعلياً (${effectiveOwnPricePerVol.toStringAsFixed(1)} مقابل ${competitor.pricePerUnitVolume.toStringAsFixed(1)} ج.م)!',
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

  /// Monthly Price & Volume Evolution Matrix Table across the months of the selected year
  /// Replaces the old synthetic multi-chain matrix with 100% real monthly trajectory data.
  Widget _buildMonthlyEvolutionMatrixCard(
    BuildContext context, {
    required OwnSkuCompetitiveGroupModel group,
    required List<CompetitorSkuComparisonModel> competitors,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final months = [
      (num: 1, name: 'يناير $_selectedYear'),
      (num: 2, name: 'فبراير $_selectedYear'),
      (num: 3, name: 'مارس $_selectedYear'),
      (num: 4, name: 'أبريل $_selectedYear'),
    ];

    SkuMonthlyPricePointModel? findMonthPoint(
      List<SkuMonthlyPricePointModel> list,
      int monthNum,
    ) {
      for (final m in list) {
        if (m.monthNum == monthNum) return m;
      }
      return list.isNotEmpty ? list.last : null;
    }

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
              Icon(Icons.table_chart_rounded, color: colorScheme.primary),
              const SizedBox(width: 8.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مصفوفة تطور الأسعار والكميات الشهرية لسنة $_selectedYear (أسواق فتح الله الفعلية)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'مقارنة دقيقة لسعر البيع والكميات المباعة ونسبة الارتفاع/الانخفاض لكل شهر بين صنفك وجميع المنافسين',
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
                for (final m in months) DataColumn(label: Text(m.name)),
                const DataColumn(label: Text('إجمالي التغير السعري')),
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
                    for (final m in months)
                      DataCell(
                        Builder(
                          builder: (context) {
                            final pt =
                                findMonthPoint(group.monthlyPrices, m.num);
                            if (pt == null) return const Text('-');
                            final isUp = pt.trendDirection == 'up';
                            final isDown = pt.trendDirection == 'down';
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${pt.unitPrice.toStringAsFixed(2)} ج.م',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    if (pt.trendDirection != 'baseline') ...[
                                      const SizedBox(width: 4.0),
                                      Text(
                                        isUp
                                            ? '▲+${pt.priceChangePct.toStringAsFixed(1)}%'
                                            : isDown
                                                ? '▼${pt.priceChangePct.toStringAsFixed(1)}%'
                                                : '•',
                                        style: TextStyle(
                                          fontSize: 11.0,
                                          fontWeight: FontWeight.w800,
                                          color: isUp
                                              ? const Color(0xFFB06000)
                                              : isDown
                                                  ? const Color(0xFF0D652D)
                                                  : colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  '${pt.unitsSold} عبوة',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    DataCell(
                      Text(
                        '${group.periodPriceChangePct >= 0 ? '+' : ''}${group.periodPriceChangePct.toStringAsFixed(1)}% (${group.periodPriceChangeEgp >= 0 ? '+' : ''}${group.periodPriceChangeEgp.toStringAsFixed(1)} ج.م)',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: group.periodPriceChangePct > 0.5
                              ? const Color(0xFFB06000)
                              : group.periodPriceChangePct < -0.5
                                  ? const Color(0xFF1967D2)
                                  : colorScheme.onSurface,
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
                      for (final m in months)
                        DataCell(
                          Builder(
                            builder: (context) {
                              final pt =
                                  findMonthPoint(comp.monthlyPrices, m.num);
                              if (pt == null) return const Text('-');
                              final isUp = pt.trendDirection == 'up';
                              final isDown = pt.trendDirection == 'down';
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${pt.unitPrice.toStringAsFixed(2)} ج.م',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      if (pt.trendDirection != 'baseline') ...[
                                        const SizedBox(width: 4.0),
                                        Text(
                                          isUp
                                              ? '▲+${pt.priceChangePct.toStringAsFixed(1)}%'
                                              : isDown
                                                  ? '▼${pt.priceChangePct.toStringAsFixed(1)}%'
                                                  : '•',
                                          style: TextStyle(
                                            fontSize: 11.0,
                                            fontWeight: FontWeight.w800,
                                            color: isUp
                                                ? const Color(0xFFB06000)
                                                : isDown
                                                    ? const Color(0xFF0D652D)
                                                    : colorScheme
                                                        .onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    '${pt.unitsSold} عبوة',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      DataCell(
                        Text(
                          '${comp.periodPriceChangePct >= 0 ? '+' : ''}${comp.periodPriceChangePct.toStringAsFixed(1)}% (${comp.periodPriceChangeEgp >= 0 ? '+' : ''}${comp.periodPriceChangeEgp.toStringAsFixed(1)} ج.م)',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: comp.periodPriceChangePct > 0.5
                                ? const Color(0xFFB06000)
                                : comp.periodPriceChangePct < -0.5
                                    ? const Color(0xFF1967D2)
                                    : colorScheme.onSurface,
                          ),
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

/// Custom Painter that renders the Multi-Line Monthly Price Trajectory Chart
/// for our Own SKU (thick primary line with price + ▲/▼ badges) and all Competing SKUs.
class _MonthlyPriceTrajectoryPainter extends CustomPainter {
  final List<SkuMonthlyPricePointModel> ownSeries;
  final List<({List<SkuMonthlyPricePointModel> points, Color color, String label})>
      competitorSeriesList;
  final Color ownColor;
  final Color gridColor;
  final Color textColor;
  final int selectedMonth;

  _MonthlyPriceTrajectoryPainter({
    required this.ownSeries,
    required this.competitorSeriesList,
    required this.ownColor,
    required this.gridColor,
    required this.textColor,
    required this.selectedMonth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (ownSeries.isEmpty) return;

    const double leftPad = 56.0;
    const double rightPad = 24.0;
    const double topPad = 24.0;
    const double bottomPad = 34.0;

    final double chartW = math.max(10.0, size.width - leftPad - rightPad);
    final double chartH = math.max(10.0, size.height - topPad - bottomPad);

    // Compute global min/max price across own + visible competitors
    double minP = double.infinity;
    double maxP = 0.0;

    for (final pt in ownSeries) {
      if (pt.unitPrice < minP) minP = pt.unitPrice;
      if (pt.unitPrice > maxP) maxP = pt.unitPrice;
    }
    for (final comp in competitorSeriesList) {
      for (final pt in comp.points) {
        if (pt.unitPrice < minP) minP = pt.unitPrice;
        if (pt.unitPrice > maxP) maxP = pt.unitPrice;
      }
    }

    if (!minP.isFinite || maxP <= 0) {
      minP = 0;
      maxP = 100;
    }
    final double span = math.max(10.0, maxP - minP);
    final double yMin = math.max(0.0, minP - span * 0.18);
    final double yMax = maxP + span * 0.22;

    double priceToY(double price) {
      final norm = (price - yMin) / math.max(1.0, yMax - yMin);
      return topPad + chartH * (1.0 - norm.clamp(0.0, 1.0));
    }

    double indexToX(int idx, int count) {
      if (count <= 1) return leftPad + chartW / 2;
      return leftPad + (idx / (count - 1)) * chartW;
    }

    // 1. Draw Horizontal Grid Lines & Y-Axis Price Labels
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    const int ySteps = 4;
    for (int i = 0; i <= ySteps; i++) {
      final val = yMin + ((yMax - yMin) * (i / ySteps));
      final y = priceToY(val);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(leftPad + chartW, y),
        gridPaint,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${val.toStringAsFixed(0)} ج',
          style: TextStyle(
            color: textColor,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 8.0, y - tp.height / 2));
    }

    // 2. Draw X-Axis Month Labels & Vertical Guide Lines
    final int n = ownSeries.length;
    for (int i = 0; i < n; i++) {
      final x = indexToX(i, n);
      final pt = ownSeries[i];
      final isHighlightedMonth = selectedMonth == pt.monthNum;

      canvas.drawLine(
        Offset(x, topPad),
        Offset(x, topPad + chartH),
        Paint()
          ..color = isHighlightedMonth
              ? ownColor.withValues(alpha: 0.35)
              : gridColor.withValues(alpha: 0.45)
          ..strokeWidth = isHighlightedMonth ? 2.0 : 1.0,
      );

      final label = n > 4 ? '${pt.monthNameAr} ${pt.year % 100}' : pt.monthNameAr;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: isHighlightedMonth ? ownColor : textColor,
            fontSize: 11.5,
            fontWeight:
                isHighlightedMonth ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, topPad + chartH + 8.0));
    }

    // 3. Draw Competitor Lines (dashed/secondary stroke + dots + price labels)
    for (final comp in competitorSeriesList) {
      final pts = comp.points;
      if (pts.isEmpty) continue;
      final path = Path();
      for (int i = 0; i < pts.length; i++) {
        final x = indexToX(i, pts.length);
        final y = priceToY(pts[i].unitPrice);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = comp.color.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );

      for (int i = 0; i < pts.length; i++) {
        final x = indexToX(i, pts.length);
        final y = priceToY(pts[i].unitPrice);
        canvas.drawCircle(
          Offset(x, y),
          4.0,
          Paint()..color = comp.color,
        );
      }
    }

    // 4. Draw Own SKU Area Fill + Thick Primary Line + Data Callouts
    final ownPath = Path();
    final fillPath = Path();
    for (int i = 0; i < n; i++) {
      final x = indexToX(i, n);
      final y = priceToY(ownSeries[i].unitPrice);
      if (i == 0) {
        ownPath.moveTo(x, y);
        fillPath.moveTo(x, topPad + chartH);
        fillPath.lineTo(x, y);
      } else {
        ownPath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
      if (i == n - 1) {
        fillPath.lineTo(x, topPad + chartH);
        fillPath.close();
      }
    }

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          colors: [
            ownColor.withValues(alpha: 0.20),
            ownColor.withValues(alpha: 0.01),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH)),
    );

    canvas.drawPath(
      ownPath,
      Paint()
        ..color = ownColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Draw Own SKU Points & Price + Trend Callouts
    for (int i = 0; i < n; i++) {
      final pt = ownSeries[i];
      final x = indexToX(i, n);
      final y = priceToY(pt.unitPrice);

      canvas.drawCircle(
        Offset(x, y),
        6.5,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(x, y),
        5.0,
        Paint()..color = ownColor,
      );

      final String arrow = pt.trendDirection == 'up'
          ? '▲'
          : pt.trendDirection == 'down'
              ? '▼'
              : '';
      final calloutText = '${pt.unitPrice.toStringAsFixed(1)} $arrow'.trim();
      final tp = TextPainter(
        text: TextSpan(
          text: calloutText,
          style: TextStyle(
            color: ownColor,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, y - 15.0),
            width: tp.width + 10.0,
            height: tp.height + 4.0,
          ),
          const Radius.circular(6.0),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.92),
      );
      tp.paint(canvas, Offset(x - tp.width / 2, y - 15.0 - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _MonthlyPriceTrajectoryPainter oldDelegate) {
    return oldDelegate.ownSeries != ownSeries ||
        oldDelegate.competitorSeriesList != competitorSeriesList ||
        oldDelegate.selectedMonth != selectedMonth ||
        oldDelegate.ownColor != ownColor;
  }
}

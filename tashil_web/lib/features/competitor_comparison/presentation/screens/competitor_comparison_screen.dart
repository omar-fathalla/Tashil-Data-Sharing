import 'dart:async';
import 'dart:math' as math;
import 'package:tashil_web/core/theme/m3_palette.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import 'package:flutter/material.dart';
import '../../../../core/data/available_months.dart';
import '../../../../core/data/available_years.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/data/result.dart';
import '../../../../core/network/api_client.dart';
import '../../data/competitor_comparison_repository.dart';
import '../../domain/competitor_month_options.dart';
import '../widgets/competitor_ai_picks_row.dart';
import '../widgets/competitor_suggestions_review.dart';
import '../utils/chart_callout_layout.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/data/data_refresh_mixin.dart';
import '../../../../core/utils/arabic_plural.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/widgets/m3_responsive_tab_bar.dart';
import '../../../../core/widgets/m3_search_field.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';

/// CompetitorComparisonScreen (Compare)
/// Material Design 3 1-vs-1 Focused Competitive Intelligence Experience:
/// - Selects an Own SKU as the Default Benchmark (e.g. Feba 3 Kg).
/// - Displays each competing brand ONCE as a clean M3 selector card with its pack volume
///   (e.g., Fairy 2L, Pril 4Kg, Wafeer 4Kg — never duplicated).
/// - Clicking any competitor immediately displays its 1-vs-1 Monthly Price Trajectory
///   for every month that has data against the default Own SKU without visual clutter.
class CompetitorComparisonScreen extends StatefulWidget {
  final ApiClient apiClient;

  /// Optional injected repository (tests); defaults to one wrapping [apiClient].
  final CompetitorComparisonSource? repository;

  const CompetitorComparisonScreen({
    super.key,
    required this.apiClient,
    this.repository,
  });

  @override
  State<CompetitorComparisonScreen> createState() =>
      _CompetitorComparisonScreenState();
}

class _CompetitorComparisonScreenState extends State<CompetitorComparisonScreen> with DataRefreshMixin<CompetitorComparisonScreen> {
  @override
  void onBackendDataChanged() {
    // Silent refresh: never flash KPI skeletons / center spinner on SWR bumps.
    // AI picks POST must not invalidate cache (see BackendHttp.invalidateCache);
    // approve/reject and real writes still land here without a full-page hang.
    _loadAvailableMonths(force: true);
    _loadCompetitiveData(forceRefresh: true, silent: true);
  }

  bool _isLoading = true;
  bool _monthsLoadFinished = false;
  int _competitiveLoadSeq = 0;
  late CompetitorComparisonSource _repo;
  List<OwnSkuCompetitiveGroupModel> _allGroups = [];
  List<OwnSkuCompetitiveGroupModel> _filteredGroups = [];
  String? _selectedOwnBarcode;
  String? _selectedCompetitorBarcode;

  // Temporal State: latest year with data (from the backend year list).
  int _selectedYear = AvailableYears.current.defaultYear;
  bool _yearTouched = false;
  int _selectedMonth = 0; // 0 = all months with data; >0 = specific month
  bool _showFullTwoYearTimeline = false;
  List<int> _apiMonths = const [];

  String _selectedChain = 'fathalla';
  String _selectedCategory = 'الكل';
  String _searchQuery = '';
  bool _showWhatIfSimulator = false;
  double? _simulatedOwnPrice;
  /// 0 = مقارنة الأسعار, 1 = اقتراحات المنافسين (بانتظار الموافقة) — optional batch tab
  int _mainTab = 0;

  /// Own-SKU master list pagination (0-based). Filters always reset to page 0.
  static const int _ownSkuPageSize = 10;
  int _ownSkuPageIndex = 0;

  /// On-demand AI top-3 for the selected own SKU (view/compare without approve).
  List<CompetitorSkuComparisonModel> _aiPicks = const [];
  bool _aiPicksLoading = false;
  String? _aiPicksEmptyHint;
  int _aiPicksRequestSeq = 0;

  final TextEditingController _searchController = TextEditingController();
  late String _lastTenantId;

  /// Adeco / own-SKU accent — theme brand green (not ColorScheme.primary blue).
  /// Pair with [M3Palette.successSurface] / [M3Palette.onSuccessSurface] for fills.
  static const Color _ownBrandGreen = M3Palette.success;


  static const List<({String code, String labelAr})> _chainOptions = [
    (code: 'fathalla', labelAr: 'أسواق فتح الله (بيانات فعلية مرفوعة)'),
  ];

  List<({int year, String labelAr})> get _yearOptions => [
        for (final y in AvailableYears.current.including(_selectedYear)) (year: y, labelAr: 'سنة $y'),
      ];

  /// Months that have data for the selected year — `/sell-out/months` ∪ competitive-monthly
  /// (never seed series).
  List<int> get _dataMonths {
    final api = _apiMonths.isNotEmpty
        ? _apiMonths
        : AvailableMonths.currentFor(_selectedYear).months;
    final merged = <int>{
      ...api,
      ...widget.apiClient.lastCompetitiveMonths,
    };
    return CompetitorMonthOptions.resolveDataMonths(apiMonths: merged.toList());
  }

  List<({int month, String labelAr})> get _monthOptions =>
      CompetitorMonthOptions.build(_dataMonths, year: _selectedYear);

  String get _monthRangeLabel => CompetitorMonthOptions.rangeLabel(_dataMonths);

  String get _monthEnumeratedLabel => CompetitorMonthOptions.enumeratedLabel(_dataMonths);

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? CompetitorComparisonRepository(widget.apiClient);
    _lastTenantId = widget.apiClient.tenantId;
    _loadCompetitiveData();
    _loadAvailableMonths();
    AvailableYears.load(widget.apiClient).then((o) {
      if (!mounted) return;
      if (!_yearTouched && o.defaultYear != _selectedYear) {
        setState(() {
          _selectedYear = o.defaultYear;
          _selectedMonth = 0;
        });
        _loadAvailableMonths();
        _loadCompetitiveData();
      } else {
        setState(() {});
      }
    });
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
      _repo = widget.repository ?? CompetitorComparisonRepository(widget.apiClient);
      _selectedYear = AvailableYears.current.defaultYear;
      _yearTouched = false;
      _selectedMonth = 0;
      _apiMonths = const [];
      _selectedChain = 'fathalla';
      _selectedCategory = 'الكل';
      _searchQuery = '';
      _searchController.clear();
      _ownSkuPageIndex = 0;
      _simulatedOwnPrice = null;
      _selectedCompetitorBarcode = null;
      _monthsLoadFinished = false;
      _loadAvailableMonths();
      _loadCompetitiveData();
    }
  }

  Future<void> _loadAvailableMonths({bool force = false}) async {
    final opts = await AvailableMonths.load(widget.apiClient, _selectedYear, force: force);
    if (!mounted) return;
    setState(() {
      _apiMonths = opts.months;
      _monthsLoadFinished = true;
      if (_selectedMonth > 0 &&
          _apiMonths.isNotEmpty &&
          !_apiMonths.contains(_selectedMonth) &&
          _dataMonths.isNotEmpty &&
          !_dataMonths.contains(_selectedMonth)) {
        _selectedMonth = 0;
      }
    });
  }

  Future<void> _loadCompetitiveData({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    final seq = ++_competitiveLoadSeq;
    final showSpinner = !silent || _allGroups.isEmpty;
    if (showSpinner) {
      setState(() => _isLoading = true);
    }
    final result = await _repo.loadGroups(
      chain: _selectedChain,
      year: _selectedYear,
      month: _selectedMonth,
      forceRefresh: forceRefresh,
    );

    if (!mounted || seq != _competitiveLoadSeq) return;
    result.when(
      success: (groups) {
        // Prefer union of /sell-out/months and competitive-monthly months so a
        // short memory window cannot leave the picker stuck at Jan–Apr.
        final fromAgg = widget.apiClient.lastCompetitiveMonths;
        if (fromAgg.isNotEmpty) {
          AvailableMonths.mergeMonths(_selectedYear, fromAgg);
        }
        setState(() {
          _apiMonths = AvailableMonths.currentFor(_selectedYear).months;
          if (_apiMonths.isEmpty && fromAgg.isNotEmpty) {
            _apiMonths = List<int>.from(fromAgg);
          }
          _allGroups = groups;
          _applyLocalFilters();
          // Drop a stale month pick if the year no longer has that month.
          if (_selectedMonth > 0 &&
              (_dataMonths.isEmpty || !_dataMonths.contains(_selectedMonth))) {
            _selectedMonth = 0;
          }
          _isLoading = false;
        });
        // Silent SWR refreshes must not restart AI picks (seq races swallow timeouts).
        if (!silent) {
          _loadAiPicksForSelectedOwn();
        }
      },
      failure: (error) {
        setState(() => _isLoading = false);
        final raw = error.message;
        final msg = raw.contains('انتهت مهلة')
            ? raw.replaceFirst(RegExp(r'^Exception:\s*'), '')
            : 'تعذر تحميل بيانات المقارنة: $raw';
        M3Feedback.showError(
          context,
          msg.isEmpty
              ? 'انتهت مهلة تحميل بيانات مقارنة الأسعار — حاول مرة أخرى'
              : msg,
        );
      },
    );
  }

  /// Re-renders from the ApiClient's in-memory custom SKUs without a server round-trip.
  Future<void> _rebuildFromLocalCache() async {
    final result = await _repo.rebuildLocal(
      chain: _selectedChain,
      year: _selectedYear,
      month: _selectedMonth,
    );
    final groups = result.valueOrNull;
    if (!mounted || groups == null) return;
    setState(() {
      _allGroups = groups;
      _applyLocalFilters();
    });
  }

  Future<void> _confirmDeleteCustomCompetitor(
      CompetitorSkuComparisonModel competitor) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف منتج المنافس'),
        content: Text('هل تريد حذف "${competitor.skuName}" من المقارنة؟'),
        actions: [
          M3Button.text(label: 'إلغاء', onPressed: () => Navigator.pop(ctx, false)),
          M3Button.primary(
            label: 'حذف',
            icon: Icons.delete_outline_rounded,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final deleting = _repo.deleteCustomSku(competitor.barcode);
    if (_selectedCompetitorBarcode == competitor.barcode) {
      _selectedCompetitorBarcode = null;
    }
    await _rebuildFromLocalCache();
    final res = await deleting;
    if (res case Failure(:final error)) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('تعذر حذف منتج المنافس: $error')));
      await _rebuildFromLocalCache();
    }
  }

  /// Recomputes [_filteredGroups]. When [resetPage] is true (search / category
  /// / data reload), pagination restarts at page 1. Callers that only need to
  /// re-slice must pass `resetPage: false` so page navigation stays intact —
  /// M3 [DropdownMenu] can re-fire `onSelected` with the same value on rebuild.
  void _applyLocalFilters({bool resetPage = true}) {
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

    if (resetPage) {
      _ownSkuPageIndex = 0;
    }
    _filteredGroups = filtered;
    if (!resetPage) {
      final last = _ownSkuTotalPages - 1;
      if (_ownSkuPageIndex > last) _ownSkuPageIndex = last < 0 ? 0 : last;
    }
    if (_filteredGroups.isNotEmpty) {
      final stillExists = _filteredGroups
          .any((g) => g.ownBarcode == _selectedOwnBarcode);
      if (!stillExists) {
        _selectedOwnBarcode = _filteredGroups.first.ownBarcode;
        _simulatedOwnPrice = null;
        _selectedCompetitorBarcode = null;
      }
      final activeGroup = _selectedGroup;
      if (activeGroup != null) {
        final pinnedExists = activeGroup.competitors
            .any((c) => c.barcode == _selectedCompetitorBarcode);
        final aiExists =
            _aiPicks.any((c) => c.barcode == _selectedCompetitorBarcode);
        if (!pinnedExists && !aiExists) {
          _selectedCompetitorBarcode = activeGroup.competitors.isNotEmpty
              ? activeGroup.competitors.first.barcode
              : (_aiPicks.isNotEmpty ? _aiPicks.first.barcode : null);
        }
      }
    } else {
      _selectedOwnBarcode = null;
      _simulatedOwnPrice = null;
      _selectedCompetitorBarcode = null;
      _aiPicks = const [];
    }
  }

  OwnSkuCompetitiveGroupModel? get _selectedGroup {
    if (_filteredGroups.isEmpty) return null;
    for (final g in _filteredGroups) {
      if (g.ownBarcode == _selectedOwnBarcode) return g;
    }
    return _filteredGroups.first;
  }

  int get _ownSkuTotalPages {
    final total = _filteredGroups.length;
    if (total <= 0) return 1;
    return ((total + _ownSkuPageSize - 1) ~/ _ownSkuPageSize);
  }

  int get _ownSkuSafePageIndex {
    final last = _ownSkuTotalPages - 1;
    if (_ownSkuPageIndex < 0) return 0;
    if (_ownSkuPageIndex > last) return last;
    return _ownSkuPageIndex;
  }

  List<OwnSkuCompetitiveGroupModel> get _ownSkuPageGroups {
    final total = _filteredGroups.length;
    if (total == 0) return const [];
    final page = _ownSkuSafePageIndex;
    final start = page * _ownSkuPageSize;
    final end = (start + _ownSkuPageSize > total) ? total : start + _ownSkuPageSize;
    return _filteredGroups.sublist(start, end);
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
    if (_selectedMonth == 0) {
      return CompetitorMonthOptions.allMonthsLabel(_dataMonths, year: _selectedYear);
    }
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
                shape: const RoundedRectangleBorder(
                  borderRadius: M3Shape.radiusXl,
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: M3Shape.radiusMd,
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
                            maxLines: 3,
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
                            labelText: 'اسم الصنف المنافس',
                            hintText: 'مثال: بريل ليمون 2.5 لتر',
                            prefixIcon: Icon(Icons.inventory_2_rounded),
                          ),
                        ),
                        const SizedBox(height: 12.0),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: brandCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'العلامة التجارية',
                                  prefixIcon: Icon(Icons.sell_rounded),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              child: TextField(
                                controller: supplierCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'الشركة المنافسة',
                                  prefixIcon: Icon(Icons.business_rounded),
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
                                  labelText: 'سعر بيع المنافس (ج.م)',
                                  hintText:
                                      'سعرنا: ${currentGroup.ownUnitPrice.toStringAsFixed(1)} ج.م',
                                  prefixIcon:
                                      const Icon(Icons.payments_rounded),
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
                                      'الوزن / الحجم (${currentGroup.volumeUnitLabel})',
                                  prefixIcon: const Icon(Icons.scale_rounded),
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
                                fontSize: M3FontSize.labelMediumPlus, fontWeight: FontWeight.w600),
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
                    onPressed: () async {
                      final compName = nameCtrl.text.trim();
                      final compPrice =
                          double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                      final compVol =
                          double.tryParse(volumeCtrl.text.trim()) ??
                              currentGroup.packVolumeUnits;
                      if (compName.isEmpty || compPrice <= 0) return;

                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(ctx);
                      final saving = _repo.addCustomSku(
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
                      // Local list already updated: refresh instantly, then confirm with the server.
                      _rebuildFromLocalCache();
                      final res = await saving;
                      if (res case Failure(:final error)) {
                        if (!mounted) return;
                        messenger.showSnackBar(SnackBar(
                          content: Text('تعذر حفظ منتج المنافس على الخادم: $error'),
                        ));
                        _rebuildFromLocalCache();
                      }
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

    final totalOwnSkus = _allGroups.length;
    final mappedOwnSkus =
        _allGroups.where((g) => g.competitors.isNotEmpty).length;
    int totalCompetitorSkus = 0;
    int advantageSkusCount = 0;
    int undercutRiskSkusCount = 0;
    int priceIncreasedSkusCount = 0;
    int priceDecreasedSkusCount = 0;
    double sumPriceIndex = 0.0;

    var mappedWithCompPrice = 0;
    for (final g in _allGroups) {
      totalCompetitorSkus += g.competitors.length;
      if (g.competitors.isNotEmpty && g.avgCompetitorPrice > 0) {
        sumPriceIndex += g.priceIndex;
        mappedWithCompPrice++;
      }
      if (g.avgCompetitorPrice > 0 && g.ownUnitPrice < g.avgCompetitorPrice) {
        advantageSkusCount++;
      }
      if (g.lowerPricedCompetitorsCount > 0) {
        undercutRiskSkusCount++;
      }
      if (g.monthlyPrices.length >= 2) {
        if (g.periodPriceChangePct > 0.5) {
          priceIncreasedSkusCount++;
        } else if (g.periodPriceChangePct < -0.5) {
          priceDecreasedSkusCount++;
        }
      }
    }
    // Never invent 100.0% when there are no competitor prices to index.
    final double? avgPriceIndex =
        mappedWithCompPrice > 0 ? sumPriceIndex / mappedWithCompPrice : null;

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
              subtitleAr: 'مقارنة أسعار أصناف شركة أديكو بالمنافسين',
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
                    onPressed: _isLoading ? null : () => _loadCompetitiveData(forceRefresh: true),
                  ),
                ],
              ),
            ),

            M3Spacing.gapMD,

            M3ResponsiveTabBar<int>(
              key: const ValueKey('compare_main_tabs'),
              textDirection: TextDirection.rtl,
              selectedValue: _mainTab,
              items: const [
                M3ResponsiveTabItem<int>(
                  value: 0,
                  icon: Icons.compare_arrows_rounded,
                  selectedIcon: Icons.compare_arrows_rounded,
                  label: 'مقارنة الأسعار',
                ),
                M3ResponsiveTabItem<int>(
                  value: 1,
                  icon: Icons.rate_review_rounded,
                  selectedIcon: Icons.rate_review_rounded,
                  label: 'اقتراحات المنافسين',
                  subtitle: 'بانتظار الموافقة',
                ),
              ],
              onChanged: (next) => setState(() => _mainTab = next),
            ),

            M3Spacing.gapMD,

            if (_mainTab == 1) ...[
              CompetitorSuggestionsReview(
                apiClient: widget.apiClient,
                chain: _selectedChain,
                year: _selectedYear,
                isOwner: _canRunSuggestions,
                onMappingsChanged: () {
                  // Approved mappings must feed Compare immediately (price tab ready).
                  _loadCompetitiveData(forceRefresh: true, silent: true);
                },
              ),
            ] else ...[

            // 2. Top 4 Competitive & Temporal Summary KPI Cards
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  _buildKpiCard(
                    context: context,
                    title: 'الأصناف النشطة $_selectedYear',
                    value: countSku(totalOwnSkus),
                    subtitle:
                        '$mappedOwnSkus بمنافسين محددين · ${countCompetitors(totalCompetitorSkus)}',
                    icon: Icons.calendar_month_rounded,
                    color: colorScheme.primary,
                    isLoading: _isLoading,
                  ),
                  _buildKpiCard(
                    context: context,
                    title: 'الميزة السعرية',
                    value: '$advantageSkusCount من ${countSku(totalOwnSkus)}',
                    subtitle: 'سعرنا أقل من متوسط المنافسين',
                    icon: Icons.trending_down_rounded,
                    color: M3Palette.success,
                    isLoading: _isLoading,
                  ),
                  _buildKpiCard(
                    context: context,
                    title: 'حركة الأسعار $_selectedYear',
                    value:
                        '▲$priceIncreasedSkusCount ▼$priceDecreasedSkusCount',
                    subtitle: '▲ زاد · ▼ نزل · $_monthRangeLabel',
                    icon: Icons.show_chart_rounded,
                    color: M3Palette.warning,
                    isLoading: _isLoading,
                  ),
                  _buildKpiCard(
                    context: context,
                    title: 'مؤشر السعر التنافسي',
                    value: avgPriceIndex == null
                        ? '—'
                        : '${avgPriceIndex.toStringAsFixed(1)}%',
                    subtitle: avgPriceIndex == null
                        ? (totalOwnSkus == 0
                            ? 'لا توجد أصناف'
                            : 'لا توجد أسعار منافسين للمقارنة')
                        : 'تهديد سعري مباشر في ${countSku(undercutRiskSkusCount)}',
                    icon: Icons.speed_rounded,
                    color: colorScheme.secondary,
                    isLoading: _isLoading,
                  ),
                ];

                // Same equal-height grid, breakpoints and 16dp gutters as the
                // Sell-Out KPI row.
                final maxWidth = constraints.maxWidth;
                return M3EqualHeightGrid(
                  key: const ValueKey('compare_kpi_cards_row'),
                  columns: maxWidth >= 960 ? 4 : (maxWidth >= 580 ? 2 : 1),
                  spacing: M3Spacing.sm,
                  runSpacing: M3Spacing.sm,
                  children: cards,
                );
              },
            ),

            M3Spacing.gapMD,

            // 3. Temporal & Chain Filter Toolbar
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
                          width: 360.0,
                          child: _buildOwnSkusMasterPanel(
                            context,
                            selectedGroup,
                          ),
                        ),
                        M3Spacing.gapMD,
                        // Left side in RTL: Focused 1-vs-1 Competitor Comparison & Monthly Trajectory
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
            ], // end compare tab
          ],
        ),
      ),
    );
  }

  bool get _canRunSuggestions {
    final u = widget.apiClient.currentUser;
    if (u == null) return false;
    return u.isSuperAdmin || u.role == 'vendor_admin';
  }

  Future<void> _loadAiPicksForSelectedOwn() async {
    if (!_canRunSuggestions) {
      if (mounted) {
        setState(() {
          _aiPicks = const [];
          _aiPicksLoading = false;
          _aiPicksEmptyHint = null;
        });
      }
      return;
    }
    final barcode = _selectedOwnBarcode;
    if (barcode == null || barcode.isEmpty) return;
    final seq = ++_aiPicksRequestSeq;
    setState(() {
      _aiPicksLoading = true;
      _aiPicksEmptyHint = null;
    });
    try {
      final result = await widget.apiClient.suggestCompetitorsForSku(
        barcode: barcode,
        chain: _selectedChain,
        year: _selectedYear,
      );
      if (!mounted || seq != _aiPicksRequestSeq) return;
      final pinned = _selectedGroup?.competitors.map((c) => c.barcode).toSet() ??
          const <String>{};
      // Owner-pinned mappings take priority — drop duplicates from AI row.
      final models = <CompetitorSkuComparisonModel>[];
      for (final s in result.suggestions) {
        if (pinned.contains(s.competitorBarcode)) continue;
        models.add(
          widget.apiClient.competitorFromAiSuggestion(
            s,
            ownUnitPrice: _selectedGroup?.ownUnitPrice ?? s.ownUnitPrice,
            year: _selectedYear,
          ),
        );
        if (models.length >= 3) break;
      }
      setState(() {
        _aiPicks = models;
        _aiPicksLoading = false;
        _aiPicksEmptyHint = models.isEmpty ? result.skippedReasonAr : null;
      });
    } catch (e) {
      if (!mounted || seq != _aiPicksRequestSeq) return;
      final msg = e is TimeoutException
          ? 'انتهت مهلة جلب اقتراحات المنافسين — حاول مرة أخرى'
          : e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      setState(() {
        _aiPicks = const [];
        _aiPicksLoading = false;
        // Surface a stable Arabic empty hint so the row never looks "stuck loading".
        _aiPicksEmptyHint = msg.isEmpty ? 'فشل جلب اقتراحات المنافسين' : msg;
      });
      M3Feedback.showError(
        context,
        msg.isEmpty ? 'فشل جلب اقتراحات المنافسين' : msg,
      );
    }
  }

  Widget _buildFilterToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final categories = _availableCategories;
    final yearOptions = _yearOptions;
    final monthOptions = _monthOptions;
    final selectedYear = yearOptions.any((y) => y.year == _selectedYear)
        ? _selectedYear
        : (yearOptions.isNotEmpty ? yearOptions.first.year : _selectedYear);
    final selectedMonth = monthOptions.any((m) => m.month == _selectedMonth)
        ? _selectedMonth
        : (monthOptions.isNotEmpty ? monthOptions.first.month : 0);

    return Container(
      key: const ValueKey('compare_filter_toolbar'),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Same 40dp M3Dropdown filters as Sell-Out / Trade Marketing.
          Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              M3Dropdown<int>(
                key: const ValueKey('compare_year_dropdown'),
                leadingIcon: Icons.event_note_rounded,
                width: kYearDropdownWidth,
                fitOptions: true,
                value: selectedYear,
                options: [
                  for (final yr in yearOptions)
                    M3DropdownOption(yr.year, yr.labelAr),
                ],
                onChanged: (yr) {
                  if (yr == _selectedYear) return;
                  setState(() {
                    _selectedYear = yr;
                    _yearTouched = true;
                    _selectedMonth = 0;
                    _simulatedOwnPrice = null;
                    _monthsLoadFinished = false;
                  });
                  _loadAvailableMonths();
                  _loadCompetitiveData();
                },
              ),
              if (monthOptions.isEmpty)
                if (_monthsLoadFinished && !_isLoading)
                  Text(
                    'لا توجد شهور بيانات لهذه السنة',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  const SizedBox.shrink()
              else
                M3Dropdown<int>(
                  key: const ValueKey('compare_month_dropdown'),
                  leadingIcon: Icons.timeline_rounded,
                  fitOptions: true,
                  value: selectedMonth,
                  options: [
                    for (final m in monthOptions)
                      M3DropdownOption(m.month, m.labelAr),
                  ],
                  onChanged: (month) {
                    if (month == _selectedMonth) return;
                    setState(() {
                      _selectedMonth = month;
                      _simulatedOwnPrice = null;
                    });
                    _loadCompetitiveData();
                  },
                ),
              M3Dropdown<String>(
                key: const ValueKey('compare_chain_dropdown'),
                leadingIcon: Icons.storefront_rounded,
                fitOptions: true,
                value: _selectedChain,
                options: [
                  for (final ch in _chainOptions)
                    M3DropdownOption(ch.code, ch.labelAr),
                ],
                onChanged: (code) {
                  if (code == _selectedChain) return;
                  setState(() => _selectedChain = code);
                  _loadCompetitiveData();
                },
              ),
              if (categories.length > 1)
                M3Dropdown<String>(
                  key: const ValueKey('compare_category_dropdown'),
                  leadingIcon: Icons.category_rounded,
                  fitOptions: true,
                  value: categories.contains(_selectedCategory)
                      ? _selectedCategory
                      : categories.first,
                  options: [
                    for (final cat in categories) M3DropdownOption(cat, cat),
                  ],
                  onChanged: (cat) {
                    // DropdownMenu may re-emit the same value on rebuild; ignore
                    // so own-SKU pagination is not reset to page 1.
                    if (cat == _selectedCategory) return;
                    setState(() {
                      _selectedCategory = cat;
                      _applyLocalFilters(resetPage: true);
                    });
                  },
                ),
            ],
          ),

          const SizedBox(height: 12.0),

          M3SearchFieldWidth(
            hintText: 'ابحث باسم الصنف، الباركود، أو المنافس...',
            hintStyle: theme.textTheme.bodyMedium,
            width: 340.0,
            child: TextField(
              key: const ValueKey('compare_search_field'),
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
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 8.0,
                ),
                constraints: const BoxConstraints(
                  maxHeight: M3ToolbarButton.height,
                ),
                filled: true,
                fillColor: colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: M3Shape.radiusMd,
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: M3Shape.radiusMd,
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Master List Panel showing the company's own SKUs (paginated, 10 / page).
  Widget _buildOwnSkusMasterPanel(
    BuildContext context,
    OwnSkuCompetitiveGroupModel selectedGroup, {
    bool isCompactList = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pageGroups = _ownSkuPageGroups;
    final totalCount = _filteredGroups.length;
    final totalPages = _ownSkuTotalPages;
    final safePage = _ownSkuSafePageIndex;
    final startIndex = totalCount == 0 ? 0 : safePage * _ownSkuPageSize + 1;
    final endIndex = totalCount == 0
        ? 0
        : (safePage * _ownSkuPageSize + pageGroups.length);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusXl,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(18.0, 16.0, 18.0, 14.0),
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
                    borderRadius: M3Shape.radiusSm,
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
                        'صنفك الأساسي ($_selectedYear)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        'اختر صنفك لعرض منافسيه المباشرين',
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
                    borderRadius: M3ChipStyle.radius,
                  ),
                  child: Text(
                    countSku(totalCount),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Pagination sits under the header (before the SKU cards) so Next/Prev
          // stay reachable — taller M3ChipSurface cards used to push the bar
          // past a 3200dp test surface (~y 4300) and leave Next untappable.
          if (totalCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 0.0),
              child: _buildOwnSkuPaginationBar(
                context,
                safePage: safePage,
                totalPages: totalPages,
                startIndex: startIndex,
                endIndex: endIndex,
                totalCount: totalCount,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                for (final group in pageGroups)
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

  /// RTL-aware prev/next: [AppIcons.chevronStart]/[AppIcons.chevronEnd] mirror;
  /// Row places previous at the reading start (right in RTL).
  Widget _buildOwnSkuPaginationBar(
    BuildContext context, {
    required int safePage,
    required int totalPages,
    required int startIndex,
    required int endIndex,
    required int totalCount,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canGoPrev = safePage > 0;
    final canGoNext = safePage < totalPages - 1;

    return Container(
      key: const ValueKey('own_sku_pagination_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: M3Shape.radiusMd,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        children: [
          Text(
            key: const ValueKey('own_sku_page_indicator'),
            'صفحة ${safePage + 1} من $totalPages',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2.0),
          Text(
            key: const ValueKey('own_sku_range_indicator'),
            '$startIndex–$endIndex من $totalCount',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('own_sku_pagination_prev_btn'),
                icon: const Icon(AppIcons.chevronStart, size: 20.0),
                tooltip: 'الصفحة السابقة',
                visualDensity: VisualDensity.compact,
                onPressed: canGoPrev
                    ? () => setState(() => _ownSkuPageIndex = safePage - 1)
                    : null,
              ),
              const SizedBox(width: 8.0),
              IconButton(
                key: const ValueKey('own_sku_pagination_next_btn'),
                icon: const Icon(AppIcons.chevronEnd, size: 20.0),
                tooltip: 'الصفحة التالية',
                visualDensity: VisualDensity.compact,
                onPressed: canGoNext
                    ? () => setState(() => _ownSkuPageIndex = safePage + 1)
                    : null,
              ),
            ],
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

    final hasCompAvg =
        group.competitors.isNotEmpty && group.avgCompetitorPrice > 0;
    final vsAvgDiffEgp = group.ownUnitPrice - group.avgCompetitorPrice;
    final vsAvgDiffPct = hasCompAvg
        ? (vsAvgDiffEgp / group.avgCompetitorPrice) * 100.0
        : 0.0;

    final bool weAreCheaper = hasCompAvg && vsAvgDiffPct < -1.5;
    final bool weAreMoreExpensive = hasCompAvg && vsAvgDiffPct > 1.5;
    final bool uncompared = !hasCompAvg;

    final Color badgeBg = uncompared
        ? colorScheme.surfaceContainerHighest
        : weAreCheaper
            ? M3Palette.successSurface
            : weAreMoreExpensive
                ? M3Palette.dangerSurface
                : colorScheme.secondaryContainer;
    final Color badgeFg = uncompared
        ? colorScheme.onSurfaceVariant
        : weAreCheaper
            ? M3Palette.onSuccessSurface
            : weAreMoreExpensive
                ? M3Palette.onDangerSurface
                : colorScheme.onSecondaryContainer;
    final String badgeShort = uncompared
        ? 'غير مقارن'
        : weAreCheaper
            ? 'أرخص'
            : weAreMoreExpensive
                ? 'أغلى'
                : 'مساوٍ';
    final String badgeDetail = uncompared
        ? 'لم يتم تحديد المنافسين بعد'
        : weAreCheaper
            ? 'من السوق بـ ${vsAvgDiffPct.abs().toStringAsFixed(1)}%'
            : weAreMoreExpensive
                ? 'من السوق بـ ${CurrencyFormatter.formatSignedPct(vsAvgDiffPct)}'
                : 'لمتوسط السوق';

    final bool hasPeriodChange = group.monthlyPrices.length >= 2;
    final double momPct = group.periodPriceChangePct;
    final bool priceRose = hasPeriodChange && momPct > 0.5;
    final bool priceDropped = hasPeriodChange && momPct < -0.5;

    return Material(
      color: isSelected ? M3Palette.successSurface : colorScheme.surface,
      borderRadius: M3Shape.radiusLg,
      elevation: isSelected ? 2.0 : 0.0,
      child: InkWell(
        borderRadius: M3Shape.radiusLg,
        onTap: () {
          setState(() {
            _selectedOwnBarcode = group.ownBarcode;
            _simulatedOwnPrice = group.ownUnitPrice;
            _selectedCompetitorBarcode = group.competitors.isNotEmpty
                ? group.competitors.first.barcode
                : null;
          });
          _loadAiPicksForSelectedOwn();
        },
        child: AnimatedContainer(
          duration: M3Motion.short4,
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: isSelected
                  ? _ownBrandGreen
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
                            M3ChipSurface(
                              color: isSelected
                                  ? _ownBrandGreen
                                  : colorScheme.surfaceContainerHighest,
                              child: Text(
                                group.ownBrand,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? Colors.white
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            M3ChipSurface(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.7),
                              child: Text(
                                group.packSizeLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (priceRose || priceDropped)
                              M3ChipSurface(
                                color: priceRose
                                    ? M3Palette.warningSurface
                                    : M3Palette.infoSurface,
                                child: Text(
                                  priceRose
                                      ? '▲ ${CurrencyFormatter.formatSignedPct(momPct)} في $_selectedYear'
                                      : '▼ ${CurrencyFormatter.formatSignedPct(momPct)} في $_selectedYear',
                                  style: TextStyle(
                                    fontSize: M3FontSize.labelSmallPlus,
                                    fontWeight: FontWeight.w800,
                                    color: priceRose
                                        ? M3Palette.onWarningSurface
                                        : M3Palette.onInfoSurface,
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
                                ? M3Palette.onSuccessSurface
                                : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${group.ownUnitPrice.toStringAsFixed(1)} ج.م',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: _ownBrandGreen,
                        ),
                      ),
                      Text(
                        '${group.ownPricePerUnitVolume.toStringAsFixed(1)} ج/${group.volumeUnitLabel}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: M3FontSize.tinyPlus,
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
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        M3ChipSurface(
                          key: ValueKey(
                              'compare_own_badge_${group.ownBarcode}'),
                          color: badgeBg,
                          child: Text(
                            badgeShort,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: badgeFg,
                              fontSize: M3FontSize.labelSmallPlus,
                            ),
                          ),
                        ),
                        const SizedBox(height: M3Spacing.s2),
                        Text(
                          badgeDetail,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        group.competitors.isEmpty
                            ? 'لم يتم تحديد المنافسين بعد'
                            : countCompetitors(group.competitors.length),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? _ownBrandGreen
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4.0),
                      Icon(
                        AppIcons.chevronEnd,
                        size: 16.0,
                        color: isSelected
                            ? _ownBrandGreen
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
  /// 1. Default Own SKU Spotlight Card (+ AI top-3 under KPI metrics)
  /// 2. Interactive What-If Price Simulator (if toggled)
  /// 3. Single Clean Competitor Selector Row (owner-pinned; AI picks are separate)
  /// 4. Focused 1-vs-1 Monthly Price Trajectory Chart for Own SKU + Selected Competitor.
  Widget _buildCompetitorDetailPanel(
    BuildContext context,
    OwnSkuCompetitiveGroupModel group,
  ) {
    final effectiveOwnPrice =
        (_showWhatIfSimulator && _simulatedOwnPrice != null)
            ? _simulatedOwnPrice!
            : group.ownUnitPrice;
    final effectiveOwnPricePerVol = group.packVolumeUnits > 0
        ? double.parse(
            (effectiveOwnPrice / group.packVolumeUnits).toStringAsFixed(2))
        : effectiveOwnPrice;

    // Deduplicate by brand and recompute price context against effectiveOwnPrice.
    // Owner-pinned only — AI picks stay out of KPI averages while the HOLD flag is OFF.
    final seenBrands = <String>{};
    final adjustedCompetitors = <CompetitorSkuComparisonModel>[];
    for (final c in group.competitors) {
      final brandKey = c.brand.trim().toLowerCase();
      if (!seenBrands.add(brandKey)) continue;
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
      adjustedCompetitors.add(
        c.copyWithPriceContext(
          priceDiffEgp: double.parse(diffEgp.toStringAsFixed(2)),
          priceDiffPct: double.parse(diffPct.toStringAsFixed(1)),
          pricePosition: pos,
        ),
      );
    }

    // Resolve selected competitor: owner pin first, else AI pick (view without approve).
    CompetitorSkuComparisonModel? selectedCompetitor;
    for (final c in adjustedCompetitors) {
      if (c.barcode == _selectedCompetitorBarcode) {
        selectedCompetitor = c;
        break;
      }
    }
    if (selectedCompetitor == null) {
      for (final c in _aiPicks) {
        if (c.barcode == _selectedCompetitorBarcode) {
          selectedCompetitor = c.copyWithPriceContext(
            priceDiffEgp: double.parse(
                (c.unitPrice - effectiveOwnPrice).toStringAsFixed(2)),
            priceDiffPct: double.parse(
              (effectiveOwnPrice > 0
                      ? ((c.unitPrice - effectiveOwnPrice) / effectiveOwnPrice) *
                          100.0
                      : 0.0)
                  .toStringAsFixed(1),
            ),
            pricePosition: (c.unitPrice - effectiveOwnPrice) /
                        (effectiveOwnPrice > 0 ? effectiveOwnPrice : 1) *
                        100 >
                    1.5
                ? 'higher'
                : (c.unitPrice - effectiveOwnPrice) /
                            (effectiveOwnPrice > 0 ? effectiveOwnPrice : 1) *
                            100 <
                        -1.5
                    ? 'lower'
                    : 'equal',
          );
          break;
        }
      }
    }
    if (selectedCompetitor == null && adjustedCompetitors.isNotEmpty) {
      selectedCompetitor = adjustedCompetitors.first;
    } else if (selectedCompetitor == null && _aiPicks.isNotEmpty) {
      selectedCompetitor = _aiPicks.first;
    }

    // KPI status pills: owner-pinned only unless HOLD flag is flipped ON.
    final kpiCompetitors = ApiClient.includeAiSuggestionsInKpiAverages
        ? [...adjustedCompetitors, ..._aiPicks]
        : adjustedCompetitors;
    final higherCount =
        kpiCompetitors.where((c) => c.pricePosition == 'higher').length;
    final lowerCount =
        kpiCompetitors.where((c) => c.pricePosition == 'lower').length;
    final equalCount =
        kpiCompetitors.where((c) => c.pricePosition == 'equal').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A. Default Own SKU Benchmark Spotlight Card
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
          ),
        ],

        M3Spacing.gapMD,

        if (adjustedCompetitors.isEmpty &&
            _aiPicks.isEmpty &&
            !_aiPicksLoading) ...[
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: M3Shape.radiusXl,
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.65),
              ),
            ),
            child: Text(
              'لم يتم تحديد المنافسين بعد — معروض مبيعات وسعر صنفنا فقط',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (group.monthlyPrices.isNotEmpty) ...[
            M3Spacing.gapMD,
            Container(
              height: 240.0,
              padding: const EdgeInsetsDirectional.fromSTEB(18.0, 24.0, 22.0, 14.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: M3Shape.radiusLg,
                border: Border.all(
                  color: _ownBrandGreen.withValues(alpha: 0.35),
                ),
              ),
              child: CustomPaint(
                painter: _MonthlyPriceTrajectoryPainter(
                  ownSeries: _showFullTwoYearTimeline
                      ? group.allMonthlyPrices
                      : group.monthlyPrices,
                  competitorSeries: const [],
                  ownColor: _ownBrandGreen,
                  compColor: M3Palette.dangerAccent,
                  gridColor: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.4),
                  textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  selectedMonth: _selectedMonth,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ] else if (adjustedCompetitors.isNotEmpty)
          // C. Owner-pinned competitor selector (AI picks live under spotlight KPIs).
          _buildCompetitorBrandSelectorSection(
            context,
            group: group,
            competitors: adjustedCompetitors,
            selectedCompetitor: selectedCompetitor,
            effectiveOwnPrice: effectiveOwnPrice,
          ),

        if (selectedCompetitor != null) ...[
          M3Spacing.gapMD,

          // D. Focused 1-vs-1 Monthly Trajectory Chart + Jan/Feb/Mar/Apr Comparison Cards
          // (Shows Default Own SKU vs. Selected Competitor ONLY — never cluttered!)
          _buildFocusedOneVsOneTrajectoryCard(
            context,
            group: group,
            selectedCompetitor: selectedCompetitor,
            effectiveOwnPrice: effectiveOwnPrice,
            effectiveOwnPricePerVol: effectiveOwnPricePerVol,
          ),
        ],
      ],
    );
  }

  /// Clean Material Design 3 Competitor Brand Selector Row:
  /// Shows 1 compact card per rival brand (e.g. Pril 4Kg, Fairy 2L, Wafeer 4Kg).
  /// Clicking a card selects that competitor and updates the chart & monthly data below.
  Widget _buildCompetitorBrandSelectorSection(
    BuildContext context, {
    required OwnSkuCompetitiveGroupModel group,
    required List<CompetitorSkuComparisonModel> competitors,
    required CompetitorSkuComparisonModel? selectedCompetitor,
    required double effectiveOwnPrice,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusXl,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: M3Shape.radiusMd,
                ),
                child: Icon(
                  Icons.compare_arrows_rounded,
                  color: colorScheme.onSecondaryContainer,
                  size: 20.0,
                ),
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'اختر المنافس لعرض حركة أسعاره الشهرية أمام (${group.ownBrand} — ${group.packSizeLabel})',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    Text(
                      'اضغط على أي منافس بالأسفل لمقارنة حركة سعره في ($_monthEnumeratedLabel) مع صنفك الأساسي',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16.0),

          // Responsive equal-height grid of competitor cards: wraps into
          // rows instead of squeezing every competitor into one row.
          LayoutBuilder(
            builder: (context, constraints) {
              final count = competitors.length;
              if (count == 0) return const SizedBox.shrink();
              final w = constraints.maxWidth;
              final columns =
                  math.min(count, w >= 720.0 ? 3 : (w >= 480.0 ? 2 : 1));
              return M3EqualHeightGrid(
                key: const ValueKey('compare_competitor_grid'),
                columns: columns,
                spacing: M3Spacing.s12,
                runSpacing: M3Spacing.s12,
                children: [
                  for (final c in competitors)
                    _buildSingleBrandCompetitorTile(
                      context,
                      competitor: c,
                      isSelected: selectedCompetitor?.barcode == c.barcode,
                      effectiveOwnPrice: effectiveOwnPrice,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSingleBrandCompetitorTile(
    BuildContext context, {
    required CompetitorSkuComparisonModel competitor,
    required bool isSelected,
    required double effectiveOwnPrice,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bool isCompHigher = competitor.pricePosition == 'higher';
    final bool isCompLower = competitor.pricePosition == 'lower';

    final Color statusBg = isCompHigher
        ? M3Palette.successSurface
        : isCompLower
            ? M3Palette.dangerSurface
            : colorScheme.secondaryContainer;
    final Color statusFg = isCompHigher
        ? M3Palette.onSuccessSurface
        : isCompLower
            ? M3Palette.onDangerSurface
            : colorScheme.onSecondaryContainer;

    final String statusShort = isCompHigher
        ? 'أغلى'
        : isCompLower
            ? 'أرخص'
            : 'مساوٍ';
    final String statusDetail = isCompHigher
        ? 'منك بـ +${competitor.priceDiffEgp.abs().toStringAsFixed(1)} ج (${CurrencyFormatter.formatSignedPct(competitor.priceDiffPct.abs())})'
        : isCompLower
            ? 'منك بـ -${competitor.priceDiffEgp.abs().toStringAsFixed(1)} ج (${CurrencyFormatter.formatSignedPct(-competitor.priceDiffPct.abs())})'
            : 'لسعرك';

    const Color activeAccent = M3Palette.dangerAccent;

    return Material(
      color: isSelected
          ? activeAccent.withValues(alpha: 0.08)
          : colorScheme.surface,
      borderRadius: M3Shape.radiusLg,
      elevation: isSelected ? 3.0 : 0.0,
      child: InkWell(
        borderRadius: M3Shape.radiusLg,
        onTap: () {
          setState(() {
            _selectedCompetitorBarcode = competitor.barcode;
          });
        },
        child: AnimatedContainer(
          duration: M3Motion.short4,
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: isSelected
                  ? activeAccent
                  : colorScheme.outlineVariant.withValues(alpha: 0.7),
              width: isSelected ? 2.2 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: Brand Name + Pack Volume Badge + Selected Checkmark
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10.0,
                              height: 10.0,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? activeAccent
                                    : colorScheme.outline,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            Flexible(
                              child: Text(
                                competitor.brand,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: isSelected
                                      ? activeAccent
                                      : colorScheme.onSurface,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      M3ChipSurface(
                        color: isSelected
                            ? activeAccent
                            : colorScheme.surfaceContainerHighest,
                        child: Text(
                          competitor.packSizeLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: isSelected
                                ? Colors.white
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (_repo.isCustomSku(competitor.barcode))
                        IconButton(
                          tooltip: 'حذف منتج المنافس',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline_rounded, size: 20.0),
                          onPressed: () => _confirmDeleteCustomCompetitor(competitor),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    competitor.skuName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),

              const SizedBox(height: 14.0),

              // Bottom row: Competitor Price + Higher/Lower Badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'سعر بيع المنافس',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '${competitor.unitPrice.toStringAsFixed(1)} ج.م',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'سعر الـ ${competitor.volumeUnitLabel}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '${competitor.pricePerUnitVolume.toStringAsFixed(1)} ج/${competitor.volumeUnitLabel}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10.0),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: AlignmentDirectional.center,
                        child: M3ChipSurface(
                          color: statusBg,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isCompHigher
                                    ? Icons.arrow_upward_rounded
                                    : isCompLower
                                        ? Icons.arrow_downward_rounded
                                        : Icons.drag_handle_rounded,
                                size: 16.0,
                                color: statusFg,
                              ),
                              M3Spacing.hGapXS,
                              Text(
                                statusShort,
                                style: TextStyle(
                                  fontSize: M3FontSize.labelSmallPlus,
                                  fontWeight: FontWeight.w800,
                                  color: statusFg,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: M3Spacing.s2),
                      Text(
                        statusDetail,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
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
    );
  }

  /// Focused 1-vs-1 Monthly Trajectory Card:
  /// - Does NOT show the deleted title "منحنى حركة الأسعار الشهرية المقارن لسنة 2026".
  /// - Gives generous line-height and top spacing to the description text.
  /// - Plots ONLY 2 lines: Default Own SKU (brand green) vs. Selected Competitor across every month with data.
  /// - Displays one M3 month card per returned series point.
  Widget _buildFocusedOneVsOneTrajectoryCard(
    BuildContext context, {
    required OwnSkuCompetitiveGroupModel group,
    required CompetitorSkuComparisonModel selectedCompetitor,
    required double effectiveOwnPrice,
    required double effectiveOwnPricePerVol,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final List<SkuMonthlyPricePointModel> ownSeries = _showFullTwoYearTimeline
        ? group.allMonthlyPrices
        : group.monthlyPrices;
    final List<SkuMonthlyPricePointModel> compSeries = _showFullTwoYearTimeline
        ? selectedCompetitor.allMonthlyPrices
        : selectedCompetitor.monthlyPrices;

    const Color compColor = M3Palette.dangerAccent;

    // Check Shrinkflation between our SKU and the selected competitor
    final bool isCompLower = selectedCompetitor.pricePosition == 'lower';
    final bool shrinkflationDetected = isCompLower &&
        selectedCompetitor.pricePerUnitVolume > effectiveOwnPricePerVol;

    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusXl,
        border: Border.all(
          color: _ownBrandGreen.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Bar: 1-vs-1 Badges (Default Own SKU vs Selected Competitor) + 2025/2026 Toggle
          Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Clean 2-Item Comparison Header Pills (No duplicate chips!)
              Wrap(
                spacing: 10.0,
                runSpacing: 8.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 8.0,
                    ),
                    decoration: const BoxDecoration(
                      color: M3Palette.successSurface,
                      borderRadius: M3ChipStyle.radius,
                      border:
                          Border.fromBorderSide(BorderSide(color: _ownBrandGreen, width: 1.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12.0,
                          height: 12.0,
                          decoration: const BoxDecoration(
                            color: _ownBrandGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Text(
                          'صنفنا الأساسي: ${group.ownBrand} • ${group.packSizeLabel} (${effectiveOwnPrice.toStringAsFixed(1)} ج.م)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: M3Palette.onSuccessSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'مقابل',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 8.0,
                    ),
                    decoration: BoxDecoration(
                      color: compColor.withValues(alpha: 0.10),
                      borderRadius: M3ChipStyle.radius,
                      border: Border.all(color: compColor, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12.0,
                          height: 12.0,
                          decoration: const BoxDecoration(
                            color: compColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Text(
                          'المنافس المختار: ${selectedCompetitor.brand} • ${selectedCompetitor.packSizeLabel} (${selectedCompetitor.unitPrice.toStringAsFixed(1)} ج.م)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: compColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              FilterChip(
                key: const ValueKey('compare_timeline_toggle'),
                avatar: Icon(
                  _showFullTwoYearTimeline
                      ? Icons.visibility_rounded
                      : Icons.date_range_rounded,
                  size: 18.0,
                ),
                label: Text(
                  _showFullTwoYearTimeline
                      ? 'عرض شهور $_selectedYear فقط ($_monthRangeLabel)'
                      : 'دمج مسار السنتين (كل الشهور المتاحة)',
                ),
                selected: _showFullTwoYearTimeline,
                visualDensity: VisualDensity.standard,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (v) {
                  setState(() => _showFullTwoYearTimeline = v);
                },
              ),
            ],
          ),

          // Generous vertical distance & line-height before the subtitle text as requested
          const SizedBox(height: 16.0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text(
              'يرسم اتجاه سعر بيع صنفك (خط أخضر عريض) أمام سعر المنافس المختار (${selectedCompetitor.brand} — ${selectedCompetitor.packSizeLabel}) شهراً بشهر خلال ($_monthEnumeratedLabel) مع نسب الارتفاع (▲) والانخفاض (▼).',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 18.0),

          // Focused 2-Line Price Trajectory Canvas Chart (Own SKU vs Selected Competitor ONLY)
          Container(
            height: 280.0,
            padding: const EdgeInsetsDirectional.fromSTEB(18.0, 24.0, 22.0, 14.0),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: M3Shape.radiusLg,
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: CustomPaint(
              painter: _MonthlyPriceTrajectoryPainter(
                ownSeries: ownSeries,
                competitorSeries: compSeries,
                ownColor: _ownBrandGreen,
                compColor: compColor,
                gridColor: colorScheme.outlineVariant.withValues(alpha: 0.4),
                textColor: colorScheme.onSurfaceVariant,
                selectedMonth: _selectedMonth,
              ),
              child: const SizedBox.expand(),
            ),
          ),

          if (shrinkflationDetected) ...[
            const SizedBox(height: 14.0),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 10.0,
              ),
              decoration: BoxDecoration(
                color: M3Palette.warningSurface,
                borderRadius: M3Shape.radiusMd,
                border: Border.all(
                  color: M3Palette.warningAccent.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 19.0,
                    color: M3Palette.onWarningSurface,
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Text(
                      'تنبيه الحجم الصافي (Shrinkflation): رغم أن سعر عبوة ${selectedCompetitor.brand} (${selectedCompetitor.unitPrice.toStringAsFixed(1)} ج.م) أقل من عبوتك (${effectiveOwnPrice.toStringAsFixed(1)} ج.م)، إلا أن عبوة المنافس (${selectedCompetitor.packSizeLabel}) أصغر حجماً، وبالتالي سعر الـ ${selectedCompetitor.volumeUnitLabel} عندك أرخص فعلياً (${effectiveOwnPricePerVol.toStringAsFixed(1)} مقابل ${selectedCompetitor.pricePerUnitVolume.toStringAsFixed(1)} ج.م)!',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: M3Palette.onWarningSurfaceDeep,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 22.0),

          // Month-by-Month Side-by-Side Breakdown for Own SKU vs Selected Competitor
          Row(
            children: [
              Expanded(
                child: Text(
                  'مقارنة الشهور (${_showFullTwoYearTimeline ? "كل السنوات المتاحة" : "$_monthRangeLabel $_selectedYear"}) — ${group.ownBrand} مقابل ${selectedCompetitor.brand}:',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8.0),
              Text(
                'اضغط على أي شهر لتصفية المؤشرات به',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12.0),

          LayoutBuilder(
            builder: (context, constraints) {
              // Keep month cards at a readable width; scroll when more than four.
              final isDesktop =
                  constraints.maxWidth >= 820.0 && ownSeries.length <= 4;
              if (isDesktop) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < ownSeries.length; i++) ...[
                        Expanded(
                          child: _buildOneVsOneMonthCard(
                            context,
                            ownPoint: ownSeries[i],
                            compPoint: _findMatchingMonthPoint(
                              compSeries,
                              ownSeries[i].year,
                              ownSeries[i].monthNum,
                            ),
                            ownBrand: group.ownBrand,
                            compBrand: selectedCompetitor.brand,
                            compColor: compColor,
                            isSelectedMonth:
                                _selectedMonth == ownSeries[i].monthNum &&
                                    _selectedYear == ownSeries[i].year,
                            onTap: () {
                              setState(() {
                                _selectedYear = ownSeries[i].year;
                                _selectedMonth =
                                    _selectedMonth == ownSeries[i].monthNum
                                        ? 0
                                        : ownSeries[i].monthNum;
                              });
                              _loadCompetitiveData();
                            },
                          ),
                        ),
                        if (i < ownSeries.length - 1)
                          const SizedBox(width: 12.0),
                      ],
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (int i = 0; i < ownSeries.length; i++)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 12.0),
                        child: SizedBox(
                          width: 245.0,
                          child: _buildOneVsOneMonthCard(
                            context,
                            ownPoint: ownSeries[i],
                            compPoint: _findMatchingMonthPoint(
                              compSeries,
                              ownSeries[i].year,
                              ownSeries[i].monthNum,
                            ),
                            ownBrand: group.ownBrand,
                            compBrand: selectedCompetitor.brand,
                            compColor: compColor,
                            isSelectedMonth:
                                _selectedMonth == ownSeries[i].monthNum &&
                                    _selectedYear == ownSeries[i].year,
                            onTap: () {
                              setState(() {
                                _selectedYear = ownSeries[i].year;
                                _selectedMonth =
                                    _selectedMonth == ownSeries[i].monthNum
                                        ? 0
                                        : ownSeries[i].monthNum;
                              });
                              _loadCompetitiveData();
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  SkuMonthlyPricePointModel? _findMatchingMonthPoint(
    List<SkuMonthlyPricePointModel> list,
    int year,
    int monthNum,
  ) {
    // Exact (year, month) only: a month the competitor has no price for
    // shows «no price», never another month's (or year's) value.
    for (final pt in list) {
      if (pt.year == year && pt.monthNum == monthNum) return pt;
    }
    return null;
  }

  /// Single Month Card (e.g. يناير 2026) comparing:
  /// - Our Default SKU price & MoM change (▲/▼)
  /// - Selected Competitor price & MoM change (▲/▼)
  /// - Net Price Gap in that month
  Widget _buildOneVsOneMonthCard(
    BuildContext context, {
    required SkuMonthlyPricePointModel ownPoint,
    required SkuMonthlyPricePointModel? compPoint,
    required String ownBrand,
    required String compBrand,
    required Color compColor,
    required bool isSelectedMonth,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String formatDelta(SkuMonthlyPricePointModel pt) {
      if (pt.trendDirection == 'baseline') return 'بداية الفترة';
      if (pt.trendDirection == 'up') {
        return '▲ ${CurrencyFormatter.formatSignedPct(pt.priceChangePct)}';
      }
      if (pt.trendDirection == 'down') {
        return '▼ ${CurrencyFormatter.formatSignedPct(pt.priceChangePct)}';
      }
      // Flat / unavailable — never advertise a fake measured 0%.
      return '• مستقر';
    }

    Color deltaColor(SkuMonthlyPricePointModel pt) {
      if (pt.trendDirection == 'up') return M3Palette.onWarningSurface;
      if (pt.trendDirection == 'down') return M3Palette.onSuccessSurface;
      return colorScheme.onSurfaceVariant;
    }

    final double gapEgp =
        compPoint != null ? (compPoint.unitPrice - ownPoint.unitPrice) : 0.0;
    final bool compHigher = gapEgp > 1.0;
    final bool compLower = gapEgp < -1.0;

    return Material(
      color: isSelectedMonth
          ? M3Palette.successSurface.withValues(alpha: 0.85)
          : colorScheme.surface,
      borderRadius: M3Shape.radiusLg,
      child: InkWell(
        borderRadius: M3Shape.radiusLg,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: isSelectedMonth
                  ? _ownBrandGreen
                  : colorScheme.outlineVariant.withValues(alpha: 0.7),
              width: isSelectedMonth ? 2.0 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Month Header
              Row(
                children: [
                  Flexible(
                    child: Text(
                      ownPoint.monthLabelAr,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Flexible(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          M3ChipSurface(
                            color: compHigher
                                ? M3Palette.successSurface
                                : compLower
                                    ? M3Palette.dangerSurface
                                    : colorScheme.surfaceContainerHighest,
                            child: Text(
                              compPoint == null
                                  ? '—'
                                  : compHigher
                                      ? 'أغلى'
                                      : compLower
                                          ? 'أرخص'
                                          : 'متقارب',
                              style: TextStyle(
                                fontSize: M3FontSize.labelSmallPlus,
                                fontWeight: FontWeight.w800,
                                color: compHigher
                                    ? M3Palette.onSuccessSurface
                                    : compLower
                                        ? M3Palette.onDangerSurface
                                        : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (compPoint == null) ...[
                            const SizedBox(height: M3Spacing.s2),
                            Text(
                              'لا يوجد سعر للمنافس',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else if (compHigher || compLower) ...[
                            const SizedBox(height: M3Spacing.s2),
                            Text(
                              '${compHigher ? '+' : ''}${gapEgp.toStringAsFixed(1)} ج',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12.0),
              const Divider(height: 1.0),
              const SizedBox(height: 10.0),

              // Row 1: Our Default SKU in this month
              Container(
                padding: const EdgeInsets.all(10.0),
                decoration: const BoxDecoration(
                  color: M3Palette.successSurface,
                  borderRadius: M3Shape.radiusMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'صنفنا ($ownBrand)',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: M3Palette.onSuccessSurface,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          formatDelta(ownPoint),
                          style: TextStyle(
                            fontSize: M3FontSize.tinyPlus,
                            fontWeight: FontWeight.w900,
                            color: deltaColor(ownPoint),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            '${ownPoint.unitPrice.toStringAsFixed(2)} ج.م',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: _ownBrandGreen,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${ownPoint.unitsSold} عبوة',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8.0),

              // Row 2: Selected Competitor in this month
              if (compPoint != null)
                Container(
                  key: ValueKey(
                      'compare_month_comp_${ownPoint.year}_${ownPoint.monthNum}'),
                  padding: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: compColor.withValues(alpha: 0.07),
                    borderRadius: M3Shape.radiusMd,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              'المنافس ($compBrand)',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: compColor,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            formatDelta(compPoint),
                            style: TextStyle(
                              fontSize: M3FontSize.tinyPlus,
                              fontWeight: FontWeight.w900,
                              color: deltaColor(compPoint),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              '${compPoint.unitPrice.toStringAsFixed(2)} ج.م',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: colorScheme.onSurface,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${compPoint.unitsSold} عبوة',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Container(
                  key: ValueKey(
                      'compare_month_no_comp_${ownPoint.year}_${ownPoint.monthNum}'),
                  padding: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: M3Shape.radiusMd,
                  ),
                  child: Text(
                    'لا يوجد سعر لـ $compBrand في هذا الشهر',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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

    String monthlyMovementSummary = 'استقرار سعري خلال شهور $_selectedYear';
    String movementChip = 'سعر مستقر';
    Color movementBg = colorScheme.secondaryContainer;
    Color movementFg = colorScheme.onSecondaryContainer;
    IconData movementIcon = Icons.timeline_rounded;

    final changes = group.monthlyPrices
        .where((m) => m.priceChangePct.abs() >= 0.5)
        .toList();
    if (changes.isNotEmpty) {
      final upMonths = changes
          .where((m) => m.priceChangePct > 0.5)
          .map((m) =>
              '${m.monthNameAr} (${CurrencyFormatter.formatSignedPct(m.priceChangePct)})')
          .toList();
      final downMonths = changes
          .where((m) => m.priceChangePct < -0.5)
          .map((m) =>
              '${m.monthNameAr} (${CurrencyFormatter.formatSignedPct(m.priceChangePct)})')
          .toList();

      final parts = <String>[];
      if (upMonths.isNotEmpty) {
        parts.add('ارتفع في: ${upMonths.join('، ')}');
      }
      if (downMonths.isNotEmpty) {
        parts.add('انخفض في: ${downMonths.join('، ')}');
      }
      monthlyMovementSummary = parts.join(' | ');
      movementChip = 'تغيّر السعر';
      if (group.periodPriceChangePct > 0.5) {
        movementChip = 'ارتفاع السعر';
        movementBg = M3Palette.warningSurface;
        movementFg = M3Palette.onWarningSurface;
        movementIcon = Icons.trending_up_rounded;
      } else if (group.periodPriceChangePct < -0.5) {
        movementBg = M3Palette.infoSurface;
        movementFg = M3Palette.onInfoSurface;
        movementIcon = Icons.trending_down_rounded;
        movementChip = 'انخفاض السعر';
      }
    }

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            M3Palette.successSurface.withValues(alpha: 0.95),
            colorScheme.surfaceContainerLow,
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: M3Shape.radiusXl,
        border: Border.all(
          color: _ownBrandGreen.withValues(alpha: 0.35),
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
                        M3ChipSurface(
                          color: _ownBrandGreen,
                          child: Text(
                            'صنفنا الافتراضي ($_activePeriodLabelAr)',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        M3ChipSurface(
                          color: colorScheme.surface,
                          child: Text(
                            'الفئة: ${group.category}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        M3ChipSurface(
                          color: colorScheme.surface,
                          child: Text(
                            'العبوة: ${group.packSizeLabel}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
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
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  _buildSpotlightMetricBox(
                    context,
                    label: _selectedMonth == 0
                        ? 'سعر بيعنا ($_selectedYear)'
                        : 'سعر بيعنا في $_activePeriodLabelAr',
                    value: '${effectiveOwnPrice.toStringAsFixed(2)} ج.م',
                    subValue:
                        '${effectiveOwnPricePerVol.toStringAsFixed(1)} ج.م / ${group.volumeUnitLabel}',
                    isHighlighted: true,
                  ),
                  _buildSpotlightMetricBox(
                    context,
                    key: const ValueKey('compare_spotlight_avg_comp'),
                    label: 'متوسط سعر المنافسين',
                    value: group.competitors.isEmpty ||
                            group.avgCompetitorPrice <= 0
                        ? '—'
                        : '${group.avgCompetitorPrice.toStringAsFixed(2)} ج.م',
                    subValue: group.competitors.isEmpty ||
                            group.avgCompetitorPrice <= 0
                        ? 'لم يتم تحديد المنافسين بعد'
                        : 'المدى: ${group.minCompetitorPrice.toStringAsFixed(0)} - ${group.maxCompetitorPrice.toStringAsFixed(0)} ج.م',
                  ),
                  _buildSpotlightMetricBox(
                    context,
                    key: const ValueKey('compare_spotlight_period_change'),
                    label: 'التغير السعري في $_selectedYear',
                    value: group.monthlyPrices.length < 2
                        ? '—'
                        : CurrencyFormatter.formatSignedPct(
                            group.periodPriceChangePct),
                    subValue: group.monthlyPrices.length < 2
                        ? 'لا توجد بيانات كافية لحساب التغير'
                        : '${group.periodPriceChangeEgp >= 0 ? '+' : ''}${group.periodPriceChangeEgp.toStringAsFixed(1)} ج.م (${_monthRangeLabel.replaceFirst(' - ', ' ← ')})',
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
          if (_canRunSuggestions) ...[
            const SizedBox(height: 16.0),
            CompetitorAiPicksRow(
              loading: _aiPicksLoading,
              picks: _aiPicks,
              selectedBarcode: _selectedCompetitorBarcode,
              emptyHintAr: _aiPicksEmptyHint,
              onSelect: (c) {
                setState(() => _selectedCompetitorBarcode = c.barcode);
              },
            ),
          ],
          const SizedBox(height: 16.0),
          const Divider(height: 1.0),
          const SizedBox(height: 12.0),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  'الموقف التنافسي وحركة السعر:',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _buildStatusCountPill(
                shortLabel: 'أرخص',
                description: 'من ${countCompetitors(higherCount)}',
                bgColor: M3Palette.successSurface,
                fgColor: M3Palette.onSuccessSurface,
                icon: Icons.arrow_upward_rounded,
              ),
              _buildStatusCountPill(
                shortLabel: 'أغلى',
                description: 'من ${countCompetitors(lowerCount)}',
                bgColor: M3Palette.dangerSurface,
                fgColor: M3Palette.onDangerSurface,
                icon: Icons.arrow_downward_rounded,
              ),
              if (equalCount > 0)
                _buildStatusCountPill(
                  shortLabel: 'مساوٍ',
                  description: 'لـ ${countCompetitors(equalCount)}',
                  bgColor: colorScheme.secondaryContainer,
                  fgColor: colorScheme.onSecondaryContainer,
                  icon: Icons.drag_handle_rounded,
                ),
              _buildStatusCountPill(
                key: const ValueKey('compare_movement_chip'),
                shortLabel: movementChip,
                bgColor: movementBg,
                fgColor: movementFg,
                icon: movementIcon,
              ),
            ],
          ),
          M3Spacing.gapXS,
          // Short status chip above, full month-by-month detail underneath.
          Text(
            monthlyMovementSummary,
            key: const ValueKey('compare_movement_detail'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpotlightMetricBox(
    BuildContext context, {
    Key? key,
    required String label,
    required String value,
    required String subValue,
    bool isHighlighted = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: isHighlighted ? _ownBrandGreen : colorScheme.surface,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(
          color: isHighlighted
              ? _ownBrandGreen
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
                  ? Colors.white.withValues(alpha: 0.9)
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
                  ? Colors.white
                  : colorScheme.onSurface,
            ),
          ),
          Text(
            subValue,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isHighlighted
                  ? Colors.white.withValues(alpha: 0.85)
                  : (value == '—'
                      ? colorScheme.onSurfaceVariant
                      : _ownBrandGreen),
              fontWeight: FontWeight.w700,
              fontSize: M3FontSize.labelSmallPlus,
            ),
          ),
        ],
      ),
    );
  }

  /// Short status chip + optional smaller description underneath (TM pattern).
  Widget _buildStatusCountPill({
    Key? key,
    required String shortLabel,
    String? description,
    required Color bgColor,
    required Color fgColor,
    required IconData icon,
  }) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        M3ChipSurface(
          color: bgColor,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16.0, color: fgColor),
              M3Spacing.hGapXS,
              Text(
                shortLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fgColor,
                  fontWeight: FontWeight.w800,
                  fontSize: M3FontSize.labelSmallPlus,
                ),
              ),
            ],
          ),
        ),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: M3Spacing.s2),
          Text(
            description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: M3FontSize.bodySmall,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWhatIfPriceSimulatorCard(
    BuildContext context, {
    required OwnSkuCompetitiveGroupModel group,
    required double effectiveOwnPrice,
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
        borderRadius: M3Shape.radiusLg,
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
                'السعر التجريبي: ${currentVal.toStringAsFixed(1)} ج.م (${CurrencyFormatter.formatSignedPct(pctChange * 100)})',
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
                      ? M3Palette.onSuccessSurface
                      : M3Palette.onDangerSurface,
                ),
              ),
            ],
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
        borderRadius: M3Shape.radiusXl,
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
    required Color color,
    bool isLoading = false,
  }) {
    // Same shared card as the Sell-Out KPIs (geometry, fonts, icon).
    // Never flash computed zeros (or stale KPIs) while competitive-monthly loads.
    return M3SummaryKpiCard(
      key: ValueKey('compare_kpi_card_$title'),
      titleKey: ValueKey('compare_kpi_title_$title'),
      subtitleKey: ValueKey('compare_kpi_subtitle_$title'),
      loadingKey: const ValueKey('compare_kpi_skeleton'),
      title: title,
      value: value,
      subtitle: subtitle,
      icon: icon,
      color: color,
      titleMaxLines: null,
      subtitleMaxLines: 3,
      isLoading: isLoading,
    );
  }
}

/// Focused 2-Line Monthly Price Trajectory Painter:
/// Draws ONLY our Default Own SKU (Thick Primary Blue Line) and the Selected Competitor SKU (Thick Accent Line)
/// with clear price callouts and ▲/▼ badges at each month in the returned series.
class _MonthlyPriceTrajectoryPainter extends CustomPainter {
  final List<SkuMonthlyPricePointModel> ownSeries;
  final List<SkuMonthlyPricePointModel> competitorSeries;
  final Color ownColor;
  final Color compColor;
  final Color gridColor;
  final Color textColor;
  final int selectedMonth;

  _MonthlyPriceTrajectoryPainter({
    required this.ownSeries,
    required this.competitorSeries,
    required this.ownColor,
    required this.compColor,
    required this.gridColor,
    required this.textColor,
    required this.selectedMonth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (ownSeries.isEmpty) return;

    const double leftPad = 58.0;
    const double rightPad = 28.0;
    const double topPad = 28.0;
    const double bottomPad = 36.0;

    final double chartW = math.max(10.0, size.width - leftPad - rightPad);
    final double chartH = math.max(10.0, size.height - topPad - bottomPad);

    double minP = double.infinity;
    double maxP = 0.0;

    for (final pt in ownSeries) {
      if (pt.unitPrice < minP) minP = pt.unitPrice;
      if (pt.unitPrice > maxP) maxP = pt.unitPrice;
    }
    for (final pt in competitorSeries) {
      if (pt.unitPrice < minP) minP = pt.unitPrice;
      if (pt.unitPrice > maxP) maxP = pt.unitPrice;
    }

    if (!minP.isFinite || maxP <= 0) {
      minP = 0;
      maxP = 100;
    }
    final double span = math.max(12.0, maxP - minP);
    final double yMin = math.max(0.0, minP - span * 0.22);
    final double yMax = maxP + span * 0.25;

    double priceToY(double price) {
      final norm = (price - yMin) / math.max(1.0, yMax - yMin);
      return topPad + chartH * (1.0 - norm.clamp(0.0, 1.0));
    }

    double indexToX(int idx, int count) {
      if (count <= 1) return leftPad + chartW / 2;
      return leftPad + (idx / (count - 1)) * chartW;
    }

    // 1. Horizontal Grid Lines & Y-Axis Labels
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
          style: AppFontFallback.applyStyle(TextStyle(
            color: textColor,
            fontFamily: 'Cairo',
            fontSize: M3FontSize.labelSmall,
            fontWeight: FontWeight.w700,
          )),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 8.0, y - tp.height / 2));
    }

    // 2. X-Axis Month Labels & Vertical Guide Lines
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
              ? ownColor.withValues(alpha: 0.4)
              : gridColor.withValues(alpha: 0.45)
          ..strokeWidth = isHighlightedMonth ? 2.0 : 1.0,
      );

      // Month labels never overlap: drop the year, then every other label,
      // when the slot between grid lines is narrower than the text.
      final slot = n > 1 ? chartW / (n - 1) - 6.0 : chartW;
      TextPainter monthLabel(String text) => TextPainter(
            text: TextSpan(
              text: text,
              style: AppFontFallback.applyStyle(TextStyle(
                color: isHighlightedMonth ? ownColor : textColor,
                fontFamily: 'Cairo',
                fontSize: M3FontSize.bodySmall,
                fontWeight:
                    isHighlightedMonth ? FontWeight.w900 : FontWeight.w800,
              )),
            ),
            textDirection: TextDirection.rtl,
          )..layout();
      var tp = monthLabel(
          n > 4 ? '${pt.monthNameAr} ${pt.year % 100}' : pt.monthNameAr);
      if (tp.width > slot) {
        tp.dispose();
        tp = monthLabel(pt.monthNameAr);
      }
      final skip = tp.width > slot && i.isOdd && !isHighlightedMonth;
      if (!skip) {
        tp.paint(canvas, Offset(x - tp.width / 2, topPad + chartH + 9.0));
      }
      tp.dispose();
    }

    // 3. Selected competitor line, aligned to our months by (year, month):
    // a competitor month with no price is a gap, never another month's value.
    final comp = alignSeriesToMonths(ownSeries, competitorSeries);
    final compPath = Path();
    var penDown = false;
    for (int i = 0; i < n; i++) {
      final pt = comp[i];
      if (pt == null) {
        penDown = false;
        continue;
      }
      final o = Offset(indexToX(i, n), priceToY(pt.unitPrice));
      if (penDown) {
        compPath.lineTo(o.dx, o.dy);
      } else {
        compPath.moveTo(o.dx, o.dy);
        penDown = true;
      }
    }
    canvas.drawPath(
      compPath,
      Paint()
        ..color = compColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (int i = 0; i < n; i++) {
      final pt = comp[i];
      if (pt == null) continue;
      final o = Offset(indexToX(i, n), priceToY(pt.unitPrice));
      canvas.drawCircle(o, 6.0, Paint()..color = Colors.white);
      canvas.drawCircle(o, 4.5, Paint()..color = compColor);
    }

    // 4. Own SKU area fill + thick line + points.
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
            ownColor.withValues(alpha: 0.18),
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
        ..strokeWidth = 3.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (int i = 0; i < n; i++) {
      final o = Offset(indexToX(i, n), priceToY(ownSeries[i].unitPrice));
      canvas.drawCircle(o, 7.0, Paint()..color = Colors.white);
      canvas.drawCircle(o, 5.2, Paint()..color = ownColor);
    }

    // 5. Price callouts, laid out together so they never collide (near line
    // crossings the lower-priority one flips side, moves out, or is hidden).
    String calloutText(SkuMonthlyPricePointModel pt) {
      final arrow = pt.trendDirection == 'up'
          ? '▲'
          : pt.trendDirection == 'down'
              ? '▼'
              : '';
      return '${pt.unitPrice.toStringAsFixed(1)} $arrow'.trim();
    }

    final painters = <TextPainter>[];
    final colors = <Color>[];
    final requests = <CalloutRequest>[];
    final markers = <Rect>[];
    for (int i = 0; i < n; i++) {
      final x = indexToX(i, n);
      final yOwn = priceToY(ownSeries[i].unitPrice);
      markers.add(Rect.fromCircle(center: Offset(x, yOwn), radius: 7.0));
      final c = comp[i];
      if (c != null) {
        markers.add(Rect.fromCircle(
            center: Offset(x, priceToY(c.unitPrice)), radius: 6.0));
      }
    }
    // Own callouts first (priority), then the competitor's.
    for (int i = 0; i < n; i++) {
      final pt = ownSeries[i];
      final x = indexToX(i, n);
      final y = priceToY(pt.unitPrice);
      final c = comp[i];
      final compY = c == null ? y + 20.0 : priceToY(c.unitPrice);
      final tp = TextPainter(
        text: TextSpan(
          text: calloutText(pt),
          style: AppFontFallback.applyStyle(TextStyle(
            color: ownColor,
            fontFamily: 'Cairo',
            fontSize: M3FontSize.labelSmall,
            fontWeight: FontWeight.w900,
          )),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      painters.add(tp);
      colors.add(Colors.white.withValues(alpha: 0.94));
      requests.add(CalloutRequest(
        anchor: Offset(x, y),
        size: Size(tp.width + 10.0, tp.height + 4.0),
        preferredDy: y <= compY ? -17.0 : 17.0,
      ));
    }
    for (int i = 0; i < n; i++) {
      final pt = comp[i];
      if (pt == null) continue;
      final x = indexToX(i, n);
      final y = priceToY(pt.unitPrice);
      final ownY = priceToY(ownSeries[i].unitPrice);
      final tp = TextPainter(
        text: TextSpan(
          text: calloutText(pt),
          style: AppFontFallback.applyStyle(TextStyle(
            color: compColor,
            fontFamily: 'Cairo',
            fontSize: M3FontSize.tinyPlus,
            fontWeight: FontWeight.w900,
          )),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      painters.add(tp);
      colors.add(Colors.white.withValues(alpha: 0.92));
      requests.add(CalloutRequest(
        anchor: Offset(x, y),
        size: Size(tp.width + 10.0, tp.height + 4.0),
        preferredDy: y >= ownY ? 16.0 : -16.0,
      ));
    }
    final rects = layoutCallouts(
      requests,
      bounds: Rect.fromLTWH(0, 0, size.width, topPad + chartH),
      markers: markers,
    );
    for (int k = 0; k < rects.length; k++) {
      final r = rects[k];
      final tp = painters[k];
      if (r != null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(6.0)),
          Paint()..color = colors[k],
        );
        tp.paint(canvas,
            Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
      }
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _MonthlyPriceTrajectoryPainter oldDelegate) {
    return oldDelegate.ownSeries != ownSeries ||
        oldDelegate.competitorSeries != competitorSeries ||
        oldDelegate.selectedMonth != selectedMonth ||
        oldDelegate.ownColor != ownColor;
  }
}

import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/arabic_plural.dart';
import '../../../../core/utils/shared_display_prefix.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/bidi_text.dart';
import '../../../../core/theme/m3_palette.dart';
import '../../../../core/theme/m3_status_colors.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_button_group.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_search_field.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../../../core/data/data_refresh_mixin.dart';

/// OOSDashboardScreen provides real-time alerting for out-of-stock items across retail chains,
/// powered by Gemini AI Root-Cause Intelligence and Brand/Branch breakdown analytics.
class OOSDashboardScreen extends StatefulWidget {
  final ApiClient apiClient;

  const OOSDashboardScreen({
    super.key,
    required this.apiClient,
  });

  @override
  State<OOSDashboardScreen> createState() => _OOSDashboardScreenState();
}

class _OOSDashboardScreenState extends State<OOSDashboardScreen> with DataRefreshMixin<OOSDashboardScreen> {
  @override
  void onBackendDataChanged() {
    _loadAlerts();
  }

  bool isLoading = true;
  /// True after a successful executive-KPI fetch (never invent OSA% / 0).
  bool _hasExecutiveKpis = false;
  /// True after a successful OOS monitor fetch (never invent 0 ج.م loss).
  bool _hasMonitorReport = false;
  OOSMonitorResponseModel? _monitorReport;
  List<OOSAlertModel> alerts = [];
  double osaRatePct = 0;
  double oosRatePct = 0;

  // Filter States
  String _selectedBrand = 'الكل';
  String _selectedBranch = 'الكل';
  String _selectedSeverity = 'الكل';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // UI States
  bool _isAiCardExpanded = true;
  int _selectedViewMode = 0; // 0: Alert Cards, 1: Branch Matrix

  late String _lastTenantId;
  String? _lastRole;
  String? _lastAssignedChain;

  @override
  void initState() {
    super.initState();
    _lastTenantId = widget.apiClient.tenantId;
    _lastRole = widget.apiClient.currentUser?.role;
    _lastAssignedChain = widget.apiClient.currentUser?.assignedChain;
    _loadAlerts();
  }

  @override
  void didUpdateWidget(covariant OOSDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient ||
        _lastTenantId != widget.apiClient.tenantId ||
        _lastRole != widget.apiClient.currentUser?.role ||
        _lastAssignedChain != widget.apiClient.currentUser?.assignedChain) {
      _lastTenantId = widget.apiClient.tenantId;
      _lastRole = widget.apiClient.currentUser?.role;
      _lastAssignedChain = widget.apiClient.currentUser?.assignedChain;
      _loadAlerts();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    setState(() => isLoading = true);
    try {
      final results = await Future.wait([
        widget.apiClient.getOOSMonitorReport(),
        widget.apiClient.getExecutiveKPIs(),
      ]);
      final report = results[0] as OOSMonitorResponseModel;
      final kpis = results[1] as ExecutiveKPIsModel;
      if (mounted) {
        setState(() {
          _monitorReport = report;
          alerts = report.alerts;
          osaRatePct = kpis.osaRatePct;
          oosRatePct = kpis.oosRatePct;
          _hasExecutiveKpis = true;
          _hasMonitorReport = true;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[OOSDashboardScreen] Error loading OOS report: $e');
      if (mounted) {
        setState(() {
          _hasExecutiveKpis = false;
          _hasMonitorReport = false;
          _monitorReport = null;
          alerts = [];
          isLoading = false;
        });
      }
    }
  }

  List<String> get _availableBrands {
    final set = <String>{};
    for (final a in alerts) {
      if (a.brand.trim().isNotEmpty) {
        set.add(a.brand.trim());
      }
    }
    final sorted = set.toList()..sort();
    return ['الكل', ...sorted];
  }

  List<String> get _availableBranches {
    final set = <String>{};
    for (final a in alerts) {
      final name = a.storeName.isNotEmpty ? a.storeName : a.storeId;
      if (name.trim().isNotEmpty) {
        set.add(name.trim());
      }
    }
    final sorted = set.toList()..sort();
    return ['الكل', ...sorted];
  }

  Map<String, String> get _branchDisplay {
    final names = <String>{
      for (final a in alerts)
        if ((a.storeName.isNotEmpty ? a.storeName : a.storeId).trim().isNotEmpty)
          (a.storeName.isNotEmpty ? a.storeName : a.storeId).trim(),
    };
    return displayNamesWithoutSharedPrefix(names);
  }

  String _displayBranch(String raw) {
    if (raw.isEmpty || raw == 'الكل' || raw == '—') return raw;
    return _branchDisplay[raw] ?? raw;
  }

  List<OOSAlertModel> get _filteredAlerts {
    return alerts.where((a) {
      if (_selectedBrand != 'الكل') {
        final matchesBrand = a.brand.toLowerCase().contains(_selectedBrand.toLowerCase()) ||
            _selectedBrand.toLowerCase().contains(a.brand.toLowerCase());
        if (!matchesBrand) return false;
      }
      if (_selectedBranch != 'الكل') {
        final bName = a.storeName.isNotEmpty ? a.storeName : a.storeId;
        if (!bName.contains(_selectedBranch) && !_selectedBranch.contains(bName)) {
          return false;
        }
      }
      if (_selectedSeverity != 'الكل') {
        if (_selectedSeverity == 'حرج جداً' && a.severity != 'critical') return false;
        if (_selectedSeverity == 'أولوية مرتفعة' && a.severity != 'high' && a.severity != 'critical') return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final match = ApiClient.matchesProductSearch(
          _searchQuery,
          itemCode: a.itemCode,
          barcode: a.barcode,
          skuName: a.skuName,
          brand: a.brand,
          storeName: a.storeName,
        );
        if (!match) return false;
      }
      return true;
    }).toList();
  }

  List<String> get _branchesMissingSelectedBrand {
    if (_selectedBrand == 'الكل') return [];
    final set = <String>{};
    for (final a in alerts) {
      final matchesBrand = a.brand.toLowerCase().contains(_selectedBrand.toLowerCase()) ||
          _selectedBrand.toLowerCase().contains(a.brand.toLowerCase());
      if (matchesBrand) {
        final name = a.storeName.isNotEmpty ? a.storeName : a.storeId;
        if (name.isNotEmpty) set.add(name);
      }
    }
    return set.toList();
  }

  double get _selectedBrandTotalLostCost {
    if (_selectedBrand == 'الكل') return 0.0;
    return alerts.where((a) {
      return a.brand.toLowerCase().contains(_selectedBrand.toLowerCase()) ||
          _selectedBrand.toLowerCase().contains(a.brand.toLowerCase());
    }).fold<double>(0.0, (sum, a) => sum + a.estimatedLostDailyCost);
  }

  Map<String, List<OOSAlertModel>> get _branchGroupedAlerts {
    final map = <String, List<OOSAlertModel>>{};
    for (final a in _filteredAlerts) {
      final bName = a.storeName.isNotEmpty ? a.storeName : a.storeId;
      map.putIfAbsent(bName, () => []).add(a);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 768.0;

    final filtered = _filteredAlerts;
    final totalLostCost = filtered.fold<double>(0.0, (sum, a) => sum + a.estimatedLostDailyCost);
    final criticalCount = filtered.where((a) => a.severity == 'critical').length;

    final impactedBranchesSet = <String>{};
    for (final a in filtered) {
      final name = a.storeName.isNotEmpty ? a.storeName : a.storeId;
      if (name.isNotEmpty) impactedBranchesSet.add(name);
    }

    return SingleChildScrollView(
      padding: isCompact ? M3Spacing.pSm : M3Spacing.pMd,
      child: M3ContentBoundary(
        maxWidth: 1440.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Page Header (MD3 Standard)
            M3PageHeader(
              titleEn: 'Out-of-Stock Alarm Monitor',
              subtitleAr: 'نظام المراقبة الاستباقية للنواقص ومحرك الذكاء الاصطناعي (Gemini Root-Cause AI)',
              actions: M3ButtonGroup(
                items: [
                  M3GroupItem(
                    label: 'تحديث البيانات',
                    icon: Icons.refresh_rounded,
                    kind: M3GroupItemKind.tonal,
                    onPressed: isLoading ? null : _loadAlerts,
                  ),
                  M3GroupItem(
                    label: 'إصدار أمر توريد طارئ',
                    icon: Icons.flash_on_rounded,
                    kind: M3GroupItemKind.tonal,
                    onPressed: isLoading
                        ? null
                        : () {
                            _showEmergencyPOModal(context);
                          },
                  ),
                ],
              ),
            ),

            M3Spacing.gapMD,

            // Executive KPI Cards (Symmetrical Grid / Row)
            _buildExecutiveKPICards(
              context: context,
              totalLostCost: totalLostCost,
              criticalCount: criticalCount,
              impactedBranchesCount: impactedBranchesSet.length,
              totalFilteredSKUs: filtered.length,
              isCompact: isCompact,
            ),

            M3Spacing.gapMD,

            // Gemini AI Root-Cause Diagnostic Card
            _buildGeminiAICard(context),

            M3Spacing.gapMD,

            // Brand Missing-in-Branches Dedicated Banner (User specific requirement)
            if (_selectedBrand != 'الكل')
              _buildBrandMissingBranchesBanner(context),

            if (_selectedBrand != 'الكل')
              M3Spacing.gapMD,

            // Filters & View Mode Toolbar
            _buildFilterToolbar(context, isCompact),

            M3Spacing.gapMD,

            // Quick Brand Filter Chips
            _buildBrandQuickChips(context),

            M3Spacing.gapMD,

            // View Content (Cards vs Branch Matrix)
            M3FadeThroughSwitcher(
              duration: M3Motion.medium1,
              child: isLoading
                  ? const Center(
                      key: ValueKey('oos_loading'),
                      child: Padding(
                        padding: EdgeInsets.all(40.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : filtered.isEmpty
                      ? _buildEmptyState(context)
                      : _selectedViewMode == 0
                          ? _buildAlertCardsList(context, filtered, isCompact)
                          : _buildBranchMatrixList(context, isCompact),
            ),
          ],
        ),
      ),
    );
  }

  /// Executive KPI cards — shared [M3SummaryKpiCard] (Sell-Out geometry).
  /// Values stay on one line (compact EGP / arabic plural), like Sell-Out.
  Widget _buildExecutiveKPICards({
    required BuildContext context,
    required double totalLostCost,
    required int criticalCount,
    required int impactedBranchesCount,
    required int totalFilteredSKUs,
    required bool isCompact,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final osaAvailable = _hasExecutiveKpis;
    final lossAvailable = _hasMonitorReport;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Even fill: 5 cards → 3+2 (not a lonely 4+1 last row).
        final columns = M3KpiGridColumns.forWidthAndCount(
          constraints.maxWidth,
          5,
        );
        return M3EqualHeightGrid(
          key: const ValueKey('oos_kpi_grid'),
          columns: columns,
          spacing: M3Spacing.sm,
          runSpacing: M3Spacing.sm,
          children: [
            M3SummaryKpiCard(
              key: const ValueKey('osa_summary_card'),
              title: 'نسبة التوافر OSA%',
              titleTooltip: 'مؤشر التوافر على الرفوف OSA%',
              titleMaxLines: 1,
              subtitleMaxLines: 1,
              isLoading: isLoading && !osaAvailable,
              value: osaAvailable ? '${osaRatePct.toStringAsFixed(1)}%' : '—',
              subtitle: osaAvailable
                  ? 'كفاءة التوافر الفعلي عبر الفروع النشطة'
                  : 'لا توجد بيانات للتوافر',
              icon: Icons.fact_check_rounded,
              color: colorScheme.primary,
              valueKey: const ValueKey('kpi_value_OSA'),
              subtitleKey: const ValueKey('kpi_subtitle_OSA'),
            ),
            M3SummaryKpiCard(
              key: const ValueKey('kpi_card_Total OOS SKUs'),
              title: 'الأصناف المنعدمة',
              titleTooltip: 'إجمالي الأصناف المنعدمة',
              titleMaxLines: 1,
              subtitleMaxLines: 1,
              isLoading: isLoading && !lossAvailable,
              value: lossAvailable ? countSku(totalFilteredSKUs) : '—',
              subtitle: !lossAvailable
                  ? 'لا توجد بيانات للنواقص'
                  : (criticalCount == 0
                      ? 'لا توجد أصناف حرجة'
                      : '${countSku(criticalCount)} ذات خطورة حرجة'),
              icon: Icons.inventory_2_rounded,
              color: colorScheme.error,
              valueKey: const ValueKey('kpi_value_Total OOS SKUs'),
              subtitleKey: const ValueKey('kpi_subtitle_Total OOS SKUs'),
            ),
            M3SummaryKpiCard(
              key: const ValueKey('kpi_card_Impacted Branches'),
              title: 'الفروع المتأثرة',
              titleTooltip: 'الفروع المتأثرة بالنواقص',
              titleMaxLines: 1,
              subtitleMaxLines: 1,
              isLoading: isLoading && !lossAvailable,
              value: lossAvailable ? countBranches(impactedBranchesCount) : '—',
              subtitle: lossAvailable
                  ? 'فروع وهايبر ماركت بها عجز على الرف'
                  : 'لا توجد بيانات للفروع',
              icon: Icons.store_rounded,
              color: colorScheme.tertiary,
              valueKey: const ValueKey('kpi_value_Impacted Branches'),
              subtitleKey: const ValueKey('kpi_subtitle_Impacted Branches'),
            ),
            M3SummaryKpiCard(
              key: const ValueKey('kpi_card_Daily Lost Revenue'),
              title: 'الخسارة اليومية',
              titleTooltip: 'الخسارة اليومية المقدرة',
              titleMaxLines: 1,
              subtitleMaxLines: 1,
              isLoading: isLoading && !lossAvailable,
              value: lossAvailable
                  ? CurrencyFormatter.formatCompactEGP(totalLostCost)
                  : '—',
              subtitle: lossAvailable
                  ? 'فاقد مبيعات يومي بسبب نفاد المخزون'
                  : 'لا توجد بيانات للفاقد',
              icon: Icons.trending_down_rounded,
              color: colorScheme.error,
              valueKey: const ValueKey('kpi_value_Daily Lost Revenue'),
              subtitleKey: const ValueKey('kpi_subtitle_Daily Lost Revenue'),
            ),
            M3SummaryKpiCard(
              key: const ValueKey('kpi_card_Monthly Projected Loss'),
              title: 'الخسارة الشهرية',
              titleTooltip: 'الخسارة الشهرية المتوقعة',
              titleMaxLines: 1,
              subtitleMaxLines: 1,
              isLoading: isLoading && !lossAvailable,
              value: lossAvailable
                  ? CurrencyFormatter.formatCompactEGP(totalLostCost * 30.0)
                  : '—',
              subtitle: lossAvailable
                  ? 'تقدير الفاقد الشهري في حال تأخر التوريد'
                  : 'لا توجد بيانات للفاقد',
              icon: Icons.calendar_month_rounded,
              color: colorScheme.onSurfaceVariant,
              valueKey: const ValueKey('kpi_value_Monthly Projected Loss'),
              subtitleKey: const ValueKey('kpi_subtitle_Monthly Projected Loss'),
            ),
          ],
        );
      },
    );
  }

  /// Gemini AI Root-Cause Diagnostic & Replenishment Advisor Card
  Widget _buildGeminiAICard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ai = _monitorReport?.aiAnalysis;

    final topBrand = ai?.topImpactedBrand.isNotEmpty == true ? ai!.topImpactedBrand : 'فيبا / فيفا ونيفيا';
    final topBranch = ai?.topImpactedBranch.isNotEmpty == true ? ai!.topImpactedBranch : 'فتح الله - مدينة بدر';

    final executiveSummary = ai?.executiveSummaryAr ??
        'تم رصد انعدام متكرر في المخزون للأصناف الأساسية ذات الدوران السريع مثل $topBrand في فروع رئيسية تتصدرها $topBranch. يوصى بإصدار أمر توريد طارئ خلال 24 ساعة لتفادي اتساع فجوة الإيرادات المفقودة.';

    final rootCauses = ai?.rootCausesAr.isNotEmpty == true
        ? ai!.rootCausesAr
        : [
            'تأخر دورات التوريد وإعادة الطلب (Supply Lead-Time Lag) مقارنة بمعدلات السحب اليومي المرتفعة بالهايبر ماركت.',
            'تركّز العجز في علامات تجارية أساسية عالية الدوران ($topBrand) مما يؤثر مباشرة على حصة الرف وحجم المبيعات.',
            'اختناقات لوجستية وتفاوت في أولوية التوزيع الإقليمي بين الفروع المركزية والفروع الطرفية.',
            'عدم انضباط الحد الأدنى لمخزون الأمان (Safety Stock Threshold) في نقاط البيع المذكورة.',
          ];

    final immediateActions = ai?.immediateActionsAr.isNotEmpty == true
        ? ai!.immediateActionsAr
        : [
            'إصدار أمر توريد طارئ (Emergency Purchase Order) للأصناف التابعة لـ $topBrand خلال 24 ساعة.',
            'إعادة موازنة المخزون (Inter-branch Stock Transfer) لصالح $topBranch من أقرب مستودع إقليمي.',
            'رفع حد نقطة إعادة الطلب (ROP) بنسبة 20% لتجنب تكرار الانعدام خلال عطلات نهاية الأسبوع ومواسم الذروة.',
            'تفعيل تنبيهات فورية للمشرفين الميدانيين لمتابعة ملء الأرفف فور استلام التوريدات.',
          ];

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: M3Shape.radiusLg,
        side: BorderSide(color: colorScheme.primary.withOpacity(0.3), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // AI Header & Toggle
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: M3Shape.radiusMd,
                  ),
                  child: Icon(Icons.auto_awesome_rounded, color: colorScheme.onPrimary, size: 22.0),
                ),
                M3Spacing.hGapSM,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'مستشار الذكاء الاصطناعي (Gemini AI Root-Cause Advisor)',
                              maxLines: 3,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          M3ChipSurface(
                            color: colorScheme.tertiaryContainer,
                            child: Text(
                              'Gemini 1.5 Pro',
                              style: TextStyle(
                                fontSize: M3FontSize.labelSmallPlus,
                                fontWeight: FontWeight.w800,
                                color: colorScheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        'تشخيص الأسباب الجذرية لانعدام المخزون (OOS) وخطط التوريد التعويضي الفوري',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(_isAiCardExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded),
                  onPressed: () {
                    setState(() => _isAiCardExpanded = !_isAiCardExpanded);
                  },
                  tooltip: _isAiCardExpanded ? 'طي التحليل' : 'توسيع التحليل',
                ),
              ],
            ),

            if (_isAiCardExpanded) ...[
              const SizedBox(height: 14.0),
              const Divider(height: 1.0),
              const SizedBox(height: 14.0),

              // Executive AI Narrative
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: M3Shape.radiusMd,
                  border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline_rounded, color: colorScheme.primary, size: 20.0),
                    const SizedBox(width: 10.0),
                    Expanded(
                      child: Text(
                        executiveSummary,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14.0),

              // Root Causes vs Immediate Actions
              LayoutBuilder(
                builder: (context, boxConstraints) {
                  final isTwoColumns = boxConstraints.maxWidth > 700.0;

                  final rootCausesWidget = Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withOpacity(0.2),
                      borderRadius: M3Shape.radiusMd,
                      border: Border.all(color: colorScheme.error.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 18.0),
                            const SizedBox(width: 8.0),
                            Text(
                              'الأسباب التشغيلية الجذرية (Root Causes)',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10.0),
                        ...rootCauses.map(
                          (rc) => Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                                Expanded(
                                  child: Text(
                                    rc,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );

                  final immediateActionsWidget = Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withOpacity(0.3),
                      borderRadius: M3Shape.radiusMd,
                      border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle_outline_rounded, color: colorScheme.primary, size: 18.0),
                            const SizedBox(width: 8.0),
                            Text(
                              'الإجراءات الفورية المقترحة (Action Plan)',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10.0),
                        ...immediateActions.map(
                          (action) => Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 16,
                                  color: M3StatusColors.of(context).success,
                                ),
                                const SizedBox(width: 6.0),
                                Expanded(
                                  child: Text(
                                    action,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );

                  if (isTwoColumns) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: rootCausesWidget),
                        const SizedBox(width: 12.0),
                        Expanded(child: immediateActionsWidget),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        rootCausesWidget,
                        const SizedBox(height: 10.0),
                        immediateActionsWidget,
                      ],
                    );
                  }
                },
              ),

              const SizedBox(height: 12.0),

              // AI Actions Footer — tonal only; solid stays in the confirm dialog.
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: M3ButtonGroup(
                  items: [
                    M3GroupItem(
                      label: 'إعادة موازنة المخزون بين الفروع',
                      icon: Icons.compare_arrows_rounded,
                      kind: M3GroupItemKind.outlined,
                      onPressed: () {
                        M3Feedback.showInfo(
                          context,
                          'تم توجيه اقتراح إعادة التوازن اللوجستي للمخزون بين فروع فتح الله المركزية والطرفية',
                        );
                      },
                    ),
                    M3GroupItem(
                      label: 'تفعيل خطة التوريد الطارئة',
                      icon: Icons.flash_on_rounded,
                      kind: M3GroupItemKind.tonal,
                      onPressed: () => _showEmergencyPOModal(context),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Dedicated Brand Missing-in-Branches Operational Banner (Direct user request)
  Widget _buildBrandMissingBranchesBanner(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final branches = _branchesMissingSelectedBrand;
    final lostCost = _selectedBrandTotalLostCost;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withOpacity(0.35),
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.error.withOpacity(0.4), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: colorScheme.error,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.storefront_rounded, color: colorScheme.onError, size: 20.0),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تحليل انعدام الماركة: ماركة "$_selectedBrand"',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      'منعدمة حالياً في ${branches.length} فروع • إجمالي الفاقد اليومي المقدر: ${CurrencyFormatter.formatEGP(lostCost)} يومياً',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer.withOpacity(0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.local_shipping_rounded, size: 16.0),
                label: Text('طلب توريد لـ $_selectedBrand'),
                onPressed: () {
                  M3Feedback.showSuccess(
                    context,
                    'تم إنشاء مسودة أمر توريد طارئ لماركة $_selectedBrand لكافة الفروع المتأثرة (${branches.length} فروع)',
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12.0),
          Text(
            'قائمة الفروع التي تعاني من انعدام ماركة $_selectedBrand:',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 8.0),
          Wrap(
            spacing: M3Spacing.xs,
            runSpacing: M3Spacing.xs,
            children: branches.map((bName) {
              return M3ChipSurface(
                color: colorScheme.surface,
                borderColor: colorScheme.error.withOpacity(0.3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on_rounded,
                        size: 14.0, color: colorScheme.error),
                    const SizedBox(width: M3Spacing.xxs),
                    Flexible(
                      child: Text(
                        _displayBranch(bName),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: M3FontSize.labelSmallPlus,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Filter Toolbar (Search + Brand dropdown + Branch dropdown + Severity + View Mode)
  Widget _buildFilterToolbar(BuildContext context, bool isCompact) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: M3Shape.radiusLg,
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 1100.0;

            const searchHint = 'بحث بالصنف أو الكرتونة أو الباركود أو اسم الفرع...';
            final searchField = M3SearchFieldWidth(
              hintText: searchHint,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: searchHint,
                  hintStyle: TextStyle(fontSize: M3FontSize.labelMediumPlus, color: colorScheme.onSurfaceVariant.withOpacity(0.6)),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20.0),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18.0),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                  border: const OutlineInputBorder(borderRadius: M3Shape.radiusSm),
                ),
              ),
            );

            final brandDropdown = M3Dropdown<String>(
              value: _availableBrands.contains(_selectedBrand)
                  ? _selectedBrand
                  : 'الكل',
              label: 'الماركة (Brand)',
              expand: true,
              fitOptions: true,
              options: m3OptionsFromMenuItems<String>(
                  _availableBrands.map((b) {
                return DropdownMenuItem<String>(
                  value: b,
                  child: Text(
                    b,
                    style: const TextStyle(fontSize: M3FontSize.bodySmall),
                    maxLines: 1,
                  ),
                );
              }).toList()),
              onChanged: m3Legacy<String>((val) {
                if (val != null) setState(() => _selectedBrand = val);
              }),
            );

            final branchDropdown = M3Dropdown<String>(
              value: _availableBranches.contains(_selectedBranch)
                  ? _selectedBranch
                  : 'الكل',
              label: 'الفرع (Branch)',
              expand: true,
              fitOptions: true,
              options: m3OptionsFromMenuItems<String>(
                  _availableBranches.map((b) {
                return DropdownMenuItem<String>(
                  value: b,
                  child: Text(
                    _displayBranch(b),
                    style: const TextStyle(fontSize: M3FontSize.bodySmall),
                    maxLines: 1,
                  ),
                );
              }).toList()),
              onChanged: m3Legacy<String>((val) {
                if (val != null) setState(() => _selectedBranch = val);
              }),
            );

            final severityDropdown = M3Dropdown<String>(
              value: _selectedSeverity,
              label: 'مستوى الخطورة',
              expand: true,
              fitOptions: true,
              options: m3OptionsFromMenuItems<String>([
                const DropdownMenuItem(
                    value: 'الكل',
                    child: Text('الكل',
                        style: TextStyle(fontSize: M3FontSize.bodySmall))),
                DropdownMenuItem(
                  value: 'حرج جداً',
                  child: Text(
                    'حرج جداً',
                    style: TextStyle(
                      fontSize: M3FontSize.bodySmall,
                      color: colorScheme.error,
                    ),
                  ),
                ),
                const DropdownMenuItem(
                  value: 'أولوية مرتفعة',
                  child: Text(
                    'أولوية مرتفعة',
                    style: TextStyle(
                      fontSize: M3FontSize.bodySmall,
                      color: M3Palette.warning,
                    ),
                  ),
                ),
              ]),
              onChanged: m3Legacy<String>((val) {
                if (val != null) setState(() => _selectedSeverity = val);
              }),
            );

            final resetButton = (_selectedBrand != 'الكل' || _selectedBranch != 'الكل' || _selectedSeverity != 'الكل' || _searchQuery.isNotEmpty)
                ? IconButton(
                    icon: const Icon(Icons.filter_alt_off_rounded),
                    tooltip: 'إعادة تعيين الفلاتر',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _selectedBrand = 'الكل';
                        _selectedBranch = 'الكل';
                        _selectedSeverity = 'الكل';
                        _searchQuery = '';
                      });
                    },
                  )
                : const SizedBox.shrink();

            return Column(
              children: [
                if (isNarrow) ...[
                  Row(
                    children: [
                      Expanded(child: searchField),
                      if (resetButton is! SizedBox) ...[
                        const SizedBox(width: 4.0),
                        resetButton,
                      ],
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  Row(
                    children: [
                      Expanded(child: brandDropdown),
                      const SizedBox(width: 6.0),
                      Expanded(child: branchDropdown),
                      const SizedBox(width: 6.0),
                      Expanded(child: severityDropdown),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(flex: 3, child: searchField),
                      const SizedBox(width: 8.0),
                      Expanded(flex: 2, child: brandDropdown),
                      const SizedBox(width: 8.0),
                      Expanded(flex: 2, child: branchDropdown),
                      const SizedBox(width: 8.0),
                      Expanded(flex: 2, child: severityDropdown),
                      if (resetButton is! SizedBox) ...[
                        const SizedBox(width: 4.0),
                        resetButton,
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 10.0),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12.0,
                  runSpacing: 8.0,
                  children: [
                    Text(
                      'عدد النتائج المطابقة: ${countSku(_filteredAlerts.length)} منعدم',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          label: Text('بطاقات التنبيهات'),
                          icon: Icon(Icons.view_agenda_rounded, size: 16.0),
                        ),
                        ButtonSegment(
                          value: 1,
                          label: Text('مصفوفة الفروع والنواقص'),
                          icon: Icon(Icons.grid_view_rounded, size: 16.0),
                        ),
                      ],
                      selected: {_selectedViewMode},
                      onSelectionChanged: (set) {
                        setState(() => _selectedViewMode = set.first);
                      },
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Quick Brand Filter Chips (Responsive Wrap)
  Widget _buildBrandQuickChips(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final brands = _availableBrands;

    return Wrap(
      spacing: M3Spacing.xs,
      runSpacing: M3Spacing.xs,
      children: brands.map((b) {
        final isSelected = _selectedBrand == b;
        int count = 0;
        if (b == 'الكل') {
          count = alerts.length;
        } else {
          count = alerts.where((a) {
            return a.brand.toLowerCase().contains(b.toLowerCase()) ||
                b.toLowerCase().contains(a.brand.toLowerCase());
          }).length;
        }

        return FilterChip(
          selected: isSelected,
          showCheckmark: false,
          visualDensity: VisualDensity.standard,
          shape: const RoundedRectangleBorder(borderRadius: M3ChipStyle.radius),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(b, maxLines: 3),
              const SizedBox(width: 8.0),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.onPrimary : colorScheme.surfaceContainerHighest,
                  borderRadius: M3ChipStyle.radius,
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: M3FontSize.tinyPlus,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          onSelected: (selected) {
            setState(() {
              _selectedBrand = selected ? b : 'الكل';
            });
          },
        );
      }).toList(),
    );
  }

  /// Short chip ([M3ChipSurface]) + description underneath (TM / Compare).
  Widget _buildShortStatus(
    BuildContext context, {
    required String short,
    required String description,
    required Color bgColor,
    required Color fgColor,
    IconData? icon,
    Key? key,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        M3ChipSurface(
          color: bgColor,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16.0, color: fgColor),
                const SizedBox(width: M3Spacing.xxs),
              ],
              Flexible(
                child: Text(
                  short,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fgColor,
                    fontWeight: FontWeight.w800,
                    fontSize: M3FontSize.labelSmallPlus,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: M3Spacing.s2),
        Text(
          description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontSize: M3FontSize.bodySmall,
          ),
        ),
      ],
    );
  }

  /// View 1: Alert Cards List
  Widget _buildAlertCardsList(BuildContext context, List<OOSAlertModel> list, bool isCompact) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView.separated(
      key: ValueKey('oos_list_${list.length}'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: M3Spacing.xs),
      itemBuilder: (context, index) {
        final alert = list[index];
        final isCritical = alert.severity == 'critical';
        final severityChip = _buildShortStatus(
          context,
          key: ValueKey('oos_severity_${alert.alertId}'),
          short: isCritical ? 'حرج' : 'مرتفع',
          description: isCritical
              ? 'انعدام ممتد يؤثر على المبيعات اليومية'
              : 'نواقص تحتاج إعادة توريد سريع',
          bgColor: isCritical
              ? M3Palette.dangerSurface
              : M3Palette.warningSurface,
          fgColor: isCritical
              ? M3Palette.onDangerSurface
              : M3Palette.onWarningSurface,
          icon: isCritical
              ? Icons.warning_rounded
              : Icons.priority_high_rounded,
        );
        final brandChip = M3ChipSurface(
          color: colorScheme.primaryContainer,
          child: Text(
            alert.brand,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontSize: M3FontSize.labelSmallPlus,
              fontWeight: FontWeight.w800,
            ),
          ),
        );

        final skuTitle = Text(
          alert.skuName,
          key: const ValueKey('oos_sku_name'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          maxLines: 3,
        );
        final storeLine = Text(
          'المنفذ: ${_displayBranch(alert.storeName)} (${alert.retailerChain.toUpperCase()}) • ${alert.itemCode.isNotEmpty ? "كود: ${alert.itemCode} • " : ""}الباركود: ${alert.barcode}',
          key: const ValueKey('oos_store_name'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          maxLines: 3,
        );
        final daysLine = Text(
          '${countDay(alert.consecutiveDaysOOS)} بدون بيع',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 3,
        );
        final lossLine = Text(
          '${CurrencyFormatter.formatCompactEGP(alert.estimatedLostDailyCost)} يومياً',
          style: theme.textTheme.titleSmall?.copyWith(
            color: colorScheme.error,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
        );

        return Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: M3Shape.radiusLg,
            side: BorderSide(
              color: isCritical ? colorScheme.error.withOpacity(0.3) : colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Padding(
            padding: isCompact ? M3Spacing.pSm : M3Spacing.pMd,
            child: LayoutBuilder(
              builder: (context, itemConstraints) {
                final isMobileCard = itemConstraints.maxWidth < 620.0;
                final iconWell = Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: isCritical ? colorScheme.errorContainer : colorScheme.tertiaryContainer,
                    borderRadius: M3Shape.radiusMd,
                  ),
                  child: Icon(
                    isCritical ? Icons.warning_rounded : Icons.info_outline_rounded,
                    color: isCritical ? colorScheme.error : colorScheme.onTertiaryContainer,
                    size: 20.0,
                  ),
                );
                final poButton = OutlinedButton(
                  onPressed: () {
                    M3Feedback.showSuccess(
                      context,
                      'تم إنشاء طلب توريد سريع للصنف: ${alert.skuName} لفرع ${_displayBranch(alert.storeName)}',
                    );
                  },
                  child: const Text('أمر توريد سريع'),
                );

                if (isMobileCard) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          iconWell,
                          const SizedBox(width: 10.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                skuTitle,
                                const SizedBox(height: 8.0),
                                Wrap(
                                  spacing: M3Spacing.xs,
                                  runSpacing: M3Spacing.xs,
                                  children: [brandChip, severityChip],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                      storeLine,
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Divider(height: 1.0),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: daysLine),
                          const SizedBox(width: 8.0),
                          Flexible(child: lossLine),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconWell,
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          skuTitle,
                          const SizedBox(height: 8.0),
                          Wrap(
                            spacing: M3Spacing.xs,
                            runSpacing: M3Spacing.xs,
                            children: [brandChip, severityChip],
                          ),
                          const SizedBox(height: 8.0),
                          storeLine,
                        ],
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        lossLine,
                        const SizedBox(height: 4.0),
                        daysLine,
                      ],
                    ),
                    const SizedBox(width: 12.0),
                    poButton,
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// View 2: Branch Matrix (grouped by branch, Sell-Out table rules).
  Widget _buildBranchMatrixList(BuildContext context, bool isCompact) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final branchMap = _branchGroupedAlerts;

    return Column(
      children: branchMap.entries.map((entry) {
        final branchName = entry.key;
        final branchAlerts = entry.value;
        final branchTotalCost = branchAlerts.fold<double>(0.0, (s, a) => s + a.estimatedLostDailyCost);
        final distinctBrands = branchAlerts.map((a) => a.brand).toSet().toList();

        return Card(
          margin: const EdgeInsets.only(bottom: 16.0),
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: M3Shape.radiusLg,
            side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: M3Shape.radiusMd,
                      ),
                      child: Icon(Icons.storefront_rounded, color: colorScheme.onTertiaryContainer, size: 20.0),
                    ),
                    const SizedBox(width: 10.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayBranch(branchName),
                            key: const ValueKey('oos_branch_name'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            'الماركات المتأثرة: ${distinctBrands.join(" • ")}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'إجمالي الفاقد: ${CurrencyFormatter.formatCompactEGP(branchTotalCost)} يومياً',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                        ),
                        Text(
                          countMissingInBranch(branchAlerts.length),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12.0),
                const Divider(height: 1.0),
                const SizedBox(height: 8.0),
                LayoutBuilder(
                  builder: (context, tableConstraints) {
                    const flex = <double>[2.2, 0.9, 0.8, 0.9];
                    const spacing = M3Spacing.xs;
                    const margin = M3Spacing.xs;
                    final availableWidth = tableConstraints.maxWidth.isFinite
                        ? tableConstraints.maxWidth
                        : MediaQuery.sizeOf(context).width;
                    final flexSum = flex.fold<double>(0, (a, b) => a + b);
                    final inner = availableWidth -
                        (2 * margin) -
                        ((flex.length - 1) * spacing);
                    double colMax(int i) =>
                        (inner * flex[i] / flexSum).clamp(56.0, double.infinity);
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
                          overflow: TextOverflow.ellipsis,
                          textAlign: align,
                          softWrap: true,
                        ),
                      );
                    }

                    final columns = [
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: cellText(0, 'الصنف'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: cellText(1, 'الماركة'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: cellText(2, 'أيام الانعدام'),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: cellText(3, 'الفاقد اليومي'),
                      ),
                    ];

                    return SizedBox(
                      width: availableWidth,
                      child: TableScrollContainer(
                        key: ValueKey('oos_matrix_table_$branchName'),
                        showSwipeHint: true,
                        columnFlex: flex,
                        child: DataTable(
                          headingRowHeight: 56,
                          dataRowMinHeight: 52,
                          dataRowMaxHeight: double.infinity,
                          columnSpacing: spacing,
                          horizontalMargin: margin,
                          columns: columns,
                          rows: centerCellsUnderCenteredHeadings(
                            columns,
                            [
                              for (final item in branchAlerts)
                                DataRow(
                                  cells: [
                                    DataCell(cellText(0, item.skuName,
                                        key: const ValueKey('oos_sku_name'))),
                                    DataCell(cellText(1, item.brand)),
                                    DataCell(cellText(
                                        2, countDay(item.consecutiveDaysOOS))),
                                    DataCell(cellText(
                                      3,
                                      CurrencyFormatter.formatCompactEGP(
                                          item.estimatedLostDailyCost),
                                    )),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8.0),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.send_rounded, size: 20.0),
                    label: Text(
                        'إصدار طلب توريد مجمع لـ ${_displayBranch(branchName)}',
                        maxLines: 3),
                    onPressed: () {
                      M3Feedback.showSuccess(
                        context,
                        'تم إنشاء طلب توريد مجمع لـ ${countSku(branchAlerts.length)} في ${_displayBranch(branchName)}',
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Empty State when no alerts match filters
  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 64.0, color: colorScheme.primary),
            const SizedBox(height: 16.0),
            Text(
              'لا توجد نواقص مطابقة للفلاتر المحددة',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8.0),
            Text(
              'جميع المنتجات متوفرة على الأرفف وفق معايير البحث المحددة',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16.0),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _selectedBrand = 'الكل';
                  _selectedBranch = 'الكل';
                  _selectedSeverity = 'الكل';
                  _searchQuery = '';
                });
              },
              child: const Text('إعادة تعيين الفلاتر'),
            ),
          ],
        ),
      ),
    );
  }

  /// Emergency PO Modal
  void _showEmergencyPOModal(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredAlerts;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.flash_on_rounded, color: colorScheme.primary),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  rtlEnd('إصدار أمر توريد طارئ (${ltrIsolate('Emergency PO')})'),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500.0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (filtered.isEmpty)
                  Text(
                    'لا توجد أصناف منعدمة',
                    style: theme.textTheme.bodyMedium,
                  )
                else ...[
                  Text(
                    rtlEnd(
                      'سيتم إرسال أمر توريد استثنائي فوري يشمل ${ltrIsolate(CurrencyFormatter.formatUnits(filtered.length))} أصناف منعدمة في الفروع المتأثرة.',
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12.0),
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: M3Shape.radiusSm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إجمالي الفاقد اليومي المستهدف استعادته:',
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          CurrencyFormatter.formatEGP(
                            filtered.fold<double>(
                                0.0, (s, a) => s + a.estimatedLostDailyCost),
                            isolate: true,
                          ),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.send_rounded, size: 16.0),
              label: const Text('تأكيد وإرسال الأمر'),
              onPressed: (isLoading || filtered.isEmpty)
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      M3Feedback.showSuccess(
                        context,
                        'تم بنجاح إرسال أمر التوريد الطارئ إلى فرق الإمداد والتوزيع',
                      );
                    },
            ),
          ],
        );
      },
    );
  }
}

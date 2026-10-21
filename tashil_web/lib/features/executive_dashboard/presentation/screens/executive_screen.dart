import 'package:flutter/material.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/m3_button.dart';
import '../widgets/bento_kpi_grid.dart';
import '../widgets/chain_share_pie.dart';
import '../widgets/pareto_category_section.dart';
import '../widgets/sellout_trend_chart.dart';

/// ExecutiveScreen is the primary executive management overview.
class ExecutiveScreen extends StatefulWidget {
  final ApiClient apiClient;

  const ExecutiveScreen({
    super.key,
    required this.apiClient,
  });

  @override
  State<ExecutiveScreen> createState() => _ExecutiveScreenState();
}

class _ExecutiveScreenState extends State<ExecutiveScreen> {
  String selectedPeriod = 'YTD';
  int selectedYear = 2026;
  int selectedMonth = 0;
  String selectedChain = 'all';
  bool isLoading = true;
  ExecutiveKPIsModel? kpis;
  late String _lastTenantId;
  String? _lastRole;
  String? _lastAssignedChain;
  int _loadRequestId = 0;

  static const List<({int number, String shortName, String fullName})> _months = [
    (number: 0, shortName: 'All', fullName: 'All Months'),
    (number: 1, shortName: 'Jan', fullName: 'January'),
    (number: 2, shortName: 'Feb', fullName: 'February'),
    (number: 3, shortName: 'Mar', fullName: 'March'),
    (number: 4, shortName: 'Apr', fullName: 'April'),
    (number: 5, shortName: 'May', fullName: 'May'),
    (number: 6, shortName: 'Jun', fullName: 'June'),
    (number: 7, shortName: 'Jul', fullName: 'July'),
    (number: 8, shortName: 'Aug', fullName: 'August'),
    (number: 9, shortName: 'Sep', fullName: 'September'),
    (number: 10, shortName: 'Oct', fullName: 'October'),
    (number: 11, shortName: 'Nov', fullName: 'November'),
    (number: 12, shortName: 'Dec', fullName: 'December'),
  ];

  static const List<int> _years = [2026, 2025, 2024];

  List<({String code, String shortName, String fullName})> get _availableChains {
    final list = <({String code, String shortName, String fullName})>[
      (code: 'all', shortName: 'All', fullName: 'All Chains (كل السلاسل)'),
    ];

    final items = (kpis?.availableChains.isNotEmpty == true)
        ? kpis!.availableChains
        : (kpis?.chainShares ?? const <ChainShareItem>[]);

    final seen = <String>{};
    for (final item in items) {
      final code = item.retailerChain.trim().toLowerCase();
      if (code.isEmpty || code == 'all' || code == 'nda_redacted' || seen.contains(code)) {
        continue;
      }
      seen.add(code);

      final resolvedLabel = ChainSharePie.labelForChain(code);
      final fullName = (item.displayName.isNotEmpty &&
              item.displayName.toLowerCase() != code)
          ? item.displayName
          : resolvedLabel;

      String shortName;
      if (code == 'beet-elgomla' || code == 'beet_elgomla' || code == 'beet elgomla') {
        shortName = 'Beet El Gomla';
      } else if (code == 'gomla') {
        shortName = 'Gomla';
      } else if (code == 'fathalla') {
        shortName = 'Fathalla';
      } else if (code == 'carrefour') {
        shortName = 'Carrefour';
      } else if (code == 'spinneys') {
        shortName = 'Spinneys';
      } else if (code == 'metro') {
        shortName = 'Metro';
      } else if (code == 'seoudi') {
        shortName = 'Seoudi';
      } else if (code == 'kazyon') {
        shortName = 'Kazyon';
      } else {
        shortName = fullName.split('(').first.trim();
        if (shortName.isEmpty) shortName = code;
      }

      list.add((code: code, shortName: shortName, fullName: fullName));
    }

    return list;
  }

  @override
  void initState() {
    super.initState();
    _lastTenantId = widget.apiClient.tenantId;
    _lastRole = widget.apiClient.currentUser?.role;
    _lastAssignedChain = widget.apiClient.currentUser?.assignedChain;
    // Sync tenant custom retail chains in the background so custom display names are registered
    widget.apiClient.getRetailChains().then((_) {
      if (mounted) setState(() {});
    });
    _loadData();
  }

  @override
  void didUpdateWidget(covariant ExecutiveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient ||
        _lastTenantId != widget.apiClient.tenantId ||
        _lastRole != widget.apiClient.currentUser?.role ||
        _lastAssignedChain != widget.apiClient.currentUser?.assignedChain) {
      _lastTenantId = widget.apiClient.tenantId;
      _lastRole = widget.apiClient.currentUser?.role;
      _lastAssignedChain = widget.apiClient.currentUser?.assignedChain;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final requestId = ++_loadRequestId;
    String? startDate;
    String? endDate;
    if (selectedMonth == 0) {
      selectedPeriod = 'YTD';
      startDate = '$selectedYear-01-01';
      endDate = '$selectedYear-12-31';
    } else {
      selectedPeriod = 'MTD';
      final lastDay = DateTime(selectedYear, selectedMonth + 1, 0).day;
      final m = selectedMonth.toString().padLeft(2, '0');
      startDate = '$selectedYear-$m-01';
      endDate = '$selectedYear-$m-${lastDay.toString().padLeft(2, '0')}';
    }

    final effectiveChain = selectedChain == 'all' ? null : selectedChain;
    final cached = widget.apiClient.getCachedExecutiveKPIs(
      period: selectedPeriod,
      startDate: startDate,
      endDate: endDate,
      chain: effectiveChain,
    );
    if (cached != null) {
      setState(() {
        kpis = cached;
        isLoading = false;
      });
    } else if (kpis == null) {
      setState(() => isLoading = true);
    }

    final result = await widget.apiClient.getExecutiveKPIs(
      period: selectedPeriod,
      startDate: startDate,
      endDate: endDate,
      chain: effectiveChain,
    );
    if (mounted && requestId == _loadRequestId) {
      setState(() {
        kpis = result;
        isLoading = false;
        if (selectedChain != 'all') {
          final chains = _availableChains;
          if (chains.every((c) => c.code.toLowerCase() != selectedChain.toLowerCase())) {
            selectedChain = 'all';
          }
        }
      });
    }
  }

  Widget _buildChainDropdown(BuildContext context, {bool isCompact = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chains = _availableChains;
    final activeChain = chains.firstWhere(
      (c) => c.code.toLowerCase() == selectedChain.toLowerCase(),
      orElse: () => chains.first,
    );

    return PopupMenuButton<String>(
      key: const ValueKey('executive_chain_dropdown'),
      tooltip: 'Filter by Retail Chain',
      initialValue: selectedChain,
      position: PopupMenuPosition.under,
      popUpAnimationStyle: M3Motion.menuAnimationStyle,
      onSelected: (chainCode) {
        setState(() => selectedChain = chainCode);
        _loadData();
      },
      itemBuilder: (context) => chains.map((c) {
        final isSelected = c.code == selectedChain;
        final chainColor = c.code == 'all'
            ? colorScheme.primary
            : ChainSharePie.colorForChain(c.code);
        return PopupMenuItem<String>(
          value: c.code,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected)
                Icon(
                  Icons.check_rounded,
                  size: 18.0,
                  color: chainColor,
                )
              else
                Container(
                  width: 10.0,
                  height: 10.0,
                  margin: const EdgeInsets.symmetric(horizontal: 4.0),
                  decoration: BoxDecoration(
                    color: chainColor,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 10.0),
              Flexible(
                child: Text(
                  c.fullName,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? chainColor : colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        height: 38.0,
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 10.0 : 14.0),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20.0),
          border: Border.all(
            color: colorScheme.outlineVariant.withOpacity(0.8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_rounded, size: 15.0, color: colorScheme.primary),
            const SizedBox(width: 6.0),
            Text(
              'Chain: ${activeChain.shortName}',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4.0),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 16.0,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// Connected Year & Month Buttons Group on a single row
  Widget _buildYearMonthConnectedGroup(BuildContext context, {bool isCompact = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeMonth = _months.firstWhere(
      (m) => m.number == selectedMonth,
      orElse: () => _months.first,
    );

    return Container(
      height: 38.0,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Year Dropdown Button Segment
          PopupMenuButton<int>(
            key: const ValueKey('executive_year_dropdown'),
            tooltip: 'Select Year',
            initialValue: selectedYear,
            position: PopupMenuPosition.under,
            popUpAnimationStyle: M3Motion.menuAnimationStyle,
            onSelected: (year) {
              setState(() => selectedYear = year);
              _loadData();
            },
            itemBuilder: (context) => _years.map((y) {
              final isSelected = y == selectedYear;
              return PopupMenuItem<int>(
                value: y,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSelected)
                      Icon(
                        Icons.check_rounded,
                        size: 18.0,
                        color: colorScheme.primary,
                      )
                    else
                      const SizedBox(width: 18.0),
                    const SizedBox(width: 10.0),
                    Text(
                      y.toString(),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 8.0 : 12.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_rounded, size: 14.0, color: colorScheme.primary),
                  const SizedBox(width: 5.0),
                  Text(
                    'Year: $selectedYear',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 3.0),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 16.0,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Vertical divider separating Year and Month
          Container(
            height: 18.0,
            width: 1.0,
            color: colorScheme.outlineVariant.withOpacity(0.8),
          ),

          // Month Dropdown Button Segment
          PopupMenuButton<int>(
            key: const ValueKey('executive_month_dropdown'),
            tooltip: 'Select Month',
            initialValue: selectedMonth,
            constraints: const BoxConstraints(minWidth: 220.0),
            position: PopupMenuPosition.under,
            popUpAnimationStyle: M3Motion.menuAnimationStyle,
            onSelected: (month) {
              setState(() => selectedMonth = month);
              _loadData();
            },
            itemBuilder: (context) => _months.map((m) {
              final isSelected = m.number == selectedMonth;
              return PopupMenuItem<int>(
                value: m.number,
                child: SizedBox(
                  width: 210.0,
                  child: Row(
                    children: [
                      if (isSelected)
                        Icon(
                          Icons.check_rounded,
                          size: 18.0,
                          color: colorScheme.primary,
                        )
                      else
                        const SizedBox(width: 18.0),
                      const SizedBox(width: 10.0),
                      Expanded(
                        child: Text(
                          m.fullName,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 8.0 : 12.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month_rounded, size: 14.0, color: colorScheme.primary),
                  const SizedBox(width: 5.0),
                  Text(
                    'Month: ${activeMonth.shortName}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 3.0),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 16.0,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: isCompact ? M3Spacing.pSm : M3Spacing.pMd,
      child: M3ContentBoundary(
        maxWidth: 1440.0,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar: Unified M3 Left English Title + Right Arabic Subtitle + Filter Controls
            M3PageHeader(
              titleEn: 'Executive Dashboard',
              subtitleAr: 'مؤشرات الأداء المالي والبيعي الفوري لسلاسل التجزئة المصرية',
              actions: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildChainDropdown(context, isCompact: isCompact),
                    const SizedBox(width: 8.0),
                    _buildYearMonthConnectedGroup(context, isCompact: isCompact),
                  ],
                ),
              ),
            ),

            M3Spacing.gapMD,

            M3FadeThroughSwitcher(
              duration: M3Motion.medium2,
              child: isLoading
                  ? const Align(
                      alignment: Alignment.topCenter,
                      key: ValueKey('exec_loading_state'),
                      child: Padding(
                        padding: EdgeInsets.all(64.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : kpis != null
                      ? Column(
                          key: ValueKey(
                            'exec_kpis_${selectedPeriod}_${selectedYear}_${selectedMonth}_${selectedChain}_${kpis!.totalRevenue}',
                          ),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Bento KPI Grid
                            BentoKpiGrid(kpis: kpis!),

                            M3Spacing.gapMD,

                            // Charts Layout (Side by Side on desktop, stacked on mobile)
                            LayoutBuilder(
                              builder: (context, constraints) {
                                if (constraints.maxWidth >= 900) {
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 7,
                                        child: SelloutTrendChart(trends: kpis!.dailyTrends),
                                      ),
                                      M3Spacing.hGapSM,
                                      Expanded(
                                        flex: 5,
                                        child: ChainSharePie(chainShares: kpis!.chainShares),
                                      ),
                                    ],
                                  );
                                }

                                return Column(
                                  children: [
                                    SelloutTrendChart(trends: kpis!.dailyTrends),
                                    M3Spacing.gapSM,
                                    ChainSharePie(chainShares: kpis!.chainShares),
                                  ],
                                );
                              },
                            ),

                            M3Spacing.gapMD,

                            // Category Contribution, Market Share vs Competitors & Pareto 80/20 Power SKUs
                            ParetoCategorySection(
                              categories: kpis!.categoryContributions,
                              paretoSkus: kpis!.paretoSkus,
                              supplierShares: kpis!.supplierShares,
                              totalMarketRevenue: kpis!.totalMarketRevenue,
                              tenantMarketSharePct: kpis!.tenantMarketSharePct,
                              competitorsCount: kpis!.competitorsCount,
                            ),
                          ],
                        )
                      : const SizedBox.shrink(key: ValueKey('exec_empty_state')),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:tashil_web/core/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../data/executive_dashboard_repository.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/m3_button.dart';
import '../widgets/bento_kpi_grid.dart';
import '../widgets/chain_share_pie.dart';
import '../widgets/pareto_category_section.dart';
import '../widgets/sellout_trend_chart.dart';
import '../widgets/market_share_section.dart';
import '../../../cpfr_replenishment/domain/cpfr_models.dart';
import '../../../../core/data/data_refresh_mixin.dart';

/// ExecutiveScreen is the primary executive management overview.
class ExecutiveScreen extends StatefulWidget {
  final ApiClient apiClient;

  /// Optional injected repository (tests); defaults to one wrapping [apiClient].
  final ExecutiveDashboardRepository? repository;

  const ExecutiveScreen({
    super.key,
    required this.apiClient,
    this.repository,
  });

  @override
  State<ExecutiveScreen> createState() => _ExecutiveScreenState();
}

class _ExecutiveScreenState extends State<ExecutiveScreen> with DataRefreshMixin<ExecutiveScreen> {
  @override
  void onBackendDataChanged() {
    _loadData();
  }

  String selectedPeriod = 'YTD';
  int selectedYear = 2026;
  int selectedMonth = 0;
  String selectedChain = 'all';
  bool isLoading = true;
  String? loadError;
  /// Period granularity for the Market Share overview: monthly | quarterly | yearly.
  String _periodMode = 'yearly';
  int _selectedQuarter = 1;
  CPFRDashboardModel? _cpfr;
  bool _cpfrLoading = false;
  String? _cpfrError;
  int _cpfrRequestId = 0;
  ExecutiveKPIsModel? kpis;
  late String _lastTenantId;
  String? _lastRole;
  String? _lastAssignedChain;
  int _loadRequestId = 0;
  late ExecutiveDashboardRepository _repo;

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
    _repo = widget.repository ?? ExecutiveDashboardRepository(widget.apiClient);
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
      _repo = widget.repository ?? ExecutiveDashboardRepository(widget.apiClient);
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final requestId = ++_loadRequestId;
    String? startDate;
    String? endDate;
    if (_periodMode == 'quarterly') {
      // Explicit date range; 'MTD' only labels it (dates take precedence).
      selectedPeriod = 'MTD';
      final firstM = (_selectedQuarter - 1) * 3 + 1;
      final lastM = firstM + 2;
      final lastDay = DateTime(selectedYear, lastM + 1, 0).day;
      startDate = '$selectedYear-${firstM.toString().padLeft(2, '0')}-01';
      endDate = '$selectedYear-${lastM.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
    } else if (selectedMonth == 0) {
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
    _loadCpfr();
    final cached = _repo.peekFresh(
          period: selectedPeriod,
          startDate: startDate,
          endDate: endDate,
          chain: effectiveChain,
        ) ??
        _repo.peekStale(
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

    final loaded = await _repo.loadKpis(
      period: selectedPeriod,
      startDate: startDate,
      endDate: endDate,
      chain: effectiveChain,
    );
    if (!mounted || requestId != _loadRequestId) return;
    final error = loaded.errorOrNull;
    if (error != null) {
      setState(() {
        isLoading = false;
        loadError = error.toString();
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('تعذر تحميل مؤشرات الأداء: $error')),
      );
      return;
    }
    final result = loaded.valueOrNull!;
    setState(() {
      kpis = result;
      isLoading = false;
      loadError = null;
      if (selectedChain != 'all') {
        final chains = _availableChains;
        if (chains.every((c) => c.code.toLowerCase() != selectedChain.toLowerCase())) {
          selectedChain = 'all';
        }
      }
    });
  }

  Future<void> _loadCpfr() async {
    final id = ++_cpfrRequestId;
    setState(() {
      _cpfrLoading = true;
      _cpfrError = null;
    });
    try {
      final res = await widget.apiClient.fetchCPFRDashboard(
        chain: selectedChain,
        year: selectedYear,
        allowLocalFallback: false, // real data only
      );
      if (!mounted || id != _cpfrRequestId) return;
      setState(() {
        _cpfr = res;
        _cpfrLoading = false;
      });
    } catch (e) {
      if (!mounted || id != _cpfrRequestId) return;
      setState(() {
        _cpfr = null;
        _cpfrLoading = false;
        _cpfrError = e.toString();
      });
    }
  }

  Set<int> get _periodMonths {
    if (_periodMode == 'quarterly') {
      final f = (_selectedQuarter - 1) * 3 + 1;
      return {f, f + 1, f + 2};
    }
    if (selectedMonth == 0) return {for (var m = 1; m <= 12; m++) m};
    return {selectedMonth};
  }

  Widget _buildPeriodControls(BuildContext context) {
    final style = ButtonStyle(
      visualDensity: const VisualDensity(horizontal: -4, vertical: -2),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6.0)),
      textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.labelMedium),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<String>(
          key: const ValueKey('executive_period_segmented'),
          segments: const [
            ButtonSegment(value: 'monthly', label: Text('Monthly')),
            ButtonSegment(value: 'quarterly', label: Text('Quarterly')),
            ButtonSegment(value: 'yearly', label: Text('Yearly')),
          ],
          selected: {_periodMode},
          showSelectedIcon: false,
          style: style,
          onSelectionChanged: (sel) {
            final mode = sel.first;
            setState(() {
              _periodMode = mode;
              if (mode == 'yearly') selectedMonth = 0;
              if (mode == 'monthly' && selectedMonth == 0) selectedMonth = 1;
              if (mode == 'quarterly') selectedMonth = 0;
            });
            _loadData();
          },
        ),
        if (_periodMode == 'quarterly') ...[
          const SizedBox(width: 8.0),
          SegmentedButton<int>(
            key: const ValueKey('executive_quarter_segmented'),
            segments: [
              for (var q = 1; q <= 4; q++) ButtonSegment(value: q, label: Text('Q$q')),
            ],
            selected: {_selectedQuarter},
            showSelectedIcon: false,
            style: style,
            onSelectionChanged: (sel) {
              setState(() => _selectedQuarter = sel.first);
              _loadData();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildChainDropdown(BuildContext context, {bool isCompact = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chains = _availableChains;
    final activeChain = chains.firstWhere(
      (c) => c.code.toLowerCase() == selectedChain.toLowerCase(),
      orElse: () => chains.first,
    );

    return _menuFilter<String>(
      key: const ValueKey('executive_chain_dropdown'),
      tooltip: 'Filter by Retail Chain',
      onSelected: (chainCode) {
        setState(() => selectedChain = chainCode);
        _loadData();
      },
      items: chains.map((c) {
        final isSelected = c.code == selectedChain;
        final chainColor = c.code == 'all'
            ? colorScheme.primary
            : ChainSharePie.colorForChain(c.code);
        final parts = ChainSharePie.splitBilingualLabel(c.fullName);
        return (
          c.code,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected)
                Icon(
                  AppIcons.check,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      parts.ar,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? chainColor : colorScheme.onSurface,
                      ),
                    ),
                    if (parts.en != null)
                      Text(
                        parts.en!,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isSelected ? chainColor : colorScheme.onSurfaceVariant,
                          fontSize: M3FontSize.tinyPlus,
                        ),
                      ),
                  ],
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
          borderRadius: M3Shape.radiusLg,
          border: Border.all(
            color: colorScheme.outlineVariant.withOpacity(0.8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.storeMatrix, size: 15.0, color: colorScheme.primary),
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
              AppIcons.dropDown,
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // M3 SegmentedButton: the year filter has only a few fixed options.
        SegmentedButton<int>(
          key: const ValueKey('executive_year_segmented'),
          segments: [
            for (final y in _years)
              ButtonSegment<int>(value: y, label: Text('$y'), tooltip: 'Year $y'),
          ],
          selected: {selectedYear},
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: const VisualDensity(horizontal: -4, vertical: -2),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 6.0)),
            textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.labelMedium),
          ),
          onSelectionChanged: (s) {
            setState(() => selectedYear = s.first);
            _loadData();
          },
        ),
        const SizedBox(width: 8.0),
        Container(
      height: 38.0,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month Dropdown Button Segment
          _menuFilter<int>(
            key: const ValueKey('executive_month_dropdown'),
            tooltip: 'Select Month',
            minWidth: 220.0,
            onSelected: (month) {
              setState(() {
                selectedMonth = month;
                _periodMode = month == 0 ? 'yearly' : 'monthly';
              });
              _loadData();
            },
            items: _months.map((m) {
              final isSelected = m.number == selectedMonth;
              return (
                m.number,
                SizedBox(
                  width: 210.0,
                  child: Row(
                    children: [
                      if (isSelected)
                        Icon(
                          AppIcons.check,
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
                  Icon(AppIcons.calendar, size: 14.0, color: colorScheme.primary),
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
                    AppIcons.dropDown,
                    size: 16.0,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
        ),
      ],
    );
  }

  /// M3 MenuAnchor-based filter menu.
  Widget _menuFilter<T>({
    required Key key,
    required String tooltip,
    required List<(T, Widget)> items,
    required ValueChanged<T> onSelected,
    required Widget child,
    double? minWidth,
  }) {
    return MenuAnchor(
      style: minWidth == null
          ? null
          : MenuStyle(minimumSize: WidgetStatePropertyAll(Size(minWidth, 0))),
      menuChildren: [
        for (final (value, label) in items)
          MenuItemButton(onPressed: () => onSelected(value), child: label),
      ],
      builder: (context, controller, _) => Tooltip(
        message: tooltip,
        child: InkWell(
          key: key,
          borderRadius: M3Shape.radiusLg,
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          child: child,
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: isCompact ? M3Spacing.pSm : M3Spacing.pMd,
      child: M3ContentBoundary(
        maxWidth: double.infinity,
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
                    const SizedBox(width: 8.0),
                    _buildPeriodControls(context),
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
                        child: SizedBox(width: 240.0, child: LinearProgressIndicator(year2023: false)),
                      ),
                    )
                  : kpis != null
                      ? Column(
                          key: ValueKey(
                            'exec_kpis_${selectedPeriod}_${selectedYear}_${selectedMonth}_${selectedChain}_${kpis!.totalRevenue}',
                          ),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Original top summary: the four KPI cards.
                            BentoKpiGrid(kpis: kpis!),

                            M3Spacing.gapMD,

                            // Share per SKU / Category, then Sell In vs Sell Out.
                            MarketShareSection(
                              kpis: kpis!,
                              cpfr: _cpfr,
                              cpfrLoading: _cpfrLoading,
                              cpfrError: _cpfrError,
                              periodMonths: _periodMonths,
                              year: selectedYear,
                            ),

                            // Full-width Monthly Sell-Out Trend Chart (100% width for all 12 months)
                            SelloutTrendChart(trends: kpis!.dailyTrends),

                            M3Spacing.gapMD,

                            // Chain Market Share section directly below the trend chart
                            ChainSharePie(chainShares: kpis!.chainShares),

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
                      : Padding(
                          key: const ValueKey('exec_error_state'),
                          padding: const EdgeInsets.all(48.0),
                          child: Column(
                            children: [
                              Icon(AppIcons.error, size: 40.0, color: Theme.of(context).colorScheme.error),
                              M3Spacing.gapSM,
                              Text(
                                loadError == null ? 'No data to display' : 'Could not load dashboard data',
                                style: Theme.of(context).textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                              M3Spacing.gapSM,
                              FilledButton.tonalIcon(
                                key: const ValueKey('exec_retry_button'),
                                onPressed: () {
                                  setState(() => isLoading = true);
                                  _loadData();
                                },
                                icon: const Icon(AppIcons.refresh),
                                label: const Text('Retry'),
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
}

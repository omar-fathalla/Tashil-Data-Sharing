import 'package:tashil_web/core/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../data/executive_dashboard_repository.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../widgets/bento_kpi_grid.dart';
import '../widgets/chain_share_pie.dart';
import '../widgets/monthly_summary_card.dart';
import '../widgets/pareto_category_section.dart';
import '../widgets/sellout_trend_chart.dart';
import '../widgets/market_share_section.dart';
import '../../../cpfr_replenishment/domain/cpfr_models.dart';
import '../../../../core/data/data_refresh_mixin.dart';
import '../../../../core/data/available_years.dart';

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

class _ExecutiveScreenState extends State<ExecutiveScreen>
    with DataRefreshMixin<ExecutiveScreen> {
  @override
  void onBackendDataChanged() {
    _loadData();
  }

  String selectedPeriod = 'YTD';
  int selectedYear = AvailableYears.current.defaultYear;
  bool _yearTouched = false;
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

  static const List<
      ({int number, String shortName, String fullName, String nameAr})> _months = [
    (number: 0, shortName: 'All', fullName: 'كل الشهور', nameAr: 'الكل'),
    (number: 1, shortName: 'Jan', fullName: 'January', nameAr: 'يناير'),
    (number: 2, shortName: 'Feb', fullName: 'February', nameAr: 'فبراير'),
    (number: 3, shortName: 'Mar', fullName: 'March', nameAr: 'مارس'),
    (number: 4, shortName: 'Apr', fullName: 'April', nameAr: 'أبريل'),
    (number: 5, shortName: 'May', fullName: 'May', nameAr: 'مايو'),
    (number: 6, shortName: 'Jun', fullName: 'June', nameAr: 'يونيو'),
    (number: 7, shortName: 'Jul', fullName: 'July', nameAr: 'يوليو'),
    (number: 8, shortName: 'Aug', fullName: 'August', nameAr: 'أغسطس'),
    (number: 9, shortName: 'Sep', fullName: 'September', nameAr: 'سبتمبر'),
    (number: 10, shortName: 'Oct', fullName: 'October', nameAr: 'أكتوبر'),
    (number: 11, shortName: 'Nov', fullName: 'November', nameAr: 'نوفمبر'),
    (number: 12, shortName: 'Dec', fullName: 'December', nameAr: 'ديسمبر'),
  ];

  List<int> get _years => AvailableYears.current.including(selectedYear);

  List<({String code, String shortName, String fullName})>
      get _availableChains {
    final list = <({String code, String shortName, String fullName})>[
      (code: 'all', shortName: 'All', fullName: 'كل السلاسل'),
    ];

    final items = (kpis?.availableChains.isNotEmpty == true)
        ? kpis!.availableChains
        : (kpis?.chainShares ?? const <ChainShareItem>[]);

    final seen = <String>{};
    for (final item in items) {
      final code = item.retailerChain.trim().toLowerCase();
      if (code.isEmpty ||
          code == 'all' ||
          code == 'nda_redacted' ||
          seen.contains(code)) {
        continue;
      }
      seen.add(code);

      final resolvedLabel = ChainSharePie.labelForChain(code);
      final fullName = (item.displayName.isNotEmpty &&
              item.displayName.toLowerCase() != code)
          ? item.displayName
          : resolvedLabel;

      String shortName;
      if (code == 'beet-elgomla' ||
          code == 'beet_elgomla' ||
          code == 'beet elgomla') {
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
    // Year filter: data years + current year; default = latest year with data.
    AvailableYears.load(widget.apiClient).then((o) {
      if (!mounted) return;
      if (!_yearTouched && o.defaultYear != selectedYear) {
        setState(() => selectedYear = o.defaultYear);
        _loadData();
      } else {
        setState(() {});
      }
    });
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
      _repo =
          widget.repository ?? ExecutiveDashboardRepository(widget.apiClient);
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
      endDate =
          '$selectedYear-${lastM.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
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
    _loadSellInMonthly();
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
      debugPrint('Executive dashboard load failed: $error');
      if (ScaffoldMessenger.maybeOf(context) != null) {
        M3Feedback.showError(context, 'تعذّر تحميل المؤشرات. حاول مرة أخرى.');
      }
      return;
    }
    final result = loaded.valueOrNull!;
    setState(() {
      kpis = result;
      isLoading = false;
      loadError = null;
      if (selectedChain != 'all') {
        final chains = _availableChains;
        if (chains.every(
            (c) => c.code.toLowerCase() != selectedChain.toLowerCase())) {
          selectedChain = 'all';
        }
      }
    });
  }

  int _sellInMonthlyRequestId = 0;
  Map<String, Map<String, double>>? _sellInMonthly;

  /// Sell-In monthly totals per chain for the trend chart's second line. Failures only hide
  /// the Sell-In lines; the Sell-Out chart still renders.
  Future<void> _loadSellInMonthly() async {
    final id = ++_sellInMonthlyRequestId;
    try {
      final res = await widget.apiClient.getSellInMonthlyByChain(
        chain: selectedChain,
        year: selectedYear,
      );
      if (!mounted || id != _sellInMonthlyRequestId) return;
      setState(() => _sellInMonthly = res);
    } catch (_) {
      if (!mounted || id != _sellInMonthlyRequestId) return;
      setState(() => _sellInMonthly = null);
    }
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

  static Widget _segLabel(String s) =>
      Text(s, maxLines: 1, softWrap: false, overflow: TextOverflow.visible);

  Widget _buildPeriodControls(BuildContext context) {
    // M3: segmented buttons inherit the theme (112x40 equal segments, 48dp
    // tap target, secondaryContainer selection + check). No local overrides.
    return Wrap(
      spacing: M3Spacing.xs,
      runSpacing: M3Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<String>(
          key: const ValueKey('executive_period_segmented'),
          segments: [
            ButtonSegment(value: 'monthly', label: _segLabel('شهري')),
            ButtonSegment(value: 'quarterly', label: _segLabel('ربع سنوي')),
            ButtonSegment(value: 'yearly', label: _segLabel('سنوي')),
          ],
          selected: {_periodMode},
          showSelectedIcon: true,
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
          SegmentedButton<int>(
            key: const ValueKey('executive_quarter_segmented'),
            style: const ButtonStyle(
              // 4 short options: no 112dp floor.
              minimumSize: WidgetStatePropertyAll(Size(56.0, 40.0)),
            ),
            segments: [
              for (var q = 1; q <= 4; q++)
                ButtonSegment(value: q, label: _segLabel('Q$q')),
            ],
            selected: {_selectedQuarter},
            showSelectedIcon: false,
            onSelectionChanged: (sel) {
              setState(() => _selectedQuarter = sel.first);
              _loadData();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildChainDropdown(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chains = _availableChains;
    final activeChain = chains.firstWhere(
      (c) => c.code.toLowerCase() == selectedChain.toLowerCase(),
      orElse: () => chains.first,
    );

    return _menuFilter<String>(
      key: const ValueKey('executive_chain_dropdown'),
      tooltip: 'تصفية حسب السلسلة',
      icon: AppIcons.storeMatrix,
      label:
          'السلسلة: ${selectedChain == 'all' ? 'الكل' : ChainSharePie.splitBilingualLabel(activeChain.fullName).ar}',
      active: selectedChain != 'all',
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
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: M3Spacing.xxs),
                  child: CircleAvatar(radius: 5.0, backgroundColor: chainColor),
                ),
              const SizedBox(width: M3Spacing.s12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      parts.ar,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: isSelected ? FontWeight.w600 : null,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (parts.en != null)
                      Text(
                        parts.en!,
                        overflow: TextOverflow.ellipsis,
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
      }).toList(),
    );
  }

  /// Arabic tenant name for the header subtitle ("أديكو (Adeco)" → "أديكو").
  String _tenantNameAr() =>
      ChainSharePie.splitBilingualLabel(
              ApiClient.getDisplayNameForTenant(widget.apiClient.tenantId))
          .ar;

  /// Menu item label: leading check (primary) on the selected value.
  Widget _menuItemText(BuildContext context, String text, bool selected) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18.0,
          child: selected
              ? Icon(AppIcons.check, size: 18.0, color: cs.primary)
              : null,
        ),
        const SizedBox(width: M3Spacing.s12),
        Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: theme.textTheme.labelLarge?.copyWith(
            color: cs.onSurface,
            fontWeight: selected ? FontWeight.w600 : null,
          ),
        ),
      ],
    );
  }

  /// Year menu filter: outlined at the default year, tonal once changed
  /// (same rule as the other filters).
  Widget _buildYearFilter(BuildContext context) => _menuFilter<int>(
        key: const ValueKey('executive_year_dropdown'),
        tooltip: 'اختر السنة',
        icon: AppIcons.event,
        label: 'السنة: $selectedYear',
        active: selectedYear != AvailableYears.current.defaultYear,
        onSelected: (y) {
          setState(() {
            selectedYear = y;
            _yearTouched = true;
          });
          _loadData();
        },
        items: [
          for (final y in _years)
            (y, _menuItemText(context, '$y', y == selectedYear)),
        ],
      );

  Widget _buildMonthFilter(BuildContext context) {
    final activeMonth = _months.firstWhere(
      (m) => m.number == selectedMonth,
      orElse: () => _months.first,
    );
    return _menuFilter<int>(
      key: const ValueKey('executive_month_dropdown'),
      tooltip: 'اختر الشهر',
      icon: AppIcons.calendar,
      label: 'الشهر: ${activeMonth.nameAr}',
      active: selectedMonth != 0,
      minWidth: 220.0,
      onSelected: (month) {
        setState(() {
          selectedMonth = month;
          _periodMode = month == 0 ? 'yearly' : 'monthly';
        });
        _loadData();
      },
      items: [
        for (final m in _months)
          (
            m.number,
            _menuItemText(context, m.number == 0 ? 'كل الشهور' : m.nameAr,
                m.number == selectedMonth),
          ),
      ],
    );
  }

  /// Header controls (RTL from the start): period segmented | divider |
  /// month, year, chain. Compact: one horizontally scrollable row.
  Widget _buildHeaderControls(BuildContext context, bool isCompact) {
    final children = <Widget>[
      _buildPeriodControls(context),
      const SizedBox(
        height: 24.0,
        child: VerticalDivider(width: M3Spacing.xs * 2),
      ),
      _buildMonthFilter(context),
      _buildYearFilter(context),
      _buildChainDropdown(context),
    ];
    if (isCompact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, w) in children.indexed) ...[
              if (i > 0) const SizedBox(width: M3Spacing.xs),
              w,
            ],
          ],
        ),
      );
    }
    return Wrap(
      spacing: M3Spacing.xs,
      runSpacing: M3Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  /// M3 MenuAnchor filter trigger: a real button (40dp, 48dp target,
  /// focus ring). Outlined at the default value, tonal when a filter is active.
  Widget _menuFilter<T>({
    required Key key,
    required String tooltip,
    required IconData icon,
    required String label,
    required bool active,
    required List<(T, Widget)> items,
    required ValueChanged<T> onSelected,
    double? minWidth,
  }) {
    return MenuAnchor(
      style: minWidth == null
          ? null
          : MenuStyle(minimumSize: WidgetStatePropertyAll(Size(minWidth, 0))),
      menuChildren: [
        for (final (value, child) in items)
          MenuItemButton(onPressed: () => onSelected(value), child: child),
      ],
      builder: (context, controller, _) {
        final cs = Theme.of(context).colorScheme;
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        final content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, maxLines: 1, softWrap: false),
            const SizedBox(width: M3Spacing.xxs),
            const Icon(AppIcons.dropDown, size: 18.0),
          ],
        );
        // Icon-start M3 button + trailing caret; one 40dp stadium family.
        const pad = EdgeInsetsDirectional.fromSTEB(12.0, 0.0, 8.0, 0.0);
        final outlined = OutlinedButton.styleFrom(
          foregroundColor: cs.onSurfaceVariant,
          iconColor: cs.onSurfaceVariant,
          padding: pad,
          iconSize: 18.0,
          minimumSize: const Size(0.0, 40.0),
        );
        final tonal = FilledButton.styleFrom(
          padding: pad,
          iconSize: 18.0,
          minimumSize: const Size(0.0, 40.0),
        );
        return Tooltip(
          message: tooltip,
          child: active
              ? FilledButton.tonalIcon(
                  key: key,
                  style: tonal,
                  onPressed: toggle,
                  icon: Icon(icon),
                  label: content,
                )
              : OutlinedButton.icon(
                  key: key,
                  style: outlined,
                  onPressed: toggle,
                  icon: Icon(icon),
                  label: content,
                ),
        );
      },
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
              title: 'أداء المبيعات في سلاسل التجزئة',
              subtitle: 'لوحة الأداء التنفيذية · ${_tenantNameAr()}',
              // Mockup: up to 1440 (sidebar + content ≈ 1140dp) the
              // controls sit under the title as one full row.
              stackActionsBelow: 1600.0,
              actions: _buildHeaderControls(context, isCompact),
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
                        child: SizedBox(
                            width: 240.0,
                            child: LinearProgressIndicator(year2023: false)),
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
                            if (kpis!.monthlySummary != null &&
                                kpis!.monthlySummary!.narrativeAr
                                    .trim()
                                    .isNotEmpty) ...[
                              M3Spacing.gapMD,
                              MonthlySummaryCard(
                                  summary: kpis!.monthlySummary!),
                            ],

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
                            SelloutTrendChart(
                              trends: kpis!.dailyTrends,
                              sellInByChain: _sellInMonthly,
                            ),

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
                              Icon(AppIcons.error,
                                  size: 40.0,
                                  color: Theme.of(context).colorScheme.error),
                              M3Spacing.gapSM,
                              Text(
                                loadError == null
                                    ? 'لا توجد بيانات لهذه الفترة'
                                    : 'تعذّر تحميل البيانات',
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
                                label: const Text('إعادة المحاولة'),
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

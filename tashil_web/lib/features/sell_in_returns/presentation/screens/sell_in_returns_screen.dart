import 'package:flutter/material.dart';
import 'package:tashil_web/core/data/available_years.dart';
import 'package:tashil_web/core/data/data_refresh_mixin.dart';
import 'package:tashil_web/core/layout/m3_content_boundary.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/m3_spacing.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/core/utils/excel_export_service.dart';
import 'package:tashil_web/core/utils/export_columns.dart';
import 'package:tashil_web/core/widgets/kpi_card.dart';
import 'package:tashil_web/core/widgets/m3_dropdown.dart';
import 'package:tashil_web/core/widgets/m3_feedback.dart';
import 'package:tashil_web/core/widgets/m3_states.dart';

import '../../data/sell_in_returns_repository.dart';
import '../../domain/sell_in_returns_models.dart';
import '../widgets/returns_heatmap_matrix.dart';
import '../widgets/returns_monthly_chart.dart';
import '../widgets/returns_top_products_table.dart';

/// المرتجعات page: Phase-1 KPIs/matrix/chart + Phase-2 top products + Excel.
/// Threshold-alert and net-negative advisory cards were removed (cards only;
/// API may still omit empty `alerts` / `advisories`).
class SellInReturnsScreen extends StatefulWidget {
  final ApiClient apiClient;
  final SellInReturnsRepository? repository;

  const SellInReturnsScreen({
    super.key,
    required this.apiClient,
    this.repository,
  });

  @override
  State<SellInReturnsScreen> createState() => _SellInReturnsScreenState();
}

class _SellInReturnsScreenState extends State<SellInReturnsScreen>
    with DataRefreshMixin<SellInReturnsScreen> {
  late SellInReturnsRepository _repo;
  bool _loading = true;
  String? _error;
  SellInReturnsReport _report = const SellInReturnsReport();

  int _year = AvailableYears.current.defaultYear;
  int _month = 0; // 0 = all
  String _branch = 'all';
  String _product = 'all';
  String _productGroup = 'all';
  bool _showPct = false; // false = value, true = return % of gross

  static const _monthLabelsAr = [
    'كل الشهور',
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

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? ApiSellInReturnsRepository(widget.apiClient);
    _year = AvailableYears.current.defaultYear;
    _load();
    // Refresh dynamic years without blocking first paint (tests inject a fake repo).
    AvailableYears.load(widget.apiClient).then((opts) {
      if (!mounted) return;
      if (_year != opts.defaultYear) {
        setState(() => _year = opts.defaultYear);
        _load();
      } else {
        setState(() {}); // rebuild year dropdown options
      }
    });
  }

  @override
  void didUpdateWidget(covariant SellInReturnsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.apiClient != widget.apiClient) {
      _repo = widget.repository ?? ApiSellInReturnsRepository(widget.apiClient);
      _load(force: true);
    }
  }

  @override
  void onBackendDataChanged() => _load(force: true);

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _repo.load(
      SellInReturnsQuery(
        year: _year,
        month: _month > 0 ? _month : null,
        branch: _branch == 'all' ? null : _branch,
        product: _product == 'all' ? null : _product,
        productGroup: _productGroup == 'all' ? null : _productGroup,
      ),
      forceRefresh: force,
    );
    if (!mounted) return;
    res.when(
      success: (value) => setState(() {
        _report = value;
        _loading = false;
      }),
      failure: (error) => setState(() {
        _error = error.message;
        _loading = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: M3ContentBoundary(
        padding: M3Spacing.pMd,
        child: RefreshIndicator(
          onRefresh: () => _load(force: true),
          child: ListView(
            children: [
              _buildHeader(theme, cs),
              const SizedBox(height: 12),
              _buildFilters(theme, cs),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                M3ErrorState(
                  title: 'تعذر تحميل المرتجعات',
                  message: _error,
                  onRetry: () => _load(force: true),
                )
              else ...[
                _buildKpis(theme, cs),
                const SizedBox(height: 16),
                ReturnsMonthlyChart(points: _report.monthly),
                if (_report.topReturnedProducts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildTopProducts(theme, cs),
                ],
                const SizedBox(height: 16),
                _buildMatrixCard(theme, cs),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleExportExcel() {
    if (widget.apiClient.currentUser?.canExportFinancials == false) {
      M3Feedback.showError(context, 'ليس لديك صلاحية تصدير التقارير.');
      return;
    }
    if (_loading || _error != null) {
      M3Feedback.showWarning(context, 'انتظر تحميل البيانات قبل التصدير.');
      return;
    }

    final matrixRows = <List<Object?>>[];
    for (final b in _report.branches) {
      for (final m in _report.months) {
        final cell = b.byMonth[m] ?? const SellInReturnsCell();
        matrixRows.add([
          b.branchName,
          _monthLabelsAr[m],
          cell.grossValueEgp.toStringAsFixed(2),
          cell.returnsValueEgp.toStringAsFixed(2),
          cell.returnsQty.toStringAsFixed(2),
          cell.netValueEgp.toStringAsFixed(2),
          cell.returnPctOfGross.toStringAsFixed(1),
        ]);
      }
    }
    final matrixCsv = ExcelExportService.generateCsv(
      headers: ExportColumns.sellInReturnsMatrix,
      rows: matrixRows,
    );
    final stamp = DateTime.now().millisecondsSinceEpoch;
    ExcelExportService.downloadCsv(
      'tashil_sellin_returns_matrix_$stamp.csv',
      matrixCsv,
    );

    if (_report.topReturnedProducts.isNotEmpty) {
      final topRows = _report.topReturnedProducts
          .map(
            (p) => [
              p.rank,
              p.productCode,
              p.productName,
              p.productGroup,
              p.returnsValueEgp.toStringAsFixed(2),
              p.returnsQty.toStringAsFixed(2),
              p.grossValueEgp.toStringAsFixed(2),
              p.netValueEgp.toStringAsFixed(2),
              p.returnPctOfGross.toStringAsFixed(1),
              p.shareOfReturns.toStringAsFixed(1),
            ],
          )
          .toList();
      final topCsv = ExcelExportService.generateCsv(
        headers: ExportColumns.sellInReturnsTopProducts,
        rows: topRows,
      );
      ExcelExportService.downloadCsv(
        'tashil_sellin_returns_top_products_$stamp.csv',
        topCsv,
      );
    }

    M3Feedback.showSuccess(
      context,
      'تم تصدير تقرير المرتجعات (CSV).',
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TestSemantics(
                identifier: 'returns-page-title',
                label: 'المرتجعات',
                child: Text(
                  'المرتجعات',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Sell-In Returns · Adeco → chains (read-only)',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        TestSemantics(
          identifier: 'returns-export-excel',
          label: 'تصدير Excel',
          child: OutlinedButton.icon(
            onPressed: _handleExportExcel,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('تصدير Excel'),
          ),
        ),
        const SizedBox(width: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('قيمة'), icon: Icon(Icons.payments_rounded, size: 18)),
            ButtonSegment(value: true, label: Text('نسبة %'), icon: Icon(Icons.percent_rounded, size: 18)),
          ],
          selected: {_showPct},
          onSelectionChanged: (s) => setState(() => _showPct = s.first),
        ),
      ],
    );
  }

  Widget _buildFilters(ThemeData theme, ColorScheme cs) {
    final years = AvailableYears.current.including(_year);
    final yearItems = years.isEmpty ? [_year] : years;
    final branches = ['all', ..._report.filterOptions.branches];
    final products = ['all', ..._report.filterOptions.products];
    final groups = ['all', ..._report.filterOptions.productGroups];

    return Card.outlined(
      child: Padding(
        padding: M3Spacing.pSm,
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            M3Dropdown<int>(
              width: 140,
              label: 'السنة',
              value: _year,
              options: [for (final y in yearItems) M3DropdownOption(y, '$y')],
              onChanged: (v) {
                setState(() => _year = v);
                _load();
              },
            ),
            M3Dropdown<int>(
              width: 160,
              label: 'الشهر',
              value: _month,
              options: [
                for (var m = 0; m <= 12; m++) M3DropdownOption(m, _monthLabelsAr[m]),
              ],
              onChanged: (v) {
                setState(() => _month = v);
                _load();
              },
            ),
            M3Dropdown<String>(
              width: 220,
              label: 'الفرع',
              value: branches.contains(_branch) ? _branch : 'all',
              options: [
                for (final b in branches)
                  M3DropdownOption(b, b == 'all' ? 'كل الفروع' : b),
              ],
              onChanged: (v) {
                setState(() => _branch = v);
                _load();
              },
            ),
            M3Dropdown<String>(
              width: 220,
              label: 'الصنف',
              value: products.contains(_product) ? _product : 'all',
              options: [
                for (final p in products)
                  M3DropdownOption(p, p == 'all' ? 'كل الأصناف' : p),
              ],
              onChanged: (v) {
                setState(() => _product = v);
                _load();
              },
            ),
            M3Dropdown<String>(
              width: 200,
              label: 'مجموعة الصنف',
              value: groups.contains(_productGroup) ? _productGroup : 'all',
              options: [
                for (final g in groups)
                  M3DropdownOption(g, g == 'all' ? 'كل المجموعات' : g),
              ],
              onChanged: (v) {
                setState(() => _productGroup = v);
                _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpis(ThemeData theme, ColorScheme cs) {
    final k = _report.kpis;
    final mom = k.momChangePct;
    final momUp = k.momDirection == 'up';
    final momDown = k.momDirection == 'down';
    final momLabel = mom == null
        ? 'لا مقارنة'
        : '${momUp ? '↑' : momDown ? '↓' : '→'} ${mom.abs().toStringAsFixed(1)}%';
    final momEn = mom == null ? 'n/a' : '${k.momDirection} ${mom.toStringAsFixed(1)}%';

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final cards = [
          KpiCard(
            title: 'قيمة المرتجعات',
            titleEn: 'Returns Value',
            value: CurrencyFormatter.formatCompactEGP(k.returnsValueEgp),
            subtitle: 'مجموع قيم المرتجع (موجب للعرض)',
            icon: Icons.undo_rounded,
            growthPct: mom ?? 0,
            badgeLabel: momLabel,
            badgeLabelEn: momEn,
            isPositive: !momUp,
            isAlert: momUp,
          ),
          KpiCard(
            title: 'كمية المرتجعات',
            titleEn: 'Returns Qty',
            value: CurrencyFormatter.formatNumber(k.returnsQty.round()),
            subtitle: 'كرتونة / وحدة مرتجعة',
            icon: Icons.inventory_2_rounded,
            growthPct: 0,
            badgeLabel: 'كمية',
            badgeLabelEn: 'Qty',
            isPositive: true,
            usePrimaryBadge: true,
          ),
          KpiCard(
            title: 'نسبة المرتجع من الإجمالي',
            titleEn: 'Return % of Gross',
            value: '${k.returnPctOfGross.toStringAsFixed(1)}%',
            subtitle: 'Returns ÷ Gross',
            icon: Icons.percent_rounded,
            growthPct: k.returnPctOfGross,
            badgeLabel: 'من الإجمالي',
            badgeLabelEn: 'of gross',
            isPositive: k.returnPctOfGross < 5,
            isAlert: k.returnPctOfGross >= 10,
          ),
          KpiCard(
            title: 'التغير الشهري (MoM)',
            titleEn: 'MoM Change',
            value: mom == null ? '—' : '${mom >= 0 ? '+' : ''}${mom.toStringAsFixed(1)}%',
            subtitle: k.focusMonth > 0
                ? 'مقارنة ${_monthLabelsAr[k.focusMonth]} بالشهر السابق'
                : 'لا يوجد شهر مقارنة',
            icon: momUp
                ? Icons.trending_up_rounded
                : momDown
                    ? Icons.trending_down_rounded
                    : Icons.trending_flat_rounded,
            growthPct: mom ?? 0,
            badgeLabel: momUp ? 'ارتفاع' : momDown ? 'انخفاض' : 'ثابت',
            badgeLabelEn: k.momDirection,
            isPositive: !momUp,
            isAlert: momUp,
          ),
        ];
        if (wide) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards)
              SizedBox(width: (c.maxWidth - 12) / 2, child: card),
          ],
        );
      },
    );
  }

  Widget _buildTopProducts(ThemeData theme, ColorScheme cs) {
    return Card.outlined(
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'أعلى الأصناف المرتجعة',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Top returned products · مرتّبة حسب قيمة المرتجع',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            ReturnsTopProductsTable(products: _report.topReturnedProducts),
          ],
        ),
      ),
    );
  }

  Widget _buildMatrixCard(ThemeData theme, ColorScheme cs) {
    final months = _report.months;

    return Card.outlined(
      child: Padding(
        padding: M3Spacing.pMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'مصفوفة المرتجعات · فرع × شهر',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _showPct
                  ? 'عرض نسبة المرتجع من الإجمالي لكل خلية'
                  : 'عرض قيمة المرتجع (موجب) لكل خلية — تلوين حسب الحجم',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (months.isEmpty || _report.branches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'لا توجد مرتجعات ضمن الفلاتر الحالية',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ReturnsHeatmapMatrix(
                months: months,
                branches: _report.branches,
                columnTotals: _report.columnTotals,
                grandTotal: _report.grandTotal,
                monthLabelsAr: _monthLabelsAr,
                showPct: _showPct,
              ),
          ],
        ),
      ),
    );
  }
}

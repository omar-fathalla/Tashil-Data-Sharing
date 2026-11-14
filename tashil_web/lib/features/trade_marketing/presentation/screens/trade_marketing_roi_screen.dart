import 'package:tashil_web/core/widgets/m3_search_field.dart';
import 'dart:convert';
import 'package:tashil_web/core/theme/m3_palette.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';

import 'package:flutter/material.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/bidi_text.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_responsive_tab_bar.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../../../core/utils/arabic_plural.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';
import '../../../../core/widgets/m3_wrap_text.dart';
import '../../data/cached_trade_marketing_repository.dart';
import '../../data/trade_marketing_repository.dart';
import '../../domain/roi_lift.dart';
import '../../domain/trade_marketing_models.dart';
import '../../../../core/data/data_refresh_mixin.dart';

/// TradeMarketingRoiScreen is a dedicated enterprise system for tracking
/// Trade Marketing & Promotional Expenses (الفلورات، الدعاية، الإعلانات، الهدايا، الإيفنتات)
/// per Chain and Month, and correlating them with actual MoM (Month-over-Month)
/// and YoY (Year-over-Year) sales growth to evaluate Marketing ROI (ROMI).
class TradeMarketingRoiScreen extends StatefulWidget {
  final ApiClient apiClient;

  /// Optional data source (tests inject a fake). Defaults to the Cloud Run API.
  final TradeMarketingRepository? repository;

  const TradeMarketingRoiScreen({
    super.key,
    required this.apiClient,
    this.repository,
  });

  @override
  State<TradeMarketingRoiScreen> createState() =>
      _TradeMarketingRoiScreenState();
}

class _TradeMarketingRoiScreenState extends State<TradeMarketingRoiScreen>
    with DataRefreshMixin<TradeMarketingRoiScreen> {
  @override
  void onBackendDataChanged() {
    _reload();
  }

  // 0: ROI & Sales Growth Matrix, 1: Campaigns & Expense Ledger, 2: Category & Brand Analytics
  int _activeTab = 0;

  String _selectedChain = 'all';
  int _selectedYear = 2026; // 0 = All Years
  int _selectedMonth = 0; // 0 = All Months
  String _selectedCategoryId = 'all';
  String _searchQuery = '';

  String _matrixSortColumn = 'month';
  bool _matrixSortAsc = true;

  String _ledgerSortColumn = 'amount';
  bool _ledgerSortAsc = false;

  List<MarketingExpenseItem> _expenses = [];

  /// Server sales baselines keyed by [tradeMarketingBaselineKey].
  final Map<String, TradeMarketingSalesBaseline> _baselines = {};
  bool _loading = false;
  String? _loadError;
  late final TradeMarketingRepository _repo = widget.repository ??
      CachedTradeMarketingRepository(
          ApiTradeMarketingRepository(widget.apiClient), widget.apiClient);

  static const List<String> _availableChains = [
    'Fathalla',
    'Gomla',
    'Beet El Gomla',
    'El Wakala',
    'Zahran',
    'Metro',
  ];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  bool _uploading = false;

  /// Roles the backend allows to write trade marketing expenses.
  static const Set<String> _writeRoles = {
    'super_admin',
    'vendor_admin',
    'admin',
    'national_sales_manager',
    'chain_kam',
    'executive',
  };

  bool get _canWrite {
    final role = widget.apiClient.currentUser?.role ?? '';
    return role.isEmpty || _writeRoles.contains(role);
  }

  static const String _templateCsvHeader =
      'year,month,chain_name,category,amount_egp,brand_name,campaign_title,vendor_or_agency,notes\n';

  void _downloadTemplate() {
    WebFileHelper.downloadFile(
      filename: 'trade_marketing_expenses_template.csv',
      bytes: [0xEF, 0xBB, 0xBF, ...utf8.encode(_templateCsvHeader)],
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  Future<void> _pickAndUploadExpenses() async {
    if (_uploading || !_canWrite) return;
    final picked = await WebFileHelper.pickFile(accept: '.xlsx,.csv');
    if (picked == null || !mounted) return;
    final lower = picked.name.toLowerCase();
    if (!(lower.endsWith('.xlsx') || lower.endsWith('.csv'))) {
      M3Feedback.showError(
          context, 'نوع الملف غير مدعوم. يرجى اختيار ملف ‎.xlsx أو ‎.csv');
      return;
    }
    setState(() => _uploading = true);
    try {
      final result = await _repo.uploadExpenses(picked.bytes, picked.name);
      if (!mounted) return;
      setState(() => _uploading = false);
      await _showUploadResultDialog(picked.name, result);
      if (mounted) await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      M3Feedback.showError(context, 'تعذر رفع الملف: $e');
    }
  }

  Future<void> _showUploadResultDialog(String filename, ExpenseUploadResult r) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            key: const ValueKey('dlg_expense_upload_result'),
            icon: Icon(
              r.rejectedCount == 0
                  ? Icons.check_circle_rounded
                  : Icons.warning_amber_rounded,
              color: r.rejectedCount == 0 ? cs.primary : cs.error,
            ),
            title: const Text('نتيجة رفع المصروفات'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(filename, style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    Chip(
                      key: const ValueKey('chip_upload_saved'),
                      avatar: Icon(Icons.check_rounded,
                          size: 18, color: cs.primary),
                      label: Text('تم الحفظ: ${r.savedCount}'),
                    ),
                    Chip(
                      key: const ValueKey('chip_upload_rejected'),
                      avatar:
                          Icon(Icons.block_rounded, size: 18, color: cs.error),
                      label: Text('مرفوض: ${r.rejectedCount}'),
                    ),
                  ]),
                  if (r.rejectedReasons.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('الصفوف المرفوضة وأسبابها:',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final reason in r.rejectedReasons)
                            ListTile(
                              dense: true,
                              leading: Icon(Icons.error_outline_rounded,
                                  size: 18, color: cs.error),
                              title: Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(reason, textAlign: TextAlign.right),
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
              FilledButton(
                key: const ValueKey('btn_close_upload_result'),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('تم'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Loads expenses and ROI sales baselines from the server.
  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([_repo.listExpenses(), _repo.getRoi()]);
      if (!mounted) return;
      setState(() {
        _expenses = List<MarketingExpenseItem>.from(
            results[0] as List<MarketingExpenseItem>);
        _baselines.clear();
        for (final b in results[1] as List<TradeMarketingSalesBaseline>) {
          _baselines[tradeMarketingBaselineKey(b.year, b.month, b.chainName)] =
              b;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _reloadRoiOnly() async {
    try {
      final list = await _repo.getRoi();
      if (!mounted) return;
      setState(() {
        _baselines.clear();
        for (final b in list) {
          _baselines[tradeMarketingBaselineKey(b.year, b.month, b.chainName)] =
              b;
        }
      });
    } catch (_) {}
  }

  /// Ensures a server baseline exists for a chain/month (used by the what-if simulator).
  Future<TradeMarketingSalesBaseline?> _ensureBaseline(
      String chain, int year, int month) async {
    final key = tradeMarketingBaselineKey(year, month, chain);
    if (_baselines.containsKey(key)) return _baselines[key];
    try {
      final list = await _repo.getRoi(year: year, month: month, chain: chain);
      for (final b in list) {
        _baselines[tradeMarketingBaselineKey(b.year, b.month, b.chainName)] = b;
      }
    } catch (_) {}
    return _baselines[key];
  }

  /// Average historical ROMI from recorded campaigns, or null when none exist.
  /// Null must not fall back to a hardcoded multiple (owner rule).
  double? get _historicalRomi =>
      averageHistoricalRomi(_monthlyRoiSummariesFor(_expenses));

  /// Filtered individual expense items
  List<MarketingExpenseItem> get _filteredExpenses {
    final q = _searchQuery.trim().toLowerCase();
    final list = _expenses.where((item) {
      if (_selectedChain != 'all' && item.chainName != _selectedChain)
        return false;
      if (_selectedYear != 0 && item.year != _selectedYear) return false;
      if (_selectedMonth != 0 && item.month != _selectedMonth) return false;
      if (_selectedCategoryId != 'all' &&
          item.category.id != _selectedCategoryId) return false;
      if (q.isNotEmpty) {
        final match = item.campaignTitle.toLowerCase().contains(q) ||
            item.brandName.toLowerCase().contains(q) ||
            item.vendorOrAgency.toLowerCase().contains(q) ||
            item.chainName.toLowerCase().contains(q) ||
            item.category.labelAr.toLowerCase().contains(q) ||
            item.category.labelEn.toLowerCase().contains(q);
        if (!match) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      switch (_ledgerSortColumn) {
        case 'month':
          cmp = (a.year * 100 + a.month).compareTo(b.year * 100 + b.month);
          break;
        case 'chain':
          cmp = a.chainName.compareTo(b.chainName);
          break;
        case 'category':
          cmp = a.category.labelAr.compareTo(b.category.labelAr);
          break;
        case 'amount':
        default:
          cmp = a.amountEgp.compareTo(b.amountEgp);
          break;
      }
      return _ledgerSortAsc ? cmp : -cmp;
    });

    return list;
  }

  /// Aggregated Monthly + Chain ROI summaries
  List<MonthlyChainRoiSummary> get _monthlyRoiSummaries =>
      _monthlyRoiSummariesFor(_filteredExpenses);

  List<MonthlyChainRoiSummary> _monthlyRoiSummariesFor(
      List<MarketingExpenseItem> source) {
    final grouped = <String, List<MarketingExpenseItem>>{};
    for (final item in source) {
      final key = '${item.year}_${item.month}_${item.chainName}';
      grouped.putIfAbsent(key, () => []).add(item);
    }

    final summaries = <MonthlyChainRoiSummary>[];
    for (final entry in grouped.entries) {
      final items = entry.value;
      final first = items.first;
      final totalSpend = items.fold<double>(0.0, (sum, e) => sum + e.amountEgp);

      final baseline = _baselines[
          tradeMarketingBaselineKey(first.year, first.month, first.chainName)];

      summaries.add(
        MonthlyChainRoiSummary(
          year: first.year,
          month: first.month,
          chainName: first.chainName,
          marketingSpendEgp: totalSpend,
          activitiesCount: items.length,
          expenses: items,
          currentMonthSalesEgp: baseline?.currentMonthSalesEgp ?? 0.0,
          previousMonthSalesEgp: baseline?.previousMonthSalesEgp ?? 0.0,
          lastYearSameMonthSalesEgp: baseline?.lastYearSameMonthSalesEgp ?? 0.0,
          currentMonthSellInEgp: baseline?.currentMonthSellInEgp ?? 0.0,
          lift: baseline?.lift,
        ),
      );
    }

    summaries.sort((a, b) {
      int cmp;
      switch (_matrixSortColumn) {
        case 'spend':
          cmp = a.marketingSpendEgp.compareTo(b.marketingSpendEgp);
          break;
        case 'sales':
          cmp = a.currentMonthSalesEgp.compareTo(b.currentMonthSalesEgp);
          break;
        case 'mom':
          cmp = a.momGrowthPct.compareTo(b.momGrowthPct);
          break;
        case 'yoy':
          cmp = a.yoyGrowthPct.compareTo(b.yoyGrowthPct);
          break;
        case 'roi':
          cmp = (a.romiMultiple ?? double.negativeInfinity)
              .compareTo(b.romiMultiple ?? double.negativeInfinity);
          break;
        case 'month':
        default:
          cmp = (a.year * 100 + a.month).compareTo(b.year * 100 + b.month);
          if (cmp == 0) cmp = a.chainName.compareTo(b.chainName);
          break;
      }
      return _matrixSortAsc ? cmp : -cmp;
    });

    return summaries;
  }

  void _toggleMatrixSort(String col) {
    setState(() {
      if (_matrixSortColumn == col) {
        _matrixSortAsc = !_matrixSortAsc;
      } else {
        _matrixSortColumn = col;
        _matrixSortAsc = false;
      }
    });
  }

  void _toggleLedgerSort(String col) {
    setState(() {
      if (_ledgerSortColumn == col) {
        _ledgerSortAsc = !_ledgerSortAsc;
      } else {
        _ledgerSortColumn = col;
        _ledgerSortAsc = false;
      }
    });
  }

  void _openAddOrEditExpenseDialog({MarketingExpenseItem? existing}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String chain = existing?.chainName ??
        (_selectedChain != 'all' ? _selectedChain : 'Fathalla');
    int year = existing?.year ?? (_selectedYear != 0 ? _selectedYear : 2026);
    int month = existing?.month ?? (_selectedMonth != 0 ? _selectedMonth : 1);
    MarketingExpenseCategory category =
        existing?.category ?? MarketingExpenseCategory.floorRental;

    final titleCtrl = TextEditingController(
      text: existing?.campaignTitle ?? '',
    );
    final brandCtrl = TextEditingController(
      text: existing?.brandName ?? 'Diva',
    );
    final vendorCtrl = TextEditingController(
      text: existing?.vendorOrAgency ?? '',
    );
    final amountCtrl = TextEditingController(
      text: existing != null ? existing.amountEgp.toStringAsFixed(0) : '',
    );
    final notesCtrl = TextEditingController(
      text: existing?.notes ?? '',
    );

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
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
                        existing == null
                            ? Icons.add_chart_rounded
                            : Icons.edit_note_rounded,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            existing == null
                                ? 'إضافة مصروف تسويقي / حملة ترويجية جديدة'
                                : 'تعديل المصروف التسويقي',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'أدخل تفاصيل المصروف أو الحملة',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 580.0,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Row 1: Chain, Month, Year
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: M3Dropdown<String>(
                                value: chain,
                                label: 'السلسلة',
                                expand: true,
                                options: m3OptionsFromMenuItems<String>(
                                    _availableChains
                                        .map((c) => DropdownMenuItem(
                                            value: c, child: Text(c)))
                                        .toList()),
                                onChanged: m3Legacy<String>((val) {
                                  if (val != null)
                                    setDialogState(() => chain = val);
                                }),
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              flex: 2,
                              child: M3Dropdown<int>(
                                value: month,
                                label: 'الشهر',
                                expand: true,
                                options: m3OptionsFromMenuItems<int>(
                                    List.generate(12, (idx) {
                                  final m = idx + 1;
                                  return DropdownMenuItem(
                                    value: m,
                                    child: Text(
                                      '${MarketingExpenseItem.monthNamesAr[m]} - ${MarketingExpenseItem.monthNamesEn[m]}',
                                    ),
                                  );
                                })),
                                onChanged: m3Legacy<int>((val) {
                                  if (val != null)
                                    setDialogState(() => month = val);
                                }),
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              flex: 1,
                              child: M3Dropdown<int>(
                                value: year,
                                label: 'السنة',
                                expand: true,
                                options: m3OptionsFromMenuItems<int>([
                                  const DropdownMenuItem(
                                      value: 2026, child: Text('2026')),
                                  const DropdownMenuItem(
                                      value: 2025, child: Text('2025')),
                                ]),
                                onChanged: m3Legacy<int>((val) {
                                  if (val != null)
                                    setDialogState(() => year = val);
                                }),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14.0),

                        // Row 2: Expense Category
                        M3Dropdown<MarketingExpenseCategory>(
                          value: category,
                          label: 'نوع المصروف',
                          expand: true,
                          options:
                              m3OptionsFromMenuItems<MarketingExpenseCategory>(
                                  MarketingExpenseCategory.values.map((cat) {
                            return DropdownMenuItem(
                              value: cat,
                              child: Row(
                                children: [
                                  Icon(cat.icon, size: 18.0, color: cat.color),
                                  const SizedBox(width: 8.0),
                                  Expanded(
                                    child: Text(
                                      cat.labelAr,
                                      maxLines: 2,
                                      overflow: TextOverflow.visible,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList()),
                          onChanged: m3Legacy<MarketingExpenseCategory>((val) {
                            if (val != null)
                              setDialogState(() => category = val);
                          }),
                        ),
                        const SizedBox(height: 14.0),

                        // Row 3: Amount EGP + Brand
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: amountCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'قيمة المصروف (ج.م) *',
                                  hintText: 'مثال: 100,000',
                                  prefixIcon: Icon(Icons.payments_rounded),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: brandCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'البراند المستهدف',
                                  hintText: 'مثال: Diva / Maxell',
                                  prefixIcon: Icon(Icons.loyalty_rounded),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14.0),

                        // Row 4: Campaign Title
                        TextField(
                          controller: titleCtrl,
                          decoration: const InputDecoration(
                            labelText: 'وصف الحملة أو النشاط الترويجي *',
                            hintText:
                                'مثال: تأجير فلورات عرض رئيسية + إيفنت تذوق وهدايا مجانية',
                            prefixIcon: Icon(Icons.campaign_rounded),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 14.0),

                        // Row 5: Vendor / Agency
                        TextField(
                          controller: vendorCtrl,
                          decoration: const InputDecoration(
                            labelText: 'جهة التعاقد أو شركة الدعاية',
                            hintText:
                                'مثال: إدارة التعاقدات بالسلسلة / شركة دعاية وإيفنتات',
                            prefixIcon: Icon(Icons.business_rounded),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 14.0),

                        // Row 6: Notes
                        TextField(
                          controller: notesCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظات وتفاصيل الفروع المستهدفة',
                            hintText:
                                'مثال: فروع سموحة، سان ستيفانو، المنتزه...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      final parsedAmount = double.tryParse(
                              amountCtrl.text.replaceAll(',', '').trim()) ??
                          0.0;
                      if (parsedAmount <= 0) {
                        M3Feedback.showWarning(context,
                            'يرجى إدخال قيمة صحيحة للمصروف بالجنيه (أكبر من صفر)');
                        return;
                      }
                      final title = titleCtrl.text.trim().isEmpty
                          ? '${category.labelAr} - $chain (${MarketingExpenseItem.monthNamesAr[month]})'
                          : titleCtrl.text.trim();

                      final newItem = MarketingExpenseItem(
                        id: existing?.id ??
                            'EXP-${DateTime.now().millisecondsSinceEpoch}',
                        year: year,
                        month: month,
                        chainName: chain,
                        category: category,
                        brandName: brandCtrl.text.trim().isEmpty
                            ? 'General'
                            : brandCtrl.text.trim(),
                        campaignTitle: title,
                        vendorOrAgency: vendorCtrl.text.trim().isEmpty
                            ? 'تعاقد مباشر - $chain'
                            : vendorCtrl.text.trim(),
                        amountEgp: parsedAmount,
                        notes: notesCtrl.text.trim(),
                        createdAt: existing?.createdAt ?? DateTime.now(),
                      );

                      final MarketingExpenseItem saved;
                      try {
                        saved = await _repo.saveExpense(newItem,
                            isNew: existing == null);
                      } catch (e) {
                        if (!mounted) return;
                        M3Feedback.showWarning(context, 'تعذر حفظ المصروف: $e');
                        return;
                      }
                      if (!mounted) return;
                      setState(() {
                        if (existing != null) {
                          final idx =
                              _expenses.indexWhere((e) => e.id == existing.id);
                          if (idx != -1) _expenses[idx] = saved;
                        } else {
                          _expenses.insert(0, saved);
                        }
                      });
                      _reloadRoiOnly();

                      if (!dialogCtx.mounted) return;
                      Navigator.pop(dialogCtx);
                      M3Feedback.showSuccess(
                        context,
                        existing == null
                            ? 'تمت إضافة المصروف التسويقي (${CurrencyFormatter.formatEGP(parsedAmount)}) وربطه بنمو مبيعات $chain لشهر ${MarketingExpenseItem.monthNamesAr[month]} بنجاح'
                            : 'تم تحديث المصروف التسويقي وإعادة احتساب الـ ROI بنجاح',
                      );
                    },
                    icon: const Icon(Icons.check_circle_outline_rounded,
                        size: 18.0),
                    label: Text(
                        existing == null ? 'حفظ المصروف' : 'تحديث المصروف'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openRoiSimulatorDialog() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String simChain = _selectedChain != 'all' ? _selectedChain : 'Fathalla';
    int simMonth = _selectedMonth != 0 ? _selectedMonth : 1;
    final int simYear =
        _selectedYear != 0 ? _selectedYear : DateTime.now().year;
    final requested = <String>{};
    final historicalRomi = _historicalRomi;
    double proposedBudget = 100000.0;
    final budgetCtrl = TextEditingController(
      text: CurrencyFormatter.formatUnits(100000),
    );

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // What-if projection seeded from server baselines (ingested sell-out data).
            final simKey =
                tradeMarketingBaselineKey(simYear, simMonth, simChain);
            final baseline = _baselines[simKey];
            if (baseline == null && !requested.contains(simKey)) {
              requested.add(simKey);
              _ensureBaseline(simChain, simYear, simMonth).then((_) {
                if (dialogCtx.mounted) setDialogState(() {});
              });
            }
            final prevSales = baseline?.previousMonthSalesEgp ?? 0.0;
            final lastYearSales = baseline?.lastYearSameMonthSalesEgp ?? 0.0;
            final simLift = baseline?.lift ??
                computeRoiLift(
                  currentSalesEgp: baseline?.currentMonthSalesEgp ?? 0.0,
                  lastYearSameMonthSalesEgp: lastYearSales,
                  marketingSpendEgp: 0,
                  target: RoiMonthKey(simYear, simMonth),
                );
            final projection = RoiSimulatorProjection(
              historicalRomi: historicalRomi,
              baselineSalesEgp: simLift.baselineSalesEgp,
              previousMonthSalesEgp: prevSales,
              lastYearSalesEgp: lastYearSales,
              budgetEgp: proposedBudget,
            );
            const noCampaigns = 'لا توجد حملات سابقة لحساب العائد';
            String moneyOrDash(double? v) =>
                v == null ? '—' : CurrencyFormatter.formatEGP(v, isolate: true);
            String liftAndPct(double? lift, double? pct) {
              if (lift == null) return '—';
              if (pct == null) {
                return CurrencyFormatter.formatEGP(lift, isolate: true);
              }
              final amt = CurrencyFormatter.formatEGP(lift)
                  .replaceAll(kLri, '')
                  .replaceAll(kPdi, '');
              final p = CurrencyFormatter.formatSignedPct(pct)
                  .replaceAll(kLri, '')
                  .replaceAll(kPdi, '');
              return ltrIsolate('$amt ($p)');
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                shape: const RoundedRectangleBorder(
                    borderRadius: M3Shape.radiusXl),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: M3Shape.radiusMd,
                      ),
                      child: Icon(
                        Icons.auto_graph_rounded,
                        color: colorScheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'محاكي العائد التسويقي الذكي',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'اختبر تأثير الميزانية التسويقية المقترحة على نمو المبيعات الشهري والسنوي',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                insetPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 24.0),
                content: Builder(builder: (dialogMediaCtx) {
                  final maxW = MediaQuery.sizeOf(dialogMediaCtx).width - 32.0;
                  final dialogW =
                      maxW < 560.0 ? (maxW < 0 ? 0.0 : maxW) : 560.0;
                  final rawH = MediaQuery.sizeOf(dialogMediaCtx).height - 160.0;
                  final maxH = rawH < 240.0 ? 240.0 : rawH;
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: dialogW,
                      maxHeight: maxH,
                    ),
                    child: SingleChildScrollView(
                      child: SizedBox(
                        width: dialogW,
                        child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: M3Dropdown<String>(
                              value: simChain,
                              label: 'السلسلة',
                              expand: true,
                              options: m3OptionsFromMenuItems<String>(
                                  _availableChains
                                      .map((c) => DropdownMenuItem(
                                          value: c, child: Text(c)))
                                      .toList()),
                              onChanged: m3Legacy<String>((v) {
                                if (v != null)
                                  setDialogState(() => simChain = v);
                              }),
                            ),
                          ),
                          const SizedBox(width: 12.0),
                          Expanded(
                            child: M3Dropdown<int>(
                              value: simMonth,
                              label: 'الشهر',
                              expand: true,
                              options: m3OptionsFromMenuItems<int>(
                                  List.generate(12, (idx) {
                                final m = idx + 1;
                                return DropdownMenuItem(
                                  value: m,
                                  child: Text(
                                      MarketingExpenseItem.monthNamesAr[m] ?? ''),
                                );
                              })),
                              onChanged: m3Legacy<int>((v) {
                                if (v != null)
                                  setDialogState(() => simMonth = v);
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14.0),
                      TextField(
                        controller: budgetCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'الميزانية التسويقية المقترحة للشهر (ج.م)',
                          prefixIcon:
                              Icon(Icons.account_balance_wallet_rounded),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (val) {
                          final parsed =
                              double.tryParse(val.replaceAll(',', '').trim());
                          if (parsed != null && parsed >= 0) {
                            setDialogState(() => proposedBudget = parsed);
                          }
                        },
                      ),
                      const SizedBox(height: 18.0),
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withOpacity(0.45),
                          borderRadius: M3Shape.radiusLg,
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'النتائج المتوقعة بناءً على حساسية المبيعات التاريخية لـ ${ltrIsolate(simChain)}:',
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (!projection.hasHistoricalRomi) ...[
                              const SizedBox(height: 8.0),
                              Text(
                                noCampaigns,
                                key: const ValueKey('roi_sim_no_campaigns'),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12.0),
                            Text(
                              simLift.methodAr,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10.0),
                            _buildSimMetricRow(
                              'مبيعات الأساس بدون حملة:',
                              simLift.available
                                  ? moneyOrDash(simLift.baselineSalesEgp)
                                  : '—',
                              colorScheme.onSurface,
                            ),
                            const SizedBox(height: 6.0),
                            _buildSimMetricRow(
                              'مبيعات الشهر السابق:',
                              prevSales > 0
                                  ? moneyOrDash(prevSales)
                                  : '—',
                              colorScheme.onSurface,
                            ),
                            const SizedBox(height: 6.0),
                            _buildSimMetricRow(
                              'مبيعات نفس الشهر بالعام الماضي:',
                              lastYearSales > 0
                                  ? moneyOrDash(lastYearSales)
                                  : '— لا توجد بيانات للعام السابق',
                              colorScheme.onSurface,
                            ),
                            const Divider(height: 20.0),
                            _buildSimMetricRow(
                              'المبيعات المتوقعة بعد الحملة:',
                              moneyOrDash(projection.projectedSalesEgp),
                              colorScheme.primary,
                              isBold: true,
                            ),
                            const SizedBox(height: 6.0),
                            _buildSimMetricRow(
                              'الزيادة المتوقعة عن الأساس:',
                              liftAndPct(projection.projectedLiftEgp,
                                  projection.liftVsBaselinePct),
                              M3Palette.success,
                              isBold: true,
                            ),
                            const SizedBox(height: 6.0),
                            _buildSimMetricRow(
                              'الزيادة المتوقعة عن الشهر السابق:',
                              liftAndPct(projection.momLiftEgp, projection.momGrowthPct),
                              M3Palette.success,
                              isBold: true,
                            ),
                            const SizedBox(height: 6.0),
                            _buildSimMetricRow(
                              'الزيادة المتوقعة عن العام السابق:',
                              !projection.hasHistoricalRomi
                                  ? '—'
                                  : (lastYearSales > 0
                                      ? liftAndPct(projection.yoyLiftEgp,
                                          projection.yoyGrowthPct)
                                      : '— لا توجد بيانات للعام السابق'),
                              M3Palette.info,
                              isBold: true,
                            ),
                            const SizedBox(height: 6.0),
                            _buildSimMetricRow(
                              'العائد لكل 1 جنيه تسويق:',
                              projection.romiMultiple == null
                                  ? '—'
                                  : ltrIsolate(
                                      '${projection.romiMultiple!.toStringAsFixed(2)}x',
                                    ) +
                                      ' (كل 1 ج.م يحقق ' +
                                      ltrIsolate(
                                        projection.romiMultiple!
                                            .toStringAsFixed(2),
                                      ) +
                                      ' ج.م نمو مبيعات)',
                              M3Palette.violet,
                              isBold: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                        ),
                      ),
                    ),
                  );
                }),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('إغلاق'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSimMetricRow(String label, String value, Color valueColor,
      {bool isBold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label,
              maxLines: 2,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                  fontSize: M3FontSize.labelMediumPlus,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8.0),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 3,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize:
                  isBold ? M3FontSize.bodyMedium : M3FontSize.labelMediumPlus,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  void _openCampaignDrillDownModal(MonthlyChainRoiSummary summary) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusXl),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: summary.verdictColor.withOpacity(0.15),
                    borderRadius: M3Shape.radiusMd,
                  ),
                  child:
                      Icon(Icons.insights_rounded, color: summary.verdictColor),
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تحليل أثر الحملة التسويقية: ${summary.chainName} - ${summary.monthNameAr} ${summary.year}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${summary.chainName} | ${summary.monthNameEn} ${summary.year} Campaign ROI Breakdown',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 680.0,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Summary comparison boxes
                    M3EqualHeightGrid(
                      key: const ValueKey('tm_drill_cards'),
                      columns: 2,
                      spacing: M3Spacing.s12,
                      runSpacing: M3Spacing.s12,
                      children: [
                        _buildMiniDrillCard(
                          titleAr: 'إجمالي المصروفات بالشهر',
                          titleEn: 'Campaign Spend',
                          value: CurrencyFormatter.formatEGP(
                              summary.marketingSpendEgp),
                          sub: _itemsCount(summary.activitiesCount),
                          color: M3Palette.violet,
                        ),
                        _buildMiniDrillCard(
                          titleAr: 'مبيعات الشهر الحالي',
                          titleEn: 'Current Month Sales',
                          value: CurrencyFormatter.formatEGP(
                              summary.currentMonthSalesEgp),
                          sub:
                              'نسبة الصرف: ${summary.spendToSalesRatioPct.toStringAsFixed(1)}% من المبيعات',
                          color: colorScheme.primary,
                        ),
                        _buildMiniDrillCard(
                          titleAr: 'مبيعات الأساس بدون حملة',
                          titleEn: 'Expected sales without the campaign',
                          value: summary.hasBaseline
                              ? CurrencyFormatter.formatEGP(summary.baselineSalesEgp!)
                              : '—',
                          sub: summary.baselineMethodAr,
                          color: colorScheme.primary,
                        ),
                        _buildMiniDrillCard(
                          titleAr: 'الزيادة عن الأساس',
                          titleEn: 'Incremental lift vs baseline',
                          value: summary.hasBaseline
                              ? '${(summary.incrementalLiftEgp ?? 0) >= 0 ? '+' : ''}${CurrencyFormatter.formatEGP(summary.incrementalLiftEgp!)}'
                              : '—',
                          sub: summary.hasBaseline && summary.liftVsBaselinePct != null
                              ? '${CurrencyFormatter.formatSignedPct(summary.liftVsBaselinePct!)} عن الأساس'
                              : kRoiBaselineUnavailableAr,
                          color: !summary.hasBaseline
                              ? M3Palette.neutral
                              : ((summary.incrementalLiftEgp ?? 0) >= 0
                                  ? M3Palette.success
                                  : M3Palette.danger),
                        ),
                        _buildMiniDrillCard(
                          titleAr: 'النمو عن الشهر السابق (MoM)',
                          titleEn:
                              'vs. Previous Month (${CurrencyFormatter.formatEGP(summary.previousMonthSalesEgp)})',
                          value:
                              '${summary.momLiftEgp >= 0 ? '+' : ''}${CurrencyFormatter.formatEGP(summary.momLiftEgp)}',
                          sub:
                              '${CurrencyFormatter.formatSignedPct(summary.momGrowthPct)} MoM Growth',
                          color: summary.momGrowthPct >= 0
                              ? M3Palette.success
                              : M3Palette.danger,
                        ),
                        _buildMiniDrillCard(
                          titleAr: 'النمو عن نفس الشهر بالعام السابق (YoY)',
                          titleEn: summary.hasYoY
                              ? 'vs. Last Year (${CurrencyFormatter.formatEGP(summary.lastYearSameMonthSalesEgp)})'
                              : 'vs. Last Year (—)',
                          value: summary.hasYoY
                              ? '${summary.yoyLiftEgp >= 0 ? '+' : ''}${CurrencyFormatter.formatEGP(summary.yoyLiftEgp)}'
                              : '—',
                          sub: summary.hasYoY
                              ? '${CurrencyFormatter.formatSignedPct(summary.yoyGrowthPct)} YoY Growth'
                              : 'لا توجد بيانات للعام السابق',
                          color: summary.yoyGrowthPct >= 0
                              ? M3Palette.info
                              : M3Palette.danger,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16.0),
                    Container(
                      padding: const EdgeInsets.all(14.0),
                      decoration: BoxDecoration(
                        color: summary.verdictColor.withOpacity(0.1),
                        borderRadius: M3Shape.radiusMd,
                        border: Border.all(
                            color: summary.verdictColor.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.verified_rounded,
                              color: summary.verdictColor),
                          const SizedBox(width: 10.0),
                          Expanded(
                            child: Text(
                              summary.hasBaseline && summary.romiMultiple != null
                                  ? 'التقييم التحليلي: ${summary.verdictAr} — الزيادة عن الأساس ${CurrencyFormatter.formatEGP(summary.incrementalLiftEgp!)} (ROMI ${summary.romiMultiple!.toStringAsFixed(2)}x). ${summary.baselineMethodAr}'
                                  : 'التقييم التحليلي: ${summary.verdictAr} — ${summary.lift.unavailableMessageAr ?? kRoiBaselineUnavailableAr}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: summary.verdictColor,
                                fontSize: M3FontSize.labelMediumPlus,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    Text(
                      'بنود المصروفات المسجلة في هذا الشهر (${summary.expenses.length}):',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8.0),
                    ...summary.expenses.map((exp) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8.0),
                        elevation: 0,
                        color: colorScheme.surfaceContainerHighest
                            .withOpacity(0.35),
                        shape: RoundedRectangleBorder(
                          borderRadius: M3Shape.radiusMd,
                          side: BorderSide(
                              color:
                                  colorScheme.outlineVariant.withOpacity(0.5)),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                exp.category.color.withOpacity(0.15),
                            child: Icon(exp.category.icon,
                                color: exp.category.color, size: 20.0),
                          ),
                          title: Text(
                            exp.campaignTitle,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: M3FontSize.bodyCompact),
                          ),
                          subtitle: Text(
                            '${exp.category.labelAr} • البراند: ${exp.brandName} • الجهة: ${exp.vendorOrAgency}',
                            style:
                                const TextStyle(fontSize: M3FontSize.bodySmall),
                          ),
                          trailing: Text(
                            CurrencyFormatter.formatEGP(exp.amountEgp),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: M3FontSize.bodyMedium,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniDrillCard({
    required String titleAr,
    required String titleEn,
    required String value,
    required String sub,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: M3Shape.radiusMd,
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titleAr,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: M3FontSize.bodySmallPlus)),
          Text(titleEn,
              style: TextStyle(
                  fontSize: M3FontSize.labelSmall,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 6.0),
          Text(
            value,
            style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: M3FontSize.titleMediumPlus,
                color: color),
          ),
          const SizedBox(height: 2.0),
          Text(sub,
              style: const TextStyle(
                  fontSize: M3FontSize.labelSmallPlus,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _exportExcelReport() {
    final summaries = _monthlyRoiSummaries;
    final headers = [
      'Year',
      'Month (AR)',
      'Month (EN)',
      'Retail Chain',
      'Activities Count',
      'Marketing Spend (EGP)',
      'Previous Month Sales (EGP)',
      'Campaign Month Sales (EGP)',
      'Baseline Sales (EGP)',
      'Incremental Lift vs Baseline (EGP)',
      'Lift vs Baseline (%)',
      'Baseline Method',
      'MoM Sales Lift (EGP)',
      'MoM Growth (%)',
      'Last Year Same Month Sales (EGP)',
      'YoY Sales Lift (EGP)',
      'YoY Growth (%)',
      'Spend-to-Sales Ratio (%)',
      'ROMI Multiple (x)',
      'Net ROI (%)',
      'Evaluation Verdict',
    ];

    final rows = summaries.map((s) {
      return [
        s.year,
        s.monthNameAr,
        s.monthNameEn,
        s.chainName,
        s.activitiesCount,
        s.marketingSpendEgp.toStringAsFixed(0),
        s.previousMonthSalesEgp.toStringAsFixed(0),
        s.currentMonthSalesEgp.toStringAsFixed(0),
        s.hasBaseline ? s.baselineSalesEgp!.toStringAsFixed(0) : '—',
        s.hasBaseline ? s.incrementalLiftEgp!.toStringAsFixed(0) : '—',
        s.hasBaseline && s.liftVsBaselinePct != null
            ? '${s.liftVsBaselinePct!.toStringAsFixed(1)}%'
            : '—',
        s.baselineMethodAr,
        s.momLiftEgp.toStringAsFixed(0),
        '${s.momGrowthPct.toStringAsFixed(1)}%',
        s.lastYearSameMonthSalesEgp.toStringAsFixed(0),
        s.hasYoY ? s.yoyLiftEgp.toStringAsFixed(0) : '—',
        s.hasYoY ? '${s.yoyGrowthPct.toStringAsFixed(1)}%' : '—',
        '${s.spendToSalesRatioPct.toStringAsFixed(1)}%',
        s.romiMultiple != null ? '${s.romiMultiple!.toStringAsFixed(2)}x' : '—',
        s.netRoiPct != null ? '${s.netRoiPct!.toStringAsFixed(0)}%' : '—',
        s.verdictAr,
      ];
    }).toList();

    final csv = ExcelExportService.generateCsv(headers: headers, rows: rows);
    ExcelExportService.downloadCsv(
        'Trade_Marketing_ROI_Growth_Report.xlsx', csv);
    M3Feedback.showSuccess(
      context,
      'تم تصدير تقرير العائد التسويقي ونمو المبيعات (Trade_Marketing_ROI_Growth_Report.xlsx) بنجاح',
    );
  }

  void _printPdfReport() {
    final summaries = _monthlyRoiSummaries;
    final totalSpend =
        summaries.fold<double>(0.0, (s, e) => s + e.marketingSpendEgp);
    final totalMomLift =
        summaries.fold<double>(0.0, (s, e) => s + e.momLiftEgp);

    final headers = [
      'الشهر والسنة',
      'السلسلة',
      'المصروف التسويقي',
      'مبيعات الشهر السابق',
      'مبيعات شهر الحملة',
      'مبيعات الأساس',
      'الزيادة عن الأساس',
      'النمو الشهري (MoM)',
      'النمو السنوي (YoY)',
      'العائد (ROMI)',
      'التقييم',
    ];

    final rows = summaries.map((s) {
      return [
        '${s.monthNameAr} ${s.year}',
        s.chainName,
        CurrencyFormatter.formatEGP(s.marketingSpendEgp),
        CurrencyFormatter.formatEGP(s.previousMonthSalesEgp),
        CurrencyFormatter.formatEGP(s.currentMonthSalesEgp),
        s.hasBaseline
            ? CurrencyFormatter.formatEGP(s.baselineSalesEgp!)
            : '—',
        s.hasBaseline
            ? CurrencyFormatter.formatEGP(s.incrementalLiftEgp!)
            : '—',
        '${s.momGrowthPct >= 0 ? '+' : ''}${s.momGrowthPct.toStringAsFixed(1)}%',
        s.hasYoY
            ? '${s.yoyGrowthPct >= 0 ? '+' : ''}${s.yoyGrowthPct.toStringAsFixed(1)}%'
            : '—',
        s.romiMultiple != null ? '${s.romiMultiple!.toStringAsFixed(2)}x' : '—',
        s.verdictAr,
      ];
    }).toList();

    final htmlContent = ExcelExportService.generatePrintableReport(
      title:
          'تقرير العائد على المصروفات التسويقية والترويجية (Trade Marketing & Promo ROI)',
      headers: headers,
      rows: rows,
      metadata: {
        'إجمالي الإنفاق التسويقي': CurrencyFormatter.formatEGP(totalSpend),
        'إجمالي نمو المبيعات الشهري (MoM)':
            CurrencyFormatter.formatEGP(totalMomLift),
      },
    );
    ExcelExportService.downloadHtml(
        'Trade_Marketing_ROI_Report.html', htmlContent);
    M3Feedback.showInfo(
        context, 'تم تجهيز وتحميل تقرير الـ PDF القابل للطباعة');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final summaries = _monthlyRoiSummaries;
    final expenses = _filteredExpenses;

    // Aggregate top KPI metrics
    final totalSpend = expenses.fold<double>(0.0, (s, e) => s + e.amountEgp);
    final totalCurrentSales =
        summaries.fold<double>(0.0, (s, e) => s + e.currentMonthSalesEgp);
    final totalPrevSales =
        summaries.fold<double>(0.0, (s, e) => s + e.previousMonthSalesEgp);
    final totalLastYearSales =
        summaries.fold<double>(0.0, (s, e) => s + e.lastYearSameMonthSalesEgp);

    final totalMomLift = totalCurrentSales - totalPrevSales;
    // MoM needs a previous-month Sell-Out baseline (and thus at least one
    // campaign row). Empty expenses → fake +0.0% must not be shown.
    final totalMomAvailable = totalPrevSales > 0;
    final totalMomPct =
        totalMomAvailable ? (totalMomLift / totalPrevSales) * 100.0 : 0.0;
    final momUnavailableNote = summaries.isEmpty
        ? 'لا توجد حملات للمقارنة'
        : 'لا توجد بيانات للمقارنة';

    // YoY compares the same months only: current sales count only for
    // rows whose same month last year has Sell-Out.
    final totalYoyCurrentSales = summaries
        .where((e) => e.hasYoY)
        .fold<double>(0.0, (s, e) => s + e.currentMonthSalesEgp);
    final totalYoyAvailable = totalLastYearSales > 0;
    final totalYoyLift = totalYoyCurrentSales - totalLastYearSales;
    final totalYoyPct =
        totalYoyAvailable ? (totalYoyLift / totalLastYearSales) * 100.0 : 0.0;

    final baselineRows = summaries.where((e) => e.hasBaseline).toList();
    final totalIncrementalLift = baselineRows.fold<double>(
        0.0, (s, e) => s + (e.incrementalLiftEgp ?? 0));
    final spendWithBaseline = baselineRows.fold<double>(
        0.0, (s, e) => s + e.marketingSpendEgp);
    final double? overallRomi =
        spendWithBaseline > 0 ? totalIncrementalLift / spendWithBaseline : null;
    final spendRatioPct =
        totalCurrentSales > 0 ? (totalSpend / totalCurrentSales) * 100.0 : 0.0;

    final isCompact = MediaQuery.sizeOf(context).width < 600.0;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: M3ToolbarButtonTheme(
        child: SingleChildScrollView(
          padding: isCompact ? M3Spacing.pSm : M3Spacing.pMd,
          child: M3ContentBoundary(
            maxWidth: double.infinity,
            alignment: AlignmentDirectional.topStart,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header & MD3 Large Responsive Tab Bar (Identical padding/margin to Sell-In & Sell-Out)
                if (_loading || _uploading) const LinearProgressIndicator(),
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: MaterialBanner(
                      content: Text(
                          'تعذر تحميل بيانات التسويق من الخادم: $_loadError'),
                      leading: Icon(Icons.cloud_off_rounded,
                          color: colorScheme.error),
                      actions: [
                        TextButton(
                            onPressed: _reload,
                            child: const Text('Retry / إعادة المحاولة')),
                      ],
                    ),
                  ),
                _buildHeaderAndTabs(theme, colorScheme),
                M3Spacing.gapMD,

                // 2. Four Symmetrical Full-Width Executive KPI Cards (Arabic on top, English below)
                _buildSymmetricalKpiRow(
                  theme: theme,
                  colorScheme: colorScheme,
                  totalSpend: totalSpend,
                  activitiesCount: expenses.length,
                  totalMomLift: totalMomLift,
                  totalMomPct: totalMomPct,
                  totalMomAvailable: totalMomAvailable,
                  momUnavailableNote: momUnavailableNote,
                  totalYoyLift: totalYoyLift,
                  totalYoyPct: totalYoyPct,
                  totalYoyAvailable: totalYoyAvailable,
                  overallRomi: overallRomi,
                  spendRatioPct: spendRatioPct,
                ),
                M3Spacing.gapMD,

                // 3. Symmetrical Filter & Action Toolbar (All English Action Buttons in MD3 Large)
                _buildFilterAndActionToolbar(theme, colorScheme),
                M3Spacing.gapMD,

                // 4. Active Tab Content
                if (_activeTab == 0)
                  _buildRoiGrowthMatrixTab(theme, colorScheme, summaries)
                else if (_activeTab == 1)
                  _buildExpenseLedgerTab(theme, colorScheme, expenses)
                else
                  _buildCategoryAnalyticsTab(
                      theme, colorScheme, expenses, summaries),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderAndTabs(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const M3PageHeader(
          title: 'التسويق التجاري والعائد',
          subtitle: 'Trade Marketing & Promo ROI',
          description:
              'متابعة إيجار الفلورات، الدعاية، الإعلانات، الهدايا، والإيفنتات شهرياً وقياس أثرها الفعلي على نمو المبيعات (MoM & YoY)',
        ),
        M3Spacing.gapSM,
        // 100% Responsive Full-Width MD3 Large Tab Bar (3 Symmetrical Tabs in English)
        M3ResponsiveTabBar<int>(
          textDirection: TextDirection.ltr,
          selectedValue: _activeTab,
          items: const [
            M3ResponsiveTabItem<int>(
              value: 0,
              icon: Icons.trending_up_rounded,
              selectedIcon: Icons.trending_up_rounded,
              label: 'ROI & Growth Matrix',
            ),
            M3ResponsiveTabItem<int>(
              value: 1,
              icon: Icons.receipt_long_rounded,
              selectedIcon: Icons.receipt_long_rounded,
              label: 'Campaigns & Expense Ledger',
            ),
            M3ResponsiveTabItem<int>(
              value: 2,
              icon: Icons.pie_chart_outline_rounded,
              selectedIcon: Icons.pie_chart_rounded,
              label: 'Activity & Brand Analytics',
            ),
          ],
          onChanged: (next) {
            setState(() => _activeTab = next);
          },
        ),
      ],
    );
  }

  Widget _buildSymmetricalKpiRow({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required double totalSpend,
    required int activitiesCount,
    required double totalMomLift,
    required double totalMomPct,
    required bool totalMomAvailable,
    required String momUnavailableNote,
    required double totalYoyLift,
    required double totalYoyPct,
    required bool totalYoyAvailable,
    required double? overallRomi,
    required double spendRatioPct,
  }) {
    String pct(double v) =>
        CurrencyFormatter.formatSignedPct(v, plusForZero: true);
    final momUp = totalMomLift >= 0;
    final yoyUp = totalYoyLift >= 0;
    // Shared Sell-Out KPI card + grid (same geometry, fonts and icon size).
    // Values stay on one line; percentages and counts go on the detail line.
    final cards = [
      M3SummaryKpiCard(
        key: const ValueKey('tm_kpi_spend'),
        valueKey: const ValueKey('tm_kpi_spend_value'),
        title: 'المصروفات الترويجية',
        value: CurrencyFormatter.formatCompactEGP(totalSpend),
        subtitle:
            '${tmActivitiesCount(activitiesCount)} • ${spendRatioPct.toStringAsFixed(1)}% من المبيعات',
        icon: Icons.campaign_rounded,
        color: M3Palette.violet,
      ),
      M3SummaryKpiCard(
        key: const ValueKey('tm_kpi_mom'),
        valueKey: const ValueKey('tm_kpi_mom_value'),
        subtitleKey: const ValueKey('tm_kpi_mom_detail'),
        title: 'النمو عن الشهر السابق',
        value: totalMomAvailable
            ? '${momUp ? '+' : ''}${CurrencyFormatter.formatCompactEGP(totalMomLift)}'
            : '—',
        subtitle: totalMomAvailable
            ? '${pct(totalMomPct)} عن الشهر السابق'
            : momUnavailableNote,
        icon: !totalMomAvailable
            ? Icons.trending_flat_rounded
            : (momUp
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded),
        color: !totalMomAvailable
            ? M3Palette.info
            : (momUp ? M3Palette.success : M3Palette.danger),
      ),
      M3SummaryKpiCard(
        key: const ValueKey('tm_kpi_yoy'),
        valueKey: const ValueKey('tm_kpi_yoy_value'),
        subtitleKey: const ValueKey('tm_kpi_yoy_detail'),
        title: 'النمو عن العام السابق',
        value: totalYoyAvailable
            ? '${yoyUp ? '+' : ''}${CurrencyFormatter.formatCompactEGP(totalYoyLift)}'
            : '—',
        subtitle: totalYoyAvailable
            ? '${pct(totalYoyPct)} عن نفس الشهر'
            : 'لا توجد بيانات للعام السابق',
        icon: Icons.calendar_month_rounded,
        color: !totalYoyAvailable || yoyUp ? M3Palette.info : M3Palette.danger,
      ),
      M3SummaryKpiCard(
        key: const ValueKey('tm_kpi_romi'),
        valueKey: const ValueKey('tm_kpi_romi_value'),
        title: 'العائد على الإنفاق',
        titleTooltip: kRoiLiftMethodExplainerAr,
        cardTooltip: kRoiLiftMethodExplainerAr,
        value: overallRomi == null
            ? '—'
            : '${overallRomi.toStringAsFixed(2)}x',
        subtitle: overallRomi == null
            ? kRoiBaselineUnavailableAr
            : 'كل 1 ج.م حقق ${overallRomi.toStringAsFixed(2)} ج.م نمو',
        icon: Icons.workspace_premium_rounded,
        color: M3Palette.warning,
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      return M3EqualHeightGrid(
        key: const ValueKey('tm_kpi_cards_row'),
        columns: w >= 960 ? 4 : (w >= 580 ? 2 : 1),
        spacing: M3Spacing.sm,
        runSpacing: M3Spacing.sm,
        children: cards,
      );
    });
  }

  Widget _buildFilterAndActionToolbar(
      ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.6)),
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
              // Filters (English labels for symmetry)
              Directionality(
                textDirection: TextDirection.ltr,
                child: M3FlexWrap(
                  spacing: 10.0,
                  runSpacing: 10.0,
                  children: [
                    // Chain Filter
                    // Sized from its longest option (no clipping, v126).
                    M3Dropdown<String>(
                      value: _selectedChain,
                      label: 'Retail Chain',
                      fitOptions: true,
                      leadingIcon: Icons.storefront_rounded,
                      options: m3OptionsFromMenuItems<String>([
                        const DropdownMenuItem(
                            value: 'all', child: Text('All Chains')),
                        ..._availableChains.map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)),
                        ),
                      ]),
                      onChanged: m3Legacy<String>((v) {
                        if (v != null) setState(() => _selectedChain = v);
                      }),
                    ),
                    // Month Filter
                    // Sized from its longest option (no clipping, v126).
                    M3Dropdown<int>(
                      value: _selectedMonth,
                      label: 'Month',
                      fitOptions: true,
                      leadingIcon: Icons.event_note_rounded,
                      options: m3OptionsFromMenuItems<int>([
                        const DropdownMenuItem(
                            value: 0, child: Text('All Months')),
                        ...List.generate(12, (idx) {
                          final m = idx + 1;
                          return DropdownMenuItem(
                            value: m,
                            child: Text(MarketingExpenseItem.monthNamesEn[m]!),
                          );
                        }),
                      ]),
                      onChanged: m3Legacy<int>((v) {
                        if (v != null) setState(() => _selectedMonth = v);
                      }),
                    ),
                    // Year Filter — same size as the shared year dropdown
                    // (Sell-Out 'سنة البيانات': 190dp with the calendar icon),
                    // so "2026" / "All Years" never clip.
                    SizedBox(
                      width: kYearDropdownWidth,
                      child: M3Dropdown<int>(
                        value: _selectedYear,
                        label: 'Year',
                        leadingIcon: Icons.calendar_today_rounded,
                        expand: true,
                        options: m3OptionsFromMenuItems<int>([
                          const DropdownMenuItem(
                              value: 0, child: Text('All Years')),
                          const DropdownMenuItem(
                              value: 2026, child: Text('2026')),
                          const DropdownMenuItem(
                              value: 2025, child: Text('2025')),
                        ]),
                        onChanged: m3Legacy<int>((v) {
                          if (v != null) setState(() => _selectedYear = v);
                        }),
                      ),
                    ),
                    // Activity Category Filter
                    // Sized from its longest option (no clipping, v126).
                    M3Dropdown<String>(
                      value: _selectedCategoryId,
                      label: 'Activity Type',
                      fitOptions: true,
                      leadingIcon: Icons.category_rounded,
                      options: m3OptionsFromMenuItems<String>([
                        const DropdownMenuItem(
                            value: 'all', child: Text('All Activity Types')),
                        ...MarketingExpenseCategory.values.map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.labelEn,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ]),
                      onChanged: m3Legacy<String>((v) {
                        if (v != null) setState(() => _selectedCategoryId = v);
                      }),
                    ),
                    // Search Box
                    M3FlexWrapFill(
                      // v127: fills the rest of the filter row, never
                      // narrower than its full placeholder.
                      child: M3SearchFieldWidth(
                          hintText: 'Search campaign, brand...',
                          child: TextField(
                            onChanged: (val) =>
                                setState(() => _searchQuery = val),
                            decoration: const InputDecoration(
                              hintText: 'Search campaign, brand...',
                              prefixIcon:
                                  Icon(Icons.search_rounded, size: 18.0),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12.0, vertical: 11.0),
                              border: OutlineInputBorder(
                                  borderRadius: M3Shape.radiusMd),
                            ),
                          )),
                    ),
                  ],
                ),
              ),

              // 4 Symmetrical Large MD3 Action Buttons in English (Identical padding & margin to Sell-In & Sell-Out)
              Directionality(
                textDirection: TextDirection.ltr,
                child: Wrap(
                  spacing: 10.0,
                  runSpacing: 10.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('btn_add_marketing_expense'),
                      onPressed: () => _openAddOrEditExpenseDialog(),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text('Add Expense'),
                    ),
                    if (_canWrite)
                      FilledButton.tonalIcon(
                        key: const ValueKey('btn_upload_marketing_expenses'),
                        onPressed: _uploading ? null : _pickAndUploadExpenses,
                        icon: _uploading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.upload_file_rounded),
                        label: Text(
                            _uploading ? 'Uploading…' : 'Upload Excel/CSV'),
                      ),
                    if (_canWrite)
                      TextButton.icon(
                        key: const ValueKey('btn_download_expense_template'),
                        onPressed: _downloadTemplate,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('CSV Template'),
                      ),
                    FilledButton.tonalIcon(
                      key: const ValueKey('btn_roi_simulator'),
                      onPressed: _openRoiSimulatorDialog,
                      icon: const Icon(Icons.auto_graph_rounded),
                      label: const Text('ROI Simulator'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('btn_export_roi_excel'),
                      onPressed: _exportExcelReport,
                      icon: const Icon(Icons.table_view_rounded),
                      label: const Text('Export Excel'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('btn_print_roi_pdf'),
                      onPressed: _printPdfReport,
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('Print PDF'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Shared table helpers (Sell-Out table rules) ----------------------
  // Headers and cells centred except the name column; text wraps up to 3
  // lines inside a bounded cell; full text in a tooltip only if clipped.
  /// Cell width cap (text wraps inside it). Sortable headers get 36dp less:
  /// DataTable adds the 18dp arrow and the table the same spacer opposite.
  static const double _cellW = 80.0;

  Widget _hdr(String label,
      {TextAlign align = TextAlign.center,
      double maxWidth = _cellW,
      String? sortKey,
      String? activeSort,
      bool asc = true,
      ValueChanged<String>? onSort}) {
    final cs = Theme.of(context).colorScheme;
    final selected = sortKey != null && sortKey == activeSort;
    final text = M3WrapText(label,
        textAlign: align,
        style: TextStyle(
            fontWeight: FontWeight.w800, color: selected ? cs.primary : null));
    if (sortKey == null || onSort == null) {
      return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth), child: text);
    }
    // Inline 16dp sort icon (no DataTable arrow + mirrored spacer), so a
    // sortable label keeps almost the full column width.
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: InkWell(
        key: ValueKey('tm_sort_$sortKey'),
        borderRadius: M3Shape.radiusSm,
        onTap: () => onSort(sortKey),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: text),
            const SizedBox(width: M3Spacing.s2),
            Icon(
              selected
                  ? (asc
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded)
                  : Icons.unfold_more_rounded,
              size: 16.0,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(Widget child, {double maxWidth = _cellW, bool start = false}) =>
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: M3Spacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment:
                start ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [child],
          ),
        ),
      );

  Widget _lines(List<Widget> children, {bool start = false}) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            start ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: children,
      );

  Widget _txt(String text,
          {TextStyle? style, bool start = false, int maxLines = 3}) =>
      M3WrapText(text,
          maxLines: maxLines,
          textAlign: start ? TextAlign.start : TextAlign.center,
          style: style);

  /// Short 8dp status chip (M3ChipSurface geometry).
  Widget _chip(String label, Color color, {Key? key, IconData? icon}) =>
      M3ChipSurface(
        key: key,
        color: color.withOpacity(0.12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16.0, color: color),
              const SizedBox(width: M3Spacing.xxs),
            ],
            Flexible(
              child: M3WrapText(
                label,
                maxLines: 3,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: M3FontSize.labelSmallPlus,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );

  /// Short verdict label for the chip + its description under it (display
  /// only; the verdict itself comes from the model unchanged).
  static (String, String) verdictParts(String verdictAr) {
    switch (verdictAr) {
      case 'عائد ممتاز ونمو قياسي':
        return ('ممتاز', 'عائد ممتاز ونمو قياسي');
      case 'حملة ناجحة ونمو إيجابي':
        return ('ناجحة', 'نمو إيجابي');
      case 'نمو متوسط - يحتاج تحسين':
        return ('متوسط', 'يحتاج تحسين');
      case 'عائد ضعيف / مراجعة التكلفة':
        return ('ضعيف', 'راجع التكلفة');
      case 'بدون إنفاق ترويجي':
        return ('بدون إنفاق', 'لا يوجد إنفاق ترويجي');
      case 'لا يمكن حساب العائد':
      case 'لا توجد بيانات للعام السابق':
        return ('غير محسوب', 'لا توجد بيانات للعام السابق');
    }
    return (verdictAr, '');
  }

  static String _itemsCount(int n) => arabicCount(n,
      one: 'بند ترويجي واحد',
      two: 'بندان ترويجيان',
      few: 'بنود ترويجية',
      many: 'بندًا ترويجيًا',
      hundred: 'بند ترويجي');

  String _money(double v) => CurrencyFormatter.formatCompactEGP(v);

  /// TAB 0: Monthly & Chain ROI vs. MoM & YoY Sales Growth Matrix
  Widget _buildRoiGrowthMatrixTab(
    ThemeData theme,
    ColorScheme colorScheme,
    List<MonthlyChainRoiSummary> summaries,
  ) {
    const sortKeys = [
      'month',
      '',
      'spend',
      '',
      'sales',
      'mom',
      'yoy',
      'roi',
      '',
      ''
    ];
    DataColumn col(int i, String label,
            {bool start = false, double maxWidth = _cellW}) =>
        DataColumn(
          headingRowAlignment:
              start ? MainAxisAlignment.start : MainAxisAlignment.center,
          label: _hdr(label,
              align: start ? TextAlign.start : TextAlign.center,
              maxWidth: maxWidth,
              sortKey: sortKeys[i].isEmpty ? null : sortKeys[i],
              activeSort: _matrixSortColumn,
              asc: _matrixSortAsc,
              onSort: _toggleMatrixSort),
        );
    final small = TextStyle(
        fontSize: M3FontSize.labelSmall, color: colorScheme.onSurfaceVariant);
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      padding: const EdgeInsets.all(M3Spacing.sm),
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
                      'مصفوفة المصروفات التسويقية ونمو المبيعات',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: M3Spacing.s2),
                    Text(
                      'العائد يُحسب من الزيادة عن مبيعات نفس الشهر العام السابق (مقارنة موسمية)، مش من المقارنة بالشهر السابق. اضغط على أي صف للتفاصيل • اضغط على عنوان العمود للترتيب',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              M3Spacing.hGapXS,
              M3ChipSurface(
                color: colorScheme.primaryContainer.withOpacity(0.6),
                child: Text(
                  arabicCount(summaries.length,
                      one: 'حملة شهرية واحدة',
                      two: 'حملتان شهريتان',
                      few: 'حملات شهرية',
                      many: 'حملة شهرية',
                      hundred: 'حملة شهرية'),
                  key: const ValueKey('tm_matrix_count'),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: M3FontSize.bodySmall,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          M3Spacing.gapSM,
          if (summaries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(
                child: Text(
                    'لا توجد مصروفات مطابقة للفلتر المحدد. اضغط «إضافة مصروف» لإضافة مصروف تسويقي جديد.'),
              ),
            )
          else
            TableScrollContainer(
              child: DataTable(
                key: const ValueKey('tm_matrix_table'),
                headingRowColor: WidgetStatePropertyAll(
                  colorScheme.surfaceContainerHighest.withOpacity(0.5),
                ),
                headingRowHeight: 64.0,
                dataRowMinHeight: 64.0,
                dataRowMaxHeight: double.infinity,
                columnSpacing: M3Spacing.xs,
                horizontalMargin: M3Spacing.xs,
                columns: [
                  col(0, 'الشهر'),
                  col(1, 'السلسلة', start: true, maxWidth: 104.0),
                  col(2, 'المصروف'),
                  col(3, 'مبيعات الشهر السابق'),
                  col(4, 'مبيعات شهر الحملة'),
                  col(5, 'النمو عن الشهر السابق'),
                  col(6, 'النمو عن العام السابق'),
                  col(7, 'العائد (ROMI)'),
                  col(8, 'تقييم الحملة'),
                  col(9, 'عرض', maxWidth: 48.0),
                ],
                rows: summaries.map((s) {
                  final momPositive = s.momLiftEgp >= 0;
                  final yoyPositive = s.yoyLiftEgp >= 0;
                  final momColor =
                      momPositive ? M3Palette.success : M3Palette.danger;
                  final yoyColor =
                      yoyPositive ? M3Palette.info : M3Palette.danger;
                  final (verdictShort, verdictDesc) = verdictParts(s.verdictAr);
                  void open() => _openCampaignDrillDownModal(s);
                  return DataRow(
                    cells: [
                      DataCell(
                        _cell(_lines([
                          _txt('${s.monthNameAr} ${s.year}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: M3FontSize.bodyCompact)),
                          _txt('${s.monthNameEn} ${s.year}', style: small),
                        ])),
                        onTap: open,
                      ),
                      DataCell(
                        _cell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront_rounded,
                                  size: 18.0, color: colorScheme.primary),
                              const SizedBox(width: M3Spacing.xxs),
                              Flexible(
                                child: _lines([
                                  _txt(s.chainName,
                                      start: true,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800)),
                                  _txt(_itemsCount(s.activitiesCount),
                                      start: true, style: small),
                                ], start: true),
                              ),
                            ],
                          ),
                          maxWidth: 104.0,
                          start: true,
                        ),
                        onTap: open,
                      ),
                      DataCell(_cell(_lines([
                        _txt(_money(s.marketingSpendEgp),
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: M3Palette.violet,
                                fontSize: M3FontSize.bodyCompact)),
                        _txt(
                            '${s.spendToSalesRatioPct.toStringAsFixed(1)}% من المبيعات',
                            style: small),
                      ]))),
                      DataCell(_cell(_txt(_money(s.previousMonthSalesEgp),
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)))),
                      DataCell(_cell(_lines([
                        _txt(_money(s.currentMonthSalesEgp),
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: colorScheme.onSurface,
                                fontSize: M3FontSize.bodyCompact)),
                        _txt(
                            'توريد Sell-In: ${_money(s.currentMonthSellInEgp)}',
                            style: small),
                      ]))),
                      DataCell(_cell(_lines([
                        _chip(
                            '${CurrencyFormatter.formatSignedPct(s.momGrowthPct)} MoM',
                            momColor),
                        const SizedBox(height: M3Spacing.s2),
                        _txt('${momPositive ? '+' : ''}${_money(s.momLiftEgp)}',
                            style: TextStyle(
                                fontSize: M3FontSize.labelSmallPlus,
                                fontWeight: FontWeight.w700,
                                color: momColor)),
                      ]))),
                      DataCell(_cell(s.hasYoY
                          ? _lines([
                              _chip(
                                  '${CurrencyFormatter.formatSignedPct(s.yoyGrowthPct)} YoY',
                                  yoyColor),
                              const SizedBox(height: M3Spacing.s2),
                              _txt(
                                  '${yoyPositive ? '+' : ''}${_money(s.yoyLiftEgp)}',
                                  style: TextStyle(
                                      fontSize: M3FontSize.labelSmallPlus,
                                      fontWeight: FontWeight.w700,
                                      color: yoyColor)),
                            ])
                          : _lines([
                              _txt('—',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              _txt('لا توجد بيانات للعام السابق', style: small),
                            ]))),
                      DataCell(_cell(Tooltip(
                        message: s.hasBaseline
                            ? s.baselineMethodAr
                            : kRoiBaselineUnavailableAr,
                        child: _lines([
                          _txt(
                              s.romiMultiple != null
                                  ? '${s.romiMultiple!.toStringAsFixed(2)}x'
                                  : '—',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: M3FontSize.bodyMediumPlus,
                                  color: s.verdictColor)),
                          _txt(
                              s.netRoiPct != null
                                  ? 'ROI ${CurrencyFormatter.formatSignedPct(s.netRoiPct!, decimals: 0)}'
                                  : (s.hasBaseline
                                      ? s.baselineMethodAr
                                      : kRoiBaselineUnavailableAr),
                              style: small),
                        ]),
                      ))),
                      DataCell(_cell(_lines([
                        _chip(verdictShort, s.verdictColor),
                        if (verdictDesc.isNotEmpty) ...[
                          const SizedBox(height: M3Spacing.s2),
                          _txt(verdictDesc, style: small),
                        ],
                      ]))),
                      DataCell(
                        IconButton(
                          tooltip: 'عرض تفاصيل الحملة والأثر البيعي',
                          icon: Icon(Icons.visibility_rounded,
                              color: colorScheme.primary),
                          onPressed: open,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// TAB 1: Detailed Campaigns & Expense Ledger (Add, Edit, Delete individual items)
  Widget _buildExpenseLedgerTab(
    ThemeData theme,
    ColorScheme colorScheme,
    List<MarketingExpenseItem> expenses,
  ) {
    const sortKeys = ['month', 'chain', 'category', '', '', '', 'amount', ''];
    DataColumn col(int i, String label,
            {bool start = false, double maxWidth = _cellW}) =>
        DataColumn(
          headingRowAlignment:
              start ? MainAxisAlignment.start : MainAxisAlignment.center,
          label: _hdr(label,
              align: start ? TextAlign.start : TextAlign.center,
              maxWidth: maxWidth,
              sortKey: sortKeys[i].isEmpty ? null : sortKeys[i],
              activeSort: _ledgerSortColumn,
              asc: _ledgerSortAsc,
              onSort: _toggleLedgerSort),
        );
    final small = TextStyle(
        fontSize: M3FontSize.labelSmall, color: colorScheme.onSurfaceVariant);
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      padding: const EdgeInsets.all(M3Spacing.sm),
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
                      'سجل المصروفات الترويجية والحملات التفصيلي',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: M3Spacing.s2),
                    Text(
                      'كل بنود الصرف (تأجير فلورات، إعلانات، هدايا، شركات دعاية وإيفنتات) مع التعديل أو الحذف',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              M3Spacing.hGapXS,
              FilledButton.icon(
                onPressed: () => _openAddOrEditExpenseDialog(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add New Expense'),
              ),
            ],
          ),
          M3Spacing.gapSM,
          TableScrollContainer(
            child: DataTable(
              key: const ValueKey('tm_ledger_table'),
              headingRowColor: WidgetStatePropertyAll(
                colorScheme.surfaceContainerHighest.withOpacity(0.5),
              ),
              headingRowHeight: 64.0,
              dataRowMinHeight: 58.0,
              dataRowMaxHeight: double.infinity,
              columnSpacing: M3Spacing.xs,
              horizontalMargin: M3Spacing.xs,
              columns: [
                col(0, 'الشهر', maxWidth: 80.0),
                col(1, 'السلسلة', maxWidth: 100.0),
                col(2, 'نوع النشاط', maxWidth: 116.0),
                col(3, 'البراند', maxWidth: 100.0),
                col(4, 'وصف الحملة / النشاط', start: true, maxWidth: 172.0),
                col(5, 'شركة الدعاية / الجهة', maxWidth: 104.0),
                col(6, 'المبلغ', maxWidth: 84.0),
                col(7, 'إجراءات', maxWidth: 88.0),
              ],
              rows: expenses.map((item) {
                return DataRow(
                  cells: [
                    DataCell(_cell(
                        _txt('${item.monthNameAr} ${item.year}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        maxWidth: 80.0)),
                    DataCell(_cell(
                        _txt(item.chainName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        maxWidth: 100.0)),
                    DataCell(_cell(
                        _chip(item.category.labelAr, item.category.color,
                            icon: item.category.icon),
                        maxWidth: 116.0)),
                    DataCell(_cell(
                        _chip(item.brandName, colorScheme.onSecondaryContainer),
                        maxWidth: 100.0)),
                    DataCell(_cell(
                      _lines([
                        _txt(item.campaignTitle,
                            start: true,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: M3FontSize.labelMediumPlus)),
                        if (item.notes.isNotEmpty)
                          _txt(item.notes, start: true, style: small),
                      ], start: true),
                      maxWidth: 172.0,
                      start: true,
                    )),
                    DataCell(_cell(
                        _txt(item.vendorOrAgency,
                            style: const TextStyle(
                                fontSize: M3FontSize.bodySmallPlus,
                                fontWeight: FontWeight.w600)),
                        maxWidth: 104.0)),
                    DataCell(_cell(_txt(_money(item.amountEgp),
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: M3FontSize.bodyCompact,
                            color: colorScheme.primary)))),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit / تعديل',
                            icon: const Icon(Icons.edit_rounded, size: 20.0),
                            onPressed: () =>
                                _openAddOrEditExpenseDialog(existing: item),
                          ),
                          IconButton(
                            tooltip: 'Delete / حذف',
                            icon: Icon(Icons.delete_outline_rounded,
                                size: 20.0, color: colorScheme.error),
                            onPressed: () async {
                              try {
                                await _repo.deleteExpense(item.id);
                              } catch (e) {
                                if (!mounted) return;
                                M3Feedback.showWarning(
                                    context, 'تعذر حذف المصروف: $e');
                                return;
                              }
                              if (!mounted) return;
                              setState(() {
                                _expenses.removeWhere((e) => e.id == item.id);
                              });
                              _reloadRoiOnly();
                              M3Feedback.showInfo(
                                context,
                                'تم حذف المصروف التسويقي (${item.campaignTitle}) وتحديث حسابات الـ ROI',
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// TAB 2: Activity Category & Brand Spend Efficiency Breakdown
  Widget _buildCategoryAnalyticsTab(
    ThemeData theme,
    ColorScheme colorScheme,
    List<MarketingExpenseItem> expenses,
    List<MonthlyChainRoiSummary> summaries,
  ) {
    final totalSpend = expenses.fold<double>(0.0, (s, e) => s + e.amountEgp);
    final cards = MarketingExpenseCategory.values.map((cat) {
      final catItems = expenses.where((e) => e.category == cat).toList();
      final catSpend = catItems.fold<double>(0.0, (s, e) => s + e.amountEgp);
      final sharePct = totalSpend > 0 ? (catSpend / totalSpend) * 100.0 : 0.0;
      return Container(
        key: ValueKey('tm_cat_${cat.id}'),
        padding: M3SummaryKpiStyle.padding,
        decoration: BoxDecoration(
          color: cat.color.withOpacity(0.06),
          borderRadius: M3Shape.radiusLg,
          border: Border.all(color: cat.color.withOpacity(0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: M3SummaryKpiStyle.iconPadding,
                  decoration: BoxDecoration(
                    color: cat.color.withOpacity(0.12),
                    borderRadius: M3SummaryKpiStyle.iconRadius,
                  ),
                  child: Icon(cat.icon,
                      color: cat.color, size: M3SummaryKpiStyle.iconSize),
                ),
                const SizedBox(width: M3SummaryKpiStyle.iconGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _txt(cat.labelAr,
                          start: true,
                          maxLines: 2,
                          style: M3SummaryKpiStyle.titleStyle(context)),
                      _txt(cat.labelEn,
                          start: true,
                          maxLines: 2,
                          style: TextStyle(
                              fontSize: M3FontSize.labelSmall,
                              color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            M3Spacing.gapXS,
            Text(
              _money(catSpend),
              key: ValueKey('tm_cat_value_${cat.id}'),
              style: M3SummaryKpiStyle.valueStyle(context)
                  ?.copyWith(color: cat.color),
            ),
            const SizedBox(height: M3SummaryKpiStyle.valueGap),
            Text(
              '${sharePct.toStringAsFixed(1)}% من الإنفاق • ${tmActivitiesCount(catItems.length)}',
              style: M3SummaryKpiStyle.subtitleStyle(context),
            ),
            M3Spacing.gapXS,
            ClipRRect(
              borderRadius: M3Shape.radiusFull,
              child: LinearProgressIndicator(
                value: (sharePct / 100.0).clamp(0.0, 1.0),
                minHeight: 8.0,
                backgroundColor: cat.color.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation<Color>(cat.color),
              ),
            ),
          ],
        ),
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(M3Spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'توزيع الميزانية التسويقية حسب نوع النشاط الترويجي',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: M3Spacing.xxs),
          Text(
            'حجم الإنفاق على تأجير الفلورات، شركات الدعاية والإيفنتات، الهدايا المجانية، والإعلانات',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          M3Spacing.gapSM,
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return M3EqualHeightGrid(
              key: const ValueKey('tm_category_grid'),
              columns: w >= 900 ? 3 : (w >= 560 ? 2 : 1),
              spacing: M3Spacing.sm,
              runSpacing: M3Spacing.sm,
              children: cards,
            );
          }),
        ],
      ),
    );
  }
}

/// «نشاط واحد / نشاطان / 3 أنشطة / 11 نشاطًا / 100 نشاط».
String tmActivitiesCount(int n) => arabicCount(n,
    one: 'نشاط واحد',
    two: 'نشاطان',
    few: 'أنشطة',
    many: 'نشاطًا',
    hundred: 'نشاط');

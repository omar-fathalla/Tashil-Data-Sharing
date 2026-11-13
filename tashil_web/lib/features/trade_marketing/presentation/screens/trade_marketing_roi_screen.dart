import 'dart:convert';
import 'package:tashil_web/core/theme/m3_palette.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';

import 'package:flutter/material.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_responsive_tab_bar.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../data/cached_trade_marketing_repository.dart';
import '../../data/trade_marketing_repository.dart';
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
  State<TradeMarketingRoiScreen> createState() => _TradeMarketingRoiScreenState();
}

class _TradeMarketingRoiScreenState extends State<TradeMarketingRoiScreen> with DataRefreshMixin<TradeMarketingRoiScreen> {
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
  late final TradeMarketingRepository _repo =
      widget.repository ??
          CachedTradeMarketingRepository(ApiTradeMarketingRepository(widget.apiClient), widget.apiClient);

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
    'super_admin', 'vendor_admin', 'admin', 'national_sales_manager', 'chain_kam', 'executive',
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
      M3Feedback.showError(context, 'نوع الملف غير مدعوم. يرجى اختيار ملف ‎.xlsx أو ‎.csv');
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
              r.rejectedCount == 0 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
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
                      avatar: Icon(Icons.check_rounded, size: 18, color: cs.primary),
                      label: Text('تم الحفظ: ${r.savedCount}'),
                    ),
                    Chip(
                      key: const ValueKey('chip_upload_rejected'),
                      avatar: Icon(Icons.block_rounded, size: 18, color: cs.error),
                      label: Text('مرفوض: ${r.rejectedCount}'),
                    ),
                  ]),
                  if (r.rejectedReasons.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('الصفوف المرفوضة وأسبابها:', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final reason in r.rejectedReasons)
                            ListTile(
                              dense: true,
                              leading: Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
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
        _expenses = List<MarketingExpenseItem>.from(results[0] as List<MarketingExpenseItem>);
        _baselines.clear();
        for (final b in results[1] as List<TradeMarketingSalesBaseline>) {
          _baselines[tradeMarketingBaselineKey(b.year, b.month, b.chainName)] = b;
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
          _baselines[tradeMarketingBaselineKey(b.year, b.month, b.chainName)] = b;
        }
      });
    } catch (_) {}
  }

  /// Ensures a server baseline exists for a chain/month (used by the what-if simulator).
  Future<TradeMarketingSalesBaseline?> _ensureBaseline(String chain, int year, int month) async {
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

  /// Average historical ROMI from server data, used to project simulator lift.
  double get _historicalRomi {
    final rows = _monthlyRoiSummariesFor(_expenses).where((s) => s.marketingSpendEgp > 0 && s.romiMultiple > 0);
    if (rows.isEmpty) return 3.45;
    return rows.fold<double>(0, (a, s) => a + s.romiMultiple) / rows.length;
  }

  /// Filtered individual expense items
  List<MarketingExpenseItem> get _filteredExpenses {
    final q = _searchQuery.trim().toLowerCase();
    final list = _expenses.where((item) {
      if (_selectedChain != 'all' && item.chainName != _selectedChain) return false;
      if (_selectedYear != 0 && item.year != _selectedYear) return false;
      if (_selectedMonth != 0 && item.month != _selectedMonth) return false;
      if (_selectedCategoryId != 'all' && item.category.id != _selectedCategoryId) return false;
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
  List<MonthlyChainRoiSummary> get _monthlyRoiSummaries => _monthlyRoiSummariesFor(_filteredExpenses);

  List<MonthlyChainRoiSummary> _monthlyRoiSummariesFor(List<MarketingExpenseItem> source) {
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

      final baseline = _baselines[tradeMarketingBaselineKey(first.year, first.month, first.chainName)];

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
          cmp = a.romiMultiple.compareTo(b.romiMultiple);
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

    String chain = existing?.chainName ?? (_selectedChain != 'all' ? _selectedChain : 'Fathalla');
    int year = existing?.year ?? (_selectedYear != 0 ? _selectedYear : 2026);
    int month = existing?.month ?? (_selectedMonth != 0 ? _selectedMonth : 1);
    MarketingExpenseCategory category = existing?.category ?? MarketingExpenseCategory.floorRental;

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
                        existing == null ? Icons.add_chart_rounded : Icons.edit_note_rounded,
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
                            'Add / Edit Trade Marketing & Promotional Expense',
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
label: 'السلسلة التجارية (Retail Chain)',
expand: true,
options: m3OptionsFromMenuItems<String>(_availableChains
                                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                    .toList()),
onChanged: m3Legacy<String>((val) {
                                  if (val != null) setDialogState(() => chain = val);
                                }),
),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              flex: 2,
                              child: M3Dropdown<int>(
value: month,
label: 'الشهر (Campaign Month)',
expand: true,
options: m3OptionsFromMenuItems<int>(List.generate(12, (idx) {
                                  final m = idx + 1;
                                  return DropdownMenuItem(
                                    value: m,
                                    child: Text(
                                      '${MarketingExpenseItem.monthNamesAr[m]} - ${MarketingExpenseItem.monthNamesEn[m]}',
                                    ),
                                  );
                                })),
onChanged: m3Legacy<int>((val) {
                                  if (val != null) setDialogState(() => month = val);
                                }),
),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              flex: 1,
                              child: M3Dropdown<int>(
value: year,
label: 'السنة (Year)',
expand: true,
options: m3OptionsFromMenuItems<int>([
                                  const DropdownMenuItem(value: 2026, child: Text('2026')),
                                  const DropdownMenuItem(value: 2025, child: Text('2025')),
                                ]),
onChanged: m3Legacy<int>((val) {
                                  if (val != null) setDialogState(() => year = val);
                                }),
),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14.0),

                        // Row 2: Expense Category
                        M3Dropdown<MarketingExpenseCategory>(
value: category,
label: 'نوع المصروف التسويقي (Expense Category)',
expand: true,
options: m3OptionsFromMenuItems<MarketingExpenseCategory>(MarketingExpenseCategory.values.map((cat) {
                            return DropdownMenuItem(
                              value: cat,
                              child: Row(
                                children: [
                                  Icon(cat.icon, size: 18.0, color: cat.color),
                                  const SizedBox(width: 8.0),
                                  Expanded(
                                    child: Text(
                                      '${cat.labelAr} (${cat.labelEn})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList()),
onChanged: m3Legacy<MarketingExpenseCategory>((val) {
                            if (val != null) setDialogState(() => category = val);
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
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'قيمة المصروف بالجنيه (Amount in EGP) *',
                                  hintText: 'مثال: 100000',
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
                                  labelText: 'البراند المستهدف (Brand)',
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
                            labelText: 'وصف النشاط الترويجي أو الحملة (Campaign / Activity Title) *',
                            hintText: 'مثال: تأجير فلورات عرض رئيسية + إيفنت تذوق وهدايا مجانية',
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
                            labelText: 'شركة الدعاية أو جهة التعاقد (Agency / Retailer Contract)',
                            hintText: 'مثال: إدارة التعاقدات بالسلسلة / شركة دعاية وإيفنتات',
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
                            labelText: 'ملاحظات وتفاصيل الفروع المستهدفة (Notes & Target Branches)',
                            hintText: 'مثال: فروع سموحة، سان ستيفانو، المنتزه...',
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
                    child: const Text('Cancel / إلغاء'),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      final parsedAmount = double.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
                      if (parsedAmount <= 0) {
                        M3Feedback.showWarning(context, 'يرجى إدخال قيمة صحيحة للمصروف بالجنيه (أكبر من صفر)');
                        return;
                      }
                      final title = titleCtrl.text.trim().isEmpty
                          ? '${category.labelAr} - $chain (${MarketingExpenseItem.monthNamesAr[month]})'
                          : titleCtrl.text.trim();

                      final newItem = MarketingExpenseItem(
                        id: existing?.id ?? 'EXP-${DateTime.now().millisecondsSinceEpoch}',
                        year: year,
                        month: month,
                        chainName: chain,
                        category: category,
                        brandName: brandCtrl.text.trim().isEmpty ? 'General' : brandCtrl.text.trim(),
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
                        saved = await _repo.saveExpense(newItem, isNew: existing == null);
                      } catch (e) {
                        if (!mounted) return;
                        M3Feedback.showWarning(context, 'تعذر حفظ المصروف: $e');
                        return;
                      }
                      if (!mounted) return;
                      setState(() {
                        if (existing != null) {
                          final idx = _expenses.indexWhere((e) => e.id == existing.id);
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
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18.0),
                    label: Text(existing == null ? 'Save Expense' : 'Update Expense'),
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
    final int simYear = _selectedYear != 0 ? _selectedYear : DateTime.now().year;
    final requested = <String>{};
    final historicalRomi = _historicalRomi;
    double proposedBudget = 100000.0;
    final budgetCtrl = TextEditingController(text: '100000');

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // What-if projection seeded from server baselines (ingested sell-out data).
            final simKey = tradeMarketingBaselineKey(simYear, simMonth, simChain);
            final baseline = _baselines[simKey];
            if (baseline == null && !requested.contains(simKey)) {
              requested.add(simKey);
              _ensureBaseline(simChain, simYear, simMonth).then((_) {
                if (dialogCtx.mounted) setDialogState(() {});
              });
            }
            final prevSales = baseline?.previousMonthSalesEgp ?? 0.0;
            final lastYearSales = baseline?.lastYearSameMonthSalesEgp ?? 0.0;
            final projectedSales = prevSales + proposedBudget * historicalRomi;
            final momLift = projectedSales - prevSales;
            final momPct = prevSales > 0 ? (momLift / prevSales) * 100.0 : 0.0;
            final yoyLift = projectedSales - lastYearSales;
            final yoyPct = lastYearSales > 0 ? (yoyLift / lastYearSales) * 100.0 : 0.0;
            final romi = proposedBudget > 0 ? momLift / proposedBudget : 0.0;

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusXl),
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
                            'محاكي العائد التسويقي الذكي (Promo Budget ROI Simulator)',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'اختبر تأثير الميزانية التسويقية المقترحة على نمو المبيعات الشهري والسنوي',
                            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 560.0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: M3Dropdown<String>(
value: simChain,
label: 'السلسلة (Chain)',
expand: true,
options: m3OptionsFromMenuItems<String>(_availableChains
                                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                  .toList()),
onChanged: m3Legacy<String>((v) {
                                if (v != null) setDialogState(() => simChain = v);
                              }),
),
                          ),
                          const SizedBox(width: 12.0),
                          Expanded(
                            child: M3Dropdown<int>(
value: simMonth,
label: 'الشهر (Month)',
expand: true,
options: m3OptionsFromMenuItems<int>(List.generate(12, (idx) {
                                final m = idx + 1;
                                return DropdownMenuItem(
                                  value: m,
                                  child: Text('${MarketingExpenseItem.monthNamesAr[m]} (${MarketingExpenseItem.monthNamesEn[m]})'),
                                );
                              })),
onChanged: m3Legacy<int>((v) {
                                if (v != null) setDialogState(() => simMonth = v);
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
                          labelText: 'الميزانية التسويقية المقترحة للشهر (Proposed Budget in EGP)',
                          prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (val) {
                          final parsed = double.tryParse(val.replaceAll(',', '').trim());
                          if (parsed != null && parsed >= 0) {
                            setDialogState(() => proposedBudget = parsed);
                          }
                        },
                      ),
                      const SizedBox(height: 18.0),
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withOpacity(0.45),
                          borderRadius: M3Shape.radiusLg,
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'النتائج المتوقعة بناءً على حساسية المبيعات التاريخية لـ $simChain:',
                              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 12.0),
                            _buildSimMetricRow(
                              'مبيعات الشهر السابق (Baseline MoM):',
                              CurrencyFormatter.formatEGP(prevSales),
                              colorScheme.onSurface,
                            ),
                            const SizedBox(height: 6.0),
                            _buildSimMetricRow(
                              'مبيعات نفس الشهر بالعام الماضي (Baseline YoY):',
                              CurrencyFormatter.formatEGP(lastYearSales),
                              colorScheme.onSurface,
                            ),
                            const Divider(height: 20.0),
                            _buildSimMetricRow(
                              'المبيعات المتوقعة بعد الحملة:',
                              CurrencyFormatter.formatEGP(projectedSales),
                              colorScheme.primary,
                              isBold: true,
                            ),
                            const SizedBox(height: 6.0),
                            _buildSimMetricRow(
                              'الزيادة المتوقعة عن الشهر السابق (MoM Lift):',
                              '+${CurrencyFormatter.formatEGP(momLift)} (+${momPct.toStringAsFixed(1)}%)',
                              M3Palette.success,
                              isBold: true,
                            ),
                            const SizedBox(height: 6.0),
                            _buildSimMetricRow(
                              'الزيادة المتوقعة عن العام السابق (YoY Lift):',
                              lastYearSales > 0
                                  ? '+${CurrencyFormatter.formatEGP(yoyLift)} (+${yoyPct.toStringAsFixed(1)}%)'
                                  : '— لا توجد بيانات للعام السابق',
                              M3Palette.info,
                              isBold: true,
                            ),
                            const SizedBox(height: 6.0),
                            _buildSimMetricRow(
                              'العائد لكل 1 جنيه تسويق (ROMI Multiple):',
                              '${romi.toStringAsFixed(2)}x (كل 1 ج.م يحقق ${romi.toStringAsFixed(2)} ج.م نمو مبيعات)',
                              M3Palette.violet,
                              isBold: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('Close / إغلاق'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSimMetricRow(String label, String value, Color valueColor, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: M3FontSize.labelMediumPlus, fontWeight: FontWeight.w600)),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? M3FontSize.bodyMedium : M3FontSize.labelMediumPlus,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: valueColor,
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
                  child: Icon(Icons.insights_rounded, color: summary.verdictColor),
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تحليل أثر الحملة التسويقية: ${summary.chainName} - ${summary.monthNameAr} ${summary.year}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${summary.chainName} | ${summary.monthNameEn} ${summary.year} Campaign ROI Breakdown',
                        style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
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
                    Wrap(
                      spacing: 12.0,
                      runSpacing: 12.0,
                      children: [
                        _buildMiniDrillCard(
                          titleAr: 'إجمالي المصروفات بالشهر',
                          titleEn: 'Campaign Spend',
                          value: CurrencyFormatter.formatEGP(summary.marketingSpendEgp),
                          sub: '${summary.activitiesCount} أنشطة ترويجية',
                          color: M3Palette.violet,
                        ),
                        _buildMiniDrillCard(
                          titleAr: 'مبيعات الشهر الحالي',
                          titleEn: 'Current Month Sales',
                          value: CurrencyFormatter.formatEGP(summary.currentMonthSalesEgp),
                          sub: 'نسبة الصرف: ${summary.spendToSalesRatioPct.toStringAsFixed(1)}% من المبيعات',
                          color: colorScheme.primary,
                        ),
                        _buildMiniDrillCard(
                          titleAr: 'النمو عن الشهر السابق (MoM)',
                          titleEn: 'vs. Previous Month (${CurrencyFormatter.formatEGP(summary.previousMonthSalesEgp)})',
                          value: '${summary.momLiftEgp >= 0 ? '+' : ''}${CurrencyFormatter.formatEGP(summary.momLiftEgp)}',
                          sub: '${summary.momGrowthPct >= 0 ? '+' : ''}${summary.momGrowthPct.toStringAsFixed(1)}% MoM Growth',
                          color: summary.momGrowthPct >= 0 ? M3Palette.success : M3Palette.danger,
                        ),
                        _buildMiniDrillCard(
                          titleAr: 'النمو عن نفس الشهر بالعام السابق (YoY)',
                          titleEn: 'vs. Last Year (${CurrencyFormatter.formatEGP(summary.lastYearSameMonthSalesEgp)})',
                          value: summary.hasYoY
                              ? '${summary.yoyLiftEgp >= 0 ? '+' : ''}${CurrencyFormatter.formatEGP(summary.yoyLiftEgp)}'
                              : '—',
                          sub: summary.hasYoY
                              ? '${summary.yoyGrowthPct >= 0 ? '+' : ''}${summary.yoyGrowthPct.toStringAsFixed(1)}% YoY Growth'
                              : 'لا توجد بيانات للعام السابق',
                          color: summary.yoyGrowthPct >= 0 ? M3Palette.info : M3Palette.danger,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16.0),
                    Container(
                      padding: const EdgeInsets.all(14.0),
                      decoration: BoxDecoration(
                        color: summary.verdictColor.withOpacity(0.1),
                        borderRadius: M3Shape.radiusMd,
                        border: Border.all(color: summary.verdictColor.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.verified_rounded, color: summary.verdictColor),
                          const SizedBox(width: 10.0),
                          Expanded(
                            child: Text(
                              'التقييم التحليلي: ${summary.verdictAr} — كل 1 جنيه تم صرفه في ${summary.monthNameAr} حقق ${summary.romiMultiple.toStringAsFixed(2)} جنيه زيادة في المبيعات مقارنة بالشهر السابق.',
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
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8.0),
                    ...summary.expenses.map((exp) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8.0),
                        elevation: 0,
                        color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
                        shape: RoundedRectangleBorder(
                          borderRadius: M3Shape.radiusMd,
                          side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: exp.category.color.withOpacity(0.15),
                            child: Icon(exp.category.icon, color: exp.category.color, size: 20.0),
                          ),
                          title: Text(
                            exp.campaignTitle,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: M3FontSize.bodyCompact),
                          ),
                          subtitle: Text(
                            '${exp.category.labelAr} • البراند: ${exp.brandName} • الجهة: ${exp.vendorOrAgency}',
                            style: const TextStyle(fontSize: M3FontSize.bodySmall),
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
                child: const Text('Close / إغلاق'),
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
      width: 310.0,
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: M3Shape.radiusMd,
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titleAr, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: M3FontSize.bodySmallPlus)),
          Text(titleEn, style: TextStyle(fontSize: M3FontSize.labelSmall, color: Colors.grey.shade700)),
          const SizedBox(height: 6.0),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: M3FontSize.titleMediumPlus, color: color),
          ),
          const SizedBox(height: 2.0),
          Text(sub, style: const TextStyle(fontSize: M3FontSize.labelSmallPlus, fontWeight: FontWeight.w600)),
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
      'MoM Sales Lift (EGP)',
      'MoM Growth (%)',
      'Last Year Same Month Sales (EGP)',
      'YoY Sales Lift (EGP)',
      'YoY Growth (%)',
      'Spend-to-Sales Ratio (%)',
      'ROMI Multiple (x)',
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
        s.momLiftEgp.toStringAsFixed(0),
        '${s.momGrowthPct.toStringAsFixed(1)}%',
        s.lastYearSameMonthSalesEgp.toStringAsFixed(0),
        s.hasYoY ? s.yoyLiftEgp.toStringAsFixed(0) : '—',
        s.hasYoY ? '${s.yoyGrowthPct.toStringAsFixed(1)}%' : '—',
        '${s.spendToSalesRatioPct.toStringAsFixed(1)}%',
        '${s.romiMultiple.toStringAsFixed(2)}x',
        s.verdictAr,
      ];
    }).toList();

    final csv = ExcelExportService.generateCsv(headers: headers, rows: rows);
    ExcelExportService.downloadCsv('Trade_Marketing_ROI_Growth_Report.xlsx', csv);
    M3Feedback.showSuccess(
      context,
      'تم تصدير تقرير العائد التسويقي ونمو المبيعات (Trade_Marketing_ROI_Growth_Report.xlsx) بنجاح',
    );
  }

  void _printPdfReport() {
    final summaries = _monthlyRoiSummaries;
    final totalSpend = summaries.fold<double>(0.0, (s, e) => s + e.marketingSpendEgp);
    final totalMomLift = summaries.fold<double>(0.0, (s, e) => s + e.momLiftEgp);

    final headers = [
      'الشهر والسنة',
      'السلسلة',
      'المصروف التسويقي',
      'مبيعات الشهر السابق',
      'مبيعات شهر الحملة',
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
        '${s.momGrowthPct >= 0 ? '+' : ''}${s.momGrowthPct.toStringAsFixed(1)}%',
        s.hasYoY ? '${s.yoyGrowthPct >= 0 ? '+' : ''}${s.yoyGrowthPct.toStringAsFixed(1)}%' : '—',
        '${s.romiMultiple.toStringAsFixed(2)}x',
        s.verdictAr,
      ];
    }).toList();

    final htmlContent = ExcelExportService.generatePrintableReport(
      title: 'تقرير العائد على المصروفات التسويقية والترويجية (Trade Marketing & Promo ROI)',
      headers: headers,
      rows: rows,
      metadata: {
        'إجمالي الإنفاق التسويقي': CurrencyFormatter.formatEGP(totalSpend),
        'إجمالي نمو المبيعات الشهري (MoM)': CurrencyFormatter.formatEGP(totalMomLift),
      },
    );
    ExcelExportService.downloadHtml('Trade_Marketing_ROI_Report.html', htmlContent);
    M3Feedback.showInfo(context, 'تم تجهيز وتحميل تقرير الـ PDF القابل للطباعة');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final summaries = _monthlyRoiSummaries;
    final expenses = _filteredExpenses;

    // Aggregate top KPI metrics
    final totalSpend = expenses.fold<double>(0.0, (s, e) => s + e.amountEgp);
    final totalCurrentSales = summaries.fold<double>(0.0, (s, e) => s + e.currentMonthSalesEgp);
    final totalPrevSales = summaries.fold<double>(0.0, (s, e) => s + e.previousMonthSalesEgp);
    final totalLastYearSales = summaries.fold<double>(0.0, (s, e) => s + e.lastYearSameMonthSalesEgp);

    final totalMomLift = totalCurrentSales - totalPrevSales;
    final totalMomPct = totalPrevSales > 0 ? (totalMomLift / totalPrevSales) * 100.0 : 0.0;

    // YoY compares the same months only: current sales count only for
    // rows whose same month last year has Sell-Out.
    final totalYoyCurrentSales =
        summaries.where((e) => e.hasYoY).fold<double>(0.0, (s, e) => s + e.currentMonthSalesEgp);
    final totalYoyAvailable = totalLastYearSales > 0;
    final totalYoyLift = totalYoyCurrentSales - totalLastYearSales;
    final totalYoyPct = totalYoyAvailable ? (totalYoyLift / totalLastYearSales) * 100.0 : 0.0;

    final overallRomi = totalSpend > 0 ? (totalMomLift / totalSpend) : 0.0;
    final spendRatioPct = totalCurrentSales > 0 ? (totalSpend / totalCurrentSales) * 100.0 : 0.0;

    final isCompact = MediaQuery.sizeOf(context).width < 600.0;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SingleChildScrollView(
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
                    content: Text('تعذر تحميل بيانات التسويق من الخادم: $_loadError'),
                    leading: Icon(Icons.cloud_off_rounded, color: colorScheme.error),
                    actions: [
                      TextButton(onPressed: _reload, child: const Text('Retry / إعادة المحاولة')),
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
                _buildCategoryAnalyticsTab(theme, colorScheme, expenses, summaries),
            ],
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
          titleEn: 'Trade Marketing & Promo ROI',
          subtitleAr:
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
    required double totalYoyLift,
    required double totalYoyPct,
    required bool totalYoyAvailable,
    required double overallRomi,
    required double spendRatioPct,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;
        final cards = [
          _buildSymmetricalKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            titleAr: 'إجمالي المصروفات الترويجية',
            titleEn: 'Total Trade Marketing Spend',
            primaryValue: CurrencyFormatter.formatEGP(totalSpend),
            badgeText: '$activitiesCount Campaigns / Activities',
            subText: 'الفلورات، الدعاية، الهدايا، والإيفنتات',
            icon: Icons.campaign_rounded,
            accentColor: M3Palette.violet,
          ),
          _buildSymmetricalKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            titleAr: 'نمو المبيعات عن الشهر السابق',
            titleEn: 'MoM Sales Growth Lift',
            primaryValue: '${totalMomLift >= 0 ? '+' : ''}${CurrencyFormatter.formatEGP(totalMomLift)}',
            badgeText: '${totalMomPct >= 0 ? '+' : ''}${totalMomPct.toStringAsFixed(1)}% MoM',
            subText: 'مقارنة بمبيعات الشهر السابق مباشرةً',
            icon: Icons.show_chart_rounded,
            accentColor: totalMomLift >= 0 ? M3Palette.success : M3Palette.danger,
          ),
          _buildSymmetricalKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            titleAr: 'نمو المبيعات عن العام السابق',
            titleEn: 'YoY Same-Month Sales Lift',
            primaryValue: totalYoyAvailable
                ? '${totalYoyLift >= 0 ? '+' : ''}${CurrencyFormatter.formatEGP(totalYoyLift)}'
                : '—',
            badgeText: totalYoyAvailable
                ? '${totalYoyPct >= 0 ? '+' : ''}${totalYoyPct.toStringAsFixed(1)}% YoY'
                : 'لا توجد بيانات للعام السابق',
            subText: 'مقارنة بنفس الشهر من السنة السابقة',
            icon: Icons.calendar_month_rounded,
            accentColor: totalYoyLift >= 0 ? M3Palette.info : M3Palette.danger,
          ),
          _buildSymmetricalKpiCard(
            theme: theme,
            colorScheme: colorScheme,
            titleAr: 'العائد على الإنفاق التسويقي',
            titleEn: 'Return on Marketing Spend (ROMI)',
            primaryValue: '${overallRomi.toStringAsFixed(2)}x ROI',
            badgeText: 'Cost Ratio: ${spendRatioPct.toStringAsFixed(1)}%',
            subText: 'كل 1 ج.م تسويق حقق ${overallRomi.toStringAsFixed(2)} ج.م نمو',
            icon: Icons.workspace_premium_rounded,
            accentColor: M3Palette.warning,
          ),
        ];

        if (isWide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14.0),
                  Expanded(child: cards[i]),
                ],
              ],
            ),
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 12.0),
                Expanded(child: cards[1]),
              ],
            ),
            const SizedBox(height: 12.0),
            Row(
              children: [
                Expanded(child: cards[2]),
                const SizedBox(width: 12.0),
                Expanded(child: cards[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildSymmetricalKpiCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required String titleAr,
    required String titleEn,
    required String primaryValue,
    required String badgeText,
    required String subText,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(
          color: accentColor.withOpacity(0.28),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: M3Shape.radiusMd,
                ),
                child: Icon(icon, color: accentColor, size: 22.0),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleAr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      titleEn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14.0),
          Text(
            primaryValue,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: accentColor,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  subText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: M3FontSize.labelSmallPlus,
                  ),
                ),
              ),
              const SizedBox(width: 6.0),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: M3Shape.radiusFull,
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: M3FontSize.labelSmall,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterAndActionToolbar(ThemeData theme, ColorScheme colorScheme) {
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
                child: Wrap(
                  spacing: 10.0,
                  runSpacing: 10.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Chain Filter
                    SizedBox(
                      width: 170.0,
                      child: M3Dropdown<String>(
value: _selectedChain,
label: 'Retail Chain',
leadingIcon: Icons.storefront_rounded,
expand: true,
options: m3OptionsFromMenuItems<String>([
                          const DropdownMenuItem(value: 'all', child: Text('All Chains')),
                          ..._availableChains.map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          ),
                        ]),
onChanged: m3Legacy<String>((v) {
                          if (v != null) setState(() => _selectedChain = v);
                        }),
),
                    ),
                    // Month Filter
                    SizedBox(
                      width: 165.0,
                      child: M3Dropdown<int>(
value: _selectedMonth,
label: 'Month',
leadingIcon: Icons.event_note_rounded,
expand: true,
options: m3OptionsFromMenuItems<int>([
                          const DropdownMenuItem(value: 0, child: Text('All Months')),
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
                    ),
                    // Year Filter
                    SizedBox(
                      width: 135.0,
                      child: M3Dropdown<int>(
value: _selectedYear,
label: 'Year',
leadingIcon: Icons.calendar_today_rounded,
expand: true,
options: m3OptionsFromMenuItems<int>([
                          const DropdownMenuItem(value: 0, child: Text('All Years')),
                          const DropdownMenuItem(value: 2026, child: Text('2026')),
                          const DropdownMenuItem(value: 2025, child: Text('2025')),
                        ]),
onChanged: m3Legacy<int>((v) {
                          if (v != null) setState(() => _selectedYear = v);
                        }),
),
                    ),
                    // Activity Category Filter
                    SizedBox(
                      width: 220.0,
                      child: M3Dropdown<String>(
value: _selectedCategoryId,
label: 'Activity Type',
leadingIcon: Icons.category_rounded,
expand: true,
options: m3OptionsFromMenuItems<String>([
                          const DropdownMenuItem(value: 'all', child: Text('All Activity Types')),
                          ...MarketingExpenseCategory.values.map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.labelEn, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ]),
onChanged: m3Legacy<String>((v) {
                          if (v != null) setState(() => _selectedCategoryId = v);
                        }),
),
                    ),
                    // Search Box
                    SizedBox(
                      width: 220.0,
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: const InputDecoration(
                          hintText: 'Search campaign, brand...',
                          prefixIcon: Icon(Icons.search_rounded, size: 18.0),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 11.0),
                          border: OutlineInputBorder(borderRadius: M3Shape.radiusMd),
                        ),
                      ),
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
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44.0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18.0,
                          vertical: 10.0,
                        ),
                        textStyle: const TextStyle(
                          fontSize: M3FontSize.bodyCompact,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => _openAddOrEditExpenseDialog(),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 20.0),
                      label: const Text('Add Expense'),
                    ),
                    if (_canWrite)
                      FilledButton.tonalIcon(
                        key: const ValueKey('btn_upload_marketing_expenses'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44.0),
                          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
                          textStyle: const TextStyle(fontSize: M3FontSize.bodyCompact, fontWeight: FontWeight.w700),
                        ),
                        onPressed: _uploading ? null : _pickAndUploadExpenses,
                        icon: _uploading
                            ? const SizedBox(
                                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.upload_file_rounded, size: 20.0),
                        label: Text(_uploading ? 'Uploading…' : 'Upload Excel/CSV'),
                      ),
                    if (_canWrite)
                      TextButton.icon(
                        key: const ValueKey('btn_download_expense_template'),
                        style: TextButton.styleFrom(minimumSize: const Size(0, 44.0)),
                        onPressed: _downloadTemplate,
                        icon: const Icon(Icons.download_rounded, size: 20.0),
                        label: const Text('CSV Template'),
                      ),
                    FilledButton.tonalIcon(
                      key: const ValueKey('btn_roi_simulator'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44.0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18.0,
                          vertical: 10.0,
                        ),
                        textStyle: const TextStyle(
                          fontSize: M3FontSize.bodyCompact,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: _openRoiSimulatorDialog,
                      icon: const Icon(Icons.auto_graph_rounded, size: 20.0),
                      label: const Text('ROI Simulator'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('btn_export_roi_excel'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44.0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18.0,
                          vertical: 10.0,
                        ),
                        textStyle: const TextStyle(
                          fontSize: M3FontSize.bodyCompact,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: _exportExcelReport,
                      icon: const Icon(Icons.table_view_rounded, size: 20.0),
                      label: const Text('Export Excel'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('btn_print_roi_pdf'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44.0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18.0,
                          vertical: 10.0,
                        ),
                        textStyle: const TextStyle(
                          fontSize: M3FontSize.bodyCompact,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: _printPdfReport,
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 20.0),
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

  /// TAB 0: Monthly & Chain ROI vs. MoM & YoY Sales Growth Matrix
  Widget _buildRoiGrowthMatrixTab(
    ThemeData theme,
    ColorScheme colorScheme,
    List<MonthlyChainRoiSummary> summaries,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مصفوفة مقارنة المصروفات التسويقية بنمو المبيعات الشهري (MoM) والسنوي (YoY)',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      'اضغط على أي شهر أو سلسلة لعرض تفاصيل الفلورات والحملات الإعلانية وكيف أثرت على المبيعات مقارنة بالشهر السابق والعام السابق • Double-click على عناوين الأعمدة للترتيب',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.6),
                  borderRadius: M3Shape.radiusFull,
                ),
                child: Text(
                  '${summaries.length} حملات شهرية مجمعة',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: M3FontSize.bodySmall,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16.0),
          if (summaries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(
                child: Text('لا توجد مصروفات مطابقة للفلتر المحدد. اضغط Add Expense لإضافة مصروف تسويقي جديد.'),
              ),
            )
          else
            TableScrollContainer(
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  colorScheme.surfaceContainerHighest.withOpacity(0.5),
                ),
                dataRowMinHeight: 62.0,
                dataRowMaxHeight: 74.0,
                columnSpacing: 22.0,
                columns: [
                  DataColumn(
                    label: _buildSortableHeader('الشهر والسنة\nMonth & Year', 'month', _matrixSortColumn, _matrixSortAsc, _toggleMatrixSort),
                  ),
                  const DataColumn(
                    label: Text('السلسلة\nRetail Chain', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  DataColumn(
                    numeric: true,
                    label: _buildSortableHeader('المصروف التسويقي\nMarketing Spend', 'spend', _matrixSortColumn, _matrixSortAsc, _toggleMatrixSort),
                  ),
                  const DataColumn(
                    numeric: true,
                    label: Text('مبيعات الشهر السابق\nPrev Month Sales', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  DataColumn(
                    numeric: true,
                    label: _buildSortableHeader('مبيعات شهر الحملة\nCampaign Month Sales', 'sales', _matrixSortColumn, _matrixSortAsc, _toggleMatrixSort),
                  ),
                  DataColumn(
                    numeric: true,
                    label: _buildSortableHeader('النمو عن الشهر السابق\nMoM Growth Lift', 'mom', _matrixSortColumn, _matrixSortAsc, _toggleMatrixSort),
                  ),
                  DataColumn(
                    numeric: true,
                    label: _buildSortableHeader('النمو عن العام السابق\nYoY Same-Month Lift', 'yoy', _matrixSortColumn, _matrixSortAsc, _toggleMatrixSort),
                  ),
                  DataColumn(
                    numeric: true,
                    label: _buildSortableHeader('العائد (ROMI)\nROI Multiple', 'roi', _matrixSortColumn, _matrixSortAsc, _toggleMatrixSort),
                  ),
                  const DataColumn(
                    label: Text('تقييم أثر الحملة\nCampaign Impact Verdict', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  const DataColumn(
                    label: Text('التفاصيل\nDetails', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
                rows: summaries.map((s) {
                  final momPositive = s.momLiftEgp >= 0;
                  final yoyPositive = s.yoyLiftEgp >= 0;
                  return DataRow(
                    cells: [
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s.monthNameAr} ${s.year}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: M3FontSize.bodyCompact),
                            ),
                            Text(
                              '${s.monthNameEn} ${s.year}',
                              style: TextStyle(fontSize: M3FontSize.labelSmall, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                        onTap: () => _openCampaignDrillDownModal(s),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.storefront_rounded, size: 17.0, color: colorScheme.primary),
                            const SizedBox(width: 6.0),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.chainName,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  '${s.activitiesCount} بنود ترويجية',
                                  style: TextStyle(fontSize: M3FontSize.labelSmall, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => _openCampaignDrillDownModal(s),
                      ),
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              CurrencyFormatter.formatEGP(s.marketingSpendEgp),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: M3Palette.violet,
                                fontSize: M3FontSize.bodyCompact,
                              ),
                            ),
                            Text(
                              '${s.spendToSalesRatioPct.toStringAsFixed(1)}% من المبيعات',
                              style: TextStyle(fontSize: M3FontSize.labelSmall, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Text(
                          CurrencyFormatter.formatEGP(s.previousMonthSalesEgp),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              CurrencyFormatter.formatEGP(s.currentMonthSalesEgp),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: colorScheme.onSurface,
                                fontSize: M3FontSize.bodyCompact,
                              ),
                            ),
                            Text(
                              'توريد Sell-In: ${CurrencyFormatter.formatEGP(s.currentMonthSellInEgp)}',
                              style: TextStyle(fontSize: M3FontSize.tinyPlus, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                              decoration: BoxDecoration(
                                color: (momPositive ? M3Palette.success : M3Palette.danger)
                                    .withOpacity(0.12),
                                borderRadius: M3Shape.radiusFull,
                              ),
                              child: Text(
                                '${momPositive ? '+' : ''}${s.momGrowthPct.toStringAsFixed(1)}% MoM',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: M3FontSize.labelSmallPlus,
                                  color: momPositive ? M3Palette.success : M3Palette.danger,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2.0),
                            Text(
                              '${momPositive ? '+' : ''}${CurrencyFormatter.formatEGP(s.momLiftEgp)}',
                              style: TextStyle(
                                fontSize: M3FontSize.labelSmallPlus,
                                fontWeight: FontWeight.w700,
                                color: momPositive ? M3Palette.success : M3Palette.danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                              decoration: BoxDecoration(
                                color: (yoyPositive ? M3Palette.info : M3Palette.danger)
                                    .withOpacity(0.12),
                                borderRadius: M3Shape.radiusFull,
                              ),
                              child: Text(
                                s.hasYoY
                                    ? '${yoyPositive ? '+' : ''}${s.yoyGrowthPct.toStringAsFixed(1)}% YoY'
                                    : '— لا توجد بيانات للعام السابق',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: M3FontSize.labelSmallPlus,
                                  color: yoyPositive ? M3Palette.info : M3Palette.danger,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2.0),
                            Text(
                              s.hasYoY ? '${yoyPositive ? '+' : ''}${CurrencyFormatter.formatEGP(s.yoyLiftEgp)}' : '—',
                              style: TextStyle(
                                fontSize: M3FontSize.labelSmallPlus,
                                fontWeight: FontWeight.w700,
                                color: yoyPositive ? M3Palette.info : M3Palette.danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${s.romiMultiple.toStringAsFixed(2)}x',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: M3FontSize.bodyMediumPlus,
                                color: s.verdictColor,
                              ),
                            ),
                            Text(
                              'ROI ${s.netRoiPct >= 0 ? '+' : ''}${s.netRoiPct.toStringAsFixed(0)}%',
                              style: TextStyle(fontSize: M3FontSize.labelSmall, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
                          decoration: BoxDecoration(
                            color: s.verdictColor.withOpacity(0.12),
                            borderRadius: M3Shape.radiusFull,
                            border: Border.all(color: s.verdictColor.withOpacity(0.35)),
                          ),
                          child: Text(
                            s.verdictAr,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: M3FontSize.labelSmallPlus,
                              color: s.verdictColor,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        IconButton(
                          tooltip: 'عرض تفاصيل الحملة والأثر البيعي',
                          icon: Icon(Icons.visibility_rounded, color: colorScheme.primary),
                          onPressed: () => _openCampaignDrillDownModal(s),
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
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سجل المصروفات الترويجية والحملات التفصيلي (Campaigns & Expense Ledger)',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      'إدارة كافة بنود الصرف (تأجير فلورات، إعلانات، هدايا، شركات دعاية وإيفنتات) مع إمكانية التعديل أو الحذف الفوري',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _openAddOrEditExpenseDialog(),
                icon: const Icon(Icons.add_rounded, size: 18.0),
                label: const Text('Add New Expense'),
              ),
            ],
          ),
          const SizedBox(height: 16.0),
          TableScrollContainer(
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(
                colorScheme.surfaceContainerHighest.withOpacity(0.5),
              ),
              dataRowMinHeight: 58.0,
              dataRowMaxHeight: 70.0,
              columnSpacing: 20.0,
              columns: [
                DataColumn(
                  label: _buildSortableHeader('الشهر\nMonth', 'month', _ledgerSortColumn, _ledgerSortAsc, _toggleLedgerSort),
                ),
                DataColumn(
                  label: _buildSortableHeader('السلسلة\nChain', 'chain', _ledgerSortColumn, _ledgerSortAsc, _toggleLedgerSort),
                ),
                DataColumn(
                  label: _buildSortableHeader('نوع النشاط الترويجي\nExpense Category', 'category', _ledgerSortColumn, _ledgerSortAsc, _toggleLedgerSort),
                ),
                const DataColumn(
                  label: Text('البراند\nBrand', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                const DataColumn(
                  label: Text('وصف الحملة / النشاط\nCampaign & Activity Description', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                const DataColumn(
                  label: Text('شركة الدعاية / الجهة\nVendor / Agency', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                DataColumn(
                  numeric: true,
                  label: _buildSortableHeader('المبلغ المدفوع\nAmount (EGP)', 'amount', _ledgerSortColumn, _ledgerSortAsc, _toggleLedgerSort),
                ),
                const DataColumn(
                  label: Text('إجراءات\nActions', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
              rows: expenses.map((item) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        '${item.monthNameAr} ${item.year}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        item.chainName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                        decoration: BoxDecoration(
                          color: item.category.color.withOpacity(0.12),
                          borderRadius: M3Shape.radiusFull,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(item.category.icon, size: 15.0, color: item.category.color),
                            const SizedBox(width: 6.0),
                            Text(
                              item.category.labelAr,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: M3FontSize.labelSmallPlus,
                                color: item.category.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: M3Shape.radiusSm,
                        ),
                        child: Text(
                          item.brandName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: M3FontSize.bodySmall,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 270.0,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.campaignTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: M3FontSize.labelMediumPlus),
                            ),
                            if (item.notes.isNotEmpty)
                              Text(
                                item.notes,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: M3FontSize.labelSmall, color: colorScheme.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        item.vendorOrAgency,
                        style: const TextStyle(fontSize: M3FontSize.bodySmallPlus, fontWeight: FontWeight.w600),
                      ),
                    ),
                    DataCell(
                      Text(
                        CurrencyFormatter.formatEGP(item.amountEgp),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: M3FontSize.bodyCompact,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit / تعديل',
                            icon: const Icon(Icons.edit_rounded, size: 19.0),
                            onPressed: () => _openAddOrEditExpenseDialog(existing: item),
                          ),
                          IconButton(
                            tooltip: 'Delete / حذف',
                            icon: Icon(Icons.delete_outline_rounded, size: 19.0, color: colorScheme.error),
                            onPressed: () async {
                              try {
                                await _repo.deleteExpense(item.id);
                              } catch (e) {
                                if (!mounted) return;
                                M3Feedback.showWarning(context, 'تعذر حذف المصروف: $e');
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: M3Shape.radiusLg,
            border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'توزيع الميزانية التسويقية حسب نوع النشاط الترويجي (Spend Breakdown by Activity Type)',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4.0),
              Text(
                'مقارنة حجم الإنفاق على تأجير الفلورات، شركات الدعاية والإيفنتات، الهدايا المجانية، والإعلانات',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16.0),
              Wrap(
                spacing: 14.0,
                runSpacing: 14.0,
                children: MarketingExpenseCategory.values.map((cat) {
                  final catItems = expenses.where((e) => e.category == cat).toList();
                  final catSpend = catItems.fold<double>(0.0, (s, e) => s + e.amountEgp);
                  final sharePct = totalSpend > 0 ? (catSpend / totalSpend) * 100.0 : 0.0;

                  return Container(
                    width: 340.0,
                    padding: const EdgeInsets.all(16.0),
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
                              padding: const EdgeInsets.all(8.0),
                              decoration: BoxDecoration(
                                color: cat.color.withOpacity(0.15),
                                borderRadius: M3Shape.radiusSm,
                              ),
                              child: Icon(cat.icon, color: cat.color, size: 20.0),
                            ),
                            const SizedBox(width: 10.0),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cat.labelAr,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: M3FontSize.bodyCompact),
                                  ),
                                  Text(
                                    cat.labelEn,
                                    style: TextStyle(fontSize: M3FontSize.labelSmall, color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12.0),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                CurrencyFormatter.formatEGP(catSpend),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: M3FontSize.bodyLarge,
                                  color: cat.color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            Flexible(
                              child: Text(
                                '${sharePct.toStringAsFixed(1)}% (${catItems.length} أنشطة)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: M3FontSize.labelSmallPlus),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8.0),
                        ClipRRect(
                          borderRadius: M3Shape.radiusFull,
                          child: LinearProgressIndicator(
                            value: (sharePct / 100.0).clamp(0.0, 1.0),
                            minHeight: 7.0,
                            backgroundColor: cat.color.withOpacity(0.15),
                            valueColor: AlwaysStoppedAnimation<Color>(cat.color),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSortableHeader(
    String label,
    String colKey,
    String activeCol,
    bool isAsc,
    ValueChanged<String> onSort,
  ) {
    final isSelected = activeCol == colKey;
    return GestureDetector(
      onDoubleTap: () => onSort(colKey),
      onTap: () => onSort(colKey),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: isSelected ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
            const SizedBox(width: 4.0),
            Icon(
              isSelected
                  ? (isAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded)
                  : Icons.unfold_more_rounded,
              size: 15.0,
              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

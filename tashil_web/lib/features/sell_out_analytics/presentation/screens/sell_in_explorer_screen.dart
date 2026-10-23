import 'package:flutter/material.dart';
import '../../../../core/data/result.dart';
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
import '../../../cpfr_replenishment/domain/cpfr_models.dart';
import '../../../product_master/presentation/screens/product_master_screen.dart';
import '../widgets/target_management_panel.dart';
import '../../data/sell_in_explorer_repository.dart';

/// SellInExplorerScreen provides dedicated Supplier Sell-In (توريدات السلاسل):
/// - Tab 0: بيانات وحركات الـ Sell-In (Sell-In Explorer Table, KPIs, Filters, Upload/Export)
/// - Tab 1: الأرصدة المتبقية والتقارير (Sell-In vs. Sell-Out Remaining Stock Balance & Reports)
/// - Tab 2: وضع ومتابعة الـ Target (Sell-In Target Management)
/// - Tab 3: الشيتات المرفوعة (Sell-In Uploaded Excel Sheets Archive: Cumulative Upload, Edit/Replace, Download, Delete)
class SellInExplorerScreen extends StatefulWidget {
  final ApiClient apiClient;

  /// Optional injected repository (tests); defaults to one wrapping [apiClient].
  final SellInExplorerRepository? repository;

  const SellInExplorerScreen({
    super.key,
    required this.apiClient,
    this.repository,
  });

  @override
  State<SellInExplorerScreen> createState() => _SellInExplorerScreenState();
}

class _SellInExplorerScreenState extends State<SellInExplorerScreen> {
  int _activeTab = 0; // 0: Sell-In Explorer, 1: Remaining Stock & Reports, 2: Sell-In Targets, 3: Uploaded Sell-In Sheets Archive
  String _selectedChain = 'all';
  int _selectedYear = 2026; // Default to 2026
  int _selectedMonth = 0; // 0 = All Months
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isUploading = false;
  SellInExplorerResponse _data = const SellInExplorerResponse(
    records: [],
    totalCount: 0,
    totalValueEgp: 0,
    totalCases: 0,
    totalWeightTons: 0,
    totalExpectedEgp: 0,
  );

  // Tab 1: Remaining Stock & Sell-In vs Sell-Out Reconciliation State
  bool _isLoadingStockReport = false;
  CPFRDashboardModel? _stockDashboard;
  String _stockStatusFilter = 'all'; // all, urgent_replenishment, optimal, overstock
  bool _showFullYtdReconciliation = false; // false = Matched Window (Jan-Apr), true = Full YTD (Jan-Oct)

  // Tab 1 SKU-Level Remaining Stock: Pagination, Sorting & AI Brand Filtering
  String _skuSearchQuery = '';
  String _selectedSkuBrand = 'all';
  String _skuStockStatusFilter = 'all';
  int _skuSortColumnIndex = 4; // Default to Remaining Stock (Index 4) or DOS (Index 5)
  bool _skuSortAscending = true;
  final int _skuPageSize = 25; // 25 items per page as requested
  int _skuCurrentPage = 0;
  late final TextEditingController _skuSearchController;

  // Tab 3: Uploaded Sell-In Excel Sheets Archive State
  bool _isLoadingArchive = false;
  List<ArchivedExcelFileModel> _archivedSellInFiles = const [];
  String _archiveUploadChain = 'fathalla';
  int _archiveUploadYear = 0; // 0 = Auto-detect from sheet
  int _archiveUploadMonth = 0; // 0 = Auto-detect from sheet
  String? _deletingFileId;
  String? _replacingFileId;

  late String _lastTenantId;
  late SellInExplorerRepository _repo;

  late final ScrollController _recordsTableScrollController;
  late final ScrollController _monthlyLedgerScrollController;
  late final ScrollController _skuStockScrollController;
  late final ScrollController _archiveSheetsScrollController;

  @override
  void initState() {
    super.initState();
    _skuSearchController = TextEditingController();
    _recordsTableScrollController = ScrollController();
    _monthlyLedgerScrollController = ScrollController();
    _skuStockScrollController = ScrollController();
    _archiveSheetsScrollController = ScrollController();
    _repo = widget.repository ?? SellInExplorerRepository(widget.apiClient);
    _lastTenantId = widget.apiClient.tenantId;
    _loadAllData();
  }

  @override
  void dispose() {
    _skuSearchController.dispose();
    _recordsTableScrollController.dispose();
    _monthlyLedgerScrollController.dispose();
    _skuStockScrollController.dispose();
    _archiveSheetsScrollController.dispose();
    super.dispose();
  }

  void _onSortSku(int columnIndex, bool ascending) {
    setState(() {
      if (_skuSortColumnIndex == columnIndex) {
        _skuSortAscending = !_skuSortAscending;
      } else {
        _skuSortColumnIndex = columnIndex;
        _skuSortAscending = ascending;
      }
      _skuCurrentPage = 0; // Reset to page 0 upon changing sort
    });
  }

  @override
  void didUpdateWidget(covariant SellInExplorerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient ||
        _lastTenantId != widget.apiClient.tenantId) {
      _lastTenantId = widget.apiClient.tenantId;
      _repo = widget.repository ?? SellInExplorerRepository(widget.apiClient);
      _selectedChain = 'all';
      _selectedYear = 2026;
      _selectedMonth = 0;
      _searchQuery = '';
      _loadAllData();
    }
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadSellInRecords(),
      _loadStockReconciliationReport(),
      _loadSellInArchive(),
    ]);
  }

  Future<void> _loadSellInRecords() async {
    if (mounted) setState(() => _isLoading = true);
    final loaded = await _repo.load(SellInExplorerQuery(
      chain: _selectedChain == 'all' ? null : _selectedChain,
      year: _selectedYear > 0 ? _selectedYear : null,
      month: _selectedMonth > 0 ? _selectedMonth : null,
      query: _searchQuery,
      limit: 250,
    ));
    if (loaded case Failure(:final error)) {
      if (mounted) {
        setState(() => _isLoading = false);
        M3Feedback.showError(context, 'تعذر تحميل بيانات الـ Sell-In: $error');
      }
      return;
    }
    final res = loaded.valueOrNull!;
    if (mounted) {
      setState(() {
        _data = res;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStockReconciliationReport() async {
    if (mounted) setState(() => _isLoadingStockReport = true);
    try {
      final res = await widget.apiClient.fetchCPFRDashboard(
        chain: _selectedChain,
        year: _selectedYear > 0 ? _selectedYear : null,
        stockStatus: _stockStatusFilter,
      );
      if (mounted) {
        setState(() {
          _stockDashboard = res;
          _isLoadingStockReport = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingStockReport = false);
      }
    }
  }

  Future<void> _loadSellInArchive() async {
    if (mounted) setState(() => _isLoadingArchive = true);
    try {
      final res = await widget.apiClient.getUploadedFilesArchive(
        fileType: 'sell_in',
      );
      if (mounted) {
        setState(() {
          _archivedSellInFiles = res.files;
          _isLoadingArchive = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingArchive = false);
      }
    }
  }

  Future<void> _handleDownloadSellInSheet(ArchivedExcelFileModel file) async {
    try {
      await widget.apiClient.downloadArchivedFile(file);
      if (!mounted) return;
      M3Feedback.showSuccess(
        context,
        'تم بدء تحميل شيت الـ Sell-In الأصلي: ${file.fileName}',
      );
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'تعذر تحميل الشيت المؤرشف: $e');
    }
  }

  static String _formatFileSize(int bytes) {
    if (bytes <= 0) return 'Excel Workbook';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024.0;
    if (kb < 1024.0) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    return '${mb.toStringAsFixed(2)} MB';
  }

  Future<void> _pickAndUploadSellInFile({
    String? replaceArchiveId,
    String? forceChain,
    int? forceYear,
    int? forceMonth,
  }) async {
    final picked = await WebFileHelper.pickFile(accept: '.xlsx,.xls,.csv');
    if (picked == null || picked.bytes.isEmpty) return;

    setState(() {
      _isUploading = true;
      if (replaceArchiveId != null) {
        _replacingFileId = replaceArchiveId;
      }
    });
    try {
      final targetChain = forceChain ??
          (_selectedChain != 'all' ? _selectedChain : _archiveUploadChain);
      final targetYear = forceYear ??
          (_selectedYear > 0
              ? _selectedYear
              : (_archiveUploadYear > 0 ? _archiveUploadYear : null));
      final targetMonth = forceMonth ??
          (_selectedMonth > 0
              ? _selectedMonth
              : (_archiveUploadMonth > 0 ? _archiveUploadMonth : null));

      final res = await widget.apiClient.uploadSellInFile(
        filename: picked.name,
        fileBytes: picked.bytes,
        chain: targetChain,
        replaceArchiveId: replaceArchiveId,
        year: targetYear,
        month: targetMonth,
      );
      if (!mounted) return;
      final actionLabel = replaceArchiveId != null
          ? 'تم استبدال وتحديث شيت الـ Sell-In بنجاح'
          : 'تم رفع ودمج شيت الـ Sell-In تراكمياً بنجاح';
      M3Feedback.showSuccess(
        context,
        '$actionLabel (${picked.name}): ${res.validRows} حركة بإجمالي ${CurrencyFormatter.formatCompactEGP(res.totalRevenue)}',
      );
      _repo.invalidateAll();
      await _loadAllData();
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'تعذر رفع ملف الـ Sell-In: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _replacingFileId = null;
        });
      }
    }
  }

  Future<void> _confirmAndDeleteSellInSheet(ArchivedExcelFileModel file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          title: Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: cs.error, size: 26.0),
              const SizedBox(width: 10.0),
              const Expanded(
                child: Text(
                  'تأكيد حذف شيت الـ Sell-In',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('هل أنت متأكد من حذف شيت الإكسيل التالي من بيانات الـ Sell-In؟'),
              const SizedBox(height: 12.0),
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'السلسلة: ${file.retailChain.toUpperCase()} • الحركات: ${file.rowsIngested} • القيمة: ${CurrencyFormatter.formatCompactEGP(file.totalRevenue)}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10.0),
              Text(
                'ملاحظة: سيتم حذف حركات هذا الشيت فقط من الـ Sell-In وإعادة حساب الأرصدة المتبقية تلقائياً دون المساس ببقية الشهور المرفوعة أو بيانات الـ Sell-Out.',
                style: TextStyle(fontSize: 12.0, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.delete_outline_rounded, size: 18.0),
              label: const Text('حذف الشيت نهائياً (Delete)'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _deletingFileId = file.id);
    try {
      await widget.apiClient.deleteArchivedFile(
        file.id,
        isSellIn: true,
      );
      if (!mounted) return;
      M3Feedback.showSuccess(
        context,
        'تم حذف شيت (${file.fileName}) وتحديث حركات الـ Sell-In والأرصدة المتبقية بنجاح',
      );
      _repo.invalidateAll();
      await _loadAllData();
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'خطأ أثناء حذف الشيت: $e');
    } finally {
      if (mounted) {
        setState(() => _deletingFileId = null);
      }
    }
  }

  Future<void> _openProductIdCard({
    required String itemCode,
    required String barcode,
    required String skuName,
  }) async {
    try {
      final query = itemCode.trim().isNotEmpty
          ? itemCode.trim()
          : (barcode.trim().isNotEmpty ? barcode.trim() : skuName.trim());
      if (query.isEmpty) return;

      final res = await widget.apiClient.getProductMaster(search: query);
      if (!mounted) return;
      if (res.items.isEmpty) {
        M3Feedback.showError(
          context,
          'لم يتم العثور على بطاقة تعريفية لهذا الصنف في كارتة الأصناف',
        );
        return;
      }

      ProductMasterItemModel matched = res.items.first;
      if (itemCode.trim().isNotEmpty) {
        for (final it in res.items) {
          if (it.itemCode == itemCode.trim()) {
            matched = it;
            break;
          }
        }
      } else if (barcode.trim().isNotEmpty) {
        for (final it in res.items) {
          if (it.barcode == barcode.trim()) {
            matched = it;
            break;
          }
        }
      }

      await ProductMasterScreen.showProductIdCardModal(
        context,
        apiClient: widget.apiClient,
        item: matched,
        onUpdated: (_) {
          _repo.invalidateAll();
          _loadAllData();
        },
      );
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'تعذر فتح بطاقة هوية الصنف: $e');
    }
  }

  void _handleExportExcel() {
    if (widget.apiClient.currentUser?.canExportFinancials == false) {
      M3Feedback.showError(
        context,
        'غير مصرح: دور المشرف الميداني لا يملك صلاحية تصدير التقارير المالية (RBAC)',
      );
      return;
    }
    final records = _data.records;
    final headers = [
      'السنة',
      'الشهر',
      'السلسلة',
      'المحافظة / الإقليم',
      'العميل / الفرع',
      'القطاع',
      'العلامة التجارية',
      'الفئة الفرعية',
      'كود الصنف (Item Code)',
      'الباركود (Barcode)',
      'اسم الصنف',
      'مندوب المبيعات',
      'شد الكرتونة (Units/Carton)',
      'الكمية بالكرتونة (Cases)',
      'إجمالي الكمية بالقطعة (Units)',
      'سعر الكرتونة الرسمي (Official Carton Excl VAT)',
      'سعر الكرتونة الفعلي (Actual Case Price Excl VAT)',
      'نسبة الخصم الفعلي %',
      'صافي قيمة التوريد غير شامل الضريبة (Net EGP)',
      'ضريبة القيمة المضافة 14% (VAT EGP)',
      'إجمالي قيمة الفاتورة شامل الضريبة (Gross Incl VAT EGP)',
      'الوزن بالطن (Tons)',
      'حالة التسعير (Pricing Wave)',
      'الشيت المصدري (Source Sheet)',
    ];
    final rows = records
        .map(
          (r) => [
            r.year,
            r.monthAr.isNotEmpty ? r.monthAr : r.monthNum,
            r.retailerChain,
            r.governorate,
            r.customerName,
            r.sector,
            r.brand,
            r.subCategory,
            r.itemCode,
            r.barcode,
            r.itemName,
            r.salesRep,
            r.unitsPerCarton,
            r.netQtyCases,
            r.totalUnitsSupplied,
            r.officialCartonExclVatEgp.toStringAsFixed(2),
            r.actualCasePriceExclEgp.toStringAsFixed(2),
            r.effectiveDiscountPct.toStringAsFixed(1),
            r.netValueEgp.toStringAsFixed(2),
            r.vatAmountEgp.toStringAsFixed(2),
            r.grossValueInclVatEgp.toStringAsFixed(2),
            r.weightTons,
            r.pricingWaveStatus,
            r.sourceFilename,
          ],
        )
        .toList();
    final csvData = ExcelExportService.generateCsv(headers: headers, rows: rows);
    final filename =
        'tashil_sellin_export_${DateTime.now().millisecondsSinceEpoch}.csv';
    ExcelExportService.downloadCsv(filename, csvData);
    M3Feedback.showSuccess(
      context,
      'تم تصدير ${records.length} صف توريد (Sell-In) شامل بيانات كارتة الأصناف والضريبة إلى ملف Excel/CSV بنجاح',
    );
  }

  void _handleExportPdf() {
    if (widget.apiClient.currentUser?.canExportFinancials == false) {
      M3Feedback.showError(
        context,
        'غير مصرح: دور المشرف الميداني لا يملك صلاحية تصدير التقارير المالية (RBAC)',
      );
      return;
    }
    final records = _data.records;
    final headers = [
      'الفترة',
      'السلسلة',
      'كود / باركود',
      'اسم الصنف',
      'الشد',
      'الكراتين (القطع)',
      'صافي التوريد (ج.م)',
      'شامل 14% ضريبة (ج.م)',
      'الوزن (طن)',
    ];
    final rows = records
        .map(
          (r) => [
            '${r.monthAr} ${r.year}',
            r.retailerChain,
            r.itemCode.isNotEmpty ? '${r.itemCode}\n${r.barcode}' : '-',
            r.itemName,
            '${r.unitsPerCarton}',
            '${r.netQtyCases.toStringAsFixed(1)} (${r.totalUnitsSupplied})',
            CurrencyFormatter.formatEGP(r.netValueEgp),
            CurrencyFormatter.formatEGP(r.grossValueInclVatEgp),
            r.weightTons.toStringAsFixed(3),
          ],
        )
        .toList();
    final htmlData = ExcelExportService.generatePrintableReport(
      title: 'تقرير حركة التوريد للسلاسل التجارية وكارتة الأصناف (Sell-In & Tax Waterfall)',
      headers: headers,
      rows: rows,
      metadata: {
        'إجمالي صافي التوريد (غير شامل الضريبة)': CurrencyFormatter.formatEGP(_data.totalValueEgp),
        'إجمالي التوريد شامل 14% ضريبة': CurrencyFormatter.formatEGP(_data.totalGrossInclVatEgp),
        'إجمالي الكراتين والقطع': '${CurrencyFormatter.formatNumber(_data.totalCases.round())} كرتونة (${CurrencyFormatter.formatNumber(_data.totalUnitsPieces)} قطعة)',
        'متوسط الخصم الفعلي عن الكارتة': '${_data.effectiveDiscountPct.toStringAsFixed(1)}%',
      },
    );
    final filename =
        'tashil_sellin_report_${DateTime.now().millisecondsSinceEpoch}.html';
    ExcelExportService.downloadHtml(filename, htmlData);
    M3Feedback.showSuccess(
      context,
      'تم إعداد تقرير طباعة الـ Sell-In بنجاح (${records.length} صف)',
    );
  }

  void _handleExportStockBalanceExcel() {
    final d = _stockDashboard;
    if (d == null) return;
    final headers = [
      'السنة (Year)',
      'الشهر (Month)',
      'حالة الفترة',
      'رصيد أول الشهر بالكرتونة (Opening Cases)',
      'رصيد أول الشهر بالجنيه (Opening EGP)',
      'التوريد الشهري بالكرتونة (Sell-In Cases)',
      'قيمة التوريد الشهري (Sell-In EGP)',
      'المبيعات الفعلية بالكرتونة التقديرية (Sell-Out Cases)',
      'قيمة المبيعات الفعلية (Sell-Out EGP)',
      'صافي حركة الشهر بالكرتونة (Monthly Net Cases)',
      'صافي حركة الشهر بالجنيه (Monthly Net EGP)',
      'الرصيد المتبقي آخر الشهر بالكرتونة (Closing Stock Cases)',
      'الرصيد المتبقي آخر الشهر بالجنيه (Closing Stock EGP)',
      'نسبة التصريف (Sell-Through %)',
      'تشخيص حالة الرصيد (Stock Health)',
    ];
    final rows = d.monthlyReconciliation
        .map(
          (m) => [
            m.year,
            '${m.monthNum} - ${m.monthAr}',
            m.periodStatus,
            m.openingStockCases.toStringAsFixed(1),
            m.openingStockValueEgp.toStringAsFixed(2),
            m.sellInCases.toStringAsFixed(1),
            m.sellInValueEgp.toStringAsFixed(2),
            m.sellOutEstCases.toStringAsFixed(1),
            m.sellOutValueEgp.toStringAsFixed(2),
            m.monthlyNetCases.toStringAsFixed(1),
            m.monthlyNetValueEgp.toStringAsFixed(2),
            m.closingStockCases.toStringAsFixed(1),
            m.closingStockValueEgp.toStringAsFixed(2),
            m.sellThroughRatePct.toStringAsFixed(1),
            m.stockHealthLabelAr,
          ],
        )
        .toList();
    final csvData = ExcelExportService.generateCsv(headers: headers, rows: rows);
    final filename =
        'tashil_remaining_stock_sellin_vs_sellout_${DateTime.now().millisecondsSinceEpoch}.csv';
    ExcelExportService.downloadCsv(filename, csvData);
    M3Feedback.showSuccess(
      context,
      'تم تصدير تقرير الأرصدة المتبقية (Sell-In vs Sell-Out) إلى ملف Excel بنجاح',
    );
  }

  void _handlePrintStockBalancePdf() {
    final d = _stockDashboard;
    if (d == null) return;
    final headers = [
      'الشهر / السنة',
      'رصيد أول الشهر',
      'التوريد (Sell-In)',
      'المبيعات (Sell-Out)',
      'صافي الشهر',
      'الرصيد المتبقي آخر الشهر',
      'نسبة التصريف %',
      'حالة الرصيد',
    ];
    final rows = d.monthlyReconciliation
        .map(
          (m) => [
            '${m.monthAr} ${m.year}',
            '${CurrencyFormatter.formatNumber(m.openingStockCases.round())} كرتونة',
            '${CurrencyFormatter.formatEGP(m.sellInValueEgp)} (${m.sellInCases.round()} ك)',
            '${CurrencyFormatter.formatEGP(m.sellOutValueEgp)} (${m.sellOutEstCases.round()} ك)',
            CurrencyFormatter.formatEGP(m.monthlyNetValueEgp),
            '${CurrencyFormatter.formatEGP(m.closingStockValueEgp)} (${m.closingStockCases.round()} كرتونة)',
            '${m.sellThroughRatePct.toStringAsFixed(1)}%',
            m.stockHealthLabelAr,
          ],
        )
        .toList();
    final htmlData = ExcelExportService.generatePrintableReport(
      title: 'تقرير الأرصدة المتبقية ومطابقة الـ Sell-In مع الـ Sell-Out شهر بشهر',
      headers: headers,
      rows: rows,
      metadata: {
        'إجمالي التوريد التراكمي (Sell-In)':
            CurrencyFormatter.formatEGP(d.ytd2026SellInEgp),
        'الرصيد المتبقي الحالي لدى السلاسل':
            '${CurrencyFormatter.formatEGP(d.totalEstimatedStockEgp)} (${CurrencyFormatter.formatNumber(d.totalEstimatedStockCases.round())} كرتونة)',
        'أوامر التوريد المقترحة (Suggested PO)':
            '${CurrencyFormatter.formatEGP(d.totalSuggestedPoEgp)} (${d.totalSuggestedPoCases} كرتونة)',
      },
    );
    final filename =
        'tashil_remaining_stock_report_${DateTime.now().millisecondsSinceEpoch}.html';
    ExcelExportService.downloadHtml(filename, htmlData);
    M3Feedback.showSuccess(
      context,
      'تم إعداد تقرير طباعة الأرصدة المتبقية (Sell-In vs Sell-Out) بنجاح',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 600.0;

    return SingleChildScrollView(
      padding: isCompact ? M3Spacing.pSm : M3Spacing.pMd,
      child: M3ContentBoundary(
        maxWidth: double.infinity,
        alignment: AlignmentDirectional.topStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const M3PageHeader(
              titleEn: 'Sell-In Analytics, Remaining Stock & Sheets Archive',
              subtitleAr:
                  'منظومة التوريد للسلاسل التجارية (Sell-In)، حساب الأرصدة المتبقية (Sell-In − Sell-Out)، المستهدفات، وإدارة الشيتات المرفوعة تراكمياً',
            ),

            M3Spacing.gapSM,

            // Top Tab Switcher: 100% Responsive Full-Width MD3 Large Tab Bar (4 Symmetrical Tabs)
            M3ResponsiveTabBar<int>(
              textDirection: TextDirection.ltr,
              selectedValue: _activeTab,
              items: [
                const M3ResponsiveTabItem<int>(
                  value: 0,
                  icon: Icons.local_shipping_outlined,
                  selectedIcon: Icons.local_shipping_rounded,
                  label: 'Sell-In Data & Operations',
                ),
                const M3ResponsiveTabItem<int>(
                  value: 1,
                  icon: Icons.warehouse_outlined,
                  selectedIcon: Icons.warehouse_rounded,
                  label: 'Remaining Stock & Reports (Sell-In − Sell-Out)',
                ),
                const M3ResponsiveTabItem<int>(
                  value: 2,
                  icon: Icons.track_changes_outlined,
                  selectedIcon: Icons.track_changes_rounded,
                  label: 'Target Management (Sell-In)',
                ),
                M3ResponsiveTabItem<int>(
                  value: 3,
                  icon: Icons.folder_copy_outlined,
                  selectedIcon: Icons.folder_copy_rounded,
                  label: 'Uploaded Sheets (${_archivedSellInFiles.length})',
                ),
              ],
              onChanged: (next) {
                setState(() => _activeTab = next);
                if (next == 1) {
                  _loadStockReconciliationReport();
                } else if (next == 3) {
                  _loadSellInArchive();
                }
              },
            ),

            M3Spacing.gapMD,

            if (_activeTab == 2)
              TargetManagementPanel(
                key: ValueKey('sell_in_targets_${widget.apiClient.tenantId}'),
                apiClient: widget.apiClient,
                targetType: 'sell_in',
              )
            else if (_activeTab == 1)
              _buildRemainingStockAndReportsTab(context, theme, colorScheme)
            else if (_activeTab == 3)
              _buildUploadedSellInSheetsTab(context, theme, colorScheme)
            else
              _buildSellInExplorerTab(context, theme, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterfallMetricPill(
    BuildContext context, {
    required String labelAr,
    required String valueText,
    required String subText,
    required Color accentColor,
    required IconData icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: accentColor.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Icon(icon, size: 18.0, color: accentColor),
          ),
          const SizedBox(width: 10.0),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labelAr,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2.0),
              Text(
                valueText,
                style: TextStyle(
                  fontSize: 15.0,
                  fontWeight: FontWeight.w900,
                  color: accentColor,
                ),
              ),
              Text(
                subText,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 0: SELL-IN DATA & TRANSACTIONS EXPLORER
  // ===========================================================================
  Widget _buildSellInExplorerTab(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final netExclVat = _data.totalNetExclVatEgp > 0
        ? _data.totalNetExclVatEgp
        : _data.totalValueEgp;
    final vat14 = _data.totalVat14Egp > 0
        ? _data.totalVat14Egp
        : netExclVat * 0.14;
    final grossInclVat = _data.totalGrossInclVatEgp > 0
        ? _data.totalGrossInclVatEgp
        : netExclVat + vat14;
    final officialListExcl = _data.totalOfficialListExclVatEgp > 0
        ? _data.totalOfficialListExclVatEgp
        : netExclVat;
    final discountGranted = _data.totalDiscountGrantedEgp;
    final discountPct = _data.effectiveDiscountPct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Summary KPI Row - Stretches across full horizontal width
        LayoutBuilder(
          builder: (context, constraints) {
            final card1 = _buildSummaryCard(
              context,
              titleAr: 'إجمالي صافي التوريد (غير شامل الضريبة)',
              titleEn: 'Total Net Sell-In (Excl. VAT)',
              value: CurrencyFormatter.formatCompactEGP(netExclVat),
              subtitle:
                  'شامل 14% ضريبة: ${CurrencyFormatter.formatCompactEGP(grossInclVat)} • ${_data.totalCount} حركة',
              icon: Icons.payments_rounded,
              color: colorScheme.primary,
            );
            final card2 = _buildSummaryCard(
              context,
              titleAr: 'إجمالي الكمية بالكرتونة والقطعة',
              titleEn: 'Total Cases & Pieces',
              value:
                  '${CurrencyFormatter.formatNumber(_data.totalCases.round())} كرتونة',
              subtitle: _data.totalUnitsPieces > 0
                  ? 'توازي ${CurrencyFormatter.formatNumber(_data.totalUnitsPieces)} قطعة (بشد الكارتة الحقيقي)'
                  : 'كرتونة موردة للسلاسل',
              icon: Icons.inventory_2_rounded,
              color: Colors.teal.shade700,
            );
            final card3 = _buildSummaryCard(
              context,
              titleAr: 'إجمالي الوزن الفعلي',
              titleEn: 'Total Weight (Tons)',
              value: '${_data.totalWeightTons.toStringAsFixed(1)} طن',
              subtitle:
                  'خصم تجاري فعلي عن الكارتة: ${discountPct.toStringAsFixed(1)}%',
              icon: Icons.scale_rounded,
              color: Colors.indigo.shade700,
            );
            final card4 = _buildSummaryCard(
              context,
              titleAr: 'إجمالي الفواتير شامل ضريبة 14%',
              titleEn: 'Gross Sell-In (Incl. 14% VAT)',
              value: CurrencyFormatter.formatCompactEGP(grossInclVat),
              subtitle:
                  'ضريبة القيمة المضافة: ${CurrencyFormatter.formatCompactEGP(vat14)} • المتوقع: ${CurrencyFormatter.formatCompactEGP(_data.totalExpectedEgp)}',
              icon: Icons.receipt_long_rounded,
              color: Colors.orange.shade800,
            );

            return _buildFourCardResponsiveLayout(
              constraints.maxWidth,
              card1,
              card2,
              card3,
              card4,
            );
          },
        ),

        M3Spacing.gapMD,

        // 1.B Tax & Discount Waterfall Banner (Product Master Official Price vs Net Invoice vs 14% VAT)
        Container(
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primaryContainer.withOpacity(0.32),
                colorScheme.secondaryContainer.withOpacity(0.24),
              ],
            ),
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: colorScheme.primary.withOpacity(0.28),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_tree_rounded,
                    size: 20.0,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      'شريط التدفق المالي والضريبي (Tax & Discount Waterfall — ربط مباشر مع كارتة الأصناف Product Master 2026)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10.0,
                      vertical: 4.0,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999.0),
                    ),
                    child: Text(
                      'اضغط على أي صنف بالجدول لفتح بطاقة الهوية (Product ID Card)',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10.0),
              Wrap(
                spacing: 10.0,
                runSpacing: 10.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildWaterfallMetricPill(
                    context,
                    labelAr: '1. التوريد بالسعر الرسمي (قبل الخصم)',
                    valueText: CurrencyFormatter.formatCompactEGP(officialListExcl),
                    subText: 'وفق سعر الكرتونة بكارتة الأصناف',
                    accentColor: Colors.blueGrey.shade700,
                    icon: Icons.price_check_rounded,
                  ),
                  Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 18.0,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  _buildWaterfallMetricPill(
                    context,
                    labelAr: '2. إجمالي الخصم التجاري الممنوح للسلسلة',
                    valueText:
                        '${CurrencyFormatter.formatCompactEGP(discountGranted)} (${discountPct.toStringAsFixed(1)}%)',
                    subText: 'خصم فاتورة + خصم إضافي (10% + 5%)',
                    accentColor: Colors.deepOrange.shade700,
                    icon: Icons.discount_outlined,
                  ),
                  Icon(
                    Icons.drag_handle_rounded,
                    size: 18.0,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  _buildWaterfallMetricPill(
                    context,
                    labelAr: '3. صافي التوريد الفعلي (غير شامل الضريبة)',
                    valueText: CurrencyFormatter.formatCompactEGP(netExclVat),
                    subText:
                        '${CurrencyFormatter.formatNumber(_data.totalCases.round())} كرتونة • ${CurrencyFormatter.formatNumber(_data.totalUnitsPieces)} قطعة',
                    accentColor: colorScheme.primary,
                    icon: Icons.local_shipping_outlined,
                  ),
                  Icon(
                    Icons.add_circle_outline_rounded,
                    size: 18.0,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  _buildWaterfallMetricPill(
                    context,
                    labelAr: '4. ضريبة القيمة المضافة (14% VAT)',
                    valueText: CurrencyFormatter.formatCompactEGP(vat14),
                    subText: 'ضريبة مبيعات 14% قانونية',
                    accentColor: Colors.purple.shade700,
                    icon: Icons.percent_rounded,
                  ),
                  Icon(
                    Icons.arrow_back_rounded,
                    size: 18.0,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  _buildWaterfallMetricPill(
                    context,
                    labelAr: '5. إجمالي الفواتير (شامل ضريبة 14%)',
                    valueText: CurrencyFormatter.formatCompactEGP(grossInclVat),
                    subText: 'إجمالي المطالبة المالية على السلسلة',
                    accentColor: Colors.teal.shade800,
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // 2. Filter & Upload Toolbar
        Container(
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Wrap(
            spacing: 12.0,
            runSpacing: 10.0,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 10.0,
                runSpacing: 8.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 190.0,
                    child: DropdownButtonFormField<String>(
                      value: _selectedChain,
                      decoration: InputDecoration(
                        labelText: 'Chain',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 10.0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All Chains'),
                        ),
                        DropdownMenuItem(
                          value: 'fathalla',
                          child: Text('Fathalla Market'),
                        ),
                        DropdownMenuItem(
                          value: 'gomla',
                          child: Text('Gomla Market'),
                        ),
                        DropdownMenuItem(
                          value: 'beet-elgomla',
                          child: Text('Beet El Gomla'),
                        ),
                        DropdownMenuItem(
                          value: 'chain-1080314',
                          child: Text('El Wakala'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _selectedChain = v);
                          _loadSellInRecords();
                          _loadStockReconciliationReport();
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 130.0,
                    child: DropdownButtonFormField<int>(
                      value: _selectedYear,
                      decoration: InputDecoration(
                        labelText: 'Year',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 10.0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('All Years')),
                        DropdownMenuItem(value: 2026, child: Text('2026')),
                        DropdownMenuItem(value: 2025, child: Text('2025')),
                        DropdownMenuItem(value: 2024, child: Text('2024')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _selectedYear = v);
                          _loadSellInRecords();
                          _loadStockReconciliationReport();
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 150.0,
                    child: DropdownButtonFormField<int>(
                      value: _selectedMonth,
                      decoration: InputDecoration(
                        labelText: 'Month',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 10.0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('All Months')),
                        DropdownMenuItem(value: 1, child: Text('January (01)')),
                        DropdownMenuItem(value: 2, child: Text('February (02)')),
                        DropdownMenuItem(value: 3, child: Text('March (03)')),
                        DropdownMenuItem(value: 4, child: Text('April (04)')),
                        DropdownMenuItem(value: 5, child: Text('May (05)')),
                        DropdownMenuItem(value: 6, child: Text('June (06)')),
                        DropdownMenuItem(value: 7, child: Text('July (07)')),
                        DropdownMenuItem(value: 8, child: Text('August (08)')),
                        DropdownMenuItem(value: 9, child: Text('September (09)')),
                        DropdownMenuItem(value: 10, child: Text('October (10)')),
                        DropdownMenuItem(value: 11, child: Text('November (11)')),
                        DropdownMenuItem(value: 12, child: Text('December (12)')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _selectedMonth = v);
                          _loadSellInRecords();
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220.0,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'بحث بالصنف أو الكرتونة',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w300,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18.0),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 10.0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                      onChanged: (val) {
                        _searchQuery = val;
                        _loadSellInRecords();
                      },
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44.0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18.0,
                        vertical: 10.0,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: _isUploading ? null : () => _pickAndUploadSellInFile(),
                    icon: _isUploading
                        ? const SizedBox(
                            width: 18.0,
                            height: 18.0,
                            child: CircularProgressIndicator(strokeWidth: 2.0),
                          )
                        : const Icon(Icons.upload_file_rounded, size: 20.0),
                    label: const Text('Upload Sell In'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44.0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18.0,
                        vertical: 10.0,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: _handleExportExcel,
                    icon: const Icon(Icons.download_rounded, size: 20.0),
                    label: const Text('Export Excel'),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44.0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18.0,
                        vertical: 10.0,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: _handleExportPdf,
                    icon: const Icon(Icons.print_rounded, size: 20.0),
                    label: const Text('Print PDF'),
                  ),
                ],
              ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // 3. Sell-In Records Table
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(48.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _data.records.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Center(
                        child: Text(
                          'لا توجد حركات توريد (Sell-In) مطابقة للفلتر المحدد حالياً.',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : TableScrollContainer(
                      controller: _recordsTableScrollController,
                      showSwipeHint: true,
                      padding: const EdgeInsets.all(16.0),
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          colorScheme.surfaceContainerHigh.withOpacity(0.5),
                        ),
                        columns: const [
                          DataColumn(label: Text('الفترة (Period)')),
                          DataColumn(label: Text('السلسلة / الفرع')),
                          DataColumn(label: Text('اسم الصنف وهوية الكارتة (SKU / ID Card)')),
                          DataColumn(label: Text('العلامة / القسم')),
                          DataColumn(label: Text('مندوب المبيعات')),
                          DataColumn(
                            numeric: true,
                            label: Text('الشد والكمية (كرتونة / قطعة)'),
                          ),
                          DataColumn(
                            numeric: true,
                            label: Text('سعر الكرتونة (فعلي vs كارتة)'),
                          ),
                          DataColumn(
                            numeric: true,
                            label: Text('صافي التوريد (غير شامل الضريبة)'),
                          ),
                          DataColumn(
                            numeric: true,
                            label: Text('الإجمالي شامل 14% ضريبة'),
                          ),
                          DataColumn(
                            numeric: true,
                            label: Text('الوزن (Tons)'),
                          ),
                          DataColumn(
                            label: Text('الشيت المصدري (Sheet)'),
                          ),
                        ],
                        rows: _data.records.map((r) {
                          final hasIdCard = r.itemCode.isNotEmpty || r.barcode.isNotEmpty;
                          final unitsSupplied = r.totalUnitsSupplied > 0
                              ? r.totalUnitsSupplied
                              : (r.netQtyCases * (r.unitsPerCarton > 0 ? r.unitsPerCarton : 12)).round();
                          final grossInclVat = r.grossValueInclVatEgp > 0
                              ? r.grossValueInclVatEgp
                              : r.netValueEgp * 1.14;
                          final vatAmount = r.vatAmountEgp > 0
                              ? r.vatAmountEgp
                              : r.netValueEgp * 0.14;
                          final actualCasePrice = r.actualCasePriceExclEgp > 0
                              ? r.actualCasePriceExclEgp
                              : (r.netQtyCases > 0 ? r.netValueEgp / r.netQtyCases : 0.0);

                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  '${r.monthAr.isNotEmpty ? r.monthAr : r.monthNum} ${r.year}',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              DataCell(
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                        vertical: 2.0,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer.withOpacity(0.6),
                                        borderRadius: BorderRadius.circular(999.0),
                                      ),
                                      child: Text(
                                        r.retailerChain.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2.0),
                                    Text(
                                      r.customerName.isNotEmpty
                                          ? '${r.governorate} • ${r.customerName}'
                                          : r.governorate,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(
                                InkWell(
                                  borderRadius: BorderRadius.circular(8.0),
                                  onTap: () => _openProductIdCard(
                                    itemCode: r.itemCode,
                                    barcode: r.barcode,
                                    skuName: r.itemName,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                r.itemName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4.0),
                                            Icon(
                                              Icons.badge_outlined,
                                              size: 15.0,
                                              color: colorScheme.primary,
                                            ),
                                          ],
                                        ),
                                        if (hasIdCard)
                                          Text(
                                            'كود: ${r.itemCode.isNotEmpty ? r.itemCode : "-"} • باركود: ${r.barcode.isNotEmpty ? r.barcode : "-"}',
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${r.brand} • ${r.subCategory}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.0,
                                      ),
                                    ),
                                    if (r.departmentAr.isNotEmpty)
                                      Text(
                                        r.departmentAr,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              DataCell(Text(r.salesRep)),
                              DataCell(
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${CurrencyFormatter.formatNumber(r.netQtyCases.round())} كرتونة',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    Text(
                                      '${CurrencyFormatter.formatNumber(unitsSupplied)} قطعة (شد ${r.unitsPerCarton > 0 ? r.unitsPerCarton : 12})',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.teal.shade700,
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
                                      'فعلي: ${CurrencyFormatter.formatEGP(actualCasePrice)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.0,
                                      ),
                                    ),
                                    if (r.officialCartonExclVatEgp > 0)
                                      Text(
                                        'كارتة: ${CurrencyFormatter.formatEGP(r.officialCartonExclVatEgp)} (${r.effectiveDiscountPct > 0 ? "خصم ${r.effectiveDiscountPct.toStringAsFixed(1)}%" : r.pricingWaveStatus})',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              DataCell(
                                Text(
                                  CurrencyFormatter.formatEGP(r.netValueEgp),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                              DataCell(
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      CurrencyFormatter.formatEGP(grossInclVat),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Colors.teal.shade800,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    Text(
                                      'ضريبة 14%: ${CurrencyFormatter.formatEGP(vatAmount)}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(Text('${r.weightTons.toStringAsFixed(2)} طن')),
                              DataCell(
                                Text(
                                  r.sourceFilename.isNotEmpty
                                      ? r.sourceFilename
                                      : 'Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 1: REMAINING STOCK BALANCE (SELL-IN − SELL-OUT) & REPORTS
  // ===========================================================================
  Widget _buildRemainingStockAndReportsTab(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final d = _stockDashboard;
    if (_isLoadingStockReport && d == null) {
      return const Padding(
        padding: EdgeInsets.all(64.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (d == null) {
      return Padding(
        padding: const EdgeInsets.all(48.0),
        child: Center(
          child: Text(
            'لا توجد بيانات مطابقة حالياً لحساب الأرصدة المتبقية.',
            style: theme.textTheme.titleMedium,
          ),
        ),
      );
    }

    // Compute aggregate Sell-Out across all reconciliation months
    double totalSellOutEgp = 0;
    double totalSellOutEstCases = 0;
    for (final m in d.monthlyReconciliation) {
      totalSellOutEgp += m.sellOutValueEgp;
      totalSellOutEstCases += m.sellOutEstCases;
    }

    // Use Matched Window (Jan-Aug) by default so Sell-In vs Sell-Out is 100% apples-to-apples
    final useMatchedWindow = !_showFullYtdReconciliation && d.matchedMonthsCount > 0;
    final displaySellInEgp = useMatchedWindow
        ? d.matchedSellInValueExclVatEgp
        : d.ytd2026SellInEgp;
    final displaySellInGrossEgp = useMatchedWindow
        ? d.matchedSellInGrossInclVatEgp
        : d.ytd2026GrossInclVatEgp;
    final displaySellInCases = useMatchedWindow
        ? d.matchedSellInCases
        : d.ytd2026SellInCases;
    final displaySellOutPosEgp = useMatchedWindow && d.matchedSellOutPosValueEgp > 0
        ? d.matchedSellOutPosValueEgp
        : totalSellOutEgp;
    final displaySellOutFactoryCostEgp = useMatchedWindow && d.matchedSellOutFactoryCostEgp > 0
        ? d.matchedSellOutFactoryCostEgp
        : totalSellOutEgp;
    final displaySellOutCases = useMatchedWindow && d.matchedSellOutCases > 0
        ? d.matchedSellOutCases
        : totalSellOutEstCases;
    final remainingStockEgp = useMatchedWindow
        ? d.matchedRemainingFactoryValueEgp
        : (d.monthlyReconciliation.isNotEmpty
            ? d.monthlyReconciliation.last.closingStockValueEgp
            : d.totalEstimatedStockEgp);
    final remainingStockCases = useMatchedWindow
        ? d.matchedRemainingCases
        : (d.monthlyReconciliation.isNotEmpty
            ? d.monthlyReconciliation.last.closingStockCases
            : d.totalEstimatedStockCases);
    final overallStrPct = useMatchedWindow && d.matchedSellThroughPct > 0
        ? d.matchedSellThroughPct
        : (displaySellInEgp > 0
            ? (displaySellOutFactoryCostEgp / displaySellInEgp) * 100.0
            : d.jan2026SellThroughPct);

    final matchedLabel = d.matchedPeriodLabel.isNotEmpty
        ? d.matchedPeriodLabel
        : 'يناير - أبريل 2026';
    final pendingLabel = d.pendingSellOutPeriodLabel.isNotEmpty
        ? d.pendingSellOutPeriodLabel
        : 'مايو - أكتوبر 2026';

    final visibleMonthlyRows = _showFullYtdReconciliation
        ? d.monthlyReconciliation
        : d.monthlyReconciliation
            .where((m) => m.hasActualSellOut || m.sellOutValueEgp > 0)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 0. Matched Period vs Full YTD Toggle Banner + Pending Sell-Out Notice
        Container(
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primaryContainer.withOpacity(0.35),
                colorScheme.tertiaryContainer.withOpacity(0.25),
              ],
            ),
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: colorScheme.primary.withOpacity(0.3),
            ),
          ),
          child: Wrap(
            spacing: 14.0,
            runSpacing: 10.0,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sync_alt_rounded,
                    color: colorScheme.primary,
                    size: 22.0,
                  ),
                  const SizedBox(width: 10.0),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الربط الثلاثي الذكي (Sell-In × Sell-Out × كارتة الأصناف Product Master)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'يتم تحويل مبيعات الكاشير بالقطعة إلى كراتين بشد الكارتة الحقيقي لكل صنف وحساب ربح السلسلة الفعلي بعد خصم تكلفة المصنع',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    selected: !_showFullYtdReconciliation,
                    label: Text(
                      'الفترة المتطابقة ($matchedLabel — ${d.matchedMonthsCount > 0 ? d.matchedMonthsCount : 4} أشهر)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: !_showFullYtdReconciliation
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                    onSelected: (_) => setState(() => _showFullYtdReconciliation = false),
                  ),
                  ChoiceChip(
                    selected: _showFullYtdReconciliation,
                    label: Text(
                      'إجمالي العام شامل التوريدات تحت التصريف (يناير - أكتوبر)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: _showFullYtdReconciliation
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                    onSelected: (_) => setState(() => _showFullYtdReconciliation = true),
                  ),
                  if (d.pendingSellOutCases > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 6.0,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(color: Colors.amber.shade700.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hourglass_top_rounded,
                            size: 15.0,
                            color: Colors.amber.shade900,
                          ),
                          const SizedBox(width: 6.0),
                          Text(
                            'توريدات تحت التصريف ($pendingLabel): ${CurrencyFormatter.formatNumber(d.pendingSellOutCases.round())} كرتونة (${CurrencyFormatter.formatCompactEGP(d.pendingSellOutValueEgp)}) بانتظار رفع شيت الكاشير',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // 1. 4 Prominent Full-Width KPI Cards for Sell-In vs Sell-Out & Remaining Stock
        LayoutBuilder(
          builder: (context, constraints) {
            final card1 = _buildSummaryCard(
              context,
              titleAr: useMatchedWindow
                  ? 'التوريد للفترة المتطابقة ($matchedLabel)'
                  : 'إجمالي التوريد التراكمي (Sell-In YTD)',
              titleEn: 'Supplied Stock (Excl. & Incl. VAT)',
              value: CurrencyFormatter.formatCompactEGP(displaySellInEgp),
              subtitle:
                  '${CurrencyFormatter.formatNumber(displaySellInCases.round())} كرتونة • شامل الضريبة: ${CurrencyFormatter.formatCompactEGP(displaySellInGrossEgp)}',
              icon: Icons.local_shipping_rounded,
              color: colorScheme.primary,
            );
            final card2 = _buildSummaryCard(
              context,
              titleAr: 'المبيعات الفعلية للكاشير (Sell-Out)',
              titleEn: 'Actual Cashier POS & Factory Cost',
              value: CurrencyFormatter.formatCompactEGP(displaySellOutPosEgp),
              subtitle:
                  '${CurrencyFormatter.formatNumber(displaySellOutCases.round())} كرتونة حقيقية (${CurrencyFormatter.formatNumber(d.matchedSellOutUnits)} قطعة) • بتكلفة مصنع ${CurrencyFormatter.formatCompactEGP(displaySellOutFactoryCostEgp)}',
              icon: Icons.point_of_sale_rounded,
              color: Colors.teal.shade700,
            );
            final card3 = _buildSummaryCard(
              context,
              titleAr: 'الرصيد المتبقي الفعلي لدى السلسلة',
              titleEn: 'Remaining Stock (Sell-In − Sell-Out)',
              value: CurrencyFormatter.formatCompactEGP(remainingStockEgp),
              subtitle:
                  '${CurrencyFormatter.formatNumber(remainingStockCases.round())} كرتونة متبقية فعلياً بعد خصم السحب الحقيقي',
              icon: Icons.warehouse_rounded,
              color: Colors.deepOrange.shade700,
            );
            final card4 = _buildSummaryCard(
              context,
              titleAr: 'نسبة التصريف وأوامر التوريد (STR %)',
              titleEn: 'Real Sell-Through % & Suggested PO',
              value: '${overallStrPct.toStringAsFixed(1)}%',
              subtitle:
                  '${d.urgentReplenishmentCount} صنف يحتاج توريد فوري (${d.totalSuggestedPoCases} كرتونة مقترحة)',
              icon: Icons.autorenew_rounded,
              color: Colors.indigo.shade700,
            );

            return _buildFourCardResponsiveLayout(
              constraints.maxWidth,
              card1,
              card2,
              card3,
              card4,
            );
          },
        ),

        M3Spacing.gapSM,

        // 1.B Strategic 3-Way Linkage KPIs: Retailer Gross Margin & YoY 2026 vs 2025 Growth
        LayoutBuilder(
          builder: (context, constraints) {
            final marginCard = _buildSummaryCard(
              context,
              titleAr: 'ربح السلسلة المحقق وهامش الربح الفعلي (Retailer Gross Margin)',
              titleEn: 'Chain POS Revenue − Factory Cost Excl. VAT',
              value:
                  '${CurrencyFormatter.formatCompactEGP(d.matchedChainGrossMarginEgp)} (هامش ${d.matchedChainGrossMarginPct.toStringAsFixed(1)}%)',
              subtitle:
                  'الفرق الفعلي بين سعر بيع الكاشير للمستهلك وتكلفة التوريد الصافية من كارتة الأصناف',
              icon: Icons.paid_rounded,
              color: Colors.green.shade800,
            );
            final yoySign = d.matchedYoyValueGrowthPct >= 0 ? '+' : '';
            final yoyUnitsSign = d.matchedYoyUnitsGrowthPct >= 0 ? '+' : '';
            final yoyCard = _buildSummaryCard(
              context,
              titleAr: 'النمو السنوي لمبيعات الكاشير (2026 مقابل 2025 YoY)',
              titleEn: 'Matched Period YoY Sell-Out Growth',
              value: '$yoySign${d.matchedYoyValueGrowthPct.toStringAsFixed(1)}% نمو قيمة',
              subtitle:
                  'نمو الكميات المباعة بالقطعة: $yoyUnitsSign${d.matchedYoyUnitsGrowthPct.toStringAsFixed(1)}% مقارنة بنفس الشهور في عام 2025',
              icon: Icons.trending_up_rounded,
              color: Colors.purple.shade800,
            );

            if (constraints.maxWidth < 760) {
              return Column(
                children: [
                  marginCard,
                  const SizedBox(height: 10.0),
                  yoyCard,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: marginCard),
                const SizedBox(width: 12.0),
                Expanded(child: yoyCard),
              ],
            );
          },
        ),

        M3Spacing.gapMD,

        // 2. Filter & Export Bar for Stock Balance Reports
        Container(
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Wrap(
            spacing: 12.0,
            runSpacing: 10.0,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 10.0,
                runSpacing: 8.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 190.0,
                    child: DropdownButtonFormField<String>(
                      value: _selectedChain,
                      decoration: InputDecoration(
                        labelText: 'Chain',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 10.0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Chains')),
                        DropdownMenuItem(
                          value: 'fathalla',
                          child: Text('Fathalla Market'),
                        ),
                        DropdownMenuItem(
                          value: 'gomla',
                          child: Text('Gomla Market'),
                        ),
                        DropdownMenuItem(
                          value: 'beet-elgomla',
                          child: Text('Beet El Gomla'),
                        ),
                        DropdownMenuItem(
                          value: 'chain-1080314',
                          child: Text('El Wakala'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _selectedChain = v);
                          _loadStockReconciliationReport();
                          _loadSellInRecords();
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 140.0,
                    child: DropdownButtonFormField<int>(
                      value: _selectedYear,
                      decoration: InputDecoration(
                        labelText: 'Year',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 10.0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('All Years')),
                        DropdownMenuItem(value: 2026, child: Text('2026')),
                        DropdownMenuItem(value: 2025, child: Text('2025')),
                        DropdownMenuItem(value: 2024, child: Text('2024')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _selectedYear = v);
                          _loadStockReconciliationReport();
                          _loadSellInRecords();
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 210.0,
                    child: DropdownButtonFormField<String>(
                      value: _stockStatusFilter,
                      decoration: InputDecoration(
                        labelText: 'Stock Status',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 10.0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Stock States')),
                        DropdownMenuItem(
                          value: 'urgent_replenishment',
                          child: Text('Urgent Replenishment'),
                        ),
                        DropdownMenuItem(
                          value: 'optimal',
                          child: Text('Optimal Balance'),
                        ),
                        DropdownMenuItem(
                          value: 'overstock',
                          child: Text('Overstock / Slow Moving'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _stockStatusFilter = v);
                          _loadStockReconciliationReport();
                        }
                      },
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44.0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18.0,
                        vertical: 10.0,
                      ),
                    ),
                    onPressed: _handleExportStockBalanceExcel,
                    icon: const Icon(Icons.download_rounded, size: 20.0),
                    label: const Text('Export Stock Excel'),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44.0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18.0,
                        vertical: 10.0,
                      ),
                    ),
                    onPressed: _handlePrintStockBalancePdf,
                    icon: const Icon(Icons.print_rounded, size: 20.0),
                    label: const Text('Print Stock PDF'),
                  ),
                ],
              ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // 3. Report 1: Monthly Rolling Stock Balance Table (Sell-In vs Sell-Out Month-by-Month)
        Container(
          padding: const EdgeInsets.all(18.0),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month_rounded, color: colorScheme.primary),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '1. كشف حساب الأرصدة التراكمية شهر بشهر (Monthly Rolling Stock Balance: Sell-In − Sell-Out)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          'المعادلة المحاسبية: رصيد أول الشهر + صافي التوريد الشهري (Sell-In) − المبيعات الفعلية للكاشير (Sell-Out) = الرصيد المتبقي آخر الشهر لدى السلسلة',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14.0),
              TableScrollContainer(
                controller: _monthlyLedgerScrollController,
                showSwipeHint: true,
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                    colorScheme.surfaceContainerHigh.withOpacity(0.5),
                  ),
                  columns: const [
                    DataColumn(label: Text('الشهر / السنة')),
                    DataColumn(label: Text('رصيد أول الشهر (Opening)'), numeric: true),
                    DataColumn(label: Text('+ التوريد الشهري (صافي وشامل 14%)'), numeric: true),
                    DataColumn(label: Text('− مبيعات الكاشير (بشد الكارتة الحقيقي)'), numeric: true),
                    DataColumn(label: Text('ربح السلسلة المحقق (هامش %)'), numeric: true),
                    DataColumn(label: Text('النمو السنوي (2026 vs 2025)'), numeric: true),
                    DataColumn(
                      label: Text('الرصيد المتبقي آخر الشهر (Closing Stock)'),
                      numeric: true,
                    ),
                    DataColumn(label: Text('نسبة التصريف (STR %)'), numeric: true),
                    DataColumn(label: Text('تشخيص حالة الرصيد')),
                  ],
                  rows: visibleMonthlyRows.map((m) {
                    final isPositiveClosing = m.closingStockValueEgp >= 0;
                    final yoySign = m.yoySellOutGrowthPct >= 0 ? '+' : '';
                    return DataRow(
                      cells: [
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${m.monthNum} - ${m.monthAr} ${m.year}',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              if (!m.hasActualSellOut)
                                Text(
                                  'بانتظار شيت كاشير السلسلة',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.amber.shade900,
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
                              Text(CurrencyFormatter.formatEGP(m.openingStockValueEgp)),
                              Text(
                                '${CurrencyFormatter.formatNumber(m.openingStockCases.round())} كرتونة',
                                style: TextStyle(
                                  fontSize: 11.0,
                                  color: colorScheme.onSurfaceVariant,
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
                                CurrencyFormatter.formatEGP(m.sellInValueEgp),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.primary,
                                ),
                              ),
                              Text(
                                '+${CurrencyFormatter.formatNumber(m.sellInCases.round())} كرتونة (${CurrencyFormatter.formatNumber(m.sellInUnits)} قطعة)',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (m.sellInGrossInclVatEgp > 0)
                                Text(
                                  'شامل 14%: ${CurrencyFormatter.formatCompactEGP(m.sellInGrossInclVatEgp)}',
                                  style: TextStyle(
                                    fontSize: 10.0,
                                    color: Colors.teal.shade800,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        DataCell(
                          m.hasActualSellOut
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      CurrencyFormatter.formatEGP(m.sellOutValueEgp),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.teal.shade700,
                                      ),
                                    ),
                                    Text(
                                      '−${CurrencyFormatter.formatNumber(m.sellOutEstCases.round())} كرتونة (${CurrencyFormatter.formatNumber(m.sellOutUnits)} قطعة)',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (m.sellOutFactoryCostExclVatEgp > 0)
                                      Text(
                                        'بتكلفة مصنع: ${CurrencyFormatter.formatCompactEGP(m.sellOutFactoryCostExclVatEgp)}',
                                        style: TextStyle(
                                          fontSize: 10.0,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                )
                              : Text(
                                  'تحت التصريف (Pending POS)',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                        ),
                        DataCell(
                          m.hasActualSellOut
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      CurrencyFormatter.formatEGP(m.chainGrossMarginEgp),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                    Text(
                                      'هامش السلسلة: ${m.chainGrossMarginPct.toStringAsFixed(1)}%',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  ],
                                )
                              : const Text('-'),
                        ),
                        DataCell(
                          m.hasActualSellOut && m.prevYearSellOutValueEgp > 0
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '$yoySign${m.yoySellOutGrowthPct.toStringAsFixed(1)}%',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: m.yoySellOutGrowthPct >= 0
                                            ? Colors.purple.shade800
                                            : colorScheme.error,
                                      ),
                                    ),
                                    Text(
                                      '2025: ${CurrencyFormatter.formatCompactEGP(m.prevYearSellOutValueEgp)}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                )
                              : const Text('-'),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10.0,
                              vertical: 4.0,
                            ),
                            decoration: BoxDecoration(
                              color: isPositiveClosing
                                  ? colorScheme.primaryContainer.withOpacity(0.55)
                                  : colorScheme.errorContainer.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  CurrencyFormatter.formatEGP(m.closingStockValueEgp),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: isPositiveClosing
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onErrorContainer,
                                  ),
                                ),
                                Text(
                                  '${CurrencyFormatter.formatNumber(m.closingStockCases.round())} كرتونة متبقية',
                                  style: TextStyle(
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w700,
                                    color: isPositiveClosing
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onErrorContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            m.hasActualSellOut
                                ? '${m.sellThroughRatePct.toStringAsFixed(1)}%'
                                : 'تحت التصريف',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        DataCell(
                          Text(
                            m.stockHealthLabelAr,
                            style: TextStyle(
                              fontSize: 12.0,
                              fontWeight: FontWeight.w600,
                              color: m.stockHealthStatus == 'overstock'
                                  ? Colors.orange.shade800
                                  : Colors.teal.shade700,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // 4. Report 2: SKU-Level Remaining Stock & Suggested Replenishment PO Table
        Builder(
          builder: (context) {
            // Extract unique brands dynamically using AI-grade inference
            final Map<String, int> brandItemCounts = {};
            for (final item in d.inventoryAndPoItems) {
              final b = item.brand.trim().isNotEmpty
                  ? item.brand.trim()
                  : SmartBrandExtractor.inferBrand(item.skuName, subCategory: item.subCategory);
              brandItemCounts[b] = (brandItemCounts[b] ?? 0) + 1;
            }
            final availableBrands = brandItemCounts.keys.toList()
              ..sort((a, b) => a.compareTo(b));

            // Filter items by Brand, Stock Status, and Search Query
            final filteredSkuItems = d.inventoryAndPoItems.where((item) {
              final brandName = item.brand.trim().isNotEmpty
                  ? item.brand.trim()
                  : SmartBrandExtractor.inferBrand(item.skuName, subCategory: item.subCategory);

              // 1. Brand filter
              if (_selectedSkuBrand != 'all' && brandName != _selectedSkuBrand) {
                return false;
              }
              // 2. Stock status filter
              if (_skuStockStatusFilter != 'all' && item.stockStatus != _skuStockStatusFilter) {
                return false;
              }
              // 3. Search query (Item Code, Barcode, SKU Name, Brand, SubCategory, Governorate)
              if (_skuSearchQuery.trim().isNotEmpty) {
                if (!ApiClient.matchesProductSearch(
                  _skuSearchQuery,
                  itemCode: item.itemCode,
                  barcode: item.barcode,
                  skuName: item.skuName,
                  brand: brandName,
                  category: item.subCategory,
                  storeName: item.governorate,
                )) {
                  return false;
                }
              }
              return true;
            }).toList();

            // Sort items based on active sort column and direction
            filteredSkuItems.sort((a, b) {
              int cmp = 0;
              switch (_skuSortColumnIndex) {
                case 0:
                  cmp = a.skuName.compareTo(b.skuName);
                  break;
                case 1:
                  cmp = a.brand.compareTo(b.brand);
                  break;
                case 2:
                  cmp = a.sellInCases.compareTo(b.sellInCases);
                  break;
                case 3:
                  cmp = a.sellOutEstCases.compareTo(b.sellOutEstCases);
                  break;
                case 4:
                  cmp = a.estimatedStockCases.compareTo(b.estimatedStockCases);
                  break;
                case 5:
                  cmp = a.daysOfInventory.compareTo(b.daysOfInventory);
                  break;
                case 6:
                  cmp = a.stockStatus.compareTo(b.stockStatus);
                  break;
                case 7:
                  cmp = a.suggestedPoCases.compareTo(b.suggestedPoCases);
                  break;
                default:
                  cmp = a.daysOfInventory.compareTo(b.daysOfInventory);
              }
              return _skuSortAscending ? cmp : -cmp;
            });

            // Pagination (25 items per page)
            final totalSkuCount = filteredSkuItems.length;
            final totalSkuPages = (totalSkuCount / _skuPageSize).ceil();
            final clampedCurrentPage = totalSkuPages == 0
                ? 0
                : _skuCurrentPage.clamp(0, totalSkuPages - 1);
            final startIdx = clampedCurrentPage * _skuPageSize;
            final endIdx = (startIdx + _skuPageSize).clamp(0, totalSkuCount);
            final currentSkuPageItems = totalSkuCount == 0
                ? <SKUBranchInventoryModel>[]
                : filteredSkuItems.sublist(startIdx, endIdx);

            return Container(
              padding: const EdgeInsets.all(18.0),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(18.0),
                border: Border.all(
                  color: colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Description
                  Row(
                    children: [
                      Icon(Icons.inventory_rounded, color: Colors.deepOrange.shade700),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '2. تقرير الأرصدة المتبقية على مستوى الأصناف وأوامر التوريد المقترحة (SKU Remaining Stock & Replenishment PO)',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2.0),
                            Text(
                              'يكشف لك لكل صنف: كم كرتونة تم توريدها (Sell-In)، وكم كرتونة بيعت فعلياً (Sell-Out)، والرصيد المتبقي الحالي على الرف، وعدد أيام التغطية المتبقية (DOS)، والكمية المقترح توريدها فوراً',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16.0),

                  // Filter & Search Controls Bar
                  Container(
                    padding: const EdgeInsets.all(14.0),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(14.0),
                      border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 800;
                            final searchField = TextField(
                              controller: _skuSearchController,
                              decoration: InputDecoration(
                                hintText: 'بحث بالصنف أو البراند (مثلاً: Maxell, Diva, Dove)...',
                                hintStyle: TextStyle(fontSize: 13.0, color: colorScheme.onSurfaceVariant),
                                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                suffixIcon: _skuSearchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 18),
                                        onPressed: () {
                                          _skuSearchController.clear();
                                          setState(() {
                                            _skuSearchQuery = '';
                                            _skuCurrentPage = 0;
                                          });
                                        },
                                      )
                                    : null,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10.0),
                                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10.0),
                                  borderSide: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.6)),
                                ),
                                filled: true,
                                fillColor: colorScheme.surface,
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _skuSearchQuery = val;
                                  _skuCurrentPage = 0;
                                });
                              },
                            );

                            final brandDropdown = DropdownButtonFormField<String>(
                              value: availableBrands.contains(_selectedSkuBrand) ? _selectedSkuBrand : 'all',
                              decoration: InputDecoration(
                                labelText: 'البراند / الماركة (Brand)',
                                labelStyle: const TextStyle(fontSize: 12.0),
                                prefixIcon: const Icon(Icons.branding_watermark_rounded, size: 20),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10.0),
                                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10.0),
                                  borderSide: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.6)),
                                ),
                                filled: true,
                                fillColor: colorScheme.surface,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text(
                                    'كل الماركات (All Brands) (${d.inventoryAndPoItems.length})',
                                    style: const TextStyle(fontSize: 13.0, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                ...availableBrands.map(
                                  (b) => DropdownMenuItem(
                                    value: b,
                                    child: Text(
                                      '$b (${brandItemCounts[b] ?? 0})',
                                      style: const TextStyle(fontSize: 13.0),
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedSkuBrand = val;
                                    _skuCurrentPage = 0;
                                  });
                                }
                              },
                            );

                            final statusDropdown = DropdownButtonFormField<String>(
                              value: _skuStockStatusFilter,
                              decoration: InputDecoration(
                                labelText: 'حالة الرصيد (Status)',
                                labelStyle: const TextStyle(fontSize: 12.0),
                                prefixIcon: const Icon(Icons.filter_alt_outlined, size: 20),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10.0),
                                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10.0),
                                  borderSide: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.6)),
                                ),
                                filled: true,
                                fillColor: colorScheme.surface,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text('كل الحالات (All)', style: TextStyle(fontSize: 13.0)),
                                ),
                                DropdownMenuItem(
                                  value: 'urgent_replenishment',
                                  child: Text(
                                    '🚨 خطر نفاد عاجل (Urgent)',
                                    style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.bold, color: Colors.red),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'optimal',
                                  child: Text('✅ رصيد آمن (Optimal)', style: TextStyle(fontSize: 13.0, color: Colors.teal)),
                                ),
                                DropdownMenuItem(
                                  value: 'overstock',
                                  child: Text('⚠️ تكدس مخزني (Overstock)', style: TextStyle(fontSize: 13.0, color: Colors.orange)),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _skuStockStatusFilter = val;
                                    _skuCurrentPage = 0;
                                  });
                                }
                              },
                            );

                            if (isNarrow) {
                              return Column(
                                children: [
                                  searchField,
                                  const SizedBox(height: 10.0),
                                  Row(
                                    children: [
                                      Expanded(child: brandDropdown),
                                      const SizedBox(width: 8.0),
                                      Expanded(child: statusDropdown),
                                    ],
                                  ),
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(flex: 3, child: searchField),
                                const SizedBox(width: 12.0),
                                Expanded(flex: 2, child: brandDropdown),
                                const SizedBox(width: 12.0),
                                Expanded(flex: 2, child: statusDropdown),
                              ],
                            );
                          },
                        ),
                        if (availableBrands.isNotEmpty) ...[
                          const SizedBox(height: 10.0),
                          Wrap(
                            spacing: 6.0,
                            runSpacing: 6.0,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'فلترة سريعة بالبراند: ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              FilterChip(
                                selected: _selectedSkuBrand == 'all',
                                label: Text('الكل (${d.inventoryAndPoItems.length})'),
                                onSelected: (_) => setState(() {
                                  _selectedSkuBrand = 'all';
                                  _skuCurrentPage = 0;
                                }),
                              ),
                              ...availableBrands.take(12).map((b) {
                                final isSelected = _selectedSkuBrand == b;
                                return FilterChip(
                                  selected: isSelected,
                                  label: Text('$b (${brandItemCounts[b] ?? 0})'),
                                  onSelected: (_) => setState(() {
                                    _selectedSkuBrand = isSelected ? 'all' : b;
                                    _skuCurrentPage = 0;
                                  }),
                                );
                              }),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 14.0),

                  // Table with Column Sorting and Double Click Support
                  TableScrollContainer(
                    controller: _skuStockScrollController,
                    showSwipeHint: true,
                    child: DataTable(
                      sortColumnIndex: _skuSortColumnIndex,
                      sortAscending: _skuSortAscending,
                      headingRowColor: WidgetStatePropertyAll(
                        colorScheme.surfaceContainerHigh.withOpacity(0.5),
                      ),
                      columns: [
                        DataColumn(
                          label: InkWell(
                            onTap: () => _onSortSku(0, !_skuSortAscending),
                            onDoubleTap: () => _onSortSku(0, !_skuSortAscending),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4.0),
                              child: Text('اسم الصنف (SKU)'),
                            ),
                          ),
                          onSort: (col, asc) => _onSortSku(0, asc),
                        ),
                        DataColumn(
                          label: InkWell(
                            onTap: () => _onSortSku(1, !_skuSortAscending),
                            onDoubleTap: () => _onSortSku(1, !_skuSortAscending),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4.0),
                              child: Text('العلامة / البراند'),
                            ),
                          ),
                          onSort: (col, asc) => _onSortSku(1, asc),
                        ),
                        DataColumn(
                          label: InkWell(
                            onTap: () => _onSortSku(2, !_skuSortAscending),
                            onDoubleTap: () => _onSortSku(2, !_skuSortAscending),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4.0),
                              child: Text('إجمالي التوريد (Sell-In)'),
                            ),
                          ),
                          numeric: true,
                          onSort: (col, asc) => _onSortSku(2, asc),
                        ),
                        DataColumn(
                          label: InkWell(
                            onTap: () => _onSortSku(3, !_skuSortAscending),
                            onDoubleTap: () => _onSortSku(3, !_skuSortAscending),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4.0),
                              child: Text('المبيعات الفعلية (Sell-Out)'),
                            ),
                          ),
                          numeric: true,
                          onSort: (col, asc) => _onSortSku(3, asc),
                        ),
                        DataColumn(
                          label: Tooltip(
                            message: 'اضغط أو انقر نقراً مزدوجاً للترتيب بالأعلى أو الأقل',
                            child: InkWell(
                              onTap: () => _onSortSku(4, !_skuSortAscending),
                              onDoubleTap: () => _onSortSku(4, !_skuSortAscending),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('الرصيد المتبقي (Stock)'),
                                    SizedBox(width: 4.0),
                                    Icon(Icons.swap_vert_rounded, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          numeric: true,
                          onSort: (col, asc) => _onSortSku(4, asc),
                        ),
                        DataColumn(
                          label: Tooltip(
                            message: 'اضغط أو انقر نقراً مزدوجاً للترتيب حسب أيام التغطية (DOS)',
                            child: InkWell(
                              onTap: () => _onSortSku(5, !_skuSortAscending),
                              onDoubleTap: () => _onSortSku(5, !_skuSortAscending),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('أيام التغطية (DOS)'),
                                    SizedBox(width: 4.0),
                                    Icon(Icons.swap_vert_rounded, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          numeric: true,
                          onSort: (col, asc) => _onSortSku(5, asc),
                        ),
                        DataColumn(
                          label: InkWell(
                            onTap: () => _onSortSku(6, !_skuSortAscending),
                            onDoubleTap: () => _onSortSku(6, !_skuSortAscending),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4.0),
                              child: Text('حالة الرصيد'),
                            ),
                          ),
                          onSort: (col, asc) => _onSortSku(6, asc),
                        ),
                        DataColumn(
                          label: InkWell(
                            onTap: () => _onSortSku(7, !_skuSortAscending),
                            onDoubleTap: () => _onSortSku(7, !_skuSortAscending),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4.0),
                              child: Text('أمر التوريد المقترح (PO)'),
                            ),
                          ),
                          numeric: true,
                          onSort: (col, asc) => _onSortSku(7, asc),
                        ),
                      ],
                      rows: currentSkuPageItems.map((item) {
                        final isUrgent = item.stockStatus == 'urgent_replenishment';
                        final isOverstock = item.stockStatus == 'overstock';
                        final packUnits = item.unitsPerCarton > 0 ? item.unitsPerCarton : 12;
                        final sellInUnits = item.sellInUnits > 0
                            ? item.sellInUnits
                            : (item.sellInCases * packUnits).round();
                        final sellOutUnits = item.sellOutUnits > 0
                            ? item.sellOutUnits
                            : (item.sellOutEstCases * packUnits).round();
                        final stockCases = useMatchedWindow && item.matchedRemainingCases > 0
                            ? item.matchedRemainingCases
                            : item.estimatedStockCases;
                        final stockVal = useMatchedWindow && item.matchedRemainingValueEgp > 0
                            ? item.matchedRemainingValueEgp
                            : item.estimatedStockValueEgp;
                        final stockUnits = item.estimatedStockUnits > 0
                            ? item.estimatedStockUnits
                            : (stockCases * packUnits).round();
                        final poGrossInclVat = item.suggestedPoGrossInclVatEgp > 0
                            ? item.suggestedPoGrossInclVatEgp
                            : item.suggestedPoValueEgp * 1.14;

                        return DataRow(
                          cells: [
                            DataCell(
                              InkWell(
                                borderRadius: BorderRadius.circular(8.0),
                                onTap: () => _openProductIdCard(
                                  itemCode: item.itemCode,
                                  barcode: item.barcode,
                                  skuName: item.skuName,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              item.skuName,
                                              style: const TextStyle(fontWeight: FontWeight.w800),
                                            ),
                                          ),
                                          const SizedBox(width: 4.0),
                                          Icon(
                                            Icons.badge_outlined,
                                            size: 15.0,
                                            color: colorScheme.primary,
                                          ),
                                        ],
                                      ),
                                      Text(
                                        'كود: ${item.itemCode.isNotEmpty ? item.itemCode : "-"} • باركود: ${item.barcode.isNotEmpty ? item.barcode : "-"} • شد $packUnits',
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10.5,
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item.brand} • ${item.governorate}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  if (item.officialCartonExclVatEgp > 0)
                                    Text(
                                      'كرتونة الكارتة: ${CurrencyFormatter.formatEGP(item.officialCartonExclVatEgp)}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: colorScheme.onSurfaceVariant,
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
                                    '${CurrencyFormatter.formatNumber(item.sellInCases.round())} كرتونة (${CurrencyFormatter.formatNumber(sellInUnits)} ق)',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    'صافي: ${CurrencyFormatter.formatCompactEGP(item.sellInValueEgp)}',
                                    style: TextStyle(
                                      fontSize: 11.0,
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w700,
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
                                    '${CurrencyFormatter.formatNumber(item.sellOutEstCases.round())} كرتونة (${CurrencyFormatter.formatNumber(sellOutUnits)} ق)',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    'POS: ${CurrencyFormatter.formatCompactEGP(item.sellOutValueEgp)}${item.retailerMarginPct != 0 ? " (هامش ${item.retailerMarginPct.toStringAsFixed(0)}%)" : ""}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Colors.teal.shade700,
                                      fontWeight: FontWeight.w700,
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
                                    '${CurrencyFormatter.formatNumber(stockCases.round())} كرتونة (${CurrencyFormatter.formatNumber(stockUnits)} ق)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  Text(
                                    CurrencyFormatter.formatEGP(stockVal),
                                    style: TextStyle(
                                      fontSize: 11.0,
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DataCell(
                              Text(
                                '${item.daysOfInventory.toStringAsFixed(1)} يوم',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: isUrgent
                                      ? Colors.red.shade700
                                      : isOverstock
                                          ? Colors.orange.shade800
                                          : Colors.teal.shade700,
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                  vertical: 4.0,
                                ),
                                decoration: BoxDecoration(
                                  color: isUrgent
                                      ? colorScheme.errorContainer
                                      : isOverstock
                                          ? Colors.orange.shade100
                                          : Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                child: Text(
                                  item.stockStatusAr,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: isUrgent
                                        ? colorScheme.onErrorContainer
                                        : isOverstock
                                            ? Colors.orange.shade900
                                            : Colors.teal.shade900,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              item.suggestedPoCases > 0
                                  ? Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${item.suggestedPoCases} كرتونة (${CurrencyFormatter.formatCompactEGP(item.suggestedPoValueEgp)})',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: Colors.deepOrange.shade800,
                                            fontSize: 12.0,
                                          ),
                                        ),
                                        Text(
                                          'شامل 14%: ${CurrencyFormatter.formatCompactEGP(poGrossInclVat)}',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.teal.shade800,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      'لا يحتاج توريد حالياً',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 14.0),

                  // Bottom Pagination Bar (25 items per page with Next / Previous Arrows)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'عرض ${totalSkuCount == 0 ? 0 : startIdx + 1} - $endIdx من إجمالي $totalSkuCount صنف (25 صنف بالصفحة)',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        // Previous Page Button
                        OutlinedButton.icon(
                          icon: const Icon(Icons.arrow_forward_rounded, size: 18.0),
                          label: const Text('السابق'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                          ),
                          onPressed: clampedCurrentPage > 0
                              ? () => setState(() => _skuCurrentPage = clampedCurrentPage - 1)
                              : null,
                        ),
                        const SizedBox(width: 10.0),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: Text(
                            'صفحة ${totalSkuPages == 0 ? 0 : clampedCurrentPage + 1} من ${totalSkuPages == 0 ? 1 : totalSkuPages}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10.0),
                        // Next Page Button
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.arrow_back_rounded, size: 18.0),
                          label: const Text('التالي'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                          ),
                          onPressed: clampedCurrentPage < totalSkuPages - 1
                              ? () => setState(() => _skuCurrentPage = clampedCurrentPage + 1)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 3: UPLOADED SELL-IN EXCEL SHEETS ARCHIVE (CUMULATIVE UPLOAD / REPLACE / DELETE)
  // ===========================================================================
  Widget _buildUploadedSellInSheetsTab(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Cumulative Upload Banner & Controls
        Container(
          padding: const EdgeInsets.all(18.0),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10.0),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Icon(
                      Icons.cloud_upload_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 24.0,
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إدارة شيتات الإكسيل المرفوعة للـ Sell-In (الرفع التراكمي شهر بشهر)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          'يمكنك رفع شيت كل شهر بشكل مستقل (يناير، ثم فبراير، ثم مارس... أو شيت مجمع لشهرين معاً في حالة التأخير) وسيقوم النظام بدمج الشهور تراكمياً دون مسح الشهور السابقة. كما يمكنك تعديل (استبدال) أو حذف أي شيت مرفوع في أي وقت.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),
              Wrap(
                spacing: 12.0,
                runSpacing: 10.0,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 10.0,
                    runSpacing: 8.0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 200.0,
                        child: DropdownButtonFormField<String>(
                          value: _archiveUploadChain,
                          decoration: InputDecoration(
                            labelText: 'Target Chain',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 10.0,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'fathalla',
                              child: Text('Fathalla Market'),
                            ),
                            DropdownMenuItem(
                              value: 'gomla',
                              child: Text('Gomla Market'),
                            ),
                            DropdownMenuItem(
                              value: 'beet-elgomla',
                              child: Text('Beet El Gomla'),
                            ),
                            DropdownMenuItem(
                              value: 'chain-1080314',
                              child: Text('El Wakala'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _archiveUploadChain = v);
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        width: 155.0,
                        child: DropdownButtonFormField<int>(
                          value: _archiveUploadYear,
                          decoration: InputDecoration(
                            labelText: 'Year (Optional)',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 10.0,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 0,
                              child: Text('Auto from Sheet'),
                            ),
                            DropdownMenuItem(value: 2026, child: Text('2026')),
                            DropdownMenuItem(value: 2025, child: Text('2025')),
                            DropdownMenuItem(value: 2024, child: Text('2024')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _archiveUploadYear = v);
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        width: 175.0,
                        child: DropdownButtonFormField<int>(
                          value: _archiveUploadMonth,
                          decoration: InputDecoration(
                            labelText: 'Month (Optional)',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 10.0,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 0,
                              child: Text('Auto from Sheet'),
                            ),
                            DropdownMenuItem(value: 1, child: Text('January (01)')),
                            DropdownMenuItem(value: 2, child: Text('February (02)')),
                            DropdownMenuItem(value: 3, child: Text('March (03)')),
                            DropdownMenuItem(value: 4, child: Text('April (04)')),
                            DropdownMenuItem(value: 5, child: Text('May (05)')),
                            DropdownMenuItem(value: 6, child: Text('June (06)')),
                            DropdownMenuItem(value: 7, child: Text('July (07)')),
                            DropdownMenuItem(value: 8, child: Text('August (08)')),
                            DropdownMenuItem(value: 9, child: Text('September (09)')),
                            DropdownMenuItem(value: 10, child: Text('October (10)')),
                            DropdownMenuItem(value: 11, child: Text('November (11)')),
                            DropdownMenuItem(value: 12, child: Text('December (12)')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _archiveUploadMonth = v);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 10.0,
                    runSpacing: 8.0,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44.0),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20.0,
                            vertical: 10.0,
                          ),
                        ),
                        onPressed: _isUploading
                            ? null
                            : () => _pickAndUploadSellInFile(
                                  forceChain: _archiveUploadChain,
                                  forceYear: _archiveUploadYear > 0
                                      ? _archiveUploadYear
                                      : null,
                                  forceMonth: _archiveUploadMonth > 0
                                      ? _archiveUploadMonth
                                      : null,
                                ),
                        icon: _isUploading && _replacingFileId == null
                            ? const SizedBox(
                                width: 18.0,
                                height: 18.0,
                                child: CircularProgressIndicator(strokeWidth: 2.0),
                              )
                            : const Icon(Icons.upload_file_rounded, size: 20.0),
                        label: const Text('Upload Sell In'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44.0),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 10.0,
                          ),
                        ),
                        onPressed: _isLoadingArchive ? null : _loadSellInArchive,
                        icon: const Icon(Icons.refresh_rounded, size: 18.0),
                        label: const Text('تحديث القائمة'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // 2. Uploaded Sell-In Sheets Table
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: _isLoadingArchive
              ? const Padding(
                  padding: EdgeInsets.all(48.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _archivedSellInFiles.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder_off_outlined,
                              size: 48.0,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12.0),
                            Text(
                              'لا توجد شيتات إكسيل مرفوعة في أرشيف الـ Sell-In حالياً.',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6.0),
                            Text(
                              'اضغط على زر "Upload Sell In" لرفع شيت الشهر الأول وبدء البناء التراكمي.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : TableScrollContainer(
                      controller: _archiveSheetsScrollController,
                      showSwipeHint: true,
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          colorScheme.surfaceContainerHigh.withOpacity(0.5),
                        ),
                        columns: const [
                          DataColumn(label: Text('اسم شيت الإكسيل (Excel File)')),
                          DataColumn(label: Text('السلسلة (Chain)')),
                          DataColumn(label: Text('الشهور المغطاة (Period)')),
                          DataColumn(label: Text('عدد الحركات'), numeric: true),
                          DataColumn(
                            label: Text('إجمالي الكراتين (Cases)'),
                            numeric: true,
                          ),
                          DataColumn(
                            label: Text('صافي التوريد (Net Sell-In EGP)'),
                            numeric: true,
                          ),
                          DataColumn(label: Text('الوزن (Tons)'), numeric: true),
                          DataColumn(label: Text('تاريخ الرفع')),
                          DataColumn(
                            label: Text('إجراءات التحكم (تعديل / تحميل / حذف)'),
                          ),
                        ],
                        rows: _archivedSellInFiles.map((file) {
                          final isDeleting = _deletingFileId == file.id;
                          final isReplacing = _replacingFileId == file.id;
                          final periodText = file.targetMonth.isNotEmpty &&
                                  file.targetMonth != 'auto'
                              ? '${file.targetMonth} / ${file.targetYear}'
                              : 'سنة ${file.targetYear}';

                          return DataRow(
                            cells: [
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.description_rounded,
                                      color: Colors.green.shade700,
                                      size: 20.0,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          file.fileName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          _formatFileSize(file.fileSizeBytes),
                                          style: TextStyle(
                                            fontSize: 11.0,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0,
                                    vertical: 3.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        colorScheme.primaryContainer.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(999.0),
                                  ),
                                  child: Text(
                                    file.retailChain.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11.0,
                                      fontWeight: FontWeight.w800,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  periodText,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              DataCell(
                                Text(
                                  CurrencyFormatter.formatNumber(file.rowsIngested),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              DataCell(
                                Text(
                                  CurrencyFormatter.formatNumber(
                                    file.totalCases > 0
                                        ? file.totalCases.round()
                                        : file.rowsIngested,
                                  ),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              DataCell(
                                Text(
                                  CurrencyFormatter.formatEGP(file.totalRevenue),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${file.totalWeightTons.toStringAsFixed(1)} طن',
                                ),
                              ),
                              DataCell(
                                Text(
                                  file.uploadedAt.length >= 16
                                      ? file.uploadedAt
                                          .substring(0, 16)
                                          .replaceAll('T', ' ')
                                      : file.uploadedAt,
                                  style: TextStyle(
                                    fontSize: 12.0,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 1. Replace / Edit Sheet Button
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10.0,
                                          vertical: 6.0,
                                        ),
                                      ),
                                      onPressed: (isDeleting || isReplacing || _isUploading)
                                          ? null
                                          : () => _pickAndUploadSellInFile(
                                                replaceArchiveId: file.id,
                                                forceChain: file.retailChain,
                                              ),
                                      icon: isReplacing
                                          ? const SizedBox(
                                              width: 14.0,
                                              height: 14.0,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.0,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.edit_document,
                                              size: 16.0,
                                            ),
                                      label: const Text('تعديل / استبدال'),
                                    ),
                                    const SizedBox(width: 6.0),
                                    // 2. Download Original Excel Sheet Button
                                    IconButton.outlined(
                                      tooltip: 'تحميل ملف الإكسيل الأصلي',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _handleDownloadSellInSheet(file),
                                      icon: const Icon(
                                        Icons.download_rounded,
                                        size: 18.0,
                                      ),
                                    ),
                                    const SizedBox(width: 6.0),
                                    // 3. Delete Sheet Button
                                    FilledButton.tonalIcon(
                                      style: FilledButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor:
                                            colorScheme.errorContainer.withOpacity(0.8),
                                        foregroundColor: colorScheme.onErrorContainer,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10.0,
                                          vertical: 6.0,
                                        ),
                                      ),
                                      onPressed: (isDeleting || isReplacing)
                                          ? null
                                          : () => _confirmAndDeleteSellInSheet(file),
                                      icon: isDeleting
                                          ? const SizedBox(
                                              width: 14.0,
                                              height: 14.0,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.0,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 16.0,
                                            ),
                                      label: const Text('حذف (Delete)'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildFourCardResponsiveLayout(
    double maxWidth,
    Widget card1,
    Widget card2,
    Widget card3,
    Widget card4,
  ) {
    if (maxWidth >= 960) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: card1),
          const SizedBox(width: 12.0),
          Expanded(child: card2),
          const SizedBox(width: 12.0),
          Expanded(child: card3),
          const SizedBox(width: 12.0),
          Expanded(child: card4),
        ],
      );
    } else if (maxWidth >= 580) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: card1),
              const SizedBox(width: 12.0),
              Expanded(child: card2),
            ],
          ),
          const SizedBox(height: 12.0),
          Row(
            children: [
              Expanded(child: card3),
              const SizedBox(width: 12.0),
              Expanded(child: card4),
            ],
          ),
        ],
      );
    } else {
      return Column(
        children: [
          card1,
          const SizedBox(height: 12.0),
          card2,
          const SizedBox(height: 12.0),
          card3,
          const SizedBox(height: 12.0),
          card4,
        ],
      );
    }
  }

  Widget _buildSummaryCard(
    BuildContext context, {
    required String titleAr,
    required String titleEn,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Icon(icon, color: color, size: 20.0),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titleAr,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1.0),
                    Text(
                      titleEn,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12.0),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6.0),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

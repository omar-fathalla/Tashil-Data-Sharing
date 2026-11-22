import 'package:tashil_web/core/widgets/m3_search_field.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../../../core/widgets/m3_table_surface.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:tashil_web/core/utils/sheet_name_utils.dart';
import 'package:tashil_web/core/widgets/m3_states.dart';
import 'package:flutter/material.dart';
import '../../../data_ingestion/presentation/widgets/upload_checks.dart';
import '../../../data_ingestion/presentation/widgets/sell_in_upload_target.dart';
import 'package:flutter/services.dart';
import 'package:tashil_web/core/theme/m3_text_variants.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/utils/export_columns.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/data/cache_store.dart';
import '../../../../core/data/result.dart';
import '../../data/target_repository.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/backend_http.dart';
import '../../domain/archive_delete_copy.dart';
import '../../../../core/testing/test_semantics.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/bidi_text.dart';
import '../../../../core/utils/app_date_format.dart';
import '../../../../core/utils/shared_display_prefix.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/archive_actions_group.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_responsive_tab_bar.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../../cpfr_replenishment/domain/cpfr_models.dart';
import '../../../product_master/presentation/screens/product_master_screen.dart';
import '../widgets/sell_in_price_waterfall_card.dart';
import '../widgets/target_management_panel.dart';
import '../widgets/sell_table_shared.dart';
import '../utils/monthly_status_text.dart';
import '../../data/sell_in_explorer_repository.dart';
import '../../../../core/data/data_refresh_mixin.dart';
import '../../../../core/data/available_years.dart';
import '../../../customer_registry/presentation/pending_customers_screen.dart';

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

class _SellInExplorerScreenState extends State<SellInExplorerScreen> with DataRefreshMixin<SellInExplorerScreen> {
  @override
  void onBackendDataChanged() {
    _loadAllData();
  }

  int _activeTab = 0; // 0: Sell-In Explorer, 1: Remaining Stock & Reports, 2: Sell-In Targets, 3: Uploaded Sell-In Sheets Archive
  String _selectedChain = 'all';
  int _selectedYear = AvailableYears.current.defaultYear; // latest year with data
  bool _yearTouched = false;
  int _selectedMonth = 0; // 0 = All Months
  /// Client-side display page size for the Sell-In records table.
  static const int _recordsPageSize = 20;
  /// API batch size when hydrating the full filtered set for client paging.
  static const int _fetchPageSize = 250;
  int _recordsPageIndex = 0;
  List<SellInRecordItem> _records = const []; // full filtered set (client-paged)

  Map<String, String> get _locationDisplay {
    final names = <String>{
      ..._records.map((r) => r.governorate),
      ...?_stockDashboard?.inventoryAndPoItems.map((i) => i.governorate),
    }..removeWhere((n) => n.trim().isEmpty);
    return displayNamesWithoutSharedPrefix(names);
  }

  String _displayLocation(String raw) => _locationDisplay[raw] ?? raw;

  String _searchQuery = '';
  bool _isLoading = true;
  String? _loadError;
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
  String _skuMarginFilter = 'all';
  int _skuSortColumnIndex = 4; // Default to Remaining Stock (Index 4) or DOS (Index 5)
  bool _skuSortAscending = true;
  final int _skuPageSize = 25; // 25 items per page as requested
  int _skuCurrentPage = 0;
  late final TextEditingController _skuSearchController;

  // Tab 3: Uploaded Sell-In Excel Sheets Archive State
  bool _isLoadingArchive = false;
  List<ArchivedExcelFileModel> _archivedSellInFiles = const [];
  /// The last list load failed (after transient retries): show an error with
  /// retry, never a misleading "no files" empty state.
  bool _archiveLoadFailed = false;
  // TOP RULE: no default chain. '' until the user picks one from the tenant chains list.
  String _archiveUploadChain = '';
  List<RetailChainModel> _chains = const [];
  int _archiveUploadYear = 0; // 0 = Auto-detect from sheet
  int _archiveUploadMonth = 0; // 0 = Auto-detect from sheet
  String? _deletingFileId;
  String? _replacingFileId;

  late String _lastTenantId;
  late SellInExplorerRepository _repo;

  late final ScrollController _monthlyLedgerScrollController;
  late final ScrollController _skuStockScrollController;
  late final ScrollController _archiveSheetsScrollController;

  @override
  void initState() {
    super.initState();
    _skuSearchController = TextEditingController();
    _monthlyLedgerScrollController = ScrollController();
    _skuStockScrollController = ScrollController();
    _archiveSheetsScrollController = ScrollController();
    _repo = widget.repository ?? SellInExplorerRepository(widget.apiClient);
    _lastTenantId = widget.apiClient.tenantId;
    _loadAllData();
    _loadChains();
    AvailableYears.load(widget.apiClient).then((o) {
      if (!mounted) return;
      if (!_yearTouched && _selectedYear != 0 && o.defaultYear != _selectedYear) {
        setState(() => _selectedYear = o.defaultYear);
        _loadSellInRecords();
        _loadStockReconciliationReport();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _skuSearchController.dispose();
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
      _selectedYear = AvailableYears.current.defaultYear;
      _yearTouched = false;
      _selectedMonth = 0;
      _searchQuery = '';
      _recordsPageIndex = 0;
      _loadAllData();
    }
  }

  Future<void> _loadAllData({bool forceRefresh = false}) async {
    await Future.wait([
      _loadSellInRecords(),
      _loadStockReconciliationReport(),
      _loadSellInArchive(forceRefresh: forceRefresh),
    ]);
  }

  SellInExplorerQuery _sellInQuery({int limit = _fetchPageSize, int offset = 0}) =>
      SellInExplorerQuery(
        chain: _selectedChain == 'all' ? null : _selectedChain,
        year: _selectedYear > 0 ? _selectedYear : null,
        month: _selectedMonth > 0 ? _selectedMonth : null,
        query: _searchQuery,
        limit: limit,
        offset: offset,
      );

  int _sellInGeneration = 0; // bumps on every filter reset to drop stale appends

  void _resetRecordsPage() {
    _recordsPageIndex = 0;
  }

  /// Hydrates the full filtered Sell-In set for client-side paging.
  /// KPI totals come from the API response (full filtered set), not the page.
  Future<void> _loadSellInRecords() async {
    final gen = ++_sellInGeneration;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _resetRecordsPage();
      });
    }
    final loaded = await _repo.load(_sellInQuery());
    if (gen != _sellInGeneration) return;
    if (loaded case Failure(:final error)) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = error.toString();
        });
        M3Feedback.showError(context, 'تعذّر تحميل بيانات Sell-In. حاول مرة أخرى.');
      }
      return;
    }
    final first = loaded.valueOrNull!;
    final all = <SellInRecordItem>[...first.records];
    var offset = all.length;
    // Pull remaining pages (display-only; no backend changes) up to totalCount.
    while (offset < first.totalCount && gen == _sellInGeneration) {
      final next = await _repo.load(_sellInQuery(offset: offset));
      if (gen != _sellInGeneration) return;
      final batch = next.valueOrNull;
      if (batch == null || batch.records.isEmpty) break;
      all.addAll(batch.records);
      offset = all.length;
      if (batch.records.length < _fetchPageSize) break;
    }
    if (!mounted || gen != _sellInGeneration) return;
    setState(() {
      _data = first;
      _records = all;
      _isLoading = false;
      _loadError = null;
      _resetRecordsPage();
    });
  }

  /// Rows for exports/print: full filtered set already held for client paging.
  Future<List<SellInRecordItem>> _exportRecords() async {
    if (_records.length >= _data.totalCount && _records.isNotEmpty) {
      return _records;
    }
    final loaded = await _repo.load(_sellInQuery(limit: math.max(_data.totalCount, _fetchPageSize)));
    return loaded.valueOrNull?.records ?? _records;
  }

  int _stockReportGeneration = 0; // drops responses for an older chain/year/status

  Future<void> _loadStockReconciliationReport() async {
    final gen = ++_stockReportGeneration;
    if (mounted) setState(() => _isLoadingStockReport = true);
    try {
      final res = await widget.apiClient.fetchCPFRDashboard(
        chain: _selectedChain,
        year: _selectedYear > 0 ? _selectedYear : null,
        stockStatus: _stockStatusFilter,
      );
      if (gen != _stockReportGeneration) return;
      if (mounted) {
        setState(() {
          _stockDashboard = res;
          _isLoadingStockReport = false;
        });
      }
    } catch (_) {
      if (mounted && gen == _stockReportGeneration) {
        setState(() => _isLoadingStockReport = false);
      }
    }
  }

  Future<void> _loadSellInArchive({bool forceRefresh = false}) async {
    if (forceRefresh) {
      _repo.invalidateAll();
    }
    if (mounted) setState(() => _isLoadingArchive = true);
    try {
      final res = await widget.apiClient.getUploadedFilesArchive(
        fileType: 'sell_in',
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        setState(() {
          _archivedSellInFiles = res.files;
          _archiveLoadFailed = false;
          _isLoadingArchive = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _archiveLoadFailed = true;
          _isLoadingArchive = false;
        });
      }
    }
  }

  Future<void> _handleDownloadSellInSheet(ArchivedExcelFileModel file) async {
    try {
      await widget.apiClient.downloadArchivedFile(file);
      if (!mounted) return;
      M3Feedback.showSuccess(
        context,
        'جارٍ تنزيل ${file.fileName}',
      );
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'تعذّر تنزيل الملف.');
    }
  }

  static String _formatFileSize(int bytes) {
    if (bytes <= 0) return 'ملف Excel';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024.0;
    if (kb < 1024.0) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    return '${mb.toStringAsFixed(2)} MB';
  }

  Future<void> _loadChains() async {
    try {
      // Filters also list chains referenced by Sell-In data but not registered yet (e.g. زهران);
      // upload targets keep registered chains only (chainOptions).
      final chains = await widget.apiClient.getRetailChainsWithReferenced();
      if (!mounted) return;
      setState(() => _chains = chains);
    } catch (_) {
      // The dropdowns stay empty and the upload asks again; nothing defaults to a chain.
    }
  }

  /// Uploads one Sell-In file. TOP RULE: the chain is always explicit. [forceChain] comes from a
  /// control the user set (archive form, or the archived file being replaced); otherwise a dialog
  /// asks for it. The screen filters never set the period: year/month are sent only when chosen.
  Future<void> _pickAndUploadSellInFile({
    String? replaceArchiveId,
    String? forceChain,
    int? forceYear,
    int? forceMonth,
  }) async {
    var targetChain = forceChain;
    var targetYear = forceYear;
    var targetMonth = forceMonth;
    if (!isExplicitChain(targetChain)) {
      if (_chains.isEmpty) await _loadChains();
      if (!mounted) return;
      final target = await askSellInUploadTarget(
        context,
        chains: _chains,
        initialChain: _selectedChain,
      );
      if (target == null || !mounted) return;
      targetChain = target.chain;
      targetYear = target.year;
      targetMonth = target.month;
    }
    final picked = await WebFileHelper.pickFile(accept: '.xlsx,.xls,.csv');
    if (picked == null || picked.bytes.isEmpty) return;

    setState(() {
      _isUploading = true;
      if (replaceArchiveId != null) {
        _replacingFileId = replaceArchiveId;
      }
    });
    try {
      final chain = targetChain!;
      if (!mounted) return;
      final res = await runUploadWithQuestions(context, (replaceConfirmed, periodChoice) => widget.apiClient.uploadSellInFile(
            filename: picked.name,
            fileBytes: picked.bytes,
            chain: chain,
            replaceArchiveId: replaceArchiveId,
            year: targetYear,
            month: targetMonth,
            replaceConfirmed: replaceConfirmed,
            periodChoice: periodChoice,
          ).timeout(sellInUploadTimeout));
      if (!mounted) return;
      if (res == null) {
        M3Feedback.showInfo(context, 'اتلغى الرفع ومفيش حاجة اتحفظت');
        return;
      }
      _repo.invalidateAll();
      _repo.cache.invalidatePrefix(CacheStore.prefix(widget.apiClient.tenantId, TargetRepository.feature));
      unawaited(AvailableYears.load(widget.apiClient, force: true));
      if (res.quarantinedCustomers.isNotEmpty) {
        // Saved, with some customer rows held out of totals: an M3 dialog, never "rejected".
        await showQuarantineSavedDialog(
          context,
          fileName: picked.name,
          validRows: res.validRows,
          validValue: res.totalRevenue,
          customers: res.quarantinedCustomers,
          onOpenPending: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => PendingCustomersScreen(apiClient: widget.apiClient),
          )),
        );
        if (!mounted) return;
        if (res.unknownBarcodes.isNotEmpty) {
          M3Feedback.showWarning(context, uploadWarningsSummary(IngestionWarningsView(0, res.unknownBarcodes.length)));
        }
      } else {
        final notes = uploadWarningsSummary(IngestionWarningsView(0, res.unknownBarcodes.length));
        if (notes.isNotEmpty) M3Feedback.showWarning(context, notes);
        final actionLabel = replaceArchiveId != null
            ? 'تم استبدال الملف.'
            : 'تم رفع الملف وإضافته للبيانات.';
        M3Feedback.showSuccess(
          context,
          '$actionLabel (${picked.name}): ${res.validRows} صف • ${CurrencyFormatter.formatCompactEGP(res.totalRevenue)}',
        );
      }
      await _loadAllData(forceRefresh: true);
    } catch (e) {
      // Stop the spinner first, then show the server's Arabic reason (or the wait-timeout) in a dialog.
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _replacingFileId = null;
      });
      // Wait-timeout is not a rejection: refresh the files list in case the job already finished.
      if (isUploadWaitTimeout(e)) {
        try {
          await _loadAllData(forceRefresh: true);
        } catch (_) {}
        if (!mounted) return;
      }
      await showUploadFailureDialog(context, picked.name, e);
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
          shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusLg),
          title: Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: cs.error, size: 24.0),
              const SizedBox(width: 10.0),
              const Expanded(
                child: Text(
                  'حذف الملف؟',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rtlEnd('سيتم حذف هذا الملف وبياناته من ${ltrIsolate('Sell-In')}.')),
              const SizedBox(height: 12.0),
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.35),
                  borderRadius: M3Shape.radiusMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'السلسلة ${file.retailChain.toUpperCase()} • الصفوف ${file.rowsIngested} • صافي Sell-In ${CurrencyFormatter.formatCompactEGP(file.totalRevenue)}',
                      style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(fontSize: M3FontSize.bodySmall)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10.0),
              Text(
                sellInDeleteConsequenceText(
                  coversAllMonths: archiveFileCoversAllMonths(
                    file.targetMonth,
                    isLastFile: _archivedSellInFiles.length <= 1,
                  ),
                ),
                style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(fontSize: M3FontSize.bodySmall, color: cs.onSurfaceVariant)),
              ),
            ],
          ),
          actions: [
            TestSemantics.button(
              identifier: TestIds.deleteCancel,
              label: 'إلغاء الحذف',
              onPressed: () => Navigator.of(ctx).pop(false),
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء'),
              ),
            ),
            TestSemantics.button(
              identifier: TestIds.deleteConfirm,
              label: 'تأكيد الحذف',
              onPressed: () => Navigator.of(ctx).pop(true),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                icon: const Icon(Icons.delete_outline_rounded, size: 18.0),
                label: const Text('حذف'),
              ),
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
        fileName: file.fileName,
        isSellIn: true,
      );
      if (!mounted) return;
      M3Feedback.showSuccess(
        context,
        'تم حذف ${file.fileName}',
      );
      _repo.invalidateAll();
      _repo.cache.invalidatePrefix(CacheStore.prefix(widget.apiClient.tenantId, TargetRepository.feature));
      BackendHttp.cache.invalidateAll();
      await _loadAllData(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      final msg = e is ArchiveDeleteException
          ? e.message
          : 'تعذّر حذف الملف.';
      M3Feedback.showError(context, msg);
      await _loadAllData(forceRefresh: true);
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
          'الصنف غير موجود في قائمة الأصناف.',
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
          _loadAllData(forceRefresh: true);
        },
      );
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'تعذّر فتح بيانات الصنف.');
    }
  }

  Future<void> _handleExportExcel() async {
    if (widget.apiClient.currentUser?.canExportFinancials == false) {
      M3Feedback.showError(
        context,
        'ليس لديك صلاحية تصدير التقارير.',
      );
      return;
    }
    final records = await _exportRecords();
    if (!mounted) return;
    const headers = ExportColumns.sellInRecords;
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
      'تم تصدير ${records.length} صف (CSV).',
    );
  }

  Future<void> _handleExportPdf() async {
    if (widget.apiClient.currentUser?.canExportFinancials == false) {
      M3Feedback.showError(
        context,
        'ليس لديك صلاحية تصدير التقارير.',
      );
      return;
    }
    final records = await _exportRecords();
    if (!mounted) return;
    final headers = [
      'الفترة',
      'السلسلة',
      'الكود / الباركود',
      'اسم الصنف',
      'وحدات/كرتونة',
      'الكراتين (الوحدات)',
      'صافي Sell-In (ج.م)',
      'شامل الضريبة (ج.م)',
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
      title: 'تقرير Sell-In',
      headers: headers,
      rows: rows,
      metadata: {
        'صافي Sell-In (بدون الضريبة)': CurrencyFormatter.formatEGP(_data.totalValueEgp),
        'Sell-In شامل الضريبة': CurrencyFormatter.formatEGP(_data.totalGrossInclVatEgp),
        'الكراتين والوحدات': '${CurrencyFormatter.formatNumber(_data.totalCases.round())} كرتونة (${CurrencyFormatter.formatNumber(_data.totalUnitsPieces)} وحدة)',
        'متوسط الخصم عن قائمة الأسعار': _data.totalOfficialListExclVatEgp > 0 ? '${_data.effectiveDiscountPct.toStringAsFixed(1)}%' : '—',
      },
    );
    final filename =
        'tashil_sellin_report_${DateTime.now().millisecondsSinceEpoch}.html';
    ExcelExportService.downloadHtml(filename, htmlData);
    M3Feedback.showSuccess(
      context,
      'التقرير جاهز للطباعة (${records.length} صف).',
    );
  }

  void _handleExportStockBalanceExcel() {
    final d = _stockDashboard;
    if (d == null) return;
    const headers = ExportColumns.sellInReconciliation;
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
      'تم تصدير تقرير المخزون.',
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
            '${CurrencyFormatter.formatEGP(m.sellInValueEgp)} (${m.sellInCases.round()} كرتونة)',
            '${CurrencyFormatter.formatEGP(m.sellOutValueEgp)} (${m.sellOutEstCases.round()} كرتونة)',
            CurrencyFormatter.formatEGP(m.monthlyNetValueEgp),
            '${CurrencyFormatter.formatEGP(m.closingStockValueEgp)} (${m.closingStockCases.round()} كرتونة)',
            '${m.sellThroughRatePct.toStringAsFixed(1)}%',
            m.stockHealthLabelAr,
          ],
        )
        .toList();
    final htmlData = ExcelExportService.generatePrintableReport(
      title: 'تقرير المخزون الشهري (Sell-In مقابل Sell-Out)',
      headers: headers,
      rows: rows,
      metadata: {
        'Sell-In منذ بداية العام':
            CurrencyFormatter.formatEGP(d.ytd2026SellInEgp),
        'المخزون المتبقي':
            '${CurrencyFormatter.formatEGP(d.totalEstimatedStockEgp)} (${CurrencyFormatter.formatNumber(d.totalEstimatedStockCases.round())} كرتونة)',
        'أوامر الشراء المقترحة':
            '${CurrencyFormatter.formatEGP(d.totalSuggestedPoEgp)} (${d.totalSuggestedPoCases} كرتونة)',
      },
    );
    final filename =
        'tashil_remaining_stock_report_${DateTime.now().millisecondsSinceEpoch}.html';
    ExcelExportService.downloadHtml(filename, htmlData);
    M3Feedback.showSuccess(
      context,
      'التقرير جاهز للطباعة.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 600.0;

    return M3ToolbarButtonTheme(
      child: SingleChildScrollView(
      padding: isCompact ? M3Spacing.pSm : M3Spacing.pMd,
      child: M3ContentBoundary(
        maxWidth: double.infinity,
        alignment: AlignmentDirectional.topStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const M3PageHeader(
              titleEn: 'Sell-In',
              subtitleAr:
                  'التوريد للسلاسل والمخزون المتبقي والمستهدفات',
            ),

            M3Spacing.gapSM,

            // Top Tab Switcher: 100% Responsive Full-Width MD3 Large Tab Bar (4 Symmetrical Tabs)
            M3ResponsiveTabBar<int>(
              textDirection: TextDirection.ltr,
              selectedValue: _activeTab,
              items: [
                const M3ResponsiveTabItem<int>(
                  value: 0,
                  icon: Icons.local_shipping_rounded,
                  selectedIcon: Icons.local_shipping_rounded,
                  label: 'بيانات التوريد',
                ),
                const M3ResponsiveTabItem<int>(
                  value: 1,
                  icon: Icons.warehouse_rounded,
                  selectedIcon: Icons.warehouse_rounded,
                  label: 'المخزون وإعادة الطلب',
                ),
                const M3ResponsiveTabItem<int>(
                  value: 2,
                  icon: Icons.track_changes_rounded,
                  selectedIcon: Icons.track_changes_rounded,
                  label: 'المستهدفات',
                ),
                M3ResponsiveTabItem<int>(
                  value: 3,
                  icon: Icons.folder_copy_rounded,
                  selectedIcon: Icons.folder_copy_rounded,
                  label: 'الملفات المرفوعة (${_archivedSellInFiles.length})',
                  semanticsIdentifier: TestIds.sellinUploadedFiles,
                ),
              ],
              onChanged: (next) {
                setState(() => _activeTab = next);
                if (next == 1) {
                  _loadStockReconciliationReport();
                } else if (next == 3) {
                  _loadSellInArchive(forceRefresh: true);
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
            else if (!_isLoading && _loadError != null && _records.isEmpty)
              M3ErrorState(
                key: const ValueKey('sell_in_error_state'),
                title: 'تعذّر تحميل بيانات Sell-In',
                message: _loadError,
                retryLabel: 'إعادة المحاولة',
                onRetry: _loadSellInRecords,
              )
            else
              _buildSellInExplorerTab(context, theme, colorScheme),
          ],
        ),
      ),
      ),
    );
  }


  // Sell-In records table: all 12 columns fit the viewport (no horizontal
  // scroll / no يمين·شمال). Client-side pagination shows 20 rows per page.
  static const double _sellInHeaderHeight = 56.0;
  static const double _sellInRowMinHeight = 64.0;
  // Flex weights (RTL visual order): item, period, chain/branch, cases/units,
  // net, gross, carton price, expected, brand/category, rep, weight, file.
  static const List<double> _sellInColFlex = [
    2.4, 0.75, 1.15, 1.05, 1.0, 1.0, 1.15, 1.2, 1.25, 0.95, 0.55, 0.5,
  ];
  List<double> _sellInWidths = const [];

  void _layoutSellInColumns(double available) {
    final totalFlex = _sellInColFlex.fold<double>(0, (a, b) => a + b);
    final unit = available / totalFlex;
    _sellInWidths = [
      for (final f in _sellInColFlex) (f * unit).floorToDouble(),
    ];
    // Absorb rounding remainder into the item column so the row fills exactly.
    final used = _sellInWidths.fold<double>(0, (a, b) => a + b);
    if (_sellInWidths.isNotEmpty) {
      _sellInWidths[0] += (available - used);
    }
  }

  // Monthly / stock DataTables: cap each column's width so long compact
  // numbers wrap onto 2 lines (centred) instead of widening the table past
  // 1030dp; TableScrollContainer still stretches the table on wider screens.
  static const double _monthlyCellMaxWidth = 84.0;
  static const double _skuCellMaxWidth = 88.0;
  static const double _monthlyStatusMaxWidth = 112.0;

  // Long stock-table headers wrap onto 2 centred lines so the columns fit 1030dp.
  static Widget _wrapHeader(String text) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 56.0),
        child: Text(text, maxLines: 2, softWrap: true, textAlign: TextAlign.center),
      );

  Widget _mText(String text, {TextStyle? style, int maxLines = 2}) => Tooltip(
        message: text,
        child: Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: style,
        ),
      );

  DataCell _fitCell(double maxWidth, Widget child) => DataCell(
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DefaultTextStyle.merge(textAlign: TextAlign.center, child: child),
        ),
      );

  Widget _sellInCell(
    int i,
    Widget child, {
    AlignmentGeometry alignment = AlignmentDirectional.topCenter,
    EdgeInsetsGeometry? padding,
  }) =>
      SizedBox(
        width: _sellInWidths[i],
        child: Padding(
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 6.0, vertical: M3Spacing.xs),
          child: Align(alignment: alignment, child: child),
        ),
      );

  int get _recordsTotalPages {
    if (_records.isEmpty) return 1;
    return ((_records.length + _recordsPageSize - 1) / _recordsPageSize).ceil();
  }

  int get _recordsSafePage =>
      _recordsPageIndex.clamp(0, math.max(0, _recordsTotalPages - 1));

  List<SellInRecordItem> get _recordsPageSlice {
    if (_records.isEmpty) return const [];
    final start = _recordsSafePage * _recordsPageSize;
    final end = math.min(start + _recordsPageSize, _records.length);
    return _records.sublist(start, end);
  }

  /// Visible page numbers with ellipsis sentinels (-1) for long ranges.
  List<int> _pageWindow(int current, int total) {
    if (total <= 7) return [for (var i = 0; i < total; i++) i];
    final pages = <int>{0, total - 1, current};
    for (var i = current - 1; i <= current + 1; i++) {
      if (i > 0 && i < total - 1) pages.add(i);
    }
    final sorted = pages.toList()..sort();
    final out = <int>[];
    for (var i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i] - sorted[i - 1] > 1) out.add(-1);
      out.add(sorted[i]);
    }
    return out;
  }

  Widget _buildRecordsPaginationBar(ThemeData theme, ColorScheme colorScheme) {
    final totalCount = _records.length;
    final totalPages = _recordsTotalPages;
    final safePage = _recordsSafePage;
    final startIndex = totalCount == 0 ? 0 : safePage * _recordsPageSize + 1;
    final endIndex = totalCount == 0
        ? 0
        : math.min((safePage + 1) * _recordsPageSize, totalCount);
    final canPrev = safePage > 0;
    final canNext = safePage < totalPages - 1;

    Widget navBtn({
      required Key key,
      required IconData icon,
      required String tooltip,
      required bool enabled,
      required VoidCallback onPressed,
    }) {
      return SizedBox(
        width: 40.0,
        height: 40.0,
        child: IconButton(
          key: key,
          icon: Icon(icon, size: 20.0),
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          onPressed: enabled ? onPressed : null,
        ),
      );
    }

    return Container(
      key: const ValueKey('sellin_records_pagination'),
      height: 56.0,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              key: const ValueKey('sellin_records_page_label'),
              'عرض $startIndex–$endIndex من $totalCount · صفحة ${totalCount == 0 ? 0 : safePage + 1} من $totalPages',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          navBtn(
            key: const ValueKey('sellin_records_first_btn'),
            icon: AppIcons.firstPage,
            tooltip: 'الصفحة الأولى',
            enabled: canPrev,
            onPressed: () => setState(() => _recordsPageIndex = 0),
          ),
          navBtn(
            key: const ValueKey('sellin_records_prev_btn'),
            icon: AppIcons.chevronStart,
            tooltip: 'الصفحة السابقة',
            enabled: canPrev,
            onPressed: () => setState(() => _recordsPageIndex = safePage - 1),
          ),
          for (final p in _pageWindow(safePage, totalPages))
            if (p < 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: Text(
                  '…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: SizedBox(
                  width: 40.0,
                  height: 40.0,
                  child: Material(
                    color: p == safePage
                        ? colorScheme.secondaryContainer
                        : colorScheme.surface.withValues(alpha: 0),
                    shape: const CircleBorder(),
                    child: InkWell(
                      key: ValueKey('sellin_records_page_circle_$p'),
                      customBorder: const CircleBorder(),
                      onTap: p == safePage
                          ? null
                          : () => setState(() => _recordsPageIndex = p),
                      child: Center(
                        child: Text(
                          '${p + 1}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: p == safePage
                                ? colorScheme.onSecondaryContainer
                                : colorScheme.onSurfaceVariant,
                            fontWeight:
                                p == safePage ? FontWeight.w700 : FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          navBtn(
            key: const ValueKey('sellin_records_next_btn'),
            icon: AppIcons.chevronEnd,
            tooltip: 'الصفحة التالية',
            enabled: canNext,
            onPressed: () => setState(() => _recordsPageIndex = safePage + 1),
          ),
          navBtn(
            key: const ValueKey('sellin_records_last_btn'),
            icon: AppIcons.lastPage,
            tooltip: 'الصفحة الأخيرة',
            enabled: canNext,
            onPressed: () =>
                setState(() => _recordsPageIndex = totalPages - 1),
          ),
        ],
      ),
    );
  }

  /// Header + current page of rows + pagination footer. No horizontal scroll.
  Widget _buildVirtualSellInTable(BuildContext context, ColorScheme colorScheme) {
    final theme = Theme.of(context);
    final headers = <Widget>[
      Text('الصنف',
          key: const ValueKey('sellin_records_pinned_item'),
          style: theme.textTheme.labelMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant)),
      Text('الفترة',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant)),
      Text('السلسلة / الفرع',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant)),
      Text('كرتونة / وحدة',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant)),
      _twoLineHeader(context, 'صافي Sell-In', 'بدون الضريبة'),
      _twoLineHeader(context, 'الإجمالي', 'شامل الضريبة'),
      _twoLineHeader(context, 'سعر الكرتونة', 'الفعلي / القائمة'),
      Tooltip(
        message:
            'سعر القائمة × (1 − خصم الفاتورة) × (1 − الخصم الإضافي) بإعدادات سلسلة الصف\nالفرق = الفعلي − المتوقع',
        child: Text(
          'السعر المتوقع',
          key: const ValueKey('sellin_expected_carton_header'),
          maxLines: 2,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
      Text('العلامة التجارية / الفئة',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant)),
      Text('المندوب',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant)),
      Text('الوزن (طن)',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant)),
      Text('الملف',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant)),
    ];
    final pageRecords = _recordsPageSlice;
    final pageBase = _recordsSafePage * _recordsPageSize;

    return Column(
      key: const ValueKey('sellin_records_table'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: _sellInHeaderHeight,
          color: colorScheme.surfaceContainer,
          child: Row(
            children: [
              for (var i = 0; i < headers.length; i++)
                _sellInCell(
                  i,
                  headers[i],
                  alignment: i == 0
                      ? AlignmentDirectional.centerStart
                      : AlignmentDirectional.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6.0,
                    vertical: M3Spacing.xxs,
                  ),
                ),
            ],
          ),
        ),
        for (var i = 0; i < pageRecords.length; i++)
          _buildSellInRecordRow(
            context,
            colorScheme,
            pageRecords[i],
            absoluteIndex: pageBase + i,
          ),
        _buildRecordsPaginationBar(theme, colorScheme),
      ],
    );
  }

  Widget _buildSellInRecordRow(
    BuildContext context,
    ColorScheme colorScheme,
    SellInRecordItem record, {
    required int absoluteIndex,
  }) {
    final item = KeyedSubtree(
      key: ValueKey('sellin_record_item_$absoluteIndex'),
      child: _sellInItemCell(context, colorScheme, record),
    );
    final cells = <Widget>[
      item,
      ..._sellInRowCells(context, colorScheme, record),
    ];
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _sellInRowMinHeight),
        child: InkWell(
          hoverColor: colorScheme.onSurface.withValues(alpha: 0.08),
          // Hover affordance only — SKU opens via the item cell InkWell.
          onTap: () {},
          mouseCursor: SystemMouseCursors.basic,
          child: Container(
            key: ValueKey('sellin_record_row_$absoluteIndex'),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < cells.length; c++)
                  _sellInCell(
                    c,
                    cells[c],
                    alignment: c == 0
                        ? AlignmentDirectional.topStart
                        : (c == 3 ||
                                c == 4 ||
                                c == 5 ||
                                c == 6 ||
                                c == 7 ||
                                c == 10)
                            ? AlignmentDirectional.topEnd
                            : AlignmentDirectional.topCenter,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _sellInItemCell(BuildContext context, ColorScheme colorScheme, SellInRecordItem r) {
    final theme = Theme.of(context);
    final hasIdCard = r.itemCode.isNotEmpty || r.barcode.isNotEmpty;
    return InkWell(
      borderRadius: M3Shape.radiusSm,
      onTap: () => _openProductIdCard(
        itemCode: r.itemCode,
        barcode: r.barcode,
        skuName: r.itemName,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: r.itemName,
            child: Text(
              r.itemName,
              key: const ValueKey('sellin_record_item_name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (hasIdCard) ...[
            const SizedBox(height: 2.0),
            _HoverCopyCode(
              icon: AppIcons.tag,
              label: 'الكود',
              value: r.itemCode,
            ),
            _HoverCopyCode(
              icon: AppIcons.barcode,
              label: 'الباركود',
              value: r.barcode,
            ),
          ],
        ],
      ),
    );
  }

  /// Arabic label for the backend pricing-wave key; unknown keys are hidden.
  static String? pricingWaveLabelAr(String key) {
    switch (key) {
      case 'current_list':
        return 'سعر القائمة الحالي';
      case 'promo_discounted':
        return 'سعر عرض مخفّض';
      case 'historical_pre_aug':
        return 'سعر قبل تحديث أغسطس';
      default:
        return null;
    }
  }

  // Primary (bodyMedium) and secondary (labelSmall/bodySmall muted) cell text.
  Widget _primary(
    BuildContext context,
    String text, {
    Color? color,
    FontWeight weight = FontWeight.w500,
    String? tooltip,
    Key? key,
    int maxLines = 2,
    TextAlign textAlign = TextAlign.center,
    bool tabular = false,
    bool isolateLtr = false,
  }) {
    final display = isolateLtr ? ltrIsolate(text) : text;
    return Tooltip(
      message: tooltip ?? text,
      child: Text(
        display,
        key: key,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: weight,
              color: color ?? Theme.of(context).colorScheme.onSurface,
              fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
            ),
      ),
    );
  }

  Widget _secondary(
    BuildContext context,
    String text, {
    Color? color,
    TextAlign textAlign = TextAlign.center,
    int maxLines = 2,
    bool tabular = false,
    bool isolateLtr = false,
  }) {
    final display = isolateLtr ? ltrIsolate(text) : text;
    return Tooltip(
      message: text,
      child: Text(
        display,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
              fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
            ),
      ),
    );
  }

  List<Widget> _sellInRowCells(
    BuildContext context,
    ColorScheme colorScheme,
    SellInRecordItem r,
  ) {
    final unitsSupplied = r.totalUnitsSupplied > 0
        ? r.totalUnitsSupplied
        : (r.netQtyCases * (r.unitsPerCarton > 0 ? r.unitsPerCarton : 12)).round();
    final grossInclVat =
        r.grossValueInclVatEgp > 0 ? r.grossValueInclVatEgp : r.netValueEgp * 1.14;
    final vatAmount =
        r.vatAmountEgp > 0 ? r.vatAmountEgp : r.netValueEgp * 0.14;
    final actualCasePrice = r.actualCasePriceExclEgp > 0
        ? r.actualCasePriceExclEgp
        : (r.netQtyCases > 0 ? r.netValueEgp / r.netQtyCases : 0.0);
    final wave = pricingWaveLabelAr(r.pricingWaveStatus);
    Widget col(List<Widget> c) => Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: c,
        );
    Widget endCol(List<Widget> c) => Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: c,
        );

    final period = '${r.monthAr.isNotEmpty ? r.monthAr : r.monthNum} ${r.year}';
    final fileTip = r.sourceFilename.isEmpty
        ? '—'
        : '${r.sourceFilename}·$period';

    return [
      _primary(context, period, weight: FontWeight.w400, maxLines: 1),
      col([
        M3ChipSurface(
          color: colorScheme.surfaceContainerHigh,
          child: Text(
            _chainNameAr(r.retailerChain),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        if (r.governorate.isNotEmpty)
          _secondary(context, _displayLocation(r.governorate)),
      ]),
      endCol([
        _primary(
          context,
          '${CurrencyFormatter.formatNumber(r.netQtyCases.round())} كرتونة',
          weight: FontWeight.w500,
          textAlign: TextAlign.end,
          tabular: true,
          maxLines: 1,
        ),
        _secondary(
          context,
          r.unitsPerCarton > 0
              ? '${CurrencyFormatter.formatNumber(unitsSupplied)} وحدة • ${r.unitsPerCarton}/كرتونة'
              : '${CurrencyFormatter.formatNumber(unitsSupplied)} وحدة',
          textAlign: TextAlign.end,
          tabular: true,
        ),
      ]),
      _primary(
        context,
        CurrencyFormatter.formatCompactEGP(r.netValueEgp),
        key: const ValueKey('sellin_record_net'),
        weight: FontWeight.w500,
        tooltip: CurrencyFormatter.formatEGP(r.netValueEgp),
        textAlign: TextAlign.end,
        tabular: true,
        maxLines: 1,
      ),
      endCol([
        _primary(
          context,
          CurrencyFormatter.formatCompactEGP(grossInclVat),
          tooltip: CurrencyFormatter.formatEGP(grossInclVat),
          textAlign: TextAlign.end,
          tabular: true,
          maxLines: 1,
        ),
        _secondary(
          context,
          'الضريبة: ${CurrencyFormatter.formatCompactEGP(vatAmount)}',
          textAlign: TextAlign.end,
          tabular: true,
        ),
      ]),
      endCol([
        _primary(
          context,
          CurrencyFormatter.formatEGP(actualCasePrice, showDecimals: true),
          key: const ValueKey('sellin_record_actual_carton'),
          tooltip:
              'الفعلي: ${CurrencyFormatter.formatEGP(actualCasePrice, showDecimals: true)}',
          textAlign: TextAlign.end,
          tabular: true,
          maxLines: 1,
        ),
        if (r.officialCartonExclVatEgp > 0)
          Tooltip(
            message: r.effectiveDiscountPct != 0
                ? 'خصم فعلي عن القائمة ${r.effectiveDiscountPct.toStringAsFixed(1)}%'
                : 'سعر القائمة بدون ضريبة',
            child: _secondary(
              context,
              'القائمة: ${CurrencyFormatter.formatEGP(r.officialCartonExclVatEgp, showDecimals: true)}',
              textAlign: TextAlign.end,
              tabular: true,
            ),
          ),
        if (r.officialCartonExclVatEgp > 0 &&
            r.effectiveDiscountPct <= 0 &&
            wave != null)
          _secondary(context, wave, textAlign: TextAlign.end),
      ]),
      _expectedCartonCell(context, colorScheme, r, actualCasePrice),
      col([
        Tooltip(
          message: '${r.brand} • ${r.subCategory}',
          child: Text(
            '${r.brand} • ${r.subCategory}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
          ),
        ),
        if (r.departmentAr.isNotEmpty) _secondary(context, r.departmentAr),
      ]),
      _primary(
        context,
        r.salesRep,
        weight: FontWeight.w400,
        tooltip: r.salesRep,
        maxLines: 1,
      ),
      _primary(
        context,
        r.weightTons.toStringAsFixed(2),
        weight: FontWeight.w400,
        textAlign: TextAlign.end,
        tabular: true,
        maxLines: 1,
      ),
      SizedBox(
        width: 48.0,
        height: 40.0,
        child: IconButton(
          key: const ValueKey('sellin_record_file_btn'),
          icon: Icon(
            AppIcons.tableView,
            size: 24.0,
            color: colorScheme.onSurfaceVariant,
          ),
          tooltip: fileTip,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: r.sourceFilename.isEmpty ? null : () {},
        ),
      ),
    ];
  }

  /// سعر الكرتونة المتوقع with this row's chain terms, and actual − expected below it.
  Widget _expectedCartonCell(
    BuildContext context,
    ColorScheme colorScheme,
    SellInRecordItem r,
    double actual,
  ) {
    final expected = r.expectedCartonExclVatEgp;
    if (expected <= 0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _primary(
            context,
            '—',
            key: const ValueKey('sellin_record_expected_carton'),
            textAlign: TextAlign.end,
          ),
          _secondary(context, 'بلا سعر رسمي', textAlign: TextAlign.end),
        ],
      );
    }
    final diff = actual > 0 ? actual - expected : 0.0;
    final diffPct = diff / expected * 100;
    final match = actual <= 0 || diff.abs() < 0.005;
    final Widget tag;
    if (match) {
      tag = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.success, size: 16.0, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4.0),
          Text(
            'مطابق',
            key: const ValueKey('sellin_record_expected_carton_diff'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      );
    } else {
      final sign = diff > 0 ? '+' : '\u2212';
      final diffText =
          '\u2066$sign${CurrencyFormatter.formatEGP(diff.abs(), showDecimals: true)} ($sign${diffPct.abs().toStringAsFixed(1)}%)\u2069';
      final below = diff < 0;
      tag = M3ChipSurface(
        color: below ? colorScheme.errorContainer : colorScheme.tertiaryContainer,
        child: Text(
          diffText,
          key: const ValueKey('sellin_record_expected_carton_diff'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: below
                    ? colorScheme.onErrorContainer
                    : colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _primary(
          context,
          CurrencyFormatter.formatEGP(expected, showDecimals: true),
          key: const ValueKey('sellin_record_expected_carton'),
          tooltip:
              '${CurrencyFormatter.formatEGP(r.officialCartonExclVatEgp, showDecimals: true)} × (1 − ${SellInPriceWaterfallCard.pct(r.invoiceDiscountPct)}) × (1 − ${SellInPriceWaterfallCard.pct(r.extraDiscountPct)})',
          textAlign: TextAlign.end,
          tabular: true,
          maxLines: 1,
        ),
        const SizedBox(height: 2.0),
        Tooltip(message: 'الفعلي − المتوقع', child: tag),
      ],
    );
  }

  Widget _twoLineHeader(BuildContext context, String title, String subtitle) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // Scale down if needed so both lines always fit the 56dp header cell.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: muted,
              height: 1.1,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  String _chainNameAr(String chain) {
    final c = chain.toLowerCase();
    if (c.contains('fathalla') || chain.contains('فتح الله')) return 'فتح الله';
    if (c.contains('gomla') || chain.contains('جملة')) return 'جملة ماركت';
    if (c.contains('carrefour') || chain.contains('كارفور')) return 'كارفور';
    return chain;
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
        : netExclVat * _data.vatRatePct / 100.0;
    final grossInclVat = _data.totalGrossInclVatEgp > 0
        ? _data.totalGrossInclVatEgp
        : netExclVat + vat14;
    final discountPct = _data.effectiveDiscountPct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: M3Spacing.sm),
            child: LinearProgressIndicator(key: ValueKey('sell_in_loading_bar'), year2023: false),
          ),
        // 1. Summary KPI Row - Stretches across full horizontal width
        LayoutBuilder(
          builder: (context, constraints) {
            final card1 = _buildSummaryCard(
              context,
              titleAr: 'صافي التوريد',
              titleEn: 'Net Sell-In after returns (excl. VAT)',
              titleTooltip: 'صافي التوريد بعد المرتجعات (غير شامل الضريبة)',
              value: CurrencyFormatter.formatCompactEGP(netExclVat),
              subtitle:
                  'شامل الضريبة: ${CurrencyFormatter.formatCompactEGP(grossInclVat)} • ${CurrencyFormatter.formatUnits(_data.totalCount)} صف',
              icon: Icons.payments_rounded,
              color: colorScheme.primary,
            );
            final card2 = _buildSummaryCard(
              context,
              titleAr: 'الكمية',
              titleEn: 'Quantity (cases)',
              value:
                  '${CurrencyFormatter.formatNumber(_data.totalCases.round())} كرتونة',
              subtitle: _data.totalUnitsPieces > 0
                  ? '= ${CurrencyFormatter.formatNumber(_data.totalUnitsPieces)} وحدة'
                  : 'كرتونة موردة للسلاسل',
              icon: Icons.inventory_2_rounded,
              color: M3StatusColors.of(context).accents.teal,
            );
            final card3 = _buildSummaryCard(
              context,
              titleAr: 'إجمالي الوزن الفعلي',
              titleEn: 'Weight (t)',
              value: '${_data.totalWeightTons.toStringAsFixed(1)} طن',
              subtitle:
                  'الخصم التجاري عن قائمة الأسعار: ${discountPct.toStringAsFixed(1)}%',
              icon: Icons.scale_rounded,
              color: M3StatusColors.of(context).accents.indigo,
            );
            final card4 = _buildSummaryCard(
              context,
              titleAr: 'قيمة الفواتير',
              titleEn: 'Gross Sell-In (incl. VAT)',
              titleTooltip: 'قيمة الفواتير شامل الضريبة',
              value: CurrencyFormatter.formatCompactEGP(grossInclVat),
              subtitle:
                  'الضريبة: ${CurrencyFormatter.formatCompactEGP(vat14)} • المتوقع: ${CurrencyFormatter.formatCompactEGP(_data.totalExpectedEgp)}',
              icon: Icons.receipt_long_rounded,
              color: M3StatusColors.of(context).accents.caution,
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

        SellInPriceWaterfallCard(
          data: _data,
          chainLabel: _chainNameAr,
          loading: _isLoading,
        ),

        M3Spacing.gapMD,

        // 2. Filter & Upload Toolbar
        Container(
          key: const ValueKey('sellin_data_filter_bar'),
          padding: M3Spacing.pSm,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Wrap(
            spacing: M3Spacing.sm,
            runSpacing: M3Spacing.xs,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: M3Spacing.sm,
                runSpacing: M3Spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  M3Dropdown<String>(
width: 190.0,
fitOptions: true,
value: _selectedChain,
label: 'السلسلة',
options: m3OptionsFromMenuItems<String>([
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('كل السلاسل'),
                        ),
                        for (final c in _chains)
                          if (isExplicitChain(c.code))
                            DropdownMenuItem(value: c.code, child: Text(c.displayName.isNotEmpty ? c.displayName : c.code)),
                      ]),
onChanged: m3Legacy<String>((v) {
                        if (v != null) {
                          setState(() {
                            _selectedChain = v;
                            _resetRecordsPage();
                          });
                          _loadSellInRecords();
                          _loadStockReconciliationReport();
                        }
                      }),
),
                  M3Dropdown<int>(
width: 130.0,
fitOptions: true,
value: _selectedYear,
label: 'سنة البيانات',
options: m3OptionsFromMenuItems<int>([
                        const DropdownMenuItem(value: 0, child: Text('كل السنوات')),
                        for (final y in AvailableYears.current.including(_selectedYear))
                          DropdownMenuItem(value: y, child: Text('$y')),
                      ]),
onChanged: m3Legacy<int>((v) {
                        if (v != null) {
                          setState(() {
                            _selectedYear = v;
                            _yearTouched = true;
                            _resetRecordsPage();
                          });
                          _loadSellInRecords();
                          _loadStockReconciliationReport();
                        }
                      }),
),
                  M3Dropdown<int>(
width: 150.0,
fitOptions: true,
value: _selectedMonth,
label: 'الشهر',
options: m3OptionsFromMenuItems<int>([
                        const DropdownMenuItem(value: 0, child: Text('كل الشهور')),
                        const DropdownMenuItem(value: 1, child: Text('يناير (01)')),
                        const DropdownMenuItem(value: 2, child: Text('فبراير (02)')),
                        const DropdownMenuItem(value: 3, child: Text('مارس (03)')),
                        const DropdownMenuItem(value: 4, child: Text('أبريل (04)')),
                        const DropdownMenuItem(value: 5, child: Text('مايو (05)')),
                        const DropdownMenuItem(value: 6, child: Text('يونيو (06)')),
                        const DropdownMenuItem(value: 7, child: Text('يوليو (07)')),
                        const DropdownMenuItem(value: 8, child: Text('أغسطس (08)')),
                        const DropdownMenuItem(value: 9, child: Text('سبتمبر (09)')),
                        const DropdownMenuItem(value: 10, child: Text('أكتوبر (10)')),
                        const DropdownMenuItem(value: 11, child: Text('نوفمبر (11)')),
                        const DropdownMenuItem(value: 12, child: Text('ديسمبر (12)')),
                      ]),
onChanged: m3Legacy<int>((v) {
                        if (v != null) {
                          setState(() {
                            _selectedMonth = v;
                            _resetRecordsPage();
                          });
                          _loadSellInRecords();
                        }
                      }),
),
                  M3SearchFieldWidth(
                    hintText: 'ابحث بالصنف أو الكود أو الباركود',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w300),
                    width: 220.0,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'ابحث بالصنف أو الكود أو الباركود',
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
                        border: const OutlineInputBorder(
                          borderRadius: M3Shape.radiusMd,
                        ),
                      ),
                      onChanged: (val) {
                        _searchQuery = val;
                        _resetRecordsPage();
                        _loadSellInRecords();
                      },
                    ),
                  ),
                ],
              ),
              SellActionButtons.row(
                context,
                uploadLabel: 'رفع ملف Sell-In',
                onUpload: () => _pickAndUploadSellInFile(),
                isUploading: _isUploading,
                onExportPdf: _handleExportPdf,
                onExportExcel: _handleExportExcel,
              ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // 3. Sell-In Records Table
        Container(
          key: const ValueKey('sellin_records_surface'),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: M3Shape.radiusMd,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(48.0),
                  child: Center(child: CircularProgressIndicator(year2023: false)),
                )
              : _records.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Center(
                        child: Text(
                          'لا توجد نتائج. جرّب تغيير الفلاتر.',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : LayoutBuilder(builder: (context, constraints) {
                      // All 12 columns share the full width — no horizontal scroll.
                      const pad = M3Spacing.sm;
                      _layoutSellInColumns(constraints.maxWidth - pad * 2);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          M3Spacing.sm,
                          M3Spacing.xs,
                          M3Spacing.sm,
                          0,
                        ),
                        child: _buildVirtualSellInTable(context, colorScheme),
                      );
                    }),
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
            'لا توجد بيانات كافية لحساب المخزون.',
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
    final displaySellOutFactoryCostExclVatEgp =
        useMatchedWindow && d.matchedSellOutFactoryCostExclVatEgp > 0
            ? d.matchedSellOutFactoryCostExclVatEgp
            : displaySellOutFactoryCostEgp;
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
        : '—';
    final pendingLabel = d.pendingSellOutPeriodLabel.isNotEmpty
        ? d.pendingSellOutPeriodLabel
        : '—';

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
          key: const ValueKey('sellin_period_strip'),
          padding: M3Spacing.pSm,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
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
                    size: 24.0,
                  ),
                  const SizedBox(width: 10.0),
                  // Flexible lets the long title wrap inside the Wrap run instead of
                  // overflowing the min-size Row at ~1440px.
                  Flexible(
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مطابقة Sell-In و Sell-Out وقائمة الأصناف',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'نحوّل مبيعات Sell-Out إلى كراتين ونحسب هامش السلسلة.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
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
                      d.matchedMonthsCount > 0 ? 'الفترة المطابقة ($matchedLabel • ${d.matchedMonthsCount} أشهر)' : 'الفترة المطابقة ($matchedLabel)',
                      style: M3TextVariants.cellPlusHeavy.copyWith(color: !_showFullYtdReconciliation
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface),
                    ),
                    onSelected: (_) => setState(() => _showFullYtdReconciliation = false),
                  ),
                  ChoiceChip(
                    selected: _showFullYtdReconciliation,
                    label: Text(
                      'العام كاملًا (يشمل ما لم يُبَع بعد)',
                      style: M3TextVariants.cellPlusHeavy.copyWith(color: _showFullYtdReconciliation
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface),
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
                        color: M3StatusColors.of(context).accents.highlightSurface.withOpacity(0.85),
                        borderRadius: M3Shape.radiusSm,
                        border: Border.all(color: M3StatusColors.of(context).accents.highlightBorder.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hourglass_top_rounded,
                            size: 18.0,
                            color: M3StatusColors.of(context).accents.highlight,
                          ),
                          const SizedBox(width: 6.0),
                          Text(
                            'بانتظار Sell-Out ($pendingLabel): ${CurrencyFormatter.formatNumber(d.pendingSellOutCases.round())} كرتونة (${CurrencyFormatter.formatCompactEGP(d.pendingSellOutValueEgp)})',
                            style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                               fontSize: M3FontSize.bodySmall,                               fontWeight: FontWeight.w800,                               color: M3StatusColors.of(context).accents.highlight,                             )),
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
              // Short title like its sibling cards; the matched period moves
              // to the detail line so it is never cut at 1280.
              titleAr: useMatchedWindow
                  ? 'Sell-In المطابق'
                  : 'Sell-In منذ بداية العام',
              titleTooltip: useMatchedWindow
                  ? 'Sell-In للفترة المطابقة'
                  : 'Sell-In منذ بداية العام',
              titleEn: useMatchedWindow ? 'Sell-In (matched period)' : 'Sell-In YTD',
              value: CurrencyFormatter.formatCompactEGP(displaySellInEgp),
              subtitle: useMatchedWindow
                  ? (matchedLabel.contains(' (')
                      ? matchedLabel.split(' (').first
                      : matchedLabel)
                  : '${CurrencyFormatter.formatNumber(displaySellInCases.round())} كرتونة',
              subtitleTooltip: useMatchedWindow
                  ? '$matchedLabel • ${CurrencyFormatter.formatNumber(displaySellInCases.round())} كرتونة • شامل الضريبة: ${CurrencyFormatter.formatCompactEGP(displaySellInGrossEgp)}'
                  : '${CurrencyFormatter.formatNumber(displaySellInCases.round())} كرتونة • شامل الضريبة: ${CurrencyFormatter.formatCompactEGP(displaySellInGrossEgp)}',
              icon: Icons.local_shipping_rounded,
              color: colorScheme.primary,
            );
            final card2 = _buildSummaryCard(
              context,
              titleAr: 'Sell-Out بسعر البيع للمستهلك',
              titleTooltip:
                  'Sell-Out بسعر البيع للمستهلك (قيمة الكاشير POS)',
              titleEn: 'Sell-Out at Consumer Retail Price',
              value: CurrencyFormatter.formatCompactEGP(displaySellOutPosEgp),
              subtitle:
                  '${CurrencyFormatter.formatNumber(displaySellOutCases.round())} كرتونة (${CurrencyFormatter.formatNumber(d.matchedSellOutUnits)} وحدة) • تكلفة المصنع ${CurrencyFormatter.formatCompactEGP(displaySellOutFactoryCostExclVatEgp)}',
              subtitleTooltip:
                  'تكلفة المصنع بدون ضريبة، بعد خصم الفاتورة والخصم الإضافي للسلسلة',
              icon: Icons.point_of_sale_rounded,
              color: M3StatusColors.of(context).accents.teal,
            );
            final card3 = _buildSummaryCard(
              context,
              titleAr: 'المخزون المتبقي',
              titleTooltip: 'المخزون المتبقي لدى السلسلة',
              titleEn: 'Remaining Stock',
              value: CurrencyFormatter.formatCompactEGP(remainingStockEgp),
              subtitle:
                  '${CurrencyFormatter.formatNumber(remainingStockCases.round())} كرتونة',
              icon: Icons.warehouse_rounded,
              color: M3StatusColors.of(context).accents.alert,
            );
            final card4 = _buildSummaryCard(
              context,
              titleAr: 'نسبة التصريف (STR)',
              titleEn: 'Sell-Through Rate',
              value: '${overallStrPct.toStringAsFixed(1)}%',
              subtitle:
                  '${d.urgentReplenishmentCount} صنف يحتاج إعادة طلب • ${d.totalSuggestedPoCases} كرتونة مقترحة',
              icon: Icons.autorenew_rounded,
              color: M3StatusColors.of(context).accents.indigo,
            );

            return _buildFourCardResponsiveLayout(
              constraints.maxWidth,
              card1,
              card2,
              card3,
              card4,
              id: 'stock',
            );
          },
        ),

        M3Spacing.gapSM,

        // 1.B Strategic 3-Way Linkage KPIs: Retailer Gross Margin & YoY 2026 vs 2025 Growth
        LayoutBuilder(
          builder: (context, constraints) {
            final marginCard = _buildSummaryCard(
              context,
              titleAr: 'هامش السلسلة',
              titleEn: 'Chain Margin',
              titleTooltip:
                  'هامش السلسلة = سعر البيع للمستهلك (POS) بدون ضريبة − تكلفة المصنع بدون ضريبة. '
                  'تكلفة المصنع = السعر الرسمي ÷ (1 + ضريبة السلسلة) × (1 − خصم الفاتورة) × (1 − الخصم الإضافي للسلسلة). '
                  'الإعدادات من «حاسبة الطلبيات والخصومات والهوامش» في كارتة الأصناف.',
              value: d.matchedSellOutPosValueEgp > 0 && d.matchedSellOutValueWithCostEgp <= 0
                  ? '—'
                  : CurrencyFormatter.formatMarginSummary(d.matchedChainGrossMarginEgp, d.matchedChainGrossMarginPct),
              subtitle: d.matchedMissingCostSellOutEgp > 0
                  ? 'محسوب على الأصناف المعروفة تكلفتها فقط • مستبعد ${CurrencyFormatter.formatCompactEGP(d.matchedMissingCostSellOutEgp)}'
                  : 'سعر البيع للمستهلك − تكلفة المصنع (كلاهما بدون ضريبة)',
              icon: Icons.paid_rounded,
              // A real loss (negative profit) is shown in the theme error colour.
              color: d.matchedChainGrossMarginEgp < 0
                  ? Theme.of(context).colorScheme.error
                  : M3StatusColors.of(context).accents.positiveStrong,
            );
            final yoyCard = _buildSummaryCard(
              context,
              titleAr: 'النمو عن العام السابق',
              titleEn: 'Sell-Out Growth YoY',
              titleTooltip: 'نمو Sell-Out مقارنة بالعام السابق',
              // No matched month with last-year data: "—", not a fake +0.0%.
              value: d.matchedYoyAvailable
                  ? '${CurrencyFormatter.formatSignedPct(d.matchedYoyValueGrowthPct)} بالقيمة'
                  : '—',
              subtitle: d.matchedYoyAvailable
                  ? 'بالكمية: ${CurrencyFormatter.formatSignedPct(d.matchedYoyUnitsGrowthPct)} عن نفس الفترة من العام السابق'
                  : 'لا توجد بيانات للعام السابق',
              icon: Icons.trending_up_rounded,
              color: M3StatusColors.of(context).accents.purpleStrong,
            );

            return M3EqualHeightGrid(
              key: const ValueKey('sellin_kpi_grid_linkage'),
              columns: constraints.maxWidth < 760 ? 1 : 2,
              spacing: M3Spacing.sm,
              runSpacing: M3Spacing.sm,
              children: [marginCard, yoyCard],
            );
          },
        ),

        M3Spacing.gapSM,

        // 1.C Items with no real factory cost (needed from Adeco) — never estimated.
        _buildMissingCostSection(context, colorScheme, d),

        M3Spacing.gapMD,

        // 2. Filter & Export Bar for Stock Balance Reports
        Container(
          key: const ValueKey('sellin_stock_filter_bar'),
          padding: M3Spacing.pSm,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Wrap(
            spacing: M3Spacing.sm,
            runSpacing: M3Spacing.xs,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: M3Spacing.sm,
                runSpacing: M3Spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  M3Dropdown<String>(
width: 190.0,
fitOptions: true,
value: _selectedChain,
label: 'السلسلة',
options: m3OptionsFromMenuItems<String>([
                        const DropdownMenuItem(value: 'all', child: Text('كل السلاسل')),
                        for (final c in _chains)
                          if (isExplicitChain(c.code))
                            DropdownMenuItem(value: c.code, child: Text(c.displayName.isNotEmpty ? c.displayName : c.code)),
                      ]),
onChanged: m3Legacy<String>((v) {
                        if (v != null) {
                          setState(() => _selectedChain = v);
                          _loadStockReconciliationReport();
                          _loadSellInRecords();
                        }
                      }),
),
                  M3Dropdown<int>(
width: 140.0,
fitOptions: true,
value: _selectedYear,
label: 'سنة البيانات',
options: m3OptionsFromMenuItems<int>([
                        const DropdownMenuItem(value: 0, child: Text('كل السنوات')),
                        for (final y in AvailableYears.current.including(_selectedYear))
                          DropdownMenuItem(value: y, child: Text('$y')),
                      ]),
onChanged: m3Legacy<int>((v) {
                        if (v != null) {
                          setState(() {
                            _selectedYear = v;
                            _yearTouched = true;
                          });
                          _loadStockReconciliationReport();
                          _loadSellInRecords();
                        }
                      }),
),
                  M3Dropdown<String>(
width: 210.0,
fitOptions: true,
value: _stockStatusFilter,
label: 'حالة المخزون',
options: m3OptionsFromMenuItems<String>([
                        const DropdownMenuItem(value: 'all', child: Text('كل الحالات')),
                        const DropdownMenuItem(
                          value: 'urgent_replenishment',
                          child: Text('إعادة طلب عاجلة'),
                        ),
                        const DropdownMenuItem(
                          value: 'optimal',
                          child: Text('مخزون مناسب'),
                        ),
                        const DropdownMenuItem(
                          value: 'overstock',
                          child: Text('مخزون زائد / بطيء الحركة'),
                        ),
                      ]),
onChanged: m3Legacy<String>((v) {
                        if (v != null) {
                          setState(() => _stockStatusFilter = v);
                          _loadStockReconciliationReport();
                        }
                      }),
),
                ],
              ),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  OutlinedButton.icon(
                    onPressed: _handleExportStockBalanceExcel,
                    icon: const Icon(Icons.download_rounded, size: 20.0),
                    label: const Text('تصدير CSV'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _handlePrintStockBalancePdf,
                    icon: const Icon(Icons.print_rounded, size: 20.0),
                    label: const Text('طباعة'),
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
            color: M3TableSurface.color(colorScheme),
            borderRadius: M3Shape.radiusLg,
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
                          '1. المخزون الشهري',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          rtlEnd(
                            'رصيد آخر الشهر = رصيد أول الشهر + ${ltrIsolate('Sell-\u2060In')} − ${ltrIsolate('Sell-\u2060Out')}',
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.visible,
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
                // Extra width follows each column's content (status chip widest).
                columnFlex: const [0.8, 0.9, 0.85, 0.85, 0.95, 0.85, 0.85, 0.8, 1.1],
                showSwipeHint: true,
                child: DataTable(
                  key: const ValueKey('sellin_monthly_table'),
                  // Compact spacing + compact money so all columns fit 1030dp.
                  columnSpacing: M3Spacing.xs,
                  horizontalMargin: M3Spacing.xs,
                  dataRowMinHeight: 64.0,
                  dataRowMaxHeight: 128.0,
                  headingRowColor: WidgetStatePropertyAll(
                    colorScheme.surfaceContainerHigh.withOpacity(0.5),
                  ),
                  columns: const [
                    DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('الشهر / السنة')),
                    DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('رصيد أول الشهر'), numeric: true),
                    DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('+ Sell-In'), numeric: true),
                    DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('− Sell-Out'), numeric: true),
                    DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('هامش السلسلة'), numeric: true),
                    DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('النمو السنوي'), numeric: true),
                    DataColumn(headingRowAlignment: MainAxisAlignment.center, 
                      label: Text('رصيد آخر الشهر'),
                      numeric: true,
                    ),
                    DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('نسبة التصريف'), numeric: true),
                    DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('الحالة')),
                  ],
                  rows: visibleMonthlyRows.map((m) {
                    final isPositiveClosing = m.closingStockValueEgp >= 0;
                    return DataRow(
                      cells: [
                        _fitCell(_monthlyCellMaxWidth, 
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _mText(
                                '${m.monthNum} - ${m.monthAr} ${m.year}',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              if (!m.hasActualSellOut)
                                _mText(
                                  'بانتظار ملف Sell-Out',
                                  style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                     fontSize: M3FontSize.bodySmall,                                     fontWeight: FontWeight.w700,                                     color: M3StatusColors.of(context).accents.highlight,                                   )),
                                ),
                            ],
                          ),
                        ),
                        _fitCell(_monthlyCellMaxWidth, 
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _mText(CurrencyFormatter.formatCompactEGP(m.openingStockValueEgp)),
                              _mText(
                                '${CurrencyFormatter.formatNumber(m.openingStockCases.round())} كرتونة',
                                style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                   fontSize: M3FontSize.bodySmall,                                   color: colorScheme.onSurfaceVariant,                                 )),
                              ),
                            ],
                          ),
                        ),
                        _fitCell(_monthlyCellMaxWidth, 
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _mText(
                                CurrencyFormatter.formatCompactEGP(m.sellInValueEgp),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.primary,
                                ),
                              ),
                              _mText(
                                '${_signedCount(m.sellInCases.round(), positive: true)} كرتونة',
                                style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                   fontSize: M3FontSize.bodySmall,                                   fontWeight: FontWeight.w700,                                   color: colorScheme.onSurfaceVariant,                                 )),
                              ),
                              if (m.sellInGrossInclVatEgp > 0)
                                _mText(
                                  'شامل الضريبة: ${CurrencyFormatter.formatCompactEGP(m.sellInGrossInclVatEgp)}',
                                  style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                     fontSize: M3FontSize.bodySmall,                                     color: M3StatusColors.of(context).accents.tealStrong,                                   )),
                                ),
                            ],
                          ),
                        ),
                        _fitCell(_monthlyCellMaxWidth, 
                          m.hasActualSellOut
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _mText(
                                      CurrencyFormatter.formatCompactEGP(m.sellOutValueEgp),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: M3StatusColors.of(context).accents.teal,
                                      ),
                                    ),
                                    _mText(
                                      '${_signedCount(m.sellOutEstCases.round(), positive: false)} كرتونة',
                                      style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                         fontSize: M3FontSize.bodySmall,                                         fontWeight: FontWeight.w700,                                         color: colorScheme.onSurfaceVariant,                                       )),
                                    ),
                                    if (m.sellOutFactoryCostExclVatEgp > 0)
                                      _mText(
                                        'تكلفة المصنع: ${CurrencyFormatter.formatCompactEGP(m.sellOutFactoryCostExclVatEgp)}',
                                        style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                           fontSize: M3FontSize.bodySmall,                                           color: colorScheme.onSurfaceVariant,                                         )),
                                      ),
                                  ],
                                )
                              : _mText(
                                  'بانتظار ملف Sell-Out',
                                  style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                     fontSize: M3FontSize.bodySmall,                                     fontWeight: FontWeight.w700,                                     color: M3StatusColors.of(context).accents.highlight,                                   )),
                                ),
                        ),
                        _fitCell(_monthlyCellMaxWidth, 
                          m.hasActualSellOut && m.sellOutFactoryCostInclVatEgp > 0
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _mText(
                                      CurrencyFormatter.formatMarginEGP(m.chainGrossMarginEgp),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: m.chainGrossMarginEgp < 0
                                            ? colorScheme.error
                                            : M3StatusColors.of(context).accents.positiveStrong,
                                      ),
                                    ),
                                    _mText(
                                      CurrencyFormatter.formatMarginPct(m.chainGrossMarginPct),
                                      style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                         fontSize: M3FontSize.bodySmall,                                         fontWeight: FontWeight.w700,                                         color: M3StatusColors.of(context).accents.positive,                                       )),
                                    ),
                                  ],
                                )
                              : const Text('-'),
                        ),
                        _fitCell(_monthlyCellMaxWidth, 
                          m.hasActualSellOut && m.prevYearSellOutValueEgp > 0
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _mText(
                                      CurrencyFormatter.formatSignedPct(m.yoySellOutGrowthPct),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: m.yoySellOutGrowthPct >= 0
                                            ? M3StatusColors.of(context).accents.purpleStrong
                                            : colorScheme.error,
                                      ),
                                    ),
                                    _mText(
                                      'العام السابق: ${CurrencyFormatter.formatCompactEGP(m.prevYearSellOutValueEgp)}',
                                      style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                         fontSize: M3FontSize.bodySmall,                                         color: colorScheme.onSurfaceVariant,                                       )),
                                    ),
                                  ],
                                )
                              : const Text('-'),
                        ),
                        _fitCell(_monthlyCellMaxWidth, 
                          Column(
                            key: const ValueKey('sellin_monthly_closing'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _mText(
                                CurrencyFormatter.formatCompactEGP(m.closingStockValueEgp),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: isPositiveClosing ? colorScheme.onSurface : colorScheme.error,
                                ),
                              ),
                              _mText(
                                '${CurrencyFormatter.formatNumber(m.closingStockCases.round())} كرتونة',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        _fitCell(_monthlyCellMaxWidth, 
                          _mText(
                            m.hasActualSellOut
                                ? '${m.sellThroughRatePct.toStringAsFixed(1)}%'
                                : 'بانتظار ملف Sell-Out',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        DataCell(
                          _stockStatusChip(
                            context,
                            m.stockHealthLabelAr,
                            m.stockHealthStatus,
                            key: const ValueKey('sellin_monthly_status'),
                            wrapWidth: _monthlyStatusMaxWidth,
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
              // 1b. Margin / promo filter (shared chips with Sell-Out)
              if (!matchesSellInMarginFilter(item, _skuMarginFilter)) {
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
                color: M3TableSurface.color(colorScheme),
                borderRadius: M3Shape.radiusLg,
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
                      Icon(Icons.inventory_rounded, color: M3StatusColors.of(context).accents.alert),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '2. المخزون وإعادة الطلب حسب الصنف',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2.0),
                            Text(
                              'لكل صنف: Sell-In و Sell-Out والمخزون وأيام التغطية والكمية المقترحة.',
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
                    padding: M3Spacing.pSm,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh.withOpacity(0.35),
                      borderRadius: M3Shape.radiusMd,
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
                                hintText: 'ابحث بالصنف أو العلامة التجارية',
                                hintStyle: M3TextVariants.compactLabel.copyWith(color: colorScheme.onSurfaceVariant),
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
                                  borderRadius: M3Shape.radiusSm,
                                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: M3Shape.radiusSm,
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

                            final brandDropdown = M3Dropdown<String>(
key: const ValueKey('sellin_stock_brand_dropdown'),
fitOptions: true,
value: availableBrands.contains(_selectedSkuBrand) ? _selectedSkuBrand : 'all',
label: 'العلامة التجارية',
leadingIcon: Icons.branding_watermark_rounded,
options: m3OptionsFromMenuItems<String>([
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text(
                                    'كل العلامات التجارية (${d.inventoryAndPoItems.length})',
                                    style: M3TextVariants.compactLabelBold,
                                  ),
                                ),
                                ...availableBrands.map(
                                  (b) => DropdownMenuItem(
                                    value: b,
                                    child: Text(
                                      '$b (${brandItemCounts[b] ?? 0})',
                                      style: M3TextVariants.compactLabel,
                                    ),
                                  ),
                                ),
                              ]),
onChanged: m3Legacy<String>((val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedSkuBrand = val;
                                    _skuCurrentPage = 0;
                                  });
                                }
                              }),
);

                            final statusDropdown = M3Dropdown<String>(
fitOptions: true,
value: _skuStockStatusFilter,
label: 'حالة المخزون',
leadingIcon: Icons.filter_alt_rounded,
options: m3OptionsFromMenuItems<String>([
                                const DropdownMenuItem(
                                  value: 'all',
                                  child: Text('كل الحالات'),
                                ),
                                const DropdownMenuItem(
                                  value: 'urgent_replenishment',
                                  child: Text(
                                    'إعادة طلب عاجلة',
                                  ),
                                ),
                                const DropdownMenuItem(
                                  value: 'optimal',
                                  child: Text('مخزون مناسب'),
                                ),
                                const DropdownMenuItem(
                                  value: 'overstock',
                                  child: Text('مخزون زائد'),
                                ),
                              ]),
onChanged: m3Legacy<String>((val) {
                                if (val != null) {
                                  setState(() {
                                    _skuStockStatusFilter = val;
                                    _skuCurrentPage = 0;
                                  });
                                }
                              }),
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

                            // Dropdowns take the width of their longest option
                            // (never clipped); search fills the rest.
                            return Row(
                              children: [
                                Expanded(child: searchField),
                                const SizedBox(width: 12.0),
                                brandDropdown,
                                const SizedBox(width: 12.0),
                                statusDropdown,
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 10.0),
                        SellTableFilterChips(
                          key: const ValueKey('sell_in_margin_chips'),
                          options: SellTableFilterChips.marginOptions(
                            all: d.inventoryAndPoItems.length,
                            healthy: d.inventoryAndPoItems.where((i) => matchesSellInMarginFilter(i, 'healthy')).length,
                            lowMargin: d.inventoryAndPoItems.where((i) => matchesSellInMarginFilter(i, 'low_margin')).length,
                            negativeMargin: d.inventoryAndPoItems.where((i) => matchesSellInMarginFilter(i, 'negative_margin')).length,
                            promo: d.inventoryAndPoItems.where((i) => matchesSellInMarginFilter(i, 'promo')).length,
                          ),
                          selected: _skuMarginFilter,
                          onSelected: (v) => setState(() {
                            _skuMarginFilter = v;
                            _skuCurrentPage = 0;
                          }),
                        ),
                        if (availableBrands.isNotEmpty) ...[
                          const SizedBox(height: 10.0),
                          Wrap(
                            spacing: 6.0,
                            runSpacing: 6.0,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'العلامات التجارية: ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              SellTableFilterChips(
                                key: const ValueKey('sell_in_brand_chips'),
                                options: [
                                  SellTableFilterOption(
                                    value: 'all',
                                    label: 'الكل',
                                    count: d.inventoryAndPoItems.length,
                                  ),
                                  ...availableBrands.take(12).map((b) => SellTableFilterOption(
                                        value: b,
                                        label: b,
                                        count: brandItemCounts[b] ?? 0,
                                      )),
                                ],
                                selected: _selectedSkuBrand,
                                onSelected: (v) => setState(() {
                                  _selectedSkuBrand = (v == _selectedSkuBrand) ? 'all' : v;
                                  _skuCurrentPage = 0;
                                }),
                              ),
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
                    columnFlex: const [1.0, 1.0, 1.0, 1.0, 0.95, 1.1, 1.0],
                    // SKU column pinned; compact columns so the main ones fit 1030dp.
                    pinnedStart: _buildSkuPinnedColumn(context, currentSkuPageItems),
                    child: DataTable(
                      key: const ValueKey('sellin_sku_table'),
                      sortColumnIndex: _skuSortColumnIndex > 0 ? _skuSortColumnIndex - 1 : null,
                      sortAscending: _skuSortAscending,
                      columnSpacing: M3Spacing.xs,
                      horizontalMargin: M3Spacing.xs,
                      headingRowHeight: _skuHeadingHeight,
                      dataRowMinHeight: _skuRowHeight,
                      dataRowMaxHeight: _skuRowHeight,
                      headingRowColor: WidgetStatePropertyAll(
                        colorScheme.surfaceContainerHigh.withOpacity(0.5),
                      ),
                      columns: [
                        DataColumn(headingRowAlignment: MainAxisAlignment.center, 
                          label: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: _wrapHeader('العلامة التجارية'),
                            ),
                          onSort: (col, asc) => _onSortSku(1, asc),
                        ),
                        DataColumn(headingRowAlignment: MainAxisAlignment.center, 
                          label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4.0),
                              child: Text('Sell-In'),
                            ),
                          numeric: true,
                          onSort: (col, asc) => _onSortSku(2, asc),
                        ),
                        DataColumn(headingRowAlignment: MainAxisAlignment.center, 
                          label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4.0),
                              child: Text('Sell-Out'),
                            ),
                          numeric: true,
                          onSort: (col, asc) => _onSortSku(3, asc),
                        ),
                        DataColumn(headingRowAlignment: MainAxisAlignment.center, 
                          // Header tap sorts via onSort; a nested Tooltip/InkWell broke the
                          // DataTable columnHeader semantics tree.
                          tooltip: 'اضغط للترتيب',
                          label: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4.0),
                                child: Text('المخزون'),
                          ),
                          numeric: true,
                          onSort: (col, asc) => _onSortSku(4, asc),
                        ),
                        DataColumn(headingRowAlignment: MainAxisAlignment.center, 
                          // Header tap sorts via onSort; a nested Tooltip/InkWell broke the
                          // DataTable columnHeader semantics tree.
                          tooltip: 'اضغط للترتيب',
                          label: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: _wrapHeader('أيام التغطية'),
                          ),
                          numeric: true,
                          onSort: (col, asc) => _onSortSku(5, asc),
                        ),
                        DataColumn(headingRowAlignment: MainAxisAlignment.center, 
                          label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4.0),
                              child: Text('الحالة'),
                            ),
                          onSort: (col, asc) => _onSortSku(6, asc),
                        ),
                        DataColumn(headingRowAlignment: MainAxisAlignment.center, 
                          label: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: _wrapHeader('أمر الشراء المقترح'),
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
                            _fitCell(_skuCellMaxWidth, 
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 140.0),
                                    child: Tooltip(
                                      message: '${item.brand} • ${_displayLocation(item.governorate)}',
                                      child: Text(
                                        '${item.brand} • ${_displayLocation(item.governorate)}',
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                  if (item.officialCartonExclVatEgp > 0)
                                    _mText(
                                      'سعر القائمة: ${CurrencyFormatter.formatEGP(item.officialCartonExclVatEgp)}',
                                      style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                         fontSize: M3FontSize.bodySmall,                                         color: colorScheme.onSurfaceVariant,                                       )), maxLines: 3),
                                ],
                              ),
                            ),
                            _fitCell(_skuCellMaxWidth, 
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _mText(
                                    '${CurrencyFormatter.formatNumber(item.sellInCases.round())} كرتونة',
                                    style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 3),
                                  _mText(
                                    '${CurrencyFormatter.formatNumber(sellInUnits)} وحدة • ${CurrencyFormatter.formatCompactEGP(item.sellInValueEgp)}',
                                    style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                       fontSize: M3FontSize.bodySmall,                                       color: colorScheme.primary,                                       fontWeight: FontWeight.w700,                                     )), maxLines: 3),
                                ],
                              ),
                            ),
                            _fitCell(_skuCellMaxWidth, 
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _mText(
                                    '${CurrencyFormatter.formatNumber(item.sellOutEstCases.round())} كرتونة',
                                    style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 3),
                                  _mText(
                                    '${CurrencyFormatter.formatNumber(sellOutUnits)} وحدة • ${CurrencyFormatter.formatCompactEGP(item.sellOutValueEgp)}${item.retailerMarginPct != 0 ? " • هامش ${item.retailerMarginPct.toStringAsFixed(0)}%" : ""}',
                                    style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                       fontSize: M3FontSize.bodySmall,                                       color: M3StatusColors.of(context).accents.teal,                                       fontWeight: FontWeight.w700,                                     )), maxLines: 3),
                                ],
                              ),
                            ),
                            _fitCell(_skuCellMaxWidth, 
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _mText(
                                    '${CurrencyFormatter.formatNumber(stockCases.round())} كرتونة',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: colorScheme.primary,
                                    ), maxLines: 3),
                                  _mText(
                                    '${CurrencyFormatter.formatNumber(stockUnits)} وحدة • ${CurrencyFormatter.formatCompactEGP(stockVal)}',
                                    style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                       fontSize: M3FontSize.bodySmall,                                       fontWeight: FontWeight.w700,                                       color: colorScheme.onSurfaceVariant,                                     )), maxLines: 3),
                                ],
                              ),
                            ),
                            _fitCell(_skuCellMaxWidth, 
                              _mText(
                                '${item.daysOfInventory.toStringAsFixed(1)} يوم',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: isUrgent
                                      ? M3StatusColors.of(context).accents.negative
                                      : isOverstock
                                          ? M3StatusColors.of(context).accents.caution
                                          : M3StatusColors.of(context).accents.teal,
                                ), maxLines: 3),
                            ),
                            DataCell(
                              _stockStatusChip(
                                context,
                                item.stockStatusAr,
                                item.stockStatus,
                                key: const ValueKey('sellin_sku_status'),
                              ),
                            ),
                            _fitCell(_skuCellMaxWidth, 
                              item.suggestedPoCases > 0
                                  ? Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        _mText(
                                          '${item.suggestedPoCases} كرتونة',
                                          style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                             fontWeight: FontWeight.w900,                                             color: M3StatusColors.of(context).accents.alertStrong,                                             fontSize: M3FontSize.bodySmall,                                           )), maxLines: 3),
                                        _mText(
                                          '${CurrencyFormatter.formatCompactEGP(item.suggestedPoValueEgp)} • شامل الضريبة ${CurrencyFormatter.formatCompactEGP(poGrossInclVat)}',
                                          style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                             fontSize: M3FontSize.bodySmall,                                             fontWeight: FontWeight.w700,                                             color: M3StatusColors.of(context).accents.tealStrong,                                           )), maxLines: 3),
                                      ],
                                    )
                                  : _mText(
                                      'لا يحتاج إعادة طلب',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                      ), maxLines: 3),
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
                      borderRadius: M3Shape.radiusMd,
                      border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.4)),
                    ),
                    // Wraps on phones so the pager never overflows at 390dp.
                    child: Wrap(
                      key: const ValueKey('sellin_sku_pager'),
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: M3Spacing.sm,
                      runSpacing: M3Spacing.xs,
                      children: [
                        Text(
                          'عرض ${totalSkuCount == 0 ? 0 : startIdx + 1} - $endIdx من إجمالي $totalSkuCount صنف (25 صنف بالصفحة)',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Wrap(
                          spacing: M3Spacing.xs,
                          runSpacing: M3Spacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                        // Previous Page Button
                        OutlinedButton.icon(
                          icon: const Icon(Icons.arrow_forward_rounded, size: 18.0),
                          label: const Text('السابق'),
                          onPressed: clampedCurrentPage > 0
                              ? () => setState(() => _skuCurrentPage = clampedCurrentPage - 1)
                              : null,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHigh,
                            borderRadius: M3Shape.radiusSm,
                          ),
                          child: Text(
                            'صفحة ${totalSkuPages == 0 ? 0 : clampedCurrentPage + 1} من ${totalSkuPages == 0 ? 1 : totalSkuPages}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        // Next Page Button
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.arrow_back_rounded, size: 18.0),
                          label: const Text('التالي'),
                          onPressed: clampedCurrentPage < totalSkuPages - 1
                              ? () => setState(() => _skuCurrentPage = clampedCurrentPage + 1)
                              : null,
                        ),
                          ],
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
            borderRadius: M3Shape.radiusLg,
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
                      borderRadius: M3Shape.radiusMd,
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
                          'ملفات Sell-In المرفوعة',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          'ارفع ملف كل شهر (أو أكثر من شهر في ملف واحد)، ولن تُحذف الشهور السابقة. يمكنك استبدال أي ملف أو حذفه.',
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
                spacing: M3Spacing.sm,
                runSpacing: M3Spacing.xs,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: M3Spacing.sm,
                    runSpacing: M3Spacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      M3Dropdown<String>(
value: _archiveUploadChain,
fitOptions: true,
label: 'السلسلة',
hint: 'اختار السلسلة',
options: chainOptions(_chains),
onChanged: m3Legacy<String>((v) {
                            if (v != null) {
                              setState(() => _archiveUploadChain = v);
                            }
                          }),
),
                      M3Dropdown<int>(
value: _archiveUploadYear,
fitOptions: true,
label: 'السنة (اختياري)',
options: m3OptionsFromMenuItems<int>([
                            const DropdownMenuItem(
                              value: 0,
                              child: Text('من الملف تلقائيًا'),
                            ),
                            for (final y in AvailableYears.current.including(_archiveUploadYear))
                              DropdownMenuItem(value: y, child: Text('$y')),
                          ]),
onChanged: m3Legacy<int>((v) {
                            if (v != null) {
                              setState(() => _archiveUploadYear = v);
                            }
                          }),
),
                      M3Dropdown<int>(
value: _archiveUploadMonth,
fitOptions: true,
label: 'الشهر (اختياري)',
options: m3OptionsFromMenuItems<int>([
                            const DropdownMenuItem(
                              value: 0,
                              child: Text('من الملف تلقائيًا'),
                            ),
                            const DropdownMenuItem(value: 1, child: Text('يناير (01)')),
                            const DropdownMenuItem(value: 2, child: Text('فبراير (02)')),
                            const DropdownMenuItem(value: 3, child: Text('مارس (03)')),
                            const DropdownMenuItem(value: 4, child: Text('أبريل (04)')),
                            const DropdownMenuItem(value: 5, child: Text('مايو (05)')),
                            const DropdownMenuItem(value: 6, child: Text('يونيو (06)')),
                            const DropdownMenuItem(value: 7, child: Text('يوليو (07)')),
                            const DropdownMenuItem(value: 8, child: Text('أغسطس (08)')),
                            const DropdownMenuItem(value: 9, child: Text('سبتمبر (09)')),
                            const DropdownMenuItem(value: 10, child: Text('أكتوبر (10)')),
                            const DropdownMenuItem(value: 11, child: Text('نوفمبر (11)')),
                            const DropdownMenuItem(value: 12, child: Text('ديسمبر (12)')),
                          ]),
onChanged: m3Legacy<int>((v) {
                            if (v != null) {
                              setState(() => _archiveUploadMonth = v);
                            }
                          }),
),
                    ],
                  ),
                  Wrap(
                    spacing: M3Spacing.sm,
                    runSpacing: M3Spacing.xs,
                    children: [
                      TestSemantics.button(
                        identifier: TestIds.sellinUploadButton,
                        label: 'رفع ملف Sell-In',
                        onPressed: _isUploading ||
                                !isExplicitChain(_archiveUploadChain)
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
                        child: FilledButton.icon(
                          onPressed: _isUploading || !isExplicitChain(_archiveUploadChain)
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
                          label: const Text('رفع ملف Sell-In'),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isLoadingArchive ? null : () => _loadSellInArchive(forceRefresh: true),
                        icon: const Icon(Icons.refresh_rounded, size: 18.0),
                        label: const Text('تحديث'),
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
        TestSemantics(
          identifier: TestIds.uploadedFilesList,
          label: 'الملفات المرفوعة (${_archivedSellInFiles.length})',
          container: true,
          child: Container(
            key: const ValueKey('sellin_uploaded_files_section'),
            decoration: BoxDecoration(
              color: M3TableSurface.color(colorScheme),
              borderRadius: M3Shape.radiusLg,
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: _isLoadingArchive
                ? const Padding(
                    padding: EdgeInsets.all(48.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _archiveLoadFailed && _archivedSellInFiles.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: M3ErrorState(
                          key: const ValueKey('sell_in_archive_load_error'),
                          title: 'تعذّر تحميل الملفات المرفوعة',
                          message: 'الخادم مشغول أو الاتصال انقطع. حاول مرة أخرى بعد لحظات.',
                          onRetry: () => _loadSellInArchive(forceRefresh: true),
                        ),
                      )
                : _archivedSellInFiles.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(48.0),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder_off_rounded,
                                size: 48.0,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 12.0),
                              Text(
                                'لا توجد ملفات مرفوعة بعد.',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6.0),
                              Text(
                                'ارفع أول ملف لتبدأ.',
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
                        // File name and net revenue are the widest columns.
                        columnFlex: const [1.05, 0.95, 0.9, 0.95, 0.95, 1.15, 0.95, 0.95],
                        showSwipeHint: true,
                        // Actions pinned at the row end (same as Sell-Out) so
                        // they stay on screen at 1280dp without scrolling.
                        pinnedEnd: _buildArchiveActionsColumn(context),
                        child: DataTable(
                          key: const ValueKey('sellin_uploaded_files_table'),
                          columnSpacing: M3Spacing.sm,
                          horizontalMargin: M3Spacing.sm,
                          headingRowHeight: _archiveHeadingHeight,
                          dataRowMinHeight: _archiveRowHeight,
                          dataRowMaxHeight: _archiveRowHeight,
                          headingRowColor: WidgetStatePropertyAll(
                            colorScheme.surfaceContainerHigh.withOpacity(0.5),
                          ),
                          columns: [
                            const DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('الملف')),
                            const DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('السلسلة')),
                            const DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('الفترة')),
                            const DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('المعاملات'), numeric: true),
                            const DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('الكراتين'), numeric: true),
                            DataColumn(headingRowAlignment: MainAxisAlignment.center, label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 64.0), child: const Text('صافي Sell-In (ج.م)', maxLines: 2, softWrap: true, textAlign: TextAlign.center)), numeric: true),
                            const DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('الوزن (طن)'), numeric: true),
                            const DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('تاريخ الرفع')),
                          ],
                          rows: _archivedSellInFiles.map((file) {
                            final periodText = file.targetMonth.isNotEmpty &&
                                    file.targetMonth != 'auto'
                                ? '${file.targetMonth} / ${file.targetYear}'
                                : 'سنة ${file.targetYear}';

                            return DataRow(
                              cells: [
                                DataCell(
                                  TestSemantics(
                                    identifier: TestIds.fileRow(
                                      archiveId: file.id,
                                      fileName: file.fileName,
                                    ),
                                    label: file.fileName,
                                    container: true,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.description_rounded,
                                          color: M3StatusColors.of(context).accents.positive,
                                          size: 20.0,
                                        ),
                                        const SizedBox(width: 8.0),
                                        Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Tooltip(
                                              message: file.fileName,
                                              child: Text(
                                                sheetShortName(file.fileName),
                                                style: const TextStyle(fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                            Text(
                                              _formatFileSize(file.fileSizeBytes),
                                              style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                             fontSize: M3FontSize.bodySmall,                                             color: colorScheme.onSurfaceVariant,                                           )),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                DataCell(
                                  M3ChipSurface(
                                    key: const ValueKey('sellin_file_chain_chip'),
                                    color: colorScheme.surfaceContainerHigh,
                                    child: Text(
                                      file.retailChain.toUpperCase(),
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
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
                                    key: ValueKey('sellin_file_rows_${file.id}'),
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                DataCell(
                                  // Cases from the file (total_cases); never the row count.
                                  Text(
                                    CurrencyFormatter.formatNumber(file.totalCases.round()),
                                    key: ValueKey('sellin_file_cases_${file.id}'),
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
                                    file.totalWeightTons.toStringAsFixed(1),
                                    key: ValueKey('sellin_file_tons_${file.id}'),
                                  ),
                                ),
                                DataCell(
                                  Tooltip(
                                    message: AppDateFormat.tryFormat(file.uploadedAt),
                                    child: Text(
                                      AppDateFormat.tryFormat(file.uploadedAt, withTime: false),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.visible,
                                      style: M3TextVariants.cell.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  /// Signed whole count with the sign before the number in RTL (U+2212 for
  /// minus, wrapped in an LTR isolate), e.g. "+1,200" / "−300"; zero is unsigned.
  static String _signedCount(int n, {required bool positive}) {
    final body = CurrencyFormatter.formatNumber(n.abs());
    if (n == 0) return '\u2066$body\u2069';
    return '\u2066${positive ? '+' : '\u2212'}$body\u2069';
  }

  /// Reorder/stock status as the shared 8dp chip. Colours stay semantic:
  /// urgent = M3 error container, overstock = tertiary container, else neutral.
  Widget _stockStatusChip(BuildContext context, String label, String status,
      {Key? key, double? wrapWidth}) {
    final cs = Theme.of(context).colorScheme;
    final urgent = status.contains('urgent') || status.contains('stockout') || status.contains('negative');
    final over = status == 'overstock';
    final bg = urgent ? cs.errorContainer : over ? cs.tertiaryContainer : cs.surfaceContainerHigh;
    final fg = urgent ? cs.onErrorContainer : over ? cs.onTertiaryContainer : cs.onSurfaceVariant;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: fg);
    if (wrapWidth != null) {
      // The chip is a short label (1-2 words); the description sits under it
      // in smaller grey text (up to 3 centred lines). The full backend label
      // is in the tooltip.
      final t = MonthlyStatusText.resolve(status, label);
      final head = t.short;
      final detail = t.description;
      return Tooltip(
        message: label,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wrapWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              M3ChipSurface(
                key: key,
                color: bg,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: M3Spacing.xxs),
                  child: Text(
                    head,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: style,
                  ),
                ),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: M3Spacing.xxs),
                Text(
                  detail,
                  key: const ValueKey('sellin_monthly_status_detail'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return M3ChipSurface(
      key: key,
      color: bg,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }

  static const double _skuHeadingHeight = 56.0;
  static const double _skuRowHeight = 120.0;
  static const double _skuItemColWidth = 204.0;

  /// Pinned SKU column for the reorder table (same header/row heights).
  Widget _buildSkuPinnedColumn(BuildContext context, List<SKUBranchInventoryModel> items) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final divider = Divider.createBorderSide(context, width: 1.0);
    final sorted = _skuSortColumnIndex == 0;
    return SizedBox(
      key: const ValueKey('sellin_sku_pinned_column'),
      width: _skuItemColWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(end: BorderSide(color: cs.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: cs.surfaceContainerHigh.withOpacity(0.5),
              child: InkWell(
                onTap: () => _onSortSku(0, true),
                child: Container(
                  height: _skuHeadingHeight,
                  alignment: AlignmentDirectional.centerStart,
                  padding: const EdgeInsets.symmetric(horizontal: M3Spacing.sm),
                  child: Row(
                    children: [
                      Text('الصنف', style: theme.dataTableTheme.headingTextStyle ?? theme.textTheme.titleSmall),
                      if (sorted) ...[
                        const SizedBox(width: 4.0),
                        Icon(
                          _skuSortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          size: 18.0,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            for (final item in items)
              Container(
                height: _skuRowHeight,
                alignment: AlignmentDirectional.centerStart,
                padding: const EdgeInsets.symmetric(horizontal: M3Spacing.sm),
                decoration: BoxDecoration(border: Border(top: divider)),
                child: InkWell(
                  borderRadius: M3Shape.radiusSm,
                  onTap: () => _openProductIdCard(
                    itemCode: item.itemCode,
                    barcode: item.barcode,
                    skuName: item.skuName,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: item.skuName,
                        child: Text(
                          item.skuName,
                          key: const ValueKey('sellin_sku_name'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Tooltip(
                        message:
                            'كود: ${item.itemCode.isNotEmpty ? item.itemCode : "-"} • الباركود: ${item.barcode.isNotEmpty ? item.barcode : "-"} • ${item.unitsPerCarton > 0 ? item.unitsPerCarton : 12} وحدات/كرتونة',
                        child: Text(
                          'كود: ${item.itemCode.isNotEmpty ? item.itemCode : "-"} • الباركود: ${item.barcode.isNotEmpty ? item.barcode : "-"}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
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

  static const double _archiveHeadingHeight = 48.0;
  static const double _archiveRowHeight = 56.0;

  Widget _buildArchiveActionsColumn(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final divider = Divider.createBorderSide(context, width: 1.0);
    return IntrinsicWidth(
      key: const ValueKey('sellin_uploaded_files_actions_column'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(start: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: _archiveHeadingHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: M3Spacing.sm),
              color: colorScheme.surfaceContainerHigh.withOpacity(0.5),
              child: Text('الإجراءات', style: theme.dataTableTheme.headingTextStyle ?? theme.textTheme.titleSmall),
            ),
            for (final file in _archivedSellInFiles)
              Container(
                height: _archiveRowHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: M3Spacing.sm),
                decoration: BoxDecoration(border: Border(top: divider)),
                child: Builder(builder: (context) {
                  final isDeleting = _deletingFileId == file.id;
                  final isReplacing = _replacingFileId == file.id;
                  return ArchiveActionsGroup(
                                    archiveId: file.id,
                                    fileName: file.fileName,
                                    // Replacing a Sell-In archive deletes the old one: super_admin only
                                    // (the backend answers 403 for anyone else).
                                    showEdit: widget.apiClient.currentUser?.isSuperAdmin ?? false,
                                    isEditing: isReplacing,
                                    isDeleting: isDeleting,
                                    onEdit: (isDeleting || isReplacing || _isUploading)
                                        ? null
                                        : () => _pickAndUploadSellInFile(
                                              replaceArchiveId: file.id,
                                              forceChain: file.retailChain,
                                            ),
                                    onDownload: () => _handleDownloadSellInSheet(file),
                                    onDelete: (isDeleting || isReplacing)
                                        ? null
                                        : () => _confirmAndDeleteSellInSheet(file),
                                  );
                }),
              ),
          ],
        ),
      ),
    );
  }

  void _exportMissingCostItems(List<MissingCostItemModel> items) {
    final headers = <String>[
      'كود الصنف',
      'الباركود',
      'اسم الصنف',
      'السلاسل',
      'الوحدات المباعة',
      'قيمة المبيعات (ج.م)',
      'السبب',
      'كود قائمة الأصناف',
      'الاسم في قائمة الأصناف',
      'سعر الوحدة (مطلوب)',
      'وحدات/كرتونة (مطلوب)',
    ];
    final rows = items
        .map((i) => <dynamic>[
              i.itemCode,
              i.barcode,
              i.skuName,
              i.chains.join(' / '),
              i.unitsSold,
              i.salesValueEgp.toStringAsFixed(2),
              i.reasonAr,
              i.masterItemCode,
              i.masterName,
              '',
              '',
            ])
        .toList();
    final csvData = ExcelExportService.generateCsv(headers: headers, rows: rows);
    ExcelExportService.downloadCsv(
      'tashil_missing_cost_items_${DateTime.now().millisecondsSinceEpoch}.csv',
      csvData,
    );
    M3Feedback.showSuccess(context, 'تم تصدير ${items.length} صنف بلا تكلفة (CSV).');
  }

  /// Flagged list of Sell-Out items with no real factory cost. Their cost and
  /// margin show "—" and are excluded from the totals until Adeco sends prices.
  Widget _buildMissingCostSection(
    BuildContext context,
    ColorScheme colorScheme,
    CPFRDashboardModel d,
  ) {
    final status = M3StatusColors.of(context);
    final theme = Theme.of(context);
    final items = d.missingCostItems;
    final totalValue = items.fold<double>(0.0, (s, i) => s + i.salesValueEgp);
    final totalUnits = items.fold<int>(0, (s, i) => s + i.unitsSold);
    final hasItems = items.isNotEmpty;
    final fg = hasItems ? status.onWarningContainer : colorScheme.onSurfaceVariant;
    return Container(
      padding: M3Spacing.pSm,
      decoration: BoxDecoration(
        color: hasItems ? status.warningContainer : colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(
          color: hasItems ? status.warning : colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(hasItems ? AppIcons.warning : AppIcons.success, color: hasItems ? status.warning : status.success),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  hasItems
                      ? 'أصناف بلا تكلفة (${items.length}) — مطلوب أسعارها من المورد'
                      : 'كل الأصناف لها تكلفة',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: fg),
                ),
              ),
              if (hasItems)
                M3Button.tonal(
                  label: 'تصدير القائمة (CSV)',
                  icon: AppIcons.fileDownload,
                  onPressed: () => _exportMissingCostItems(items),
                ),
            ],
          ),
          const SizedBox(height: 6.0),
          Text(
            hasItems
                ? 'التكلفة والهامش غير متاحين لهذه الأصناف ومستبعدان من الإجماليات. مبيعاتها ${CurrencyFormatter.formatCompactEGP(totalValue)} (${CurrencyFormatter.formatNumber(totalUnits)} وحدة).'
                : 'التكلفة من ملف Sell-Out أو قائمة الأصناف فقط، بلا تقدير.',
            style: theme.textTheme.bodySmall?.copyWith(color: fg),
          ),
          if (hasItems) ...[
            const SizedBox(height: 10.0),
            TableScrollContainer(
              child: DataTable(
                headingRowHeight: 40.0,
                dataRowMinHeight: 40.0,
                dataRowMaxHeight: 56.0,
                columns: const [
                  DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('الصنف')),
                  DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('الكود / الباركود')),
                  DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('السلاسل')),
                  DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('الوحدات'), numeric: true),
                  DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('المبيعات'), numeric: true),
                  DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('التكلفة / الربح')),
                  DataColumn(headingRowAlignment: MainAxisAlignment.center, label: Text('السبب')),
                ],
                rows: items
                    .take(50)
                    .map((i) => DataRow(cells: [
                          DataCell(Text(i.skuName)),
                          DataCell(Text(
                            [i.itemCode, i.barcode].where((e) => e.isNotEmpty).join(' • '),
                            textDirection: TextDirection.ltr,
                          )),
                          DataCell(Text(i.chains.join('، '))),
                          DataCell(Text(CurrencyFormatter.formatNumber(i.unitsSold))),
                          DataCell(Text(CurrencyFormatter.formatEGP(i.salesValueEgp))),
                          const DataCell(Text('—')),
                          DataCell(Text(i.reasonAr)),
                        ]))
                    .toList(),
              ),
            ),
            if (items.length > 50)
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  'أعلى 50 صنفًا بالمبيعات • القائمة الكاملة في ملف التصدير',
                  style: theme.textTheme.bodySmall?.copyWith(color: fg),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildFourCardResponsiveLayout(
    double maxWidth,
    Widget card1,
    Widget card2,
    Widget card3,
    Widget card4, {
    String id = 'main',
  }) {
    // Same equal-height grid and gutters as the Sell-Out KPI row.
    final columns = M3KpiGridColumns.forWidth(maxWidth);
    return M3EqualHeightGrid(
      key: ValueKey('sellin_kpi_grid_$id'),
      columns: columns,
      spacing: M3Spacing.sm,
      runSpacing: M3Spacing.sm,
      children: [card1, card2, card3, card4],
    );
  }

  Widget _buildSummaryCard(
    BuildContext context, {
    required String titleAr,
    required String titleEn,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    String? titleTooltip,
    String? subtitleTooltip,
  }) {
    return M3SummaryKpiCard(
      key: ValueKey('kpi_card_$titleEn'),
      valueKey: ValueKey('kpi_value_$titleEn'),
      subtitleKey: ValueKey('kpi_subtitle_$titleEn'),
      loadingKey: const ValueKey('sell_in_kpi_skeleton'),
      title: titleAr,
      value: value,
      subtitle: subtitle,
      icon: icon,
      color: color,
      titleTooltip: titleTooltip,
      subtitleTooltip: subtitleTooltip,
      titleMaxLines: 1,
      subtitleMaxLines: 1,
      isLoading: _isLoading,
    );
  }
}


/// Margin / promo filter for Sell-In SKU rows. Margin filters only match rows
/// that have a real basis (sell-out units and a factory cost); no data is
/// inferred for rows without one.
bool matchesSellInMarginFilter(SKUBranchInventoryModel i, String filter) {
  final hasBasis = i.sellOutUnits > 0 && i.factoryCartonCost > 0 && !i.factoryCostMissing;
  switch (filter) {
    case 'healthy':
      return hasBasis && i.retailerMarginPct >= 10.0;
    case 'low_margin':
      return hasBasis && i.retailerMarginPct >= 0.0 && i.retailerMarginPct < 10.0;
    case 'negative_margin':
      return hasBasis && (i.retailerMarginPct < 0.0 || i.chainGrossMarginEgp < 0.0);
    case 'promo':
      return i.itemType == 'عرض';
    case 'all':
    default:
      return true;
  }
}


/// One code/barcode line: 16dp icon (semanticLabel) + 4dp gap + LTR tabular value.
/// No visible «الكود»/«الباركود» text labels. Hover reveals copy; tap copies.
class _HoverCopyCode extends StatefulWidget {
  const _HoverCopyCode({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  State<_HoverCopyCode> createState() => _HoverCopyCodeState();
}

class _HoverCopyCodeState extends State<_HoverCopyCode> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasValue = widget.value.isNotEmpty;
    final display = hasValue ? ltrIsolate(widget.value) : '—';
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
          fontFamily: 'monospace',
        );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: hasValue ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: hasValue
            ? () {
                Clipboard.setData(ClipboardData(text: widget.value));
                M3Feedback.showSuccess(context, 'تم نسخ ${widget.label}');
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16.0,
                color: cs.onSurfaceVariant,
                semanticLabel: widget.label,
              ),
              const SizedBox(width: 4.0),
              Flexible(
                child: Tooltip(
                  message: '${widget.label}: ${hasValue ? widget.value : "-"}',
                  child: Text(
                    display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ),
              if (hasValue && _hover) ...[
                const SizedBox(width: 4.0),
                Tooltip(
                  message: 'نسخ',
                  child: Icon(AppIcons.copy, size: 16.0, color: cs.primary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_palette.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/widgets/m3_states.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/network/api_client.dart';
import '../../data/product_master_repository.dart';
import '../../data/chain_discount_repository.dart';
import '../widgets/chain_discount_profiles_card.dart';
import '../widgets/pm_catalog_table.dart';
import '../../../../core/storage/session_storage.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/data/data_refresh_mixin.dart';
import '../../../../core/utils/arabic_plural.dart';
import '../../../../core/utils/bidi_text.dart';
import '../../../../core/utils/app_date_format.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_search_field.dart';
import '../../../../core/widgets/m3_table_surface.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';
import '../../../../core/widgets/m3_wrap_text.dart';

/// Adeco Canonical Product Master & Official Price List Screen (`كارتة الأصناف والأسعار`).
/// Provides:
/// 1. Full 389-SKU Catalog searchable by Item Code (`كود الصنف` e.g. FGCL-0550-0001 / FGSL),
///    Barcode (`الباركود`), Arabic SKU Name, Brand, Prefix, Packaging, and Item Type (`عادي` / `عرض`).
/// 2. Interactive Product ID Card Modal (`بطاقة تعريف الصنف`) with inline editing & persistence.
/// 3. Per-chain terms table (VAT, invoice discount, extra discount) that drives Sell-In.
/// 4. Product Master Excel Workbook Upload & Archive History (`الشيتات المرفوعة وتحديث الكارتة`).
class ProductMasterScreen extends StatefulWidget {
  final ApiClient apiClient;
  final String? initialSearchQuery;

  const ProductMasterScreen({
    super.key,
    required this.apiClient,
    this.initialSearchQuery,
    this.repository,
    this.chainRepository,
    this.persistTabInUrl = true,
  });

  /// Keep the selected tab in the `?tab=` URL query (off when embedded in a dialog).
  final bool persistTabInUrl;

  /// Optional injected chain-terms repository (tests).
  final ChainDiscountRepository? chainRepository;

  /// Optional injected repository (tests); defaults to one wrapping [apiClient].
  final ProductMasterRepository? repository;

  /// Opens the Canonical Product ID Card Modal (`بطاقة تعريف الصنف`) from any screen.
  static Future<ProductMasterItemModel?> showProductIdCardModal(
    BuildContext context, {
    required ApiClient apiClient,
    required ProductMasterItemModel item,
    ValueChanged<ProductMasterSummaryModel>? onUpdated,
  }) {
    return showDialog<ProductMasterItemModel>(
      context: context,
      builder: (ctx) => _ProductIdCardDialog(
        apiClient: apiClient,
        item: item,
        onUpdated: onUpdated,
      ),
    );
  }

  @override
  State<ProductMasterScreen> createState() => _ProductMasterScreenState();
}

class _ProductMasterScreenState extends State<ProductMasterScreen>
    with SingleTickerProviderStateMixin, DataRefreshMixin<ProductMasterScreen> {
  @override
  void onBackendDataChanged() {
    _loadData();
  }

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currFmt = NumberFormat('#,##0.00', 'en_US');
  final NumberFormat _intFmt = NumberFormat('#,###', 'en_US');

  bool _isLoading = true;
  late final ProductMasterRepository _repo =
      widget.repository ?? ProductMasterRepository(widget.apiClient);
  bool _isUploading = false;
  String? _errorMessage;

  ProductMasterSummaryModel? _summary;
  List<ArchivedExcelFileModel> _archivedMasterFiles = const [];

  String _selectedPrefix = 'all';
  String _selectedBrand = 'all';
  String _selectedItemType = 'all';
  String _selectedPackaging = 'all';
  String _selectedPullStatus = 'all';
  String _selectedPriceChange = 'all';
  int _currentPage = 0;
  static const int _pageSize = 50;

  // Per-chain terms (VAT, invoice discount, extra discount) stored by the backend; they drive Sell-In.
  late final ChainDiscountRepository _chainDiscRepo =
      widget.chainRepository ?? ChainDiscountRepository(widget.apiClient);
  List<ChainDiscountProfileModel> _chainProfiles = const [];
  bool _chainProfilesLoading = false;
  bool _chainProfilesSaving = false;
  String? _chainProfilesError;
  bool _chainProfilesErrorOnLoad = true;

  /// Set when a save could not be confirmed; the banner's retry re-sends exactly this list.
  List<ChainDiscountProfileModel>? _chainProfilesUnverified;

  /// User choices from the columns menu (true = show); others follow the width.
  final Map<PmCatalogColumn, bool> _columnOverrides = {};

  /// `?tab=` values, in tab order.
  static const List<String> tabSlugs = ['catalog', 'sheets', 'calculator'];
  static const String tabQueryParam = 'tab';

  @override
  void initState() {
    super.initState();
    final urlTab = widget.persistTabInUrl
        ? tabSlugs.indexOf(SessionStorage.browserQueryParam(tabQueryParam) ?? '')
        : -1;
    _tabController = TabController(
        length: 3, vsync: this, initialIndex: urlTab < 0 ? 0 : urlTab);
    _tabController.addListener(() {
      if (!mounted || _tabController.indexIsChanging) return;
      setState(() {});
      _writeTabToUrl();
    });
    if (urlTab > 0) {
      // AppShell re-asserts the page path after the first frame (dropping the query).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _writeTabToUrl();
      });
    }
    if (widget.initialSearchQuery != null &&
        widget.initialSearchQuery!.trim().isNotEmpty) {
      _searchController.text = widget.initialSearchQuery!.trim();
    }
    _loadData();
    _loadChainProfiles();
  }

  void _writeTabToUrl() {
    if (!widget.persistTabInUrl) return;
    final i = _tabController.index;
    SessionStorage.replaceBrowserQueryParam(
        tabQueryParam, i == 0 ? null : tabSlugs[i]);
  }

  Future<void> _loadChainProfiles() async {
    setState(() {
      _chainProfilesLoading = true;
      _chainProfilesError = null;
    });
    try {
      final list = await _chainDiscRepo.load();
      if (!mounted) return;
      setState(() => _chainProfiles = list);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chainProfilesError = friendlyChainDiscountError(e);
        _chainProfilesErrorOnLoad = true;
      });
    } finally {
      if (mounted) setState(() => _chainProfilesLoading = false);
    }
  }

  Future<void> _saveChainProfiles(List<ChainDiscountProfileModel> next) async {
    if (_chainProfilesSaving) return;
    setState(() {
      _chainProfilesSaving = true;
      _chainProfilesError = null;
      _chainProfilesUnverified = null;
    });
    try {
      final saved = await _chainDiscRepo.save(next);
      if (!mounted) return;
      setState(() => _chainProfiles = saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chainProfilesError = friendlyChainDiscountError(e);
        _chainProfilesErrorOnLoad = false;
        _chainProfilesUnverified =
            e is ChainDiscountSaveUnverifiedException ? next : null;
      });
    } finally {
      if (mounted) setState(() => _chainProfilesSaving = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final loaded = await _repo.loadSummary();
      final loadError = loaded.errorOrNull;
      if (loadError != null) throw loadError.cause ?? loadError;
      final summary = loaded.valueOrNull!;
      final archiveFiles = (await _repo.loadArchive()).valueOrNull ??
          const <ArchivedExcelFileModel>[];
      List<ArchivedExcelFileModel> pmArchives = archiveFiles
          .where((f) =>
              f.fileType == 'product_master' ||
              f.retailChain == 'product-master' ||
              f.fileName.toLowerCase().contains('product_master') ||
              f.fileName.contains('اسعار') ||
              f.fileName.contains('أصناف'))
          .toList();

      if (pmArchives.isEmpty &&
          summary.sourceFilename.isNotEmpty &&
          summary.totalSkus > 0) {
        pmArchives = [
          ArchivedExcelFileModel(
            id: 'pm_default_seed',
            tenantId: summary.tenantId,
            fileType: 'product_master',
            fileName: summary.sourceFilename,
            contentType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            fileSizeBytes: 51200,
            retailChain: 'product-master',
            chainNameAr: 'كارتة الأصناف والأسعار (Product Master)',
            chainNameEn: 'Product Master',
            targetYear: '2026',
            rowsIngested: summary.totalSkus,
            branchesCount: 0,
            totalRevenue: 0.0,
            uploadedAt: summary.sheetDateLabel,
          ),
        ];
      }

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _archivedMasterFiles = pmArchives;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  List<ProductMasterItemModel> get _filteredItems {
    final all = _summary?.items ?? const [];
    final q = _searchController.text.trim();
    return all.where((item) {
      if (_selectedPrefix != 'all') {
        if (_selectedPrefix.toUpperCase() == 'PR') {
          if (!item.itemCodePrefix.toUpperCase().startsWith('PR')) {
            return false;
          }
        } else if (item.itemCodePrefix.toUpperCase() !=
            _selectedPrefix.toUpperCase()) {
          return false;
        }
      }
      if (_selectedBrand != 'all' && item.brand != _selectedBrand) {
        return false;
      }
      if (_selectedItemType != 'all' && item.itemType != _selectedItemType) {
        return false;
      }
      if (_selectedPackaging != 'all' &&
          item.packagingType != _selectedPackaging) {
        return false;
      }
      if (_selectedPullStatus == 'active' && !item.isActiveInChains) {
        return false;
      }
      if (_selectedPullStatus == 'unpulled' && item.isActiveInChains) {
        return false;
      }
      if (_selectedPriceChange != 'all') {
        final dir = item.priceChangeDirection.toLowerCase();
        switch (_selectedPriceChange) {
          case 'changed':
            if (dir != 'up' && dir != 'down' && dir != 'new') return false;
            break;
          case 'up':
            if (dir != 'up') return false;
            break;
          case 'down':
            if (dir != 'down') return false;
            break;
          case 'new':
            if (dir != 'new') return false;
            break;
          case 'same':
            if (dir == 'up' || dir == 'down' || dir == 'new') return false;
            break;
        }
      }
      if (q.isNotEmpty) {
        return ApiClient.matchesProductSearch(
          q,
          itemCode: item.itemCode,
          barcode: item.barcode,
          skuName: item.officialName,
          brand: item.brand,
          category: item.category,
          packagingType: item.packagingType,
        );
      }
      return true;
    }).toList();
  }

  Future<void> _handleUploadMasterWorkbook() async {
    final picked = await WebFileHelper.pickFile(accept: '.xlsx,.xls,.csv');
    if (picked == null || !mounted) return;

    setState(() => _isUploading = true);
    try {
      final res = await widget.apiClient.uploadProductMasterFile(
        filename: picked.name,
        fileBytes: picked.bytes,
      );
      if (!mounted) return;
      setState(() {
        _summary = res.summary;
        _isUploading = false;
        _currentPage = 0;
      });
      _repo.invalidateAll();
      await _loadData();
      if (!mounted) return;
      final latestSummary = _summary ?? res.summary;
      await _showUploadDiffSummaryDialog(
        latestSummary,
        uploadedFilename: picked.name,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      M3Feedback.showError(context, 'تعذر رفع شيت كارتة الأصناف: $e');
    }
  }

  Future<void> _handleDeleteProductMasterSheet(
      ArchivedExcelFileModel file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          icon: Icon(
            Icons.delete_forever_rounded,
            color: Theme.of(ctx).colorScheme.error,
            size: 36,
          ),
          title: const Text(
            'حذف شيت الأسعار وإلغاء تأثيراته',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Text(
            'هل أنت متأكد من حذف الملف ${quotedLtr(file.fileName)}؟\nسيتم إزالة جميع تحديثات الأسعار والأصناف التي تمت من خلال هذا الشيت والرجوع تلقائياً إلى النسخة السابقة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('تأكيد الحذف واسترجاع الأسعار'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final hasOtherSameName = _archivedMasterFiles.any(
      (f) =>
          f.id != file.id &&
          f.fileName.toLowerCase() == file.fileName.toLowerCase(),
    );
    try {
      await widget.apiClient.deleteArchivedFile(
        file.id,
        fileName: hasOtherSameName ? null : file.fileName,
        isProductMaster: true,
      );
    } catch (e) {
      if (!mounted) return;
      final msg =
          e is ArchiveDeleteException ? e.message : 'تعذّر حذف ملف الماستر.';
      M3Feedback.showError(context, msg);
      await _loadData();
      return;
    }
    if (!mounted) return;
    setState(() {
      _archivedMasterFiles =
          _archivedMasterFiles.where((f) => f.id != file.id).toList();
    });
    _repo.invalidateAll();
    await _loadData();
    if (!mounted) return;
    M3Feedback.showSuccess(
      context,
      'تم حذف الشيت "${file.fileName}" وإلغاء تأثيراته واسترجاع الأسعار السابقة بنجاح.',
    );
  }

  Future<void> _showUploadDiffSummaryDialog(
    ProductMasterSummaryModel summary, {
    String? uploadedFilename,
  }) async {
    final diff = summary.diffSummary;
    final upCount = diff?.priceIncreasedCount ?? summary.priceIncreasedCount;
    final downCount = diff?.priceDecreasedCount ?? summary.priceDecreasedCount;
    final newCount = diff?.newSkusCount ?? summary.newSkusCount;
    final sameCount = diff?.priceUnchangedCount ?? summary.priceUnchangedCount;
    final fileName =
        uploadedFilename ?? diff?.newFileName ?? summary.sourceFilename;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            key: const ValueKey('product_master_diff_summary_dialog'),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: M3Palette.teal.withValues(alpha: 0.14),
                    borderRadius: M3Shape.radiusSm,
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: M3Palette.teal,
                    size: 22.0,
                  ),
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ملخص مقارنة الشيت الجديد (AI Price Diff Summary)',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: M3FontSize.bodyMediumLargePlus,
                        ),
                      ),
                      Text(
                        'تم فحص ومطابقة أسعار "$fileName" تلقائياً مع النسخة السابقة',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 10.0,
                    runSpacing: 10.0,
                    children: [
                      _buildDiffStatCard(
                        cs: cs,
                        icon: Icons.trending_up_rounded,
                        labelAr: 'أصناف زاد سعرها',
                        count: upCount,
                        color: M3Palette.danger,
                      ),
                      _buildDiffStatCard(
                        cs: cs,
                        icon: Icons.trending_down_rounded,
                        labelAr: 'أصناف انخفض سعرها',
                        count: downCount,
                        color: M3Palette.teal,
                      ),
                      _buildDiffStatCard(
                        cs: cs,
                        icon: Icons.fiber_new_rounded,
                        labelAr: 'أصناف جديدة مضافة',
                        count: newCount,
                        color: M3Palette.info,
                      ),
                      _buildDiffStatCard(
                        cs: cs,
                        icon: Icons.horizontal_rule_rounded,
                        labelAr: 'أصناف لم يتغير سعرها',
                        count: sameCount,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                  if (diff != null && diff.topChangedItems.isNotEmpty) ...[
                    const SizedBox(height: 16.0),
                    Text(
                      'أبرز التغيرات السعرية المكتشفة:',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 210),
                      child: SingleChildScrollView(
                        child: Column(
                          children: diff.topChangedItems.take(8).map((item) {
                            final isUp = item.direction == 'up';
                            final isDown = item.direction == 'down';
                            final badgeColor = isUp
                                ? M3Palette.danger
                                : isDown
                                    ? M3Palette.teal
                                    : M3Palette.info;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10.0,
                                  vertical: 8.0,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerLow,
                                  borderRadius: M3Shape.radiusSm,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isUp
                                          ? Icons.arrow_upward_rounded
                                          : isDown
                                              ? Icons.arrow_downward_rounded
                                              : Icons.fiber_new_rounded,
                                      size: 16,
                                      color: badgeColor,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Expanded(
                                      child: M3WrapText(
                                        '[${item.itemCode}] ${item.officialName}',
                                        maxLines: 3,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: M3FontSize.bodySmall,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8.0),
                                    if (item.direction == 'new')
                                      Text(
                                        'صنف جديد (${_currFmt.format(item.newUnitPriceIncl)} ج.م)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: M3FontSize.labelSmallPlus,
                                          color: badgeColor,
                                        ),
                                      )
                                    else
                                      Text(
                                        '${_currFmt.format(item.oldUnitPriceIncl)} ← ${_currFmt.format(item.newUnitPriceIncl)} ج.م (${CurrencyFormatter.formatSignedPct(item.diffPct)})',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: M3FontSize.labelSmallPlus,
                                          color: badgeColor,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إغلاق'),
              ),
              if (upCount + downCount + newCount > 0)
                FilledButton.icon(
                  key: const ValueKey('diff_dialog_filter_changed_btn'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    setState(() {
                      _selectedPriceChange = 'changed';
                      _currentPage = 0;
                      _tabController.animateTo(0);
                    });
                  },
                  icon: const Icon(Icons.filter_alt_rounded, size: 18),
                  label: const Text('عرض الأصناف المتغيرة فقط في الجدول'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiffStatCard({
    required ColorScheme cs,
    required IconData icon,
    required String labelAr,
    required int count,
    required Color color,
  }) {
    return Container(
      width: 125,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: M3Shape.radiusMd,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20.0),
          const SizedBox(height: 6.0),
          Text(
            _intFmt.format(count),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: M3FontSize.titleMediumPlus,
              color: color,
            ),
          ),
          Text(
            labelAr,
            style: TextStyle(
              fontSize: M3FontSize.labelSmall,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }


  void _exportFilteredCatalogToCsv() {
    final items = _filteredItems;
    final csv = ExcelExportService.generateCsv(
      headers: const [
        'م (Serial)',
        'كود الصنف (Item Code)',
        'الاسم الرسمي للصنف (Official Name)',
        'الباركود (Barcode)',
        'العلامة التجارية (Brand)',
        'الفئة (Category)',
        'التعبئة (Packaging)',
        'الشدة بالكرتونة (Units/Carton)',
        'سعر الوحدة ق.ض (Unit Excl VAT)',
        'ضريبة القيمة المضافة (VAT %)',
        'سعر الوحدة ش.ض (Unit Incl VAT)',
        'سعر الكرتونة ش.ض (Carton Incl VAT)',
        'خصم الفاتورة % (Invoice Discount %)',
        'صافي تكلفة الوحدة (Net Unit Cost)',
        'صافي تكلفة الكرتونة (Net Carton Cost)',
        'نوع الصنف (Item Type)',
      ],
      rows: items
          .map((e) => [
                e.serialNo.toString(),
                e.itemCode,
                e.officialName,
                e.barcode,
                e.brand,
                e.category,
                e.packagingType,
                e.unitsPerCarton.toString(),
                e.unitPriceExclVat.toStringAsFixed(2),
                '${(e.vatRate * 100).toStringAsFixed(0)}%',
                e.unitPriceInclVat.toStringAsFixed(2),
                e.cartonPriceInclVat.toStringAsFixed(2),
                '${e.invoiceDiscountPct.toStringAsFixed(1)}%',
                e.netUnitInvoiceCost.toStringAsFixed(2),
                e.netCartonInvoiceCost.toStringAsFixed(2),
                e.itemType,
              ])
          .toList(),
    );
    ExcelExportService.downloadCsv(
      'Adeco_Product_Master_${DateTime.now().millisecondsSinceEpoch}.csv',
      csv,
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_isLoading) {
      return const M3LoadingState();
    }

    if (_errorMessage != null && _summary == null) {
      // Keep page chrome (title + upload) visible; body uses shared M3 error state.
      // Backend hang root-cause is tracked in PR #86 / TDS-76 — this is UI only.
      return Scaffold(
        backgroundColor: cs.surface,
        body: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24.0, 20.0, 24.0, 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPageHeader(),
              const SizedBox(height: 16.0),
              M3ErrorBanner(
                title: 'تعذّر تحميل كارتة الأصناف والأسعار',
                message: 'حاول مرة أخرى بعد قليل، أو ارفع شيت أسعار محدّث.',
                technicalDetails: _errorMessage,
                onRetry: _loadData,
                retryLabel: 'إعادة المحاولة',
              ),
              Expanded(
                child: M3ErrorState(
                  key: const ValueKey('product_master_error_state'),
                  title: 'تعذّر تحميل كارتة الأصناف والأسعار',
                  message: 'تعذّر الاتصال بالخادم أو انتهت مهلة الطلب.',
                  onRetry: _loadData,
                  retryLabel: 'إعادة المحاولة',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final summary = _summary!;
    final filtered = _filteredItems;

    return Scaffold(
      backgroundColor: cs.surface,
      body: M3ToolbarButtonTheme(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                    24.0, 20.0, 24.0, 0.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPageHeader(),
                    const SizedBox(height: 16.0),
                    _buildTabBar(theme, cs, filtered.length),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildCatalogTab(theme, cs, summary, filtered),
              _buildUploadAndArchiveTab(theme, cs, summary),
              _buildCalculatorTab(theme, cs, summary),
            ],
          ),
        ),
      ),
    );
  }

  /// M3 primary tabs, fixed (not scrollable), 48dp, directly under the title.
  /// Order (RTL, first = rightmost): SKU card, uploaded sheets, order calculator.
  Widget _buildTabBar(ThemeData theme, ColorScheme cs, int catalogCount) {
    return TabBar(
      key: const ValueKey('product_master_tabs'),
      controller: _tabController,
      isScrollable: false,
      labelColor: cs.primary,
      unselectedLabelColor: cs.onSurfaceVariant,
      labelStyle: theme.textTheme.titleSmall,
      unselectedLabelStyle: theme.textTheme.titleSmall,
      indicatorColor: cs.primary,
      dividerColor: cs.outlineVariant,
      dividerHeight: 1.0,
      tabs: [
        Tab(
          key: const ValueKey('pm_tab_catalog'),
          height: 48.0,
          text: 'كارتة الأصناف ($catalogCount)',
        ),
        Tab(
          key: const ValueKey('pm_tab_sheets'),
          height: 48.0,
          text: 'الشيتات المرفوعة (${_archivedMasterFiles.length})',
        ),
        const Tab(
          key: ValueKey('pm_tab_calculator'),
          height: 48.0,
          text: 'حاسبة الطلبيات',
        ),
      ],
    );
  }

  /// Title only: page actions live in each tab's toolbar.
  Widget _buildPageHeader() {
    return const M3PageHeader(
      key: ValueKey('product_master_page_header'),
      titleEn: 'Product Master & Price List',
      subtitleAr: 'كارتة الأصناف والأسعار',
    );
  }

  Future<void> _openNewSkuCard(ProductMasterSummaryModel summary) async {
    final newItem = ProductMasterItemModel(
      serialNo: summary.totalSkus + 1,
      itemCode: 'FGCL-0550-0999',
      itemCodePrefix: 'FGCL',
      officialName: '',
      barcode: '6221133000000',
      category: 'الكلور والمطهرات (Chlorine & Disinfectants)',
      brand: 'كلوريل (Clorel)',
      packagingType: 'عبوة',
      unitsPerCarton: 12,
      unitPriceExclVat: 20.0,
      vatRate: 0.14,
      unitPriceInclVat: 22.80,
      cartonPriceExclVat: 240.0,
      cartonPriceInclVat: 273.60,
      invoiceDiscountPct: 10.0,
      extraDiscountPct: 0.0,
      netUnitInvoiceCost: 20.52,
      netCartonInvoiceCost: 246.24,
      itemType: 'عادي',
    );
    await ProductMasterScreen.showProductIdCardModal(
      context,
      apiClient: widget.apiClient,
      item: newItem,
      onUpdated: (updatedSummary) {
        _repo.prime(updatedSummary);
        if (mounted) {
          setState(() => _summary = updatedSummary);
        }
      },
    );
  }

  List<String> _buildEffectivePrefixChips(ProductMasterSummaryModel summary) {
    final raw = summary.availablePrefixes;
    final hasSubPr = raw.any(
        (p) => p.toUpperCase().startsWith('PR') && p.toUpperCase() != 'PR');
    final hasExactPr = raw.any((p) => p.toUpperCase() == 'PR');
    if (hasSubPr && !hasExactPr) {
      return [...raw, 'PR'];
    }
    return raw;
  }

  bool get _hasActiveFilters =>
      _selectedPrefix != 'all' ||
      _selectedBrand != 'all' ||
      _selectedItemType != 'all' ||
      _selectedPackaging != 'all' ||
      _selectedPullStatus != 'all' ||
      _selectedPriceChange != 'all' ||
      _searchController.text.isNotEmpty;

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _selectedPrefix = 'all';
      _selectedBrand = 'all';
      _selectedItemType = 'all';
      _selectedPackaging = 'all';
      _selectedPullStatus = 'all';
      _selectedPriceChange = 'all';
      _currentPage = 0;
    });
  }

  Future<void> _openItemCard(ProductMasterItemModel item) async {
    await ProductMasterScreen.showProductIdCardModal(
      context,
      apiClient: widget.apiClient,
      item: item,
      onUpdated: (updatedSummary) {
        _repo.prime(updatedSummary);
        if (mounted) setState(() => _summary = updatedSummary);
      },
    );
  }

  Widget _buildCatalogTab(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
    List<ProductMasterItemModel> filtered,
  ) {
    final pageCount = (filtered.length / _pageSize).ceil();
    final safePage =
        pageCount == 0 ? 0 : _currentPage.clamp(0, pageCount - 1);
    final startIdx = safePage * _pageSize;
    final endIdx = math.min(startIdx + _pageSize, filtered.length);
    final pageItems = filtered.isEmpty
        ? const <ProductMasterItemModel>[]
        : filtered.sublist(startIdx, endIdx);

    return LayoutBuilder(builder: (context, constraints) {
      final tableWidth = constraints.maxWidth - 48.0;
      final visible =
          PmCatalogTableStyle.visibleColumns(tableWidth, _columnOverrides);
      const radius = M3Shape.radiusLg;
      return CustomScrollView(
        key: const PageStorageKey('pm_catalog_scroll'),
        slivers: [
          SliverPadding(
            padding:
                const EdgeInsetsDirectional.fromSTEB(24.0, 16.0, 24.0, 32.0),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildCatalogToolbar(
                      theme, cs, summary, filtered, tableWidth, visible),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16.0)),
                DecoratedSliver(
                  key: const ValueKey('pm_catalog_tonal_surface'),
                  decoration: BoxDecoration(
                    color: M3TableSurface.color(cs),
                    borderRadius: radius,
                  ),
                  sliver: DecoratedSliver(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    sliver: SliverMainAxisGroup(
                      key: const ValueKey('pm_catalog_table'),
                      slivers: PmCatalogTable.slivers(
                        context: context,
                        tableWidth: tableWidth,
                        visible: visible,
                        pageItems: pageItems,
                        totalCount: filtered.length,
                        startIndex: startIdx,
                        page: safePage,
                        pageCount: pageCount,
                        defaultDiscountPct: summary.defaultDiscountPct,
                        onPageChanged: (p) => setState(() => _currentPage = p),
                        onOpenItem: _openItemCard,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  static const String _searchHint = 'بحث بالكود أو الباركود أو الاسم';

  /// One 40dp row: search (start) · filter chips · actions (end).
  Widget _buildCatalogToolbar(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
    List<ProductMasterItemModel> filtered,
    double tableWidth,
    List<PmCatalogColumn> visible,
  ) {
    final chips = _buildFilterChips(summary);
    return SizedBox(
      key: const ValueKey('pm_catalog_toolbar'),
      height: 40.0,
      child: Row(
        children: [
          M3SearchFieldWidth(
            hintText: _searchHint,
            width: 240.0,
            chrome: 48.0 + 16.0 + 16.0,
            child: TextField(
              key: const ValueKey('product_master_search_input'),
              controller: _searchController,
              onChanged: (_) => setState(() => _currentPage = 0),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                constraints: const BoxConstraints.tightFor(height: 40.0),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                prefixIcon: const Icon(Icons.search_rounded, size: 20.0),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18.0),
                        tooltip: 'مسح البحث',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _currentPage = 0);
                        },
                      )
                    : null,
                hintText: _searchHint,
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: const OutlineInputBorder(
                  borderRadius: M3Shape.radiusFull,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('pm_catalog_filter_chips'),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8.0),
                    chips[i],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          _buildColumnsMenu(tableWidth, visible),
          const SizedBox(width: 8.0),
          IconButton(
            key: const ValueKey('product_master_export_csv_btn'),
            icon: const Icon(Icons.download_rounded),
            tooltip: 'تصدير CSV',
            onPressed: filtered.isEmpty ? null : _exportFilteredCatalogToCsv,
          ),
          const SizedBox(width: 8.0),
          _buildCatalogOverflowMenu(summary),
          const SizedBox(width: 8.0),
          FilledButton.icon(
            key: const ValueKey('product_master_add_sku_btn'),
            onPressed: () => _openNewSkuCard(summary),
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة صنف'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFilterChips(ProductMasterSummaryModel summary) {
    final allItems = summary.items;
    final upCount = summary.priceIncreasedCount > 0
        ? summary.priceIncreasedCount
        : allItems.where((e) => e.priceChangeDirection == 'up').length;
    final downCount = summary.priceDecreasedCount > 0
        ? summary.priceDecreasedCount
        : allItems.where((e) => e.priceChangeDirection == 'down').length;
    final newCount = summary.newSkusCount > 0
        ? summary.newSkusCount
        : allItems.where((e) => e.priceChangeDirection == 'new').length;
    final changedCount = upCount + downCount + newCount;

    return [
      _PmFilterMenuChip(
        key: const ValueKey('pm_filter_price_change'),
        label: 'تغير السعر',
        value: _selectedPriceChange,
        selectedLabel: const {
          'changed': 'تغير',
          'up': 'زاد ↑',
          'down': 'انخفض ↓',
          'new': 'جديد',
        }[_selectedPriceChange],
        itemKeyPrefix: 'price_filter',
        options: {
          'all': 'الكل (${summary.totalSkus})',
          'changed': 'تغير السعر ($changedCount)',
          'up': 'زاد ↑ ($upCount)',
          'down': 'انخفض ↓ ($downCount)',
          'new': 'جديد ($newCount)',
        },
        onSelected: (v) => setState(() {
          _selectedPriceChange = v;
          _currentPage = 0;
        }),
      ),
      _PmFilterMenuChip(
        key: const ValueKey('pm_filter_brand'),
        label: 'العلامة',
        value: _selectedBrand,
        itemKeyPrefix: 'pm_filter_brand',
        options: {
          'all': 'كل العلامات (${summary.availableBrands.length})',
          for (final b in summary.availableBrands) b: b,
        },
        onSelected: (v) => setState(() {
          _selectedBrand = v;
          _currentPage = 0;
        }),
      ),
      _PmFilterMenuChip(
        key: const ValueKey('pm_filter_item_type'),
        label: 'النوع',
        value: _selectedItemType,
        itemKeyPrefix: 'pm_filter_item_type',
        options: {
          'all': 'الكل (عادي + عرض)',
          'عادي': 'عادي (${summary.regularSkusCount})',
          'عرض': 'عرض ترويجي (${summary.promoSkusCount})',
        },
        onSelected: (v) => setState(() {
          _selectedItemType = v;
          _currentPage = 0;
        }),
      ),
      _PmFilterMenuChip(
        key: const ValueKey('pm_filter_pull_status'),
        label: 'السحب',
        value: _selectedPullStatus,
        selectedLabel: const {
          'active': 'مسحوب',
          'unpulled': 'غير مسحوب',
        }[_selectedPullStatus],
        itemKeyPrefix: 'pm_filter_pull_status',
        options: {
          'all': 'الكل (${summary.totalSkus})',
          'active': 'مسحوب ونشط بالسلاسل (${summary.activeInChainsCount})',
          'unpulled': 'غير مسحوب - فرصة توزيع (${summary.unpulledSkusCount})',
        },
        onSelected: (v) => setState(() {
          _selectedPullStatus = v;
          _currentPage = 0;
        }),
      ),
      _PmFilterMenuChip(
        key: const ValueKey('pm_filter_prefix'),
        label: 'البادئة',
        value: _selectedPrefix,
        itemKeyPrefix: 'pm_filter_prefix',
        options: {
          'all': 'الكل',
          for (final pfx in _buildEffectivePrefixChips(summary))
            pfx: '$pfx (${_prefixDescriptionAr(pfx)})',
        },
        onSelected: (v) => setState(() {
          _selectedPrefix = v;
          _currentPage = 0;
        }),
      ),
      _PmFilterMenuChip(
        key: const ValueKey('pm_filter_packaging'),
        label: 'التعبئة',
        value: _selectedPackaging,
        itemKeyPrefix: 'pm_filter_packaging',
        options: {
          'all': 'كل أنواع التعبئة',
          for (final p in summary.availablePackaging) p: p,
        },
        onSelected: (v) => setState(() {
          _selectedPackaging = v;
          _currentPage = 0;
        }),
      ),
    ];
  }

  /// Column visibility: columns that don't fit are hidden instead of cut off.
  Widget _buildColumnsMenu(double tableWidth, List<PmCatalogColumn> visible) {
    return MenuAnchor(
      menuChildren: [
        for (final c in PmCatalogTableStyle.columns.where((c) => c.hideable))
          CheckboxMenuButton(
            key: ValueKey('pm_column_toggle_${c.id.name}'),
            value: visible.contains(c.id),
            closeOnActivate: false,
            onChanged: (v) =>
                setState(() => _columnOverrides[c.id] = v ?? false),
            child: Text(c.label),
          ),
        const Divider(height: 1.0),
        MenuItemButton(
          key: const ValueKey('pm_column_reset'),
          onPressed: _columnOverrides.isEmpty
              ? null
              : () => setState(_columnOverrides.clear),
          child: const Text('الأعمدة الافتراضية'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        key: const ValueKey('pm_columns_menu_btn'),
        icon: const Icon(Icons.view_column_rounded),
        tooltip: 'الأعمدة',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  Widget _buildCatalogOverflowMenu(ProductMasterSummaryModel summary) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('product_master_reset_filters_btn'),
          leadingIcon: const Icon(Icons.filter_alt_off_rounded),
          onPressed: _hasActiveFilters ? _resetFilters : null,
          child: const Text('إعادة ضبط الفلاتر'),
        ),
        if (summary.diffSummary != null)
          MenuItemButton(
            key: const ValueKey('product_master_open_diff_summary_btn'),
            leadingIcon: const Icon(Icons.summarize_rounded),
            onPressed: () => _showUploadDiffSummaryDialog(
              summary,
              uploadedFilename: summary.sourceFilename,
            ),
            child: const Text('تقرير مقارنة الشيت الجديد'),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        key: const ValueKey('pm_catalog_more_btn'),
        icon: const Icon(Icons.more_vert_rounded),
        tooltip: 'المزيد',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  String _prefixDescriptionAr(String prefix) {
    final p = prefix.toUpperCase();
    switch (p) {
      case 'FGCL':
        return 'كلور ومبيضات';
      case 'FGDG':
        return 'سائل أطباق فيبا';
      case 'FGDW':
        return 'غسالات أطباق أوتوماتيك';
      case 'FGLC':
        return 'العناية بالملابس والمنسوجات';
      case 'FGGC':
        return 'منظف وملمع زجاج';
      case 'FGHC':
        return 'عناية منزلية ومطهرات';
      case 'FGPC':
        return 'عناية شخصية وصابون';
      default:
        if (p.startsWith('PR')) {
          return 'عروض ترويجية';
        }
        return 'أصناف أدكو';
    }
  }

  /// «حاسبة الطلبيات»: per-chain VAT / invoice / extra discount settings.
  /// They are the single source of truth for that chain's Sell-In everywhere.
  Widget _buildCalculatorTab(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
  ) {
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(24.0, 16.0, 24.0, 32.0),
      children: [
        ChainDiscountProfilesCard(
          profiles: _chainProfiles,
          loading: _chainProfilesLoading,
          saving: _chainProfilesSaving,
          error: _chainProfilesError,
          errorTitle: _chainProfilesErrorOnLoad
              ? 'تعذّر تحميل إعدادات السلاسل'
              : (_chainProfilesUnverified != null
                  ? kChainDiscountSaveUnverifiedTitle
                  : 'تعذّر حفظ إعدادات السلاسل'),
          onRetry: _chainProfilesErrorOnLoad
              ? _loadChainProfiles
              : (_chainProfilesUnverified == null
                  ? null
                  : () => _saveChainProfiles(_chainProfilesUnverified!)),
          canEdit:
              widget.apiClient.currentUser?.canEditChainTerms ?? true,
          onSave: _saveChainProfiles,
          loadKnownChains: _chainDiscRepo.loadKnownChains,
        ),
      ],
    );
  }

  Widget _buildUploadAndArchiveTab(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
  ) {
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(24.0, 16.0, 24.0, 32.0),
      children: [
        SizedBox(
          key: const ValueKey('pm_sheets_toolbar'),
          height: 40.0,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'أرشيف شيتات كارتة الأصناف والأسعار (${_archivedMasterFiles.length})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8.0),
              FilledButton.icon(
                key: const ValueKey('product_master_upload_btn'),
                onPressed: _isUploading ? null : _handleUploadMasterWorkbook,
                icon: _isUploading
                    ? const SizedBox.square(
                        dimension: 18.0,
                        child: CircularProgressIndicator(strokeWidth: 2.0),
                      )
                    : const Icon(Icons.upload_file_rounded),
                label: Text(
                    _isUploading ? 'جاري تحديث الكارتة...' : 'رفع شيت أسعار'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8.0),
        Text(
          'ارفع شيت Excel (.xlsx / .csv): يقرأ النظام أكواد الأصناف والباركودات وسعة الكرتونة والأسعار ويحدّث كل الشاشات فوراً. حذف شيت يلغي تحديثاته ويسترجع الأسعار السابقة.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16.0),
        if (_archivedMasterFiles.isEmpty)
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: M3Shape.radiusMd,
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: cs.primary),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Text(
                    'النسخة المعتمدة الحالية: ${summary.sourceFilename} (${summary.sheetDateLabel}) • إجمالي ${summary.totalSkus} صنف مفعل بالنظام.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ..._archivedMasterFiles.map(
            (file) => Card(
              margin: const EdgeInsets.only(bottom: 10.0),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Icon(Icons.table_view_rounded, color: cs.primary),
                ),
                title: M3WrapText(
                  file.fileName,
                  maxLines: 3,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: M3WrapText(
                  '${countSku(file.rowsIngested)} • تاريخ الرفع: ${AppDateFormat.tryFormat(file.uploadedAt)}',
                  maxLines: 2,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(file.fileSizeBytes / 1024).toStringAsFixed(1)} KB',
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(width: 8.0),
                    IconButton(
                      key: ValueKey('archive_tab_delete_sheet_${file.id}'),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: M3Palette.danger,
                      ),
                      tooltip: 'حذف الشيت والتراجع عن تحديثاته',
                      onPressed: () => _handleDeleteProductMasterSheet(file),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProductIdCardDialog extends StatefulWidget {
  final ApiClient apiClient;
  final ProductMasterItemModel item;
  final ValueChanged<ProductMasterSummaryModel>? onUpdated;

  const _ProductIdCardDialog({
    required this.apiClient,
    required this.item,
    this.onUpdated,
  });

  @override
  State<_ProductIdCardDialog> createState() => _ProductIdCardDialogState();
}

class _ProductIdCardDialogState extends State<_ProductIdCardDialog> {
  late final TextEditingController _itemCodeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _packagingCtrl;
  late final TextEditingController _unitsPerCartonCtrl;
  late final TextEditingController _unitPriceInclVatCtrl;
  late final TextEditingController _discountPctCtrl;
  late String _itemType;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _itemCodeCtrl = TextEditingController(text: i.itemCode);
    _nameCtrl = TextEditingController(text: i.officialName);
    _barcodeCtrl = TextEditingController(text: i.barcode);
    _brandCtrl = TextEditingController(text: i.brand);
    _categoryCtrl = TextEditingController(text: i.category);
    _packagingCtrl = TextEditingController(text: i.packagingType);
    _unitsPerCartonCtrl =
        TextEditingController(text: i.unitsPerCarton.toString());
    _unitPriceInclVatCtrl =
        TextEditingController(text: i.unitPriceInclVat.toStringAsFixed(2));
    _discountPctCtrl =
        TextEditingController(text: i.invoiceDiscountPct.toStringAsFixed(1));
    _itemType = i.itemType == 'عرض' ? 'عرض' : 'عادي';
  }

  @override
  void dispose() {
    _itemCodeCtrl.dispose();
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _brandCtrl.dispose();
    _categoryCtrl.dispose();
    _packagingCtrl.dispose();
    _unitsPerCartonCtrl.dispose();
    _unitPriceInclVatCtrl.dispose();
    _discountPctCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final code = _itemCodeCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    final barcode = _barcodeCtrl.text.trim();
    if (code.isEmpty || name.isEmpty) return;

    final units = int.tryParse(_unitsPerCartonCtrl.text.trim()) ?? 12;
    final unitIncl = double.tryParse(_unitPriceInclVatCtrl.text.trim()) ?? 0.0;
    final discPct = double.tryParse(_discountPctCtrl.text.trim()) ?? 10.0;
    final vatRate = widget.item.vatRate > 0 ? widget.item.vatRate : 0.14;
    final unitExcl = unitIncl / (1.0 + vatRate);
    final cartonIncl = unitIncl * units;
    final cartonExcl = unitExcl * units;
    final netUnit = unitIncl * (1.0 - (discPct / 100.0));
    final netCarton = cartonIncl * (1.0 - (discPct / 100.0));

    final updatedItem = widget.item.copyWith(
      itemCode: code,
      itemCodePrefix: code.contains('-') ? code.split('-').first : code,
      officialName: name,
      barcode: barcode,
      brand: _brandCtrl.text.trim(),
      category: _categoryCtrl.text.trim(),
      packagingType: _packagingCtrl.text.trim(),
      unitsPerCarton: units,
      unitPriceExclVat: double.parse(unitExcl.toStringAsFixed(2)),
      unitPriceInclVat: double.parse(unitIncl.toStringAsFixed(2)),
      cartonPriceExclVat: double.parse(cartonExcl.toStringAsFixed(2)),
      cartonPriceInclVat: double.parse(cartonIncl.toStringAsFixed(2)),
      invoiceDiscountPct: discPct,
      netUnitInvoiceCost: double.parse(netUnit.toStringAsFixed(2)),
      netCartonInvoiceCost: double.parse(netCarton.toStringAsFixed(2)),
      itemType: _itemType,
    );

    setState(() => _isSaving = true);
    try {
      final summary =
          await widget.apiClient.updateProductMasterItem(updatedItem);
      widget.onUpdated?.call(summary);
      if (!mounted) return;
      Navigator.of(context).pop(updatedItem);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      M3Feedback.showError(context, 'تعذر حفظ تعديلات الصنف: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final i = widget.item;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.badge_rounded, color: cs.primary),
            const SizedBox(width: 10.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'بطاقة تعريف الصنف الرسمية',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: M3FontSize.bodyLarge),
                  ),
                  Text(
                    'كود الصنف: ${ltrIsolate(i.itemCode)} • الباركود: ${ltrIsolate(i.barcode)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Official Factory Pricing & Chain Pull Status Summary Card
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: M3Shape.radiusMd,
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12.0,
                        runSpacing: 6.0,
                        children: [
                          Text(
                            'القسم: ${i.departmentAr.isNotEmpty ? i.departmentAr : i.itemCodePrefix}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.primary,
                            ),
                          ),
                          Text(
                            '• صافي تكلفة الوحدة: ${i.netUnitInvoiceCost.toStringAsFixed(2)} ج.م',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: M3Palette.teal,
                            ),
                          ),
                          Text(
                            '• صافي تكلفة الكرتونة: ${i.netCartonInvoiceCost.toStringAsFixed(2)} ج.م',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            i.isActiveInChains
                                ? '• حالة السحب: نشط بالسلاسل (${i.totalPosUnitsSold} وحدة / ${i.totalPosCartonsSold.toStringAsFixed(1)} كرتونة)'
                                : '• حالة السحب: غير مسحوب بالسلاسل (فرصة توزيع)',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: i.isActiveInChains
                                  ? M3Palette.info
                                  : M3Palette.warning,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14.0),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _itemCodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'كود الصنف',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: TextField(
                        controller: _barcodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الباركود',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12.0),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الرسمي للصنف',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12.0),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _brandCtrl,
                        decoration: const InputDecoration(
                          labelText: 'العلامة التجارية',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: TextField(
                        controller: _packagingCtrl,
                        decoration: const InputDecoration(
                          labelText: 'نوع التعبئة',
                          border: OutlineInputBorder(),
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
                        controller: _unitsPerCartonCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'الوحدات / كرتونة',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: TextField(
                        controller: _unitPriceInclVatCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'سعر الوحدة شامل الضريبة',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: TextField(
                        controller: _discountPctCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'خصم الفاتورة %',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12.0),
                M3Dropdown<String>(
                  value: _itemType,
                  label: 'نوع الصنف',
                  options: m3OptionsFromMenuItems<String>([
                    const DropdownMenuItem(
                      value: 'عادي',
                      child: Text('عادي (Regular SKU)'),
                    ),
                    const DropdownMenuItem(
                      value: 'عرض',
                      child: Text('عرض ترويجي (Promotional Bundle)'),
                    ),
                  ]),
                  onChanged: m3Legacy<String>((v) {
                    if (v != null) setState(() => _itemType = v);
                  }),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
          FilledButton.icon(
            onPressed: _isSaving ? null : _saveChanges,
            icon: const Icon(Icons.save_rounded, size: 18),
            label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ وتحديث الكارتة'),
          ),
        ],
      ),
    );
  }
}

/// M3 filter chip (8dp corners) that opens a menu of [options]. Selected
/// (tonal) whenever [value] is not `all`.
class _PmFilterMenuChip extends StatelessWidget {
  const _PmFilterMenuChip({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    required this.itemKeyPrefix,
    this.selectedLabel,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onSelected;
  final String itemKeyPrefix;

  /// Short text shown after «label:» when filtered (defaults to [value]).
  final String? selectedLabel;

  @override
  Widget build(BuildContext context) {
    final active = value != 'all' && options.containsKey(value);
    return MenuAnchor(
      menuChildren: [
        for (final e in options.entries)
          MenuItemButton(
            key: ValueKey('${itemKeyPrefix}_${e.key}'),
            leadingIcon: Icon(
              Icons.check_rounded,
              color: e.key == value ? null : Colors.transparent,
            ),
            onPressed: () => onSelected(e.key),
            child: Text(e.value),
          ),
      ],
      builder: (context, controller, _) => FilterChip(
        selected: active,
        showCheckmark: false,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(borderRadius: M3ChipStyle.radius),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160.0),
              child: Text(
                active ? '$label: ${selectedLabel ?? value}' : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4.0),
            const Icon(Icons.arrow_drop_down_rounded, size: 18.0),
          ],
        ),
        onSelected: (_) =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

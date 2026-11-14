import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_palette.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/widgets/m3_states.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/network/api_client.dart';
import '../../data/product_master_repository.dart';
import '../../data/chain_discount_repository.dart';
import '../widgets/chain_discount_profiles_card.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/data/data_refresh_mixin.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/arabic_plural.dart';
import '../../../../core/utils/bidi_text.dart';
import '../../../../core/utils/app_date_format.dart';
import '../../../../core/widgets/hyphenated_code_text.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_responsive_tab_bar.dart';
import '../../../../core/widgets/m3_search_field.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';
import '../../../../core/widgets/m3_wrap_text.dart';
import '../../../../core/widgets/table_scroll_container.dart';

/// Adeco Canonical Product Master & Official Price List Screen (`كارتة الأصناف والأسعار`).
/// Provides:
/// 1. Full 389-SKU Catalog searchable by Item Code (`كود الصنف` e.g. FGCL-0550-0001 / FGSL),
///    Barcode (`الباركود`), Arabic SKU Name, Brand, Prefix, Packaging, and Item Type (`عادي` / `عرض`).
/// 2. Interactive Product ID Card Modal (`بطاقة تعريف الصنف`) with inline editing & persistence.
/// 3. Interactive Carton/Unit Order, VAT (14%), Discount & Retailer Margin Calculator.
/// 4. Product Master Excel Workbook Upload & Archive History (`الشيتات المرفوعة وتحديث الكارتة`).
class ProductMasterScreen extends StatefulWidget {
  final ApiClient apiClient;
  final String? initialSearchQuery;

  const ProductMasterScreen({
    super.key,
    required this.apiClient,
    this.initialSearchQuery,
    this.repository,
  });

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

  // Calculator state
  ProductMasterItemModel? _calcSelectedSku;
  final TextEditingController _calcCartonsCtrl =
      TextEditingController(text: '10');
  final TextEditingController _calcInvoiceDiscCtrl =
      TextEditingController(text: '10.0');
  final TextEditingController _calcExtraDiscCtrl =
      TextEditingController(text: '0.0');
  final TextEditingController _calcRetailPriceCtrl =
      TextEditingController(text: '0.0');

  // Per-chain discount profiles (Firestore via backend). '' = no chain (defaults 10% / 0%).
  late final ChainDiscountRepository _chainDiscRepo =
      ChainDiscountRepository(widget.apiClient);
  List<ChainDiscountProfileModel> _chainProfiles = const [];
  bool _chainProfilesLoading = false;
  bool _chainProfilesSaving = false;
  String? _chainProfilesError;
  String _calcChain = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted && !_tabController.indexIsChanging) setState(() {});
    });
    if (widget.initialSearchQuery != null &&
        widget.initialSearchQuery!.trim().isNotEmpty) {
      _searchController.text = widget.initialSearchQuery!.trim();
    }
    _loadData();
    _loadChainProfiles();
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
      setState(() => _chainProfilesError = e.toString());
    } finally {
      if (mounted) setState(() => _chainProfilesLoading = false);
    }
  }

  Future<void> _saveChainProfiles(List<ChainDiscountProfileModel> next) async {
    setState(() {
      _chainProfilesSaving = true;
      _chainProfilesError = null;
    });
    try {
      final saved = await _chainDiscRepo.save(next);
      if (!mounted) return;
      setState(() {
        _chainProfiles = saved;
        if (_calcChain.isNotEmpty &&
            !saved.any((p) =>
                ChainDiscountProfileModel.key(p.chain) ==
                ChainDiscountProfileModel.key(_calcChain))) {
          _calcChain = '';
        }
        _applyCalcChainDiscounts();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _chainProfilesError = e.toString());
    } finally {
      if (mounted) setState(() => _chainProfilesSaving = false);
    }
  }

  /// Prefills the calculator's two discount fields from the selected chain (or the 10% / 0% defaults).
  void _applyCalcChainDiscounts() {
    if (_calcChain.isEmpty) {
      if (_calcSelectedSku == null) {
        _calcInvoiceDiscCtrl.text =
            kDefaultInvoiceDiscountPct.toStringAsFixed(1);
        _calcExtraDiscCtrl.text =
            kDefaultAdditionalDiscountPct.toStringAsFixed(1);
      } else {
        _calcInvoiceDiscCtrl.text =
            _calcSelectedSku!.invoiceDiscountPct.toStringAsFixed(1);
        _calcExtraDiscCtrl.text =
            _calcSelectedSku!.extraDiscountPct.toStringAsFixed(1);
      }
      return;
    }
    for (final p in _chainProfiles) {
      if (ChainDiscountProfileModel.key(p.chain) ==
          ChainDiscountProfileModel.key(_calcChain)) {
        _calcInvoiceDiscCtrl.text = p.invoiceDiscountPct.toStringAsFixed(1);
        _calcExtraDiscCtrl.text = p.additionalDiscountPct.toStringAsFixed(1);
        return;
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _calcCartonsCtrl.dispose();
    _calcInvoiceDiscCtrl.dispose();
    _calcExtraDiscCtrl.dispose();
    _calcRetailPriceCtrl.dispose();
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
        if (_calcSelectedSku == null && summary.items.isNotEmpty) {
          _selectCalculatorSku(summary.items.first);
        }
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

  void _selectCalculatorSku(ProductMasterItemModel sku) {
    _calcSelectedSku = sku;
    _calcInvoiceDiscCtrl.text = sku.invoiceDiscountPct.toStringAsFixed(1);
    _calcExtraDiscCtrl.text = sku.extraDiscountPct.toStringAsFixed(1);
    if (_calcChain.isNotEmpty) _applyCalcChainDiscounts();
    final suggestedShelf =
        sku.unitPriceInclVat > 0 ? (sku.unitPriceInclVat * 1.12) : 25.0;
    _calcRetailPriceCtrl.text = suggestedShelf.toStringAsFixed(2);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('تعذر رفع شيت كارتة الأصناف: $e'),
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text(msg)),
      );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: M3Palette.teal,
        content: Text(
          'تم حذف الشيت "${file.fileName}" وإلغاء تأثيراته واسترجاع الأسعار السابقة بنجاح.',
        ),
      ),
    );
  }

  Future<void> _showFileSheetsModal() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final theme = Theme.of(ctx);
            final cs = theme.colorScheme;
            final files = _archivedMasterFiles;
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                titlePadding:
                    const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 8),
                contentPadding:
                    const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 16),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: M3Shape.radiusSm,
                      ),
                      child: Icon(
                        Icons.folder_copy_rounded,
                        color: cs.primary,
                        size: 22.0,
                      ),
                    ),
                    const SizedBox(width: 10.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'شيتات الأسعار المرفوعة (File Sheets)',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: M3FontSize.bodyLarge,
                            ),
                          ),
                          Text(
                            'سجل ملفات الإكسيل المرفوعة بالتاريخ مع إمكانية حذف أي شيت وإلغاء تأثيراته فوراً',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 620,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (files.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24.0),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: M3Shape.radiusMd,
                          ),
                          child: const Center(
                            child: Text('لا توجد شيتات مرفوعة حالياً'),
                          ),
                        )
                      else
                        Flexible(
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 10.0,
                              runSpacing: 10.0,
                              children: files.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final file = entry.value;
                                final isLatest = idx == 0;
                                return Container(
                                  key: ValueKey('file_sheet_bubble_${file.id}'),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14.0,
                                    vertical: 12.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isLatest
                                        ? cs.primaryContainer
                                            .withValues(alpha: 0.45)
                                        : cs.surfaceContainerLow,
                                    borderRadius: M3Shape.radiusLg,
                                    border: Border.all(
                                      color: isLatest
                                          ? cs.primary.withValues(alpha: 0.5)
                                          : cs.outlineVariant
                                              .withValues(alpha: 0.6),
                                      width: isLatest ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: isLatest
                                            ? cs.primary
                                            : cs.surfaceContainerHighest,
                                        child: Icon(
                                          Icons.table_chart_rounded,
                                          size: 18,
                                          color: isLatest
                                              ? cs.onPrimary
                                              : cs.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(width: 12.0),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: M3WrapText(
                                                    file.fileName,
                                                    maxLines: 3,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: M3FontSize
                                                          .labelMediumPlus,
                                                    ),
                                                  ),
                                                ),
                                                if (isLatest) ...[
                                                  const SizedBox(width: 8.0),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8.0,
                                                      vertical: 2.0,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                              0xFF0F766E)
                                                          .withValues(
                                                              alpha: 0.15),
                                                      borderRadius:
                                                          M3Shape.radiusFull,
                                                    ),
                                                    child: const Text(
                                                      'مفعل حالياً',
                                                      style: TextStyle(
                                                        fontSize:
                                                            M3FontSize.tiny,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: M3Palette.teal,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 4.0),
                                            Wrap(
                                              spacing: 10.0,
                                              runSpacing: 4.0,
                                              children: [
                                                Text(
                                                  'تاريخ الرفع: ${_formatUploadDate(file.uploadedAt)}',
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                    color: cs.onSurfaceVariant,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                Text(
                                                  '• عدد الأصناف: ${file.rowsIngested} صنف',
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                    color: cs.primary,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        key: ValueKey(
                                            'delete_file_sheet_btn_${file.id}'),
                                        tooltip:
                                            'حذف هذا الشيت وإلغاء تأثيراته من الكارتة',
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          color: cs.error,
                                        ),
                                        onPressed: () async {
                                          Navigator.of(ctx).pop();
                                          await _handleDeleteProductMasterSheet(
                                              file);
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('إغلاق'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _handleUploadMasterWorkbook();
                    },
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('رفع شيت أسعار جديد'),
                  ),
                ],
              ),
            );
          },
        );
      },
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

  String _formatUploadDate(String raw) =>
      AppDateFormat.tryFormat(raw, withTime: true);

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

  void _copyToClipboard(String value, String labelAr) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('تم نسخ $labelAr: $value'),
      ),
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
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Product Master & Price List',
                          style: theme.textTheme.headlineSmall,
                        ),
                        Text(
                          'كارتة الأصناف والأسعار',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('product_master_upload_btn'),
                    onPressed:
                        _isUploading ? null : _handleUploadMasterWorkbook,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_rounded),
                    label: Text(
                      _isUploading
                          ? 'جاري تحديث الكارتة...'
                          : 'رفع تحديث شيت الأسعار',
                    ),
                  ),
                ],
              ),
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
              padding:
                  const EdgeInsetsDirectional.fromSTEB(24.0, 20.0, 24.0, 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderBanner(theme, cs, summary),
                  const SizedBox(height: 16.0),
                  _buildKpiCardsRow(theme, cs, summary, filtered.length),
                  const SizedBox(height: 16.0),
                  M3ResponsiveTabBar<int>(
                    key: const ValueKey('product_master_tabs'),
                    textDirection: TextDirection.ltr,
                    selectedValue: _tabController.index,
                    items: [
                      M3ResponsiveTabItem<int>(
                        value: 0,
                        icon: Icons.qr_code_2_rounded,
                        selectedIcon: Icons.qr_code_2_rounded,
                        label: 'كارتة الأصناف (${filtered.length})',
                      ),
                      const M3ResponsiveTabItem<int>(
                        value: 1,
                        icon: Icons.calculate_rounded,
                        selectedIcon: Icons.calculate_rounded,
                        label: 'حاسبة الطلبيات والخصومات والهامش',
                      ),
                      M3ResponsiveTabItem<int>(
                        value: 2,
                        icon: Icons.cloud_upload_rounded,
                        selectedIcon: Icons.cloud_upload_rounded,
                        label:
                            'الشيتات المرفوعة (${_archivedMasterFiles.length})',
                      ),
                    ],
                    onChanged: (next) {
                      _tabController.animateTo(next);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildCatalogTab(theme, cs, summary, filtered),
            _buildCalculatorTab(theme, cs, summary),
            _buildUploadAndArchiveTab(theme, cs, summary),
          ],
        ),
        ),
      ),
    );
  }

  /// Short status chip matching Sell-Out / Trade Marketing geometry.
  /// Labels stay on one line (no wrap) so «مسحوب» never clips as «مسحو / ب».
  Widget _statusChip(String label, Color color, {Key? key, IconData? icon}) {
    final style = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: M3FontSize.labelSmallPlus,
      color: color,
    );
    final text = Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      textAlign: TextAlign.center,
      style: style,
    );
    return M3ChipSurface(
      key: key,
      color: color.withValues(alpha: 0.14),
      child: icon == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14.0, color: color),
                const SizedBox(width: M3Spacing.xxs),
                text,
              ],
            ),
    );
  }

  Widget _buildHeaderBanner(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
  ) {
    final totalChanged = summary.priceIncreasedCount +
        summary.priceDecreasedCount +
        summary.newSkusCount;
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer.withValues(alpha: 0.55),
            cs.surfaceContainer,
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Wrap(
        spacing: 16.0,
        runSpacing: 14.0,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: M3Shape.radiusMd,
                ),
                child: Icon(
                  Icons.inventory_rounded,
                  color: cs.onPrimary,
                  size: 28.0,
                ),
              ),
              const SizedBox(width: 14.0),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'كارتة الأصناف والأسعار المعتمدة • أدكو (Adeco)',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      'Canonical Product Master, Item Codes (كود الصنف), Barcodes & Official Carton/Unit Pricing',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 6.0,
                      children: [
                        _buildMetaChip(
                          cs,
                          Icons.verified_rounded,
                          summary.sheetDateLabel,
                        ),
                        _buildMetaChip(
                          cs,
                          Icons.discount_rounded,
                          'خصم فاتورة ${summary.defaultDiscountPct.toStringAsFixed(0)}%',
                        ),
                        _buildMetaChip(
                          cs,
                          Icons.receipt_long_rounded,
                          'ضريبة ${(summary.defaultVatRate * 100).toStringAsFixed(0)}%',
                        ),
                        // Compact interactive File Sheets bubble button replacing cluttered file list
                        InkWell(
                          key: const ValueKey('product_master_file_sheets_btn'),
                          onTap: _showFileSheetsModal,
                          borderRadius: M3Shape.radiusFull,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 4.5,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.12),
                              borderRadius: M3Shape.radiusFull,
                              border: Border.all(
                                color: cs.primary.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.folder_special_rounded,
                                  size: 15.0,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 6.0),
                                Text(
                                  'File Sheets • شيتات الأسعار (${_archivedMasterFiles.length})',
                                  style: TextStyle(
                                    fontSize: M3FontSize.labelSmallPlus,
                                    fontWeight: FontWeight.w800,
                                    color: cs.primary,
                                  ),
                                ),
                                const SizedBox(width: 4.0),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16.0,
                                  color: cs.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (totalChanged > 0)
                          InkWell(
                            key: const ValueKey(
                                'product_master_diff_summary_chip'),
                            onTap: () => _showUploadDiffSummaryDialog(summary),
                            borderRadius: M3Shape.radiusFull,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10.0,
                                vertical: 4.5,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    M3Palette.warning.withValues(alpha: 0.14),
                                borderRadius: M3Shape.radiusFull,
                                border: Border.all(
                                  color:
                                      M3Palette.warning.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.price_change_rounded,
                                    size: 14.0,
                                    color: M3Palette.amberDeep,
                                  ),
                                  const SizedBox(width: 5.0),
                                  Text(
                                    'ملخص فروق الأسعار: ↑${summary.priceIncreasedCount} ↓${summary.priceDecreasedCount} +${summary.newSkusCount}',
                                    style: const TextStyle(
                                      fontSize: M3FontSize.labelSmallPlus,
                                      fontWeight: FontWeight.w800,
                                      color: M3Palette.amberDeep,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 10.0,
            runSpacing: 8.0,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('product_master_header_sheets_btn'),
                onPressed: _showFileSheetsModal,
                icon: const Icon(Icons.layers_rounded, size: 18.0),
                label: Text('File Sheets (${_archivedMasterFiles.length})'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('product_master_export_csv_btn'),
                onPressed: _exportFilteredCatalogToCsv,
                icon: const Icon(Icons.download_rounded, size: 18.0),
                label: const Text('تصدير Excel (CSV)'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('product_master_add_sku_btn'),
                onPressed: () async {
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
                },
                icon: const Icon(Icons.add_box_rounded, size: 18.0),
                label: const Text('إضافة صنف جديد'),
              ),
              FilledButton.icon(
                key: const ValueKey('product_master_upload_btn'),
                onPressed: _isUploading ? null : _handleUploadMasterWorkbook,
                icon: _isUploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded, size: 18.0),
                label: Text(
                  _isUploading
                      ? 'جاري تحديث الكارتة...'
                      : 'رفع تحديث شيت الأسعار',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip(ColorScheme cs, IconData icon, String label) {
    return _statusChip(label, cs.primary, icon: icon);
  }

  Widget _buildKpiCardsRow(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
    int filteredCount,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Even fill: 5 cards → 3+2 at the live shell (not a lonely 4+1).
        // Card height stays Sell-Out 138 via M3SummaryKpiCard + equal grid.
        final columns = M3KpiGridColumns.forWidthAndCount(
          constraints.maxWidth,
          5,
        );
        final regularShare = summary.totalSkus > 0
            ? ((summary.regularSkusCount / summary.totalSkus) * 100)
                .toStringAsFixed(1)
            : '0';
        return M3EqualHeightGrid(
          key: const ValueKey('product_master_kpi_grid'),
          columns: columns,
          spacing: M3Spacing.sm,
          runSpacing: M3Spacing.sm,
          children: [
            M3SummaryKpiCard(
              key: const ValueKey('pm_kpi_card_Total Registered'),
              title: 'إجمالي الأصناف',
              titleMaxLines: 1,
              subtitleMaxLines: 1,
              value: countSku(summary.totalSkus),
              subtitle: 'المعروض بالفلتر الحالي: ${countSku(filteredCount)}',
              icon: Icons.qr_code_scanner_rounded,
              color: cs.primary,
              valueKey: const ValueKey('pm_kpi_value_Total Registered'),
            ),
            M3SummaryKpiCard(
              key: const ValueKey('pm_kpi_card_Regular Catalog'),
              title: 'أصناف البيع العادي',
              titleMaxLines: 1,
              subtitleMaxLines: 1,
              value: countSku(summary.regularSkusCount),
              subtitle: 'تمثل $regularShare% من إجمالي الكارتة',
              icon: Icons.check_circle_outline_rounded,
              color: M3Palette.teal,
            ),
            M3SummaryKpiCard(
              key: const ValueKey('pm_kpi_card_Promos'),
              title: 'أصناف العروض',
              titleMaxLines: 1,
              subtitleMaxLines: 1,
              value: '${_intFmt.format(summary.promoSkusCount)} عرض',
              subtitle: 'عروض وشرنك وباقات ترويجية',
              icon: Icons.local_offer_rounded,
              color: M3Palette.warning,
            ),
            M3SummaryKpiCard(
              key: const ValueKey('pm_kpi_card_Unique Barcodes'),
              title: 'الباركودات الفريدة',
              titleMaxLines: 1,
              subtitleMaxLines: 1,
              value: '${_intFmt.format(summary.uniqueBarcodesCount)} باركود',
              subtitle:
                  'متوسط السعة: ${summary.avgUnitsPerCarton.toStringAsFixed(1)} وحدة/كرتونة',
              icon: Icons.view_in_ar_rounded,
              color: M3Palette.indigo,
            ),
            M3SummaryKpiCard(
              key: const ValueKey('pm_kpi_card_Chain Coverage'),
              title: 'التغطية بالسلاسل',
              titleMaxLines: 1,
              subtitleMaxLines: 1,
              value: '${_intFmt.format(summary.activeInChainsCount)} نشط',
              subtitle:
                  'غير مسحوب (فرصة توزيع): ${countSku(summary.unpulledSkusCount)}',
              icon: Icons.storefront_rounded,
              color: M3Palette.info,
            ),
          ],
        );
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

  Widget _buildCatalogTab(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
    List<ProductMasterItemModel> filtered,
  ) {
    final totalPages = (filtered.length / _pageSize).ceil();
    final safePage =
        totalPages == 0 ? 0 : _currentPage.clamp(0, totalPages - 1);
    final startIdx = safePage * _pageSize;
    final endIdx = (startIdx + _pageSize) > filtered.length
        ? filtered.length
        : (startIdx + _pageSize);
    final pageItems = filtered.isEmpty
        ? const <ProductMasterItemModel>[]
        : filtered.sublist(startIdx, endIdx);

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(24.0, 8.0, 24.0, 32.0),
      children: [
        // Search & Filter Bar
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: M3Shape.radiusLg,
            border:
                Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: M3SearchFieldWidth(
                      hintText: 'بحث بكود الصنف أو الباركود أو الاسم',
                      child: TextField(
                      key: const ValueKey('product_master_search_input'),
                      controller: _searchController,
                      onChanged: (_) => setState(() => _currentPage = 0),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _currentPage = 0);
                                },
                              )
                            : null,
                        hintText: 'بحث بكود الصنف أو الباركود أو الاسم',
                        filled: true,
                        fillColor: cs.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        border: const OutlineInputBorder(
                          borderRadius: M3Shape.radiusMd,
                        ),
                      ),
                    ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  if (_selectedPrefix != 'all' ||
                      _selectedBrand != 'all' ||
                      _selectedItemType != 'all' ||
                      _selectedPackaging != 'all' ||
                      _selectedPullStatus != 'all' ||
                      _selectedPriceChange != 'all' ||
                      _searchController.text.isNotEmpty)
                    TextButton.icon(
                      key: const ValueKey('product_master_reset_filters_btn'),
                      onPressed: () {
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
                      },
                      icon:
                          const Icon(Icons.filter_alt_off_rounded, size: 18.0),
                      label: const Text('إعادة ضبط الفلاتر'),
                    ),
                ],
              ),
              const SizedBox(height: 12.0),
              // Quick Price-Change Filter Bar (فلتر سريع لتغيرات الأسعار)
              _buildQuickPriceChangeFilterBar(theme, cs, summary),
              const SizedBox(height: 12.0),
              Wrap(
                spacing: 12.0,
                runSpacing: 10.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Item Code Prefix dropdown filter
                  _buildDropdownFilter(
                    labelAr: 'البادئة',
                    value: _selectedPrefix,
                    items: {
                      'all': 'الكل (All)',
                      for (final pfx in _buildEffectivePrefixChips(summary))
                        pfx: '$pfx (${_prefixDescriptionAr(pfx)})',
                    },
                    onChanged: (v) => setState(() {
                      _selectedPrefix = v ?? 'all';
                      _currentPage = 0;
                    }),
                  ),
                  // Brand filter
                  _buildDropdownFilter(
                    labelAr: 'العلامة',
                    value: _selectedBrand,
                    items: {
                      'all':
                          'كل العلامات التجارية (${summary.availableBrands.length})',
                      for (final b in summary.availableBrands) b: b,
                    },
                    onChanged: (v) => setState(() {
                      _selectedBrand = v ?? 'all';
                      _currentPage = 0;
                    }),
                  ),
                  // Item Type filter
                  _buildDropdownFilter(
                    labelAr: 'النوع',
                    value: _selectedItemType,
                    items: {
                      'all': 'الكل (عادي + عرض)',
                      'عادي': 'عادي (Regular - ${summary.regularSkusCount})',
                      'عرض': 'عرض ترويجي (Promo - ${summary.promoSkusCount})',
                    },
                    onChanged: (v) => setState(() {
                      _selectedItemType = v ?? 'all';
                      _currentPage = 0;
                    }),
                  ),
                  // Packaging filter
                  _buildDropdownFilter(
                    labelAr: 'التعبئة',
                    value: _selectedPackaging,
                    items: {
                      'all': 'كل أنواع التعبئة',
                      for (final p in summary.availablePackaging) p: p,
                    },
                    onChanged: (v) => setState(() {
                      _selectedPackaging = v ?? 'all';
                      _currentPage = 0;
                    }),
                  ),
                  // Chain Pull Status filter
                  _buildDropdownFilter(
                    labelAr: 'السحب',
                    value: _selectedPullStatus,
                    items: {
                      'all': 'الكل (${summary.totalSkus})',
                      'active':
                          'مسحوب ونشط بالسلاسل (${summary.activeInChainsCount})',
                      'unpulled':
                          'غير مسحوب - فرصة توزيع (${summary.unpulledSkusCount})',
                    },
                    onChanged: (v) => setState(() {
                      _selectedPullStatus = v ?? 'all';
                      _currentPage = 0;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16.0),

        // Table Header & Pagination Top Bar
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: M3Shape.radiusLg,
            border:
                Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12.0,
                  runSpacing: 8.0,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'جدول كارتة الأصناف والأسعار الرسمية (${_intFmt.format(filtered.length)} صنف)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Official SKU Master Table • اضغط على أي صنف لفتح بطاقة تعريف الصنف أو تعديل السعر والباركود',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          filtered.isEmpty
                              ? '0 من 0'
                              : 'عرض ${startIdx + 1} - $endIdx من ${filtered.length}',
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(width: 8.0),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded),
                          tooltip: 'الصفحة السابقة',
                          onPressed: safePage > 0
                              ? () =>
                                  setState(() => _currentPage = safePage - 1)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded),
                          tooltip: 'الصفحة التالية',
                          onPressed: safePage < totalPages - 1
                              ? () =>
                                  setState(() => _currentPage = safePage + 1)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1.0),
              if (pageItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد أصناف مطابقة لمعايير البحث الحالية',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                )
              else
                LayoutBuilder(builder: (context, tableConstraints) {
                final w = _catalogColumnWidths(tableConstraints.maxWidth);
                Widget box(int i, Widget child) =>
                    SizedBox(width: w[i], child: child);
                return TableScrollContainer(
                  showSwipeHint: false,
                  showControls: false,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      cs.surfaceContainerHighest.withValues(alpha: 0.45),
                    ),
                    dataRowMinHeight: 52.0,
                    dataRowMaxHeight: 120.0,
                    headingRowHeight: 44.0,
                    columnSpacing: 6.0,
                    horizontalMargin: 8.0,
                    showCheckboxColumn: false,
                    columns: [
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: box(0, _buildColHeader('م', '#')),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: box(1, _buildColHeader('كود الصنف', 'Item Code')),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: box(2, _buildColHeader('اسم الصنف', 'Official SKU Name')),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: box(3, _buildColHeader('الباركود', 'Barcode')),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: box(4, _buildColHeader('التعبئة', 'Pack')),
                      ),
                      DataColumn(
                        numeric: true,
                        headingRowAlignment: MainAxisAlignment.center,
                        label: box(5, _buildColHeader('سعر الوحدة', 'Excl. VAT')),
                      ),
                      DataColumn(
                        numeric: true,
                        headingRowAlignment: MainAxisAlignment.center,
                        label: box(6, _buildColHeader('السعر ش.ض', 'Incl. VAT')),
                      ),
                      DataColumn(
                        numeric: true,
                        headingRowAlignment: MainAxisAlignment.center,
                        label: box(7, _buildColHeader('سعر الكرتونة', 'Carton')),
                      ),
                      DataColumn(
                        numeric: true,
                        headingRowAlignment: MainAxisAlignment.center,
                        label: box(
                          8,
                          _buildColHeader(
                            'الصافي',
                            'Net (-${summary.defaultDiscountPct.toStringAsFixed(0)}%)',
                          ),
                        ),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: box(9, _buildColHeader('النوع', 'Type')),
                      ),
                      DataColumn(
                        headingRowAlignment: MainAxisAlignment.center,
                        label: box(10, _buildColHeader('إجراءات', 'Actions')),
                      ),
                    ],
                    rows: pageItems.map((item) {
                      final isPromo = item.itemType == 'عرض';
                      final raw = DataRow(
                        onSelectChanged: (_) async {
                          await ProductMasterScreen.showProductIdCardModal(
                            context,
                            apiClient: widget.apiClient,
                            item: item,
                            onUpdated: (updatedSummary) {
                              _repo.prime(updatedSummary);
                              if (mounted) {
                                setState(() => _summary = updatedSummary);
                              }
                            },
                          );
                        },
                        cells: [
                          DataCell(
                            Text(
                              item.serialNo.toString(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          // Item Code pill
                          DataCell(
                            SizedBox(
                              width: w[1],
                              child: InkWell(
                              onTap: () =>
                                  _copyToClipboard(item.itemCode, 'كود الصنف'),
                              borderRadius: M3Shape.radiusSm,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0,
                                  vertical: 2.0,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer
                                      .withValues(alpha: 0.55),
                                  borderRadius: M3Shape.radiusSm,
                                  border: Border.all(
                                    color: cs.primary.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: HyphenatedCodeText(
                                  item.itemCode,
                                  maxLines: 2,
                                  maxWidth: w[1] - 10,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w800,
                                    fontSize: M3FontSize.bodySmall,
                                  ),
                                ),
                              ),
                            ),
                            ),
                          ),
                          // Official Name & Brand (centered, wrap ≤3)
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                M3WrapText(
                                  item.officialName,
                                  maxLines: 3,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2.0),
                                M3WrapText(
                                  '${item.brand} • ${item.category}',
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontSize: M3FontSize.tinyPlus,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Barcode
                          DataCell(
                            SizedBox(
                              width: w[3],
                              child: InkWell(
                              onTap: () =>
                                  _copyToClipboard(item.barcode, 'الباركود'),
                              borderRadius: M3Shape.radiusSm,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0,
                                  vertical: 2.0,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest
                                      .withValues(alpha: 0.6),
                                  borderRadius: M3Shape.radiusSm,
                                ),
                                child: HyphenatedCodeText(
                                  item.barcode,
                                  maxLines: 2,
                                  maxWidth: w[3] - 10,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700,
                                    fontSize: M3FontSize.bodySmall,
                                  ),
                                ),
                              ),
                            ),
                            ),
                          ),
                          // Pack & Units/Carton
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                M3WrapText(
                                  '${item.unitsPerCarton} / كرتونة',
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                M3WrapText(
                                  item.packagingType,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Unit Price Excl VAT
                          DataCell(
                            M3WrapText(
                              '${_currFmt.format(item.unitPriceExclVat)} ج.م',
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          // Unit Price Incl VAT + Price Change Indicator Badge
                          DataCell(
                            _buildPriceWithChangeIndicator(theme, cs, item),
                          ),
                          // Carton Price Incl VAT
                          DataCell(
                            M3WrapText(
                              '${_currFmt.format(item.cartonPriceInclVat)} ج.م',
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          // Net Unit Cost
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                M3WrapText(
                                  '${_currFmt.format(item.netUnitInvoiceCost)} ج.م',
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: M3Palette.teal,
                                  ),
                                ),
                                M3WrapText(
                                  'كرتونة: ${_currFmt.format(item.netCartonInvoiceCost)}',
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: M3FontSize.tiny,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Item Type & Pull Status: short chip + description
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _statusChip(
                                  isPromo ? 'عرض' : 'عادي',
                                  isPromo
                                      ? M3Palette.amberDeep
                                      : M3Palette.teal,
                                ),
                                const SizedBox(height: 4.0),
                                _statusChip(
                                  item.isActiveInChains ? 'مسحوب' : 'غير مسحوب',
                                  item.isActiveInChains
                                      ? M3Palette.info
                                      : cs.onSurfaceVariant,
                                ),
                                const SizedBox(height: 2.0),
                                M3WrapText(
                                  item.isActiveInChains
                                      ? (item.totalPosUnitsSold > 0
                                          ? '${_intFmt.format(item.totalPosUnitsSold)} وحدة'
                                          : 'نشط بالسلاسل')
                                      : 'فرصة توزيع',
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: M3FontSize.tiny,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Actions
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 28.0,
                                    minHeight: 28.0,
                                  ),
                                  style: IconButton.styleFrom(
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    minimumSize: const Size(28.0, 28.0),
                                  ),
                                  icon: const Icon(
                                    Icons.badge_rounded,
                                    size: 18.0,
                                  ),
                                  tooltip: 'بطاقة تعريف الصنف وتعديل السعر',
                                  onPressed: () async {
                                    await ProductMasterScreen
                                        .showProductIdCardModal(
                                      context,
                                      apiClient: widget.apiClient,
                                      item: item,
                                      onUpdated: (updatedSummary) {
                                        _repo.prime(updatedSummary);
                                        if (mounted) {
                                          setState(
                                              () => _summary = updatedSummary);
                                        }
                                      },
                                    );
                                  },
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 28.0,
                                    minHeight: 28.0,
                                  ),
                                  style: IconButton.styleFrom(
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    minimumSize: const Size(28.0, 28.0),
                                  ),
                                  icon: const Icon(
                                    Icons.calculate_rounded,
                                    size: 18.0,
                                  ),
                                  tooltip: 'حساب طلبية وهامش ربح لهذا الصنف',
                                  onPressed: () {
                                    setState(() {
                                      _selectCalculatorSku(item);
                                      _tabController.animateTo(1);
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                      return DataRow(
                        onSelectChanged: raw.onSelectChanged,
                        cells: [
                          for (var i = 0; i < raw.cells.length; i++)
                            DataCell(box(i, raw.cells[i].child)),
                        ],
                      );
                    }).toList(),
                  ),
                );
                }),
            ],
          ),
        ),
      ],
    );
  }

  /// Mins at the live 1030 content shell: item code / barcode stay on
  /// one monospace line (e.g. FGCL-0550-0001, 13-digit barcodes), and
  /// the price headers «سعر الوحدة / السعر ش.ض / سعر الكرتونة» are
  /// not cut. Leftover width still goes to the name column.
  // Type col (index 9) must fit one-line chips «مسحوب» / «غير مسحوب»
  // (M3ChipSurface padding + Cairo) without wrapping mid-word.
  static const _catalogColMinsLive = <double>[
    24, 130, 140, 120, 64, 80, 80, 88, 64, 96, 52,
  ];

  /// Narrower shell (1024+sidebar ≈ 774dp): codes wrap at dashes, no
  /// horizontal scroll.
  static const _catalogColMinsCompact = <double>[
    24, 92, 120, 92, 60, 52, 52, 52, 60, 88, 52,
  ];

  /// Column content widths that fill [available] (table chrome included)
  /// so the 11-column catalog fits the live 1030 content shell.
  List<double> _catalogColumnWidths(double available) {
    const spacing = 6.0;
    const margin = 8.0;
    // Live 1280+sidebar content is 1030, but the catalog tab has 24dp
    // horizontal padding, so the table LayoutBuilder sees ~982dp — still
    // the live profile. Compact is for the 1024+sidebar shell (~726–774).
    final useLive = available >= 900;
    final mins = useLive ? _catalogColMinsLive : _catalogColMinsCompact;
    final slack = useLive ? 24.0 : 16.0;
    final chrome = margin * 2 + spacing * (mins.length - 1) + slack;
    var leftover = available - chrome - mins.fold<double>(0, (a, b) => a + b);
    final widths = List<double>.from(mins);
    if (leftover > 0) {
      widths[2] += leftover;
    } else if (leftover < 0) {
      // Shrink the name column first, then the others, never below 85% of min.
      // Shrink type (9) last so pull-status chips keep one-line width.
      for (final i in [2, 4, 8, 1, 3, 10, 5, 6, 7, 0, 9]) {
        if (leftover >= 0) break;
        final reducible = widths[i] - mins[i] * 0.85;
        if (reducible <= 0) continue;
        final cut = reducible < -leftover ? reducible : -leftover;
        widths[i] -= cut;
        leftover += cut;
      }
    }
    return widths;
  }

  Widget _buildQuickPriceChangeFilterBar(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
  ) {
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

    Widget buildChip({
      required String keyId,
      required String value,
      required String label,
      required IconData icon,
      required Color color,
    }) {
      final isSelected = _selectedPriceChange == value;
      return FilterChip(
        key: ValueKey(keyId),
        selected: isSelected,
        showCheckmark: false,
        avatar: Icon(
          icon,
          size: 15.0,
          color: isSelected ? Colors.white : color,
        ),
        label: Text(
          label,
          style: TextStyle(
            fontSize: M3FontSize.labelSmallPlus,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : cs.onSurface,
          ),
        ),
        selectedColor: color,
        backgroundColor: cs.surface,
        side: BorderSide(
          color: isSelected ? color : color.withValues(alpha: 0.35),
        ),
        onSelected: (_) {
          setState(() {
            _selectedPriceChange =
                (_selectedPriceChange == value && value != 'all')
                    ? 'all'
                    : value;
            _currentPage = 0;
          });
        },
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: M3Shape.radiusMd,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.price_change_rounded, size: 17.0, color: cs.primary),
              const SizedBox(width: 6.0),
              const Text(
                'فلتر سريع لتغيرات الأسعار:',
                style: TextStyle(
                    fontSize: M3FontSize.bodySmall,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
          buildChip(
            keyId: 'price_filter_all',
            value: 'all',
            label: 'الكل (${summary.totalSkus})',
            icon: Icons.apps_rounded,
            color: cs.primary,
          ),
          buildChip(
            keyId: 'price_filter_changed',
            value: 'changed',
            label: 'تغير السعر ($changedCount)',
            icon: Icons.published_with_changes_rounded,
            color: M3Palette.warning,
          ),
          buildChip(
            keyId: 'price_filter_up',
            value: 'up',
            label: 'زاد ↑ ($upCount)',
            icon: Icons.trending_up_rounded,
            color: M3Palette.danger,
          ),
          buildChip(
            keyId: 'price_filter_down',
            value: 'down',
            label: 'انخفض ↓ ($downCount)',
            icon: Icons.trending_down_rounded,
            color: M3Palette.teal,
          ),
          buildChip(
            keyId: 'price_filter_new',
            value: 'new',
            label: 'جديد ($newCount)',
            icon: Icons.fiber_new_rounded,
            color: M3Palette.info,
          ),
          if (summary.diffSummary != null)
            ActionChip(
              key: const ValueKey('product_master_open_diff_summary_btn'),
              avatar: Icon(
                Icons.summarize_rounded,
                size: 15.0,
                color: cs.primary,
              ),
              label: const Text(
                'تقرير مقارنة الشيت الجديد',
                style: TextStyle(
                    fontSize: M3FontSize.labelSmallPlus,
                    fontWeight: FontWeight.w800),
              ),
              onPressed: () => _showUploadDiffSummaryDialog(
                summary,
                uploadedFilename: summary.sourceFilename,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPriceWithChangeIndicator(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterItemModel item,
  ) {
    final dir = item.priceChangeDirection.toLowerCase();
    final isUp = dir == 'up';
    final isDown = dir == 'down';
    final isNew = dir == 'new';
    final hasPrev = item.prevUnitPriceInclVat > 0;
    final changeColor = isUp
        ? M3Palette.danger
        : isDown
            ? M3Palette.teal
            : M3Palette.info;
    // Missing prior price / pct → «—», never advertise a fake +0.0%.
    final changeLabel = isNew
        ? 'جديد'
        : (!hasPrev || item.priceChangePct == 0)
            ? '—'
            : CurrencyFormatter.formatSignedPct(item.priceChangePct);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        M3WrapText(
          '${_currFmt.format(item.unitPriceInclVat)} ج.م',
          maxLines: 2,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.primary,
          ),
        ),
        if (isUp || isDown || isNew) ...[
          const SizedBox(height: 2.0),
          _statusChip(
            changeLabel,
            changeColor,
            key: ValueKey('price_indicator_${item.itemCode}_$dir'),
            icon: isUp
                ? Icons.trending_up_rounded
                : isDown
                    ? Icons.trending_down_rounded
                    : Icons.fiber_new_rounded,
          ),
          if ((isUp || isDown) && hasPrev)
            M3WrapText(
              'كان: ${_currFmt.format(item.prevUnitPriceInclVat)} ج.م',
              maxLines: 2,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: M3FontSize.microPlus,
                color: cs.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
              ),
            )
          else if ((isUp || isDown) && !hasPrev)
            M3WrapText(
              'لا يوجد سعر سابق للمقارنة',
              maxLines: 2,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: M3FontSize.microPlus,
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildColHeader(String ar, String en) {
    return Tooltip(
      message: en,
      child: Text(
        ar,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.visible,
        style: const TextStyle(
            fontWeight: FontWeight.w800, fontSize: M3FontSize.bodySmall),
      ),
    );
  }

  Widget _buildDropdownFilter({
    required String labelAr,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = items.containsKey(value) ? value : 'all';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$labelAr:',
          style: const TextStyle(
              fontSize: M3FontSize.bodySmall, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 6.0),
        DropdownButtonHideUnderline(
          child: M3Dropdown<String>(
            value: safeValue,
            fitOptions: true,
            options: m3OptionsFromMenuItems<String>(items.entries
                .map((e) => DropdownMenuItem<String>(
                      value: e.key,
                      child: Text(
                        e.value,
                        style: const TextStyle(fontSize: M3FontSize.bodySmall),
                      ),
                    ))
                .toList()),
            onChanged: m3Legacy<String>(onChanged),
          ),
        ),
      ],
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

  void _exportCalculatorOrderToCsv({
    required ProductMasterItemModel sku,
    required double cartons,
    required int totalUnits,
    required double grossExclVat,
    required double vatAmount,
    required double grossInclVat,
    required double invDiscPct,
    required double extraDiscPct,
    required double totalDiscountEgp,
    required double netPayable,
    required double netUnitCost,
    required double shelfUnitPrice,
    required double retailerProfitEgp,
    required double retailerMarginPct,
  }) {
    final csv = ExcelExportService.generateCsv(
      headers: const [
        'كود الصنف (Item Code)',
        'الاسم الرسمي للصنف (Official Name)',
        'الباركود (Barcode)',
        'الكمية بالكرتونة (Cartons)',
        'الشدة بالكرتونة (Units/Carton)',
        'إجمالي الوحدات (Total Units)',
        'إجمالي القيمة قبل الضريبة (Gross Excl VAT)',
        'ضريبة القيمة المضافة 14% (VAT EGP)',
        'الإجمالي شامل الضريبة (Gross Incl VAT)',
        'خصم الفاتورة % (Invoice Disc %)',
        'خصم إضافي % (Extra Disc %)',
        'إجمالي الخصومات (Total Discount EGP)',
        'صافي الفاتورة المستحق لأدكو (Net Payable EGP)',
        'صافي تكلفة الوحدة (Net Unit Cost EGP)',
        'سعر بيع السلسلة للمستهلك (Shelf Price EGP)',
        'هامش ربح السلسلة المتوقع % (Retailer Margin %)',
        'إجمالي ربح السلسلة (Retailer Profit EGP)',
      ],
      rows: [
        [
          sku.itemCode,
          sku.officialName,
          sku.barcode,
          cartons.toStringAsFixed(1),
          sku.unitsPerCarton.toString(),
          totalUnits.toString(),
          grossExclVat.toStringAsFixed(2),
          vatAmount.toStringAsFixed(2),
          grossInclVat.toStringAsFixed(2),
          '${invDiscPct.toStringAsFixed(1)}%',
          '${extraDiscPct.toStringAsFixed(1)}%',
          totalDiscountEgp.toStringAsFixed(2),
          netPayable.toStringAsFixed(2),
          netUnitCost.toStringAsFixed(2),
          shelfUnitPrice.toStringAsFixed(2),
          '${retailerMarginPct.toStringAsFixed(1)}%',
          retailerProfitEgp.toStringAsFixed(2),
        ],
      ],
    );
    ExcelExportService.downloadCsv(
      'Adeco_Order_${sku.itemCode}_${DateTime.now().millisecondsSinceEpoch}.csv',
      csv,
    );
  }

  Widget _buildCalculatorTab(
    ThemeData theme,
    ColorScheme cs,
    ProductMasterSummaryModel summary,
  ) {
    final sku = _calcSelectedSku ??
        (summary.items.isNotEmpty ? summary.items.first : null);
    if (sku == null) {
      return const Center(child: Text('لا توجد أصناف متاحة بالحاسبة'));
    }

    final cartons = double.tryParse(_calcCartonsCtrl.text.trim()) ?? 1.0;
    final invDiscPct = double.tryParse(_calcInvoiceDiscCtrl.text.trim()) ??
        sku.invoiceDiscountPct;
    final extraDiscPct =
        double.tryParse(_calcExtraDiscCtrl.text.trim()) ?? sku.extraDiscountPct;
    final shelfUnitPrice = double.tryParse(_calcRetailPriceCtrl.text.trim()) ??
        sku.unitPriceInclVat;

    final totalUnits = (cartons * sku.unitsPerCarton).round();
    final grossExclVat = cartons * sku.cartonPriceExclVat;
    final vatAmount = grossExclVat * sku.vatRate;
    final grossInclVat = cartons * sku.cartonPriceInclVat;

    final afterInvDisc = grossInclVat * (1.0 - (invDiscPct / 100.0));
    final netPayable = afterInvDisc * (1.0 - (extraDiscPct / 100.0));
    final totalDiscountEgp = grossInclVat - netPayable;
    final netUnitCost = totalUnits > 0 ? netPayable / totalUnits : 0.0;

    final shelfMissing = shelfUnitPrice <= 0;
    final totalShelfRevenue = shelfMissing ? 0.0 : totalUnits * shelfUnitPrice;
    final retailerProfitEgp =
        shelfMissing ? 0.0 : totalShelfRevenue - netPayable;
    final retailerMarginPct = !shelfMissing && totalShelfRevenue > 0
        ? (retailerProfitEgp / totalShelfRevenue) * 100.0
        : 0.0;

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(24.0, 12.0, 24.0, 32.0),
      children: [
        ChainDiscountProfilesCard(
          profiles: _chainProfiles,
          loading: _chainProfilesLoading,
          saving: _chainProfilesSaving,
          error: _chainProfilesError,
          onSave: _saveChainProfiles,
        ),
        const SizedBox(height: 16.0),
        Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: M3Shape.radiusLg,
            border:
                Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12.0,
                runSpacing: 8.0,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'حاسبة الطلبيات والخصومات وضريبة القيمة المضافة وهامش ربح السلسلة',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Order Economics, VAT (14%), Trade Discounts & Retailer Shelf Margin Simulator',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('product_master_export_order_csv_btn'),
                    onPressed: () => _exportCalculatorOrderToCsv(
                      sku: sku,
                      cartons: cartons,
                      totalUnits: totalUnits,
                      grossExclVat: grossExclVat,
                      vatAmount: vatAmount,
                      grossInclVat: grossInclVat,
                      invDiscPct: invDiscPct,
                      extraDiscPct: extraDiscPct,
                      totalDiscountEgp: totalDiscountEgp,
                      netPayable: netPayable,
                      netUnitCost: netUnitCost,
                      shelfUnitPrice: shelfUnitPrice,
                      retailerProfitEgp: retailerProfitEgp,
                      retailerMarginPct: retailerMarginPct,
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18.0),
                    label: const Text('تصدير أمر التوريد Excel (CSV)'),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),
              M3Dropdown<String>(
                key: const ValueKey('calc_chain_dropdown'),
                value: _calcChain,
                label: 'السلسلة (تملأ الخصمين تلقائياً)',
                expand: true,
                options: [
                  const M3DropdownOption('', 'بدون سلسلة — 10% / 0%'),
                  for (final p in _chainProfiles)
                    M3DropdownOption(
                      p.chain,
                      '${p.chain} — ${p.invoiceDiscountPct}% / ${p.additionalDiscountPct}%',
                    ),
                ],
                onChanged: (v) => setState(() {
                  _calcChain = v;
                  _applyCalcChainDiscounts();
                }),
              ),
              const SizedBox(height: 16.0),
              M3Dropdown<ProductMasterItemModel>(
                value: summary.items.contains(sku) ? sku : summary.items.first,
                label: 'اختر الصنف من كارتة الأصناف (Select SKU)',
                expand: true,
                options:
                    m3OptionsFromMenuItems<ProductMasterItemModel>(summary.items
                        .take(200)
                        .map(
                          (item) => DropdownMenuItem<ProductMasterItemModel>(
                            value: item,
                            child: Text(
                              '[${item.itemCode}] ${item.officialName} • باركود: ${item.barcode} (${item.unitsPerCarton} وحدة/كرتونة)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList()),
                onChanged: m3Legacy<ProductMasterItemModel>((val) {
                  if (val != null) {
                    setState(() => _selectCalculatorSku(val));
                  }
                }),
              ),
              const SizedBox(height: 16.0),
              Wrap(
                spacing: 16.0,
                runSpacing: 12.0,
                children: [
                  SizedBox(
                    width: 210,
                    child: TextField(
                      controller: _calcCartonsCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'الكمية بالكرتونة (Cartons)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: TextField(
                      controller: _calcInvoiceDiscCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'خصم الفاتورة % (Invoice Disc %)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: TextField(
                      controller: _calcExtraDiscCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'خصم إضافي % (Extra Disc %)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: TextField(
                      controller: _calcRetailPriceCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'سعر بيع السلسلة للمستهلك (Shelf EGP)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20.0),
              const Divider(),
              const SizedBox(height: 12.0),
              LayoutBuilder(
                builder: (context, calcConstraints) {
                  // Same 138dp shared cards as the Product Master / Sell-Out
                  // KPIs. 3 columns at the live 1030 shell (inner ~942 after
                  // page + card padding); 2 columns on the 1024 shell.
                  final columns = calcConstraints.maxWidth >= 720
                      ? 3
                      : (calcConstraints.maxWidth >= 520 ? 2 : 1);
                  return M3EqualHeightGrid(
                    key: const ValueKey('pm_calc_result_grid'),
                    columns: columns,
                    spacing: M3Spacing.sm,
                    runSpacing: M3Spacing.sm,
                    children: [
                      M3SummaryKpiCard(
                        key: const ValueKey('pm_calc_card_total_units'),
                        title: 'إجمالي الوحدات',
                        titleTooltip: 'إجمالي الوحدات بالطلبية',
                        titleMaxLines: 1,
                        subtitleMaxLines: 1,
                        value: '${_intFmt.format(totalUnits)} وحدة',
                        subtitle: 'Total Units Ordered · ${sku.packagingType}',
                        icon: Icons.inventory_2_rounded,
                        color: cs.primary,
                      ),
                      M3SummaryKpiCard(
                        key: const ValueKey('pm_calc_card_gross'),
                        title: 'القيمة قبل الضريبة',
                        titleTooltip: 'إجمالي القيمة قبل الضريبة',
                        titleMaxLines: 1,
                        subtitleMaxLines: 1,
                        value: '${_currFmt.format(grossExclVat)} ج.م',
                        subtitle: 'Gross Value Excl. VAT',
                        icon: Icons.payments_rounded,
                        color: cs.onSurface,
                      ),
                      M3SummaryKpiCard(
                        key: const ValueKey('pm_calc_card_vat'),
                        title: 'ضريبة القيمة المضافة',
                        titleTooltip: 'قيمة ضريبة القيمة المضافة (14%)',
                        titleMaxLines: 1,
                        subtitleMaxLines: 1,
                        value: '${_currFmt.format(vatAmount)} ج.م',
                        subtitle: 'VAT Amount (14%)',
                        icon: Icons.receipt_long_rounded,
                        color: M3Palette.warning,
                      ),
                      M3SummaryKpiCard(
                        key: const ValueKey('pm_calc_card_discounts'),
                        title: 'الخصومات التجارية',
                        titleTooltip: 'إجمالي قيمة الخصومات التجارية',
                        titleMaxLines: 1,
                        subtitleMaxLines: 1,
                        value: CurrencyFormatter.formatEGP(-totalDiscountEgp, showDecimals: true),
                        subtitle: 'Total Invoice & Extra Discounts',
                        icon: Icons.discount_rounded,
                        color: M3Palette.danger,
                      ),
                      M3SummaryKpiCard(
                        key: const ValueKey('pm_calc_card_net'),
                        title: 'صافي الفاتورة',
                        titleTooltip: 'صافي الفاتورة المستحق لأدكو',
                        titleMaxLines: 1,
                        subtitleMaxLines: 1,
                        value: '${_currFmt.format(netPayable)} ج.م',
                        subtitle:
                            'Net Payable · الوحدة: ${_currFmt.format(netUnitCost)}',
                        icon: Icons.account_balance_wallet_rounded,
                        color: M3Palette.teal,
                      ),
                      M3SummaryKpiCard(
                        key: const ValueKey('pm_calc_card_margin'),
                        title: 'هامش ربح السلسلة',
                        titleTooltip: 'هامش ربح السلسلة المتوقع',
                        titleMaxLines: 1,
                        subtitleMaxLines: 1,
                        value: shelfMissing
                            ? '—'
                            : '${retailerMarginPct.toStringAsFixed(1)}%',
                        subtitle: shelfMissing
                            ? 'أدخل سعر بيع السلسلة لحساب الهامش'
                            : 'Shelf Margin · ${_currFmt.format(retailerProfitEgp)} ج.م',
                        icon: Icons.trending_up_rounded,
                        color: M3Palette.indigo,
                        textValue: shelfMissing,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
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
      padding: const EdgeInsetsDirectional.fromSTEB(24.0, 12.0, 24.0, 32.0),
      children: [
        Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: M3Shape.radiusLg,
            border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              Icon(
                Icons.cloud_upload_rounded,
                size: 48.0,
                color: cs.primary,
              ),
              const SizedBox(height: 12.0),
              Text(
                'رفع وتحديث شيت كارتة الأصناف والأسعار (Excel .xlsx / .csv)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4.0),
              Text(
                'يقوم النظام تلقائياً بقراءة أكواد الأصناف (FGCL, FGDW, PR...) والباركودات وسعة الكرتونة والأسعار وتحديث جميع شاشات المبيعات والنواقص والتسعير فوراً',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16.0),
              FilledButton.icon(
                onPressed: _isUploading ? null : _handleUploadMasterWorkbook,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('اختيار شيت كارتة الأصناف من الجهاز'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20.0),
        Text(
          'أرشيف شيتات كارتة الأصناف والأسعار المرفوعة (${_archivedMasterFiles.length})',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10.0),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ تعديلات الصنف: $e')),
      );
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

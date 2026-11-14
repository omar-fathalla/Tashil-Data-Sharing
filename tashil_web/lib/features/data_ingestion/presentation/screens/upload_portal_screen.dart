import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/bidi_text.dart';
import '../../../../core/utils/arabic_plural.dart';
import '../../../../core/widgets/archive_actions_group.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_button_group.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../../../core/widgets/m3_search_field.dart';
import '../../../../core/widgets/m3_section_title.dart';
import '../../../../core/widgets/m3_states.dart';
import '../../../../core/widgets/m3_table_surface.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../widgets/ai_analysis_progress_card.dart';
import '../widgets/anomaly_resolution_table.dart';
import '../widgets/dropzone_file_picker.dart';
import '../widgets/preupload_fix_list.dart';
import '../widgets/register_chain_dialog.dart';
import '../widgets/sell_in_upload_target.dart';
import '../widgets/upload_checks.dart';
import '../../../../core/data/available_years.dart';
import '../../../../core/data/data_refresh_mixin.dart';

/// UploadPortalScreen serves as the entry point for uploading retail files
/// and managing the retail-chain-organized Excel/CSV archive.
class UploadPortalScreen extends StatefulWidget {
  final ApiClient apiClient;

  const UploadPortalScreen({
    super.key,
    required this.apiClient,
  });

  /// True when the archive entry has no measured sell-out metrics yet.
  static bool archiveMetricsMissing(ArchivedExcelFileModel file) =>
      file.rowsIngested <= 0 &&
      file.branchesCount <= 0 &&
      file.totalRevenue <= 0;

  /// Branches cell: «—» when metrics were never recorded (not a measured 0).
  static String? archiveBranchesLabel(ArchivedExcelFileModel file) {
    if (file.fileType == 'product_master' || archiveMetricsMissing(file)) {
      return null;
    }
    return CurrencyFormatter.formatNumber(file.branchesCount);
  }

  /// Rows cell: «—» when the file has no ingested metrics.
  static String? archiveRowsLabel(ArchivedExcelFileModel file) {
    if (archiveMetricsMissing(file)) return null;
    return CurrencyFormatter.formatNumber(file.rowsIngested);
  }

  /// Revenue cell: «—» for product-master or when metrics are absent.
  static String? archiveRevenueLabel(ArchivedExcelFileModel file) {
    if (file.fileType == 'product_master' || archiveMetricsMissing(file)) {
      return null;
    }
    return CurrencyFormatter.formatCompactEGP(file.totalRevenue);
  }

  static const String archiveMissingMetricNote = 'لا تتوفر مؤشرات لهذا الملف';

  /// Formats an archive ISO timestamp. Empty → «—» (never invent a date).
  static String formatArchiveDateTime(String iso) {
    if (iso.isEmpty) return '—';
    if (iso.length >= 16) return iso.substring(0, 16).replaceAll('T', ' ');
    if (iso.length >= 10) return iso.substring(0, 10);
    return iso;
  }

  @override
  State<UploadPortalScreen> createState() => _UploadPortalScreenState();
}

class _UploadPortalScreenState extends State<UploadPortalScreen>
    with DataRefreshMixin<UploadPortalScreen> {
  @override
  void onBackendDataChanged() {
    _loadArchive();
  }

  bool isProcessing = false;
  bool isCommitting = false;
  IngestionResultModel? result;
  PreuploadCheckReport? _preuploadReport;
  final Set<String> _processedFiles = {};
  String? _stagedFileKey;
  late String _lastTenantId;

  List<RetailChainModel> _availableChains = [];
  String _selectedTenant = 'adeco';
  String? _selectedChain; // Must start null (no pre-selected chain)
  bool _showChainRequiredError = false;
  String _selectedYear = 'auto';
  String _selectedMonth = 'auto';
  bool _isLoadingContext = true;

  // Per-Company Retail Chain Creation & Management State
  final TextEditingController _newChainNameController = TextEditingController();
  bool _isAddingChain = false;

  // Excel Archive State
  List<ArchivedExcelFileModel> _archivedFiles = [];
  Map<String, int> _archiveChainCounts = {};
  String _archiveChainFilter = 'all';
  String _archiveYearFilter = 'all';
  String _archiveSearchQuery = '';
  bool _isLoadingArchive = true;
  bool _archiveLoadFailed = false;
  String? _downloadingArchiveId;
  String? _deletingArchiveId;
  final TextEditingController _archiveSearchController =
      TextEditingController();
  final ScrollController _archiveSheetsScrollController = ScrollController();

  static const double _archiveHeadingHeight = 48.0;
  // 3 filename lines + the size line under the name, kept aligned
  // with the pinned actions column.
  static const double _archiveRowHeight = 104.0;
  static const List<double> _archiveColumnFlex = [
    1.9, // الملف (flexes and wraps)
    0.95, // السلسلة
    0.7, // الفترة
    0.5, // الفروع
    0.65, // السجلات
    0.75, // المبيعات
    1.35, // تاريخ الرفع (full uploaded + last-import date)
  ];
  static const double _archiveActionsWidthEstimate = 168.0;

  static const Map<String, String> _monthNamesAr = {
    '1': '1 - يناير (Jan)',
    '2': '2 - فبراير (Feb)',
    '3': '3 - مارس (Mar)',
    '4': '4 - أبريل (Apr)',
    '5': '5 - مايو (May)',
    '6': '6 - يونيو (Jun)',
    '7': '7 - يوليو (Jul)',
    '8': '8 - أغسطس (Aug)',
    '9': '9 - سبتمبر (Sep)',
    '10': '10 - أكتوبر (Oct)',
    '11': '11 - نوفمبر (Nov)',
    '12': '12 - ديسمبر (Dec)',
  };

  String? _buildEffectivePeriodDate() {
    if (_selectedYear == 'auto' && _selectedMonth == 'auto') {
      return null;
    }
    // Only a full year+month is sent; half a period is never completed with a guessed value
    // (_periodSelectionError blocks the upload instead).
    if (_selectedYear == 'auto' || _selectedMonth == 'auto') return null;
    return '$_selectedYear-${_selectedMonth.padLeft(2, '0')}-15';
  }

  /// Arabic message when only one of year/month is chosen; null when the selection is usable.
  String? _periodSelectionError() {
    final yearAuto = _selectedYear == 'auto';
    final monthAuto = _selectedMonth == 'auto';
    if (yearAuto == monthAuto) return null;
    return yearAuto
        ? 'اخترت الشهر من غير السنة. اختار السنة كمان، أو رجّع الاتنين "تلقائي" عشان نقرا الفترة من الملف.'
        : 'اخترت السنة من غير الشهر. اختار الشهر كمان، أو رجّع الاتنين "تلقائي" عشان نقرا الفترة من الملف.';
  }

  String _describeTargetPeriod() {
    if (_periodChoice == 'sheet') return describeSheetPeriod(_sheetMonths);
    if (_selectedYear == 'auto' && _selectedMonth == 'auto') {
      return 'اكتشاف تلقائي من الشيت (Auto)';
    }
    if (_selectedYear == 'auto' || _selectedMonth == 'auto') {
      return 'الفترة ناقصة: ${_periodSelectionError() ?? ''}';
    }
    final mLabel = _monthNamesAr[_selectedMonth] ?? _selectedMonth;
    return '$mLabel • سنة $_selectedYear (${_buildEffectivePeriodDate()})';
  }

  @override
  void initState() {
    super.initState();
    _lastTenantId = widget.apiClient.tenantId;
    _selectedTenant =
        ApiClient.normalizeDataTenantSlug(widget.apiClient.tenantId);
    _loadContext();
    _loadArchive();
    AvailableYears.load(widget.apiClient).then((_) {
      if (mounted) setState(() {});
    });
  }

  // Answers the user gave to upload questions for the staged file; resent on commit.
  bool _replaceConfirmed = false;
  String? _periodChoice;
  List<String> _sheetMonths = const [];

  /// Runs an upload/commit call, asking the user each server question (409) and resending with the answer.
  /// Returns null when the user cancels a question (nothing saved).
  Future<IngestionResultModel?> _withUploadQuestions(
    Future<IngestionResultModel> Function(
            bool replaceConfirmed, String? periodChoice)
        call,
  ) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        return await call(_replaceConfirmed, _periodChoice);
      } on UploadConfirmationRequiredException catch (q) {
        if (!mounted) return null;
        if (q.kind == 'chain_required') {
          setState(() => _showChainRequiredError = true);
        }
        final answer = await askUploadConfirmation(context, q);
        if (answer == null || q.kind == 'chain_required') return null;
        if (answer.replaceConfirmed) _replaceConfirmed = true;
        if (answer.periodChoice != null) _periodChoice = answer.periodChoice;
        if (q.kind == 'period_conflict' && q.breakdown.isNotEmpty) {
          _sheetMonths = [for (final b in q.breakdown) b.month];
        }
      }
    }
    return null;
  }

  @override
  void dispose() {
    _newChainNameController.dispose();
    _archiveSearchController.dispose();
    _archiveSheetsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    setState(() => _isLoadingContext = true);
    final chains =
        await widget.apiClient.getRetailChains(targetTenant: _selectedTenant);
    if (mounted) {
      setState(() {
        _availableChains = chains;
        if (_selectedChain != null &&
            !_availableChains.any((c) => c.code == _selectedChain)) {
          _selectedChain = null;
        }
        _isLoadingContext = false;
      });
    }
  }

  Future<void> _handleAddCompanyChain() async {
    final rawName = _newChainNameController.text.trim();
    if (rawName.isEmpty) {
      M3Feedback.showWarning(
        context,
        'يرجى كتابة اسم السلسلة أولاً',
      );
      return;
    }

    final formattedBilingual = ApiClient.formatBilingualChainName(rawName);
    final generatedCode = ApiClient.generateChainCode(formattedBilingual);
    final existingIdx = _availableChains.indexWhere(
      (c) =>
          c.code.toLowerCase() == generatedCode.toLowerCase() ||
          c.displayName.trim().toLowerCase() == rawName.toLowerCase() ||
          c.displayName.trim().toLowerCase() ==
              formattedBilingual.toLowerCase(),
    );
    if (existingIdx >= 0) {
      final existing = _availableChains[existingIdx];
      setState(() {
        _selectedChain = existing.code;
        _showChainRequiredError = false;
        _newChainNameController.clear();
      });
      M3Feedback.showInfo(
        context,
        'السلسلة "${existing.displayName}" مسجلة بالفعل وتم اختيارها كسلسلة مستهدفة.',
      );
      return;
    }

    setState(() => _isAddingChain = true);
    try {
      final created = await widget.apiClient.createRetailChain(
        displayName: formattedBilingual,
        code: generatedCode,
        targetTenant: _selectedTenant,
      );
      final refreshed =
          await widget.apiClient.getRetailChains(targetTenant: _selectedTenant);
      if (mounted) {
        setState(() {
          _availableChains =
              refreshed.isNotEmpty ? refreshed : [..._availableChains, created];
          _selectedChain = created.code;
          _showChainRequiredError = false;
          _isAddingChain = false;
          _newChainNameController.clear();
        });
        M3Feedback.showSuccess(
          context,
          'تمت إضافة سلسلة "${created.displayName}" بنجاح',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAddingChain = false);
        M3Feedback.showError(context, 'تعذر إضافة السلسلة: $e');
      }
    }
  }

  Future<void> _showEditCompanyChainDialog(RetailChainModel chain) async {
    final decomposed = ApiClient.decomposeBilingualChainName(chain.displayName);
    final arCtrl = TextEditingController(text: decomposed.nameAr);
    final enCtrl = TextEditingController(text: decomposed.nameEn);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final theme = Theme.of(ctx);
        return AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusLg),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: M3Shape.radiusSm,
                ),
                child: Icon(Icons.edit_note_rounded,
                    color: colorScheme.onPrimaryContainer, size: 22.0),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('تعديل سلسلة التجزئة',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('edit_chain_arabic_input'),
                    controller: arCtrl,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      labelText: 'اسم السلسلة بالعربية',
                      hintText: 'مثال: الوكالة، أسواق فتح الله...',
                      prefixIcon:
                          const Icon(Icons.language_rounded, size: 18.0),
                      border: const OutlineInputBorder(
                          borderRadius: M3Shape.radiusMd),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHigh,
                    ),
                  ),
                  const SizedBox(height: 14.0),
                  TextField(
                    key: const ValueKey('edit_chain_english_input'),
                    controller: enCtrl,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'اسم السلسلة بالإنجليزية',
                      hintText: 'e.g. El Wakala, Fathalla Market...',
                      prefixIcon:
                          const Icon(Icons.translate_rounded, size: 18.0),
                      border: const OutlineInputBorder(
                          borderRadius: M3Shape.radiusMd),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHigh,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.check_rounded, size: 18.0),
              label: const Text('حفظ التعديل'),
            ),
          ],
        );
      },
    );

    if (saved == true) {
      final cleanAr = arCtrl.text.trim();
      final cleanEn = enCtrl.text.trim();
      String combinedDisplay = '';
      if (cleanAr.isNotEmpty && cleanEn.isNotEmpty) {
        combinedDisplay = '$cleanAr ($cleanEn)';
      } else if (cleanAr.isNotEmpty) {
        combinedDisplay = ApiClient.formatBilingualChainName(cleanAr);
      } else if (cleanEn.isNotEmpty) {
        combinedDisplay = ApiClient.formatBilingualChainName(cleanEn);
      }
      if (combinedDisplay.isNotEmpty) {
        try {
          await widget.apiClient.updateRetailChain(
            code: chain.code,
            displayName: combinedDisplay,
            chainType: chain.chainType,
            storeCount: chain.storeCount,
            targetTenant: _selectedTenant,
          );
          await _loadContext();
          if (mounted) {
            M3Feedback.showSuccess(context, 'تم تحديث اسم السلسلة بنجاح');
          }
        } catch (e) {
          if (mounted) {
            M3Feedback.showError(context, 'فشل تعديل السلسلة: $e');
          }
        }
      }
    }
  }

  Future<void> _handleDeleteCompanyChain(RetailChainModel chain) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: colorScheme.error),
              const SizedBox(width: 8.0),
              const Expanded(child: Text('حذف السلسلة من قائمة الشركة')),
            ],
          ),
          content: Text(
            'هل تريد حذف سلسلة "${chain.displayName}" من قائمة سلاسل الشركة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.delete_forever_rounded, size: 18.0),
              label: const Text('حذف السلسلة'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    try {
      await widget.apiClient.deleteRetailChain(
        chain.code,
        targetTenant: _selectedTenant,
      );
      if (_selectedChain == chain.code) {
        _selectedChain = null;
      }
      if (_archiveChainFilter == chain.code) {
        _archiveChainFilter = 'all';
      }
      await _loadContext();
      await _loadArchive();
      if (mounted) {
        M3Feedback.showSuccess(
          context,
          'تم حذف سلسلة "${chain.displayName}" من قائمة الشركة',
        );
      }
    } catch (e) {
      if (mounted) {
        M3Feedback.showError(context, 'تعذر حذف السلسلة: $e');
      }
    }
  }

  String _getShortChainTabLabel(String code) {
    final match = _availableChains.where(
      (c) => c.code.toLowerCase() == code.toLowerCase(),
    );
    if (match.isNotEmpty) {
      final disp = match.first.displayName.trim();
      final parenIdx = disp.indexOf('(');
      if (parenIdx > 0) {
        return disp.substring(0, parenIdx).trim();
      }
      if (disp.isNotEmpty) return disp;
    }
    return ApiClient.getRetailChainShortAr(code);
  }

  Future<void> _loadArchive() async {
    setState(() {
      _isLoadingArchive = true;
      _archiveLoadFailed = false;
    });
    try {
      final resp = await widget.apiClient.getUploadedFilesArchive(
        chain: _archiveChainFilter == 'all' ? null : _archiveChainFilter,
        year: _archiveYearFilter == 'all' ? null : _archiveYearFilter,
        searchQuery: _archiveSearchQuery.trim().isEmpty
            ? null
            : _archiveSearchQuery.trim(),
        targetTenant: _selectedTenant,
      );
      if (mounted) {
        setState(() {
          _archivedFiles = resp.files;
          _archiveChainCounts = resp.chainCounts;
          _isLoadingArchive = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _archivedFiles = [];
          _archiveChainCounts = {};
          _archiveLoadFailed = true;
          _isLoadingArchive = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant UploadPortalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient ||
        _lastTenantId != widget.apiClient.tenantId) {
      setState(() {
        _lastTenantId = widget.apiClient.tenantId;
        _selectedTenant =
            ApiClient.normalizeDataTenantSlug(widget.apiClient.tenantId);
        _selectedChain = null;
        _showChainRequiredError = false;
        isProcessing = false;
        isCommitting = false;
        result = null;
        _preuploadReport = null;
        _stagedFileKey = null;
        _processedFiles.clear();
      });
      _loadContext();
      _loadArchive();
    }
  }

  String _getChainDisplayName(String? code) {
    if (code == null || code.isEmpty)
      return '-- اختر سلسلة التجزئة المستهدفة --';
    final match = _availableChains.where((c) => c.code == code);
    if (match.isNotEmpty) return match.first.displayName;
    return ApiClient.getRetailChainDisplayName(code);
  }

  bool _validateChainSelectedBeforeUpload() {
    if (_selectedChain == null || _selectedChain!.trim().isEmpty) {
      setState(() => _showChainRequiredError = true);
      M3Feedback.showError(
        context,
        'تنبيه هام: يجب اختيار سلسلة التجزئة المستهدفة أولاً قبل رفع ملف الإكسيل حتى لا يتم إدراج البيانات في سلسلة خاطئة!',
      );
      return false;
    }
    return true;
  }

  Future<void> _handleFileSelected(String filename, List<int> bytes) async {
    if (widget.apiClient.currentUser?.canUploadFiles == false) {
      M3Feedback.showError(
        context,
        'غير مصرح: دورك الحالي لا يملك صلاحية رفع ملفات البيانات (RBAC)',
      );
      return;
    }

    if (!_validateChainSelectedBeforeUpload()) {
      return;
    }

    final periodError = _periodSelectionError();
    if (periodError != null) {
      M3Feedback.showError(context, periodError);
      return;
    }

    final activeChain = _selectedChain!;
    final effectivePeriodDate = _buildEffectivePeriodDate();
    final fileKey =
        '$filename-${bytes.length}-$_selectedTenant-$activeChain-${effectivePeriodDate ?? 'auto'}';
    if (_processedFiles.contains(fileKey)) {
      await M3Feedback.showDuplicateWarning(
        context,
        title: 'تم رفض المعالجة: ملف مكرر',
        message:
            'تم استيعاب هذا الملف ومطابقة معاملاته في قاعدة بيانات BigQuery مسبقاً. تم رفض إعادة المعالجة لمنع تكرار البيانات المالية.',
        duplicateIdentifier: 'اسم الملف: $filename (سلسلة: $activeChain)',
      );
      return;
    }

    setState(() {
      _showChainRequiredError = false;
      isProcessing = true;
      result = null;
      _preuploadReport = null;
      _stagedFileKey = fileKey;
    });
    _replaceConfirmed = false;
    _periodChoice = null;
    _sheetMonths = const [];

    try {
      // Single upload: server folds preupload.Check into dry-run (no second file POST).
      final res = await _withUploadQuestions(
          (replaceConfirmed, periodChoice) => widget.apiClient.uploadFile(
                filename,
                bytes,
                targetChain: activeChain,
                targetTenant: _selectedTenant,
                periodDate: effectivePeriodDate,
                dryRun: true,
                replaceConfirmed: replaceConfirmed,
                periodChoice: periodChoice,
              ));
      if (res == null) {
        if (mounted) {
          setState(() => isProcessing = false);
          M3Feedback.showInfo(context, 'اتلغى الرفع ومفيش حاجة اتحفظت');
        }
        return;
      }
      widget.apiClient.recordAuditLog(
        action: 'INGEST_ANALYZE',
        resource: filename,
        details:
            'تحليل أولي لملف $filename لسلسلة $activeChain وشركة $_selectedTenant (${res.validRows} صف صالح • ${res.autoCreatedStoresCount} فرع) - قيد المراجعة',
      );
      await _loadArchive();
      if (mounted) {
        setState(() {
          result = res;
          isProcessing = false;
        });

        if (res.chainMismatchDetected) {
          final discoveredName =
              res.suggestedChainName ?? res.discoveredRetailer;
          M3Feedback.showWarning(
            context,
            'تنبيه تعارض السلسلة: محتوى الملف يشير إلى "$discoveredName" بينما السلسلة المحددة هي "${_getChainDisplayName(activeChain)}". راجع البيانات أدناه.',
          );
        } else {
          M3Feedback.showInfo(
            context,
            'تم فحص وتحليل ملف $filename بالذكاء الاصطناعي • يرجى مراجعة البيانات والضغط على زر "حفظ واعتماد البيانات"',
          );
        }
      }
    } on PreuploadBlockedException catch (e) {
      if (mounted) {
        setState(() {
          isProcessing = false;
          _preuploadReport = e.report;
        });
        M3Feedback.showError(
          context,
          'الملف محتاج تصليح قبل الرفع (${e.report.blockingCount} مشكلة). مفيش حاجة اتحفظت.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => isProcessing = false);
        M3Feedback.showError(
          context,
          'فشلت معالجة الملف: $e',
        );
      }
    }
  }

  void _handleFixChainMismatch() {
    if (result?.suggestedChain == null) return;
    final oldChain = _selectedChain ?? result!.targetRetailer;
    final newChain = result!.suggestedChain!;
    final newName =
        result!.suggestedChainName ?? _getChainDisplayName(newChain);
    final batchId = result!.batchId;
    widget.apiClient.updateStagedArchiveChain(
      batchId,
      newChain,
      targetTenant: _selectedTenant,
      periodDate: _buildEffectivePeriodDate(),
    );
    setState(() {
      _selectedChain = newChain;
      _showChainRequiredError = false;
      if (_stagedFileKey != null && oldChain.isNotEmpty) {
        _stagedFileKey = _stagedFileKey!.replaceFirst(
          '-$_selectedTenant-$oldChain-',
          '-$_selectedTenant-$newChain-',
        );
      }
      result = result!.copyWith(
        chainMismatchDetected: false,
        retailerDetected: newChain,
        targetRetailer: newChain,
      );
    });
    _loadArchive();
    M3Feedback.showSuccess(
      context,
      'تم تصحيح سلسلة التجزئة المستهدفة تلقائياً إلى "$newName"',
    );
  }

  Future<void> _handleCommitData() async {
    if (result == null || isCommitting) return;

    final activeChain = _selectedChain ?? result!.targetRetailer;
    final chainDisplayName = _getChainDisplayName(activeChain);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colorScheme = theme.colorScheme;
        final hasMismatch = result!.chainMismatchDetected;

        return AlertDialog(
          icon: Icon(
            hasMismatch
                ? Icons.warning_amber_rounded
                : Icons.check_circle_rounded,
            color: hasMismatch ? Colors.amber.shade800 : colorScheme.primary,
            size: 32.0,
          ),
          title: Text(
            'تأكيد اعتماد وحفظ البيانات',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasMismatch) ...[
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    margin: const EdgeInsets.only(bottom: 16.0),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: M3Shape.radiusSm,
                      border: Border.all(
                          color: Colors.amber.shade700.withOpacity(0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.amber.shade900, size: 22.0),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            'تنبيه تعارض: محتوى الملف يتبع لسلسلة "${result!.suggestedChainName ?? result!.discoveredRetailer}" بينما السلسلة المحددة هي "$chainDisplayName". هل تود تأكيد الحفظ تحت "$chainDisplayName"؟',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Text(
                  'سيتم إدراج معاملات المبيعات نهائياً في Google BigQuery ومزامنة الفروع المكتشفة في Firestore.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16.0),
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                    borderRadius: M3Shape.radiusSm,
                  ),
                  child: Column(
                    children: [
                      _buildDialogRow('اسم الملف:', result!.filename, theme),
                      const Divider(height: 12.0),
                      _buildDialogRow(
                          'سلسلة التجزئة:', chainDisplayName, theme),
                      const Divider(height: 12.0),
                      _buildDialogRow(
                          'الفترة الزمنية:', _describeTargetPeriod(), theme),
                      const Divider(height: 12.0),
                      _buildDialogRow(
                          'السجلات الصالحة:', '${result!.validRows} صف', theme),
                      const Divider(height: 12.0),
                      _buildDialogRow('الفروع المكتشفة:',
                          '${result!.autoCreatedStoresCount} فرع', theme),
                      const Divider(height: 12.0),
                      _buildDialogRow(
                          'إجمالي المبيعات:',
                          CurrencyFormatter.formatCompactEGP(
                              result!.totalRevenue),
                          theme),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('تراجع'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.check_circle_rounded),
              label: const Text('تأكيد الحفظ والاعتماد'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => isCommitting = true);

    try {
      final batchId = result!.batchId;
      final committedResult = await _withUploadQuestions(
          (replaceConfirmed, periodChoice) =>
              widget.apiClient.commitStagedUpload(
                batchId: batchId,
                targetChain: activeChain,
                targetTenant: _selectedTenant,
                periodDate: _buildEffectivePeriodDate(),
                replaceConfirmed: replaceConfirmed,
                periodChoice: periodChoice,
              ));
      if (committedResult == null) {
        if (mounted) {
          setState(() => isCommitting = false);
          M3Feedback.showInfo(context, 'اتلغى الحفظ ومفيش حاجة اتحفظت');
        }
        return;
      }

      widget.apiClient.recordAuditLog(
        action: 'INGEST_COMMIT',
        resource: result!.filename,
        details:
            'حفظ واعتماد بيانات ملف ${result!.filename} لسلسلة $activeChain (${committedResult.validRows} صف)',
      );

      if (_stagedFileKey != null) {
        _processedFiles.add(_stagedFileKey!);
      }

      await _loadArchive();

      if (mounted) {
        setState(() {
          result = committedResult;
          isCommitting = false;
        });

        M3Feedback.showSuccess(
          context,
          'تم حفظ واعتماد ${committedResult.validRows} صفاً لسلسلة $chainDisplayName بنجاح وتدفق البيانات إلى BigQuery',
        );
        unawaited(AvailableYears.load(widget.apiClient, force: true));
      }
    } catch (e) {
      if (mounted) {
        setState(() => isCommitting = false);
        // Any 4xx/5xx from the commit (410 expired preview, 409 changed file...) in an M3 dialog.
        await showUploadFailureDialog(context, result?.filename ?? '', e,
            title: 'الحفظ ماتمش ومفيش حاجة اتحفظت');
      }
    }
  }

  Future<void> _handleDiscardData() async {
    if (result == null || isCommitting) return;

    final batchId = result!.batchId;
    setState(() {
      result = null;
      _stagedFileKey = null;
    });

    await widget.apiClient.discardStagedUpload(
      batchId: batchId,
      targetTenant: _selectedTenant,
    );

    await _loadArchive();

    if (mounted) {
      M3Feedback.showInfo(
        context,
        'تم إلغاء وتفريغ المعاينة دون المساس بقاعدة البيانات',
      );
    }
  }

  Future<void> _handleDownloadArchivedFile(ArchivedExcelFileModel file) async {
    if (_downloadingArchiveId != null) return;
    setState(() => _downloadingArchiveId = file.id);
    try {
      await widget.apiClient.downloadArchivedFile(
        file,
        targetTenant: _selectedTenant,
      );
      widget.apiClient.recordAuditLog(
        action: 'ARCHIVE_DOWNLOAD',
        resource: file.fileName,
        details:
            'تحميل شيت الإكسيل المؤرشف ${file.fileName} لسلسلة ${file.chainNameAr}',
      );
      if (mounted) {
        M3Feedback.showSuccess(
          context,
          'تم بدء تحميل شيت الإكسيل الأصلي: ${file.fileName} (${file.chainNameAr})',
        );
      }
    } catch (e) {
      if (mounted) {
        M3Feedback.showError(context, 'تعذر تحميل الملف المؤرشف: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _downloadingArchiveId = null);
      }
    }
  }

  Future<void> _handleDeleteArchivedFile(ArchivedExcelFileModel file) async {
    if (_deletingArchiveId != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded,
            color: Colors.redAccent, size: 32.0),
        title: const Text('حذف شيت الإكسيل والبيانات المستوردة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل أنت متأكد من رغبتك في حذف ملف ${quotedLtr(file.fileName)}؟',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10.0),
            Text(
              rtlEnd('سيتم حذف هذا الشيت من التخزين (${ltrIsolate('Storage')}) ومسح كافة البيانات والسجلات التحليلية المستوردة منه من قاعدة البيانات نهائياً.'),
              style: TextStyle(
                color: Theme.of(dialogCtx).colorScheme.onSurfaceVariant,
                fontSize: M3FontSize.labelMediumPlus,
              ),
            ),
            const SizedBox(height: 12.0),
            Container(
              padding: const EdgeInsets.all(10.0),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: M3Shape.radiusSm,
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 20.0, color: Colors.red.shade800),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      'عند حذف جميع الشيتات المرفوعة، سيتم تصفير كافة أرقام المبيعات والتحليلات بالكامل.',
                      style: TextStyle(
                        fontSize: M3FontSize.bodySmall,
                        color: Colors.red.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deletingArchiveId = file.id);
    try {
      final ok = await widget.apiClient.deleteArchivedFile(
        file.id,
        targetTenant: _selectedTenant,
        fileName: file.fileName,
      );
      widget.apiClient.recordAuditLog(
        action: 'ARCHIVE_DELETE',
        resource: file.fileName,
        details:
            'حذف شيت الإكسيل المؤرشف ${file.fileName} لسلسلة ${file.chainNameAr} ومسح سجلاته',
      );
      if (mounted) {
        if (ok) {
          setState(() {
            _archivedFiles = _archivedFiles
                .where((f) => f.id != file.id && f.fileName != file.fileName)
                .toList();
          });
          M3Feedback.showSuccess(
            context,
            'تم حذف شيت "${file.fileName}" ومسح سجلاته التحليلية بنجاح.',
          );
          await _loadArchive();
        } else {
          M3Feedback.showError(
            context,
            'تعذر حذف الشيت "${file.fileName}". حاول مرة أخرى.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        M3Feedback.showError(context, 'خطأ أثناء حذف الملف المؤرشف: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _deletingArchiveId = null);
      }
    }
  }

  static Widget _buildDialogRow(String label, String value, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(width: 8.0),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canUpload = widget.apiClient.currentUser?.canUploadFiles ?? true;

    return SingleChildScrollView(
      padding: M3Spacing.pMd,
      child: M3ContentBoundary(
        maxWidth: 1440.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header (Unified M3 Left English Title + Right Arabic Subtitle)
            M3PageHeader(
              title: 'رفع البيانات الذكي',
              subtitle: 'Smart Data Ingestion Portal',
              description: 'مبيعات الفروع وأرشفة شيتات الإكسيل حسب السلاسل',
              actions: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: M3Shape.radiusLg,
                  border:
                      Border.all(color: colorScheme.primary.withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.layers_rounded,
                        size: 16.0, color: colorScheme.primary),
                    const SizedBox(width: 6.0),
                    Text(
                      'Multi-Tab Ingestion',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            M3Spacing.gapMD,

            if (!canUpload) ...[
              Container(
                key: const ValueKey('rbac_upload_restricted_banner'),
                padding: M3Spacing.pSm,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withOpacity(0.55),
                  borderRadius: M3Shape.radiusMd,
                  border: Border.all(color: colorScheme.error.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_person_rounded,
                        color: colorScheme.error, size: 20.0),
                    M3Spacing.hGapXS,
                    Expanded(
                      child: Text(
                        'تنبيه الصلاحيات (RBAC): رفع ملفات المبيعات متاح فقط لمدير الشركة أو مسؤول حساب السلسلة',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              M3Spacing.gapSM,
            ],

            // Organization & Retail Chain Context Selection Bar
            _buildContextSelectorBar(colorScheme, theme),

            // Red Warning Banner when attempting upload without selecting a retail chain
            if (_showChainRequiredError) ...[
              _buildMissingChainRedAlertBanner(theme),
              M3Spacing.gapMD,
            ],

            // File Picker Dropzone
            DropzoneFilePicker(
              isProcessing: isProcessing || isCommitting,
              hasError: _showChainRequiredError,
              onBeforePickFile: _validateChainSelectedBeforeUpload,
              onFileSelected: _handleFileSelected,
            ),

            if (_preuploadReport != null) ...[
              M3Spacing.gapMD,
              PreuploadFixListPanel(
                report: _preuploadReport!,
                onDismiss: () => setState(() => _preuploadReport = null),
              ),
            ],

            M3Spacing.gapMD,

            // Staging & Commit Status Transitions (M3 Fade Through)
            M3FadeThroughSwitcher(
              child: result == null
                  ? const SizedBox.shrink(key: ValueKey('upload_idle'))
                  : Column(
                      key: ValueKey(
                          'upload_status_${result!.isStaged}_${result!.isCommitted}'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (result!.isStaged) ...[
                          _buildStagingReviewBanner(colorScheme, theme),
                          M3Spacing.gapMD,
                        ],
                        if (result!.chainMismatchDetected) ...[
                          _buildChainMismatchCard(colorScheme, theme),
                          M3Spacing.gapMD,
                        ],
                        if (result!.isStaged) ...[
                          _buildCommitActionBar(colorScheme, theme),
                          M3Spacing.gapMD,
                        ],
                        if (result!.isCommitted) ...[
                          _buildCommittedSuccessBanner(colorScheme, theme),
                          M3Spacing.gapMD,
                        ],
                      ],
                    ),
            ),

            // AI Progress / Ingestion Result Card
            AiAnalysisProgressCard(
              isAnalyzing: isProcessing,
              result: result,
            ),

            if (result != null) ...[
              M3Spacing.gapMD,
              // Anomaly Resolution Table
              UploadChecksPanel(
                warnings: result!.uploadWarnings,
                quarantined: result!.quarantinedCustomers,
                unknownBarcodes: result!.unknownBarcodes,
              ),
              AnomalyResolutionTable(anomalies: result!.anomalies),
            ],

            M3Spacing.gapLG,

            // Persistent Retail Chain Excel Archive & Download System
            _buildExcelArchiveSection(colorScheme, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingChainRedAlertBanner(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Container(
      key: const ValueKey('missing_chain_error_banner'),
      padding: M3Spacing.pMd,
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withOpacity(0.45),
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.error, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: colorScheme.error,
              borderRadius: M3Shape.radiusSm,
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: colorScheme.onError,
              size: 24.0,
            ),
          ),
          M3Spacing.hGapMD,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تنبيه هام: يجب اختيار سلسلة التجزئة المستهدفة أولاً قبل رفع ملف الإكسيل حتى لا يتم إدراج البيانات في سلسلة خاطئة!',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  'يرجى تحديد السلسلة (مثل: أسواق فتح الله، جملة ماركت، كارفور مصر...) من قائمة "سلسلة التجزئة المستهدفة" أعلاه ثم إعادة المحاولة.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextSelectorBar(ColorScheme colorScheme, ThemeData theme) {
    final hasSelectedChain = _selectedChain != null &&
        _availableChains.any((c) => c.code == _selectedChain);
    final chainName =
        hasSelectedChain ? _getChainDisplayName(_selectedChain) : null;
    final periodLabel = _describeTargetPeriod();

    return Container(
      padding: M3Spacing.pMd,
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(
          color: _showChainRequiredError
              ? colorScheme.error
              : colorScheme.outlineVariant.withOpacity(0.5),
          width: _showChainRequiredError ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: M3Shape.radiusSm,
                ),
                child: Icon(
                  Icons.tune_rounded,
                  color: colorScheme.onPrimaryContainer,
                  size: 20.0,
                ),
              ),
              M3Spacing.gapSM,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const M3SectionTitle(
                      'سياق استيعاب البيانات وتوجيه الذكاء الاصطناعي (Ingestion Context)',
                      maxLines: 3,
                    ),
                    Text(
                      'حدد سلسلة التجزئة والسنة/الشهر المستهدف لضمان مطابقة الفروع وتوجيه البيانات في التاريخ الصحيح',
                      maxLines: 3,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isLoadingContext) ...[
            M3Spacing.gapSM,
            const LinearProgressIndicator(minHeight: 2.0),
          ],
          M3Spacing.gapMD,
          _buildCompanyChainsEntryBox(colorScheme, theme),
          if (widget.apiClient.currentUser?.canManageChains == true) ...[
            M3Spacing.gapSM,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: RegisterChainButton(
                apiClient: widget.apiClient,
                targetTenant: _selectedTenant,
                onRegistered: (_) => _loadContext(),
              ),
            ),
          ],
          M3Spacing.gapMD,
          LayoutBuilder(
            builder: (context, constraints) {
              // Under 600px the fields stack and the labels are short Arabic (no clipped English).
              final compact = constraints.maxWidth < 600;
              final chainDropdown = M3Dropdown<String?>(
                key: const ValueKey('ingestion_retail_chain_dropdown'),
                value: hasSelectedChain ? _selectedChain : null,
                label: 'السلسلة *',
                leadingIcon: Icons.store_mall_directory_rounded,
                fitOptions: true,
                expand: compact || constraints.maxWidth >= 1000,
                errorText: _showChainRequiredError ? 'مطلوب' : null,
                options: [
                  for (final c in _availableChains)
                    M3DropdownOption<String?>(
                      c.code,
                      c.storeCount > 0
                          ? '${c.displayName} (${countBranches(c.storeCount)})'
                          : c.displayName,
                    ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedChain = val;
                      _showChainRequiredError = false;
                    });
                  }
                },
              );

              final yearDropdown = M3Dropdown<String>(
                key: const ValueKey('ingestion_year_dropdown'),
                value: _selectedYear,
                label: 'السنة',
                leadingIcon: Icons.calendar_today_rounded,
                fitOptions: true,
                expand: compact || constraints.maxWidth >= 1000,
                options: [
                  const M3DropdownOption('auto', 'تلقائي من الشيت (Auto)'),
                  for (final y in AvailableYears.current
                      .including(int.tryParse(_selectedYear) ?? 0))
                    M3DropdownOption('$y', 'سنة $y'),
                ],
                onChanged: (val) => setState(() => _selectedYear = val),
              );

              final monthDropdown = M3Dropdown<String>(
                key: const ValueKey('ingestion_month_dropdown'),
                value: _selectedMonth,
                label: 'الشهر',
                leadingIcon: Icons.date_range_rounded,
                fitOptions: true,
                expand: compact || constraints.maxWidth >= 1000,
                options: [
                  const M3DropdownOption('auto', 'تلقائي (Auto)'),
                  for (final e in _monthNamesAr.entries)
                    M3DropdownOption(e.key, e.value),
                ],
                onChanged: (val) => setState(() => _selectedMonth = val),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    chainDropdown,
                    M3Spacing.gapXS,
                    yearDropdown,
                    M3Spacing.gapXS,
                    monthDropdown,
                  ],
                );
              }
              if (constraints.maxWidth >= 1000) {
                return Row(
                  children: [
                    Expanded(flex: 4, child: chainDropdown),
                    const SizedBox(width: M3Spacing.xs),
                    Expanded(flex: 3, child: yearDropdown),
                    const SizedBox(width: M3Spacing.xs),
                    Expanded(flex: 3, child: monthDropdown),
                  ],
                );
              }
              return Wrap(
                spacing: M3Spacing.xs,
                runSpacing: M3Spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  chainDropdown,
                  yearDropdown,
                  monthDropdown,
                ],
              );
            },
          ),
          M3Spacing.gapSM,
          // AI Context Badge
          Container(
            key: const ValueKey('ai_ingestion_context_status_bar'),
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: hasSelectedChain
                  ? colorScheme.secondaryContainer.withOpacity(0.4)
                  : (_showChainRequiredError
                      ? colorScheme.errorContainer.withOpacity(0.45)
                      : colorScheme.tertiaryContainer.withOpacity(0.35)),
              borderRadius: M3Shape.radiusSm,
              border: Border.all(
                color: hasSelectedChain
                    ? colorScheme.secondary.withOpacity(0.25)
                    : (_showChainRequiredError
                        ? colorScheme.error
                        : colorScheme.tertiary.withOpacity(0.4)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasSelectedChain
                      ? Icons.auto_awesome_rounded
                      : Icons.info_outline_rounded,
                  size: 16.0,
                  color: hasSelectedChain
                      ? colorScheme.secondary
                      : (_showChainRequiredError
                          ? colorScheme.error
                          : colorScheme.tertiary),
                ),
                M3Spacing.hGapXS,
                Expanded(
                  child: Text(
                    hasSelectedChain
                        ? 'سياق الذكاء الاصطناعي النشط: سيتم استيعاب ملف الإكسيل ومطابقة الفروع والأسعار تحت مظلة سلسلة "$chainName" • الفترة الزمنية: $periodLabel'
                        : 'سياق الذكاء الاصطناعي النشط: لم يتم اختيار سلسلة التجزئة بعد — يجب اختيار سلسلة التجزئة المستهدفة أعلاه قبل رفع ملف الإكسيل • الفترة الزمنية: $periodLabel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hasSelectedChain
                          ? colorScheme.onSecondaryContainer
                          : (_showChainRequiredError
                              ? colorScheme.onErrorContainer
                              : colorScheme.onTertiaryContainer),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStagingReviewBanner(ColorScheme colorScheme, ThemeData theme) {
    return Container(
      key: const ValueKey('staging_review_banner'),
      padding: M3Spacing.pMd,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.primary.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: M3Shape.radiusMd,
            ),
            child: Icon(
              Icons.rule_folder_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 26.0,
            ),
          ),
          M3Spacing.hGapMD,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8.0,
                  runSpacing: 6.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'وضع المعاينة والتدقيق الأمني (Staging & Review)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 2.0),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer.withOpacity(0.55),
                        borderRadius: M3Shape.radiusSm,
                        border: Border.all(
                            color: colorScheme.tertiary.withOpacity(0.45)),
                      ),
                      child: Text(
                        'لم يتم الحفظ في BigQuery بعد',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4.0),
                Text(
                  'قام الذكاء الاصطناعي باستخراج وتحليل كافة تابات الإكسيل والفروع والأصناف. البيانات معروضة أدناه للمراجعة فقط، ولن يتم اعتمادها أو التأثير على أي تقارير حتى تضغط زر "اعتماد البيانات".',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChainMismatchCard(ColorScheme colorScheme, ThemeData theme) {
    final suggestedName = result!.suggestedChainName ??
        result!.suggestedChain ??
        result!.discoveredRetailer;
    final currentChainName = _getChainDisplayName(_selectedChain);

    return Container(
      key: const ValueKey('chain_mismatch_alert_card'),
      padding: M3Spacing.pMd,
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withOpacity(0.35),
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.tertiary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: colorScheme.tertiary,
                  borderRadius: M3Shape.radiusSm,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: colorScheme.onTertiary,
                  size: 24.0,
                ),
              ),
              M3Spacing.hGapMD,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تنبيه تعارض سلسلة التجزئة (Chain Mismatch Detected)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'محتوى الملف وأسماء الفروع والتابات تشير إلى سلسلة "$suggestedName"، بينما السلسلة المحددة حالياً للاستيعاب هي "$currentChainName".',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'لتفادي خلط البيانات بين السلاسل، يمكنك تصحيح السلسلة تلقائياً بضغطة واحدة:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          M3Spacing.gapMD,
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: M3Button.primary(
              label: 'تصحيح السلسلة',
              icon: Icons.auto_fix_high_rounded,
              onPressed: _handleFixChainMismatch,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommitActionBar(ColorScheme colorScheme, ThemeData theme) {
    return Container(
      key: const ValueKey('commit_action_toolbar'),
      padding: M3Spacing.pMd,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border:
            Border.all(color: colorScheme.primary.withOpacity(0.4), width: 1.5),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: M3Spacing.md,
        runSpacing: M3Spacing.sm,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded,
                  color: colorScheme.primary, size: 24.0),
              const SizedBox(width: 8.0),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'جاهز للاعتماد والحفظ النهائي',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      'اضغط على زر الاعتماد لإدراج ${result!.validRows} صف صالح في BigQuery.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Cancel = text (not destructive); only final commit stays filled.
          M3ButtonGroup(
            items: [
              M3GroupItem(
                label: 'إلغاء',
                icon: Icons.close_rounded,
                kind: M3GroupItemKind.text,
                onPressed: isCommitting ? null : _handleDiscardData,
              ),
              M3GroupItem(
                label: 'اعتماد البيانات',
                icon: Icons.check_circle_rounded,
                kind: M3GroupItemKind.filled,
                isLoading: isCommitting,
                onPressed: isCommitting ? null : _handleCommitData,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommittedSuccessBanner(
      ColorScheme colorScheme, ThemeData theme) {
    final chainDisplayName =
        _getChainDisplayName(_selectedChain ?? result!.retailerDetected);
    return Container(
      key: const ValueKey('committed_success_banner'),
      padding: M3Spacing.pMd,
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withOpacity(0.45),
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.secondary, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: colorScheme.secondary,
              borderRadius: M3Shape.radiusMd,
            ),
            child: Icon(
              Icons.check_circle_rounded,
              color: colorScheme.onSecondary,
              size: 24.0,
            ),
          ),
          M3Spacing.hGapMD,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تم حفظ واعتماد البيانات نهائياً في النظام (Committed to BigQuery)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  'تم إدراج ${result!.validRows} صف صالح ومزامنة ${result!.autoCreatedStoresCount} فرع لسلسلة "$chainDisplayName" في قاعدة بيانات BigQuery وFirestore بنجاح. أصبحت التحليلات والتقارير التنفيذية ومصفوفة الفروع محدثة الآن.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyChainsEntryBox(ColorScheme colorScheme, ThemeData theme) {
    final isCompact = MediaQuery.sizeOf(context).width < 600.0;
    final inputField = TextField(
      key: const ValueKey('company_new_chain_input'),
      controller: _newChainNameController,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _handleAddCompanyChain(),
      decoration: InputDecoration(
        hintText: 'اسم السلسلة',
        prefixIcon: Icon(
          Icons.add_business_rounded,
          color: colorScheme.primary,
          size: 20.0,
        ),
        isDense: true,
        filled: true,
        fillColor: colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: M3Shape.radiusMd,
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: M3Shape.radiusMd,
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: M3Shape.radiusMd,
          borderSide: BorderSide(color: colorScheme.primary, width: 2.0),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      ),
    );

    final addBtn = FilledButton.icon(
      key: const ValueKey('company_add_chain_button'),
      onPressed: _isAddingChain ? null : _handleAddCompanyChain,
      icon: _isAddingChain
          ? const SizedBox(
              width: 16.0,
              height: 16.0,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            )
          : const Icon(Icons.add_rounded, size: 18.0),
      label: const Text(
        'أضف سلسلة التجزئة',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
      ),
    );

    return Container(
      key: const ValueKey('company_chains_management_box'),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(
            color: colorScheme.outlineVariant.withOpacity(0.7), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: M3Shape.radiusSm,
                ),
                child: Icon(Icons.storefront_rounded,
                    size: 20.0, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: M3SectionTitle(
                  'نظام إدخال سلاسل التجزئة بالشركة (${countRegisteredChains(_availableChains.length)})',
                  maxLines: 3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Text(
            'أضف سلاسل التجزئة التي تتعامل معها شركتك هنا؛ كل سلسلة تضيفها تظهر فوراً في القائمة وفي شريط الأرشيف بالأسفل (الكل / السلاسل)',
            maxLines: 3,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: M3Spacing.xs),
          if (isCompact) ...[
            inputField,
            const SizedBox(height: 8.0),
            SizedBox(width: double.infinity, child: addBtn),
          ] else
            Row(
              children: [
                Expanded(child: inputField),
                const SizedBox(width: 10.0),
                addBtn,
              ],
            ),
          if (_availableChains.isNotEmpty) ...[
            const SizedBox(height: 14.0),
            _buildChainsButtonGroup(colorScheme, theme),
          ],
        ],
      ),
    );
  }

  Widget _buildChainsButtonGroup(ColorScheme colorScheme, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: M3Shape.radiusXl,
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.7),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(4.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < _availableChains.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1.0,
                  height: 28.0,
                  margin: const EdgeInsets.symmetric(horizontal: 2.0),
                  color: colorScheme.outlineVariant.withOpacity(0.6),
                ),
              _buildChainButtonSegment(_availableChains[i], colorScheme, theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChainButtonSegment(
      RetailChainModel c, ColorScheme colorScheme, ThemeData theme) {
    final isSelected = _selectedChain == c.code;
    final shortLabel = _getShortChainTabLabel(c.code);
    final sheetCount = _archiveChainCounts[c.code.toLowerCase()] ?? 0;
    final labelWithCount =
        sheetCount > 0 ? '$shortLabel ($sheetCount)' : shortLabel;

    return Material(
      color: isSelected ? colorScheme.primary : Colors.transparent,
      borderRadius: M3Shape.radiusLg,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('company_chain_btn_${c.code}'),
        onTap: () {
          setState(() {
            _selectedChain = c.code;
            _showChainRequiredError = false;
          });
        },
        hoverColor: isSelected
            ? colorScheme.onPrimary.withOpacity(0.1)
            : colorScheme.surfaceContainerHigh,
        borderRadius: M3Shape.radiusLg,
        child: Tooltip(
          message: c.displayName,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.store_mall_directory_rounded,
                  size: 16.0,
                  color:
                      isSelected ? colorScheme.onPrimary : colorScheme.primary,
                ),
                const SizedBox(width: 8.0),
                Text(
                  labelWithCount,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8.0),
                // Edit bilingual name action
                InkWell(
                  key: ValueKey('edit_company_chain_${c.code}'),
                  onTap: () => _showEditCompanyChainDialog(c),
                  borderRadius: M3Shape.radiusMd,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(
                      Icons.edit_rounded,
                      size: 14.0,
                      color: isSelected
                          ? colorScheme.onPrimary.withOpacity(0.9)
                          : colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 4.0),
                // Delete chain action
                InkWell(
                  key: ValueKey('delete_company_chain_${c.code}'),
                  onTap: () => _handleDeleteCompanyChain(c),
                  borderRadius: M3Shape.radiusMd,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15.0,
                      color: isSelected
                          ? colorScheme.onPrimary.withOpacity(0.9)
                          : colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Persistent Retail Chain Excel Archive Section
  // ---------------------------------------------------------------------------
  Widget _buildExcelArchiveSection(ColorScheme colorScheme, ThemeData theme) {
    final totalAllChains =
        _archiveChainCounts.values.fold<int>(0, (sum, c) => sum + c);
    final chainKeys = <String>{
      ..._availableChains.map((c) => c.code.toLowerCase()),
      ..._archiveChainCounts.keys.map((k) => k.toLowerCase()),
    }.toList();
    final isCompact = MediaQuery.sizeOf(context).width < 600.0;

    const searchHint =
        'ابحث باسم ملف الإكسيل أو السلسلة (مثال: 40-Adco أو Book1)...';
    final searchBox = M3SearchFieldWidth(
      hintText: searchHint,
      child: TextField(
        key: const ValueKey('archive_search_field'),
        controller: _archiveSearchController,
        decoration: InputDecoration(
          hintText: searchHint,
          prefixIcon: const Icon(Icons.search_rounded, size: 18.0),
          suffixIcon: _archiveSearchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18.0),
                  onPressed: () {
                    _archiveSearchController.clear();
                    setState(() => _archiveSearchQuery = '');
                    _loadArchive();
                  },
                )
              : null,
          isDense: true,
          filled: true,
          fillColor: colorScheme.surface,
          border: const OutlineInputBorder(
            borderRadius: M3Shape.radiusMd,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          constraints: const BoxConstraints(maxHeight: M3ToolbarButton.height),
        ),
        onChanged: (v) {
          setState(() => _archiveSearchQuery = v);
          _loadArchive();
        },
      ),
    );

    final yearDropdown = M3Dropdown<String>(
      key: const ValueKey('archive_year_filter_dropdown'),
      value: _archiveYearFilter,
      label: 'تصفية بالسنة',
      fitOptions: true,
      options: [
        const M3DropdownOption('all', 'كل السنوات'),
        for (final y in AvailableYears.current
            .including(int.tryParse(_archiveYearFilter) ?? 0))
          M3DropdownOption('$y', 'سنة $y'),
      ],
      onChanged: (val) {
        setState(() => _archiveYearFilter = val);
        _loadArchive();
      },
    );

    final totalRows = _archivedFiles.fold<int>(0, (s, f) => s + f.rowsIngested);
    final totalRevenue =
        _archivedFiles.fold<double>(0, (s, f) => s + f.totalRevenue);
    final chainCount = chainKeys.length;
    // Empty filter → missing aggregates (not a measured 0). Mirror TM/Compare.
    final hasArchiveRows = _archivedFiles.isNotEmpty;
    final recordsValue = hasArchiveRows
        ? CurrencyFormatter.formatNumber(totalRows)
        : '—';
    final recordsSubtitle = hasArchiveRows
        ? countRecords(totalRows)
        : 'لا توجد ملفات مطابقة للفلتر';
    final revenueValue = hasArchiveRows
        ? CurrencyFormatter.formatCompactEGP(totalRevenue)
        : '—';
    final revenueSubtitle =
        hasArchiveRows ? 'مجموع الملفات الظاهرة' : 'لا توجد مبيعات للعرض';

    return Container(
      key: const ValueKey('excel_upload_archive_section'),
      padding: isCompact ? M3Spacing.pMd : M3Spacing.pLg,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: M3Spacing.xs,
            runSpacing: M3Spacing.xs,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(M3Spacing.xs),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: M3Shape.radiusMd,
                    ),
                    child: Icon(
                      Icons.inventory_2_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 20.0,
                    ),
                  ),
                  const SizedBox(width: M3Spacing.xs),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const M3SectionTitle(
                          'أرشيف شيتات الإكسيل المرفوعة حسب السلاسل',
                          maxLines: 3,
                        ),
                        const SizedBox(height: M3Spacing.xxs),
                        Text(
                          'يتم حفظ وأرشفة كافة شيتات الإكسيل وملفات CSV المرفوعة بنظام السلاسل لتتمكن من استرجاعها وتحميلها في أي وقت',
                          maxLines: 3,
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
                spacing: M3Spacing.xs,
                runSpacing: M3Spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  M3ChipSurface(
                    color: colorScheme.secondaryContainer.withOpacity(0.6),
                    child: Text(
                      countSheets(totalAllChains),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  M3Button.tonal(
                    label: 'تحديث',
                    icon: Icons.refresh_rounded,
                    onPressed: _isLoadingArchive ? null : _loadArchive,
                  ),
                ],
              ),
            ],
          ),
          M3Spacing.gapSM,
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 960
                  ? 4
                  : (constraints.maxWidth >= 580 ? 2 : 1);
              return M3EqualHeightGrid(
                key: const ValueKey('kpi_cards_row'),
                columns: columns,
                spacing: M3Spacing.sm,
                runSpacing: M3Spacing.sm,
                children: [
                  M3SummaryKpiCard(
                    key: const ValueKey('kpi_card_Files'),
                    valueKey: const ValueKey('kpi_value_Files'),
                    title: 'إجمالي الملفات',
                    titleMaxLines: 3,
                    subtitleMaxLines: 3,
                    value: CurrencyFormatter.formatNumber(totalAllChains),
                    subtitle: countFiles(totalAllChains),
                    icon: Icons.inventory_2_rounded,
                    color: colorScheme.primary,
                  ),
                  M3SummaryKpiCard(
                    key: const ValueKey('kpi_card_Chains'),
                    valueKey: const ValueKey('kpi_value_Chains'),
                    title: 'السلاسل',
                    titleMaxLines: 3,
                    subtitleMaxLines: 3,
                    value: CurrencyFormatter.formatNumber(chainCount),
                    subtitle: countRegisteredChains(chainCount),
                    icon: Icons.storefront_rounded,
                    color: colorScheme.secondary,
                  ),
                  M3SummaryKpiCard(
                    key: const ValueKey('kpi_card_Records'),
                    valueKey: const ValueKey('kpi_value_Records'),
                    title: 'إجمالي السجلات',
                    titleMaxLines: 3,
                    subtitleMaxLines: 3,
                    value: recordsValue,
                    subtitle: recordsSubtitle,
                    textValue: !hasArchiveRows,
                    icon: Icons.fact_check_rounded,
                    color: colorScheme.tertiary,
                  ),
                  M3SummaryKpiCard(
                    key: const ValueKey('kpi_card_Revenue'),
                    valueKey: const ValueKey('kpi_value_Revenue'),
                    title: 'إجمالي المبيعات',
                    titleMaxLines: 3,
                    subtitleMaxLines: 3,
                    value: revenueValue,
                    subtitle: revenueSubtitle,
                    textValue: !hasArchiveRows,
                    icon: Icons.payments_rounded,
                    color: colorScheme.primary,
                  ),
                ],
              );
            },
          ),
          M3Spacing.gapSM,
          LayoutBuilder(
            builder: (context, tabConstraints) {
              final tabMax = tabConstraints.maxWidth.isFinite
                  ? tabConstraints.maxWidth
                  : MediaQuery.sizeOf(context).width;
              return Wrap(
                key: const ValueKey('archive_chain_tabs'),
                spacing: M3Spacing.xs,
                runSpacing: M3Spacing.xs,
                children: [
                  _archiveChainTab(
                    value: 'all',
                    label: 'الكل ($totalAllChains)',
                    icon: Icons.apps_rounded,
                    selected: _archiveChainFilter == 'all' ||
                        !chainKeys.contains(_archiveChainFilter),
                    maxWidth: tabMax,
                  ),
                  for (final code in chainKeys)
                    _archiveChainTab(
                      value: code,
                      label:
                          '${_getShortChainTabLabel(code)} (${_archiveChainCounts[code.toLowerCase()] ?? 0})',
                      icon: Icons.storefront_rounded,
                      selected: _archiveChainFilter == code,
                      maxWidth: tabMax,
                    ),
                ],
              );
            },
          ),
          M3Spacing.gapXS,
          M3FlexWrap(
            spacing: M3Spacing.xs,
            runSpacing: M3Spacing.xs,
            children: [
              M3FlexWrapFill(child: searchBox),
              yearDropdown,
            ],
          ),
          M3Spacing.gapSM,
          if (_isLoadingArchive)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_archiveLoadFailed)
            Padding(
              key: const Key('archive_load_failed'),
              padding: const EdgeInsets.all(24.0),
              child: M3ErrorState(
                title: 'مقدرناش نحمّل الأرشيف',
                message:
                    'الخادم مشغول أو الاتصال انقطع. حاول مرة أخرى بعد لحظات.',
                onRetry: _loadArchive,
              ),
            )
          else if (_archivedFiles.isEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
              decoration: BoxDecoration(
                color: M3TableSurface.color(colorScheme),
                borderRadius: M3Shape.radiusLg,
                border: Border.all(
                    color: colorScheme.outlineVariant.withOpacity(0.4)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.folder_off_rounded,
                    size: 48.0,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12.0),
                  Text(
                    'لا توجد ملفات إكسيل مؤرشفة مطابقة للفلتر المحدد حالياً',
                    maxLines: 3,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else if (isCompact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final file in _archivedFiles)
                  _buildCompactArchiveCard(file, colorScheme, theme),
              ],
            )
          else
            Container(
              decoration: BoxDecoration(
                color: M3TableSurface.color(colorScheme),
                borderRadius: M3Shape.radiusLg,
                border: Border.all(
                  color: colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final nameMaxWidth = _archiveFileNameMaxWidth(
                    constraints.maxWidth,
                  );
                  return TableScrollContainer(
                    controller: _archiveSheetsScrollController,
                    showSwipeHint: true,
                    columnFlex: _archiveColumnFlex,
                    pinnedEnd: _buildArchiveActionsColumn(context),
                    child: DataTable(
                      key: const ValueKey('upload_archive_files_table'),
                      columnSpacing: M3Spacing.xs,
                      horizontalMargin: M3Spacing.xs,
                      headingRowHeight: _archiveHeadingHeight,
                      dataRowMinHeight: _archiveRowHeight,
                      dataRowMaxHeight: _archiveRowHeight,
                      headingRowColor: WidgetStatePropertyAll(
                        colorScheme.surfaceContainerHigh.withOpacity(0.5),
                      ),
                      columns: const [
                        DataColumn(
                            headingRowAlignment: MainAxisAlignment.center,
                            label: Text('الملف')),
                        DataColumn(
                            headingRowAlignment: MainAxisAlignment.center,
                            label: Text('السلسلة')),
                        DataColumn(
                            headingRowAlignment: MainAxisAlignment.center,
                            label: Text('الفترة')),
                        DataColumn(
                            headingRowAlignment: MainAxisAlignment.center,
                            label: Text('الفروع'),
                            numeric: true),
                        DataColumn(
                            headingRowAlignment: MainAxisAlignment.center,
                            label: Text('السجلات'),
                            numeric: true),
                        DataColumn(
                            headingRowAlignment: MainAxisAlignment.center,
                            label: Text('المبيعات')),
                        DataColumn(
                            headingRowAlignment: MainAxisAlignment.center,
                            label: Text('تاريخ الرفع')),
                      ],
                      rows: [
                        for (final file in _archivedFiles)
                          _buildArchiveDataRow(
                            file,
                            colorScheme,
                            theme,
                            nameMaxWidth: nameMaxWidth,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactArchiveCard(
    ArchivedExcelFileModel file,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final periodText = file.targetMonth.isNotEmpty && file.targetMonth != 'auto'
        ? '${file.targetMonth} / ${file.targetYear}'
        : 'سنة ${file.targetYear}';
    return Container(
      key: ValueKey('archive_file_card_${file.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: M3Spacing.xs),
      padding: M3Spacing.pSm,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.description_rounded,
                  color: colorScheme.primary, size: 20.0),
              const SizedBox(width: M3Spacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: file.fileName,
                      child: Text(
                        file.fileName,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      _formatFileSize(file.fileSizeBytes),
                      maxLines: 3,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: M3Spacing.xs),
          Wrap(
            spacing: M3Spacing.xs,
            runSpacing: M3Spacing.xxs,
            children: [
              M3ChipSurface(
                color: colorScheme.surfaceContainerHigh,
                child: Text(
                  file.chainNameAr.isNotEmpty
                      ? file.chainNameAr
                      : file.retailChain.toUpperCase(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(periodText,
                  maxLines: 3,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: M3Spacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _archiveActions(file),
          ),
        ],
      ),
    );
  }

  DataRow _buildArchiveDataRow(
    ArchivedExcelFileModel file,
    ColorScheme colorScheme,
    ThemeData theme, {
    required double nameMaxWidth,
  }) {
    final periodText = file.targetMonth.isNotEmpty && file.targetMonth != 'auto'
        ? '${file.targetMonth} / ${file.targetYear}'
        : 'سنة ${file.targetYear}';
    final dateLines = _archiveDateLines(file);

    return DataRow(
      cells: [
        DataCell(
          KeyedSubtree(
            key: ValueKey('archive_file_card_${file.id}'),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: nameMaxWidth),
              child: Row(
                children: [
                  Icon(
                    Icons.description_rounded,
                    color: colorScheme.primary,
                    size: 20.0,
                  ),
                  const SizedBox(width: M3Spacing.xs),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message: file.fileName,
                          child: Text(
                            file.fileName,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.start,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          _formatFileSize(file.fileSizeBytes),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120.0),
            child: M3ChipSurface(
              color: colorScheme.surfaceContainerHigh,
              child: Text(
                file.chainNameAr.isNotEmpty
                    ? file.chainNameAr
                    : file.retailChain.toUpperCase(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        DataCell(_archiveCenteredText(periodText, theme)),
        DataCell(_archiveMetricCell(
          theme,
          key: ValueKey('file_branches_${file.id}'),
          value: UploadPortalScreen.archiveBranchesLabel(file),
          weight: FontWeight.w700,
        )),
        DataCell(_archiveMetricCell(
          theme,
          key: ValueKey('file_rows_${file.id}'),
          value: UploadPortalScreen.archiveRowsLabel(file),
          weight: FontWeight.w700,
        )),
        DataCell(_archiveMetricCell(
          theme,
          key: ValueKey('file_revenue_${file.id}'),
          value: UploadPortalScreen.archiveRevenueLabel(file),
          weight: FontWeight.w800,
          color: colorScheme.primary,
        )),
        DataCell(
          KeyedSubtree(
            key: ValueKey('archive_date_${file.id}'),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final line in dateLines)
                  Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: line == 'آخر استيراد'
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Widget _archiveMetricCell(
    ThemeData theme, {
    Key? key,
    required String? value,
    FontWeight weight = FontWeight.w600,
    Color? color,
  }) {
    if (value == null) {
      return KeyedSubtree(
        key: key,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '—',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              UploadPortalScreen.archiveMissingMetricNote,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return _archiveCenteredText(
      value,
      theme,
      key: key,
      weight: weight,
      color: color,
    );
  }

  static Widget _archiveCenteredText(
    String text,
    ThemeData theme, {
    Key? key,
    FontWeight weight = FontWeight.w600,
    Color? color,
  }) {
    return Text(
      text,
      key: key,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: weight,
        color: color,
      ),
    );
  }

  Widget _buildArchiveActionsColumn(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final divider = Divider.createBorderSide(context, width: 1.0);
    return IntrinsicWidth(
      key: const ValueKey('upload_archive_actions_column'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(
              start: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: _archiveHeadingHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xs),
              color: colorScheme.surfaceContainerHigh.withOpacity(0.5),
              child: Text(
                'الإجراءات',
                style: theme.dataTableTheme.headingTextStyle ??
                    theme.textTheme.titleSmall,
              ),
            ),
            for (final file in _archivedFiles)
              Container(
                height: _archiveRowHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: M3Spacing.xs),
                decoration: BoxDecoration(border: Border(top: divider)),
                child: _archiveActions(file),
              ),
          ],
        ),
      ),
    );
  }

  Widget _archiveActions(ArchivedExcelFileModel file) {
    return ArchiveActionsGroup(
      key: ValueKey('archive_action_group_${file.id}'),
      archiveId: file.id,
      fileName: file.fileName,
      showEdit: false,
      isDeleting: _deletingArchiveId == file.id,
      onEdit: null,
      onDownload:
          (_downloadingArchiveId == file.id || _deletingArchiveId == file.id)
              ? null
              : () => _handleDownloadArchivedFile(file),
      onDelete:
          (_downloadingArchiveId == file.id || _deletingArchiveId == file.id)
              ? null
              : () => _handleDeleteArchivedFile(file),
    );
  }

  Widget _archiveChainTab({
    required String value,
    required String label,
    required IconData icon,
    required bool selected,
    required double maxWidth,
  }) {
    void onPressed() {
      setState(() => _archiveChainFilter = value);
      _loadArchive();
    }

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: M3ToolbarButton.iconSize),
        const SizedBox(width: 8.0),
        Flexible(
          child: Text(
            label,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final button = selected
        ? FilledButton.tonal(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
    return KeyedSubtree(
      key: ValueKey('archive_chain_tab_$value'),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: button,
      ),
    );
  }

  /// Uploaded timestamp, plus last-import date on its own lines so neither
  /// is ellipsised. At most 3 lines.
  static List<String> _archiveDateLines(ArchivedExcelFileModel file) {
    final uploaded = _formatArchiveDateTime(file.uploadedAt);
    if (file.lastIngestedAt.isNotEmpty &&
        file.lastIngestedAt != file.uploadedAt) {
      return [
        uploaded,
        'آخر استيراد',
        _formatArchiveDateTime(file.lastIngestedAt),
      ];
    }
    return [uploaded];
  }

  /// Width reserved for the file-name cell so a long name wraps (up to 3
  /// lines) instead of pushing the table into a horizontal scroll.
  static double _archiveFileNameMaxWidth(double tableAreaWidth) {
    const otherFlexSum = 0.95 + 0.7 + 0.5 + 0.65 + 0.75 + 1.35;
    const nameFlex = 1.9;
    const spacing = M3Spacing.xs;
    const columns = 7;
    final tableWidth = (tableAreaWidth - _archiveActionsWidthEstimate)
        .clamp(0.0, double.infinity);
    final inner = tableWidth - (2 * spacing) - ((columns - 1) * spacing);
    final share = inner * nameFlex / (nameFlex + otherFlexSum);
    // Keep enough room for the 20dp icon + 8dp gap + a few glyphs.
    return share.clamp(120.0, 480.0);
  }

  static String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024.0;
    if (kb < 1024.0) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    return '${mb.toStringAsFixed(2)} MB';
  }

  static String _formatArchiveDateTime(String iso) =>
      UploadPortalScreen.formatArchiveDateTime(iso);
}

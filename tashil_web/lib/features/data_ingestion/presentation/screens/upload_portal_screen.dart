import 'package:flutter/material.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_motion.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/m3_segmented_button_group.dart';
import '../widgets/ai_analysis_progress_card.dart';
import '../widgets/anomaly_resolution_table.dart';
import '../widgets/dropzone_file_picker.dart';

/// UploadPortalScreen serves as the entry point for uploading retail files
/// and managing the retail-chain-organized Excel/CSV archive.
class UploadPortalScreen extends StatefulWidget {
  final ApiClient apiClient;

  const UploadPortalScreen({
    super.key,
    required this.apiClient,
  });

  @override
  State<UploadPortalScreen> createState() => _UploadPortalScreenState();
}

class _UploadPortalScreenState extends State<UploadPortalScreen> {
  bool isProcessing = false;
  bool isCommitting = false;
  IngestionResultModel? result;
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
  String? _downloadingArchiveId;
  String? _deletingArchiveId;
  final TextEditingController _archiveSearchController = TextEditingController();

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
    final year = _selectedYear == 'auto' ? '2026' : _selectedYear;
    final month = _selectedMonth == 'auto' ? '01' : _selectedMonth.padLeft(2, '0');
    return '$year-$month-15';
  }

  String _describeTargetPeriod() {
    if (_selectedYear == 'auto' && _selectedMonth == 'auto') {
      return 'اكتشاف تلقائي من الشيت (Auto)';
    }
    final yLabel = _selectedYear == 'auto' ? '2026' : _selectedYear;
    final mLabel = _selectedMonth == 'auto'
        ? 'يناير (01)'
        : (_monthNamesAr[_selectedMonth] ?? _selectedMonth);
    return '$mLabel • سنة $yLabel (${_buildEffectivePeriodDate()})';
  }

  @override
  void initState() {
    super.initState();
    _lastTenantId = widget.apiClient.tenantId;
    _selectedTenant = ApiClient.normalizeDataTenantSlug(widget.apiClient.tenantId);
    _loadContext();
    _loadArchive();
  }

  @override
  void dispose() {
    _newChainNameController.dispose();
    _archiveSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    setState(() => _isLoadingContext = true);
    final chains = await widget.apiClient.getRetailChains(targetTenant: _selectedTenant);
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
          c.displayName.trim().toLowerCase() == formattedBilingual.toLowerCase(),
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
      final refreshed = await widget.apiClient.getRetailChains(targetTenant: _selectedTenant);
      if (mounted) {
        setState(() {
          _availableChains = refreshed.isNotEmpty
              ? refreshed
              : [..._availableChains, created];
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
                child: Icon(Icons.edit_note_rounded, color: colorScheme.onPrimaryContainer, size: 22.0),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('تعديل سلسلة التجزئة', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text('Edit Retail Chain (Arabic / English)', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
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
                      labelText: 'اسم السلسلة بالعربية (Arabic)',
                      hintText: 'مثال: الوكالة، أسواق فتح الله...',
                      prefixIcon: const Icon(Icons.language_rounded, size: 18.0),
                      border: const OutlineInputBorder(borderRadius: M3Shape.radiusMd),
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
                      labelText: 'اسم السلسلة بالإنجليزية (English)',
                      hintText: 'e.g. El Wakala, Fathalla Market...',
                      prefixIcon: const Icon(Icons.translate_rounded, size: 18.0),
                      border: const OutlineInputBorder(borderRadius: M3Shape.radiusMd),
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
    setState(() => _isLoadingArchive = true);
    final resp = await widget.apiClient.getUploadedFilesArchive(
      chain: _archiveChainFilter == 'all' ? null : _archiveChainFilter,
      year: _archiveYearFilter == 'all' ? null : _archiveYearFilter,
      searchQuery: _archiveSearchQuery.trim().isEmpty ? null : _archiveSearchQuery.trim(),
      targetTenant: _selectedTenant,
    );
    if (mounted) {
      setState(() {
        _archivedFiles = resp.files;
        _archiveChainCounts = resp.chainCounts;
        _isLoadingArchive = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant UploadPortalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient ||
        _lastTenantId != widget.apiClient.tenantId) {
      setState(() {
        _lastTenantId = widget.apiClient.tenantId;
        _selectedTenant = ApiClient.normalizeDataTenantSlug(widget.apiClient.tenantId);
        _selectedChain = null;
        _showChainRequiredError = false;
        isProcessing = false;
        isCommitting = false;
        result = null;
        _stagedFileKey = null;
        _processedFiles.clear();
      });
      _loadContext();
      _loadArchive();
    }
  }

  String _getChainDisplayName(String? code) {
    if (code == null || code.isEmpty) return '-- اختر سلسلة التجزئة المستهدفة --';
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

    final activeChain = _selectedChain!;
    final effectivePeriodDate = _buildEffectivePeriodDate();
    final fileKey = '$filename-${bytes.length}-$_selectedTenant-$activeChain-${effectivePeriodDate ?? 'auto'}';
    if (_processedFiles.contains(fileKey)) {
      await M3Feedback.showDuplicateWarning(
        context,
        title: 'تم رفض المعالجة: ملف مكرر',
        message: 'تم استيعاب هذا الملف ومطابقة معاملاته في قاعدة بيانات BigQuery مسبقاً. تم رفض إعادة المعالجة لمنع تكرار البيانات المالية.',
        duplicateIdentifier: 'اسم الملف: $filename (سلسلة: $activeChain)',
      );
      return;
    }

    setState(() {
      _showChainRequiredError = false;
      isProcessing = true;
      result = null;
      _stagedFileKey = fileKey;
    });

    try {
      final res = await widget.apiClient.uploadFile(
        filename,
        bytes,
        targetChain: activeChain,
        targetTenant: _selectedTenant,
        periodDate: effectivePeriodDate,
        dryRun: true,
      );
      widget.apiClient.recordAuditLog(
        action: 'INGEST_ANALYZE',
        resource: filename,
        details: 'تحليل أولي لملف $filename لسلسلة $activeChain وشركة $_selectedTenant (${res.validRows} صف صالح • ${res.autoCreatedStoresCount} فرع) - قيد المراجعة',
      );
      await _loadArchive();
      if (mounted) {
        setState(() {
          result = res;
          isProcessing = false;
        });

        if (res.chainMismatchDetected) {
          final discoveredName = res.suggestedChainName ?? res.discoveredRetailer;
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
    final newName = result!.suggestedChainName ?? _getChainDisplayName(newChain);
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
            hasMismatch ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
            color: hasMismatch ? Colors.amber.shade800 : colorScheme.primary,
            size: 32.0,
          ),
          title: Text(
            'تأكيد اعتماد وحفظ البيانات',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
                      border: Border.all(color: Colors.amber.shade700.withOpacity(0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 22.0),
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
                      _buildDialogRow('سلسلة التجزئة:', chainDisplayName, theme),
                      const Divider(height: 12.0),
                      _buildDialogRow('الفترة الزمنية:', _describeTargetPeriod(), theme),
                      const Divider(height: 12.0),
                      _buildDialogRow('السجلات الصالحة:', '${result!.validRows} صف', theme),
                      const Divider(height: 12.0),
                      _buildDialogRow('الفروع المكتشفة:', '${result!.autoCreatedStoresCount} فرع', theme),
                      const Divider(height: 12.0),
                      _buildDialogRow('إجمالي المبيعات:', CurrencyFormatter.formatCompactEGP(result!.totalRevenue), theme),
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
      final committedResult = await widget.apiClient.commitStagedUpload(
        batchId: result!.batchId,
        targetChain: activeChain,
        targetTenant: _selectedTenant,
        periodDate: _buildEffectivePeriodDate(),
      );

      widget.apiClient.recordAuditLog(
        action: 'INGEST_COMMIT',
        resource: result!.filename,
        details: 'حفظ واعتماد بيانات ملف ${result!.filename} لسلسلة $activeChain (${committedResult.validRows} صف)',
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
      }
    } catch (e) {
      if (mounted) {
        setState(() => isCommitting = false);
        M3Feedback.showError(context, 'فشل حفظ واعتماد البيانات: $e');
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
        details: 'تحميل شيت الإكسيل المؤرشف ${file.fileName} لسلسلة ${file.chainNameAr}',
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
        icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 32.0),
        title: const Text('حذف شيت الإكسيل والبيانات المستوردة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل أنت متأكد من رغبتك في حذف ملف "${file.fileName}"؟',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10.0),
            Text(
              'سيتم حذف هذا الشيت من التخزين (Storage) ومسح كافة البيانات والسجلات التحليلية المستوردة منه من قاعدة البيانات نهائياً.',
              style: TextStyle(
                color: Theme.of(dialogCtx).colorScheme.onSurfaceVariant,
                fontSize: 13.0,
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
                  Icon(Icons.warning_amber_rounded, size: 20.0, color: Colors.red.shade800),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      'عند حذف جميع الشيتات المرفوعة، سيتم تصفير كافة أرقام المبيعات والتحليلات بالكامل.',
                      style: TextStyle(
                        fontSize: 12.0,
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
            child: const Text('حذف (Delete)'),
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
        details: 'حذف شيت الإكسيل المؤرشف ${file.fileName} لسلسلة ${file.chainNameAr} ومسح سجلاته',
      );
      if (mounted) {
        if (ok) {
          setState(() {
            _archivedFiles = _archivedFiles.where((f) => f.id != file.id && f.fileName != file.fileName).toList();
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
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(width: 8.0),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
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
              titleEn: 'Smart Data Ingestion Portal',
              subtitleAr: 'مبيعات الفروع وأرشفة شيتات الإكسيل حسب السلاسل',
              actions: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: M3Shape.radiusLg,
                  border: Border.all(color: colorScheme.primary.withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.layers_rounded, size: 16.0, color: colorScheme.primary),
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
                    Icon(Icons.lock_person_rounded, color: colorScheme.error, size: 20.0),
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

            M3Spacing.gapMD,

            // Staging & Commit Status Transitions (M3 Fade Through)
            M3FadeThroughSwitcher(
              child: result == null
                  ? const SizedBox.shrink(key: ValueKey('upload_idle'))
                  : Column(
                      key: ValueKey('upload_status_${result!.isStaged}_${result!.isCommitted}'),
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
    final hasSelectedChain =
        _selectedChain != null && _availableChains.any((c) => c.code == _selectedChain);
    final chainName = hasSelectedChain ? _getChainDisplayName(_selectedChain) : null;
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
                    Text(
                      'سياق استيعاب البيانات وتوجيه الذكاء الاصطناعي (Ingestion Context)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'حدد سلسلة التجزئة والسنة/الشهر المستهدف لضمان مطابقة الفروع وتوجيه البيانات في التاريخ الصحيح',
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
          M3Spacing.gapMD,
          LayoutBuilder(
            builder: (context, constraints) {
              final chainBorderColor = _showChainRequiredError
                  ? colorScheme.error
                  : colorScheme.outline;
              final chainDropdown = DropdownButtonFormField<String>(
                key: const ValueKey('ingestion_retail_chain_dropdown'),
                isExpanded: true,
                focusColor: Colors.transparent,
                dropdownColor: colorScheme.surfaceContainerHigh,
                borderRadius: M3Shape.radiusMd,
                icon: Icon(
                  Icons.arrow_drop_down_rounded,
                  color: _showChainRequiredError
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
                value: hasSelectedChain ? _selectedChain : null,
                hint: Text(
                  '-- اختر سلسلة التجزئة المستهدفة --',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _showChainRequiredError
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                decoration: InputDecoration(
                  labelText: 'سلسلة التجزئة المستهدفة (Target Retail Chain) *',
                  labelStyle: _showChainRequiredError
                      ? TextStyle(
                          color: colorScheme.error,
                          fontWeight: FontWeight.bold,
                        )
                      : null,
                  prefixIcon: Icon(
                    Icons.store_mall_directory_rounded,
                    color: _showChainRequiredError ? colorScheme.error : null,
                  ),
                  filled: true,
                  fillColor: _showChainRequiredError
                      ? colorScheme.errorContainer.withOpacity(0.3)
                      : colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: M3Shape.radiusMd,
                    borderSide: BorderSide(
                      color: chainBorderColor,
                      width: _showChainRequiredError ? 2.0 : 1.0,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: M3Shape.radiusMd,
                    borderSide: BorderSide(
                      color: chainBorderColor,
                      width: _showChainRequiredError ? 2.0 : 1.0,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: M3Shape.radiusMd,
                    borderSide: BorderSide(
                      color: _showChainRequiredError
                          ? colorScheme.error
                          : colorScheme.primary,
                      width: 2.0,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                ),
                items: _availableChains.map((c) {
                  final label = c.storeCount > 0 ? '${c.displayName} (${c.storeCount} فرع)' : c.displayName;
                  return DropdownMenuItem<String>(
                    value: c.code,
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedChain = val;
                      _showChainRequiredError = false;
                    });
                  }
                },
              );

              final yearDropdown = DropdownButtonFormField<String>(
                key: const ValueKey('ingestion_year_dropdown'),
                isExpanded: true,
                focusColor: Colors.transparent,
                dropdownColor: colorScheme.surfaceContainerHigh,
                borderRadius: M3Shape.radiusMd,
                icon: Icon(
                  Icons.arrow_drop_down_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
                value: _selectedYear,
                decoration: InputDecoration(
                  labelText: 'سنة البيانات (Target Year)',
                  prefixIcon: const Icon(Icons.calendar_today_rounded),
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: const OutlineInputBorder(
                    borderRadius: M3Shape.radiusMd,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
                ),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('تلقائي من الشيت (Auto)', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: '2026', child: Text('سنة 2026 (26)', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: '2025', child: Text('سنة 2025 (25)', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: '2024', child: Text('سنة 2024 (24)', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedYear = val);
                  }
                },
              );

              final monthDropdown = DropdownButtonFormField<String>(
                key: const ValueKey('ingestion_month_dropdown'),
                isExpanded: true,
                focusColor: Colors.transparent,
                dropdownColor: colorScheme.surfaceContainerHigh,
                borderRadius: M3Shape.radiusMd,
                icon: Icon(
                  Icons.arrow_drop_down_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
                value: _selectedMonth,
                decoration: InputDecoration(
                  labelText: 'الشهر المستهدف (Target Month)',
                  prefixIcon: const Icon(Icons.date_range_rounded),
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: const OutlineInputBorder(
                    borderRadius: M3Shape.radiusMd,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
                ),
                items: [
                  const DropdownMenuItem(value: 'auto', child: Text('تلقائي (Auto)', overflow: TextOverflow.ellipsis)),
                  ..._monthNamesAr.entries.map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedMonth = val);
                  }
                },
              );

              if (constraints.maxWidth >= 820) {
                return Row(
                  children: [
                    Expanded(flex: 5, child: chainDropdown),
                    M3Spacing.hGapSM,
                    Expanded(flex: 3, child: yearDropdown),
                    M3Spacing.hGapSM,
                    Expanded(flex: 3, child: monthDropdown),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  chainDropdown,
                  M3Spacing.gapSM,
                  Row(
                    children: [
                      Expanded(child: yearDropdown),
                      M3Spacing.hGapSM,
                      Expanded(child: monthDropdown),
                    ],
                  ),
                ],
              );
            },
          ),
          M3Spacing.gapSM,
          // AI Context Badge
          Container(
            key: const ValueKey('ai_ingestion_context_status_bar'),
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer.withOpacity(0.55),
                        borderRadius: M3Shape.radiusSm,
                        border: Border.all(color: colorScheme.tertiary.withOpacity(0.45)),
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
    final suggestedName = result!.suggestedChainName ?? result!.suggestedChain ?? result!.discoveredRetailer;
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
        border: Border.all(color: colorScheme.primary.withOpacity(0.4), width: 1.5),
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
              Icon(Icons.verified_rounded, color: colorScheme.primary, size: 24.0),
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
          M3ActionButtonGroup(
            actions: [
              M3ActionItem(
                label: 'إلغاء',
                icon: Icons.delete_outline_rounded,
                isDestructive: true,
                onPressed: isCommitting ? null : _handleDiscardData,
              ),
              M3ActionItem(
                label: 'اعتماد البيانات',
                icon: Icons.check_circle_rounded,
                isPrimary: true,
                isLoading: isCommitting,
                onPressed: isCommitting ? null : _handleCommitData,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommittedSuccessBanner(ColorScheme colorScheme, ThemeData theme) {
    final chainDisplayName = _getChainDisplayName(_selectedChain ?? result!.retailerDetected);
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
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
        shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusMd),
      ),
    );

    return Container(
      key: const ValueKey('company_chains_management_box'),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.7), width: 1.0),
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
                child: Icon(Icons.storefront_rounded, size: 20.0, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Text(
                  'نظام إدخال سلاسل التجزئة بالشركة (${_availableChains.length} سلسلة مسجلة)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Text(
            'أضف سلاسل التجزئة التي تتعامل معها شركتك هنا؛ كل سلسلة تضيفها تظهر فوراً في القائمة وفي شريط الأرشيف بالأسفل (الكل / السلاسل)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12.0),
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

  Widget _buildChainButtonSegment(RetailChainModel c, ColorScheme colorScheme, ThemeData theme) {
    final isSelected = _selectedChain == c.code;
    final shortLabel = _getShortChainTabLabel(c.code);
    final sheetCount = _archiveChainCounts[c.code.toLowerCase()] ?? 0;
    final labelWithCount = sheetCount > 0 ? '$shortLabel ($sheetCount)' : shortLabel;

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
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.store_mall_directory_rounded,
                  size: 16.0,
                  color: isSelected ? colorScheme.onPrimary : colorScheme.primary,
                ),
                const SizedBox(width: 8.0),
                Text(
                  labelWithCount,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
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
                      color: isSelected ? colorScheme.onPrimary.withOpacity(0.9) : colorScheme.primary,
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
                      color: isSelected ? colorScheme.onPrimary.withOpacity(0.9) : colorScheme.error,
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
    final totalAllChains = _archiveChainCounts.values.fold<int>(0, (sum, c) => sum + c);
    final chainKeys = <String>{
      ..._availableChains.map((c) => c.code.toLowerCase()),
      ..._archiveChainCounts.keys.map((k) => k.toLowerCase()),
    }.toList();
    final isCompact = MediaQuery.sizeOf(context).width < 600.0;

    final searchBox = TextField(
      key: const ValueKey('archive_search_field'),
      controller: _archiveSearchController,
      decoration: InputDecoration(
        hintText: 'ابحث باسم ملف الإكسيل أو السلسلة (مثال: 40-Adco أو Book1)...',
        prefixIcon: const Icon(Icons.search_rounded, size: 20.0),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      ),
      onChanged: (v) {
        setState(() => _archiveSearchQuery = v);
        _loadArchive();
      },
    );

    final yearDropdown = DropdownButtonFormField<String>(
      key: const ValueKey('archive_year_filter_dropdown'),
      value: _archiveYearFilter,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'تصفية بالسنة',
        isDense: true,
        filled: true,
        fillColor: colorScheme.surface,
        border: const OutlineInputBorder(
          borderRadius: M3Shape.radiusMd,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      ),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('كل السنوات')),
        DropdownMenuItem(value: '2026', child: Text('سنة 2026')),
        DropdownMenuItem(value: '2025', child: Text('سنة 2025')),
        DropdownMenuItem(value: '2024', child: Text('سنة 2024')),
      ],
      onChanged: (val) {
        if (val != null) {
          setState(() => _archiveYearFilter = val);
          _loadArchive();
        }
      },
    );

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
          // Section Header
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: M3Spacing.md,
            runSpacing: M3Spacing.sm,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10.0),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: M3Shape.radiusMd,
                    ),
                    child: Icon(
                      Icons.inventory_2_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 24.0,
                    ),
                  ),
                  M3Spacing.hGapSM,
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'أرشيف شيتات الإكسيل المرفوعة حسب السلاسل',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          'يتم حفظ وأرشفة كافة شيتات الإكسيل وملفات CSV المرفوعة بنظام السلاسل لتتمكن من استرجاعها وتحميلها في أي وقت',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer.withOpacity(0.6),
                      borderRadius: M3Shape.radiusLg,
                    ),
                    child: Text(
                      'إجمالي الملفات: $totalAllChains شيت',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  M3Button.tonal(
                    label: 'تحديث',
                    icon: Icons.refresh_rounded,
                    onPressed: _isLoadingArchive ? null : _loadArchive,
                  ),
                ],
              ),
            ],
          ),

          M3Spacing.gapMD,

          // Retail Chain Filter Segmented Group
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: M3SegmentedButtonGroup<String>(
              segments: [
                M3SegmentItem(
                  value: 'all',
                  label: 'الكل ($totalAllChains)',
                  icon: Icons.apps_rounded,
                ),
                ...chainKeys.map((code) {
                  final count = _archiveChainCounts[code.toLowerCase()] ?? 0;
                  final arName = _getShortChainTabLabel(code);
                  return M3SegmentItem(
                    value: code,
                    label: '$arName ($count)',
                    icon: Icons.storefront_rounded,
                  );
                }),
              ],
              selectedValue: chainKeys.contains(_archiveChainFilter) ? _archiveChainFilter : 'all',
              onSelectionChanged: (val) {
                setState(() => _archiveChainFilter = val);
                _loadArchive();
              },
            ),
          ),

          M3Spacing.gapSM,

          // Search & Year filter bar (Stacked on Compact mobile, Row on Tablet/Desktop)
          if (isCompact) ...[
            searchBox,
            const SizedBox(height: 8.0),
            yearDropdown,
          ] else
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: searchBox,
                ),
                M3Spacing.hGapSM,
                SizedBox(
                  width: 170.0,
                  child: yearDropdown,
                ),
              ],
            ),

          M3Spacing.gapMD,

          if (_isLoadingArchive)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_archivedFiles.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: M3Shape.radiusLg,
                border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.4)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.folder_off_rounded,
                    size: 40.0,
                    color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    'لا توجد ملفات إكسيل مؤرشفة مطابقة للفلتر المحدد حالياً',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _archivedFiles
                  .map((file) => _buildArchivedFileCard(file, colorScheme, theme))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildArchivedFileCard(
    ArchivedExcelFileModel file,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final isExcel = file.fileName.toLowerCase().endsWith('.xlsx') ||
        file.fileName.toLowerCase().endsWith('.xls');
    final chainColor = _chainBadgeColor(file.retailChain, colorScheme);
    final isDownloading = _downloadingArchiveId == file.id;
    final isDeleting = _deletingArchiveId == file.id;

    return Container(
      key: ValueKey('archive_file_card_${file.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: M3Spacing.pMd,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.55)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;

          final fileInfoWidget = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: isExcel
                      ? colorScheme.secondaryContainer
                      : colorScheme.primaryContainer,
                  borderRadius: M3Shape.radiusMd,
                ),
                child: Icon(
                  isExcel ? Icons.table_view_rounded : Icons.description_rounded,
                  color: isExcel
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onPrimaryContainer,
                  size: 26.0,
                ),
              ),
              M3Spacing.hGapSM,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          file.fileName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
                          decoration: BoxDecoration(
                            color: chainColor.withOpacity(0.14),
                            borderRadius: M3Shape.radiusLg,
                            border: Border.all(color: chainColor.withOpacity(0.45)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront_rounded, size: 13.0, color: chainColor),
                              const SizedBox(width: 4.0),
                              Text(
                                file.chainNameAr,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: chainColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer.withOpacity(0.5),
                            borderRadius: M3Shape.radiusSm,
                          ),
                          child: Text(
                            'سنة ${file.targetYear}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (file.fileType == 'product_master')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer.withOpacity(0.6),
                              borderRadius: M3Shape.radiusSm,
                            ),
                            child: Text(
                              'كارتة الأصناف والأسعار (Product Master)',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6.0),
                    Wrap(
                      spacing: 14.0,
                      runSpacing: 4.0,
                      children: [
                        _buildArchiveMetaChip(
                          Icons.account_tree_rounded,
                          'عدد الفروع: ${file.branchesCount} فرع',
                          theme,
                        ),
                        _buildArchiveMetaChip(
                          Icons.fact_check_rounded,
                          'عدد السجلات: ${file.rowsIngested} سجل',
                          theme,
                        ),
                        _buildArchiveMetaChip(
                          Icons.payments_rounded,
                          'إجمالي المبيعات: ${CurrencyFormatter.formatCompactEGP(file.totalRevenue)}',
                          theme,
                        ),
                        _buildArchiveMetaChip(
                          Icons.sd_storage_rounded,
                          'حجم الملف: ${_formatFileSize(file.fileSizeBytes)}',
                          theme,
                        ),
                        _buildArchiveMetaChip(
                          Icons.schedule_rounded,
                          'تاريخ الرفع: ${_formatArchiveDate(file.uploadedAt)}',
                          theme,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          // Connected M3 Button Group for Download + Delete (as requested by user)
          final actionsWidget = M3ActionButtonGroup(
            key: ValueKey('archive_action_group_${file.id}'),
            actions: [
              M3ActionItem(
                label: 'Download',
                icon: Icons.download_rounded,
                isPrimary: true,
                isLoading: isDownloading,
                onPressed: (isDownloading || isDeleting)
                    ? null
                    : () => _handleDownloadArchivedFile(file),
              ),
              M3ActionItem(
                label: 'Delete',
                icon: Icons.delete_outline_rounded,
                isDestructive: true,
                isLoading: isDeleting,
                onPressed: (isDownloading || isDeleting)
                    ? null
                    : () => _handleDeleteArchivedFile(file),
              ),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                fileInfoWidget,
                const SizedBox(height: 12.0),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: actionsWidget,
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: fileInfoWidget),
              const SizedBox(width: 16.0),
              actionsWidget,
            ],
          );
        },
      ),
    );
  }

  static Widget _buildArchiveMetaChip(IconData icon, String text, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14.0, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4.0),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  static Color _chainBadgeColor(String chainCode, ColorScheme colorScheme) {
    switch (chainCode.trim().toLowerCase()) {
      case 'fathalla':
        return colorScheme.primary;
      case 'gomla':
        return colorScheme.secondary;
      case 'carrefour':
        return colorScheme.tertiary;
      default:
        return colorScheme.primary;
    }
  }

  static String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024.0;
    if (kb < 1024.0) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    return '${mb.toStringAsFixed(2)} MB';
  }

  static String _formatArchiveDate(String iso) {
    if (iso.isEmpty) return '2026-03-08';
    if (iso.length >= 10) return iso.substring(0, 10);
    return iso;
  }
}

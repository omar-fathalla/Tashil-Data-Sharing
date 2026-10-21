import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/table_scroll_container.dart';

/// TargetManagementPanel provides a unified Target entry, Excel upload, and
/// real-time Actual vs. Target achievement comparison experience for both
/// Sell-Out (مبيعات الكاشير) and Sell-In (توريدات السلاسل).
class TargetManagementPanel extends StatefulWidget {
  final ApiClient apiClient;
  final String targetType; // 'sell_out' or 'sell_in'

  const TargetManagementPanel({
    super.key,
    required this.apiClient,
    required this.targetType,
  });

  @override
  State<TargetManagementPanel> createState() => _TargetManagementPanelState();
}

class _TargetManagementPanelState extends State<TargetManagementPanel> {
  bool _isLoading = true;
  bool _isUploading = false;
  String _selectedChain = 'all';
  int _selectedYear = 0; // 0 = All Years
  TargetsSummaryModel? _summary;
  List<RetailChainModel> _companyChains = const [];

  static const List<({int month, String labelAr, String labelEn})> _months = [
    (month: 0, labelAr: 'إجمالي السنة (كل الشهور)', labelEn: 'Full Year'),
    (month: 1, labelAr: 'يناير (01)', labelEn: 'January'),
    (month: 2, labelAr: 'فبراير (02)', labelEn: 'February'),
    (month: 3, labelAr: 'مارس (03)', labelEn: 'March'),
    (month: 4, labelAr: 'أبريل (04)', labelEn: 'April'),
    (month: 5, labelAr: 'مايو (05)', labelEn: 'May'),
    (month: 6, labelAr: 'يونيو (06)', labelEn: 'June'),
    (month: 7, labelAr: 'يوليو (07)', labelEn: 'July'),
    (month: 8, labelAr: 'أغسطس (08)', labelEn: 'August'),
    (month: 9, labelAr: 'سبتمبر (09)', labelEn: 'September'),
    (month: 10, labelAr: 'أكتوبر (10)', labelEn: 'October'),
    (month: 11, labelAr: 'نوفمبر (11)', labelEn: 'November'),
    (month: 12, labelAr: 'ديسمبر (12)', labelEn: 'December'),
  ];

  bool get _isSellIn => widget.targetType == 'sell_in';

  String get _unitLabelAr => _isSellIn ? 'كرتونة' : 'وحدة';
  String get _unitLabelEn => _isSellIn ? 'Cases' : 'Units';

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    try {
      final chains = await widget.apiClient.getRetailChains();
      if (mounted) {
        setState(() => _companyChains = chains);
      }
    } catch (_) {}
    await _loadTargets();
  }

  Future<void> _loadTargets() async {
    setState(() => _isLoading = true);
    final res = await widget.apiClient.getTargetsSummary(
      targetType: widget.targetType,
      chain: _selectedChain == 'all' ? null : _selectedChain,
      year: _selectedYear > 0 ? _selectedYear : null,
    );
    if (mounted) {
      setState(() {
        _summary = res;
        _isLoading = false;
      });
    }
  }

  List<({String code, String label})> get _chainOptions {
    final opts = <({String code, String label})>[
      (code: 'all', label: 'All Chains'),
      (code: 'fathalla', label: 'Fathalla Market'),
      (code: 'gomla', label: 'Gomla Market'),
      (code: 'beet-elgomla', label: 'Beet El Gomla'),
      (code: 'chain-1080314', label: 'El Wakala'),
      (code: 'carrefour', label: 'Carrefour'),
      (code: 'spinneys', label: 'Spinneys'),
    ];
    final seen = opts.map((e) => e.code.toLowerCase()).toSet();
    for (final c in _companyChains) {
      final code = c.code.trim().toLowerCase();
      if (code.isNotEmpty && !seen.contains(code)) {
        seen.add(code);
        opts.add((code: code, label: c.displayName));
      }
    }
    return opts;
  }

  Future<void> _openTargetFormDialog({TargetComparisonModel? existing}) async {
    String chain = existing?.retailerChain ?? (_selectedChain != 'all' ? _selectedChain : 'fathalla');
    int year = existing?.year ?? (_selectedYear > 0 ? _selectedYear : 2025);
    int month = existing?.month ?? 0;
    final branchCtrl = TextEditingController(
      text: existing != null && existing.branchName != 'كل الفروع' ? existing.branchName : '',
    );
    final categoryCtrl = TextEditingController(
      text: existing != null && existing.category != 'كل الفئات' ? existing.category : '',
    );
    final revCtrl = TextEditingController(
      text: existing != null && existing.targetRevenueEgp > 0
          ? existing.targetRevenueEgp.toStringAsFixed(0)
          : '',
    );
    final unitsCtrl = TextEditingController(
      text: existing != null && existing.targetUnits > 0
          ? existing.targetUnits.toStringAsFixed(0)
          : '',
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colorScheme = theme.colorScheme;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24.0),
                ),
                title: Row(
                  children: [
                    Icon(
                      Icons.track_changes_rounded,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 10.0),
                    Expanded(
                      child: Text(
                        existing == null
                            ? (_isSellIn
                                ? 'إضافة Target جديد للتوريد (Sell-In)'
                                : 'إضافة Target جديد للمبيعات (Sell-Out)')
                            : 'تعديل المستهدف (Target)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 520.0,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          value: _chainOptions.any((c) => c.code == chain) ? chain : 'fathalla',
                          decoration: const InputDecoration(
                            labelText: 'سلسلة التجزئة (Retail Chain)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _chainOptions
                              .map(
                                (c) => DropdownMenuItem<String>(
                                  value: c.code,
                                  child: Text(c.label),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setDialogState(() => chain = v);
                          },
                        ),
                        const SizedBox(height: 12.0),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: year,
                                decoration: const InputDecoration(
                                  labelText: 'السنة (Year)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: const [2026, 2025, 2024]
                                    .map(
                                      (yr) => DropdownMenuItem<int>(
                                        value: yr,
                                        child: Text('$yr'),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) setDialogState(() => year = v);
                                },
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: month,
                                decoration: const InputDecoration(
                                  labelText: 'الشهر (Month)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: _months
                                    .map(
                                      (m) => DropdownMenuItem<int>(
                                        value: m.month,
                                        child: Text(m.labelAr),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) setDialogState(() => month = v);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12.0),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: revCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'القيمة المستهدفة بالجنيه (Target EGP) *',
                                  hintText: 'مثال: 10000000',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              child: TextField(
                                controller: unitsCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'الكمية المستهدفة ($_unitLabelAr)',
                                  hintText: 'مثال: 120000',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
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
                                controller: branchCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'الفرع / الإقليم (اختياري)',
                                  hintText: 'اتركه فارغاً لكل الفروع',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              child: TextField(
                                controller: categoryCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'الفئة / العلامة (اختياري)',
                                  hintText: 'اتركه فارغاً لكل الفئات',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12.0),
                        TextField(
                          controller: notesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظات (اختياري)',
                            hintText: 'مثال: مستهدف الربع الأول أو حملة رمضان',
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
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.save_rounded, size: 18.0),
                    label: const Text('حفظ الـ Target'),
                    onPressed: () async {
                      final rev = double.tryParse(
                            revCtrl.text.replaceAll(',', '').trim(),
                          ) ??
                          0.0;
                      final units = double.tryParse(
                            unitsCtrl.text.replaceAll(',', '').trim(),
                          ) ??
                          0.0;
                      if (rev <= 0 && units <= 0) {
                        M3Feedback.showError(
                          context,
                          'يرجى إدخال القيمة المستهدفة بالجنيه أو الكمية المستهدفة',
                        );
                        return;
                      }
                      Navigator.pop(ctx, true);
                      try {
                        await widget.apiClient.upsertTarget(
                          id: existing?.id,
                          targetType: widget.targetType,
                          retailerChain: chain,
                          year: year,
                          month: month,
                          branchName: branchCtrl.text.trim().isEmpty
                              ? 'كل الفروع'
                              : branchCtrl.text.trim(),
                          category: categoryCtrl.text.trim().isEmpty
                              ? 'كل الفئات'
                              : categoryCtrl.text.trim(),
                          targetRevenueEgp: rev,
                          targetUnits: units,
                          notes: notesCtrl.text.trim(),
                        );
                        if (!mounted) return;
                        M3Feedback.showSuccess(
                          context,
                          'تم حفظ الـ Target وتحديث نسبة التحقيق بنجاح',
                        );
                        await _loadTargets();
                      } catch (e) {
                        if (!mounted) return;
                        M3Feedback.showError(context, 'تعذر حفظ المستهدف: $e');
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (saved == true) {
      await _loadTargets();
    }
  }

  Future<void> _pickAndUploadTargetExcel() async {
    final picked = await WebFileHelper.pickFile(accept: '.xlsx,.xls,.csv');
    if (picked == null || picked.bytes.isEmpty) return;

    setState(() => _isUploading = true);
    try {
      final res = await widget.apiClient.uploadTargetsFile(
        filename: picked.name,
        fileBytes: picked.bytes,
        targetType: widget.targetType,
        chain: _selectedChain != 'all' ? _selectedChain : 'fathalla',
        year: _selectedYear > 0 ? _selectedYear : 2025,
      );
      if (!mounted) return;
      M3Feedback.showSuccess(
        context,
        'تم استيراد ${res.rowsImported} مستهدف من الملف (${picked.name}) بنجاح',
      );
      await _loadTargets();
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'تعذر رفع ملف المستهدفات: $e');
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _downloadTargetTemplate() {
    final headers = [
      'سلسلة التجزئة (Chain)',
      'السنة (Year)',
      'الشهر (Month)',
      'الفرع (Branch)',
      'الفئة أو الماركة (Category)',
      'القيمة المستهدفة بالجنيه (Target_Revenue_EGP)',
      'الكمية المستهدفة ($_unitLabelAr) (Target_Units)',
      'ملاحظات (Notes)',
    ];
    final rows = [
      [
        'أسواق فتح الله',
        2025,
        1,
        'كل الفروع',
        'كل الفئات',
        8500000,
        125000,
        'مستهدف شهر يناير 2025',
      ],
      [
        'أسواق فتح الله',
        2025,
        2,
        'كل الفروع',
        'كل الفئات',
        9500000,
        138000,
        'مستهدف شهر فبراير 2025',
      ],
      [
        'أسواق فتح الله',
        2025,
        3,
        'كل الفروع',
        'كل الفئات',
        9000000,
        130000,
        'مستهدف شهر مارس 2025',
      ],
      [
        'أسواق فتح الله',
        2025,
        4,
        'كل الفروع',
        'كل الفئات',
        7500000,
        110000,
        'مستهدف شهر أبريل 2025',
      ],
    ];
    final csvData = ExcelExportService.generateCsv(headers: headers, rows: rows);
    final filename = 'tashil_${widget.targetType}_targets_template.csv';
    ExcelExportService.downloadCsv(filename, csvData);
    M3Feedback.showSuccess(
      context,
      'تم تحميل قالب إكسيل المستهدفات ($filename)',
    );
  }

  void _exportTargetsComparisonCsv() {
    final items = _summary?.items ?? const [];
    if (items.isEmpty) {
      M3Feedback.showError(context, 'لا توجد مستهدفات مسجلة لتصديرها حالياً');
      return;
    }
    final headers = [
      'السلسلة',
      'الفترة / الشهر',
      'الفرع',
      'الفئة',
      'المستهدف (ج.م)',
      'المحقق الفعلي (ج.م)',
      'الفرق (ج.م)',
      'نسبة تحقيق القيمة %',
      'الكمية المستهدفة ($_unitLabelAr)',
      'الكمية الفعلية ($_unitLabelAr)',
      'نسبة تحقيق الكمية %',
      'الحالة',
      'ملاحظات',
    ];
    final rows = items
        .map(
          (i) => [
            i.chainDisplayName,
            i.monthLabel,
            i.branchName,
            i.category,
            i.targetRevenueEgp,
            i.actualRevenueEgp,
            i.varianceRevenueEgp,
            '${i.achievementRevPct.toStringAsFixed(1)}%',
            i.targetUnits,
            i.actualUnits,
            '${i.achievementUnitsPct.toStringAsFixed(1)}%',
            i.statusAr,
            i.notes,
          ],
        )
        .toList();
    final csvData = ExcelExportService.generateCsv(headers: headers, rows: rows);
    final filename =
        'tashil_${widget.targetType}_target_vs_actual_${DateTime.now().millisecondsSinceEpoch}.csv';
    ExcelExportService.downloadCsv(filename, csvData);
    M3Feedback.showSuccess(
      context,
      'تم تصدير تقرير مقارنة المستهدف بالفعلي (${items.length} صف)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final summary = _summary ?? TargetsSummaryModel.empty(widget.targetType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Top KPI Summary Cards (Full Width & Perfectly Symmetrical 4 Cards)
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final card1 = _buildKpiCard(
              context,
              titleAr: _isSellIn
                  ? 'إجمالي مستهدف التوريد'
                  : 'إجمالي مستهدف المبيعات',
              titleEn: _isSellIn ? 'Target Sell-In (EGP)' : 'Target Sell-Out (EGP)',
              value: CurrencyFormatter.formatCompactEGP(summary.totalTargetRevenueEgp),
              subtitleAr:
                  '${CurrencyFormatter.formatNumber(summary.totalTargetUnits.round())} $_unitLabelAr مستهدفة',
              subtitleEn: 'Target $_unitLabelEn',
              icon: Icons.flag_circle_rounded,
              color: colorScheme.primary,
            );
            final card2 = _buildKpiCard(
              context,
              titleAr: _isSellIn
                  ? 'المحقق الفعلي للتوريد'
                  : 'المحقق الفعلي للمبيعات',
              titleEn: _isSellIn ? 'Actual Sell-In (EGP)' : 'Actual Sell-Out (EGP)',
              value: CurrencyFormatter.formatCompactEGP(summary.totalActualRevenueEgp),
              subtitleAr:
                  '${CurrencyFormatter.formatNumber(summary.totalActualUnits.round())} $_unitLabelAr محققة فعلياً',
              subtitleEn: 'Actual $_unitLabelEn',
              icon: Icons.insights_rounded,
              color: Colors.teal.shade700,
            );
            final card3 = _buildKpiCard(
              context,
              titleAr: 'نسبة التحقيق الإجمالية',
              titleEn: 'Overall Achievement %',
              value: '${summary.overallAchievementPct.toStringAsFixed(1)}%',
              subtitleAr: summary.overallAchievementPct >= 100
                  ? 'تجاوز المستهدف بنجاح'
                  : (summary.overallAchievementPct >= 85
                      ? 'أداء قريب من المستهدف'
                      : 'يحتاج لتنشيط للوصول للمستهدف'),
              subtitleEn: summary.overallAchievementPct >= 100
                  ? 'Target Exceeded'
                  : (summary.overallAchievementPct >= 85
                      ? 'Near Target'
                      : 'Action Required'),
              icon: Icons.pie_chart_rounded,
              color: summary.overallAchievementPct >= 100
                  ? Colors.green.shade700
                  : (summary.overallAchievementPct >= 85
                      ? Colors.orange.shade800
                      : colorScheme.error),
              progressPct: summary.overallAchievementPct,
            );
            final card4 = _buildKpiCard(
              context,
              titleAr: _isSellIn
                  ? 'الفجوة / الفرق في التوريد'
                  : 'الفجوة / الفرق في المبيعات',
              titleEn: 'Variance (EGP)',
              value:
                  '${summary.totalVarianceEgp >= 0 ? '+' : ''}${CurrencyFormatter.formatCompactEGP(summary.totalVarianceEgp)}',
              subtitleAr: summary.totalVarianceEgp >= 0
                  ? 'فائض فوق المستهدف'
                  : 'المتبقي لتحقيق المستهدف',
              subtitleEn: summary.totalVarianceEgp >= 0
                  ? 'Surplus Above Target'
                  : 'Remaining to Target',
              icon: summary.totalVarianceEgp >= 0
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              color: summary.totalVarianceEgp >= 0
                  ? Colors.green.shade700
                  : colorScheme.error,
            );

            if (width >= 1100) {
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
            } else if (width >= 650) {
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: card1),
                      const SizedBox(width: 12.0),
                      Expanded(child: card2),
                    ],
                  ),
                  const SizedBox(height: 12.0),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
          },
        ),

        M3Spacing.gapMD,

        // 2. Action & Filter Toolbar
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
            runSpacing: 12.0,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Filters: Year + Chain in English
              Wrap(
                spacing: 12.0,
                runSpacing: 8.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 160.0,
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      value: _selectedYear,
                      decoration: InputDecoration(
                        labelText: 'Year',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 11.0,
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
                          _loadTargets();
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220.0,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _chainOptions.any((c) => c.code == _selectedChain)
                          ? _selectedChain
                          : 'all',
                      decoration: InputDecoration(
                        labelText: 'Retail Chain',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 11.0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                      items: _chainOptions
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c.code,
                              child: Text(
                                c.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _selectedChain = v);
                          _loadTargets();
                        }
                      },
                    ),
                  ),
                ],
              ),

              // Action Buttons: MD3 Large Button Size & in English
              Wrap(
                spacing: 10.0,
                runSpacing: 10.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => _openTargetFormDialog(),
                    icon: const Icon(Icons.add_task_rounded, size: 20.0),
                    label: const Text('Add Target Manually'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48.0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 12.0,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.0),
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _isUploading ? null : _pickAndUploadTargetExcel,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 18.0,
                            height: 18.0,
                            child: CircularProgressIndicator(strokeWidth: 2.0),
                          )
                        : const Icon(Icons.upload_file_rounded, size: 20.0),
                    label: const Text('Upload Target Excel'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48.0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 12.0,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.0),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _downloadTargetTemplate,
                    icon: const Icon(Icons.download_rounded, size: 20.0),
                    label: const Text('Excel Template'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48.0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18.0,
                        vertical: 12.0,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.0),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _exportTargetsComparisonCsv,
                    icon: const Icon(Icons.table_view_rounded, size: 20.0),
                    label: const Text('Export Report'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48.0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18.0,
                        vertical: 12.0,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.0),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // 3. Target vs. Actual Comparison Table
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
              : summary.items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 48.0,
                        horizontal: 24.0,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.track_changes_outlined,
                            size: 48.0,
                            color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                          ),
                          const SizedBox(height: 12.0),
                          Text(
                            _isSellIn
                                ? 'لم يتم تسجيل مستهدفات توريد (Sell-In Targets) لهذه الفترة بعد'
                                : 'لم يتم تسجيل مستهدفات مبيعات (Sell-Out Targets) لهذه الفترة بعد',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6.0),
                          Text(
                            'اضغط على "إضافة Target يدوياً" أو قم برفع شيت إكسيل المستهدفات ليقوم النظام بمقارنته تلقائياً مع الأرقام الفعلية وحساب نسبة التحقيق.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : TableScrollContainer(
                      showSwipeHint: true,
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          colorScheme.surfaceContainerHigh.withOpacity(0.5),
                        ),
                        columns: [
                          const DataColumn(label: Text('السلسلة (Chain)')),
                          const DataColumn(label: Text('الفترة (Period)')),
                          const DataColumn(label: Text('النطاق (الفرع / الفئة)')),
                          const DataColumn(
                            numeric: true,
                            label: Text('المستهدف (Target EGP)'),
                          ),
                          const DataColumn(
                            numeric: true,
                            label: Text('المحقق الفعلي (Actual EGP)'),
                          ),
                          const DataColumn(
                            numeric: true,
                            label: Text('الفرق (Variance)'),
                          ),
                          DataColumn(
                            numeric: true,
                            label: Text('الكمية ($_unitLabelAr: فعلي / مستهدف)'),
                          ),
                          const DataColumn(
                            label: Text('نسبة التحقيق (Achievement %)'),
                          ),
                          const DataColumn(label: Text('إجراءات')),
                        ],
                        rows: summary.items.map((item) {
                          final isPositive = item.varianceRevenueEgp >= 0;
                          final badgeColor = item.achievementRevPct >= 100
                              ? Colors.green.shade700
                              : (item.achievementRevPct >= 85
                                  ? Colors.orange.shade800
                                  : colorScheme.error);
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  item.chainDisplayName,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              DataCell(Text(item.monthLabel)),
                              DataCell(
                                Text('${item.branchName} • ${item.category}'),
                              ),
                              DataCell(
                                Text(
                                  CurrencyFormatter.formatEGP(item.targetRevenueEgp),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              DataCell(
                                Text(
                                  CurrencyFormatter.formatEGP(item.actualRevenueEgp),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${isPositive ? '+' : ''}${CurrencyFormatter.formatEGP(item.varianceRevenueEgp)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: isPositive
                                        ? Colors.green.shade700
                                        : colorScheme.error,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${CurrencyFormatter.formatNumber(item.actualUnits.round())} / ${CurrencyFormatter.formatNumber(item.targetUnits.round())}',
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10.0,
                                        vertical: 4.0,
                                      ),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(999.0),
                                      ),
                                      child: Text(
                                        '${item.achievementRevPct.toStringAsFixed(1)}% (${item.statusAr})',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.0,
                                          color: badgeColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'تعديل المستهدف',
                                      icon: const Icon(Icons.edit_outlined, size: 18.0),
                                      onPressed: () =>
                                          _openTargetFormDialog(existing: item),
                                    ),
                                    IconButton(
                                      tooltip: 'حذف المستهدف',
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18.0,
                                        color: colorScheme.error,
                                      ),
                                      onPressed: () async {
                                        try {
                                          await widget.apiClient.deleteTarget(
                                            id: item.id,
                                            targetType: widget.targetType,
                                          );
                                          if (!context.mounted) return;
                                          M3Feedback.showSuccess(
                                            context,
                                            'تم حذف المستهدف بنجاح',
                                          );
                                          await _loadTargets();
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          M3Feedback.showError(
                                            context,
                                            'تعذر حذف المستهدف: $e',
                                          );
                                        }
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
        ),
      ],
    );
  }

  Widget _buildKpiCard(
    BuildContext context, {
    required String titleAr,
    required String titleEn,
    required String value,
    required String subtitleAr,
    required String subtitleEn,
    required IconData icon,
    required Color color,
    double? progressPct,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 145.0),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9.0),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Icon(icon, color: color, size: 22.0),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleAr,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      titleEn,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withOpacity(0.85),
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
          if (progressPct != null) ...[
            const SizedBox(height: 8.0),
            ClipRRect(
              borderRadius: BorderRadius.circular(999.0),
              child: LinearProgressIndicator(
                value: (progressPct / 100.0).clamp(0.0, 1.0),
                minHeight: 6.0,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: color,
              ),
            ),
          ],
          const SizedBox(height: 6.0),
          Row(
            children: [
              Expanded(
                child: Text(
                  subtitleAr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subtitleEn.isNotEmpty) ...[
                const SizedBox(width: 4.0),
                Text(
                  '• $subtitleEn',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                    fontSize: 11.0,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

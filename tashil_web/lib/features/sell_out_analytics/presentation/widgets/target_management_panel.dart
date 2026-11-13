import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_text_variants.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/data/result.dart';
import '../../../../core/network/api_client.dart';
import '../../data/target_repository.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../../product_master/presentation/screens/product_master_screen.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';
import '../../../../core/widgets/m3_section_title.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_table_surface.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';

/// TargetManagementPanel provides a unified Target entry, Excel upload, and
/// real-time Actual vs. Target achievement comparison experience for both
/// Sell-Out (مبيعات الكاشير) and Sell-In (توريدات السلاسل).
///
/// For Sell-In, it includes a 3-Tier Comprehensive Hierarchical Drill-Down Engine:
/// Level 1: Chain Target Summary (Value EGP, Cases, Tons, Gross w/ Return Buffer, Promo Mix, MT/CC)
/// Level 2: Chain Branches Breakdown (how much Value, Cases & Tons each branch must achieve)
/// Level 3: Branch SKUs Breakdown (exact quantity of goods per SKU inside each branch) +
///          Total Chain SKUs Rollup + Sales Rep Quotas + 12-Month Seasonality Phasing.
class TargetManagementPanel extends StatefulWidget {
  final ApiClient apiClient;
  final String targetType; // 'sell_out' or 'sell_in'

  /// Optional injected repository (tests); defaults to one wrapping [apiClient].
  final TargetRepository? repository;

  const TargetManagementPanel({
    super.key,
    required this.apiClient,
    required this.targetType,
    this.repository,
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

  // Selected Target for Comprehensive 3-Level Drill-Down
  String? _selectedTargetId;
  // Active sub-view inside the Comprehensive Breakdown:
  // 0 = فروع السلسلة (Level 2: Branches)
  // 1 = أصناف وبضاعة الفرع المختار (Level 3: SKUs inside Selected Branch)
  // 2 = إجمالي بضاعة وأصناف السلسلة بالكامل (Chain Total SKUs)
  // 3 = كوتة المناديب والماركات (Sales Reps & Brands Quotas)
  // 4 = التوزيع الشهري الموسمي (12-Month Phasing)
  int _drillSubTab = 0;

  // Selected branch index or code inside Level 2 -> Level 3
  String? _selectedBranchName;
  String _branchSearchQuery = '';
  String _branchRegionFilter = 'all';

  // Level 3 / Chain SKUs filters & pagination
  String _skuSearchQuery = '';
  String _skuBrandFilter = 'all';
  String _skuSectorFilter = 'all';
  String _skuStockStatusFilter = 'all';
  int _skuPage = 0;
  static const int _skuPageSize = 25;

  static const List<({int month, String labelAr, String labelEn})> _months = [
    (month: 0, labelAr: 'السنة كاملة', labelEn: 'Full year'),
    (month: 1, labelAr: 'يناير', labelEn: 'January'),
    (month: 2, labelAr: 'فبراير', labelEn: 'February'),
    (month: 3, labelAr: 'مارس', labelEn: 'March'),
    (month: 4, labelAr: 'أبريل', labelEn: 'April'),
    (month: 5, labelAr: 'مايو', labelEn: 'May'),
    (month: 6, labelAr: 'يونيو', labelEn: 'June'),
    (month: 7, labelAr: 'يوليو', labelEn: 'July'),
    (month: 8, labelAr: 'أغسطس', labelEn: 'August'),
    (month: 9, labelAr: 'سبتمبر', labelEn: 'September'),
    (month: 10, labelAr: 'أكتوبر', labelEn: 'October'),
    (month: 11, labelAr: 'نوفمبر', labelEn: 'November'),
    (month: 12, labelAr: 'ديسمبر', labelEn: 'December'),
  ];

  bool get _isSellIn => widget.targetType == 'sell_in';

  String get _unitLabelAr => _isSellIn ? 'كرتونة' : 'وحدة';
  String get _unitLabelEn => _isSellIn ? 'Cases' : 'Units';

  /// Dynamic base year (locked at minimum 2026, advances automatically in future years e.g. 2027, 2028)
  int get _baseCurrentYear {
    final nowYear = DateTime.now().year;
    return nowYear >= 2026 ? nowYear : 2026;
  }

  /// Dynamic Target Planning Years Formula:
  /// Locks floor at current year (e.g. 2026) and always provides 2 future years ahead:
  /// - In 2026 -> [2026, 2027, 2028]
  /// - In 2027 -> [2027, 2028, 2029]
  List<int> get _targetPlanningYears {
    final base = _baseCurrentYear;
    return [base, base + 1, base + 2];
  }

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? TargetRepository(widget.apiClient);
    _initAndLoad();
  }

  late TargetRepository _repo;

  Future<void> _initAndLoad() async {
    final chains = await _repo.loadChains();
    if (chains case Success(:final value)) {
      if (mounted) {
        setState(() => _companyChains = value);
      }
    }
    await _loadTargets();
  }

  Future<void> _loadTargets() async {
    setState(() => _isLoading = true);
    final loaded = await _repo.loadSummary(
      targetType: widget.targetType,
      chain: _selectedChain == 'all' ? null : _selectedChain,
      year: _selectedYear > 0 ? _selectedYear : null,
    );
    if (loaded case Failure(:final error)) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('Targets load failed: $error');
        M3Feedback.showError(context, 'تعذّر تحميل المستهدفات. حاول مرة أخرى.');
      }
      return;
    }
    final res = loaded.valueOrNull!;
    if (mounted) {
      setState(() {
        _summary = res;
        _isLoading = false;
        if (res.items.isNotEmpty) {
          final stillExists = res.items.any((i) => i.id == _selectedTargetId);
          if (!stillExists) {
            _selectedTargetId = res.items.first.id;
          }
          final activeTarget = _activeTargetItem;
          if (activeTarget != null && activeTarget.branches.isNotEmpty) {
            final branchExists = activeTarget.branches.any(
              (b) => b.branchName == _selectedBranchName,
            );
            if (!branchExists) {
              _selectedBranchName = activeTarget.branches.first.branchName;
            }
          }
        } else {
          _selectedTargetId = null;
          _selectedBranchName = null;
        }
      });
    }
  }

  TargetComparisonModel? get _activeTargetItem {
    final items = _summary?.items ?? const [];
    if (items.isEmpty) return null;
    if (_selectedTargetId != null) {
      for (final item in items) {
        if (item.id == _selectedTargetId) return item;
      }
    }
    return items.first;
  }

  TargetBranchBreakdownModel? _getActiveBranch(TargetComparisonModel target) {
    if (target.branches.isEmpty) return null;
    if (_selectedBranchName != null) {
      for (final b in target.branches) {
        if (b.branchName == _selectedBranchName) return b;
      }
    }
    return target.branches.first;
  }

  List<({String code, String label})> get _chainOptions {
    final opts = <({String code, String label})>[
      (code: 'all', label: 'كل السلاسل'),
      (code: 'fathalla', label: 'أسواق فتح الله'),
      (code: 'gomla', label: 'جملة ماركت'),
      (code: 'beet-elgomla', label: 'بيت الجملة'),
      (code: 'chain-1080314', label: 'الوكالة'),
      (code: 'carrefour', label: 'كارفور'),
      (code: 'spinneys', label: 'سبينيس'),
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

  Future<void> _openTargetFormDialog({
    TargetComparisonModel? existing,
    String? prefillChain,
    int? prefillYear,
    String? prefillBranch,
    double? prefillRev,
    double? prefillUnits,
  }) async {
    String chain = existing?.retailerChain ??
        prefillChain ??
        (_selectedChain != 'all' ? _selectedChain : 'fathalla');
    final planningYears = List<int>.from(_targetPlanningYears);
    int year = existing?.year ??
        prefillYear ??
        (_selectedYear >= _baseCurrentYear ? _selectedYear : _baseCurrentYear);
    if (!planningYears.contains(year)) {
      planningYears.add(year);
      planningYears.sort();
    }
    int month = existing?.month ?? 0;
    final branchCtrl = TextEditingController(
      text: prefillBranch ??
          (existing != null && existing.branchName != 'كل الفروع'
              ? existing.branchName
              : ''),
    );
    final categoryCtrl = TextEditingController(
      text: existing != null && existing.category != 'كل الفئات'
          ? existing.category
          : '',
    );
    final revCtrl = TextEditingController(
      text: prefillRev != null && prefillRev > 0
          ? prefillRev.toStringAsFixed(0)
          : (existing != null && existing.targetRevenueEgp > 0
              ? existing.targetRevenueEgp.toStringAsFixed(0)
              : ''),
    );
    final unitsCtrl = TextEditingController(
      text: prefillUnits != null && prefillUnits > 0
          ? prefillUnits.toStringAsFixed(0)
          : (existing != null && existing.targetUnits > 0
              ? existing.targetUnits.toStringAsFixed(0)
              : ''),
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    final avgCasePrice = (_summary?.avgCasePriceEgp ?? 587.5) > 0
        ? (_summary?.avgCasePriceEgp ?? 587.5)
        : 587.5;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colorScheme = theme.colorScheme;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final parsedRev = double.tryParse(
                  revCtrl.text.replaceAll(',', '').trim(),
                ) ??
                0.0;
            final parsedUnits = double.tryParse(
                  unitsCtrl.text.replaceAll(',', '').trim(),
                ) ??
                0.0;

            final effectiveRev = parsedRev > 0
                ? parsedRev
                : (parsedUnits > 0 ? parsedUnits * avgCasePrice : 0.0);
            final effectiveUnits = parsedUnits > 0
                ? parsedUnits
                : (parsedRev > 0 ? (parsedRev / avgCasePrice) : 0.0);
            final effectiveTons = effectiveUnits * 0.0145;
            final grossUnitsWithBuffer = effectiveUnits * 1.018;

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                shape: const RoundedRectangleBorder(
                  borderRadius: M3Shape.radiusXl,
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
                                ? 'إضافة مستهدف'
                                : 'إضافة مستهدف')
                            : 'تعديل المستهدف',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
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
                        if (_isSellIn) ...[
                          Container(
                            padding: const EdgeInsets.all(12.0),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withOpacity(0.35),
                              borderRadius: M3Shape.radiusMd,
                              border: Border.all(
                                color: colorScheme.primary.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  color: colorScheme.primary,
                                  size: 20.0,
                                ),
                                const SizedBox(width: 10.0),
                                Expanded(
                                  child: Text(
                                    'أدخل السلسلة والسنة والمستهدف، وسنوزّعه تلقائيًا على الفروع والأصناف.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.onSurface,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14.0),
                        ],
                        M3Dropdown<String>(
value: _chainOptions.any((c) => c.code == chain)
                              ? chain
                              : 'fathalla',
label: 'السلسلة *',
expand: true,
options: m3OptionsFromMenuItems<String>(_chainOptions
                              .map(
                                (c) => DropdownMenuItem<String>(
                                  value: c.code,
                                  child: Text(
                                    c.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList()),
onChanged: m3Legacy<String>((v) {
                            if (v != null) setDialogState(() => chain = v);
                          }),
),
                        const SizedBox(height: 12.0),
                        Row(
                          children: [
                            Expanded(
                              child: M3Dropdown<int>(
key: const ValueKey('target_dialog_year_dropdown'),
value: year,
label: 'السنة *',
expand: true,
options: m3OptionsFromMenuItems<int>(planningYears
                                    .map(
                                      (yr) => DropdownMenuItem<int>(
                                        value: yr,
                                        child: Text(
                                          '$yr',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList()),
onChanged: m3Legacy<int>((v) {
                                  if (v != null) setDialogState(() => year = v);
                                }),
),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              child: M3Dropdown<int>(
value: month,
label: 'الشهر',
expand: true,
options: m3OptionsFromMenuItems<int>(_months
                                    .map(
                                      (m) => DropdownMenuItem<int>(
                                        value: m.month,
                                        child: Text(
                                          m.labelAr,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList()),
onChanged: m3Legacy<int>((v) {
                                  if (v != null) setDialogState(() => month = v);
                                }),
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
                                onChanged: (_) => setDialogState(() {}),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText:
                                      'المستهدف (ج.م) *',
                                  hintText: 'مثال: 150,000,000',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              child: TextField(
                                controller: unitsCtrl,
                                onChanged: (_) => setDialogState(() {}),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: InputDecoration(
                                  labelText:
                                      'الكمية المستهدفة ($_unitLabelAr) (اختياري)',
                                  hintText: 'مثال: 250,000',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_isSellIn && (effectiveRev > 0 || effectiveUnits > 0)) ...[
                          const SizedBox(height: 10.0),
                          Container(
                            padding: const EdgeInsets.all(12.0),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withOpacity(0.55),
                              borderRadius: M3Shape.radiusMd,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'معاينة',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    if (parsedRev > 0 && parsedUnits <= 0)
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8.0,
                                          ),
                                        ),
                                        onPressed: () {
                                          unitsCtrl.text = effectiveUnits
                                              .round()
                                              .toString();
                                          setDialogState(() {});
                                        },
                                        icon: const Icon(
                                          Icons.sync_rounded,
                                          size: 18.0,
                                        ),
                                        label: const Text(
                                          'تعبئة الكراتين تلقائياً',
                                          style: M3TextVariants.denseLabel,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6.0),
                                Wrap(
                                  spacing: 14.0,
                                  runSpacing: 6.0,
                                  children: [
                                    Text(
                                      '• القيمة: ${CurrencyFormatter.formatEGP(effectiveRev)}',
                                      style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(                                         fontSize: M3FontSize.bodySmall,                                         fontWeight: FontWeight.w700,                                       )),
                                    ),
                                    Text(
                                      '• الكمية: ${CurrencyFormatter.formatNumber(effectiveUnits.round())} كرتونة',
                                      style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(                                         fontSize: M3FontSize.bodySmall,                                         fontWeight: FontWeight.w700,                                       )),
                                    ),
                                    if (_isSellIn) Text(
                                      '• الوزن: ${effectiveTons.toStringAsFixed(1)} طن',
                                      style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(                                         fontSize: M3FontSize.bodySmall,                                         fontWeight: FontWeight.w700,                                       )),
                                    ),
                                    if (_isSellIn) Text(
                                      '• شامل احتياطي المرتجعات: ${CurrencyFormatter.formatNumber(grossUnitsWithBuffer.round())} كرتونة',
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: M3StatusColors.of(context).accents.teal),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12.0),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: branchCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'الفرع (اختياري)',
                                  hintText:
                                      'اتركه فارغًا للتوزيع على كل الفروع',
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
                                  labelText: 'الفئة (اختياري)',
                                  hintText:
                                      'اتركه فارغًا للتوزيع على كل الأصناف',
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
                          decoration: InputDecoration(
                            labelText: 'ملاحظات الخطة (اختياري)',
                            hintText:
                                'مثال: مستهدف ${DateTime.now().year}',
                            border: const OutlineInputBorder(),
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
                    label: Text(
                      _isSellIn
                          ? 'حفظ'
                          : 'حفظ',
                    ),
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
                          'أدخل المستهدف بالجنيه أو بالكمية.',
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
                          _isSellIn
                              ? 'تم حفظ المستهدف وتوزيعه.'
                              : 'تم حفظ المستهدف.',
                        );
                        _repo.invalidateAll();
                        await _loadTargets();
                      } catch (e) {
                        if (!mounted) return;
                        M3Feedback.showError(context, 'تعذّر حفظ المستهدف. حاول مرة أخرى.');
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
      _repo.invalidateAll();
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
        year: _selectedYear > 0 ? _selectedYear : 2026,
      );
      if (!mounted) return;
      M3Feedback.showSuccess(
        context,
        'تم استيراد ${res.rowsImported} مستهدف من الملف (${picked.name}) بنجاح',
      );
      _repo.invalidateAll();
      await _loadTargets();
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'تعذّر رفع ملف المستهدفات. حاول مرة أخرى.');
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
      'الفئة أو العلامة التجارية (Category)',
      'القيمة المستهدفة بالجنيه (Target_Revenue_EGP)',
      'الكمية المستهدفة ($_unitLabelAr) (Target_Units)',
      'ملاحظات (Notes)',
    ];
    final rows = [
      [
        'أسواق فتح الله',
        2026,
        0,
        'كل الفروع',
        'كل الفئات',
        150000000,
        255000,
        'مستهدف السنة (يُوزَّع تلقائيًا على الفروع والأصناف)',
      ],
      [
        'جملة ماركت',
        2026,
        0,
        'كل الفروع',
        'كل الفئات',
        45000000,
        76000,
        'مستهدف جملة ماركت السنوي',
      ],
      [
        'بيت الجملة',
        2026,
        0,
        'كل الفروع',
        'كل الفئات',
        38000000,
        64000,
        'مستهدف بيت الجملة السنوي',
      ],
    ];
    final csvData =
        ExcelExportService.generateCsv(headers: headers, rows: rows);
    final filename = 'tashil_${widget.targetType}_targets_template.csv';
    ExcelExportService.downloadCsv(filename, csvData);
    M3Feedback.showSuccess(
      context,
      'تم تنزيل القالب.',
    );
  }

  void _exportTargetsComparisonCsv() {
    final items = _summary?.items ?? const [];
    if (items.isEmpty) {
      M3Feedback.showError(context, 'لا توجد مستهدفات للتصدير.');
      return;
    }
    final active = _activeTargetItem;
    if (_isSellIn && active != null && active.branches.isNotEmpty) {
      // Export full comprehensive report: Chain + All Branches + Top SKUs
      final headers = [
        'المستوى',
        'السلسلة (Chain)',
        'الفترة (Period)',
        'الفرع (Branch)',
        'المحافظة / الإقليم',
        'مندوب المبيعات',
        'الصنف / العلامة التجارية (SKU / Brand)',
        'القطاع (Sector)',
        'حصة النطاق % (Share %)',
        'القيمة المستهدفة بالجنيه',
        'المحقق بالجنيه',
        'الفجوة بالجنيه',
        'الكمية المستهدفة بالكرتونة',
        'الكمية الفعلية بالكرتونة',
        'الوزن المستهدف بالطن (Target Tons)',
        'نسبة التحقيق % (Achievement %)',
        'الحالة / المخزون',
      ];
      final rows = <List<dynamic>>[];
      for (final item in items) {
        rows.add([
          '1. إجمالي السلسلة (Chain)',
          item.chainDisplayName,
          item.monthLabel,
          item.branchName,
          'كل الأقاليم',
          'كبار العملاء',
          'كل الأصناف (${item.activeSkusCount})',
          'MT + CC',
          '100%',
          item.targetRevenueEgp,
          item.actualRevenueEgp,
          item.varianceRevenueEgp,
          item.targetUnits,
          item.actualUnits,
          item.targetWeightTons,
          '${item.achievementRevPct.toStringAsFixed(1)}%',
          item.statusAr,
        ]);
        for (final b in item.branches) {
          rows.add([
            '2. فرع السلسلة (Branch)',
            item.chainDisplayName,
            item.monthLabel,
            b.branchName,
            '${b.governorate} (${b.regionCode})',
            b.salesRep,
            'إجمالي أصناف الفرع (${b.activeSkusCount} صنف)',
            'MT + CC',
            '${b.shareOfChainPct.toStringAsFixed(2)}%',
            b.targetRevenueEgp,
            b.actualRevenueEgp,
            b.varianceRevenueEgp,
            b.targetUnits,
            b.actualUnits,
            b.targetWeightTons,
            '${b.achievementRevPct.toStringAsFixed(1)}%',
            b.statusAr,
          ]);
        }
        for (final s in item.chainSkuTotals) {
          rows.add([
            '3. إجمالي الصنف بالسلسلة (Chain SKU)',
            item.chainDisplayName,
            item.monthLabel,
            'إجمالي فروع السلسلة',
            'كل الأقاليم',
            'كل المناديب',
            '${s.skuName} (${s.brand})',
            s.sector,
            '${s.sharePct.toStringAsFixed(2)}%',
            s.targetRevenueEgp,
            s.actualRevenueEgp,
            s.varianceRevenueEgp,
            s.targetUnits,
            s.actualUnits,
            s.targetWeightTons,
            '${s.achievementPct.toStringAsFixed(1)}%',
            s.stockStatusAr,
          ]);
        }
      }
      final csvData =
          ExcelExportService.generateCsv(headers: headers, rows: rows);
      final filename =
          'tashil_comprehensive_sellin_target_${DateTime.now().millisecondsSinceEpoch}.csv';
      ExcelExportService.downloadCsv(filename, csvData);
      M3Feedback.showSuccess(
        context,
        'تم تصدير المستهدفات (${rows.length} صف).',
      );
      return;
    }

    final headers = [
      'السلسلة',
      'الفترة / الشهر',
      'الفرع',
      'الفئة',
      'المستهدف (ج.م)',
      'المحقق (ج.م)',
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
    final csvData =
        ExcelExportService.generateCsv(headers: headers, rows: rows);
    final filename =
        'tashil_${widget.targetType}_target_vs_actual_${DateTime.now().millisecondsSinceEpoch}.csv';
    ExcelExportService.downloadCsv(filename, csvData);
    M3Feedback.showSuccess(
      context,
      'تم تصدير تقرير مقارنة المستهدف بالفعلي (${items.length} صف)',
    );
  }

  void _exportBranchSkusExcel(
    TargetComparisonModel target,
    TargetBranchBreakdownModel branch,
  ) {
    final headers = [
      'السلسلة',
      'الفترة',
      'اسم الفرع',
      'كود الفرع',
      'المحافظة / الإقليم',
      'مندوب المبيعات',
      'اسم الصنف (SKU)',
      'العلامة التجارية (Brand)',
      'القطاع (Sector)',
      'حصة الصنف بالفرع %',
      'متوسط سعر الكرتونة (ج.م)',
      'الكمية المستهدفة للفرع بالكرتونة',
      'القيمة المستهدفة للفرع بالجنيه',
      'الوزن المستهدف بالطن (Tons)',
      'الكمية المحققة',
      'القيمة المحققة',
      'المتبقي بالكرتونة',
      'المتبقي بالجنيه',
      'نسبة التحقيق %',
      'المخزون المتبقي بالفرع',
      'حالة المخزون بالفرع',
    ];
    final rows = branch.skus
        .map(
          (s) => [
            target.chainDisplayName,
            target.monthLabel,
            branch.branchName,
            branch.branchCode,
            '${branch.governorate} (${branch.regionCode})',
            branch.salesRep,
            s.skuName,
            s.brand,
            s.sector,
            '${s.sharePct.toStringAsFixed(2)}%',
            s.casePriceEgp,
            s.targetUnits,
            s.targetRevenueEgp,
            s.targetWeightTons,
            s.actualUnits,
            s.actualRevenueEgp,
            s.varianceUnits,
            s.varianceRevenueEgp,
            '${s.achievementPct.toStringAsFixed(1)}%',
            s.remainingStockCases,
            s.stockStatusAr,
          ],
        )
        .toList();
    final csvData =
        ExcelExportService.generateCsv(headers: headers, rows: rows);
    final filename =
        'tashil_branch_sku_targets_${branch.branchCode}_${DateTime.now().millisecondsSinceEpoch}.csv';
    ExcelExportService.downloadCsv(filename, csvData);
    M3Feedback.showSuccess(
      context,
      'تم تصدير مستهدفات أصناف (${branch.branchName}) بالكامل (${rows.length} صنف)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final summary = _summary ?? TargetsSummaryModel.empty(widget.targetType);
    final activeTarget = _activeTargetItem;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Top KPI Summary Cards (Full Width & Perfectly Symmetrical 4 Cards)
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // No targets yet: neutral cards with one empty-state line instead
            // of contradictory 'فوق المستهدف' / 'أقل من المستهدف'.
            final hasTargets = summary.items.isNotEmpty;
            const noTargets = 'لا توجد مستهدفات بعد';
            final neutral = colorScheme.onSurfaceVariant;
            final card1 = _buildKpiCard(
              context,
              titleAr: _isSellIn
                  ? 'مستهدف Sell-In'
                  : 'مستهدف Sell-Out',
              titleEn: _isSellIn
                  ? 'Sell-In Target'
                  : 'Sell-Out Target',
              value: CurrencyFormatter.formatCompactEGP(
                summary.totalTargetRevenueEgp,
              ),
              subtitleAr: _isSellIn
                  ? '${CurrencyFormatter.formatNumber(summary.totalTargetUnits.round())} كرتونة • ${summary.totalTargetWeightTons.toStringAsFixed(1)} طن'
                  : '${CurrencyFormatter.formatNumber(summary.totalTargetUnits.round())} $_unitLabelAr مستهدفة',
              subtitleEn: _isSellIn
                  ? '+ returns: ${CurrencyFormatter.formatNumber(summary.totalGrossTargetUnits.round())} cases'
                  : 'Target $_unitLabelEn',
              icon: Icons.flag_circle_rounded,
              color: colorScheme.primary,
            );
            final card2 = _buildKpiCard(
              context,
              titleAr: _isSellIn
                  ? 'المحقق صافي بعد المرتجعات (Sell-In)'
                  : 'المحقق (Sell-Out)',
              titleEn: _isSellIn
                  ? 'Actual net Sell-In after returns'
                  : 'Actual Sell-Out',
              value: CurrencyFormatter.formatCompactEGP(
                summary.totalActualRevenueEgp,
              ),
              subtitleAr: _isSellIn
                  ? '${CurrencyFormatter.formatNumber(summary.totalActualUnits.round())} كرتونة • ${summary.totalActualWeightTons.toStringAsFixed(1)} طن'
                  : '${CurrencyFormatter.formatNumber(summary.totalActualUnits.round())} $_unitLabelAr محققة',
              subtitleEn: _isSellIn && summary.totalExpectedRevenueEgp > 0
                  ? 'Forecast: ${CurrencyFormatter.formatCompactEGP(summary.totalExpectedRevenueEgp)}'
                  : 'Actual $_unitLabelEn',
              icon: Icons.insights_rounded,
              color: M3StatusColors.of(context).accents.teal,
            );
            final card3 = _buildKpiCard(
              context,
              titleAr: 'نسبة التحقيق الإجمالية',
              titleEn: 'Overall Achievement %',
              value: '${summary.overallAchievementPct.toStringAsFixed(1)}%',
              subtitleAr: !hasTargets
                  ? noTargets
                  : summary.overallAchievementPct >= 100
                      ? 'فوق المستهدف'
                      : (summary.overallAchievementPct >= 85
                          ? 'قريب من المستهدف'
                          : 'أقل من المستهدف'),
              subtitleEn: summary.overallAchievementPct >= 100
                  ? 'Above target'
                  : (summary.overallAchievementPct >= 85
                      ? 'Near target'
                      : 'Below target'),
              icon: Icons.pie_chart_rounded,
              color: !hasTargets
                  ? neutral
                  : summary.overallAchievementPct >= 100
                  ? M3StatusColors.of(context).accents.positive
                  : (summary.overallAchievementPct >= 85
                      ? M3StatusColors.of(context).accents.caution
                      : colorScheme.error),
              progressPct: hasTargets ? summary.overallAchievementPct : null,
              reserveProgress: true,
            );
            final card4 = _buildKpiCard(
              context,
              titleAr: _isSellIn
                  ? 'الفرق'
                  : 'الفرق',
              titleEn: 'Variance',
              value: !hasTargets
                  ? '—'
                  : '${summary.totalVarianceEgp >= 0 ? '+' : ''}${CurrencyFormatter.formatCompactEGP(summary.totalVarianceEgp)}',
              subtitleAr: !hasTargets
                  ? noTargets
                  : _isSellIn && summary.totalBranchesCovered > 0
                      ? 'موزع على ${summary.totalBranchesCovered} فرع • ${summary.totalSkusCovered} صنف'
                      : (summary.totalVarianceEgp >= 0
                          ? 'فوق المستهدف'
                          : 'المتبقي للمستهدف'),
              subtitleEn: summary.totalVarianceEgp >= 0
                  ? 'Above target'
                  : 'To go',
              icon: summary.totalVarianceEgp >= 0
                  ? Icons.trending_up_rounded
                  : Icons.account_tree_rounded,
              color: !hasTargets
                  ? neutral
                  : summary.totalVarianceEgp >= 0
                      ? M3StatusColors.of(context).accents.positive
                      : M3StatusColors.of(context).accents.indigo,
            );

            // Equal-height grid (as on the other tabs) so the progress bar
            // card is not taller than its siblings.
            return M3EqualHeightGrid(
              key: const ValueKey('targets_kpi_grid'),
              columns: width >= 1100 ? 4 : (width >= 650 ? 2 : 1),
              spacing: M3Spacing.sm,
              runSpacing: M3Spacing.sm,
              children: [card1, card2, card3, card4],
            );
          },
        ),

        M3Spacing.gapMD,

        // 2. Action & Filter Toolbar
        Container(
          key: const ValueKey('targets_filter_bar'),
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
              // Filters: Year + Chain
              Wrap(
                spacing: M3Spacing.sm,
                runSpacing: M3Spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 190.0,
                    child: M3Dropdown<int>(
value: [0, ..._targetPlanningYears].contains(_selectedYear)
                          ? _selectedYear
                          : 0,
label: 'سنة البيانات',
expand: true,
options: m3OptionsFromMenuItems<int>([
                        const DropdownMenuItem(value: 0, child: Text('كل السنوات')),
                        ..._targetPlanningYears.map(
                          (yr) => DropdownMenuItem<int>(
                            value: yr,
                            child: Text('$yr'),
                          ),
                        ),
                      ]),
onChanged: m3Legacy<int>((v) {
                        if (v != null) {
                          setState(() => _selectedYear = v);
                          _loadTargets();
                        }
                      }),
),
                  ),
                  SizedBox(
                    width: 240.0,
                    child: M3Dropdown<String>(
value: _chainOptions.any((c) => c.code == _selectedChain)
                          ? _selectedChain
                          : 'all',
label: 'السلسلة',
expand: true,
options: m3OptionsFromMenuItems<String>(_chainOptions
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c.code,
                              child: Text(
                                c.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList()),
onChanged: m3Legacy<String>((v) {
                        if (v != null) {
                          setState(() => _selectedChain = v);
                          _loadTargets();
                        }
                      }),
),
                  ),
                ],
              ),

              // Action Buttons
              Wrap(
                spacing: M3Spacing.xs,
                runSpacing: M3Spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => _openTargetFormDialog(),
                    icon: const Icon(Icons.add_task_rounded, size: M3ToolbarButton.iconSize),
                    label: Text(
                      _isSellIn
                          ? 'إضافة مستهدف'
                          : 'إضافة مستهدف',
                    ),
                    style: M3ToolbarButton.style,
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _isUploading ? null : _pickAndUploadTargetExcel,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 18.0,
                            height: 18.0,
                            child: CircularProgressIndicator(strokeWidth: 2.0),
                          )
                        : const Icon(Icons.upload_file_rounded, size: M3ToolbarButton.iconSize),
                    label: const Text('رفع ملف المستهدفات'),
                    style: M3ToolbarButton.style,
                  ),
                  OutlinedButton.icon(
                    onPressed: _downloadTargetTemplate,
                    icon: const Icon(Icons.download_rounded, size: M3ToolbarButton.iconSize),
                    label: const Text('تنزيل القالب'),
                    style: M3ToolbarButton.style,
                  ),
                  OutlinedButton.icon(
                    onPressed: _exportTargetsComparisonCsv,
                    icon: const Icon(Icons.table_view_rounded, size: M3ToolbarButton.iconSize),
                    label: Text(
                      _isSellIn ? 'تصدير' : 'تصدير',
                    ),
                    style: M3ToolbarButton.style,
                  ),
                ],
              ),
            ],
          ),
        ),

        M3Spacing.gapMD,

        // 3. Level 1: Chain Target vs. Actual Summary Table
        Container(
          key: const ValueKey('targets_chain_table_section'),
          decoration: BoxDecoration(
            color: M3TableSurface.color(colorScheme),
            borderRadius: M3Shape.radiusLg,
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
                  ? _buildEmptyTargetsState(context, theme, colorScheme)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            18.0,
                            16.0,
                            18.0,
                            8.0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.layers_rounded,
                                    color: colorScheme.primary,
                                    size: 24.0,
                                  ),
                                  const SizedBox(width: 8.0),
                                  M3SectionTitle(
                                    _isSellIn
                                        ? 'المستهدف حسب السلسلة'
                                        : 'المستهدف مقابل المحقق',
),
                                ],
                              ),
                              if (_isSellIn)
                                Text(
                                  'اضغط على السلسلة لعرض الفروع والأصناف.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        TableScrollContainer(
                          showSwipeHint: true,
                          child: DataTable(
                            showCheckboxColumn: false,
                            headingRowColor: WidgetStatePropertyAll(
                              colorScheme.surfaceContainerHigh.withOpacity(0.5),
                            ),
                            columns: [
                              const DataColumn(label: Text('السلسلة (Chain)')),
                              const DataColumn(label: Text('الفترة (Period)')),
                              const DataColumn(
                                label: Text('النطاق'),
                              ),
                              const DataColumn(
                                numeric: true,
                                label: Text('المستهدف'),
                              ),
                              const DataColumn(
                                numeric: true,
                                label: Text('المحقق (ج.م)'),
                              ),
                              const DataColumn(
                                numeric: true,
                                label: Text('الفرق (ج.م)'),
                              ),
                              DataColumn(
                                numeric: true,
                                label: Text(
                                  'الكمية ($_unitLabelAr: فعلي / مستهدف)',
                                ),
                              ),
                              if (_isSellIn)
                                const DataColumn(
                                  numeric: true,
                                  label: Text('الوزن بالطن (فعلي / مستهدف)'),
                                ),
                              const DataColumn(
                                label: Text('نسبة التحقيق %'),
                              ),
                              const DataColumn(label: Text('إجراءات')),
                            ],
                            rows: summary.items.map((item) {
                              final isSelected = item.id == activeTarget?.id;
                              final isPositive = item.varianceRevenueEgp >= 0;
                              final badgeColor = item.achievementRevPct >= 100
                                  ? M3StatusColors.of(context).accents.positive
                                  : (item.achievementRevPct >= 85
                                      ? M3StatusColors.of(context).accents.caution
                                      : colorScheme.error);
                              return DataRow(
                                selected: isSelected,
                                onSelectChanged: (_) {
                                  setState(() {
                                    _selectedTargetId = item.id;
                                    if (item.branches.isNotEmpty) {
                                      _selectedBranchName =
                                          item.branches.first.branchName;
                                    }
                                  });
                                },
                                cells: [
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isSelected && _isSellIn)
                                          Padding(
                                            padding: const EdgeInsetsDirectional
                                                .only(end: 6.0),
                                            child: Icon(
                                              Icons.check_circle_rounded,
                                              size: 18.0,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                        Text(
                                          item.chainDisplayName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(Text(item.monthLabel)),
                                  DataCell(
                                    _isSellIn && item.branchesCount > 0
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10.0,
                                              vertical: 4.0,
                                            ),
                                            decoration: BoxDecoration(
                                              color: colorScheme
                                                  .primaryContainer
                                                  .withOpacity(0.5),
                                              borderRadius:
                                                  M3Shape.radiusSm,
                                            ),
                                            child: Text(
                                              '${item.branchesCount} فرع • ${item.activeSkusCount} صنف',
                                              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.primary),
                                            ),
                                          )
                                        : Text(
                                            '${item.branchName} • ${item.category}',
                                          ),
                                  ),
                                  DataCell(
                                    Text(
                                      CurrencyFormatter.formatEGP(
                                        item.targetRevenueEgp,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      CurrencyFormatter.formatEGP(
                                        item.actualRevenueEgp,
                                      ),
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
                                            ? M3StatusColors.of(context).accents.positive
                                            : colorScheme.error,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '${CurrencyFormatter.formatNumber(item.actualUnits.round())} / ${CurrencyFormatter.formatNumber(item.targetUnits.round())} $_unitLabelAr',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (_isSellIn)
                                    DataCell(
                                      Text(
                                        '${item.actualWeightTons.toStringAsFixed(1)} / ${item.targetWeightTons.toStringAsFixed(1)} طن',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: M3StatusColors.of(context).accents.indigo,
                                        ),
                                      ),
                                    ),
                                  DataCell(
                                    M3ChipSurface(
                      color: badgeColor.withOpacity(0.12),
                      child: Text(
                                        '${item.achievementRevPct.toStringAsFixed(1)}% (${item.statusAr})',
                                        style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: badgeColor),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_isSellIn)
                                          TextButton.icon(
                                            onPressed: () {
                                              setState(() {
                                                _selectedTargetId = item.id;
                                                _drillSubTab = 0;
                                                if (item.branches.isNotEmpty) {
                                                  _selectedBranchName = item
                                                      .branches
                                                      .first
                                                      .branchName;
                                                }
                                              });
                                            },
                                            icon: const Icon(
                                              Icons.account_tree_rounded,
                                              size: 18.0,
                                            ),
                                            label: const Text('تفاصيل الفروع'),
                                          ),
                                        IconButton(
                                          tooltip: 'تعديل المستهدف',
                                          icon: const Icon(
                                            Icons.edit_rounded,
                                            size: 18.0,
                                          ),
                                          onPressed: () =>
                                              _openTargetFormDialog(
                                            existing: item,
                                          ),
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
                                              await widget.apiClient
                                                  .deleteTarget(
                                                id: item.id,
                                                targetType: widget.targetType,
                                              );
                                              if (!context.mounted) return;
                                              M3Feedback.showSuccess(
                                                context,
                                                'تم حذف المستهدف بنجاح',
                                              );
                                              _repo.invalidateAll();
                                              await _loadTargets();
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              M3Feedback.showError(
                                                context,
                                                'تعذّر حذف المستهدف. حاول مرة أخرى.',
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
                      ],
                    ),
        ),

        // 4. Comprehensive 3-Tier Hierarchical Drill-Down Workspace (For Sell-In)
        if (_isSellIn && activeTarget != null && activeTarget.branches.isNotEmpty) ...[
          M3Spacing.gapMD,
          _buildComprehensiveSellInWorkspace(
            context,
            theme,
            colorScheme,
            activeTarget,
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyTargetsState(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 42.0,
        horizontal: 24.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_tree_rounded,
            size: 48.0,
            color: colorScheme.primary.withOpacity(0.75),
          ),
          const SizedBox(height: 14.0),
          Text(
            _isSellIn
                ? 'لا توجد مستهدفات لهذه الفترة بعد.'
                : 'لا توجد مستهدفات لهذه الفترة بعد.',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8.0),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680.0),
            child: Text(
              _isSellIn
                  ? 'أضف مستهدفًا للسلسلة وسنوزّعه تلقائيًا على الفروع والأصناف.'
                  : 'أضف مستهدفًا أو ارفع ملف المستهدفات لمقارنته بالمحقق.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 18.0),
          Wrap(
            spacing: 12.0,
            runSpacing: 10.0,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => _openTargetFormDialog(),
                icon: const Icon(Icons.add_task_rounded),
                label: const Text('إضافة مستهدف'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // COMPREHENSIVE 3-TIER HIERARCHICAL DRILL-DOWN WORKSPACE (CHAIN -> BRANCH -> SKU)
  // ===========================================================================
  Widget _buildComprehensiveSellInWorkspace(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    TargetComparisonModel target,
  ) {
    final activeBranch = _getActiveBranch(target);

    return Container(
      padding: M3Spacing.pSm,
      decoration: BoxDecoration(
        color: M3TableSurface.color(colorScheme),
        borderRadius: M3Shape.radiusLg,
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.35),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A. Interactive Breadcrumb Header & Chain Intelligence Strip
          Container(
            padding: const EdgeInsets.all(14.0),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.28),
              borderRadius: M3Shape.radiusLg,
              border: Border.all(
                color: colorScheme.primary.withOpacity(0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.account_tree_rounded,
                      color: colorScheme.primary,
                      size: 24.0,
                    ),
                    Text(
                      'توزيع المستهدف:',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.primary,
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.storefront_rounded, size: 18.0),
                      label: Text(
                        '1. السلسلة: ${target.chainDisplayName} (${target.monthLabel})',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onPressed: () => setState(() => _drillSubTab = 0),
                    ),
                    const Icon(AppIcons.chevronEnd, size: 18.0),
                    ActionChip(
                      avatar:
                          const Icon(Icons.location_city_rounded, size: 18.0),
                      backgroundColor: _drillSubTab == 0
                          ? colorScheme.primaryContainer
                          : null,
                      label: Text(
                        '2. فروع السلسلة (${target.branches.length} فرع)',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onPressed: () => setState(() => _drillSubTab = 0),
                    ),
                    if (activeBranch != null) ...[
                      const Icon(AppIcons.chevronEnd, size: 18.0),
                      ActionChip(
                        avatar: const Icon(
                          Icons.inventory_2_rounded,
                          size: 18.0,
                        ),
                        backgroundColor: _drillSubTab == 1
                            ? colorScheme.primaryContainer
                            : null,
                        label: Text(
                          '3. أصناف: ${activeBranch.branchName} (${activeBranch.skus.length} صنف)',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onPressed: () => setState(() {
                          _drillSubTab = 1;
                          _skuPage = 0;
                        }),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10.0),
                const Divider(height: 1.0),
                const SizedBox(height: 10.0),
                // Smart Intelligence Pills (Gross Target w/ Return Buffer, Promo vs Regular, MT vs CC, Tonnage)
                Wrap(
                  spacing: 10.0,
                  runSpacing: 8.0,
                  children: [
                    _buildInfoPill(
                      context,
                      icon: Icons.inventory_rounded,
                      label:
                          'الكمية المستهدفة للسلسلة: ${CurrencyFormatter.formatNumber(target.targetUnits.round())} كرتونة (${target.targetWeightTons.toStringAsFixed(1)} طن)',
                      color: colorScheme.primary,
                    ),
                    _buildInfoPill(
                      context,
                      icon: Icons.shield_rounded,
                      label:
                          'Sell-In شامل احتياطي المرتجعات (+${target.historicalReturnRatePct.toStringAsFixed(1)}%): ${CurrencyFormatter.formatNumber(target.grossTargetUnits.round())} كرتونة (${CurrencyFormatter.formatCompactEGP(target.grossTargetRevenueEgp)})',
                      color: M3StatusColors.of(context).accents.teal,
                    ),
                    _buildInfoPill(
                      context,
                      icon: Icons.local_offer_rounded,
                      label:
                          'مزيج التوريد: عادي ${CurrencyFormatter.formatCompactEGP(target.regularTargetRevenueEgp)} • عروض (${target.promoSharePct.toStringAsFixed(1)}%) ${CurrencyFormatter.formatCompactEGP(target.promoTargetRevenueEgp)}',
                      color: M3StatusColors.of(context).accents.alert,
                    ),
                    _buildInfoPill(
                      context,
                      icon: Icons.category_rounded,
                      label:
                          'القطاعات: منظفات ${CurrencyFormatter.formatCompactEGP(target.mtTargetRevenueEgp)} • العناية بالسيارات ${CurrencyFormatter.formatCompactEGP(target.ccTargetRevenueEgp)}',
                      color: M3StatusColors.of(context).accents.indigo,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16.0),

          // B. 5 Sub-Tabs Switcher for the Comprehensive Target Breakdown
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSubTabButton(
                  context,
                  index: 0,
                  icon: Icons.store_mall_directory_rounded,
                  label:
                      '1. الفروع (${target.branches.length})',
                ),
                const SizedBox(width: 8.0),
                _buildSubTabButton(
                  context,
                  index: 1,
                  icon: Icons.receipt_long_rounded,
                  label:
                      '2. أصناف الفرع (${activeBranch?.skus.length ?? 0})',
                ),
                const SizedBox(width: 8.0),
                _buildSubTabButton(
                  context,
                  index: 2,
                  icon: Icons.warehouse_rounded,
                  label:
                      '3. أصناف السلسلة (${target.chainSkuTotals.length})',
                ),
                const SizedBox(width: 8.0),
                _buildSubTabButton(
                  context,
                  index: 3,
                  icon: Icons.badge_rounded,
                  label:
                      '4. المناديب والعلامات التجارية (${target.salesRepQuotas.length})',
                ),
                const SizedBox(width: 8.0),
                _buildSubTabButton(
                  context,
                  index: 4,
                  icon: Icons.calendar_month_rounded,
                  label:
                      '5. التوزيع الشهري (${target.monthlyPhasing.length})',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16.0),

          // C. Active Sub-View Content
          if (_drillSubTab == 0)
            _buildBranchesBreakdownView(context, theme, colorScheme, target)
          else if (_drillSubTab == 1 && activeBranch != null)
            _buildBranchSkusBreakdownView(
              context,
              theme,
              colorScheme,
              target,
              activeBranch,
            )
          else if (_drillSubTab == 2)
            _buildChainTotalSkusView(context, theme, colorScheme, target)
          else if (_drillSubTab == 3)
            _buildRepsAndBrandsQuotaView(context, theme, colorScheme, target)
          else
            _buildMonthlyPhasingView(context, theme, colorScheme, target),
        ],
      ),
    );
  }

  Widget _buildInfoPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: M3Shape.radiusSm,
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18.0, color: color),
          const SizedBox(width: 6.0),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabButton(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _drillSubTab == index;
    return FilledButton.tonalIcon(
      onPressed: () => setState(() {
        _drillSubTab = index;
        _skuPage = 0;
      }),
      icon: Icon(
        icon,
        size: 18.0,
        color: selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
      ),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: selected
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest.withOpacity(0.6),
        foregroundColor:
            selected ? colorScheme.onPrimary : colorScheme.onSurface,
        minimumSize: const Size(0.0, M3ToolbarButton.height),
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        shape: M3ToolbarButton.shape,
      ),
    );
  }

  // ===========================================================================
  // SUB-VIEW 0 (LEVEL 2): CHAIN BRANCHES TARGET BREAKDOWN
  // ===========================================================================
  Widget _buildBranchesBreakdownView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    TargetComparisonModel target,
  ) {
    final q = _branchSearchQuery.trim().toLowerCase();
    final filteredBranches = target.branches.where((b) {
      if (_branchRegionFilter != 'all' &&
          b.regionCode.toUpperCase() != _branchRegionFilter) {
        return false;
      }
      if (q.isNotEmpty) {
        final matchName = b.branchName.toLowerCase().contains(q);
        final matchCode = b.branchCode.toLowerCase().contains(q);
        final matchGov = b.governorate.toLowerCase().contains(q);
        final matchRep = b.salesRep.toLowerCase().contains(q);
        if (!matchName && !matchCode && !matchGov && !matchRep) return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12.0,
          runSpacing: 10.0,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                M3SectionTitle('المستهدف حسب الفرع (${filteredBranches.length} من ${target.branches.length})'),
                const SizedBox(height: 2.0),
                Text(
                  'اضغط على الفرع لعرض أصنافه.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 10.0,
              runSpacing: 8.0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 175.0,
                  child: M3Dropdown<String>(
value: _branchRegionFilter,
label: 'الإقليم / المحافظة',
options: m3OptionsFromMenuItems<String>([
                      const DropdownMenuItem(value: 'all', child: Text('كل الأقاليم')),
                      const DropdownMenuItem(
                        value: 'ALX',
                        child: Text('الإسكندرية ومطروح (ALX)'),
                      ),
                      const DropdownMenuItem(
                        value: 'CIR',
                        child: Text('القاهرة الكبرى (CIR)'),
                      ),
                      const DropdownMenuItem(
                        value: 'TNT',
                        child: Text('الغربية وطنطا (TNT)'),
                      ),
                      const DropdownMenuItem(
                        value: 'BHR',
                        child: Text('البحيرة ودمنهور (BHR)'),
                      ),
                      const DropdownMenuItem(
                        value: 'MNS',
                        child: Text('المنصورة ودمياط (MNS)'),
                      ),
                    ]),
onChanged: m3Legacy<String>((v) {
                      if (v != null) setState(() => _branchRegionFilter = v);
                    }),
),
                ),
                SizedBox(
                  width: 240.0,
                  child: TextField(
                    onChanged: (v) => setState(() => _branchSearchQuery = v),
                    decoration: const InputDecoration(
                      hintText: 'ابحث باسم الفرع أو الكود أو المندوب...',
                      prefixIcon: Icon(Icons.search_rounded, size: 18.0),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10.0,
                        vertical: 10.0,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: M3Shape.radiusSm,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12.0),
        TableScrollContainer(
          showSwipeHint: true,
          child: DataTable(
            showCheckboxColumn: false,
            headingRowColor: WidgetStatePropertyAll(
              colorScheme.surfaceContainerHigh.withOpacity(0.55),
            ),
            columns: const [
              DataColumn(label: Text('الفرع (Branch)')),
              DataColumn(label: Text('الإقليم والمندوب المسؤول')),
              DataColumn(numeric: true, label: Text('حصة الفرع %')),
              DataColumn(
                numeric: true,
                label: Text('المستهدف للفرع'),
              ),
              DataColumn(
                numeric: true,
                label: Text('كمية الفرع المستهدفة (كرتونة)'),
              ),
              DataColumn(
                numeric: true,
                label: Text('الوزن (طن)'),
              ),
              DataColumn(
                numeric: true,
                label: Text('المحقق (ج.م / كرتونة)'),
              ),
              DataColumn(
                numeric: true,
                label: Text('الفرق (ج.م)'),
              ),
              DataColumn(label: Text('نسبة التحقيق %')),
              DataColumn(label: Text('الأصناف')),
            ],
            rows: filteredBranches.map((b) {
              final isPositive = b.varianceRevenueEgp >= 0;
              final badgeColor = b.achievementRevPct >= 100
                  ? M3StatusColors.of(context).accents.positive
                  : (b.achievementRevPct >= 85
                      ? M3StatusColors.of(context).accents.caution
                      : colorScheme.error);
              return DataRow(
                selected: b.branchName == _selectedBranchName,
                onSelectChanged: (_) {
                  setState(() {
                    _selectedBranchName = b.branchName;
                    _drillSubTab = 1;
                    _skuPage = 0;
                  });
                },
                cells: [
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          b.branchName,
                          style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(                             fontWeight: FontWeight.w800,                             fontSize: M3FontSize.bodyMedium,                           )),
                        ),
                        Text(
                          'كود: ${b.branchCode} • ${b.activeSkusCount} صنف',
                          style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                             fontSize: M3FontSize.labelSmall,                             color: colorScheme.onSurfaceVariant,                           )),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${b.governorate} (${b.regionCode})',
                          style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(                             fontWeight: FontWeight.w700,                             fontSize: M3FontSize.bodySmall,                           )),
                        ),
                        Text(
                          'المندوب: ${b.salesRep}',
                          style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                             fontSize: M3FontSize.labelSmall,                             color: colorScheme.onSurfaceVariant,                           )),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      '${b.shareOfChainPct.toStringAsFixed(2)}%',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  DataCell(
                    Text(
                      CurrencyFormatter.formatEGP(b.targetRevenueEgp),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${CurrencyFormatter.formatNumber(b.targetUnits.round())} كرتونة',
                          style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(                             fontWeight: FontWeight.w800,                             fontSize: M3FontSize.bodyMedium,                           )),
                        ),
                        Text(
                          'شامل المرتجع: ${CurrencyFormatter.formatNumber(b.grossTargetUnits.round())} كرتونة',
                          style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                             fontSize: M3FontSize.labelSmall,                             color: M3StatusColors.of(context).accents.teal,                             fontWeight: FontWeight.w700,                           )),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      '${b.targetWeightTons.toStringAsFixed(2)} طن',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: M3StatusColors.of(context).accents.indigo,
                      ),
                    ),
                  ),
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          CurrencyFormatter.formatEGP(b.actualRevenueEgp),
                          style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(                             fontWeight: FontWeight.w800,                             fontSize: M3FontSize.bodySmall,                           )),
                        ),
                        Text(
                          '${CurrencyFormatter.formatNumber(b.actualUnits.round())} كرتونة',
                          style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                             fontSize: M3FontSize.labelSmall,                             color: colorScheme.onSurfaceVariant,                           )),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${isPositive ? '+' : ''}${CurrencyFormatter.formatEGP(b.varianceRevenueEgp)}',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: isPositive                                 ? M3StatusColors.of(context).accents.positive                                 : colorScheme.error),
                        ),
                        Text(
                          '${b.varianceUnits >= 0 ? '+' : ''}${CurrencyFormatter.formatNumber(b.varianceUnits.round())} كرتونة',
                          style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                             fontSize: M3FontSize.labelSmall,                             color: isPositive                                 ? M3StatusColors.of(context).accents.positive                                 : colorScheme.error,                           )),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    M3ChipSurface(
                      color: badgeColor.withOpacity(0.12),
                      child: Text(
                        '${b.achievementRevPct.toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: badgeColor),
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10.0,
                              vertical: 6.0,
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _selectedBranchName = b.branchName;
                              _drillSubTab = 1;
                              _skuPage = 0;
                            });
                          },
                          icon: const Icon(
                            Icons.inventory_2_rounded,
                            size: 18.0,
                          ),
                          label: Text(
                            'أصناف الفرع (${b.skus.length})',
                            style: M3TextVariants.cellHeavy,
                          ),
                        ),
                        const SizedBox(width: 4.0),
                        IconButton(
                          tooltip: 'تعديل مستهدف الفرع',
                          icon: const Icon(Icons.tune_rounded, size: 18.0),
                          onPressed: () => _openTargetFormDialog(
                            prefillChain: target.retailerChain,
                            prefillYear: target.year,
                            prefillBranch: b.branchName,
                            prefillRev: b.targetRevenueEgp,
                            prefillUnits: b.targetUnits,
                          ),
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
    );
  }

  // ===========================================================================
  // SUB-VIEW 1 (LEVEL 3): SKUs & GOODS INSIDE THE SELECTED BRANCH
  // ===========================================================================
  Widget _buildBranchSkusBreakdownView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    TargetComparisonModel target,
    TargetBranchBreakdownModel branch,
  ) {
    final brands = <String>{'all'};
    for (final s in branch.skus) {
      if (s.brand.trim().isNotEmpty) brands.add(s.brand.trim());
    }

    final q = _skuSearchQuery.trim().toLowerCase();
    final filteredSkus = branch.skus.where((s) {
      if (_skuBrandFilter != 'all' && s.brand != _skuBrandFilter) return false;
      if (_skuSectorFilter != 'all' &&
          s.sector.toUpperCase() != _skuSectorFilter) {
        return false;
      }
      if (_skuStockStatusFilter != 'all' &&
          s.stockStatus != _skuStockStatusFilter) {
        return false;
      }
      if (q.isNotEmpty) {
        final mName = s.skuName.toLowerCase().contains(q);
        final mBrand = s.brand.toLowerCase().contains(q);
        final mCat = s.subCategory.toLowerCase().contains(q);
        final mCode = s.itemCode.toLowerCase().contains(q);
        final mBar = s.barcode.toLowerCase().contains(q);
        if (!mName && !mBrand && !mCat && !mCode && !mBar) return false;
      }
      return true;
    }).toList();

    final totalPages =
        (filteredSkus.length / _skuPageSize).ceil().clamp(1, 9999);
    final safePage = _skuPage.clamp(0, totalPages - 1);
    final startIdx = safePage * _skuPageSize;
    final endIdx = (startIdx + _skuPageSize).clamp(0, filteredSkus.length);
    final pageSkus = filteredSkus.sublist(startIdx, endIdx);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Branch Selector & Summary Bar
        Container(
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh.withOpacity(0.45),
            borderRadius: M3Shape.radiusMd,
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
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _drillSubTab = 0),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18.0),
                    label: const Text('العودة لكل الفروع'),
                  ),
                  const SizedBox(width: 12.0),
                  SizedBox(
                    width: 310.0,
                    child: M3Dropdown<String>(
value: branch.branchName,
label: 'الفرع',
expand: true,
options: m3OptionsFromMenuItems<String>(target.branches
                          .map(
                            (b) => DropdownMenuItem<String>(
                              value: b.branchName,
                              child: Text(
                                '${b.branchName} (${CurrencyFormatter.formatNumber(b.targetUnits.round())} كرتونة)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList()),
onChanged: m3Legacy<String>((v) {
                        if (v != null) {
                          setState(() {
                            _selectedBranchName = v;
                            _skuPage = 0;
                          });
                        }
                      }),
),
                  ),
                ],
              ),
              Wrap(
                spacing: 12.0,
                runSpacing: 8.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildInfoPill(
                    context,
                    icon: Icons.payments_rounded,
                    label:
                        'مستهدف الفرع: ${CurrencyFormatter.formatEGP(branch.targetRevenueEgp)} (${branch.shareOfChainPct.toStringAsFixed(2)}% من السلسلة)',
                    color: colorScheme.primary,
                  ),
                  _buildInfoPill(
                    context,
                    icon: Icons.inventory_2_rounded,
                    label:
                        'كمية الفرع: ${CurrencyFormatter.formatNumber(branch.targetUnits.round())} كرتونة • ${branch.targetWeightTons.toStringAsFixed(2)} طن',
                    color: M3StatusColors.of(context).accents.teal,
                  ),
                  _buildInfoPill(
                    context,
                    icon: Icons.person_outline_rounded,
                    label: 'المندوب: ${branch.salesRep}',
                    color: M3StatusColors.of(context).accents.indigo,
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _exportBranchSkusExcel(target, branch),
                    icon: const Icon(Icons.download_rounded, size: 18.0),
                    label: const Text('تصدير أصناف الفرع'),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12.0),

        // SKU Filter Bar (Brand, Sector, Stock Health, Search)
        _buildSkuFilterToolbar(context, brands.toList(), filteredSkus.length),

        const SizedBox(height: 12.0),

        // Branch SKUs Table
        _buildSkuBreakdownDataTable(
          context,
          theme,
          colorScheme,
          pageSkus,
          scopeLabel: branch.branchName,
        ),

        const SizedBox(height: 10.0),
        _buildPaginationFooter(
          context,
          totalItems: filteredSkus.length,
          currentPage: safePage,
          totalPages: totalPages,
          onPageChanged: (next) => setState(() => _skuPage = next),
        ),
      ],
    );
  }

  // ===========================================================================
  // SUB-VIEW 2: CHAIN-WIDE TOTAL SKUs ROLLUP (إجمالي البضاعة المطلوبة للسلسلة)
  // ===========================================================================
  Widget _buildChainTotalSkusView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    TargetComparisonModel target,
  ) {
    final brands = <String>{'all'};
    for (final s in target.chainSkuTotals) {
      if (s.brand.trim().isNotEmpty) brands.add(s.brand.trim());
    }

    final q = _skuSearchQuery.trim().toLowerCase();
    final filteredSkus = target.chainSkuTotals.where((s) {
      if (_skuBrandFilter != 'all' && s.brand != _skuBrandFilter) return false;
      if (_skuSectorFilter != 'all' &&
          s.sector.toUpperCase() != _skuSectorFilter) {
        return false;
      }
      if (_skuStockStatusFilter != 'all' &&
          s.stockStatus != _skuStockStatusFilter) {
        return false;
      }
      if (q.isNotEmpty) {
        final mName = s.skuName.toLowerCase().contains(q);
        final mBrand = s.brand.toLowerCase().contains(q);
        final mCat = s.subCategory.toLowerCase().contains(q);
        final mCode = s.itemCode.toLowerCase().contains(q);
        final mBar = s.barcode.toLowerCase().contains(q);
        if (!mName && !mBrand && !mCat && !mCode && !mBar) return false;
      }
      return true;
    }).toList();

    final totalPages =
        (filteredSkus.length / _skuPageSize).ceil().clamp(1, 9999);
    final safePage = _skuPage.clamp(0, totalPages - 1);
    final startIdx = safePage * _skuPageSize;
    final endIdx = (startIdx + _skuPageSize).clamp(0, filteredSkus.length);
    final pageSkus = filteredSkus.sublist(startIdx, endIdx);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M3SectionTitle('أصناف السلسلة (${target.chainSkuTotals.length} صنف)'),
        const SizedBox(height: 4.0),
        Text(
          'الإجمالي لكل صنف في كل الفروع',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12.0),
        _buildSkuFilterToolbar(context, brands.toList(), filteredSkus.length),
        const SizedBox(height: 12.0),
        _buildSkuBreakdownDataTable(
          context,
          theme,
          colorScheme,
          pageSkus,
          scopeLabel: 'إجمالي ${target.chainDisplayName}',
        ),
        const SizedBox(height: 10.0),
        _buildPaginationFooter(
          context,
          totalItems: filteredSkus.length,
          currentPage: safePage,
          totalPages: totalPages,
          onPageChanged: (next) => setState(() => _skuPage = next),
        ),
      ],
    );
  }

  Widget _buildSkuFilterToolbar(
    BuildContext context,
    List<String> brands,
    int matchedCount,
  ) {
    return Wrap(
      spacing: 10.0,
      runSpacing: 8.0,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Wrap(
          spacing: 10.0,
          runSpacing: 8.0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 170.0,
              child: M3Dropdown<String>(
value: brands.contains(_skuBrandFilter) ? _skuBrandFilter : 'all',
label: 'العلامة التجارية',
expand: true,
options: m3OptionsFromMenuItems<String>(brands
                    .map(
                      (b) => DropdownMenuItem<String>(
                        value: b,
                        child: Text(
                          b == 'all' ? 'كل العلامات التجارية' : b,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList()),
onChanged: m3Legacy<String>((v) {
                  if (v != null) {
                    setState(() {
                      _skuBrandFilter = v;
                      _skuPage = 0;
                    });
                  }
                }),
),
            ),
            SizedBox(
              width: 165.0,
              child: M3Dropdown<String>(
value: _skuSectorFilter,
label: 'القطاع (Sector)',
options: m3OptionsFromMenuItems<String>([
                  const DropdownMenuItem(value: 'all', child: Text('كل القطاعات')),
                  const DropdownMenuItem(
                    value: 'MT',
                    child: Text('منظفات'),
                  ),
                  const DropdownMenuItem(
                    value: 'CC',
                    child: Text('العناية بالسيارات'),
                  ),
                ]),
onChanged: m3Legacy<String>((v) {
                  if (v != null) {
                    setState(() {
                      _skuSectorFilter = v;
                      _skuPage = 0;
                    });
                  }
                }),
),
            ),
            SizedBox(
              width: 195.0,
              child: M3Dropdown<String>(
value: _skuStockStatusFilter,
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
                    child: Text('مخزون زائد'),
                  ),
                ]),
onChanged: m3Legacy<String>((v) {
                  if (v != null) {
                    setState(() {
                      _skuStockStatusFilter = v;
                      _skuPage = 0;
                    });
                  }
                }),
),
            ),
            SizedBox(
              width: 240.0,
              child: TextField(
                onChanged: (v) => setState(() {
                  _skuSearchQuery = v;
                  _skuPage = 0;
                }),
                decoration: const InputDecoration(
                  hintText: 'ابحث بالصنف أو الباركود',
                  prefixIcon: Icon(Icons.search_rounded, size: 18.0),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10.0,
                    vertical: 10.0,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: M3Shape.radiusSm,
                  ),
                ),
              ),
            ),
          ],
        ),
        Text(
          'إجمالي الأصناف المطابقة: $matchedCount صنف',
          style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(fontWeight: FontWeight.w800, fontSize: M3FontSize.bodySmall)),
        ),
      ],
    );
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
          'الصنف غير موجود في قائمة الأسعار.',
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
          _loadTargets();
        },
      );
    } catch (e) {
      if (!mounted) return;
      M3Feedback.showError(context, 'تعذّر فتح بيانات الصنف.');
    }
  }

  Widget _buildSkuBreakdownDataTable(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    List<TargetSKUBreakdownModel> skus, {
    required String scopeLabel,
  }) {
    return TableScrollContainer(
      showSwipeHint: true,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerHigh.withOpacity(0.55),
        ),
        columns: [
          DataColumn(label: Text('الصنف ($scopeLabel)')),
          const DataColumn(label: Text('العلامة التجارية والقطاع')),
          const DataColumn(numeric: true, label: Text('حصة الصنف %')),
          const DataColumn(numeric: true, label: Text('سعر الكرتونة (الخطة مقابل القائمة)')),
          const DataColumn(
            numeric: true,
            label: Text('الكمية المستهدفة (كرتونة / وحدة)'),
          ),
          const DataColumn(
            numeric: true,
            label: Text('القيمة المستهدفة'),
          ),
          const DataColumn(numeric: true, label: Text('الوزن (طن)')),
          const DataColumn(
            numeric: true,
            label: Text('المحقق (ج.م / كرتونة)'),
          ),
          const DataColumn(
            numeric: true,
            label: Text('المتبقي'),
          ),
          const DataColumn(label: Text('حالة المخزون')),
        ],
        rows: skus.map((s) {
          final isPositive = s.varianceRevenueEgp >= 0;
          final stockColor = s.stockStatus == 'urgent_replenishment'
              ? colorScheme.error
              : (s.stockStatus == 'overstock'
                  ? M3StatusColors.of(context).accents.caution
                  : M3StatusColors.of(context).accents.positive);
          final packUnits = s.unitsPerCarton > 0 ? s.unitsPerCarton : 12;
          final targetPieces = s.targetPieces > 0
              ? s.targetPieces
              : (s.targetUnits * packUnits).round();
          final actualPieces = s.actualPieces > 0
              ? s.actualPieces
              : (s.actualUnits * packUnits).round();

          return DataRow(
            cells: [
              DataCell(
                InkWell(
                  borderRadius: M3Shape.radiusSm,
                  onTap: () => _openProductIdCard(
                    itemCode: s.itemCode,
                    barcode: s.barcode,
                    skuName: s.skuName,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 290.0),
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
                                  s.skuName,
                                  style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(                                     fontWeight: FontWeight.w800,                                     fontSize: M3FontSize.bodySmall,                                   )),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4.0),
                              Icon(
                                Icons.badge_rounded,
                                size: 18.0,
                                color: colorScheme.primary,
                              ),
                            ],
                          ),
                          if (s.itemCode.isNotEmpty || s.barcode.isNotEmpty)
                            Text(
                              'كود: ${s.itemCode.isNotEmpty ? s.itemCode : "-"} • باركود: ${s.barcode.isNotEmpty ? s.barcode : "-"} • $packUnits وحدة/كرتونة',
                              style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                 fontFamily: 'monospace',                                 fontSize: M3FontSize.labelSmall,                                 fontWeight: FontWeight.w700,                                 color: colorScheme.primary,                               )),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          else if (s.subCategory.isNotEmpty)
                            Text(
                              '${s.subCategory} • $packUnits وحدة/كرتونة',
                              style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                                 fontSize: M3FontSize.labelSmall,                                 color: colorScheme.onSurfaceVariant,                               )),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
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
                      '${s.brand} (${s.sector})',
                      style: M3TextVariants.cellPlusBold,
                    ),
                    if (s.departmentAr.isNotEmpty)
                      Text(
                        s.departmentAr,
                        style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                           fontSize: M3FontSize.labelSmall,                           color: colorScheme.onSurfaceVariant,                         )),
                      ),
                  ],
                ),
              ),
              DataCell(Text('${s.sharePct.toStringAsFixed(2)}%')),
              DataCell(
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormatter.formatEGP(s.casePriceEgp),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (s.officialCartonExclVatEgp > 0)
                      Text(
                        'القائمة: ${CurrencyFormatter.formatEGP(s.officialCartonExclVatEgp)}',
                        style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                           fontSize: M3FontSize.labelSmall,                           color: colorScheme.onSurfaceVariant,                         )),
                      ),
                  ],
                ),
              ),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10.0,
                    vertical: 4.0,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.55),
                    borderRadius: M3Shape.radiusSm,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${CurrencyFormatter.formatNumber(s.targetUnits.round())} كرتونة',
                        style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                           fontWeight: FontWeight.w900,                           color: colorScheme.primary,                           fontSize: M3FontSize.bodyMedium,                         )),
                      ),
                      Text(
                        '${CurrencyFormatter.formatNumber(targetPieces)} وحدة ($packUnits وحدات/كرتونة)',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: M3StatusColors.of(context).accents.tealStrong),
                      ),
                    ],
                  ),
                ),
              ),
              DataCell(
                Text(
                  CurrencyFormatter.formatEGP(s.targetRevenueEgp),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              DataCell(
                Text(
                  '${s.targetWeightTons.toStringAsFixed(2)} طن',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: M3StatusColors.of(context).accents.indigo,
                  ),
                ),
              ),
              DataCell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${CurrencyFormatter.formatNumber(s.actualUnits.round())} كرتونة (${CurrencyFormatter.formatNumber(actualPieces)} وحدة)',
                      style: M3TextVariants.cellPlusHeavy,
                    ),
                    Text(
                      CurrencyFormatter.formatEGP(s.actualRevenueEgp),
                      style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                         fontSize: M3FontSize.labelSmall,                         color: colorScheme.onSurfaceVariant,                       )),
                    ),
                  ],
                ),
              ),
              DataCell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${s.varianceUnits >= 0 ? '+' : ''}${CurrencyFormatter.formatNumber(s.varianceUnits.round())} كرتونة',
                      style: M3TextVariants.cellPlusHeavy.copyWith(color: isPositive
                            ? M3StatusColors.of(context).accents.positive
                            : colorScheme.error),
                    ),
                    Text(
                      '${isPositive ? '+' : ''}${CurrencyFormatter.formatEGP(s.varianceRevenueEgp)}',
                      style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                         fontSize: M3FontSize.labelSmall,                         color: isPositive                             ? M3StatusColors.of(context).accents.positive                             : colorScheme.error,                       )),
                    ),
                  ],
                ),
              ),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9.0,
                    vertical: 4.0,
                  ),
                  decoration: BoxDecoration(
                    color: stockColor.withOpacity(0.12),
                    borderRadius: M3Shape.radiusSm,
                  ),
                  child: Text(
                    '${s.stockStatusAr} (${s.remainingStockCases.round()} كرتونة)',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: stockColor),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPaginationFooter(
    BuildContext context, {
    required int totalItems,
    required int currentPage,
    required int totalPages,
    required ValueChanged<int> onPageChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'صفحة ${currentPage + 1} من $totalPages • $totalItems صنف',
          style: Theme.of(context).textTheme.bodyMedium!.merge(const TextStyle(fontWeight: FontWeight.w700, fontSize: M3FontSize.bodySmall)),
        ),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed:
                  currentPage > 0 ? () => onPageChanged(currentPage - 1) : null,
              icon: const Icon(Icons.chevron_right_rounded, size: 18.0),
              label: const Text('السابق'),
            ),
            const SizedBox(width: 8.0),
            OutlinedButton.icon(
              onPressed: currentPage < totalPages - 1
                  ? () => onPageChanged(currentPage + 1)
                  : null,
              icon: const Icon(Icons.chevron_left_rounded, size: 18.0),
              label: const Text('التالي'),
            ),
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // SUB-VIEW 3: SALES REPS QUOTAS & BRANDS BREAKDOWN
  // ===========================================================================
  Widget _buildRepsAndBrandsQuotaView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    TargetComparisonModel target,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M3SectionTitle('مستهدف المناديب (${target.salesRepQuotas.length})'),
        const SizedBox(height: 4.0),
        Text(
          'مستهدف المندوب = مجموع فروعه وأصنافه.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10.0),
        TableScrollContainer(
          showSwipeHint: true,
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(
              colorScheme.surfaceContainerHigh.withOpacity(0.55),
            ),
            columns: const [
              DataColumn(label: Text('مندوب المبيعات')),
              DataColumn(label: Text('الإقليم / المحافظة')),
              DataColumn(numeric: true, label: Text('عدد الفروع')),
              DataColumn(numeric: true, label: Text('حصة المندوب %')),
              DataColumn(
                numeric: true,
                label: Text('المستهدف للمندوب'),
              ),
              DataColumn(
                numeric: true,
                label: Text('الكمية المستهدفة (كرتونة)'),
              ),
              DataColumn(numeric: true, label: Text('الوزن (طن)')),
              DataColumn(
                numeric: true,
                label: Text('منظفات / العناية بالسيارات'),
              ),
              DataColumn(
                numeric: true,
                label: Text('المحقق (ج.م)'),
              ),
              DataColumn(label: Text('نسبة التحقيق %')),
            ],
            rows: target.salesRepQuotas.map((r) {
              return DataRow(
                cells: [
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          r.salesRep,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'مسؤول كبار العملاء: ${r.kaOfficer}',
                          style: Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(                             fontSize: M3FontSize.labelSmall,                             color: colorScheme.onSurfaceVariant,                           )),
                        ),
                      ],
                    ),
                  ),
                  DataCell(Text('${r.governorate} (${r.regionCode})')),
                  DataCell(Text('${r.branchesCount} فرع')),
                  DataCell(Text('${r.sharePct.toStringAsFixed(1)}%')),
                  DataCell(
                    Text(
                      CurrencyFormatter.formatEGP(r.targetRevenueEgp),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${CurrencyFormatter.formatNumber(r.targetUnits.round())} كرتونة',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  DataCell(Text('${r.targetWeightTons.toStringAsFixed(1)} طن')),
                  DataCell(
                    Text(
                      'منظفات: ${CurrencyFormatter.formatCompactEGP(r.mtTargetRevenueEgp)} • العناية بالسيارات: ${CurrencyFormatter.formatCompactEGP(r.ccTargetRevenueEgp)}',
                      style: M3TextVariants.cell,
                    ),
                  ),
                  DataCell(
                    Text(
                      CurrencyFormatter.formatEGP(r.actualRevenueEgp),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${r.achievementPct.toStringAsFixed(1)}%',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 22.0),
        M3SectionTitle('المستهدف حسب العلامة التجارية (${target.brands.length})'),
        const SizedBox(height: 10.0),
        TableScrollContainer(
          showSwipeHint: true,
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(
              colorScheme.surfaceContainerHigh.withOpacity(0.55),
            ),
            columns: const [
              DataColumn(label: Text('العلامة التجارية (Brand)')),
              DataColumn(label: Text('القطاع (Sector)')),
              DataColumn(numeric: true, label: Text('عدد الأصناف')),
              DataColumn(numeric: true, label: Text('حصة العلامة التجارية %')),
              DataColumn(
                numeric: true,
                label: Text('المستهدف بالجنيه'),
              ),
              DataColumn(
                numeric: true,
                label: Text('الكمية المستهدفة (كرتونة)'),
              ),
              DataColumn(numeric: true, label: Text('الوزن (طن)')),
              DataColumn(
                numeric: true,
                label: Text('المحقق (ج.م)'),
              ),
              DataColumn(label: Text('نسبة التحقيق %')),
            ],
            rows: target.brands.map((b) {
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      b.brand,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  DataCell(Text(b.sectorNameAr)),
                  DataCell(Text('${b.activeSkusCount} صنف')),
                  DataCell(Text('${b.sharePct.toStringAsFixed(1)}%')),
                  DataCell(
                    Text(
                      CurrencyFormatter.formatEGP(b.targetRevenueEgp),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${CurrencyFormatter.formatNumber(b.targetUnits.round())} كرتونة',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  DataCell(Text('${b.targetWeightTons.toStringAsFixed(1)} طن')),
                  DataCell(
                    Text(
                      CurrencyFormatter.formatEGP(b.actualRevenueEgp),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${b.achievementPct.toStringAsFixed(1)}%',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SUB-VIEW 4: 12-MONTH SEASONALITY PHASING
  // ===========================================================================
  Widget _buildMonthlyPhasingView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    TargetComparisonModel target,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M3SectionTitle('التوزيع الشهري (${target.chainDisplayName} — ${target.year})'),
        const SizedBox(height: 4.0),
        Text(
          'يتوزّع المستهدف على الشهور حسب الموسم.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10.0),
        TableScrollContainer(
          showSwipeHint: true,
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(
              colorScheme.surfaceContainerHigh.withOpacity(0.55),
            ),
            columns: const [
              DataColumn(label: Text('الشهر (Month)')),
              DataColumn(numeric: true, label: Text('الوزن الموسمي %')),
              DataColumn(
                numeric: true,
                label: Text('مستهدف الشهر'),
              ),
              DataColumn(
                numeric: true,
                label: Text('كمية الشهر المستهدفة (كرتونة)'),
              ),
              DataColumn(numeric: true, label: Text('الوزن (طن)')),
              DataColumn(
                numeric: true,
                label: Text('المحقق (ج.م / كرتونة)'),
              ),
              DataColumn(
                numeric: true,
                label: Text('المتوقع لنهاية الشهر (ج.م)'),
              ),
              DataColumn(
                numeric: true,
                label: Text('الفرق (ج.م)'),
              ),
              DataColumn(label: Text('نسبة التحقيق %')),
            ],
            rows: target.monthlyPhasing.map((m) {
              final isPositive = m.varianceRevenueEgp >= 0;
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      m.monthLabelAr,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  DataCell(Text('${m.seasonalitySharePct.toStringAsFixed(1)}%')),
                  DataCell(
                    Text(
                      CurrencyFormatter.formatEGP(m.targetRevenueEgp),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${CurrencyFormatter.formatNumber(m.targetUnits.round())} كرتونة',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  DataCell(Text('${m.targetWeightTons.toStringAsFixed(1)} طن')),
                  DataCell(
                    Text(
                      '${CurrencyFormatter.formatEGP(m.actualRevenueEgp)} (${CurrencyFormatter.formatNumber(m.actualUnits.round())} كرتونة)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  DataCell(
                    Text(
                      CurrencyFormatter.formatEGP(m.expectedRevenueEgp),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: M3StatusColors.of(context).accents.teal,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${isPositive ? '+' : ''}${CurrencyFormatter.formatEGP(m.varianceRevenueEgp)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isPositive
                            ? M3StatusColors.of(context).accents.positive
                            : colorScheme.error,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${m.achievementPct.toStringAsFixed(1)}%',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              );
            }).toList(),
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
    bool reserveProgress = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      key: ValueKey('targets_kpi_card_$titleAr'),
      constraints: const BoxConstraints(minHeight: 145.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
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
                  borderRadius: M3Shape.radiusMd,
                ),
                child: Icon(icon, color: color, size: 24.0),
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
          if (progressPct == null && reserveProgress)
            const SizedBox(height: 14.0)
          else if (progressPct != null) ...[
            const SizedBox(height: 8.0),
            ClipRRect(
              borderRadius: M3Shape.radiusFull,
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
                    fontSize: M3FontSize.bodySmall,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

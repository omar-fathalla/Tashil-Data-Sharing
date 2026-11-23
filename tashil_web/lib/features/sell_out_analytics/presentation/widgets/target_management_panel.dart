import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_text_variants.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/data/result.dart';
import '../../../../core/network/api_client.dart';
import '../../data/target_repository.dart';
import '../../domain/target_kpi.dart';
import '../../domain/target_table_format.dart';
import 'target_breakdown_dialog.dart';
import 'target_detail_page.dart';
import 'target_status_pill.dart';
import 'sell_in_derived_targets_view.dart';
import 'share_target_wizard.dart';
import '../../domain/target_achievement_status.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/shared_display_prefix.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../../../core/widgets/table_scroll_container.dart';
import '../../../../core/widgets/m3_toolbar_button.dart';
import '../../../../core/widgets/m3_section_title.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../../../core/widgets/m3_table_surface.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';
import '../../../../core/widgets/m3_table_text.dart';
import '../../../../core/testing/test_semantics.dart';

/// TargetManagementPanel provides Target entry, Excel upload and the
/// real-time Actual vs. Target comparison for Sell-Out (مبيعات الكاشير).
///
/// Sell-In targets are not entered here: they are derived from the Sell-Out
/// targets and shown read-only by [SellInDerivedTargetsView], which this panel
/// renders when `targetType` is `sell_in`.
class TargetManagementPanel extends StatefulWidget {
  final ApiClient apiClient;
  final String targetType; // 'sell_out' or 'sell_in'

  /// Optional injected repository (tests); defaults to one wrapping [apiClient].
  final TargetRepository? repository;

  /// Fired when Sell-Out full-page detail opens/closes so the explorer can
  /// hide its tab bar (sidebar stays).
  final ValueChanged<bool>? onDetailOpenChanged;

  /// Sell-In only: opens the Sell-Out targets tab (the source of the derived
  /// Sell-In targets).
  final VoidCallback? onOpenSellOutTargets;

  const TargetManagementPanel({
    super.key,
    required this.apiClient,
    required this.targetType,
    this.repository,
    this.onDetailOpenChanged,
    this.onOpenSellOutTargets,
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
  TargetComparisonModel? _detailTarget;

  Map<String, String> get _branchDisplay {
    final names = <String>{};
    final items = _summary?.items;
    if (items != null) {
      for (final item in items) {
        if (item.branchName.trim().isNotEmpty && item.branchName != 'كل الفروع') {
          names.add(item.branchName);
        }
        for (final b in item.branches) {
          if (b.branchName.trim().isNotEmpty && b.branchName != 'كل الفروع') {
            names.add(b.branchName);
          }
        }
      }
    }
    return displayNamesWithoutSharedPrefix(names);
  }

  String _displayBranch(String raw) {
    if (raw.isEmpty || raw == 'كل الفروع' || raw == '—') return raw;
    return _branchDisplay[raw] ?? raw;
  }

  /// Caps so the 9-column Sell-Out table fits the live 1280 shell
  /// (250dp sidebar + 24dp page padding each side ≈ 982dp) without
  /// horizontal scrolling. Sum of caps stays under that width minus
  /// the 4dp margins and column gaps. Chain + achievement get enough
  /// room for «أسواق فتح الله» and compact «63.6% · أقل».
  static const _sellOutColMax = <double>[
    124, // السلسلة — «أسواق فتح الله»
    78, // الفترة (Period)
    96, // النطاق — «فرع المعادي»
    74, // المستهدف
    90, // المحقق
    74, // الفرق
    136, // الكمية
    116, // نسبة التحقيق — «63.6% · أقل»
    70, // إجراءات
  ];

  Widget _sellOutCap(int column, Widget child) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _sellOutColMax[column]),
      child: child,
    );
  }

  Widget _maybeSellOutCap(int column, Widget child) =>
      _isSellIn ? child : _sellOutCap(column, child);

  /// One-line cell. [tooltip] is the full exact value (money / quantity)
  /// or the unclipped label (chain / scope / period).
  Widget _sellOutLine(
    String text, {
    required int column,
    String? tooltip,
    Key? key,
    TextStyle? style,
  }) {
    final line = Text(
      text,
      key: key,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: style,
    );
    return _sellOutCap(
      column,
      tooltip == null ? line : Tooltip(message: tooltip, child: line),
    );
  }

  Widget _targetIconButton({
    required String tooltip,
    required IconData icon,
    required FutureOr<void> Function() onPressed,
    Key? key,
    Color? color,
  }) {
    final compact = !_isSellIn;
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: () {
        onPressed();
      },
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      padding: compact ? EdgeInsets.zero : null,
      constraints: compact
          ? const BoxConstraints.tightFor(width: 28, height: 32)
          : null,
      style: compact
          ? IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
              minimumSize: const Size(28, 32),
              visualDensity: VisualDensity.compact,
            )
          : null,
      icon: Icon(icon, size: compact ? 16 : 18, color: color),
    );
  }

  List<RetailChainModel> _companyChains = const [];

  String? _selectedTargetId;

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
    if (!_isSellIn) _initAndLoad();
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
        } else {
          _selectedTargetId = null;
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

  Future<void> _openAddTargetEntry() async {
    if (_isSellIn) {
      await _openTargetFormDialog();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: const RoundedRectangleBorder(
              borderRadius: M3Shape.radiusXl,
            ),
            title: Text(
              'نوع المستهدف',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    key: const ValueKey('target_type_value'),
                    leading: Icon(Icons.payments_rounded, color: cs.primary),
                    title: const Text('مستهدف بالقيمة'),
                    subtitle: const Text('إدخال القيمة أو الكمية مباشرة'),
                    onTap: () => Navigator.pop(ctx, 'value'),
                  ),
                  ListTile(
                    key: const ValueKey('target_type_share'),
                    leading:
                        Icon(Icons.pie_chart_outline_rounded, color: cs.primary),
                    title: const Text('مستهدف بالحصة السوقية'),
                    subtitle: const Text(
                      'تحديد الحصة المستهدفة لكل فئة ثم التوزيع',
                    ),
                    onTap: () => Navigator.pop(ctx, 'share'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    if (choice == 'share') {
      final saved = await showShareTargetWizard(
        context: context,
        apiClient: widget.apiClient,
        chainOptions: _chainOptions,
        initialChain: _selectedChain != 'all' ? _selectedChain : 'fathalla',
        initialYear:
            _selectedYear >= _baseCurrentYear ? _selectedYear : _baseCurrentYear,
      );
      if (saved && mounted) {
        _repo.invalidateAll();
        await _loadTargets();
      }
      return;
    }
    await _openTargetFormDialog();
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
        year: _selectedYear > 0 ? _selectedYear : _baseCurrentYear,
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

  void _setDetailTarget(TargetComparisonModel? target) {
    setState(() => _detailTarget = target);
    widget.onDetailOpenChanged?.call(target != null);
  }

  @override
  Widget build(BuildContext context) {
    if (_isSellIn) {
      return SellInDerivedTargetsView(
        apiClient: widget.apiClient,
        repository: _repo,
        onOpenSellOutTargets: widget.onOpenSellOutTargets,
      );
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final summary = _summary ?? TargetsSummaryModel.empty(widget.targetType);
    final activeTarget = _activeTargetItem;

    if (!_isSellIn && _detailTarget != null) {
      return TargetDetailPage(
        key: ValueKey('target_detail_${_detailTarget!.id}'),
        repository: _repo,
        target: _detailTarget!,
        siblings: summary.items,
        onBack: () => _setDetailTarget(null),
      );
    }

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
            const noSalesYet = 'لا توجد مبيعات بعد';
            final neutral = colorScheme.onSurfaceVariant;
            // Sell-Out KPIs share one year-scoped total: the year filter
            // already limits summary.items; when "كل السنوات" still mixes
            // future years without sales, Target/Ach/Gap all use the
            // comparable (has-sales) basis so 390M never sits next to a
            // 200M achievement denominator.
            final kpis = TargetKpis.fromSummary(summary);
            final onlyNoData = !_isSellIn && kpis.onlyNoData;
            final includesNoData = !_isSellIn && kpis.includesNoData;
            final double? achPct = _isSellIn
                ? summary.overallAchievementPct
                : (hasTargets ? kpis.achievementPct : summary.overallAchievementPct);
            final double? variance = _isSellIn
                ? summary.totalVarianceEgp
                : (hasTargets ? kpis.gapRevenue : summary.totalVarianceEgp);
            final sellOutTargetRevenue = includesNoData
                ? kpis.comparableTargetRevenue
                : summary.totalTargetRevenueEgp;
            final sellOutTargetUnits = includesNoData
                ? kpis.comparableTargetUnits
                : summary.totalTargetUnits;
            final targetUnitsText =
                '${CurrencyFormatter.formatNumber((_isSellIn ? summary.totalTargetUnits : sellOutTargetUnits).round())} $_unitLabelAr مستهدفة';
            final card1 = _buildKpiCard(
              context,
              titleAr: _isSellIn ? 'مستهدف التوريد' : 'مستهدف المبيعات',
              titleTooltip: _isSellIn ? 'مستهدف Sell-In' : 'مستهدف Sell-Out',
              titleEn: _isSellIn
                  ? 'Sell-In Target'
                  : 'Sell-Out Target',
              value: CurrencyFormatter.formatCompactEGP(
                _isSellIn
                    ? summary.totalTargetRevenueEgp
                    : sellOutTargetRevenue,
              ),
              subtitleAr: _isSellIn
                  ? '${CurrencyFormatter.formatNumber(summary.totalTargetUnits.round())} كرتونة • ${summary.totalTargetWeightTons.toStringAsFixed(1)} طن'
                  : includesNoData
                      ? 'لفترات بها مبيعات • مستهدفات قادمة مستبعدة'
                      : targetUnitsText,
              subtitleTooltip: includesNoData
                  ? 'نفس أساس نسبة التحقيق والفرق (فترات بها مبيعات). '
                      'مستهدفات بدون مبيعات مستبعدة '
                      '(${CurrencyFormatter.formatCompactEGP(kpis.noDataTargetRevenue)})'
                  : null,
              subtitleEn: _isSellIn
                  ? '+ returns: ${CurrencyFormatter.formatNumber(summary.totalGrossTargetUnits.round())} cases'
                  : 'Target $_unitLabelEn',
              icon: Icons.flag_circle_rounded,
              color: colorScheme.primary,
            );
            final card2 = _buildKpiCard(
              context,
              titleAr: _isSellIn ? 'صافي المحقق' : 'المحقق',
              titleTooltip: _isSellIn
                  ? 'المحقق صافي بعد المرتجعات (Sell-In)'
                  : 'المحقق (Sell-Out)',
              titleEn: _isSellIn
                  ? 'Actual net Sell-In after returns'
                  : 'Actual Sell-Out',
              value: onlyNoData
                  ? '—'
                  : CurrencyFormatter.formatCompactEGP(
                      summary.totalActualRevenueEgp,
                    ),
              subtitleAr: _isSellIn
                  ? '${CurrencyFormatter.formatNumber(summary.totalActualUnits.round())} كرتونة • ${summary.totalActualWeightTons.toStringAsFixed(1)} طن'
                  : onlyNoData
                      ? noSalesYet
                      : '${CurrencyFormatter.formatNumber(summary.totalActualUnits.round())} $_unitLabelAr محققة',
              subtitleEn: _isSellIn && summary.totalExpectedRevenueEgp > 0
                  ? 'Forecast: ${CurrencyFormatter.formatCompactEGP(summary.totalExpectedRevenueEgp)}'
                  : 'Actual $_unitLabelEn',
              icon: Icons.insights_rounded,
              color: M3StatusColors.of(context).accents.teal,
            );
            final achBasisTooltip = includesNoData
                ? 'محسوبة على الفترات التي بها مبيعات فقط؛ لا تشمل مستهدفات '
                    'سنوات قادمة بدون مبيعات (${CurrencyFormatter.formatCompactEGP(kpis.noDataTargetRevenue)})'
                : null;
            final card3 = _buildKpiCard(
              context,
              titleAr: 'نسبة التحقيق',
              titleTooltip: 'نسبة التحقيق الإجمالية',
              titleEn: 'Overall Achievement %',
              value: achPct == null ? '—' : '${achPct.toStringAsFixed(1)}%',
              subtitleAr: !hasTargets
                  ? noTargets
                  : achPct == null
                      ? noSalesYet
                      : achPct >= 100
                          ? (_isSellIn ? 'فوق المستهدف' : 'محقق')
                          : (achPct >=
                                  (_isSellIn
                                      ? 85
                                      : TargetAchievementStatus.nearFloor)
                              ? 'قريب من المستهدف'
                              : 'أقل من المستهدف'),
              subtitleTooltip: achBasisTooltip,
              subtitleEn: (achPct ?? 0) >= 100
                  ? 'Above target'
                  : ((achPct ?? 0) >=
                          (_isSellIn ? 85 : TargetAchievementStatus.nearFloor)
                      ? 'Near target'
                      : 'Below target'),
              icon: Icons.pie_chart_rounded,
              color: !hasTargets || achPct == null
                  ? neutral
                  : achPct >= 100
                      ? M3StatusColors.of(context).accents.positive
                      : (achPct >=
                              (_isSellIn
                                  ? 85
                                  : TargetAchievementStatus.nearFloor)
                          ? M3StatusColors.of(context).accents.caution
                          : colorScheme.error),
              progressPct: hasTargets ? achPct : null,
              reserveProgress: true,
            );
            final card4 = _buildKpiCard(
              context,
              titleAr: _isSellIn
                  ? 'الفرق'
                  : 'الفرق',
              titleEn: 'Variance',
              value: !hasTargets || variance == null
                  ? '—'
                  : _signedCompactEgp(variance),
              subtitleAr: !hasTargets
                  ? noTargets
                  : variance == null
                      ? noSalesYet
                      : _isSellIn && summary.totalBranchesCovered > 0
                          ? 'موزع على ${summary.totalBranchesCovered} فرع • ${summary.totalSkusCovered} صنف'
                          : (variance >= 0 ? 'فوق المستهدف' : 'المتبقي للمستهدف'),
              subtitleTooltip: achBasisTooltip,
              subtitleEn: (variance ?? 0) >= 0 ? 'Above target' : 'To go',
              icon: (variance ?? 0) >= 0
                  ? Icons.trending_up_rounded
                  : Icons.account_tree_rounded,
              color: !hasTargets || variance == null
                  ? neutral
                  : variance >= 0
                      ? M3StatusColors.of(context).accents.positive
                      : M3StatusColors.of(context).accents.indigo,
            );

            // Equal-height grid (as on the other tabs) so the progress bar
            // card is not taller than its siblings.
            return M3EqualHeightGrid(
              key: const ValueKey('targets_kpi_grid'),
              columns: M3KpiGridColumns.forWidth(width),
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
                  M3Dropdown<int>(
width: 190.0,
fitOptions: true,
value: [0, ..._targetPlanningYears].contains(_selectedYear)
                          ? _selectedYear
                          : 0,
label: 'سنة البيانات',
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
                  M3Dropdown<String>(
width: 240.0,
fitOptions: true,
value: _chainOptions.any((c) => c.code == _selectedChain)
                          ? _selectedChain
                          : 'all',
label: 'السلسلة',
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
                ],
              ),

              // Action Buttons — Sell-Out keeps only Add + Export (upload/template stay in code).
              Wrap(
                spacing: M3Spacing.xs,
                runSpacing: M3Spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_isSellIn)
                    FilledButton.icon(
                      onPressed: _openAddTargetEntry,
                      icon: const Icon(Icons.add_task_rounded, size: M3ToolbarButton.iconSize),
                      label: const Text('إضافة مستهدف'),
                      style: M3ToolbarButton.style,
                    )
                  else
                    TestSemantics.button(
                      identifier: TestIds.selloutTargetsAdd,
                      label: 'إضافة مستهدف',
                      onPressed: _openAddTargetEntry,
                      child: FilledButton.icon(
                        onPressed: _openAddTargetEntry,
                        icon: const Icon(Icons.add_task_rounded, size: M3ToolbarButton.iconSize),
                        label: const Text('إضافة مستهدف'),
                        style: M3ToolbarButton.style,
                      ),
                    ),
                  if (_isSellIn) ...[
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
                  ],
                  if (_isSellIn)
                    OutlinedButton.icon(
                      onPressed: _exportTargetsComparisonCsv,
                      icon: const Icon(Icons.table_view_rounded, size: M3ToolbarButton.iconSize),
                      label: const Text('تصدير'),
                      style: M3ToolbarButton.style,
                    )
                  else
                    TestSemantics.button(
                      identifier: TestIds.selloutTargetsExport,
                      label: 'تصدير',
                      onPressed: _exportTargetsComparisonCsv,
                      child: OutlinedButton.icon(
                        onPressed: _exportTargetsComparisonCsv,
                        icon: const Icon(Icons.table_view_rounded, size: M3ToolbarButton.iconSize),
                        label: const Text('تصدير'),
                        style: M3ToolbarButton.style,
                      ),
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
                              if (!_isSellIn)
                                Text(
                                  'اضغط على المستهدف لعرض توزيعه على الفروع والأصناف.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
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
                          key: const ValueKey('targets_main_table'),
                          // Scroll arrows appear only while the table
                          // actually overflows. Sell-Out columns are capped
                          // to fit a 1280 desktop, so the hint stays hidden.
                          showSwipeHint: true,
                          columnFlex: _isSellIn
                              ? const [1.3, 0.9, 1.3, 1.0, 1.0, 1.0, 1.2, 1.0, 1.3, 1.2]
                              : _sellOutColMax,
                          child: DataTable(
                            showCheckboxColumn: false,
                            headingRowColor: WidgetStatePropertyAll(
                              colorScheme.surfaceContainerHigh.withOpacity(0.5),
                            ),
                            columnSpacing: _isSellIn ? null : M3Spacing.xxs,
                            horizontalMargin: _isSellIn ? null : M3Spacing.xxs,
                            headingRowHeight: _isSellIn ? null : 40,
                            dataRowMinHeight: _isSellIn ? null : 40,
                            dataRowMaxHeight: _isSellIn ? null : 64,
                            headingTextStyle: _isSellIn
                                ? null
                                : theme.textTheme.labelMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            dataTextStyle: _isSellIn
                                ? null
                                : theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurface,
                                  ),
                            columns: [
                              for (final (i, h) in [
                                'السلسلة (Chain)',
                                'الفترة (Period)',
                                'النطاق',
                                'المستهدف',
                                'المحقق (ج.م)',
                                'الفرق (ج.م)',
                                'الكمية ($_unitLabelAr: فعلي / مستهدف)',
                                if (_isSellIn) 'الوزن بالطن (فعلي / مستهدف)',
                                'نسبة التحقيق %',
                                'إجراءات',
                              ].indexed)
                                DataColumn(
                                  headingRowAlignment: M3TableText.headingAlignment,
                                  label: _isSellIn
                                      ? M3TableText(h, maxLines: 2)
                                      : _sellOutCap(
                                          i,
                                          M3TableText(
                                            // Sell-Out: short one-line headers so
                                            // chain + achievement stay readable.
                                            switch (i) {
                                              0 => 'السلسلة',
                                              6 => 'الكمية',
                                              7 => 'التحقيق %',
                                              _ => h,
                                            },
                                            maxLines: 1,
                                          ),
                                        ),
                                ),
                            ],
                            rows: summary.items.map((item) {
                              final isSelected = item.id == activeTarget?.id;
                              // Future periods have no sales yet: «—», never 0.
                              final noSales = !_isSellIn && !item.hasActuals;
                              final isPositive = item.varianceRevenueEgp >= 0;
                              final sellOutStatus = TargetAchievementStatus.fromPct(
                                noSales ? null : item.achievementRevPct,
                                hasActuals: !noSales,
                              );
                              final badgeColor = noSales
                                  ? colorScheme.onSurfaceVariant
                                  : item.achievementRevPct >= 100
                                      ? M3StatusColors.of(context).accents.positive
                                      : (item.achievementRevPct >=
                                              (_isSellIn
                                                  ? 85
                                                  : TargetAchievementStatus.nearFloor)
                                          ? M3StatusColors.of(context).accents.caution
                                          : colorScheme.error);
                              final periodLabel = TargetTableFormat.period(
                                year: item.year,
                                month: item.month,
                                monthLabel: item.monthLabel,
                              );
                              final scopeLabel = TargetTableFormat.scope(
                                branch: _displayBranch(item.branchName),
                                category: item.category,
                              );
                              final periodTip = item.monthLabel.trim();
                              Widget centered(Widget child) =>
                                  Align(alignment: Alignment.center, child: child);
                              return DataRow(
                                key: ValueKey('targets_row_${item.id}'),
                                selected: isSelected,
                                onSelectChanged: (_) {
                                  setState(() => _selectedTargetId = item.id);
                                  _openBreakdown(item);
                                },
                                cells: [
                                  DataCell(
                                    centered(
                                      _isSellIn
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isSelected)
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
                                            )
                                          : _sellOutLine(
                                              item.chainDisplayName,
                                              column: 0,
                                              key: ValueKey(
                                                'targets_chain_${item.id}',
                                              ),
                                              tooltip: item.chainDisplayName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                    ),
                                  ),
                                  DataCell(
                                    centered(
                                      _isSellIn
                                          ? Text(item.monthLabel)
                                          : _sellOutLine(
                                              periodLabel,
                                              column: 1,
                                              key: ValueKey(
                                                'targets_period_${item.id}',
                                              ),
                                              tooltip: periodTip.isNotEmpty &&
                                                      periodTip != periodLabel
                                                  ? periodTip
                                                  : null,
                                            ),
                                    ),
                                  ),
                                  DataCell(
                                    centered(
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
                                                borderRadius: M3Shape.radiusSm,
                                              ),
                                              child: Text(
                                                '${item.branchesCount} فرع • ${item.activeSkusCount} صنف',
                                                style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.primary),
                                              ),
                                            )
                                          : _isSellIn
                                              ? Text(
                                                  '${_displayBranch(item.branchName)} • ${item.category}',
                                                  textAlign: TextAlign.center,
                                                )
                                              : _sellOutLine(
                                                  scopeLabel,
                                                  column: 2,
                                                  key: ValueKey(
                                                    'targets_scope_${item.id}',
                                                  ),
                                                  tooltip: scopeLabel,
                                                ),
                                    ),
                                  ),
                                  DataCell(
                                    centered(
                                      _isSellIn
                                          ? Text(
                                              CurrencyFormatter.formatEGP(
                                                item.targetRevenueEgp,
                                              ),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            )
                                          : _sellOutLine(
                                              TargetTableFormat.money(
                                                item.targetRevenueEgp,
                                              ),
                                              column: 3,
                                              key: ValueKey(
                                                'targets_target_money_${item.id}',
                                              ),
                                              tooltip: TargetTableFormat.moneyExact(
                                                item.targetRevenueEgp,
                                              ),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                    ),
                                  ),
                                  DataCell(
                                    centered(
                                      noSales
                                          ? _maybeSellOutCap(
                                              4,
                                              Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    '—',
                                                    key: ValueKey('targets_actual_dash_${item.id}'),
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w800,
                                                      color: colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  Text(
                                                    'لا توجد مبيعات بعد',
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    textAlign: TextAlign.center,
                                                    style: theme.textTheme.bodySmall?.copyWith(
                                                      color: colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : _isSellIn
                                              ? Text(
                                                  CurrencyFormatter.formatEGP(
                                                    item.actualRevenueEgp,
                                                  ),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    color: colorScheme.primary,
                                                  ),
                                                )
                                              : _sellOutLine(
                                                  TargetTableFormat.money(
                                                    item.actualRevenueEgp,
                                                  ),
                                                  column: 4,
                                                  key: ValueKey(
                                                    'targets_actual_money_${item.id}',
                                                  ),
                                                  tooltip: TargetTableFormat.moneyExact(
                                                    item.actualRevenueEgp,
                                                  ),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    color: colorScheme.primary,
                                                  ),
                                                ),
                                    ),
                                  ),
                                  DataCell(
                                    centered(
                                      noSales
                                          ? _maybeSellOutCap(
                                              5,
                                              Text(
                                                '—',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            )
                                          : _isSellIn
                                              ? Text(
                                                  '${isPositive ? '+' : ''}${CurrencyFormatter.formatEGP(item.varianceRevenueEgp)}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: isPositive
                                                        ? M3StatusColors.of(context).accents.positive
                                                        : colorScheme.error,
                                                  ),
                                                )
                                              : _sellOutLine(
                                                  item.varianceRevenueEgp >= 0.5
                                                      ? '\u2066+${TargetTableFormat.money(item.varianceRevenueEgp)}\u2069'
                                                      : TargetTableFormat.money(
                                                          item.varianceRevenueEgp,
                                                        ),
                                                  column: 5,
                                                  key: ValueKey(
                                                    'targets_gap_money_${item.id}',
                                                  ),
                                                  tooltip: TargetTableFormat.moneyExact(
                                                    item.varianceRevenueEgp,
                                                  ),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: isPositive
                                                        ? M3StatusColors.of(context).accents.positive
                                                        : colorScheme.error,
                                                  ),
                                                ),
                                    ),
                                  ),
                                  DataCell(
                                    centered(
                                      _isSellIn
                                          ? Text(
                                              '${noSales ? '—' : CurrencyFormatter.formatNumber(item.actualUnits.round())} / ${CurrencyFormatter.formatNumber(item.targetUnits.round())} $_unitLabelAr',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            )
                                          : _sellOutLine(
                                              TargetTableFormat.quantity(
                                                actual: noSales
                                                    ? null
                                                    : item.actualUnits,
                                                target: item.targetUnits,
                                                unit: _unitLabelAr,
                                              ),
                                              column: 6,
                                              key: ValueKey(
                                                'targets_qty_${item.id}',
                                              ),
                                              tooltip: TargetTableFormat.quantityExact(
                                                actual: noSales
                                                    ? null
                                                    : item.actualUnits,
                                                target: item.targetUnits,
                                                unit: _unitLabelAr,
                                              ),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                    ),
                                  ),
                                  if (_isSellIn)
                                    DataCell(
                                      centered(
                                        Text(
                                          '${item.actualWeightTons.toStringAsFixed(1)} / ${item.targetWeightTons.toStringAsFixed(1)} طن',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: M3StatusColors.of(context).accents.indigo,
                                          ),
                                        ),
                                      ),
                                    ),
                                  DataCell(
                                    centered(
                                      _maybeSellOutCap(
                                        7,
                                        _isSellIn
                                            ? M3ChipSurface(
                                                color: badgeColor.withOpacity(0.12),
                                                child: Text(
                                                  '${item.achievementRevPct.toStringAsFixed(1)}% (${item.statusAr})',
                                                  key: ValueKey(
                                                      'targets_achievement_${item.id}'),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        fontWeight: FontWeight.w600,
                                                        color: badgeColor,
                                                      ),
                                                ),
                                              )
                                            : KeyedSubtree(
                                                key: ValueKey(
                                                    'targets_achievement_${item.id}'),
                                                child: TargetStatusPill(
                                                  status: sellOutStatus,
                                                  compact: true,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    centered(
                                      _maybeSellOutCap(
                                      8,
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _targetIconButton(
                                              key: ValueKey('targets_breakdown_${item.id}'),
                                              tooltip: 'توزيع المستهدف على الفروع والأصناف',
                                              icon: Icons.account_tree_rounded,
                                              onPressed: () => _openBreakdown(item),
                                            ),
                                          _targetIconButton(
                                            tooltip: 'تعديل المستهدف',
                                            icon: Icons.edit_rounded,
                                            onPressed: () =>
                                                _openTargetFormDialog(
                                              existing: item,
                                            ),
                                          ),
                                          _targetIconButton(
                                            tooltip: 'حذف المستهدف',
                                            icon: Icons.delete_outline_rounded,
                                            color: colorScheme.error,
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
                  : 'أضف مستهدفًا لمقارنته بالمحقق على مستوى الشهور والفروع والأصناف.',
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
                onPressed: _openAddTargetEntry,
                icon: const Icon(Icons.add_task_rounded),
                label: const Text('إضافة مستهدف'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openBreakdown(TargetComparisonModel item) async {
    // Sell-Out option B: full-page detail inside the content area (not the
    // modal breakdown dialog). Sell-In keeps the existing workspace flow.
    if (!_isSellIn) {
      _setDetailTarget(item);
      return;
    }
    return showTargetBreakdownDialog(
      context,
      repository: _repo,
      target: item,
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
    String? titleTooltip,
    String? subtitleTooltip,
  }) {
    return M3SummaryKpiCard(
      key: ValueKey('targets_kpi_card_$titleAr'),
      title: titleAr,
      value: value,
      subtitle: subtitleAr,
      icon: icon,
      color: color,
      titleTooltip: titleTooltip,
      subtitleTooltip: subtitleTooltip,
      titleMaxLines: 1,
      subtitleMaxLines: 1,
    );
  }

  static String _signedCompactEgp(double amount) {
    if (amount < 0) return CurrencyFormatter.formatCompactEGP(amount);
    if (amount == 0) return CurrencyFormatter.formatCompactEGP(0);
    return '\u2066+${CurrencyFormatter.formatCompactEGP(amount)}\u2069';
  }

}

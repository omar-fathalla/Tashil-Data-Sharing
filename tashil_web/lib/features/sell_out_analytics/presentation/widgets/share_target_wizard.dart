import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_shape.dart';
import 'package:tashil_web/core/theme/m3_spacing.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/core/widgets/m3_dropdown.dart';
import 'package:tashil_web/core/widgets/m3_feedback.dart';
import 'package:tashil_web/core/network/api_client.dart';

import '../../data/share_target_models.dart';
import '../../domain/share_target_plan.dart';

/// 3-step Sell-Out wizard: «مستهدف بالحصة السوقية».
Future<bool> showShareTargetWizard({
  required BuildContext context,
  required ApiClient apiClient,
  required List<({String code, String label})> chainOptions,
  String initialChain = 'fathalla',
  int initialYear = 2026,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ShareTargetWizardDialog(
      apiClient: apiClient,
      chainOptions: chainOptions.where((c) => c.code != 'all').toList(),
      initialChain: initialChain == 'all' ? 'fathalla' : initialChain,
      initialYear: initialYear,
    ),
  );
  return result == true;
}

class ShareTargetWizardDialog extends StatefulWidget {
  const ShareTargetWizardDialog({
    super.key,
    required this.apiClient,
    required this.chainOptions,
    required this.initialChain,
    required this.initialYear,
  });

  final ApiClient apiClient;
  final List<({String code, String label})> chainOptions;
  final String initialChain;
  final int initialYear;

  @override
  State<ShareTargetWizardDialog> createState() =>
      _ShareTargetWizardDialogState();
}

class _ShareTargetWizardDialogState extends State<ShareTargetWizardDialog> {
  int _step = 0;
  late String _chain;
  late int _year;
  double _marketGrowthPct = 0; // Mohamed: flat default
  bool _annualize = true;
  bool _loading = false;
  String? _error;
  ShareTargetBaseline? _baseline;
  final Set<String> _selectedBranches = {};
  final Map<String, double> _desired = {};
  ShareTargetPreview? _preview;
  bool _saving = false;
  late final TextEditingController _growthCtrl;

  static const _monthNames = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  @override
  void initState() {
    super.initState();
    _chain = widget.initialChain;
    _year = widget.initialYear;
    _growthCtrl = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _growthCtrl.dispose();
    super.dispose();
  }

  SharePlanOptions get _opt => SharePlanOptions(
        marketGrowthPct: _marketGrowthPct,
        monthsWithData: _baseline?.monthsWithData ?? 12,
        annualize: _annualize,
      );

  SharePlanSummary? get _livePlan {
    final b = _baseline;
    if (b == null || b.categories.isEmpty) return null;
    final inputs = b.categories.map((c) => c.toInput()).toList();
    final desired = b.categories
        .map((c) => _desired[c.category] ?? c.currentSharePct)
        .toList();
    return planAll(inputs, desired, _opt);
  }

  Future<void> _loadBaseline() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = await widget.apiClient.getShareTargetBaseline(
        chain: _chain,
        year: _year,
      );
      if (!mounted) return;
      setState(() {
        _baseline = b;
        _selectedBranches
          ..clear()
          ..addAll(b.branches.map((e) => e.branchKey));
        _desired
          ..clear()
          ..addEntries(
            b.categories.map((c) => MapEntry(c.category, c.currentSharePct)),
          );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل حصص الفئات لهذه السلسلة.';
      });
    }
  }

  Future<void> _loadPreview() async {
    final b = _baseline;
    if (b == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await widget.apiClient.previewShareTarget(
        retailerChain: _chain,
        year: _year,
        marketGrowthPct: _marketGrowthPct,
        monthsWithData: b.monthsWithData,
        annualize: _annualize,
        branchKeys: _selectedBranches.toList(),
        categories: b.categories
            .map(
              (c) => (
                category: c.category,
                desiredSharePct: _desired[c.category] ?? c.currentSharePct,
              ),
            )
            .toList(),
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر حساب التوزيع.';
      });
    }
  }

  Future<void> _save() async {
    final plan = _livePlan;
    if (plan == null || !plan.canProceed) return;
    setState(() => _saving = true);
    try {
      await widget.apiClient.saveShareTarget(
        retailerChain: _chain,
        year: _year,
        marketGrowthPct: _marketGrowthPct,
        monthsWithData: _baseline?.monthsWithData ?? 12,
        annualize: _annualize,
        branchKeys: _selectedBranches.toList(),
        categories: (_baseline?.categories ?? const [])
            .map(
              (c) => (
                category: c.category,
                desiredSharePct: _desired[c.category] ?? c.currentSharePct,
              ),
            )
            .toList(),
      );
      if (!mounted) return;
      M3Feedback.showSuccess(context, 'تم حفظ المستهدف بالحصة السوقية.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      M3Feedback.showError(context, 'تعذّر حفظ المستهدف. حاول مرة أخرى.');
    }
  }

  void _applyDelta(double pts) {
    final b = _baseline;
    if (b == null) return;
    setState(() {
      for (final c in b.categories) {
        final exact = exactCurrentSharePct(c.toInput());
        _desired[c.category] = double.parse((exact + pts).toStringAsFixed(1));
      }
    });
  }

  Future<void> _next() async {
    if (_step == 0) {
      await _loadBaseline();
      if (_baseline == null) return;
      setState(() => _step = 1);
      return;
    }
    if (_step == 1) {
      final plan = _livePlan;
      if (plan == null || !plan.canProceed) {
        M3Feedback.showError(context, 'الحصة المستهدفة لا يمكن أن تتجاوز 100%.');
        return;
      }
      await _loadPreview();
      if (_preview == null) return;
      setState(() => _step = 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final plan = _livePlan;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusXl),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        title: Row(
          children: [
            Icon(Icons.pie_chart_outline_rounded, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'مستهدف بالحصة السوقية',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 720,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StepHeader(step: _step),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.error, fontWeight: FontWeight.w700),
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : switch (_step) {
                        0 => _buildStep1(theme, cs),
                        1 => _buildStep2(theme, cs, plan),
                        _ => _buildStep3(theme, cs, plan),
                      },
              ),
              if (_step == 1 && plan != null) _BottomBar(plan: plan),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          if (_step > 0)
            TextButton(
              onPressed: _saving || _loading
                  ? null
                  : () => setState(() => _step -= 1),
              child: const Text('السابق'),
            ),
          if (_step < 2)
            FilledButton(
              onPressed: _loading || _saving ? null : _next,
              child: const Text('التالي'),
            )
          else
            FilledButton.icon(
              onPressed: _saving ||
                      _loading ||
                      plan == null ||
                      !plan.canProceed
                  ? null
                  : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('حفظ المستهدف'),
            ),
        ],
      ),
    );
  }

  Widget _buildStep1(ThemeData theme, ColorScheme cs) {
    final years = List<int>.generate(5, (i) => widget.initialYear - 1 + i);
    if (!years.contains(_year)) years.add(_year);
    years.sort();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'الخطوة 1: نوع المستهدف والإطار',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'مستهدف بالحصة السوقية — الحصة الحالية من «مساهمة الفئات» (أدكو ÷ سوق الفئة) لنفس السلسلة فقط.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          M3Dropdown<String>(
            value: widget.chainOptions.any((c) => c.code == _chain)
                ? _chain
                : (widget.chainOptions.isNotEmpty
                    ? widget.chainOptions.first.code
                    : _chain),
            label: 'السلسلة *',
            expand: true,
            options: m3OptionsFromMenuItems<String>(
              widget.chainOptions
                  .map(
                    (c) => DropdownMenuItem(
                      value: c.code,
                      child: Text(c.label, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
            ),
            onChanged: m3Legacy<String>((v) {
              if (v != null) setState(() => _chain = v);
            }),
          ),
          const SizedBox(height: 12),
          M3Dropdown<int>(
            value: _year,
            label: 'السنة المستهدفة *',
            expand: true,
            options: m3OptionsFromMenuItems<int>(
              years
                  .map(
                    (y) => DropdownMenuItem(
                      value: y,
                      child: Text('$y'),
                    ),
                  )
                  .toList(),
            ),
            onChanged: m3Legacy<int>((v) {
              if (v != null) setState(() => _year = v);
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('share_market_growth'),
            controller: _growthCtrl,
            decoration: const InputDecoration(
              labelText: 'نمو السوق المتوقع % (افتراضي 0 — ثابت)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) {
              final n = double.tryParse(v.replaceAll(',', '').trim());
              if (n != null) setState(() => _marketGrowthPct = n);
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('سَنْوَنة سنة الأساس (×12 ÷ الشهور المتاحة)'),
            subtitle: const Text(
              'سنة 2026 الناقصة تُحوَّل لسنة كاملة بعد التحميل',
            ),
            value: _annualize,
            onChanged: (v) => setState(() => _annualize = v),
          ),
          Text(
            'الفروع تُحمَّل مع بيانات السلسلة عند «التالي» (الكل محدد افتراضيًا).',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2(
    ThemeData theme,
    ColorScheme cs,
    SharePlanSummary? plan,
  ) {
    final b = _baseline;
    if (b == null) {
      return const Center(child: Text('لا توجد بيانات.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'الخطوة 2: الحصة المستهدفة لكل فئة',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: () => _applyDelta(5),
              child: const Text('+5 نقط للكل'),
            ),
          ],
        ),
        if (b.branches.isNotEmpty) ...[
          Text(
            'الفروع المشمولة',
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final br in b.branches)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: FilterChip(
                      label: Text(br.branchName),
                      selected: _selectedBranches.contains(br.branchKey),
                      onSelected: (sel) {
                        setState(() {
                          if (sel) {
                            _selectedBranches.add(br.branchKey);
                          } else {
                            _selectedBranches.remove(br.branchKey);
                          }
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (plan?.hasBelowCurrent == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'تنبيه: بعض الفئات أقل من الحصة الحالية (تحذير فقط).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: M3StatusColors.of(context).warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (plan?.hasShareOver100 == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'حصة أكبر من 100% — لا يمكن المتابعة أو الحفظ.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.error,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        Expanded(
          child: ListView.separated(
            itemCount: b.categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final c = b.categories[i];
              final desired = _desired[c.category] ?? c.currentSharePct;
              ShareCategoryPlan? catPlan;
              if (plan != null) {
                for (final p in plan.categories) {
                  if (p.category == c.category) {
                    catPlan = p;
                    break;
                  }
                }
              }
              return _CategoryShareCard(
                category: c.category,
                currentSharePct: c.currentSharePct,
                desiredSharePct: desired,
                ownEgp: c.ownRevenueEgp,
                marketEgp: c.marketRevenueEgp,
                targetEgp: catPlan?.targetRevenueEgp ?? 0,
                upliftEgp: catPlan?.upliftRevenueEgp ?? 0,
                targetUnits: catPlan?.targetUnits ?? 0,
                belowCurrent: catPlan?.belowCurrent ?? false,
                exceedsMarket: catPlan?.exceedsMarket ?? false,
                onChanged: (v) => setState(() => _desired[c.category] = v),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStep3(
    ThemeData theme,
    ColorScheme cs,
    SharePlanSummary? plan,
  ) {
    final preview = _preview;
    if (preview == null || plan == null) {
      return const Center(child: Text('لا توجد معاينة.'));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'الخطوة 3: مراجعة التوزيع ثم الحفظ',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'الإجمالي: ${CurrencyFormatter.formatEGP(plan.totalTargetEgp)}'
            '  •  الزيادة: ${CurrencyFormatter.formatEGP(plan.totalUpliftEgp)}'
            ' (${plan.totalUpliftPct.toStringAsFixed(1)}%)'
            '  •  الكمية: ${CurrencyFormatter.formatNumber(plan.totalTargetUnits.round())}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text('الحصص', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          for (final c in plan.categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• ${c.category}: ${c.currentSharePct.toStringAsFixed(1)}% ← '
                '${c.desiredSharePct.toStringAsFixed(1)}%  = '
                '${CurrencyFormatter.formatEGP(c.targetRevenueEgp)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          Text('الفروع (عينة من أول فئة)', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          if (preview.cascades.isNotEmpty)
            for (final br in preview.cascades.first.branches.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${br.branchName}: ${CurrencyFormatter.formatEGP(br.targetEgp)}'
                  ' (وزن ${br.historicalSharePct.toStringAsFixed(1)}%)',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          if (preview.cascades.isNotEmpty &&
              preview.cascades.first.branches.isNotEmpty &&
              preview.cascades.first.branches.first.skus.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('أصناف أول فرع', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            for (final s
                in preview.cascades.first.branches.first.skus.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${s.skuName}: ${CurrencyFormatter.formatEGP(s.targetEgp)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
          if (preview.cascades.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('التوزيع الشهري (أول فئة)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            for (final m in preview.cascades.first.months)
              if (m.targetEgp > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• ${_monthNames[m.month - 1]}: '
                    '${CurrencyFormatter.formatEGP(m.targetEgp)}'
                    ' (${m.sharePct.toStringAsFixed(1)}%)',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
          ],
          const SizedBox(height: 12),
          Text(
            'بعد الحفظ يظهر المستهدف في صفحة التفاصيل كتوزيع عادي (فروع / أصناف / شهور).',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final labels = ['الإطار', 'الحصص', 'المراجعة'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: i <= step
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: M3Shape.radiusSm,
              ),
              alignment: Alignment.center,
              child: Text(
                '${i + 1}. ${labels[i]}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.plan});
  final SharePlanSummary plan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(M3Spacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: M3Shape.radiusMd,
      ),
      child: Text(
        'الإجمالي المطلوب: ${CurrencyFormatter.formatEGP(plan.totalTargetEgp)}'
        '  •  الزيادة: ${CurrencyFormatter.formatEGP(plan.totalUpliftEgp)}'
        '  •  الكمية: ${CurrencyFormatter.formatNumber(plan.totalTargetUnits.round())}',
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _CategoryShareCard extends StatefulWidget {
  const _CategoryShareCard({
    required this.category,
    required this.currentSharePct,
    required this.desiredSharePct,
    required this.ownEgp,
    required this.marketEgp,
    required this.targetEgp,
    required this.upliftEgp,
    required this.targetUnits,
    required this.belowCurrent,
    required this.exceedsMarket,
    required this.onChanged,
  });

  final String category;
  final double currentSharePct;
  final double desiredSharePct;
  final double ownEgp;
  final double marketEgp;
  final double targetEgp;
  final double upliftEgp;
  final double targetUnits;
  final bool belowCurrent;
  final bool exceedsMarket;
  final ValueChanged<double> onChanged;

  @override
  State<_CategoryShareCard> createState() => _CategoryShareCardState();
}

class _CategoryShareCardState extends State<_CategoryShareCard> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.desiredSharePct.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(covariant _CategoryShareCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.desiredSharePct.toStringAsFixed(1);
    if (_ctrl.text != next && !_ctrl.selection.isValid) {
      _ctrl.text = next;
    } else if (_ctrl.text != next &&
        double.tryParse(_ctrl.text) != widget.desiredSharePct) {
      final sel = _ctrl.selection;
      _ctrl.text = next;
      if (sel.isValid) {
        _ctrl.selection = sel;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: M3Shape.radiusMd,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.category,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  'الحالية ${widget.currentSharePct.toStringAsFixed(1)}%',
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'مبيعاتنا ${CurrencyFormatter.formatEGP(widget.ownEgp)}'
              ' من سوق ${CurrencyFormatter.formatEGP(widget.marketEgp)}',
              style: theme.textTheme.bodySmall,
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: widget.desiredSharePct.clamp(0, 100),
                    min: 0,
                    max: 100,
                    divisions: 200,
                    label: '${widget.desiredSharePct.toStringAsFixed(1)}%',
                    onChanged: (v) {
                      final n = double.parse(v.toStringAsFixed(1));
                      _ctrl.text = n.toStringAsFixed(1);
                      widget.onChanged(n);
                    },
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: _ctrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      isDense: true,
                      suffixText: '%',
                      errorText: widget.exceedsMarket ? '!' : null,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final n = double.tryParse(v.replaceAll(',', '').trim());
                      if (n != null) widget.onChanged(n);
                    },
                  ),
                ),
              ],
            ),
            Text(
              'المطلوب ${CurrencyFormatter.formatEGP(widget.targetEgp)}'
              '  •  زيادة ${CurrencyFormatter.formatEGP(widget.upliftEgp)}'
              '  •  كمية ${CurrencyFormatter.formatNumber(widget.targetUnits.round())}'
              '${widget.belowCurrent ? '  •  أقل من الحالية' : ''}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: widget.exceedsMarket
                    ? cs.error
                    : widget.belowCurrent
                        ? M3StatusColors.of(context).warning
                        : null,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

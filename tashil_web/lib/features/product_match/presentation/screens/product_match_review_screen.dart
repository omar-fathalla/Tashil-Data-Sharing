import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../data/product_match_repository.dart';

/// "مراجعة مطابقة الأصناف": uncertain / unmatched Sell-In items vs Product Master.
/// Phase B: prioritized by business impact + bulk approve for eligible suggestions.
/// Rule: barcodes are never invented — only cleaned input or Product Master barcodes.
class ProductMatchReviewScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final ProductMatchDataSource? dataSource;

  const ProductMatchReviewScreen({super.key, this.apiClient, this.dataSource})
      : assert(apiClient != null || dataSource != null);

  @override
  State<ProductMatchReviewScreen> createState() => _ProductMatchReviewScreenState();
}

class _ProductMatchReviewScreenState extends State<ProductMatchReviewScreen> {
  late final ProductMatchDataSource _ds =
      widget.dataSource ?? HttpProductMatchDataSource(widget.apiClient!);

  String _status = 'pending';
  List<ProductMatchReviewItem> _items = const [];
  ProductMatchMetrics _metrics = const ProductMatchMetrics();
  final Set<String> _selected = {};
  bool _loading = true;
  bool _bulkBusy = false;
  String? _error;
  String? _busyId;

  static const _statusLabels = {
    'pending': 'بانتظار المراجعة',
    'approved': 'معتمد',
    'rejected': 'مرفوض',
  };

  static const _decisionLabels = {
    'exact': 'تطابق تام',
    'high': 'ثقة عالية',
    'uncertain': 'غير مؤكد',
    'none': 'بدون مرشح',
  };

  List<ProductMatchReviewItem> get _eligible =>
      _items.where((e) => e.bulkApproveEligible).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _ds.list(status: _status);
      final metrics = await _ds.metrics();
      if (!mounted) return;
      setState(() {
        _items = list;
        _metrics = metrics;
        _selected.removeWhere((id) => !_items.any((e) => e.id == id && e.bulkApproveEligible));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSelect(String id, bool? checked) {
    setState(() {
      if (checked == true) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  void _selectAllEligible() {
    setState(() {
      _selected
        ..clear()
        ..addAll(_eligible.map((e) => e.id));
    });
  }

  void _clearSelection() => setState(() => _selected.clear());

  Future<void> _decide(ProductMatchReviewItem item, String status, {String chosenItemCode = '', String chosenBarcode = '', String reasonAr = ''}) async {
    setState(() => _busyId = item.id);
    try {
      final m = await _ds.decide(
        id: item.id,
        status: status,
        reasonAr: reasonAr,
        chosenItemCode: chosenItemCode,
        chosenBarcode: chosenBarcode,
      );
      if (!mounted) return;
      setState(() {
        _metrics = m;
        _selected.remove(item.id);
      });
      M3Feedback.showSuccess(context, status == 'approved' ? 'تم اعتماد المطابقة' : 'تم رفض المطابقة');
      await _load();
    } catch (e) {
      if (mounted) M3Feedback.showError(context, '$e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _bulkApprove() async {
    final ids = _selected.where((id) => _items.any((e) => e.id == id && e.bulkApproveEligible)).toList();
    if (ids.isEmpty) return;
    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('bulk_approve_product_match_dialog'),
        icon: const Icon(AppIcons.verified),
        title: const Text('اعتماد جماعي'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('سيتم اعتماد ${ids.length} صنفاً باستخدام باركود كارتة الأصناف المقترح فقط. لن يتم اختراع باركود.'),
              const SizedBox(height: M3Spacing.sm),
              TextField(
                key: const Key('bulk_approve_match_reason'),
                controller: reasonCtl,
                decoration: const InputDecoration(
                  labelText: 'سبب الاعتماد الجماعي (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          FilledButton(
            key: const Key('bulk_approve_match_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('اعتماد المحدد'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _bulkBusy = true);
    try {
      final result = await _ds.bulkDecide(
        ids: ids,
        status: 'approved',
        reasonAr: reasonCtl.text.trim().isEmpty ? 'اعتماد جماعي من شاشة المراجعة' : reasonCtl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _metrics = result.metrics;
        _selected.clear();
      });
      M3Feedback.showSuccess(
        context,
        'اعتماد جماعي: ${result.approved} معتمد • ${result.skipped} متجاوز • ${result.failed} فشل',
      );
      await _load();
    } catch (e) {
      if (mounted) M3Feedback.showError(context, '$e');
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _approve(ProductMatchReviewItem item) async {
    String chosenCode = item.matchedItemCode;
    String chosenBarcode = item.suggestedBarcode;
    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              key: const Key('approve_product_match_dialog'),
              icon: const Icon(AppIcons.verified),
              title: const Text('اعتماد مطابقة الصنف'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('الاسم في الملف: ${item.skuName.isEmpty ? '—' : item.skuName}'),
                      const SizedBox(height: M3Spacing.xs),
                      Text('باركود الملف: ${item.barcode.isEmpty ? '—' : item.barcode}'),
                      const SizedBox(height: M3Spacing.xs),
                      Text(
                        'لن يتم اختراع باركود. يُستخدم باركود الملف أو باركود كارتة الأصناف فقط.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      const SizedBox(height: M3Spacing.sm),
                      if (item.candidates.isNotEmpty) ...[
                        Text('المرشحون', style: Theme.of(ctx).textTheme.titleSmall),
                        const SizedBox(height: M3Spacing.xs),
                        for (final c in item.candidates)
                          RadioListTile<String>(
                            key: ValueKey('cand_${c.itemCode}'),
                            dense: true,
                            title: Text(c.officialName),
                            subtitle: Text('${c.itemCode} • ${c.barcode.isEmpty ? 'بدون باركود' : c.barcode} • ${(c.confidence * 100).toStringAsFixed(0)}%'),
                            value: c.itemCode,
                            groupValue: chosenCode,
                            onChanged: (v) => setLocal(() {
                              chosenCode = v ?? '';
                              chosenBarcode = c.barcode;
                            }),
                          ),
                      ] else
                        Text('كود مقترح: ${chosenCode.isEmpty ? '—' : chosenCode}'),
                      const SizedBox(height: M3Spacing.sm),
                      TextField(
                        key: const Key('approve_match_reason'),
                        controller: reasonCtl,
                        decoration: const InputDecoration(
                          labelText: 'سبب الاعتماد (اختياري)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
                FilledButton(
                  key: const Key('approve_match_confirm'),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('اعتماد'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok == true) {
      await _decide(item, 'approved', chosenItemCode: chosenCode, chosenBarcode: chosenBarcode, reasonAr: reasonCtl.text.trim());
    }
  }

  Future<void> _reject(ProductMatchReviewItem item) async {
    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('reject_product_match_dialog'),
        title: const Text('رفض المطابقة'),
        content: TextField(
          key: const Key('reject_match_reason'),
          controller: reasonCtl,
          decoration: const InputDecoration(
            labelText: 'السبب',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          FilledButton(
            key: const Key('reject_match_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('رفض'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _decide(item, 'rejected', reasonAr: reasonCtl.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final eligibleCount = _eligible.length;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('مراجعة مطابقة الأصناف')),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(M3Spacing.md),
            children: [
              Text(
                'مرتّبة حسب الأولوية (القيمة وعدد الصفوف أولاً). الأصناف غير المؤكدة ذات اقتراح باركود من الكارتة يمكن اعتمادها جماعياً. لا يتم اختراع باركودات.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: M3Spacing.sm),
              _MetricsStrip(metrics: _metrics),
              const SizedBox(height: M3Spacing.sm),
              SegmentedButton<String>(
                key: const Key('product_match_status_filter'),
                segments: [
                  for (final e in _statusLabels.entries)
                    ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {_status},
                onSelectionChanged: (s) {
                  setState(() {
                    _status = s.first;
                    _selected.clear();
                  });
                  _load();
                },
              ),
              if (_status == 'pending' && !_loading && _error == null && _items.isNotEmpty) ...[
                const SizedBox(height: M3Spacing.sm),
                _BulkToolbar(
                  eligibleCount: eligibleCount,
                  selectedCount: _selected.length,
                  busy: _bulkBusy,
                  onSelectAll: eligibleCount == 0 ? null : _selectAllEligible,
                  onClear: _selected.isEmpty ? null : _clearSelection,
                  onBulkApprove: _selected.isEmpty || _bulkBusy ? null : _bulkApprove,
                ),
              ],
              const SizedBox(height: M3Spacing.sm),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(M3Spacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Card(
                  color: cs.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(M3Spacing.sm),
                    child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
                  ),
                )
              else if (_items.isEmpty)
                Padding(
                  key: const ValueKey('product_match_empty'),
                  padding: const EdgeInsets.all(M3Spacing.lg),
                  child: Column(
                    children: [
                      Icon(AppIcons.empty, size: 48, color: cs.outline),
                      const SizedBox(height: M3Spacing.xs),
                      Text('لا توجد عناصر في هذه الحالة', style: theme.textTheme.titleMedium),
                    ],
                  ),
                )
              else
                for (var i = 0; i < _items.length; i++)
                  _ReviewCard(
                    index: i,
                    item: _items[i],
                    status: _status,
                    decisionLabel: _decisionLabels[_items[i].decision] ?? _items[i].decision,
                    selected: _selected.contains(_items[i].id),
                    busy: _busyId == _items[i].id || _bulkBusy,
                    onToggle: _items[i].bulkApproveEligible ? (v) => _toggleSelect(_items[i].id, v) : null,
                    onApprove: () => _approve(_items[i]),
                    onReject: () => _reject(_items[i]),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulkToolbar extends StatelessWidget {
  final int eligibleCount;
  final int selectedCount;
  final bool busy;
  final VoidCallback? onSelectAll;
  final VoidCallback? onClear;
  final VoidCallback? onBulkApprove;

  const _BulkToolbar({
    required this.eligibleCount,
    required this.selectedCount,
    required this.busy,
    required this.onSelectAll,
    required this.onClear,
    required this.onBulkApprove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('product_match_bulk_toolbar'),
      padding: const EdgeInsets.all(M3Spacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: M3Shape.radiusMd,
      ),
      child: Wrap(
        spacing: M3Spacing.xs,
        runSpacing: M3Spacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'قابل للاعتماد الجماعي: $eligibleCount • محدد: $selectedCount',
            style: theme.textTheme.labelLarge,
          ),
          OutlinedButton(
            key: const Key('pm_select_all_eligible'),
            onPressed: busy ? null : onSelectAll,
            child: const Text('تحديد الكل المؤهل'),
          ),
          OutlinedButton(
            key: const Key('pm_clear_selection'),
            onPressed: busy ? null : onClear,
            child: const Text('مسح التحديد'),
          ),
          FilledButton.icon(
            key: const Key('pm_bulk_approve'),
            onPressed: onBulkApprove,
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(AppIcons.verified),
            label: const Text('اعتماد جماعي'),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final int index;
  final ProductMatchReviewItem item;
  final String status;
  final String decisionLabel;
  final bool selected;
  final bool busy;
  final ValueChanged<bool?>? onToggle;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ReviewCard({
    required this.index,
    required this.item,
    required this.status,
    required this.decisionLabel,
    required this.selected,
    required this.busy,
    required this.onToggle,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final priorityColor = switch (item.priority) {
      ProductMatchPriority.high => cs.error,
      ProductMatchPriority.medium => cs.tertiary,
      ProductMatchPriority.low => cs.outline,
    };
    return Card(
      key: ValueKey('pm_review_${item.id}'),
      margin: const EdgeInsets.only(bottom: M3Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(M3Spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (status == 'pending' && onToggle != null)
                  Checkbox(
                    key: ValueKey('pm_select_${item.id}'),
                    value: selected,
                    onChanged: busy ? null : onToggle,
                  ),
                Expanded(
                  child: Text(
                    item.skuName.isEmpty ? (item.itemCode.isEmpty ? 'صنف بدون اسم' : item.itemCode) : item.skuName,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  key: ValueKey('pm_priority_${item.id}'),
                  avatar: Icon(AppIcons.trendingUp, size: 16, color: priorityColor),
                  label: Text(item.priorityLabelAr),
                  side: BorderSide(color: priorityColor.withOpacity(0.4)),
                ),
                const SizedBox(width: M3Spacing.xs),
                Chip(
                  key: ValueKey('pm_decision_${item.id}'),
                  label: Text(decisionLabel),
                ),
              ],
            ),
            if (index == 0)
              Padding(
                padding: const EdgeInsets.only(bottom: M3Spacing.xs),
                child: Text(
                  'الأعلى أولوية في القائمة',
                  key: const Key('pm_top_priority_hint'),
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.primary),
                ),
              ),
            Text('السبب: ${item.reasonAr.isEmpty ? '—' : item.reasonAr}'),
            Text('الثقة: ${(item.confidence * 100).toStringAsFixed(0)}%'),
            Text('باركود الملف: ${item.barcode.isEmpty ? '—' : item.barcode}'),
            Text('باركود مقترح: ${item.suggestedBarcode.isEmpty ? '—' : item.suggestedBarcode}'),
            if (item.matchedName.isNotEmpty) Text('مرشح: ${item.matchedName} (${item.matchedItemCode})'),
            if (item.sourceFile.isNotEmpty) Text('الملف: ${item.sourceFile}'),
            if (item.rows > 0 || item.value > 0)
              Text('الصفوف: ${item.rows} • القيمة: ${CurrencyFormatter.formatCompactEGP(item.value)}'),
            if (item.bulkApproveEligible)
              Padding(
                padding: const EdgeInsets.only(top: M3Spacing.xs),
                child: Text(
                  'مؤهل للاعتماد الجماعي',
                  key: ValueKey('pm_bulk_eligible_${item.id}'),
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.primary),
                ),
              ),
            if (status == 'pending') ...[
              const SizedBox(height: M3Spacing.xs),
              Row(
                children: [
                  FilledButton(
                    key: ValueKey('pm_approve_${item.id}'),
                    onPressed: busy ? null : onApprove,
                    child: const Text('اعتماد'),
                  ),
                  const SizedBox(width: M3Spacing.xs),
                  OutlinedButton(
                    key: ValueKey('pm_reject_${item.id}'),
                    onPressed: busy ? null : onReject,
                    child: const Text('رفض'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricsStrip extends StatelessWidget {
  final ProductMatchMetrics metrics;
  const _MetricsStrip({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String pct(double r) => '${(r * 100).toStringAsFixed(0)}%';
    final tiles = <(String, String)>[
      ('حسم تلقائي', pct(metrics.autoResolveRate)),
      ('إحالة للمراجعة', pct(metrics.reviewRate)),
      ('اعتماد بعد المراجعة', pct(metrics.approvalRate)),
      ('بانتظار المراجعة', '${metrics.pending}'),
      ('باركودات مخترعة', '${metrics.inventedBarcodes}'),
    ];
    return Wrap(
      key: const Key('product_match_metrics'),
      spacing: M3Spacing.xs,
      runSpacing: M3Spacing.xs,
      children: [
        for (final t in tiles)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: M3Shape.radiusMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.$1, style: theme.textTheme.labelSmall),
                Text(t.$2, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
      ],
    );
  }
}

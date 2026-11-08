import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../data/product_match_repository.dart';

/// "مراجعة مطابقة الأصناف": uncertain / unmatched Sell-In items vs Product Master.
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
  bool _loading = true;
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
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
      setState(() => _metrics = m);
      M3Feedback.showSuccess(context, status == 'approved' ? 'تم اعتماد المطابقة' : 'تم رفض المطابقة');
      await _load();
    } catch (e) {
      if (mounted) M3Feedback.showError(context, '$e');
    } finally {
      if (mounted) setState(() => _busyId = null);
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
                'الأصناف غير المؤكدة أو غير الموجودة في كارتة الأصناف والأسعار تظهر هنا. لا يتم اختراع باركودات — فقط باركود الملف أو باركود الكارتة.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: M3Spacing.xs),
              Material(
                key: const Key('product_match_ram_note'),
                color: cs.secondaryContainer.withOpacity(0.45),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(M3Spacing.sm),
                  child: Text(
                    'ملاحظة: قرارات المراجعة في ذاكرة السيرفر فقط (RAM) — بتضيع لو السيرفر اتعمل له restart ومش متشاركة بين النسخ. مفيش حفظ durable لسه.',
                  ),
                ),
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
                  setState(() => _status = s.first);
                  _load();
                },
              ),
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
                for (final item in _items)
                  Card(
                    key: ValueKey('pm_review_${item.id}'),
                    margin: const EdgeInsets.only(bottom: M3Spacing.sm),
                    child: Padding(
                      padding: const EdgeInsets.all(M3Spacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.skuName.isEmpty ? (item.itemCode.isEmpty ? 'صنف بدون اسم' : item.itemCode) : item.skuName,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Chip(
                                key: ValueKey('pm_decision_${item.id}'),
                                label: Text(_decisionLabels[item.decision] ?? item.decision),
                              ),
                            ],
                          ),
                          const SizedBox(height: M3Spacing.xs),
                          Text('السبب: ${item.reasonAr.isEmpty ? '—' : item.reasonAr}'),
                          Text('الثقة: ${(item.confidence * 100).toStringAsFixed(0)}%'),
                          Text('باركود الملف: ${item.barcode.isEmpty ? '—' : item.barcode}'),
                          Text('باركود مقترح: ${item.suggestedBarcode.isEmpty ? '—' : item.suggestedBarcode}'),
                          if (item.matchedName.isNotEmpty) Text('مرشح: ${item.matchedName} (${item.matchedItemCode})'),
                          if (item.sourceFile.isNotEmpty) Text('الملف: ${item.sourceFile}'),
                          if (item.rows > 0 || item.value > 0)
                            Text('الصفوف: ${item.rows} • القيمة: ${CurrencyFormatter.formatCompactEGP(item.value)}'),
                          if (_status == 'pending') ...[
                            const SizedBox(height: M3Spacing.xs),
                            Row(
                              children: [
                                FilledButton(
                                  key: ValueKey('pm_approve_${item.id}'),
                                  onPressed: _busyId == item.id ? null : () => _approve(item),
                                  child: const Text('اعتماد'),
                                ),
                                const SizedBox(width: M3Spacing.xs),
                                OutlinedButton(
                                  key: ValueKey('pm_reject_${item.id}'),
                                  onPressed: _busyId == item.id ? null : () => _reject(item),
                                  child: const Text('رفض'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
            ],
          ),
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
              borderRadius: BorderRadius.circular(12),
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

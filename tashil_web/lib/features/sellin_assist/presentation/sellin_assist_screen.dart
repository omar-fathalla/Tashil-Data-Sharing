import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/m3_shape.dart';
import '../../../core/theme/m3_spacing.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/m3_feedback.dart';
import '../data/sellin_assist_repository.dart';

/// Arabic approval UI for Sell-In Gemini assist:
/// layout suggestions + SELLIN_CUSTOMER_CHAIN_MAP customer→chain proposals.
/// Nothing is applied to production without an explicit approve here.
class SellInAssistScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final SellInAssistDataSource? dataSource;

  const SellInAssistScreen({super.key, this.apiClient, this.dataSource});

  @override
  State<SellInAssistScreen> createState() => _SellInAssistScreenState();
}

class _SellInAssistScreenState extends State<SellInAssistScreen> {
  late final SellInAssistDataSource _ds =
      widget.dataSource ?? HttpSellInAssistDataSource(widget.apiClient!);

  String _status = 'pending';
  List<AssistSuggestion> _items = const [];
  AssistMetrics _metrics = const AssistMetrics();
  bool _loading = true;
  String? _error;
  String? _busyId;

  static const _statusLabels = {
    'pending': 'محتاج موافقة',
    'approved': 'معتمد',
    'rejected': 'مرفوض',
  };

  static const _kindLabels = {
    'layout': 'تخطيط الملف',
    'customer_chain': 'ربط عميل ← سلسلة',
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
      if (mounted) {
        setState(() {
          _items = list;
          _metrics = metrics;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _promptSuggestChains() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('sellin_assist_suggest_chains_dialog'),
        title: const Text('اقتراح ربط عميل ← سلسلة'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'الصق أسماء العملاء (سطر لكل اسم). الاقتراحات للتأكيد فقط ومش هتتضاف لـ SELLIN_CUSTOMER_CHAIN_MAP غير بعد موافقتك.',
              ),
              const SizedBox(height: M3Spacing.sm),
              TextField(
                key: const Key('sellin_assist_customers_field'),
                controller: ctl,
                maxLines: 6,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'فرع فتح الله - كيه اتش جمله ماركت',
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          FilledButton(
            key: const Key('sellin_assist_suggest_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('اقترح'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final names = ctl.text
        .split(RegExp(r'[\n,;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (names.isEmpty) {
      if (mounted) M3Feedback.showWarning(context, 'مفيش أسماء');
      return;
    }
    try {
      final sugs = await _ds.suggestChains(customers: names);
      if (!mounted) return;
      M3Feedback.showSuccess(context, 'اتعمل ${sugs.length} اقتراح — راجعهم واعتمد أو ارفض');
      setState(() => _status = 'pending');
      await _load();
    } catch (e) {
      if (mounted) M3Feedback.showError(context, '$e');
    }
  }

  Future<void> _decide(String action, AssistSuggestion s) async {
    setState(() => _busyId = s.id);
    try {
      await _ds.decide(action, s.id);
      if (!mounted) return;
      if (action == 'approve') {
        final hint = s.isChain && s.envFragment.isNotEmpty
            ? 'اتسجل الاعتماد في الذاكرة فقط. لتفعيل الربط يدوياً بعد المراجعة: ${s.envFragment} — مفيش تغيير على الإنتاج.'
            : 'اتسجل الاعتماد في الذاكرة فقط. مفيش تغيير على بيانات الإنتاج.';
        M3Feedback.showSuccess(context, hint);
      } else {
        M3Feedback.showSuccess(context, 'اترفض الاقتراح');
      }
      await _load();
    } catch (e) {
      if (mounted) M3Feedback.showError(context, '$e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ratePct = (_metrics.approvalRate * 100).toStringAsFixed(0);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مساعدة Gemini لملفات التوريد'),
          actions: [
            IconButton(
              key: const Key('sellin_assist_suggest_chains'),
              tooltip: 'اقتراح ربط من أسماء عملاء',
              onPressed: _promptSuggestChains,
              icon: const Icon(AppIcons.link),
            ),
            IconButton(
              key: const Key('sellin_assist_refresh'),
              tooltip: 'تحديث',
              onPressed: _load,
              icon: const Icon(AppIcons.refresh),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(M3Spacing.md),
            children: [
              Text(
                'اقتراحات تخطيط الملف وربط اسم العميل بالسلسلة (SELLIN_CUSTOMER_CHAIN_MAP). '
                'الاقتراحات للتأكيد فقط ومش بتتطبق على الإنتاج غير بعد موافقتك.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: M3Spacing.xs),
              Material(
                key: const Key('sellin_assist_ram_note'),
                color: cs.secondaryContainer.withOpacity(0.45),
                borderRadius: M3Shape.radiusSm,
                child: const Padding(
                  padding: EdgeInsets.all(M3Spacing.sm),
                  child: Text(
                    'ملاحظة: القرارات والمؤشرات في ذاكرة السيرفر فقط (RAM) — بتضيع لو السيرفر اتعمل له restart ومش متشاركة بين النسخ. مفيش حفظ durable لسه.',
                  ),
                ),
              ),
              const SizedBox(height: M3Spacing.sm),
              Wrap(
                key: const Key('sellin_assist_metrics'),
                spacing: M3Spacing.xs,
                runSpacing: M3Spacing.xs,
                children: [
                  Chip(label: Text('معلق: ${_metrics.pending}')),
                  Chip(label: Text('معتمد: ${_metrics.approved}')),
                  Chip(label: Text('مرفوض: ${_metrics.rejected}')),
                  Chip(
                    key: const Key('sellin_assist_approval_rate'),
                    avatar: const Icon(AppIcons.insights, size: 16),
                    label: Text('نسبة الاعتماد: $ratePct%'),
                  ),
                ],
              ),
              if (_metrics.approvedFragments.isNotEmpty) ...[
                const SizedBox(height: M3Spacing.xs),
                Text(
                  'مقاطع معتمدة لنسخها لـ SELLIN_CUSTOMER_CHAIN_MAP (يدوياً):',
                  style: theme.textTheme.bodySmall,
                ),
                for (final f in _metrics.approvedFragments)
                  ListTile(
                    dense: true,
                    leading: const Icon(AppIcons.copy, size: 18),
                    title: Text(f, style: theme.textTheme.bodySmall),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: f));
                      if (!context.mounted) return;
                      M3Feedback.showSuccess(context, 'اتنسخ المقطع');
                    },
                  ),
              ],
              const SizedBox(height: M3Spacing.sm),
              SegmentedButton<String>(
                key: const Key('sellin_assist_status_filter'),
                segments: [
                  for (final s in _statusLabels.entries)
                    ButtonSegment(value: s.key, label: Text(s.value)),
                ],
                selected: {_status},
                onSelectionChanged: (v) {
                  setState(() => _status = v.first);
                  _load();
                },
              ),
              const SizedBox(height: M3Spacing.sm),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(M3Spacing.md),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_error != null)
                ListTile(
                  leading: Icon(AppIcons.error, color: cs.error),
                  title: Text(_error!),
                )
              else if (_items.isEmpty)
                const ListTile(
                  leading: Icon(AppIcons.empty),
                  title: Text('مفيش اقتراحات هنا'),
                )
              else
                for (final s in _items) _card(s, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(AssistSuggestion s, ThemeData theme) {
    final busy = _busyId == s.id;
    final title = s.isLayout
        ? '${_kindLabels[s.kind]} • ${s.filename.isEmpty ? 'ملف' : s.filename}'
        : '${_kindLabels[s.kind]} • ${s.customerNeedle} → ${s.suggestedChain}';

    return Card.outlined(
      key: Key('sellin_assist_${s.id}'),
      child: Padding(
        padding: const EdgeInsets.all(M3Spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(s.isLayout ? AppIcons.tableChart : AppIcons.link),
                const SizedBox(width: M3Spacing.xs),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                Chip(label: Text(_statusLabels[s.status] ?? s.status)),
              ],
            ),
            if (s.reasonAr.isNotEmpty)
              Text(s.reasonAr, style: theme.textTheme.bodyMedium),
            Text(
              'المصدر: ${s.mappingSource}'
              '${s.modelUsed.isEmpty ? '' : ' • ${s.modelUsed}'}'
              '${s.confidence > 0 ? ' • ثقة ${(s.confidence * 100).toStringAsFixed(0)}%' : ''}'
              '${s.layout.isEmpty ? '' : ' • شكل ${s.layout}'}',
              style: theme.textTheme.bodySmall,
            ),
            if (s.envFragment.isNotEmpty)
              Text('مقطع البيئة: ${s.envFragment}', style: theme.textTheme.bodySmall),
            if (s.sampleCustomers.isNotEmpty)
              Text(
                'أمثلة: ${s.sampleCustomers.take(3).join('، ')}',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: M3Spacing.xs),
            if (s.status == 'pending')
              Wrap(
                spacing: M3Spacing.xs,
                children: [
                  FilledButton(
                    key: Key('sellin_assist_approve_${s.id}'),
                    onPressed: busy ? null : () => _decide('approve', s),
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('اعتماد'),
                  ),
                  OutlinedButton(
                    key: Key('sellin_assist_reject_${s.id}'),
                    onPressed: busy ? null : () => _decide('reject', s),
                    child: const Text('رفض'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

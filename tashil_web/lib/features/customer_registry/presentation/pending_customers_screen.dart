import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/data/available_years.dart';
import '../../../core/network/backend_http.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/m3_spacing.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/m3_feedback.dart';
import '../data/customer_registry_repository.dart';

/// "عملاء محتاجين تأكيد": Sell-In customer names held out of all totals until an admin decides.
/// Rule: a customer's rows are never attributed to another customer by guessing. Suggestions are shown
/// only as hints; nothing is merged unless the admin picks it here (and it can be undone).
class PendingCustomersScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final CustomerRegistryDataSource? dataSource;

  const PendingCustomersScreen({super.key, this.apiClient, this.dataSource});

  @override
  State<PendingCustomersScreen> createState() => _PendingCustomersScreenState();
}

class _PendingCustomersScreenState extends State<PendingCustomersScreen> {
  late final CustomerRegistryDataSource _ds =
      widget.dataSource ?? HttpCustomerRegistryDataSource(widget.apiClient!);
  String _status = 'pending';
  List<RegistryEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  String? _busyName;

  static const _statusLabels = {
    'pending': 'محتاج تأكيد',
    'approved': 'متأكد',
    'rejected': 'مرفوض',
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
      if (mounted) setState(() => _entries = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(String action, RegistryEntry e, {String chain = '', String aliasOf = ''}) async {
    setState(() => _busyName = e.name);
    try {
      final r = await _ds.decide(action, e.name, chain: chain, aliasOf: aliasOf);
      if (!mounted) return;
      if (r.errors.isNotEmpty) {
        M3Feedback.showWarning(context, 'اتسجل القرار، بس فيه ملفات معرفناش نعيد حسابها: ${r.errors.join('، ')}');
      } else {
        M3Feedback.showSuccess(context, 'اتسجل القرار واتعاد حساب ${r.reappliedFiles.length} ملف');
      }
      // Reapplied rows may add a year (e.g. 2027) or change totals: refresh shared caches.
      final api = widget.apiClient;
      if (api != null) {
        BackendHttp.cache.invalidateAll();
        unawaited(AvailableYears.load(api, force: true));
      }
      await _load();
    } catch (err) {
      if (mounted) M3Feedback.showError(context, '$err');
    } finally {
      if (mounted) setState(() => _busyName = null);
    }
  }

  Future<void> _approve(RegistryEntry e) async {
    final chainCtl = TextEditingController(text: e.chain);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('approve_customer_dialog'),
        icon: const Icon(AppIcons.verified),
        title: Text('تأكيد العميل "${e.name}"'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('الصفوف هتدخل الإجماليات فوراً باسمه هو بس، ومش هتتدمج مع أي عميل تاني.'),
              const SizedBox(height: M3Spacing.sm),
              TextField(
                key: const Key('approve_chain_field'),
                controller: chainCtl,
                decoration: InputDecoration(
                  labelText: 'السلسلة (اختياري)',
                  helperText: e.uploadChain.isEmpty
                      ? 'سيبها فاضية عشان تفضل على سلسلة الرفع'
                      : 'سيبها فاضية عشان تفضل على "${e.uploadChain}"',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          FilledButton(
            key: const Key('approve_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (ok == true) await _decide('approve', e, chain: chainCtl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('عملاء محتاجين تأكيد')),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(M3Spacing.md),
            children: [
              Text(
                'العملاء الجداد في ملفات التوريد مش بيتحسبوا في أي إجمالي لحد ما تأكدهم. الاقتراحات مجرد تلميح ومش بتتطبق لوحدها.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: M3Spacing.sm),
              SegmentedButton<String>(
                key: const Key('registry_status_filter'),
                segments: [
                  for (final s in _statusLabels.entries) ButtonSegment(value: s.key, label: Text(s.value)),
                ],
                selected: {_status},
                onSelectionChanged: (v) {
                  setState(() => _status = v.first);
                  _load();
                },
              ),
              const SizedBox(height: M3Spacing.sm),
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(M3Spacing.md), child: CircularProgressIndicator()))
              else if (_error != null)
                ListTile(leading: Icon(AppIcons.error, color: cs.error), title: Text(_error!))
              else if (_entries.isEmpty)
                const ListTile(leading: Icon(AppIcons.empty), title: Text('مفيش عملاء هنا'))
              else
                for (final e in _entries) _entryCard(e, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entryCard(RegistryEntry e, ThemeData theme) {
    final busy = _busyName == e.name;
    return Card.outlined(
      key: Key('registry_entry_${e.name}'),
      child: Padding(
        padding: const EdgeInsets.all(M3Spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(AppIcons.person),
              const SizedBox(width: M3Spacing.xs),
              Expanded(child: Text(e.name, style: theme.textTheme.titleMedium)),
              Chip(label: Text(_statusLabels[e.status] ?? e.status)),
            ]),
            if (e.rows > 0)
              Text('${e.rows} صف • ${CurrencyFormatter.formatCompactEGP(e.value)} برّه الإجماليات'
                  '${e.months.isEmpty ? '' : ' • ${e.months.join('، ')}'}'),
            if (e.chain.isNotEmpty) Text('السلسلة: ${e.chain}'),
            if (e.aliasOf.isNotEmpty) Text('متسجل كاسم تاني لـ: ${e.aliasOf}'),
            if (e.suggestedName.isNotEmpty)
              Text('اسم قريب (اقتراح بس): ${e.suggestedName}', style: theme.textTheme.bodySmall),
            const SizedBox(height: M3Spacing.xs),
            Wrap(spacing: M3Spacing.xs, runSpacing: M3Spacing.xs, children: [
              if (e.status != 'approved')
                FilledButton.icon(
                  key: Key('approve_${e.name}'),
                  onPressed: busy ? null : () => _approve(e),
                  icon: const Icon(AppIcons.check),
                  label: const Text('تأكيد'),
                ),
              if (e.status != 'rejected')
                OutlinedButton.icon(
                  key: Key('reject_${e.name}'),
                  onPressed: busy ? null : () => _decide('reject', e),
                  icon: const Icon(AppIcons.block),
                  label: const Text('رفض'),
                ),
              if (e.status != 'pending')
                OutlinedButton.icon(
                  key: Key('unmerge_${e.name}'),
                  onPressed: busy ? null : () => _decide('unmerge', e),
                  icon: const Icon(AppIcons.undo),
                  label: const Text('رجوع عن القرار'),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

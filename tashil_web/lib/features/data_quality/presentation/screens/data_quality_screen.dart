import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/excel_export_service.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../data/data_quality_repository.dart';
import '../../../customer_registry/presentation/pending_customers_screen.dart';
import '../../../sellin_assist/presentation/sellin_assist_screen.dart';
import '../../../product_match/presentation/screens/product_match_review_screen.dart';
import '../../../../core/data/data_refresh_mixin.dart';

String _egp(double v) {
  final s = v.abs().round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${v < 0 ? '-' : ''}$s ج.م';
}

String _d(DateTime? t) => t == null
    ? ''
    : '${t.toLocal().year}-${t.toLocal().month.toString().padLeft(2, '0')}-${t.toLocal().day.toString().padLeft(2, '0')}';

/// "الأخطاء": per-tenant data-quality issues. Auto-refreshes when the backend re-runs checks.
class DataQualityScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final DataQualityDataSource? dataSource;
  final Duration pollInterval;

  const DataQualityScreen({
    super.key,
    this.apiClient,
    this.dataSource,
    this.pollInterval = const Duration(seconds: 30),
  }) : assert(apiClient != null || dataSource != null);

  @override
  State<DataQualityScreen> createState() => _DataQualityScreenState();
}

class _DataQualityScreenState extends State<DataQualityScreen> with DataRefreshMixin<DataQualityScreen> {
  @override
  void onBackendDataChanged() {
    _load();
  }

  late final DataQualityDataSource _repo = widget.dataSource ?? DataQualityRepository(widget.apiClient!);
  DataQualitySummary _summary = const DataQualitySummary();
  List<DataQualityIssue> _issues = const [];
  DataQualityFilter _filter = const DataQualityFilter();
  bool _loading = true;
  String? _error;
  DateTime? _version;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(widget.pollInterval, (_) => _checkForUpdates());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _repo.summary();
      final i = await _repo.issues(_filter);
      if (!mounted) return;
      setState(() {
        _summary = s;
        _issues = i;
        _version = s.updatedAt;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final s = await _repo.summary();
      if (!mounted || s.updatedAt == _version) return;
      final i = await _repo.issues(_filter);
      if (!mounted) return;
      setState(() {
        _summary = s;
        _issues = i;
        _version = s.updatedAt;
      });
    } catch (_) {}
  }

  void _setFilter(DataQualityFilter f) {
    _filter = f;
    _load();
  }

  Future<void> _changeStatus(DataQualityIssue issue) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _StatusDialog(issue: issue),
    );
    if (result == null) return;
    try {
      await _repo.updateStatus(issue.id, result.$1, result.$2);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _export() {
    final csv = ExcelExportService.generateCsv(
      headers: const [
        'المصدر', 'النوع', 'الخطورة', 'الشيت', 'الصف', 'العمود', 'كود الصنف', 'الباركود', 'اسم الصنف',
        'القيمة الموجودة', 'القيمة المتوقعة', 'التأثير (ج.م)', 'الحالة', 'السبب', 'أول ظهور', 'تاريخ الحل',
      ],
      rows: _issues
          .map((i) => [
                dqSourceLabel(i.source), i.typeLabel, i.severity, i.sheet, i.row, i.column,
                i.itemCode, i.barcode, i.itemName, i.foundValue, i.expectedValue,
                i.impactEgp?.toStringAsFixed(2) ?? '', i.status, i.statusReason, _d(i.firstSeen), _d(i.resolvedAt),
              ])
          .toList(),
    );
    ExcelExportService.downloadCsv('data_quality_issues.csv', csv);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            Row(
              children: [
                Icon(AppIcons.dataQuality, color: cs.primary),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text('الأخطاء وجودة البيانات',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  key: const ValueKey('dq_refresh'),
                  tooltip: 'تحديث',
                  onPressed: _load,
                  icon: const Icon(AppIcons.refresh),
                ),
                if (widget.apiClient != null)
                  IconButton(
                    key: const ValueKey('dq_pending_customers'),
                    tooltip: 'عملاء محتاجين تأكيد',
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => PendingCustomersScreen(apiClient: widget.apiClient),
                    )),
                    icon: const Icon(AppIcons.pendingCustomers),
                  ),
                if (widget.apiClient != null)
                  IconButton(
                    key: const ValueKey('dq_sellin_assist'),
                    tooltip: 'مساعدة Gemini للتوريد',
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => SellInAssistScreen(apiClient: widget.apiClient),
                    )),
                    icon: const Icon(AppIcons.sellInAssist),
                  ),
                if (widget.apiClient != null)
                  IconButton(
                    key: const ValueKey('dq_product_match_review'),
                    tooltip: 'مراجعة مطابقة الأصناف',
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ProductMatchReviewScreen(apiClient: widget.apiClient),
                    )),
                    icon: const Icon(AppIcons.productMatchReview),
                  ),
                const SizedBox(width: 4.0),
                FilledButton.tonalIcon(
                  key: const ValueKey('dq_export'),
                  onPressed: _issues.isEmpty ? null : _export,
                  icon: const Icon(AppIcons.download),
                  label: const Text('تصدير Excel/CSV'),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            if (_error != null)
              Card(
                color: cs.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer)),
                ),
              ),
            _SummaryRow(summary: _summary),
            const SizedBox(height: 16.0),
            _Filters(summary: _summary, filter: _filter, onChanged: _setFilter),
            const SizedBox(height: 12.0),
            if (_loading)
              const Padding(padding: EdgeInsets.all(32.0), child: Center(child: CircularProgressIndicator()))
            else if (_issues.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: Text('لا توجد أخطاء مطابقة للفلاتر',
                      key: const ValueKey('dq_empty'), style: theme.textTheme.titleMedium),
                ),
              )
            else
              _IssuesTable(issues: _issues, onChangeStatus: _changeStatus),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final DataQualitySummary summary;
  const _SummaryRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Defensive empty-state UI. Backend row totals when Runs are missing are
    // fixed in PR #86 / TDS-76 — keep this guard so 0 rows never show 100%.
    final hasRows = summary.totalRows > 0;
    final pct = hasRows ? summary.cleanlinessPct.clamp(0, 100) / 100 : 0.0;
    final gauge = Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(
              width: 96.0,
              height: 96.0,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: hasRows ? pct.toDouble() : null,
                      strokeWidth: 10.0,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: !hasRows
                          ? cs.outlineVariant
                          : (pct >= 0.95
                              ? cs.primary
                              : (pct >= 0.85 ? cs.tertiary : cs.error)),
                    ),
                  ),
                  Text(
                    hasRows
                        ? '${summary.cleanlinessPct.toStringAsFixed(1)}%'
                        : '—',
                    key: const ValueKey('dq_cleanliness'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: hasRows ? null : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8.0),
            Text('نظافة البيانات', style: theme.textTheme.labelLarge),
            Text(
              hasRows
                  ? '${summary.totalRows - summary.criticalRows} من ${summary.totalRows} صف بدون أخطاء حرجة'
                  : 'مفيش صفوف اتفحصت',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4.0),
            Text('مفتوحة ${summary.open} · اتصلّحت ${summary.resolved} · متجاهلة ${summary.ignored}',
                key: const ValueKey('dq_counts'), style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
    final cards = summary.types.where((t) => t.total > 0).map((t) {
      final critical = t.severity == kDqCritical;
      return SizedBox(
        width: 220.0,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(critical ? AppIcons.error : AppIcons.warning,
                      size: 18.0, color: critical ? cs.error : cs.tertiary),
                  const SizedBox(width: 6.0),
                  Expanded(child: Text(t.typeLabel, style: theme.textTheme.labelLarge, maxLines: 2)),
                ]),
                const SizedBox(height: 8.0),
                Text('${t.open}', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(t.impactEgp > 0 ? 'التأثير ${_egp(t.impactEgp)}' : 'التأثير غير محسوب',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }).toList();
    return Wrap(spacing: 12.0, runSpacing: 12.0, children: [gauge, ...cards]);
  }
}

class _Filters extends StatelessWidget {
  final DataQualitySummary summary;
  final DataQualityFilter filter;
  final ValueChanged<DataQualityFilter> onChanged;
  const _Filters({required this.summary, required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final types = <String, String>{for (final t in summary.types) t.type: t.typeLabel};
    final sources = <String>{for (final t in summary.types) t.source};
    return Wrap(spacing: 12.0, runSpacing: 12.0, children: [
      M3Dropdown<String>(
        key: const ValueKey('dq_filter_status'),
        label: 'الحالة',
        width: 170.0,
        value: filter.status,
        options: const [
          M3DropdownOption('', kDqOpen),
          M3DropdownOption(kDqResolved, kDqResolved),
          M3DropdownOption(kDqIgnored, kDqIgnored),
          M3DropdownOption('all', 'الكل'),
        ],
        onChanged: (v) => onChanged(filter.copyWith(status: v)),
      ),
      M3Dropdown<String>(
        key: const ValueKey('dq_filter_severity'),
        label: 'الخطورة',
        width: 150.0,
        value: filter.severity,
        options: const [
          M3DropdownOption('', 'الكل'),
          M3DropdownOption(kDqCritical, kDqCritical),
          M3DropdownOption(kDqWarning, kDqWarning),
        ],
        onChanged: (v) => onChanged(filter.copyWith(severity: v)),
      ),
      M3Dropdown<String>(
        key: const ValueKey('dq_filter_source'),
        label: 'المصدر',
        width: 170.0,
        value: filter.source,
        options: [
          const M3DropdownOption('', 'الكل'),
          for (final s in sources) M3DropdownOption(s, dqSourceLabel(s)),
        ],
        onChanged: (v) => onChanged(filter.copyWith(source: v)),
      ),
      M3Dropdown<String>(
        key: const ValueKey('dq_filter_type'),
        label: 'النوع',
        width: 240.0,
        value: filter.type,
        options: [
          const M3DropdownOption('', 'الكل'),
          for (final e in types.entries) M3DropdownOption(e.key, e.value),
        ],
        onChanged: (v) => onChanged(filter.copyWith(type: v)),
      ),
    ]);
  }
}

class _IssuesTable extends StatelessWidget {
  final List<DataQualityIssue> issues;
  final ValueChanged<DataQualityIssue> onChangeStatus;
  const _IssuesTable({required this.issues, required this.onChangeStatus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const ValueKey('dq_table'),
          headingTextStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          columns: const [
            DataColumn(label: Text('الخطورة')),
            DataColumn(label: Text('النوع')),
            DataColumn(label: Text('الصف')),
            DataColumn(label: Text('كود الصنف')),
            DataColumn(label: Text('الباركود')),
            DataColumn(label: Text('اسم الصنف')),
            DataColumn(label: Text('الموجود')),
            DataColumn(label: Text('المتوقع')),
            DataColumn(label: Text('التأثير'), numeric: true),
            DataColumn(label: Text('الحالة')),
            DataColumn(label: Text('')),
          ],
          rows: issues.map((i) {
            final critical = i.severity == kDqCritical;
            return DataRow(cells: [
              DataCell(Chip(
                avatar: Icon(critical ? AppIcons.error : AppIcons.warning,
                    size: 16.0, color: critical ? cs.error : cs.tertiary),
                label: Text(i.severity),
                visualDensity: VisualDensity.compact,
              )),
              DataCell(Text(i.typeLabel)),
              DataCell(Text(i.row > 0 ? '${i.row}${i.column.isNotEmpty ? ' · ${i.column}' : ''}' : '')),
              DataCell(Text(i.itemCode)),
              DataCell(Text(i.barcode)),
              DataCell(ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260.0),
                child: Text(i.itemName, overflow: TextOverflow.ellipsis),
              )),
              DataCell(Text(i.foundValue)),
              DataCell(Text(i.expectedValue)),
              DataCell(Text(i.impactEgp == null ? '—' : _egp(i.impactEgp!))),
              DataCell(Tooltip(
                message: i.statusReason,
                child: Text(i.status + (i.autoClosed ? ' (تلقائي)' : '')),
              )),
              DataCell(IconButton(
                key: ValueKey('dq_status_${i.id}'),
                tooltip: 'تغيير الحالة',
                icon: const Icon(AppIcons.edit),
                onPressed: () => onChangeStatus(i),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

class _StatusDialog extends StatefulWidget {
  final DataQualityIssue issue;
  const _StatusDialog({required this.issue});
  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  late String _status = widget.issue.status == kDqOpen ? kDqIgnored : kDqOpen;
  final _reason = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تغيير حالة الخطأ'),
        content: SizedBox(
          width: 380.0,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${widget.issue.typeLabel} — ${widget.issue.itemCode}'),
            const SizedBox(height: 16.0),
            M3Dropdown<String>(
              key: const ValueKey('dq_status_select'),
              label: 'الحالة الجديدة',
              expand: true,
              value: _status,
              options: const [
                M3DropdownOption(kDqOpen, kDqOpen),
                M3DropdownOption(kDqResolved, kDqResolved),
                M3DropdownOption(kDqIgnored, kDqIgnored),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
            const SizedBox(height: 12.0),
            TextField(
              key: const ValueKey('dq_status_reason'),
              controller: _reason,
              decoration: InputDecoration(labelText: 'السبب', errorText: _err),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            key: const ValueKey('dq_status_save'),
            onPressed: () {
              final r = _reason.text.trim();
              if (_status == kDqIgnored && r.isEmpty) {
                setState(() => _err = 'السبب مطلوب عند التجاهل');
                return;
              }
              Navigator.pop(context, (_status, r));
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/theme/m3_shape.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../data/chain_discount_repository.dart';
import '../../../../core/widgets/m3_table_surface.dart';
import '../../../../core/widgets/m3_wrap_text.dart';
import '../../../../core/widgets/table_scroll_container.dart';

/// Product Master → «حاسبة الطلبيات والخصومات والهامش»: one row per chain with its VAT, invoice
/// discount and extra discount. Saved terms are the single source of truth for that chain's Sell-In
/// everywhere (factory cost, chain margin, supply waterfall, VAT, invoices, totals).
/// Chains without a row use VAT 14% / invoice 10% / extra 0%.
class ChainDiscountProfilesCard extends StatelessWidget {
  final List<ChainDiscountProfileModel> profiles;
  final bool loading;
  final bool saving;
  final String? error;

  /// Admin-only: when false the table is read-only.
  final bool canEdit;
  final Future<void> Function(List<ChainDiscountProfileModel> next) onSave;

  const ChainDiscountProfilesCard({
    super.key,
    required this.profiles,
    required this.onSave,
    this.loading = false,
    this.saving = false,
    this.error,
    this.canEdit = true,
  });

  static String pct(double v) =>
      '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}%';

  Future<void> _edit(BuildContext context,
      {ChainDiscountProfileModel? existing}) async {
    final result = await showDialog<_DialogResult>(
      context: context,
      builder: (_) => _ChainTermsDialog(
          existing: existing,
          readOnly: !canEdit,
          taken: profiles
              .map((p) => ChainDiscountProfileModel.key(p.chain))
              .toSet()),
    );
    if (result == null || !canEdit) return;
    final next = List<ChainDiscountProfileModel>.of(profiles);
    if (existing != null) {
      next.removeWhere((p) =>
          ChainDiscountProfileModel.key(p.chain) ==
          ChainDiscountProfileModel.key(existing.chain));
    }
    if (!result.delete) next.add(result.profile!);
    await onSave(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: const ValueKey('chain_discount_profiles_card'),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: M3TableSurface.color(cs),
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.discount, color: cs.primary),
              const SizedBox(width: 8.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('المؤسسات / السلاسل — الضريبة والخصومات',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      'القيم المحفوظة لكل سلسلة تُطبَّق على كل بيانات Sell-In الخاصة بها (التكلفة، الهامش، الضريبة، الفواتير والإجماليات). '
                      'السلاسل غير المضافة: ضريبة 14% • خصم فاتورة 10% • خصم إضافي 0%.',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (canEdit)
                FilledButton.tonalIcon(
                  key: const ValueKey('chain_discount_add_btn'),
                  onPressed: loading || saving ? null : () => _edit(context),
                  icon: const Icon(AppIcons.add, size: 18.0),
                  label: const Text('إضافة سلسلة'),
                ),
            ],
          ),
          if (!canEdit)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text('التعديل متاح للمدير فقط.',
                  key: const ValueKey('chain_terms_read_only_hint'),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 12.0),
          if (loading || saving) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(error!,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
            ),
          if (!loading && profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                  'لا توجد سلاسل مضافة — كل السلاسل على الافتراضي (ضريبة 14% • فاتورة 10% • إضافي 0%).',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ),
          if (profiles.isNotEmpty)
            Container(
              key: const ValueKey('pm_chain_discount_tonal_surface'),
              decoration: BoxDecoration(
                color: M3TableSurface.color(cs),
                borderRadius: M3Shape.radiusMd,
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              clipBehavior: Clip.antiAlias,
              child: TableScrollContainer(
                showSwipeHint: false,
                showControls: false,
                child: DataTable(
                  key: const ValueKey('pm_chain_discount_table'),
                  showCheckboxColumn: false,
                  headingRowHeight: 48.0,
                  dataRowMinHeight: 56.0,
                  dataRowMaxHeight: 88.0,
                  horizontalMargin: 12.0,
                  columnSpacing: 24.0,
                  columns: const [
                    DataColumn(
                        label: Text('المؤسسة / السلسلة'),
                        headingRowAlignment: MainAxisAlignment.center),
                    DataColumn(
                        label: Text('الضريبة'),
                        numeric: true,
                        headingRowAlignment: MainAxisAlignment.center),
                    DataColumn(
                        label: Text('خصم الفاتورة'),
                        numeric: true,
                        headingRowAlignment: MainAxisAlignment.center),
                    DataColumn(
                        label: Text('الخصم الإضافي'),
                        numeric: true,
                        headingRowAlignment: MainAxisAlignment.center),
                    DataColumn(
                        label: Text('آخر تحديث'),
                        headingRowAlignment: MainAxisAlignment.center),
                  ],
                  rows: [
                    for (final p in profiles)
                      DataRow(
                        onSelectChanged: saving
                            ? null
                            : (_) => _edit(context, existing: p),
                        cells: [
                          DataCell(M3WrapText(p.chain,
                              key: ValueKey(
                                  'chain_terms_row_${ChainDiscountProfileModel.key(p.chain)}'),
                              maxLines: 3,
                              textAlign: TextAlign.center)),
                          DataCell(Text(pct(p.effectiveVatRatePct),
                              textAlign: TextAlign.center)),
                          DataCell(Text(pct(p.invoiceDiscountPct),
                              textAlign: TextAlign.center)),
                          DataCell(Text(pct(p.additionalDiscountPct),
                              textAlign: TextAlign.center)),
                          DataCell(M3WrapText(
                            [
                              if (p.updatedAt != null)
                                p.updatedAt!
                                    .toLocal()
                                    .toString()
                                    .substring(0, 16),
                              if (p.updatedBy.isNotEmpty) p.updatedBy,
                            ].join(' • '),
                            maxLines: 3,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall,
                          )),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DialogResult {
  final ChainDiscountProfileModel? profile;
  final bool delete;
  const _DialogResult.save(ChainDiscountProfileModel this.profile)
      : delete = false;
  const _DialogResult.delete()
      : profile = null,
        delete = true;
}

class _ChainTermsDialog extends StatefulWidget {
  final ChainDiscountProfileModel? existing;
  final Set<String> taken;
  final bool readOnly;
  const _ChainTermsDialog(
      {this.existing, required this.taken, this.readOnly = false});

  @override
  State<_ChainTermsDialog> createState() => _ChainTermsDialogState();
}

class _ChainTermsDialogState extends State<_ChainTermsDialog> {
  late final TextEditingController _chain;
  late final TextEditingController _vat;
  late final TextEditingController _inv;
  late final TextEditingController _add;
  String? _err;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _chain = TextEditingController(text: e?.chain ?? '');
    _vat = TextEditingController(
        text: _fmt(e?.effectiveVatRatePct ?? kDefaultVatRatePct));
    _inv = TextEditingController(
        text: _fmt(e?.invoiceDiscountPct ?? kDefaultInvoiceDiscountPct));
    _add = TextEditingController(
        text: _fmt(e?.additionalDiscountPct ?? kDefaultAdditionalDiscountPct));
  }

  @override
  void dispose() {
    _chain.dispose();
    _vat.dispose();
    _inv.dispose();
    _add.dispose();
    super.dispose();
  }

  void _submit() {
    final chain = _chain.text.trim();
    final vat = double.tryParse(_vat.text.trim());
    final inv = double.tryParse(_inv.text.trim());
    final add = double.tryParse(_add.text.trim());
    final key = ChainDiscountProfileModel.key(chain);
    final isRename = widget.existing == null ||
        ChainDiscountProfileModel.key(widget.existing!.chain) != key;
    String? err;
    if (chain.isEmpty) {
      err = 'اسم السلسلة مطلوب';
    } else if (isRename && widget.taken.contains(key)) {
      err = 'هذه السلسلة مضافة بالفعل';
    } else if (vat == null || vat < 0 || vat > 100) {
      err = 'الضريبة يجب أن تكون من 0 إلى 100';
    } else if (inv == null ||
        inv < 0 ||
        inv >= 100 ||
        add == null ||
        add < 0 ||
        add >= 100) {
      err = 'الخصومات يجب أن تكون من 0 إلى أقل من 100';
    }
    if (err != null) {
      setState(() => _err = err);
      return;
    }
    Navigator.pop(
        context,
        _DialogResult.save(ChainDiscountProfileModel(
            chain: chain,
            vatRatePct: vat!,
            invoiceDiscountPct: inv!,
            additionalDiscountPct: add!)));
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف إعدادات السلسلة'),
        content: Text(
            'سيتم حذف إعدادات «${widget.existing!.chain}» والعودة للافتراضي (ضريبة 14% • فاتورة 10% • إضافي 0%).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              key: const ValueKey('chain_discount_confirm_delete_btn'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.pop(context, const _DialogResult.delete());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = widget.existing;
    final ro = widget.readOnly;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(existing == null
            ? 'إضافة سلسلة'
            : (ro ? 'إعدادات السلسلة' : 'تعديل إعدادات السلسلة')),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('chain_discount_chain_field'),
                controller: _chain,
                enabled: existing == null && !ro,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'السلسلة (كما في شيت الكاشير)',
                  hintText: 'fathalla',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12.0),
              TextField(
                key: const ValueKey('chain_discount_vat_field'),
                controller: _vat,
                enabled: !ro,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'الضريبة %', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12.0),
              TextField(
                key: const ValueKey('chain_discount_invoice_field'),
                controller: _inv,
                enabled: !ro,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'خصم الفاتورة %', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12.0),
              TextField(
                key: const ValueKey('chain_discount_additional_field'),
                controller: _add,
                enabled: !ro,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'الخصم الإضافي %',
                    border: OutlineInputBorder()),
              ),
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(_err!,
                      key: const ValueKey('chain_discount_error'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error)),
                ),
            ],
          ),
        ),
        actions: [
          if (existing != null && !ro)
            TextButton(
                key: const ValueKey('chain_discount_delete_btn'),
                onPressed: _confirmDelete,
                child: Text('حذف',
                    style: TextStyle(color: theme.colorScheme.error))),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ro ? 'إغلاق' : 'إلغاء')),
          if (!ro)
            FilledButton(
              key: const ValueKey('chain_discount_save_btn'),
              onPressed: _submit,
              child: const Text('حفظ'),
            ),
        ],
      ),
    );
  }
}

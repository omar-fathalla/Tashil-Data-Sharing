import 'package:flutter/material.dart';

import '../../../../core/theme/m3_shape.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../data/chain_discount_repository.dart';

/// Product Master → Calculator tab: per-chain discount profiles (add / edit / delete).
/// Saved profiles drive the CPFR cost of that chain:
/// list price incl. VAT × (1 − invoice%) × (1 − additional%). Chains without a profile use 10% / 0%.
class ChainDiscountProfilesCard extends StatelessWidget {
  final List<ChainDiscountProfileModel> profiles;
  final bool loading;
  final bool saving;
  final String? error;
  final Future<void> Function(List<ChainDiscountProfileModel> next) onSave;

  const ChainDiscountProfilesCard({
    super.key,
    required this.profiles,
    required this.onSave,
    this.loading = false,
    this.saving = false,
    this.error,
  });

  String _pct(double v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}%';

  Future<void> _edit(BuildContext context, {ChainDiscountProfileModel? existing}) async {
    final result = await showDialog<ChainDiscountProfileModel>(
      context: context,
      builder: (_) => _ChainDiscountDialog(existing: existing, taken: profiles.map((p) => ChainDiscountProfileModel.key(p.chain)).toSet()),
    );
    if (result == null) return;
    final next = List<ChainDiscountProfileModel>.of(profiles);
    if (existing != null) {
      next.removeWhere((p) => ChainDiscountProfileModel.key(p.chain) == ChainDiscountProfileModel.key(existing.chain));
    }
    next.add(result);
    await onSave(next);
  }

  Future<void> _delete(BuildContext context, ChainDiscountProfileModel p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف خصم السلسلة'),
        content: Text('سيتم حذف خصومات «${p.chain}» والعودة للافتراضي (خصم فاتورة 10% / إضافي 0%).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    await onSave(profiles.where((x) => ChainDiscountProfileModel.key(x.chain) != ChainDiscountProfileModel.key(p.chain)).toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: const ValueKey('chain_discount_profiles_card'),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.discount, color: cs.primary),
              const SizedBox(width: 8.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('خصومات السلاسل', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      'التكلفة = سعر القطعة شامل الضريبة × (1 − خصم الفاتورة) × (1 − الخصم الإضافي). السلاسل بدون إعداد: 10% / 0%.',
                      style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('chain_discount_add_btn'),
                onPressed: loading || saving ? null : () => _edit(context),
                icon: const Icon(AppIcons.add, size: 18.0),
                label: const Text('إضافة سلسلة'),
              ),
            ],
          ),
          const SizedBox(height: 12.0),
          if (loading || saving) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(error!, style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
            ),
          if (!loading && profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text('لا توجد خصومات مخصصة — كل السلاسل على الافتراضي (10% / 0%).',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
          if (profiles.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
              columns: const [
                DataColumn(label: Text('السلسلة')),
                DataColumn(label: Text('خصم الفاتورة %'), numeric: true),
                DataColumn(label: Text('خصم إضافي %'), numeric: true),
                DataColumn(label: Text('آخر تعديل')),
                DataColumn(label: Text('')),
              ],
              rows: [
                for (final p in profiles)
                  DataRow(cells: [
                    DataCell(Text(p.chain)),
                    DataCell(Text(_pct(p.invoiceDiscountPct))),
                    DataCell(Text(_pct(p.additionalDiscountPct))),
                    DataCell(Text(
                      [
                        if (p.updatedAt != null) p.updatedAt!.toLocal().toString().substring(0, 16),
                        if (p.updatedBy.isNotEmpty) p.updatedBy,
                      ].join(' • '),
                      style: theme.textTheme.labelSmall,
                    )),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'تعديل',
                        icon: const Icon(AppIcons.edit),
                        onPressed: saving ? null : () => _edit(context, existing: p),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        icon: Icon(AppIcons.delete, color: cs.error),
                        onPressed: saving ? null : () => _delete(context, p),
                      ),
                    ])),
                  ]),
              ],
            ),
            ),
        ],
      ),
    );
  }
}

class _ChainDiscountDialog extends StatefulWidget {
  final ChainDiscountProfileModel? existing;
  final Set<String> taken;
  const _ChainDiscountDialog({this.existing, required this.taken});

  @override
  State<_ChainDiscountDialog> createState() => _ChainDiscountDialogState();
}

class _ChainDiscountDialogState extends State<_ChainDiscountDialog> {
  late final TextEditingController _chain;
  late final TextEditingController _inv;
  late final TextEditingController _add;
  String? _err;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _chain = TextEditingController(text: e?.chain ?? '');
    _inv = TextEditingController(text: (e?.invoiceDiscountPct ?? kDefaultInvoiceDiscountPct).toString());
    _add = TextEditingController(text: (e?.additionalDiscountPct ?? kDefaultAdditionalDiscountPct).toString());
  }

  @override
  void dispose() {
    _chain.dispose();
    _inv.dispose();
    _add.dispose();
    super.dispose();
  }

  void _submit() {
    final chain = _chain.text.trim();
    final inv = double.tryParse(_inv.text.trim());
    final add = double.tryParse(_add.text.trim());
    final key = ChainDiscountProfileModel.key(chain);
    final isRename = widget.existing == null || ChainDiscountProfileModel.key(widget.existing!.chain) != key;
    String? err;
    if (chain.isEmpty) {
      err = 'اسم السلسلة مطلوب';
    } else if (isRename && widget.taken.contains(key)) {
      err = 'هذه السلسلة لها خصومات بالفعل';
    } else if (inv == null || inv < 0 || inv >= 100 || add == null || add < 0 || add >= 100) {
      err = 'النسب يجب أن تكون من 0 إلى أقل من 100';
    }
    if (err != null) {
      setState(() => _err = err);
      return;
    }
    Navigator.pop(context, ChainDiscountProfileModel(chain: chain, invoiceDiscountPct: inv!, additionalDiscountPct: add!));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.existing == null ? 'إضافة خصومات سلسلة' : 'تعديل خصومات السلسلة'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('chain_discount_chain_field'),
              controller: _chain,
              decoration: const InputDecoration(
                labelText: 'السلسلة (كما في شيت الكاشير، مثال: fathalla)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12.0),
            TextField(
              key: const ValueKey('chain_discount_invoice_field'),
              controller: _inv,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'خصم الفاتورة %', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12.0),
            TextField(
              key: const ValueKey('chain_discount_additional_field'),
              controller: _add,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'خصم إضافي %', border: OutlineInputBorder()),
            ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(_err!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          key: const ValueKey('chain_discount_save_btn'),
          onPressed: _submit,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/theme/m3_shape.dart';
import '../../../../core/utils/app_date_format.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_dropdown.dart';
import '../../../../core/widgets/m3_states.dart';
import '../../data/chain_discount_repository.dart';
import '../../../../core/widgets/m3_table_surface.dart';
import '../../../../core/widgets/m3_wrap_text.dart';
import '../../../../core/widgets/table_scroll_container.dart';

/// «آخر تحديث» cell: calendar date only (`yyyy-MM-dd`), never email or time.
String formatChainDiscountUpdatedAt(DateTime? at) {
  if (at == null) return '';
  return AppDateFormat.formatDate(at);
}

/// Product Master → «حاسبة الطلبيات»: one row per chain with its VAT, invoice
/// discount and extra discount. Saved terms are the single source of truth for that chain's Sell-In
/// everywhere (factory cost, chain margin, supply waterfall, VAT, invoices, totals).
/// Chains without a row use VAT 14% / invoice 10% / extra 0%.
class ChainDiscountProfilesCard extends StatelessWidget {
  final List<ChainDiscountProfileModel> profiles;
  final bool loading;
  final bool saving;
  /// Friendly Arabic message (never a raw exception string).
  final String? error;
  final String errorTitle;

  /// Shown as «إعادة المحاولة» on the error banner when set.
  final VoidCallback? onRetry;

  /// Admin-only: when false the table is read-only.
  final bool canEdit;
  final Future<void> Function(List<ChainDiscountProfileModel> next) onSave;

  /// Chains already present in counted Sell-In / Sell-Out. Used when [loadKnownChains] is null.
  final List<KnownChain> knownChains;

  /// Reloads [knownChains] when the add dialog opens and when the user retries.
  final Future<List<KnownChain>> Function()? loadKnownChains;

  const ChainDiscountProfilesCard({
    super.key,
    required this.profiles,
    required this.onSave,
    this.loading = false,
    this.saving = false,
    this.error,
    this.errorTitle = 'تعذّر تحميل إعدادات السلاسل',
    this.onRetry,
    this.canEdit = true,
    this.knownChains = const [],
    this.loadKnownChains,
  });

  static String pct(double v) =>
      '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}%';

  Future<void> _edit(BuildContext context,
      {ChainDiscountProfileModel? existing}) async {
    if (saving) return;
    final result = await showDialog<_DialogResult>(
      context: context,
      builder: (_) => _ChainTermsDialog(
          existing: existing,
          readOnly: !canEdit,
          taken: profiles
              .map((p) => ChainDiscountProfileModel.key(p.chain))
              .toSet(),
          knownChains: knownChains,
          loadKnownChains: loadKnownChains),
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
          if (error != null && !loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: M3ErrorBanner(
                key: const ValueKey('chain_discount_error_banner'),
                title: errorTitle,
                message: error,
                onRetry: onRetry,
              ),
            ),
          if (!loading && profiles.isEmpty && error == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                  'لا توجد سلاسل مضافة — كل السلاسل على الافتراضي (ضريبة 14% • فاتورة 10% • إضافي 0%).',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ),
          if (profiles.isNotEmpty)
            AbsorbPointer(
              key: const ValueKey('pm_chain_discount_absorb'),
              absorbing: saving,
              child: Opacity(
                opacity: saving ? 0.6 : 1.0,
                child: Container(
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
                          DataCell(Text(
                            formatChainDiscountUpdatedAt(p.updatedAt),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall,
                          )),
                        ],
                      ),
                  ],
                ),
              ),
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
  final List<KnownChain> knownChains;
  final Future<List<KnownChain>> Function()? loadKnownChains;
  const _ChainTermsDialog({
    this.existing,
    required this.taken,
    this.readOnly = false,
    this.knownChains = const [],
    this.loadKnownChains,
  });

  @override
  State<_ChainTermsDialog> createState() => _ChainTermsDialogState();
}

class _ChainTermsDialogState extends State<_ChainTermsDialog> {
  late final TextEditingController _chain;
  late final TextEditingController _vat;
  late final TextEditingController _inv;
  late final TextEditingController _add;
  String? _err;
  List<KnownChain> _chains = const [];
  bool _chainsLoading = false;
  String? _chainsError;
  String? _selectedKey;

  /// A second tap on «حفظ» / «حذف» while the dialog is closing must not pop again.
  bool _closing = false;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  bool _takenKey(String key) =>
      widget.taken.contains(ChainDiscountProfileModel.key(key));

  bool get _adding => widget.existing == null;

  bool get _hasSelectable =>
      _chains.any((c) => c.key.isNotEmpty && !_takenKey(c.key));

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
    _chains = List<KnownChain>.of(widget.knownChains);
    if (_adding && widget.loadKnownChains != null) {
      _chainsLoading = _chains.isEmpty;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadChains());
    }
  }

  Future<void> _loadChains() async {
    final load = widget.loadKnownChains;
    if (load == null) return;
    setState(() {
      _chainsLoading = true;
      _chainsError = null;
    });
    try {
      final list = await load();
      if (!mounted) return;
      setState(() {
        _chains = list;
        _chainsLoading = false;
        if (_selectedKey != null &&
            !list.any((c) => c.key == _selectedKey && !_takenKey(c.key))) {
          _selectedKey = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chains = const [];
        _chainsLoading = false;
        _chainsError = friendlyKnownChainsError(e);
        _selectedKey = null;
      });
    }
  }

  @override
  void dispose() {
    _chain.dispose();
    _vat.dispose();
    _inv.dispose();
    _add.dispose();
    super.dispose();
  }

  String _optionLabel(KnownChain chain) {
    final base = chain.displayName.trim().isEmpty ? chain.key : chain.displayName;
    final shown = base.toLowerCase().contains(chain.key.toLowerCase())
        ? base
        : '$base (${chain.key})';
    return _takenKey(chain.key) ? '$shown — $kKnownChainsAlreadyAdded' : shown;
  }

  void _submit() {
    if (_closing) return;
    final chain = _adding ? (_selectedKey ?? '') : _chain.text.trim();
    final vat = double.tryParse(_vat.text.trim());
    final inv = double.tryParse(_inv.text.trim());
    final add = double.tryParse(_add.text.trim());
    final key = ChainDiscountProfileModel.key(chain);
    final isRename = widget.existing == null ||
        ChainDiscountProfileModel.key(widget.existing!.chain) != key;
    String? err;
    if (chain.isEmpty) {
      err = _adding ? kKnownChainsPickMessage : 'اسم السلسلة مطلوب';
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
    _closing = true;
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
    if (ok == true && mounted && !_closing) {
      _closing = true;
      Navigator.pop(context, const _DialogResult.delete());
    }
  }

  Widget _chainPicker(ThemeData theme) {
    if (!_adding) {
      return TextField(
        key: const ValueKey('chain_discount_chain_field'),
        controller: _chain,
        enabled: false,
        textDirection: TextDirection.ltr,
        decoration: const InputDecoration(
          labelText: 'السلسلة',
          border: OutlineInputBorder(),
        ),
      );
    }
    if (_chainsLoading) {
      return const Column(
        key: ValueKey('chain_discount_chains_loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(),
          SizedBox(height: 8.0),
          Text('جاري تحميل السلاسل…'),
        ],
      );
    }
    if (_chainsError != null) {
      return _chainsNotice(
        key: const ValueKey('chain_discount_chains_error'),
        message: _chainsError!,
        color: theme.colorScheme.error,
      );
    }
    if (_chains.isEmpty) {
      return _chainsNotice(
        key: const ValueKey('chain_discount_chains_empty'),
        message: kKnownChainsEmptyMessage,
        color: theme.colorScheme.onSurfaceVariant,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_hasSelectable)
          Padding(
            key: const ValueKey('chain_discount_chains_all_added'),
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              kKnownChainsAllAddedMessage,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        M3Dropdown<String>(
          key: const ValueKey('chain_discount_chain_dropdown'),
          width: 440,
          fitOptions: true,
          dense: true,
          label: 'السلسلة',
          hint: 'اختر سلسلة',
          value: _selectedKey ?? '',
          options: [
            for (final c in _chains)
              if (c.key.isNotEmpty)
                M3DropdownOption<String>(
                  c.key,
                  _optionLabel(c),
                  enabled: !_takenKey(c.key),
                ),
          ],
          onChanged: (v) => setState(() {
            _selectedKey = v;
            _err = null;
          }),
        ),
        if (_chains.any((c) => _takenKey(c.key)))
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'السلاسل المضافة بالفعل تُعدَّل من الجدول.',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _chainsNotice({
    required Key key,
    required String message,
    required Color color,
  }) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: TextStyle(color: color)),
        if (widget.loadKnownChains != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey('chain_discount_chains_retry'),
              onPressed: _chainsLoading ? null : _loadChains,
              child: const Text('إعادة المحاولة'),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = widget.existing;
    final ro = widget.readOnly;
    final addBlocked = _adding &&
        (_chainsLoading ||
            _chainsError != null ||
            _chains.isEmpty ||
            !_hasSelectable);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(existing == null
            ? 'إضافة سلسلة'
            : (ro ? 'إعدادات السلسلة' : 'تعديل إعدادات السلسلة')),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _chainPicker(theme),
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
              onPressed: addBlocked ? null : _submit,
              child: const Text('حفظ'),
            ),
        ],
      ),
    );
  }
}

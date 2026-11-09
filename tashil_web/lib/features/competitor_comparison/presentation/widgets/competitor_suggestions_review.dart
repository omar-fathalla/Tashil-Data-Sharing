import 'package:flutter/material.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/m3_palette.dart';
import 'package:tashil_web/core/theme/m3_shape.dart';
import 'package:tashil_web/core/theme/m3_spacing.dart';
import 'package:tashil_web/core/widgets/m3_dropdown.dart';

/// Arabic RTL review queue for pending AI competitor suggestions.
/// Pending items never appear in Compare KPIs until owner approve.
class CompetitorSuggestionsReview extends StatefulWidget {
  final ApiClient apiClient;
  final String chain;
  final int year;
  final bool isOwner;

  const CompetitorSuggestionsReview({
    super.key,
    required this.apiClient,
    required this.chain,
    required this.year,
    this.isOwner = true,
  });

  @override
  State<CompetitorSuggestionsReview> createState() =>
      CompetitorSuggestionsReviewState();
}

class CompetitorSuggestionsReviewState
    extends State<CompetitorSuggestionsReview> {
  List<CompetitorSuggestionModel> _items = const [];
  bool _loading = true;
  bool _running = false;
  String? _error;
  int _batchSize = 10;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant CompetitorSuggestionsReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chain != widget.chain || oldWidget.year != widget.year) {
      _reload();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.apiClient.listCompetitorSuggestions(
        chain: widget.chain,
        status: 'pending',
      );
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _runBatch() async {
    if (!widget.isOwner || _running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      await widget.apiClient.runCompetitorSuggestions(
        chain: widget.chain,
        limit: _batchSize,
        year: widget.year,
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _approve(CompetitorSuggestionModel s) async {
    setState(() => _busyId = s.id);
    try {
      await widget.apiClient.approveCompetitorSuggestion(s.id);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(CompetitorSuggestionModel s) async {
    setState(() => _busyId = s.id);
    try {
      await widget.apiClient.rejectCompetitorSuggestion(s.id);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'اقتراحات المنافسين (بانتظار الموافقة)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.isOwner) ...[
                SizedBox(
                  width: 96,
                  child: M3Dropdown<int>(
                    value: _batchSize,
                    label: 'دفعة',
                    options: const [
                      M3DropdownOption(5, '5'),
                      M3DropdownOption(10, '10'),
                      M3DropdownOption(20, '20'),
                    ],
                    onChanged: _running
                        ? null
                        : (v) => setState(() => _batchSize = v),
                  ),
                ),
                M3Spacing.gapSM,
                FilledButton.icon(
                  onPressed: _running ? null : _runBatch,
                  icon: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(_running ? 'جاري التشغيل…' : 'تشغيل دفعة'),
                ),
              ],
            ],
          ),
          M3Spacing.gapSM,
          Text(
            'الاقتراحات المعلّقة لا تظهر في المقارنة أو مؤشرات الأداء حتى الموافقة.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (_error != null) ...[
            M3Spacing.gapSM,
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: M3Palette.dangerAccent,
              ),
            ),
          ],
          M3Spacing.gapMD,
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'لا توجد اقتراحات بانتظار الموافقة',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            )
          else
            ..._items.map(_buildCard),
        ],
      ),
    );
  }

  Widget _buildCard(CompetitorSuggestionModel s) {
    final theme = Theme.of(context);
    final busy = _busyId == s.id;
    return Card(
      key: ValueKey('suggestion-${s.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _skuBlock(
                    label: 'صنف الشركة',
                    name: s.ownSkuName.isEmpty ? s.ownBarcode : s.ownSkuName,
                    barcode: s.ownBarcode,
                    price: s.ownUnitPrice,
                    units: s.ownUnits,
                    color: M3Palette.success,
                    surface: M3Palette.successSurface,
                    onSurface: M3Palette.onSuccessSurface,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
                  child: Icon(Icons.compare_arrows_rounded, color: theme.colorScheme.outline),
                ),
                Expanded(
                  child: _skuBlock(
                    label: 'المنافس المقترح',
                    name: s.competitorSkuName.isEmpty
                        ? s.competitorBarcode
                        : s.competitorSkuName,
                    barcode: s.competitorBarcode,
                    price: s.competitorUnitPrice,
                    units: s.competitorUnits,
                    color: M3Palette.dangerAccent,
                    surface: M3Palette.dangerSurface,
                    onSurface: M3Palette.onDangerSurface,
                  ),
                ),
              ],
            ),
            M3Spacing.gapSM,
            Text(
              s.reasonAr,
              style: theme.textTheme.bodyMedium,
            ),
            M3Spacing.gapXS,
            Text(
              'الثقة: ${(s.confidence * 100).toStringAsFixed(0)}% · الترتيب: ${s.rank}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.isOwner) ...[
              M3Spacing.gapSM,
              Row(
                children: [
                  FilledButton(
                    onPressed: busy ? null : () => _approve(s),
                    style: FilledButton.styleFrom(
                      backgroundColor: M3Palette.success,
                      foregroundColor: M3Palette.onSuccessSurface,
                    ),
                    child: const Text('موافقة'),
                  ),
                  M3Spacing.gapSM,
                  OutlinedButton(
                    onPressed: busy ? null : () => _reject(s),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: M3Palette.dangerAccent,
                    ),
                    child: const Text('رفض'),
                  ),
                  if (busy) ...[
                    M3Spacing.gapSM,
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _skuBlock({
    required String label,
    required String name,
    required String barcode,
    required double price,
    required int units,
    required Color color,
    required Color surface,
    required Color onSurface,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: M3Shape.radiusMd,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: onSurface),
          ),
          M3Spacing.gapXXS,
          Text(
            name,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            barcode,
            style: theme.textTheme.labelSmall?.copyWith(
              color: onSurface.withValues(alpha: 0.8),
            ),
          ),
          M3Spacing.gapXS,
          Text(
            'سعر ${price.toStringAsFixed(2)} · مبيعات $units',
            style: theme.textTheme.bodySmall?.copyWith(color: onSurface),
          ),
        ],
      ),
    );
  }
}

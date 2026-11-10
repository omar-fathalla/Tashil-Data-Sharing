import 'package:flutter/material.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/m3_palette.dart';
import 'package:tashil_web/core/theme/m3_shape.dart';
import 'package:tashil_web/core/theme/m3_spacing.dart';
import 'package:tashil_web/core/widgets/app_icons.dart';
import 'package:tashil_web/core/widgets/m3_dropdown.dart';
import 'package:tashil_web/core/widgets/m3_feedback.dart';

/// One own-SKU card with its pending competitor suggestions (2–3 typically).
class PendingSuggestionGroup {
  final String ownBarcode;
  final String ownSkuName;
  final double ownUnitPrice;
  final int ownUnits;
  final List<CompetitorSuggestionModel> suggestions;

  const PendingSuggestionGroup({
    required this.ownBarcode,
    required this.ownSkuName,
    required this.ownUnitPrice,
    required this.ownUnits,
    required this.suggestions,
  });
}

/// Groups flat pending rows by own barcode (rank ascending within each group).
List<PendingSuggestionGroup> groupPendingSuggestionsByOwnSku(
  List<CompetitorSuggestionModel> items,
) {
  final order = <String>[];
  final byOwn = <String, List<CompetitorSuggestionModel>>{};
  for (final s in items) {
    final key = s.ownBarcode.trim();
    if (key.isEmpty) continue;
    final list = byOwn.putIfAbsent(key, () {
      order.add(key);
      return <CompetitorSuggestionModel>[];
    });
    if (!list.any((e) => e.id == s.id)) {
      list.add(s);
    }
  }
  final out = <PendingSuggestionGroup>[];
  for (final key in order) {
    final list = List<CompetitorSuggestionModel>.from(byOwn[key]!)
      ..sort((a, b) => a.rank.compareTo(b.rank));
    final first = list.first;
    out.add(
      PendingSuggestionGroup(
        ownBarcode: key,
        ownSkuName: first.ownSkuName,
        ownUnitPrice: first.ownUnitPrice,
        ownUnits: first.ownUnits,
        suggestions: list,
      ),
    );
  }
  return out;
}

/// Arabic RTL review queue for pending AI competitor suggestions.
/// Pending items never appear in Compare KPIs until owner approve.
/// Batch size only controls «تشغيل دفعة» — it never caps the pending list.
class CompetitorSuggestionsReview extends StatefulWidget {
  final ApiClient apiClient;
  final String chain;
  final int year;
  final bool isOwner;

  /// Called after any approve so Compare can treat new mappings as ready.
  final VoidCallback? onMappingsChanged;

  /// Per-chain /run cooldown (backend ~30s). Shorten in widget tests.
  final Duration chainRunCooldown;

  /// Backoff after HTTP 429 before retrying «توليد للكل».
  final Duration rateLimitBackoff;

  const CompetitorSuggestionsReview({
    super.key,
    required this.apiClient,
    required this.chain,
    required this.year,
    this.isOwner = true,
    this.onMappingsChanged,
    this.chainRunCooldown = const Duration(seconds: 30),
    this.rateLimitBackoff = const Duration(seconds: 35),
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
  bool _generatingAll = false;
  bool _stopGenerateAll = false;
  String? _error;
  int _batchSize = 10;
  String? _busyId;
  String? _busyGroupKey;

  /// Progress for «توليد للكل»: covered so far / estimated total own SKUs.
  int _generateAllDone = 0;
  int _generateAllTotal = 0;

  /// Paginate grouped own-SKU cards (batch dropdown must NOT limit this list).
  static const int _pageSize = 20;
  int _pageIndex = 0;

  bool get _busyBatch => _running || _generatingAll;

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

  List<PendingSuggestionGroup> get _groups =>
      groupPendingSuggestionsByOwnSku(_items);

  void _surfaceError(Object e) {
    final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    setState(() => _error = msg);
    if (!mounted) return;
    M3Feedback.showError(
      context,
      msg.isEmpty ? 'حدث خطأ أثناء اقتراحات المنافسين' : msg,
    );
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
        final pages = (_groups.isEmpty)
            ? 1
            : ((_groups.length + _pageSize - 1) ~/ _pageSize);
        if (_pageIndex >= pages) _pageIndex = pages - 1;
        if (_pageIndex < 0) _pageIndex = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _surfaceError(e);
    }
  }

  Future<void> _runBatch() async {
    if (!widget.isOwner || _busyBatch) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.runCompetitorSuggestions(
        chain: widget.chain,
        limit: _batchSize,
        year: widget.year,
      );
      final created = (result['created_count'] as num?)?.toInt() ?? 0;
      final summary =
          (result['summary_ar'] ?? result['error'])?.toString().trim() ?? '';
      final rankFailures = (result['rank_failures'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      if (created == 0 && (summary.isNotEmpty || rankFailures > 0)) {
        _showRunFailure(
          summary.isNotEmpty ? summary : 'لم يتم إنشاء اقتراحات',
        );
      }
      await _reload();
    } catch (e) {
      if (!mounted) return;
      final detail = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      _showRunFailure(detail);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _requestStopGenerateAll() {
    if (!_generatingAll) return;
    setState(() => _stopGenerateAll = true);
  }

  static const int _maxRateLimitRetries = 5;

  /// Loops POST …/run batches until remaining_uncovered=0, user stops, or error.
  /// Respects the ~30s per-chain rate limit; 429 uses a slightly longer backoff
  /// (capped at [_maxRateLimitRetries]). Never auto-approves — rows stay pending.
  Future<void> _generateAll() async {
    if (!widget.isOwner || _busyBatch) return;
    setState(() {
      _generatingAll = true;
      _stopGenerateAll = false;
      _error = null;
      _generateAllDone = 0;
      _generateAllTotal = 0;
    });
    var previousRemaining = -1;
    var rateLimitRetries = 0;
    try {
      while (mounted && !_stopGenerateAll) {
        Map<String, dynamic> result;
        try {
          result = await widget.apiClient.runCompetitorSuggestions(
            chain: widget.chain,
            limit: _batchSize,
            year: widget.year,
          );
          rateLimitRetries = 0;
        } on CompetitorSuggestRateLimitException catch (e) {
          if (!mounted || _stopGenerateAll) break;
          rateLimitRetries++;
          if (rateLimitRetries > _maxRateLimitRetries) {
            _showRunFailure(
              'تم إيقاف التوليد بعد عدة تجاوزات لحد الطلبات (${e.message})',
            );
            break;
          }
          await Future<void>.delayed(widget.rateLimitBackoff);
          continue;
        }

        final processed = (result['processed_own'] as num?)?.toInt() ?? 0;
        final created = (result['created_count'] as num?)?.toInt() ?? 0;
        final remaining =
            (result['remaining_uncovered'] as num?)?.toInt() ?? 0;
        final summary =
            (result['summary_ar'] ?? result['error'])?.toString().trim() ?? '';
        final rankFailures = (result['rank_failures'] as num?)?.toInt() ?? 0;

        if (!mounted) return;
        setState(() {
          if (_generateAllTotal <= 0) {
            _generateAllTotal = remaining + processed;
            if (_generateAllTotal < 1) _generateAllTotal = 1;
          }
          _generateAllDone =
              (_generateAllDone + processed).clamp(0, _generateAllTotal);
        });

        if (created == 0 && (summary.isNotEmpty || rankFailures > 0)) {
          _showRunFailure(
            summary.isNotEmpty ? summary : 'لم يتم إنشاء اقتراحات',
          );
          break;
        }

        await _reload();
        if (!mounted || _stopGenerateAll) break;

        if (remaining <= 0) break;
        // Stall: no progress — stop with a clear message (not silent).
        if (processed == 0 ||
            (created == 0 &&
                previousRemaining >= 0 &&
                remaining >= previousRemaining)) {
          _showInfoMessage(
            'توقف التوليد: لا تقدّم إضافي (المتبقي $remaining صنف)',
          );
          break;
        }
        previousRemaining = remaining;

        // Wait out the per-chain cooldown before the next batch.
        final cooldown = widget.chainRunCooldown;
        if (cooldown > Duration.zero) {
          final deadline = DateTime.now().add(cooldown);
          while (mounted &&
              !_stopGenerateAll &&
              DateTime.now().isBefore(deadline)) {
            final left = deadline.difference(DateTime.now());
            final step = cooldown < const Duration(seconds: 1)
                ? left
                : (left > const Duration(seconds: 1)
                    ? const Duration(seconds: 1)
                    : left);
            await Future<void>.delayed(step);
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      final detail = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      _showRunFailure(detail);
    } finally {
      if (mounted) {
        setState(() {
          _generatingAll = false;
          _stopGenerateAll = false;
        });
        await _reload();
      }
    }
  }

  void _showInfoMessage(String message) {
    setState(() => _error = message);
    if (!mounted) return;
    M3Feedback.showInfo(context, message);
  }

  /// Surfaces empty/failed batch runs with an Arabic snackbar (not silent empty).
  void _showRunFailure(String detail) {
    final message = detail.startsWith('تعذر تشغيل الاقتراحات')
        ? detail
        : 'تعذر تشغيل الاقتراحات: $detail';
    setState(() => _error = message);
    if (!mounted) return;
    M3Feedback.showError(context, message);
  }

  Future<void> _approve(CompetitorSuggestionModel s) async {
    setState(() => _busyId = s.id);
    try {
      await widget.apiClient.approveCompetitorSuggestion(s.id);
      await _reload();
      widget.onMappingsChanged?.call();
    } catch (e) {
      if (!mounted) return;
      _surfaceError(e);
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
      _surfaceError(e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _approveAll(PendingSuggestionGroup group) async {
    if (!widget.isOwner || group.suggestions.isEmpty) return;
    setState(() => _busyGroupKey = group.ownBarcode);
    try {
      for (final s in List<CompetitorSuggestionModel>.from(group.suggestions)) {
        await widget.apiClient.approveCompetitorSuggestion(s.id);
      }
      await _reload();
      widget.onMappingsChanged?.call();
    } catch (e) {
      if (!mounted) return;
      _surfaceError(e);
      await _reload();
    } finally {
      if (mounted) setState(() => _busyGroupKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final groups = _groups;
    final pageCount =
        groups.isEmpty ? 1 : ((groups.length + _pageSize - 1) ~/ _pageSize);
    final pageStart = (_pageIndex * _pageSize).clamp(0, groups.length);
    final pageEnd = (pageStart + _pageSize).clamp(0, groups.length);
    final pageGroups = groups.isEmpty
        ? const <PendingSuggestionGroup>[]
        : groups.sublist(pageStart, pageEnd);

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
                    ],
                    onChanged: _busyBatch
                        ? null
                        : (v) => setState(() => _batchSize = v),
                  ),
                ),
                M3Spacing.gapSM,
                FilledButton.tonalIcon(
                  key: const ValueKey('run-suggestions-batch'),
                  onPressed: _busyBatch ? null : _runBatch,
                  icon: _running && !_generatingAll
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(_running && !_generatingAll
                      ? 'جاري التشغيل…'
                      : 'تشغيل دفعة'),
                ),
                M3Spacing.gapSM,
                if (_generatingAll)
                  OutlinedButton.icon(
                    key: const ValueKey('stop-generate-all-suggestions'),
                    onPressed: _stopGenerateAll ? null : _requestStopGenerateAll,
                    icon: const Icon(Icons.stop_circle_rounded, size: 18),
                    label: Text(_stopGenerateAll ? 'جارٍ الإيقاف…' : 'إيقاف'),
                  )
                else
                  FilledButton.tonalIcon(
                    key: const ValueKey('generate-all-suggestions'),
                    onPressed: _busyBatch ? null : _generateAll,
                    icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                    label: const Text('توليد للكل'),
                  ),
              ],
            ],
          ),
          if (_generatingAll) ...[
            M3Spacing.gapSM,
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
                M3Spacing.gapSM,
                Expanded(
                  child: Text(
                    _generateAllTotal > 0
                        ? '$_generateAllDone من $_generateAllTotal صنف'
                        : 'جاري التوليد…',
                    key: const ValueKey('generate-all-progress'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          M3Spacing.gapSM,
          Text(
            'هذه القائمة تعرض الاقتراحات المخزّنة بانتظار الموافقة فقط '
            '(لا تُنشأ تلقائياً لكل أصناف الشركة). '
            'تشغيل دفعة (حتى 10 أصناف) أو «توليد للكل» أو اختيار صنف في تبويب الأسعار يولّد اقتراحات جديدة (تبقى معلّقة). '
            'حجم الدفعة يخص التشغيل اليدوي فقط ولا يقيّد قائمة الانتظار. '
            'الاقتراحات المعلّقة لا تظهر في المقارنة أو مؤشرات الأداء حتى الموافقة.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (!_loading && groups.isNotEmpty) ...[
            M3Spacing.gapXS,
            Text(
              '${groups.length} صنف · ${_items.length} اقتراح بانتظار الموافقة',
              key: const ValueKey('pending-suggestions-count'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
          else if (groups.isEmpty)
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
          else ...[
            for (final g in pageGroups) _buildGroupCard(g),
            if (pageCount > 1) ...[
              M3Spacing.gapSM,
              _buildPager(theme, cs, groups.length, pageCount, pageStart, pageEnd),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPager(
    ThemeData theme,
    ColorScheme cs,
    int totalGroups,
    int pageCount,
    int pageStart,
    int pageEnd,
  ) {
    final rangeLabel = totalGroups == 0
        ? '0 من 0'
        : '${pageStart + 1}–$pageEnd من $totalGroups';
    return Row(
      children: [
        IconButton(
          tooltip: 'الصفحة السابقة',
          onPressed: _pageIndex > 0
              ? () => setState(() => _pageIndex--)
              : null,
          icon: const Icon(AppIcons.chevronStart),
        ),
        Expanded(
          child: Text(
            'صفحة ${_pageIndex + 1} من $pageCount · $rangeLabel',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        IconButton(
          tooltip: 'الصفحة التالية',
          onPressed: _pageIndex < pageCount - 1
              ? () => setState(() => _pageIndex++)
              : null,
          icon: const Icon(AppIcons.chevronEnd),
        ),
      ],
    );
  }

  Widget _buildGroupCard(PendingSuggestionGroup group) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final groupBusy = _busyGroupKey == group.ownBarcode;
    final ownName =
        group.ownSkuName.isEmpty ? group.ownBarcode : group.ownSkuName;

    return Card(
      key: ValueKey('suggestion-group-${group.ownBarcode}'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: M3Shape.radiusLg,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'صنف الشركة',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: M3Palette.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      M3Spacing.gapXXS,
                      Text(
                        ownName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        group.ownBarcode,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'سعر ${group.ownUnitPrice.toStringAsFixed(2)} · مبيعات ${group.ownUnits}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isOwner)
                  FilledButton.tonalIcon(
                    onPressed: groupBusy ? null : () => _approveAll(group),
                    style: FilledButton.styleFrom(
                      foregroundColor: M3Palette.success,
                      backgroundColor: M3Palette.successSurface,
                    ),
                    icon: groupBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('موافقة على الكل'),
                  ),
              ],
            ),
            M3Spacing.gapMD,
            for (final s in group.suggestions) ...[
              _buildCompetitorRow(s, groupBusy: groupBusy),
              M3Spacing.gapSM,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompetitorRow(
    CompetitorSuggestionModel s, {
    required bool groupBusy,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final busy = groupBusy || _busyId == s.id;
    final name = s.competitorSkuName.isEmpty
        ? s.competitorBarcode
        : s.competitorSkuName;

    return Container(
      key: ValueKey('suggestion-${s.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: M3Shape.radiusMd,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المنافس المقترح',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (s.competitorBrand.isNotEmpty)
                      Text(
                        s.competitorBrand,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      s.competitorBarcode,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'سعر ${s.competitorUnitPrice.toStringAsFixed(2)} · مبيعات ${s.competitorUnits}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsetsDirectional.only(start: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          M3Spacing.gapXS,
          Text(s.reasonAr, style: theme.textTheme.bodyMedium),
          M3Spacing.gapXXS,
          Text(
            'الثقة: ${(s.confidence * 100).toStringAsFixed(0)}% · الترتيب: ${s.rank}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (widget.isOwner) ...[
            M3Spacing.gapSM,
            // M3 connected action group: tonal approve + outlined reject on light surface.
            // Adeco green is accent only (selected/tonal), never a solid dark fill.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: M3Shape.radiusXl,
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.tonal(
                        onPressed: busy ? null : () => _approve(s),
                        style: FilledButton.styleFrom(
                          foregroundColor: M3Palette.success,
                          backgroundColor: M3Palette.successSurface,
                        ),
                        child: const Text('موافقة'),
                      ),
                      M3Spacing.gapXS,
                      OutlinedButton(
                        onPressed: busy ? null : () => _reject(s),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.onSurfaceVariant,
                          side: BorderSide(color: cs.outlineVariant),
                        ),
                        child: const Text('رفض'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

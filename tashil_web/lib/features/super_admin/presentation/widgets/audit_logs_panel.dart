import 'package:tashil_web/core/widgets/m3_search_field.dart';
import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_states.dart';
import '../../../../core/theme/m3_shape.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_segmented_button_group.dart';

class AuditLogsPanel extends StatefulWidget {
  final ApiClient apiClient;
  final String title;
  final String subtitle;

  const AuditLogsPanel({
    super.key,
    required this.apiClient,
    this.title = 'Enterprise Security Audit Logs',
    this.subtitle =
        'سجل التدقيق الأمني الشامل — تسجيل غير قابل للتعديل لعمليات الدخول ورفع الملفات والتصدير',
  });

  static Future<void> showAuditLogsDialog(
    BuildContext context,
    ApiClient apiClient,
  ) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 780),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: AuditLogsPanel(apiClient: apiClient),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: M3ActionButtonGroup(
                    compact: true,
                    actions: [
                      M3ActionItem(
                        label: 'Close',
                        icon: Icons.close_rounded,
                        isPrimary: true,
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
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

  @override
  State<AuditLogsPanel> createState() => _AuditLogsPanelState();
}

class _AuditLogsPanelState extends State<AuditLogsPanel> {
  static const int _pageSize = 25;

  List<AuditLogEntryModel> _logs = [];
  bool _isLoading = true;
  String _selectedActionFilter = 'all';
  String _searchQuery = '';
  int _currentPage = 1;
  final TextEditingController _searchCtrl = TextEditingController();

  static const List<(String, String)> _filterOptions = [
    ('all', 'All Events'),
    ('AUTH_LOGIN', 'Logins'),
    ('INGEST_UPLOAD', 'Uploads'),
    ('EXPORT', 'Exports'),
    ('TENANT', 'Companies'),
    ('CHAIN', 'Chains'),
  ];

  @override
  void initState() {
    super.initState();
    _loadAuditLogs();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAuditLogs() async {
    setState(() => _isLoading = true);
    try {
      final list = await widget.apiClient.getAuditLogs(
        actionFilter: _selectedActionFilter,
      );
      if (!mounted) return;
      setState(() {
        _logs = list;
        _currentPage = 1;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<AuditLogEntryModel> get _filteredLogs {
    if (_searchQuery.trim().isEmpty) return _logs;
    final q = _searchQuery.trim().toLowerCase();
    return _logs.where((entry) {
      return entry.details.toLowerCase().contains(q) ||
          entry.actorEmail.toLowerCase().contains(q) ||
          entry.tenantId.toLowerCase().contains(q) ||
          entry.action.toLowerCase().contains(q) ||
          entry.resource.toLowerCase().contains(q) ||
          entry.ipAddress.toLowerCase().contains(q);
    }).toList();
  }

  int get _totalPages {
    final total = _filteredLogs.length;
    if (total == 0) return 1;
    return (total / _pageSize).ceil();
  }

  List<AuditLogEntryModel> get _currentPageLogs {
    final all = _filteredLogs;
    if (all.isEmpty) return const [];
    final safePage = _currentPage.clamp(1, _totalPages);
    final start = (safePage - 1) * _pageSize;
    if (start >= all.length) return const [];
    final end = (start + _pageSize).clamp(0, all.length);
    return all.sublist(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final filtered = _filteredLogs;
    final pageLogs = _currentPageLogs;
    final totalPages = _totalPages;
    final safePage = _currentPage.clamp(1, totalPages);
    final startRecord = filtered.isEmpty ? 0 : ((safePage - 1) * _pageSize) + 1;
    final endRecord = filtered.isEmpty
        ? 0
        : (startRecord + pageLogs.length - 1).clamp(0, filtered.length);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified M3 Header: Left English Title + Right Arabic Subtitle + Action Group
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: M3Shape.radiusSm,
                          ),
                          child: Icon(
                            Icons.policy_rounded,
                            color: cs.onPrimaryContainer,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          widget.title,
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.subtitle,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withValues(alpha: 0.7),
                      borderRadius: M3Shape.radiusSm,
                    ),
                    child: Text(
                      '${filtered.length} Records • 25 / Page',
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  M3ActionButtonGroup(
                    compact: true,
                    actions: [
                      M3ActionItem(
                        label: 'Refresh',
                        icon: Icons.refresh_rounded,
                        onPressed: _isLoading ? null : _loadAuditLogs,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Filter Chips & Search Bar Row
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              M3SegmentedButtonGroup<String>(
                selectedValue: _selectedActionFilter,
                onSelectionChanged: (val) {
                  setState(() {
                    _selectedActionFilter = val;
                    _currentPage = 1;
                  });
                  _loadAuditLogs();
                },
                segments: _filterOptions
                    .map(
                      (opt) => M3SegmentItem<String>(
                        value: opt.$1,
                        label: opt.$2,
                      ),
                    )
                    .toList(),
              ),
              M3SearchFieldWidth(
                hintText: 'بحث في السجل (مستخدم، شركة، IP)...',
                width: 280,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                      _currentPage = 1;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'بحث في السجل (مستخدم، شركة، IP)...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {
                                _searchQuery = '';
                                _currentPage = 1;
                              });
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: cs.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: M3Shape.radiusSm,
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_isLoading)
            const M3LoadingState(message: 'جاري تحميل سجلات التدقيق...')
          else if (filtered.isEmpty)
            const M3EmptyState(
              icon: AppIcons.empty,
              title: 'لا توجد سجلات تدقيق مطابقة للفلتر المحدد',
            )
          else ...[
            LayoutBuilder(
              builder: (context, auditConstraints) {
                final isCompactAudit = auditConstraints.maxWidth < 720.0;
                if (isCompactAudit) {
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: pageLogs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final globalIndex = startRecord + index;
                      return _buildMobileAuditCard(
                        pageLogs[index],
                        globalIndex,
                        cs,
                        tt,
                      );
                    },
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Structured M3 Audit Table Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text(
                              '#',
                              style: tt.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'نوع العملية / الحالة',
                              style: tt.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Text(
                              'التفاصيل والمورد (Resource)',
                              style: tt.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              'المستخدم والشركة',
                              style: tt.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'التوقيت / IP',
                              textAlign: TextAlign.end,
                              style: tt.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 25-Row Paginated Table Body
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.6),
                          ),
                          right: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.6),
                          ),
                          bottom: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(12),
                        ),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: pageLogs.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.4),
                        ),
                        itemBuilder: (context, index) {
                          final globalIndex = startRecord + index;
                          return _buildAuditTableRow(
                            pageLogs[index],
                            globalIndex,
                            cs,
                            tt,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // M3 Pagination Footer Bar (25 per page)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: M3Shape.radiusMd,
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.table_rows_rounded,
                        size: 16,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'عرض السجلات $startRecord إلى $endRecord من إجمالي ${filtered.length} سجل (صفحة $safePage من $totalPages)',
                        style: tt.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        M3ActionButtonGroup(
                          compact: true,
                          actions: [
                            M3ActionItem(
                              label: 'Prev',
                              icon: Icons.chevron_left_rounded,
                              onPressed: safePage > 1
                                  ? () => setState(() => _currentPage = safePage - 1)
                                  : null,
                            ),
                            for (int p = 1; p <= totalPages; p++)
                              M3ActionItem(
                                label: 'Page $p',
                                isPrimary: p == safePage,
                                onPressed: () =>
                                    setState(() => _currentPage = p),
                              ),
                            M3ActionItem(
                              label: 'Next',
                              icon: Icons.chevron_right_rounded,
                              onPressed: safePage < totalPages
                                  ? () => setState(() => _currentPage = safePage + 1)
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileAuditCard(
    AuditLogEntryModel entry,
    int rowNumber,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final badge = _resolveActionBadge(entry.action, cs);
    final isSuccess = entry.status.toUpperCase() == 'SUCCESS';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: M3Shape.radiusMd,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: M3Shape.radiusSm,
                ),
                child: Text(
                  '#$rowNumber',
                  style: tt.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badge.$3,
                  borderRadius: M3Shape.radiusSm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badge.$2, size: 13, color: badge.$4),
                    const SizedBox(width: 4),
                    Text(
                      badge.$1,
                      style: tt.labelSmall?.copyWith(
                        color: badge.$4,
                        fontWeight: FontWeight.w800,
                        fontSize: M3FontSize.tinyPlus,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isSuccess ? cs.secondaryContainer : cs.errorContainer,
                  borderRadius: M3Shape.radiusSm,
                ),
                child: Text(
                  entry.status.toUpperCase(),
                  style: tt.labelSmall?.copyWith(
                    fontSize: M3FontSize.microPlus,
                    fontWeight: FontWeight.w800,
                    color: isSuccess
                        ? cs.onSecondaryContainer
                        : cs.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            entry.details,
            style: tt.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: M3Shape.radiusXs,
                ),
                child: Text(
                  entry.resource,
                  style: tt.labelSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: M3FontSize.tiny,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildMetaChip(
                cs,
                tt,
                Icons.person_outline_rounded,
                entry.actorEmail,
              ),
              _buildMetaChip(
                cs,
                tt,
                Icons.domain_rounded,
                entry.tenantId.toUpperCase(),
              ),
              _buildMetaChip(
                cs,
                tt,
                Icons.badge_rounded,
                TenantUserModel.mapRoleToEnglish(entry.actorRole),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  entry.timestamp,
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    fontSize: M3FontSize.tinyPlus,
                  ),
                ),
                Text(
                  'IP: ${entry.ipAddress}',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: M3FontSize.tiny,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditTableRow(
    AuditLogEntryModel entry,
    int rowNumber,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final badge = _resolveActionBadge(entry.action, cs);
    final isSuccess = entry.status.toUpperCase() == 'SUCCESS';

    return Container(
      color: rowNumber.isEven
          ? cs.surfaceContainerLowest
          : cs.surfaceContainerLow.withValues(alpha: 0.45),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // # Row Number
          SizedBox(
            width: 48,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: M3Shape.radiusSm,
              ),
              child: Text(
                '#$rowNumber',
                textAlign: TextAlign.center,
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),

          // Action Type & Status Chips
          Expanded(
            flex: 2,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badge.$3,
                    borderRadius: M3Shape.radiusSm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badge.$2, size: 13, color: badge.$4),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          badge.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelSmall?.copyWith(
                            color: badge.$4,
                            fontWeight: FontWeight.w800,
                            fontSize: M3FontSize.tinyPlus,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isSuccess
                        ? cs.secondaryContainer
                        : cs.errorContainer,
                    borderRadius: M3Shape.radiusSm,
                  ),
                  child: Text(
                    entry.status.toUpperCase(),
                    style: tt.labelSmall?.copyWith(
                      fontSize: M3FontSize.microPlus,
                      fontWeight: FontWeight.w800,
                      color: isSuccess
                          ? cs.onSecondaryContainer
                          : cs.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Details & Resource
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.details,
                    style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: M3Shape.radiusXs,
                      ),
                      child: Text(
                        entry.resource,
                        style: tt.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: M3FontSize.tiny,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // User & Tenant Chips
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _buildMetaChip(
                  cs,
                  tt,
                  Icons.person_outline_rounded,
                  entry.actorEmail,
                ),
                _buildMetaChip(
                  cs,
                  tt,
                  Icons.domain_rounded,
                  entry.tenantId.toUpperCase(),
                ),
                _buildMetaChip(
                  cs,
                  tt,
                  Icons.badge_rounded,
                  TenantUserModel.mapRoleToEnglish(entry.actorRole),
                ),
              ],
            ),
          ),

          // Timestamp & IP
          Expanded(
            flex: 2,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    entry.timestamp,
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: M3FontSize.labelSmall,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'IP: ${entry.ipAddress}',
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: M3FontSize.tiny,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip(
    ColorScheme cs,
    TextTheme tt,
    IconData icon,
    String text,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.7),
        borderRadius: M3Shape.radiusSm,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: M3FontSize.tinyPlus,
              ),
            ),
          ),
        ],
      ),
    );
  }

  (String, IconData, Color, Color) _resolveActionBadge(
    String action,
    ColorScheme cs,
  ) {
    final upper = action.toUpperCase();
    if (upper.contains('LOGIN')) {
      return (
        'AUTH LOGIN',
        Icons.login_rounded,
        cs.primaryContainer,
        cs.onPrimaryContainer,
      );
    }
    if (upper.contains('UPLOAD') || upper.contains('INGEST')) {
      return (
        'FILE UPLOAD',
        Icons.cloud_upload_rounded,
        cs.secondaryContainer,
        cs.onSecondaryContainer,
      );
    }
    if (upper.contains('EXPORT')) {
      return (
        'DATA EXPORT',
        Icons.download_rounded,
        cs.tertiaryContainer,
        cs.onTertiaryContainer,
      );
    }
    if (upper.contains('DELETE')) {
      return (
        'DELETE',
        Icons.delete_outline_rounded,
        cs.errorContainer,
        cs.onErrorContainer,
      );
    }
    if (upper.contains('PROVISION') || upper.contains('CREATE')) {
      return (
        'PROVISION',
        Icons.domain_add_rounded,
        cs.tertiaryContainer,
        cs.onTertiaryContainer,
      );
    }
    return (
      action,
      Icons.security_rounded,
      cs.secondaryContainer,
      cs.onSecondaryContainer,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../../../../core/widgets/m3_states.dart';
import '../../../../core/theme/m3_shape.dart';
import 'package:flutter/services.dart';
import '../../../../core/layout/m3_content_boundary.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_color_roles.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/web_file_helper.dart';
import '../../../../core/widgets/data_sharing_logo.dart';
import '../../../../core/widgets/m3_button.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../widgets/audit_logs_panel.dart';
import '../widgets/system_version_card.dart';

/// SuperAdminScreen provides enterprise multi-tenant provisioning, full CRUD
/// management for companies and retail chains, and 25-row paginated audit logs.
class SuperAdminScreen extends StatefulWidget {
  final ApiClient apiClient;
  final ValueChanged<String>? onSwitchToPortal;
  final VoidCallback? onLogout;

  const SuperAdminScreen({
    super.key,
    required this.apiClient,
    this.onSwitchToPortal,
    this.onLogout,
  });

  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends State<SuperAdminScreen> {
  List<TenantProfileModel> _tenants = [];
  bool _isLoading = true;
  String _tenantSearchQuery = '';
  final TextEditingController _tenantSearchCtrl = TextEditingController();
  final GlobalKey _auditSectionKey = GlobalKey();

  void _scrollToKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _tenantSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _loadTenants();
  }

  Future<void> _loadTenants() async {
    setState(() => _isLoading = true);
    final list = await widget.apiClient.getAdminTenants();
    if (mounted) {
      setState(() {
        _tenants = list;
        _isLoading = false;
      });
    }
  }

  List<TenantProfileModel> get _filteredTenants {
    if (_tenantSearchQuery.trim().isEmpty) return _tenants;
    final q = _tenantSearchQuery.trim().toLowerCase();
    return _tenants.where((t) {
      return t.displayName.toLowerCase().contains(q) ||
          t.slug.toLowerCase().contains(q) ||
          t.adminEmail.toLowerCase().contains(q) ||
          t.activeChains.any((c) => c.toLowerCase().contains(q));
    }).toList();
  }

  void _openProvisionWizard() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TenantProvisionWizardDialog(
        apiClient: widget.apiClient,
        onTenantCreated: (newTenant) {
          _loadTenants();
          M3Feedback.showSuccess(
            context,
            'تم تسجيل شركة ${newTenant.displayName} وتجهيز البوابة بنجاح',
          );
        },
      ),
    );
  }

  void _openEditTenantDialog(TenantProfileModel tenant) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EditTenantDialog(
        apiClient: widget.apiClient,
        tenant: tenant,
        onTenantUpdated: (updated) {
          _loadTenants();
          M3Feedback.showSuccess(
            context,
            'تم تحديث بيانات شركة "${updated.displayName}" بنجاح',
          );
        },
      ),
    );
  }

  void _confirmDeleteTenant(TenantProfileModel tenant) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusLg),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
            const SizedBox(width: 8.0),
            const Text('تأكيد حذف الشركة وإيقاف البوابة'),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف شركة "${tenant.displayName}" (${tenant.slug}) نهائياً؟\n\n'
          'سيتم إيقاف رابط البوابة المخصص (${ApiClient.buildPortalUrl(tenant.slug)}) وإلغاء صلاحيات الدخول المرتبطة بها.',
        ),
        actions: [
          M3ActionButtonGroup(
            actions: [
              M3ActionItem(
                label: 'Cancel',
                icon: Icons.close_rounded,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
              M3ActionItem(
                label: 'Delete',
                icon: Icons.delete_forever_rounded,
                isPrimary: true,
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  setState(() {
                    _tenants = _tenants
                        .where((t) =>
                            t.slug.toLowerCase() != tenant.slug.toLowerCase())
                        .toList();
                  });
                  try {
                    await widget.apiClient.deleteTenant(tenant.slug);
                    await _loadTenants();
                    if (mounted) {
                      M3Feedback.showSuccess(
                        context,
                        'تم حذف شركة "${tenant.displayName}" وإيقاف بوابتها بنجاح',
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      _loadTenants();
                      M3Feedback.showError(context, 'فشل حذف الشركة: $e');
                    }
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openResetPasswordModal(TenantProfileModel tenant) {
    showDialog(
      context: context,
      builder: (ctx) => _AdminResetPasswordModal(
        apiClient: widget.apiClient,
        tenant: tenant,
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    M3Feedback.showSuccess(context, 'تم نسخ $label إلى الحافظة');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: M3ContentBoundary(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Unified M3 Page Header (Left English Bold Title + Right Arabic Subtitle + Connected Action Group)
              M3PageHeader(
                leading: const DataSharingLogo(size: 40, showSquircle: true),
                titleEn: 'Super Admin Executive Portal',
                subtitleAr:
                    'لوحة التحكم المركزية لإدارة بوابات الشركات المستقلة ومعايير الأمان وتدقيق العمليات',
                actions: M3ActionButtonGroup(
                  actions: [
                    M3ActionItem(
                      label: 'New Company',
                      icon: Icons.add_business_rounded,
                      isPrimary: true,
                      onPressed: _openProvisionWizard,
                    ),
                    M3ActionItem(
                      label: 'Refresh',
                      icon: Icons.refresh_rounded,
                      onPressed: _loadData,
                    ),
                    if (widget.onLogout != null)
                      M3ActionItem(
                        label: 'Sign Out',
                        icon: Icons.logout_rounded,
                        onPressed: widget.onLogout,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SystemVersionCard(),
              const SizedBox(height: 20),

              // 1. Metric / Security Summary Hero Cards
              _buildStatsRow(cs, theme),
              const SizedBox(height: 24),

              // 2. Registered Companies (Tenants) Management Card
              _buildTenantsSectionCard(cs, theme),
              const SizedBox(height: 24),

              // 3. Paginated (25/Page) Enterprise Security Audit Logs Panel
              Container(
                key: _auditSectionKey,
                child: AuditLogsPanel(apiClient: widget.apiClient),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(
    ColorScheme cs,
    ThemeData theme,
  ) {
    final totalCompanyChains = _tenants.fold<int>(
      0,
      (sum, t) => sum + t.activeChains.length,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final cards = [
          _buildMetricTile(
            cs: cs,
            theme: theme,
            titleEn: 'REGISTERED COMPANIES',
            titleAr: 'إجمالي الشركات المفعلة',
            value: '${_tenants.length}',
            chipText: 'RLS Isolated Portals',
            icon: Icons.domain_rounded,
            accentColor: cs.primary,
          ),
          _buildMetricTile(
            cs: cs,
            theme: theme,
            titleEn: 'PER-COMPANY CHAINS',
            titleAr: 'سلاسل خاصة بكل شركة (تُدار من صفحة الرفع)',
            value: '$totalCompanyChains',
            chipText: 'Tenant Self-Managed',
            icon: Icons.storefront_rounded,
            accentColor: cs.tertiary,
          ),
          _buildMetricTile(
            cs: cs,
            theme: theme,
            titleEn: 'ZERO-TRUST SECURITY',
            titleAr: 'تشفير الهوية وعزل البيانات',
            value: 'SHA-256 + Bcrypt',
            chipText: '100% Zero Plaintext',
            icon: Icons.verified_user_rounded,
            accentColor: Colors.green.shade700,
          ),
          _buildMetricTile(
            cs: cs,
            theme: theme,
            titleEn: 'SECURITY AUDIT LOGS',
            titleAr: 'سجل التدقيق الأمني المقسم',
            value: '25 / Page',
            chipText: 'View Audit Table',
            icon: Icons.policy_rounded,
            accentColor: cs.secondary,
            onTap: () => _scrollToKey(_auditSectionKey),
          ),
        ];

        if (isWide) {
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: 16),
              ],
            ],
          );
        }

        final isPhone = constraints.maxWidth < 460;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (c) => SizedBox(
                  width: isPhone
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 12) / 2,
                  child: c,
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildMetricTile({
    required ColorScheme cs,
    required ThemeData theme,
    required String titleEn,
    required String titleAr,
    required String value,
    required String chipText,
    required IconData icon,
    required Color accentColor,
    VoidCallback? onTap,
  }) {
    final tt = theme.textTheme;
    final content = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: M3Shape.radiusMd,
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: M3Shape.radiusSm,
                  ),
                  child: Text(
                    chipText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontSize: M3FontSize.tiny,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              titleEn,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: tt.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            titleAr,
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      borderRadius: M3Shape.radiusLg,
      onTap: onTap,
      child: content,
    );
  }

  Widget _buildTenantsSectionCard(
    ColorScheme cs,
    ThemeData theme,
  ) {
    final tt = theme.textTheme;
    final filtered = _filteredTenants;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section Header (Left English Title + Right Arabic Subtitle + Search + Action Group)
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
                            Icons.business_rounded,
                            color: cs.onPrimaryContainer,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Registered Companies & Portals',
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
                    'إدارة الشركات المسجلة — كل شركة تدير سلاسل التجزئة الخاصة بها بشكل مستقل من داخل صفحة الرفع (Upload)',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 250,
                    child: TextField(
                      controller: _tenantSearchCtrl,
                      onChanged: (v) => setState(() => _tenantSearchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'بحث عن شركة أو بريد أو كود...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: _tenantSearchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                onPressed: () {
                                  _tenantSearchCtrl.clear();
                                  setState(() => _tenantSearchQuery = '');
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
                  M3ActionButtonGroup(
                    compact: true,
                    actions: [
                      M3ActionItem(
                        label: 'New Company',
                        icon: Icons.add_business_rounded,
                        isPrimary: true,
                        onPressed: _openProvisionWizard,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_isLoading)
            const M3LoadingState(message: 'جاري تحميل الشركات...')
          else if (filtered.isEmpty)
            _buildEmptyState(cs, theme)
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildTenantCardItem(filtered[index], cs, theme);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTenantCardItem(
    TenantProfileModel tenant,
    ColorScheme cs,
    ThemeData theme,
  ) {
    final tt = theme.textTheme;
    final brandColor =
        TenantBrandSeeds.parseHexColor(tenant.brandSeedColor) ?? cs.primary;
    final effectiveUrl = ApiClient.buildPortalUrl(tenant.slug);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: M3Shape.radiusMd,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 14,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Identity & Metadata Chips
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: brandColor,
                      borderRadius: M3Shape.radiusMd,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tenant.displayName.isNotEmpty
                          ? tenant.displayName[0]
                          : 'T',
                      style: tt.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              tenant.displayName,
                              style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                            ),
                            _buildChip(
                              cs: cs,
                              tt: tt,
                              icon: Icons.tag_rounded,
                              label: tenant.slug.toUpperCase(),
                              bgColor: brandColor.withValues(alpha: 0.14),
                              fgColor: brandColor,
                            ),
                            _buildChip(
                              cs: cs,
                              tt: tt,
                              icon: Icons.palette_rounded,
                              label: tenant.brandSeedColor.toUpperCase(),
                              bgColor: cs.surfaceContainerHighest,
                              fgColor: cs.onSurfaceVariant,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildChip(
                              cs: cs,
                              tt: tt,
                              icon: Icons.alternate_email_rounded,
                              label: tenant.adminEmail.isNotEmpty
                                  ? tenant.adminEmail
                                  : 'admin@${tenant.slug}-retail.com',
                              bgColor: cs.surfaceContainerLowest,
                              fgColor: cs.onSurface,
                            ),
                            if (tenant.activeChains.isEmpty)
                              _buildChip(
                                cs: cs,
                                tt: tt,
                                icon: Icons.storefront_rounded,
                                label: 'إدخال السلاسل من بوابة الشركة',
                                bgColor: cs.secondaryContainer
                                    .withValues(alpha: 0.5),
                                fgColor: cs.onSecondaryContainer,
                              )
                            else
                              for (final chain in tenant.activeChains)
                                _buildChip(
                                  cs: cs,
                                  tt: tt,
                                  icon: Icons.storefront_rounded,
                                  label: ApiClient.getRetailChainShortAr(chain),
                                  bgColor: cs.secondaryContainer
                                      .withValues(alpha: 0.65),
                                  fgColor: cs.onSecondaryContainer,
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Full CRUD Connected M3 Action Button Group (Edit, Reset Pass, Delete, Copy URL, Open Portal)
              Directionality(
                textDirection: TextDirection.ltr,
                child: M3ActionButtonGroup(
                  compact: true,
                  actions: [
                    M3ActionItem(
                      label: 'Open Portal',
                      icon: Icons.open_in_new_rounded,
                      isPrimary: true,
                      onPressed: () {
                        if (widget.onSwitchToPortal != null) {
                          widget.onSwitchToPortal!(tenant.slug);
                        } else {
                          WebFileHelper.openUrlInNewTab(effectiveUrl);
                        }
                      },
                    ),
                    M3ActionItem(
                      label: 'Copy URL',
                      icon: Icons.copy_rounded,
                      onPressed: () => _copyToClipboard(
                        effectiveUrl,
                        'رابط بوابة ${tenant.displayName}',
                      ),
                    ),
                    M3ActionItem(
                      label: 'Edit',
                      icon: Icons.edit_rounded,
                      onPressed: () => _openEditTenantDialog(tenant),
                    ),
                    M3ActionItem(
                      label: 'Reset Key',
                      icon: Icons.lock_reset_rounded,
                      onPressed: () => _openResetPasswordModal(tenant),
                    ),
                    M3ActionItem(
                      label: 'Delete',
                      icon: Icons.delete_outline_rounded,
                      onPressed: () => _confirmDeleteTenant(tenant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Dedicated Portal URL Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: M3Shape.radiusSm,
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  Icon(Icons.link_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Dedicated Portal URL:',
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      effectiveUrl,
                      style: tt.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Open in New Tab',
                    onPressed: () => WebFileHelper.openUrlInNewTab(effectiveUrl),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs, ThemeData theme) {
    return M3EmptyState(
      icon: Icons.business_rounded,
      title: 'لا توجد شركات مطابقة للبحث الحالي',
      action: M3ActionButtonGroup(
        actions: [
          M3ActionItem(
            label: 'New Company',
            icon: Icons.add_business_rounded,
            isPrimary: true,
            onPressed: _openProvisionWizard,
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required ColorScheme cs,
    required TextTheme tt,
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color fgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: M3Shape.radiusSm,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fgColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: fgColor,
              fontWeight: FontWeight.w700,
              fontSize: M3FontSize.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// _EditTenantDialog allows Super Admin to edit an existing company's display name,
/// admin email, and brand seed color. Retail chains are managed by the company itself.
class _EditTenantDialog extends StatefulWidget {
  final ApiClient apiClient;
  final TenantProfileModel tenant;
  final ValueChanged<TenantProfileModel> onTenantUpdated;

  const _EditTenantDialog({
    required this.apiClient,
    required this.tenant,
    required this.onTenantUpdated,
  });

  @override
  State<_EditTenantDialog> createState() => _EditTenantDialogState();
}

class _EditTenantDialogState extends State<_EditTenantDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late String _selectedHex;
  bool _isSubmitting = false;

  static const List<Map<String, String>> _presetColors = [
    {'name': 'Adeco Navy', 'hex': '#1E3A8A'},
    {'name': 'Unilever Teal', 'hex': '#0D9488'},
    {'name': 'Pepsi Crimson', 'hex': '#B91C1C'},
    {'name': 'Juhayna Emerald', 'hex': '#059669'},
    {'name': 'Royal Indigo', 'hex': '#4338CA'},
    {'name': 'Warm Amber', 'hex': '#D97706'},
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.tenant.displayName);
    _emailController = TextEditingController(text: widget.tenant.adminEmail);
    _selectedHex = widget.tenant.brandSeedColor.isNotEmpty
        ? widget.tenant.brandSeedColor
        : '#1E3A8A';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final updated = await widget.apiClient.updateTenant(
        slug: widget.tenant.slug,
        displayName: _nameController.text.trim(),
        brandSeedColor: _selectedHex,
        adminEmail: _emailController.text.trim().toLowerCase(),
        activeChains: widget.tenant.activeChains,
      );
      if (mounted) {
        widget.onTenantUpdated(updated);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        M3Feedback.showError(context, 'فشل تعديل بيانات الشركة: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currentSeed =
        TenantBrandSeeds.parseHexColor(_selectedHex) ?? cs.primary;

    return Dialog(
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusXl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580.0),
        child: Padding(
          padding: M3Spacing.pLg,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10.0),
                        decoration: BoxDecoration(
                          color: currentSeed.withValues(alpha: 0.14),
                          borderRadius: M3Shape.radiusMd,
                        ),
                        child: Icon(
                          Icons.edit_note_rounded,
                          color: currentSeed,
                          size: 24.0,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تعديل بيانات الشركة (${widget.tenant.slug})',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'تحديث اسم الشركة والبريد الإداري والهوية اللونية',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المؤسسة / الشركة *',
                      prefixIcon: Icon(Icons.business_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'اسم الشركة مطلوب'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    initialValue: widget.tenant.slug,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'معرف الرابط الفريد (Slug - ثابت)',
                      prefixIcon: Icon(Icons.tag_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني لمسؤول الشركة *',
                      prefixIcon: Icon(Icons.email_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'يرجى إدخال بريد إلكتروني صالح'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'لون الهوية البصرية (M3 Brand Seed):',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: _presetColors.map((p) {
                      final c = TenantBrandSeeds.parseHexColor(p['hex']!)!;
                      final isSelected =
                          _selectedHex.toUpperCase() == p['hex']!.toUpperCase();
                      return ChoiceChip(
                        label: Text(p['name']!),
                        selected: isSelected,
                        avatar: CircleAvatar(backgroundColor: c, radius: 8.0),
                        onSelected: (val) {
                          if (val) setState(() => _selectedHex = p['hex']!);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withValues(alpha: 0.35),
                      borderRadius: M3Shape.radiusSm,
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.storefront_rounded,
                          size: 18.0,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            'تتم إدارة وإدخال سلاسل التجزئة بشكل مستقل من قِبل الشركة نفسها داخل صفحة الرفع (Upload).',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: M3ActionButtonGroup(
                        actions: [
                          M3ActionItem(
                            label: _isSubmitting ? 'Saving...' : 'Save Changes',
                            icon: Icons.check_rounded,
                            isPrimary: true,
                            onPressed: _isSubmitting ? null : _submit,
                          ),
                          M3ActionItem(
                            label: 'Cancel',
                            icon: Icons.close_rounded,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// TenantProvisionWizardDialog implements the company onboarding generator wizard.
class _TenantProvisionWizardDialog extends StatefulWidget {
  final ApiClient apiClient;
  final ValueChanged<TenantProfileModel> onTenantCreated;

  const _TenantProvisionWizardDialog({
    required this.apiClient,
    required this.onTenantCreated,
  });

  @override
  State<_TenantProvisionWizardDialog> createState() =>
      _TenantProvisionWizardDialogState();
}

class _TenantProvisionWizardDialogState
    extends State<_TenantProvisionWizardDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedHex = '#1E3A8A';
  bool _isSubmitting = false;
  ProvisionTenantResultModel? _createdResult;

  final List<Map<String, String>> _presetColors = [
    {'name': 'Adeco Navy', 'hex': '#1E3A8A'},
    {'name': 'Unilever Teal', 'hex': '#0D9488'},
    {'name': 'Pepsi Crimson', 'hex': '#B91C1C'},
    {'name': 'Juhayna Emerald', 'hex': '#059669'},
    {'name': 'Royal Indigo', 'hex': '#4338CA'},
    {'name': 'Warm Amber', 'hex': '#D97706'},
  ];

  @override
  void initState() {
    super.initState();
    _passwordController.text =
        'Tsh!${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}Pass#';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onNameChanged(String val) {
    if (_createdResult != null) return;
    String transliterated =
        val.trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), '-');
    transliterated = transliterated
        .replaceAll('شركة', '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (transliterated.isNotEmpty) {
      _slugController.text = transliterated;
    }
    setState(() {});
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final res = await widget.apiClient.provisionTenant(
        displayName: _nameController.text.trim(),
        slug: _slugController.text.trim().toLowerCase(),
        brandSeedColor: _selectedHex,
        adminEmail: _emailController.text.trim().toLowerCase(),
        adminPassword: _passwordController.text.trim(),
        activeChains: const [],
      );

      if (mounted) {
        setState(() {
          _createdResult = res;
          _isSubmitting = false;
        });
        widget.onTenantCreated(res.tenant);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        M3Feedback.showError(context, 'فشل إنشاء الشركة: $e');
      }
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    M3Feedback.showSuccess(context, 'تم نسخ $label');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentSeed =
        TenantBrandSeeds.parseHexColor(_selectedHex) ?? colorScheme.primary;

    final size = MediaQuery.sizeOf(context);
    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusXl),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600.0,
          maxHeight: size.height * 0.88,
        ),
        child: Padding(
          padding: M3Spacing.pLg,
          child: SingleChildScrollView(
            child: _createdResult != null
                ? _buildSuccessSummaryCard(theme, colorScheme, currentSeed)
                : _buildWizardForm(theme, colorScheme, currentSeed),
          ),
        ),
      ),
    );
  }

  Widget _buildWizardForm(
    ThemeData theme,
    ColorScheme colorScheme,
    Color currentSeed,
  ) {
    final cleanSlug = _slugController.text.trim().toLowerCase();
    final previewUrl =
        ApiClient.buildPortalUrl(cleanSlug.isNotEmpty ? cleanSlug : 'company');

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: currentSeed.withValues(alpha: 0.12),
                  borderRadius: M3Shape.radiusMd,
                ),
                child: Icon(
                  Icons.domain_add_rounded,
                  color: currentSeed,
                  size: 24.0,
                ),
              ),
              M3Spacing.gapSM,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'معالج إضافة شركة جديدة وتوليد الرابط',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'إنشاء بوابة مستقلة وحساب مسؤول مؤمن بتشفير Bcrypt',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          M3Spacing.gapMD,
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'اسم المؤسسة / الشركة *',
              hintText: 'مثال: شركة جهينة للصناعات الغذائية',
              prefixIcon: Icon(Icons.business_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: _onNameChanged,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'يرجى إدخال اسم الشركة' : null,
          ),
          M3Spacing.gapSM,
          TextFormField(
            controller: _slugController,
            decoration: const InputDecoration(
              labelText: 'معرف الرابط الفريد (Slug) *',
              hintText: 'juhayna',
              prefixIcon: Icon(Icons.alternate_email_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'يرجى إدخال المعرف' : null,
          ),
          M3Spacing.gapXS,
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: M3Shape.radiusSm,
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 16.0, color: currentSeed),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    previewUrl,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16.0),
                  tooltip: 'نسخ رابط البوابة المولد',
                  onPressed: () => _copy(previewUrl, 'رابط البوابة المولد'),
                ),
              ],
            ),
          ),
          M3Spacing.gapSM,
          Text(
            'لون الهوية والعلامة التجارية (M3 Brand Seed):',
            style: theme.textTheme.labelMedium,
          ),
          M3Spacing.gapXS,
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: _presetColors.map((p) {
              final c = TenantBrandSeeds.parseHexColor(p['hex']!)!;
              final isSelected = _selectedHex == p['hex'];
              return ChoiceChip(
                label: Text(p['name']!),
                selected: isSelected,
                avatar: CircleAvatar(backgroundColor: c, radius: 8.0),
                onSelected: (val) {
                  if (val) setState(() => _selectedHex = p['hex']!);
                },
              );
            }).toList(),
          ),
          M3Spacing.gapSM,
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.35),
              borderRadius: M3Shape.radiusSm,
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.storefront_rounded,
                  size: 18.0,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    'يقوم مسؤول الشركة بإدخال وإدارة سلاسل التجزئة الخاصة بشركته مباشرة من داخل صفحة الرفع (Upload).',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          M3Spacing.gapSM,
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'البريد الإلكتروني لمسؤول الشركة *',
              hintText: 'admin@company.com',
              prefixIcon: Icon(Icons.email_rounded),
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v == null || !v.contains('@'))
                ? 'يرجى إدخال بريد إلكتروني صالح'
                : null,
          ),
          M3Spacing.gapSM,
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: 'كلمة المرور الأولية (توليد آلي مؤمن)',
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'توليد كلمة مرور جديدة',
                onPressed: () {
                  setState(() {
                    _passwordController.text =
                        'Tsh!${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}Pass#';
                  });
                },
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          M3Spacing.gapLG,
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: M3ActionButtonGroup(
                actions: [
                  M3ActionItem(
                    label: _isSubmitting ? 'Creating...' : 'Create Portal',
                    icon: Icons.check_circle_rounded,
                    isPrimary: true,
                    onPressed: _isSubmitting ? null : _submit,
                  ),
                  M3ActionItem(
                    label: 'Cancel',
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessSummaryCard(
    ThemeData theme,
    ColorScheme colorScheme,
    Color seedColor,
  ) {
    final res = _createdResult!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: Colors.green,
              size: 40.0,
            ),
          ),
        ),
        M3Spacing.gapMD,
        Center(
          child: Text(
            'تم تجهيز بوابة ${res.tenant.displayName} بنجاح!',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Center(
          child: Text(
            'يمكنك نسخ بيانات الاعتماد أدناه وإرسالها لمسؤول الشركة فوراً',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        M3Spacing.gapMD,
        Container(
          padding: M3Spacing.pMd,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: M3Shape.radiusMd,
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              Builder(
                builder: (_) {
                  final effectivePortalUrl =
                      ApiClient.buildPortalUrl(res.tenant.slug);
                  return _buildCredentialRow(
                    label: 'رابط البوابة المخصص:',
                    value: effectivePortalUrl,
                    onCopy: () => _copy(effectivePortalUrl, 'رابط البوابة'),
                  );
                },
              ),
              const Divider(height: 16.0),
              _buildCredentialRow(
                label: 'البريد الإلكتروني:',
                value: res.adminUser.email,
                onCopy: () => _copy(res.adminUser.email, 'البريد الإلكتروني'),
              ),
              const Divider(height: 16.0),
              _buildCredentialRow(
                label: 'كلمة المرور المؤقتة:',
                value: res.temporaryPassword,
                onCopy: () => _copy(res.temporaryPassword, 'كلمة المرور'),
                isSecret: true,
              ),
            ],
          ),
        ),
        M3Spacing.gapLG,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: M3ActionButtonGroup(
            actions: [
              M3ActionItem(
                label: 'Done',
                icon: Icons.done_all_rounded,
                isPrimary: true,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCredentialRow({
    required String label,
    required String value,
    required VoidCallback onCopy,
    bool isSecret = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: M3FontSize.bodySmall, color: Colors.grey),
              ),
              SelectableText(
                value,
                style: TextStyle(
                  fontSize: M3FontSize.bodyMedium,
                  fontWeight: FontWeight.bold,
                  fontFamily: isSecret ? 'monospace' : null,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded, size: 18.0),
          tooltip: 'نسخ',
          onPressed: onCopy,
        ),
      ],
    );
  }
}

/// _AdminResetPasswordModal handles password resetting for existing companies.
class _AdminResetPasswordModal extends StatefulWidget {
  final ApiClient apiClient;
  final TenantProfileModel tenant;

  const _AdminResetPasswordModal({
    required this.apiClient,
    required this.tenant,
  });

  @override
  State<_AdminResetPasswordModal> createState() =>
      _AdminResetPasswordModalState();
}

class _AdminResetPasswordModalState extends State<_AdminResetPasswordModal> {
  String? _newPassword;
  bool _isLoading = false;

  Future<void> _performReset() async {
    setState(() => _isLoading = true);
    final pass =
        await widget.apiClient.adminResetTenantPassword(widget.tenant.tenantId);
    if (mounted) {
      setState(() {
        _newPassword = pass;
        _isLoading = false;
      });
      M3Feedback.showSuccess(context, 'تم إعادة تعيين كلمة المرور بنجاح');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusLg),
      title: Row(
        children: [
          Icon(Icons.lock_reset_rounded, color: colorScheme.error),
          M3Spacing.gapSM,
          Expanded(
            child: Text(
              'إعادة تعيين كلمة المرور: ${widget.tenant.displayName}',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 450.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'سيتم توليد كلمة مرور جديدة صالحة للاستخدام الفوري لمسؤول الحساب (${widget.tenant.adminEmail}):',
              style: theme.textTheme.bodyMedium,
            ),
            M3Spacing.gapMD,
            if (_newPassword != null) ...[
              Container(
                padding: M3Spacing.pMd,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: M3Shape.radiusSm,
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'كلمة المرور الجديدة:',
                            style: TextStyle(fontSize: M3FontSize.bodySmall),
                          ),
                          SelectableText(
                            _newPassword!,
                            style: const TextStyle(
                              fontSize: M3FontSize.bodyLarge,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _newPassword!));
                        M3Feedback.showSuccess(context, 'تم نسخ كلمة المرور');
                      },
                    ),
                  ],
                ),
              ),
              M3Spacing.gapSM,
            ],
          ],
        ),
      ),
      actions: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: M3ActionButtonGroup(
            actions: [
              if (_newPassword == null)
                M3ActionItem(
                  label: _isLoading ? 'Generating...' : 'Generate Key',
                  icon: Icons.key_rounded,
                  isPrimary: true,
                  onPressed: _isLoading ? null : _performReset,
                ),
              M3ActionItem(
                label: 'Close',
                icon: Icons.close_rounded,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

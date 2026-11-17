import 'package:flutter/material.dart';

import '../../../core/config/app_version.dart';
import '../../../core/theme/m3_shape.dart';
import '../../../core/theme/m3_spacing.dart';
import '../../../core/theme/m3_typography.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/m3_button.dart';
import 'tenant_logo_slot.dart';
import 'tenant_profile_card.dart';

/// Visual treatment for the owner review. Not used by [DesktopSidebar].
enum SidebarMockupVariant {
  /// Small grey section title above each group, thin rule between groups.
  titles,

  /// Divider plus a collapsible section header (arrow).
  collapsible,

  /// Tracked chip labels, extra space, then a divider.
  chips;

  static SidebarMockupVariant parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'b':
      case 'collapsible':
        return SidebarMockupVariant.collapsible;
      case 'c':
      case 'chips':
        return SidebarMockupVariant.chips;
      case 'a':
      case 'titles':
      default:
        return SidebarMockupVariant.titles;
    }
  }
}

/// `?variant=a-collapsed` is variant A drawn as the narrow rail.
bool sidebarMockupNarrow(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  return v == 'a-collapsed' || v == 'a_collapsed' || v == 'collapsed';
}

class _NavItem {
  final String label;
  final IconData icon;
  final int? badgeCount;

  const _NavItem(this.label, this.icon, {this.badgeCount});
}

class _NavSection {
  final String id;
  final String titleAr;
  final List<_NavItem> items;

  const _NavSection(this.id, this.titleAr, this.items);
}

/// Proposed grouping. Upload stays off the menu (route is unchanged).
const List<_NavSection> _sections = [
  _NavSection('home', 'الرئيسية', [
    _NavItem('Dashboard', Icons.dashboard_rounded),
    _NavItem('OOS Monitor', Icons.warning_amber_rounded, badgeCount: 3),
    _NavItem('Store Matrix', Icons.store_mall_directory_rounded),
  ]),
  _NavSection('entry', 'الإدخالات', [
    _NavItem('Sell-Out', Icons.analytics_rounded),
    _NavItem('Sell-In', Icons.local_shipping_rounded),
    _NavItem('Returns', Icons.assignment_return_rounded),
    _NavItem('Product Master', Icons.qr_code_2_rounded),
    _NavItem('CPFR Replenishment', Icons.inventory_2_rounded),
  ]),
  _NavSection('marketing', 'التسويق', [
    _NavItem('Pricing & Promos', Icons.price_change_rounded),
    _NavItem('Compare', Icons.compare_arrows_rounded),
    _NavItem('Trade Marketing & ROI', Icons.campaign_rounded),
  ]),
  _NavSection('system', 'النظام', [
    _NavItem('Errors', AppIcons.dataQuality),
  ]),
];

const Map<String, String> _pageTitleAr = {
  'Dashboard': 'لوحة القيادة',
  'OOS Monitor': 'مراقب النواقص',
  'Store Matrix': 'مصفوفة الفروع',
  'Sell-Out': 'المبيعات (Sell-Out)',
  'Sell-In': 'التوريد (Sell-In)',
  'Returns': 'المرتجعات',
  'Product Master': 'كارتة الأصناف',
  'CPFR Replenishment': 'التجديد وأوامر الشراء',
  'Pricing & Promos': 'التسعير والعروض',
  'Compare': 'مقارنة المنافسين',
  'Trade Marketing & ROI': 'التسويق التجاري والعائد',
  'Errors': 'الأخطاء',
};

/// Full-window review frame: RTL content, Adeco header, production footer.
class SidebarSectionMockupPage extends StatefulWidget {
  final SidebarMockupVariant variant;
  final bool narrow;

  const SidebarSectionMockupPage({
    super.key,
    required this.variant,
    this.narrow = false,
  });

  @override
  State<SidebarSectionMockupPage> createState() =>
      _SidebarSectionMockupPageState();
}

class _SidebarSectionMockupPageState extends State<SidebarSectionMockupPage> {
  String _selected = 'Dashboard';
  final Map<String, bool> _open = {
    for (final section in _sections) section.id: true,
  };

  bool get _narrow {
    if (widget.narrow) return true;
    return sidebarMockupNarrow(Uri.base.queryParameters['variant']);
  }

  void _toggle(String id) {
    setState(() => _open[id] = !(_open[id] ?? true));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sidebarWidth = _narrow ? 96.0 : 250.0;
    final variant = widget.variant;

    return Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 0,
              right: sidebarWidth,
              top: 0,
              bottom: 0,
              child: ColoredBox(
                color: colorScheme.surface,
                child: _MockupCanvas(
                  selectedLabel: _selected,
                  variant: variant,
                  narrow: _narrow,
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: sidebarWidth,
              child: _MockSidebar(
                variant: variant,
                narrow: _narrow,
                selected: _selected,
                open: _open,
                onSelect: (label) => setState(() => _selected = label),
                onToggle: _toggle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MockSidebar extends StatelessWidget {
  final SidebarMockupVariant variant;
  final bool narrow;
  final String selected;
  final Map<String, bool> open;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onToggle;

  const _MockSidebar({
    required this.variant,
    required this.narrow,
    required this.selected,
    required this.open,
    required this.onSelect,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      elevation: 1.0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      color: colorScheme.surfaceContainer,
      shape: BorderDirectional(
        end: BorderSide(color: colorScheme.outlineVariant, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (narrow)
            const _NarrowAdecoHeader()
          else
            const Padding(
              padding: EdgeInsetsDirectional.fromSTEB(16.0, 24.0, 16.0, 16.0),
              child: TenantProfileCard(
                activeTenant: 'adeco',
                logoUrl: '',
                onTenantChanged: _noopTenant,
                onOpenProfile: _noop,
              ),
            ),
          Expanded(
            child: ListView(
              padding: EdgeInsetsDirectional.fromSTEB(
                narrow ? 8.0 : 12.0,
                0.0,
                narrow ? 8.0 : 12.0,
                8.0,
              ),
              children: [
                for (var i = 0; i < _sections.length; i++) ...[
                  _SectionBlock(
                    section: _sections[i],
                    variant: variant,
                    narrow: narrow,
                    selected: selected,
                    expanded: open[_sections[i].id] ?? true,
                    showDivider: i < _sections.length - 1,
                    onSelect: onSelect,
                    onToggle: () => onToggle(_sections[i].id),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1.0),
          _ProductionFooter(narrow: narrow),
        ],
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  final _NavSection section;
  final SidebarMockupVariant variant;
  final bool narrow;
  final String selected;
  final bool expanded;
  final bool showDivider;
  final ValueChanged<String> onSelect;
  final VoidCallback onToggle;

  const _SectionBlock({
    required this.section,
    required this.variant,
    required this.narrow,
    required this.selected,
    required this.expanded,
    required this.showDivider,
    required this.onSelect,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final showItems =
        narrow || variant != SidebarMockupVariant.collapsible || expanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!narrow) _header(context),
        if (showItems)
          for (var i = 0; i < section.items.length; i++) ...[
            if (i > 0) const SizedBox(height: 2.0),
            _NavRow(
              item: section.items[i],
              selected: selected == section.items[i].label,
              narrow: narrow,
              onTap: () => onSelect(section.items[i].label),
            ),
          ],
        if (showDivider) _between(context),
      ],
    );
  }

  Widget _header(BuildContext context) {
    switch (variant) {
      case SidebarMockupVariant.titles:
        return _GreyTitle(title: section.titleAr, sectionId: section.id);
      case SidebarMockupVariant.collapsible:
        return _CollapsibleHeader(
          title: section.titleAr,
          sectionId: section.id,
          expanded: expanded,
          onToggle: onToggle,
        );
      case SidebarMockupVariant.chips:
        return _ChipTitle(title: section.titleAr, sectionId: section.id);
    }
  }

  Widget _between(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final gapTop = variant == SidebarMockupVariant.chips ? 10.0 : 6.0;
    final gapBottom = variant == SidebarMockupVariant.chips ? 8.0 : 4.0;
    return Padding(
      padding: EdgeInsets.only(top: gapTop, bottom: gapBottom),
      child: Divider(
        key: ValueKey('sidebar_section_divider_${section.id}'),
        height: 1.0,
        thickness: 1.0,
        color: colorScheme.outline.withOpacity(0.65),
      ),
    );
  }
}

class _GreyTitle extends StatelessWidget {
  final String title;
  final String sectionId;

  const _GreyTitle({required this.title, required this.sectionId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      key: ValueKey('sidebar_section_$sectionId'),
      padding: const EdgeInsetsDirectional.fromSTEB(16.0, 8.0, 16.0, 2.0),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          fontSize: M3FontSize.labelSmall,
          height: 1.2,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _CollapsibleHeader extends StatelessWidget {
  final String title;
  final String sectionId;
  final bool expanded;
  final VoidCallback onToggle;

  const _CollapsibleHeader({
    required this.title,
    required this.sectionId,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2.0),
      child: Material(
        key: ValueKey('sidebar_section_$sectionId'),
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onToggle,
          customBorder: const StadiumBorder(),
          child: Semantics(
            button: true,
            expanded: expanded,
            label: title,
            child: SizedBox(
              height: 32.0,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: M3FontSize.labelMediumPlus,
                        ),
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20.0,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipTitle extends StatelessWidget {
  final String title;
  final String sectionId;

  const _ChipTitle({required this.title, required this.sectionId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      key: ValueKey('sidebar_section_$sectionId'),
      padding: const EdgeInsetsDirectional.fromSTEB(8.0, 10.0, 8.0, 6.0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: M3Shape.radiusFull,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: M3FontSize.labelSmall,
              letterSpacing: 0.6,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final bool narrow;
  final VoidCallback onTap;

  const _NavRow({
    required this.item,
    required this.selected,
    required this.narrow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconColor = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;

    final icon = Icon(
      item.icon,
      size: narrow ? 22.0 : 22.0,
      color: iconColor,
    );

    final Widget iconSlot = item.badgeCount == null
        ? icon
        : Badge.count(count: item.badgeCount!, child: icon);

    if (narrow) {
      return Center(
        child: Material(
          key: ValueKey('sidebar_nav_${item.label}'),
          color: selected ? colorScheme.secondaryContainer : Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.none,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Semantics(
              button: true,
              selected: selected,
              label: item.label,
              child: SizedBox(
                width: 48.0,
                height: 36.0,
                child: Center(child: iconSlot),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      key: ValueKey('sidebar_nav_${item.label}'),
      color: selected ? colorScheme.secondaryContainer : Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Semantics(
          button: true,
          selected: selected,
          label: item.label,
          child: SizedBox(
            height: 36.0,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  iconSlot,
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: selected
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurface,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: M3FontSize.labelMediumPlus,
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

class _NarrowAdecoHeader extends StatelessWidget {
  const _NarrowAdecoHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8.0, 16.0, 8.0, 8.0),
      child: Column(
        children: [
          const TenantLogoSlot(
            tenantSlug: 'adeco',
            logoUrl: '',
            radius: 18.0,
          ),
          const SizedBox(height: 6.0),
          Text(
            'Adeco',
            key: const ValueKey('sidebar_tenant_name'),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Same footer copy as [DesktopSidebar]: status line, then the platform line.
class _ProductionFooter extends StatelessWidget {
  final bool narrow;

  const _ProductionFooter({required this.narrow});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        narrow ? 6.0 : 16.0,
        8.0,
        narrow ? 6.0 : 16.0,
        12.0,
      ),
      child: ValueListenableBuilder<String>(
        valueListenable: AppVersion.listenable,
        builder: (context, versionLabel, _) {
          final version = Text(
            narrow
                ? 'Tashil • Data Sharing\nPlatform • $versionLabel'
                : 'Tashil • Data Sharing Platform • $versionLabel',
            key: const ValueKey('sidebar-app-version'),
            textDirection: TextDirection.ltr,
            textAlign: narrow ? TextAlign.center : TextAlign.left,
            maxLines: narrow ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w300,
              fontSize: narrow ? M3FontSize.micro : null,
              height: narrow ? 1.3 : null,
            ),
          );
          final status = Row(
            key: const ValueKey('sidebar_footer_status'),
            mainAxisAlignment:
                narrow ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              CircleAvatar(radius: 4.0, backgroundColor: colorScheme.primary),
              const SizedBox(width: 6.0),
              Icon(Icons.bolt_rounded,
                  size: 16.0, color: colorScheme.onSurfaceVariant),
              if (!narrow) ...[
                const SizedBox(width: 6.0),
                Expanded(
                  child: Text(
                    'Smart Ingestion Active',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          );
          return Column(
            crossAxisAlignment:
                narrow ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
            children: [
              status,
              if (narrow)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    'Smart Ingestion\nActive',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: M3FontSize.micro,
                      height: 1.2,
                    ),
                  ),
                ),
              const SizedBox(height: 4.0),
              version,
            ],
          );
        },
      ),
    );
  }
}

class _MockupCanvas extends StatelessWidget {
  final String selectedLabel;
  final SidebarMockupVariant variant;
  final bool narrow;

  const _MockupCanvas({
    required this.selectedLabel,
    required this.variant,
    required this.narrow,
  });

  String get _chip {
    if (narrow) return 'المقترح أ · القائمة الضيقة';
    switch (variant) {
      case SidebarMockupVariant.titles:
        return 'المقترح أ · عنوان رمادي';
      case SidebarMockupVariant.collapsible:
        return 'المقترح ب · أقسام قابلة للطي';
      case SidebarMockupVariant.chips:
        return 'المقترح ج · شارات الأقسام';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final titleAr = _pageTitleAr[selectedLabel] ?? selectedLabel;

    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          M3PageHeader(
            title: titleAr,
            subtitle: selectedLabel,
            description:
                'معاينة ترتيب القائمة للمراجعة فقط. صفحة «رفع البيانات الذكي» مخفية من القائمة.',
            actions: Container(
              key: const ValueKey('mockup-variant-chip'),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: M3Shape.radiusFull,
              ),
              child: Text(
                _chip,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          M3Spacing.gapMD,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final slot in const [
                  'ملخص الصفحة',
                  'حركة البيانات',
                  'تنبيهات',
                ]) ...[
                  Expanded(child: _EmptySlot(title: slot)),
                  if (slot != 'تنبيهات') const SizedBox(width: 16.0),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final String title;

  const _EmptySlot({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusLg,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8.0),
            Text(
              'بدون بيانات. المساحة توضح الصفحة بجانب القائمة فقط.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _noop() {}

void _noopTenant(String _) {}

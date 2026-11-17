import 'package:flutter/material.dart';

import '../../core/theme/m3_shape.dart';
import '../../core/widgets/app_icons.dart';

/// One labeled block in the shell navigation menu.
///
/// Order matches the reviewed sidebar (variant C): الرئيسية, الإدخالات,
/// التسويق, النظام.
class AppNavSection {
  final String id;
  final String titleAr;

  const AppNavSection(this.id, this.titleAr);

  bool get labeled => titleAr.isNotEmpty;

  static const home = AppNavSection('home', 'الرئيسية');
  static const inputs = AppNavSection('inputs', 'الإدخالات');
  static const marketing = AppNavSection('marketing', 'التسويق');
  static const system = AppNavSection('system', 'النظام');
}

/// A shell page. [routeIndex] matches [AppPageRoute.pageSlugs] and the
/// screen list in `AppShell`. Menu order is independent of that index.
class AppNavItem {
  final int routeIndex;
  final AppNavSection section;

  /// English label in the wide sidebar.
  final String sidebarLabel;

  /// Longer English label in the drawer and the compact "More" sheet.
  final String labelEn;

  /// Arabic page name. Section headers carry the Arabic grouping; item
  /// rows stay English, matching the existing sidebar.
  final String labelAr;

  /// Short label on the narrow (collapsed) sidebar.
  final String shortLabel;
  final IconData icon;
  final IconData selectedIcon;

  /// False hides the page from every menu. The route and screen stay.
  final bool showInMenu;
  final int? badgeCount;

  const AppNavItem({
    required this.routeIndex,
    required this.section,
    required this.sidebarLabel,
    required this.labelEn,
    required this.labelAr,
    required this.shortLabel,
    required this.icon,
    required this.selectedIcon,
    this.showInMenu = true,
    this.badgeCount,
  });
}

/// Visible items that share a section, in menu order.
class NavMenuGroup {
  final AppNavSection section;
  final List<AppNavItem> items;

  const NavMenuGroup(this.section, this.items);
}

/// Single catalog for the wide sidebar, the narrow sidebar, the drawer,
/// and the compact "More" sheet.
class AppNavCatalog {
  AppNavCatalog._();

  /// Menu order. Hidden pages are listed too so deep links can resolve them.
  static const List<AppNavItem> items = [
    AppNavItem(
      routeIndex: 0,
      section: AppNavSection.home,
      sidebarLabel: 'Dashboard',
      labelEn: 'Executive Overview',
      labelAr: 'لوحة القيادة التنفيذية',
      shortLabel: 'Dashboard',
      icon: Icons.dashboard_rounded,
      selectedIcon: Icons.dashboard_rounded,
    ),
    AppNavItem(
      routeIndex: 4,
      section: AppNavSection.home,
      sidebarLabel: 'OOS Monitor',
      labelEn: 'OOS Monitor',
      labelAr: 'مراقب النواقص',
      shortLabel: 'OOS',
      icon: Icons.warning_amber_rounded,
      selectedIcon: Icons.warning_amber_rounded,
      badgeCount: 3,
    ),
    AppNavItem(
      routeIndex: 5,
      section: AppNavSection.home,
      sidebarLabel: 'Store Matrix',
      labelEn: 'Store Matrix',
      labelAr: 'مصفوفة الفروع',
      shortLabel: 'Matrix',
      icon: Icons.store_mall_directory_rounded,
      selectedIcon: Icons.store_mall_directory_rounded,
    ),
    AppNavItem(
      routeIndex: 1,
      section: AppNavSection.inputs,
      sidebarLabel: 'Sell-Out',
      labelEn: 'Sell-Out & Targets',
      labelAr: 'المبيعات ومستهدفات الـ Sell-Out',
      shortLabel: 'Sell-Out',
      icon: Icons.analytics_rounded,
      selectedIcon: Icons.analytics_rounded,
    ),
    AppNavItem(
      routeIndex: 2,
      section: AppNavSection.inputs,
      sidebarLabel: 'Sell-In',
      labelEn: 'Sell-In & Targets',
      labelAr: 'التوريد ومستهدفات الـ Sell-In',
      shortLabel: 'Sell-In',
      icon: Icons.local_shipping_rounded,
      selectedIcon: Icons.local_shipping_rounded,
    ),
    AppNavItem(
      routeIndex: 3,
      section: AppNavSection.inputs,
      sidebarLabel: 'Returns',
      labelEn: 'Returns',
      labelAr: 'المرتجعات',
      shortLabel: 'Returns',
      icon: Icons.assignment_return_rounded,
      selectedIcon: Icons.assignment_return_rounded,
    ),
    AppNavItem(
      routeIndex: 11,
      section: AppNavSection.inputs,
      sidebarLabel: 'Product Master',
      labelEn: 'Product Master & Price List',
      labelAr: 'كارتة الأصناف والأسعار',
      shortLabel: 'Master',
      icon: Icons.qr_code_2_rounded,
      selectedIcon: Icons.qr_code_2_rounded,
    ),
    AppNavItem(
      routeIndex: 9,
      section: AppNavSection.inputs,
      sidebarLabel: 'CPFR Replenishment',
      labelEn: 'CPFR & PO',
      labelAr: 'التجديد وأوامر الشراء',
      shortLabel: 'CPFR',
      icon: Icons.inventory_2_rounded,
      selectedIcon: Icons.inventory_2_rounded,
    ),
    AppNavItem(
      routeIndex: 6,
      section: AppNavSection.marketing,
      sidebarLabel: 'Pricing & Promos',
      labelEn: 'Pricing & Promos',
      labelAr: 'التسعير والعروض',
      shortLabel: 'Pricing',
      icon: Icons.price_change_rounded,
      selectedIcon: Icons.price_change_rounded,
    ),
    AppNavItem(
      routeIndex: 7,
      section: AppNavSection.marketing,
      sidebarLabel: 'Compare',
      labelEn: 'Compare',
      labelAr: 'مقارنة المنافسين',
      shortLabel: 'Compare',
      icon: Icons.compare_arrows_rounded,
      selectedIcon: Icons.compare_arrows_rounded,
    ),
    AppNavItem(
      routeIndex: 8,
      section: AppNavSection.marketing,
      sidebarLabel: 'Trade Marketing & ROI',
      labelEn: 'Trade Marketing & ROI',
      labelAr: 'المصروفات الترويجية وعائد التسويق',
      shortLabel: 'Promo ROI',
      icon: Icons.campaign_rounded,
      selectedIcon: Icons.campaign_rounded,
    ),
    AppNavItem(
      routeIndex: 12,
      section: AppNavSection.system,
      sidebarLabel: 'Errors',
      labelEn: 'Data Errors',
      labelAr: 'الأخطاء',
      shortLabel: 'Errors',
      icon: AppIcons.dataQuality,
      selectedIcon: AppIcons.dataQuality,
    ),
    // Kept for `/upload` deep links. Not shown in any menu.
    AppNavItem(
      routeIndex: 10,
      section: AppNavSection.system,
      sidebarLabel: 'Upload',
      labelEn: 'Smart Upload',
      labelAr: 'رفع البيانات الذكي',
      shortLabel: 'Upload',
      icon: Icons.auto_awesome_rounded,
      selectedIcon: Icons.auto_awesome_rounded,
      showInMenu: false,
    ),
  ];

  static List<AppNavItem> get menu =>
      items.where((item) => item.showInMenu).toList(growable: false);

  static AppNavItem byRoute(int routeIndex) {
    for (final item in items) {
      if (item.routeIndex == routeIndex) return item;
    }
    throw ArgumentError.value(routeIndex, 'routeIndex', 'Unknown nav route');
  }

  /// Index inside [menu], or null when the route is hidden or unknown.
  static int? menuIndexForRoute(int routeIndex) {
    final i = menu.indexWhere((item) => item.routeIndex == routeIndex);
    return i < 0 ? null : i;
  }

  static List<NavMenuGroup> groupedMenu() {
    final order = <AppNavSection>[];
    final buckets = <String, List<AppNavItem>>{};
    for (final item in menu) {
      final bucket = buckets[item.section.id];
      if (bucket == null) {
        order.add(item.section);
        buckets[item.section.id] = <AppNavItem>[item];
      } else {
        bucket.add(item);
      }
    }
    return [
      for (final section in order)
        NavMenuGroup(
            section, List<AppNavItem>.unmodifiable(buckets[section.id]!)),
    ];
  }
}

/// Wide sidebar, drawer, and More sheet. The narrow rail passes
/// [collapsed] and gets a thin divider between sections instead of chips.
List<Widget> navSectionChildren({
  required Widget Function(AppNavItem item) itemBuilder,
  bool collapsed = false,
  EdgeInsetsGeometry? labelPadding,
}) {
  final groups = AppNavCatalog.groupedMenu();
  return [
    for (var i = 0; i < groups.length; i++) ...[
      if (i > 0)
        NavSectionDivider(
          sectionId: groups[i - 1].section.id,
          collapsed: collapsed,
        ),
      if (!collapsed)
        NavSectionLabel(
          section: groups[i].section,
          padding: labelPadding,
        ),
      for (final item in groups[i].items) itemBuilder(item),
    ],
  ];
}

/// Small Arabic chip above a wide-menu section (variant C).
class NavSectionLabel extends StatelessWidget {
  final AppNavSection section;
  final EdgeInsetsGeometry? padding;

  const NavSectionLabel({
    super.key,
    required this.section,
    this.padding,
  });

  /// Extra space around the chip so the groups read as separate blocks.
  /// Top is 8 rather than the mockup's 10 so twelve rows still fit at 1280×800.
  static const EdgeInsetsDirectional chipPadding =
      EdgeInsetsDirectional.fromSTEB(8.0, 8.0, 8.0, 6.0);

  @override
  Widget build(BuildContext context) {
    if (!section.labeled) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      key: ValueKey('nav_section_${section.id}'),
      padding: padding ?? chipPadding,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: M3Shape.radiusFull,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
            child: Text(
              section.titleAr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Visible rule between sections. The narrow rail uses the same line with
/// less padding so the icon column stays compact.
class NavSectionDivider extends StatelessWidget {
  final String sectionId;
  final bool collapsed;

  const NavSectionDivider({
    super.key,
    required this.sectionId,
    this.collapsed = false,
  });

  static const EdgeInsets widePadding = EdgeInsets.only(top: 10.0, bottom: 6.0);

  static const EdgeInsetsDirectional collapsedPadding =
      EdgeInsetsDirectional.fromSTEB(12.0, 6.0, 12.0, 6.0);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // A ColoredBox, not Divider: Divider is a Container+BoxDecoration, and
    // the nav list is required to keep its indicator as a Material pill.
    return Padding(
      key: ValueKey('nav_section_divider_$sectionId'),
      padding: collapsed ? collapsedPadding : widePadding,
      child: SizedBox(
        key: ValueKey('nav_section_rule_$sectionId'),
        height: 1.0,
        width: double.infinity,
        child: ColoredBox(
          color: colorScheme.outline.withOpacity(0.65),
        ),
      ),
    );
  }
}

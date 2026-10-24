import 'package:flutter/material.dart';

/// Single source of truth for icons.
///
/// RULE: Google Material Icons only (Flutter `Icons.*`), Rounded style only.
/// No other icon packages, no SVG/PNG icons. Use the `selected*` filled
/// variants only for the selected state in navigation.
class AppIcons {
  AppIcons._();

  // Navigation / pages
  static const IconData dashboard = Icons.dashboard_rounded;
  static const IconData sellOut = Icons.point_of_sale_rounded;
  static const IconData sellIn = Icons.local_shipping_rounded;
  static const IconData oos = Icons.inventory_2_rounded;
  static const IconData storeMatrix = Icons.storefront_rounded;
  static const IconData pricing = Icons.price_change_rounded;
  static const IconData compare = Icons.compare_arrows_rounded;
  static const IconData tradeMarketing = Icons.campaign_rounded;
  static const IconData cpfr = Icons.warehouse_rounded;
  static const IconData upload = Icons.cloud_upload_rounded;
  static const IconData productMaster = Icons.category_rounded;
  static const IconData superAdmin = Icons.admin_panel_settings_rounded;
  static const IconData analytics = Icons.analytics_rounded;
  static const IconData insights = Icons.insights_rounded;
  static const IconData leaderboard = Icons.leaderboard_rounded;
  static const IconData business = Icons.business_rounded;
  static const IconData store = Icons.store_rounded;

  // Actions
  static const IconData search = Icons.search_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData clear = Icons.clear_rounded;
  static const IconData clearAll = Icons.clear_all_rounded;
  static const IconData refresh = Icons.refresh_rounded;
  static const IconData download = Icons.download_rounded;
  static const IconData uploadFile = Icons.upload_file_rounded;
  static const IconData print = Icons.print_rounded;
  static const IconData edit = Icons.edit_rounded;
  static const IconData delete = Icons.delete_rounded;
  static const IconData deleteForever = Icons.delete_forever_rounded;
  static const IconData copy = Icons.copy_rounded;
  static const IconData filter = Icons.tune_rounded;
  static const IconData visibility = Icons.visibility_rounded;
  static const IconData logout = Icons.logout_rounded;
  static const IconData scanner = Icons.qr_code_scanner_rounded;
  static const IconData tableView = Icons.table_view_rounded;
  static const IconData ai = Icons.auto_awesome_rounded;

  // Navigation affordances (auto-mirrored in RTL by Flutter)
  static const IconData chevronStart = Icons.chevron_left_rounded;
  static const IconData chevronEnd = Icons.chevron_right_rounded;
  static const IconData dropDown = Icons.arrow_drop_down_rounded;
  static const IconData arrowUp = Icons.arrow_upward_rounded;
  static const IconData arrowDown = Icons.arrow_downward_rounded;
  static const IconData trendingUp = Icons.trending_up_rounded;
  static const IconData trendingDown = Icons.trending_down_rounded;

  // Dates
  static const IconData calendar = Icons.calendar_month_rounded;
  static const IconData dateRange = Icons.date_range_rounded;

  // Status
  static const IconData success = Icons.check_circle_rounded;
  static const IconData check = Icons.check_rounded;
  static const IconData warning = Icons.warning_amber_rounded;
  static const IconData error = Icons.error_rounded;
  static const IconData info = Icons.info_rounded;
  static const IconData verified = Icons.verified_rounded;
  static const IconData cloudOff = Icons.cloud_off_rounded;
  static const IconData empty = Icons.inbox_rounded;

  // Entities
  static const IconData money = Icons.payments_rounded;
  static const IconData units = Icons.inventory_2_rounded;
  static const IconData person = Icons.person_rounded;
  static const IconData email = Icons.email_rounded;
  static const IconData lock = Icons.lock_rounded;
  static const IconData location = Icons.location_on_rounded;
  static const IconData barcode = Icons.qr_code_2_rounded;
  static const IconData offer = Icons.local_offer_rounded;
}

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
  static const IconData dataQuality = Icons.rule_rounded;
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
  static const IconData fileDownload = Icons.file_download_rounded;
  static const IconData edit = Icons.edit_rounded;
  static const IconData add = Icons.add_rounded;
  static const IconData discount = Icons.percent_rounded;
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
  static const IconData firstPage = Icons.first_page_rounded;
  static const IconData lastPage = Icons.last_page_rounded;
  static const IconData dropDown = Icons.arrow_drop_down_rounded;
  static const IconData arrowUp = Icons.arrow_upward_rounded;
  static const IconData arrowDown = Icons.arrow_downward_rounded;
  static const IconData tag = Icons.tag_rounded;
  static const IconData arrowForward = Icons.arrow_forward_rounded;
  static const IconData trendingUp = Icons.trending_up_rounded;
  static const IconData trendingDown = Icons.trending_down_rounded;
  static const IconData trendingFlat = Icons.trending_flat_rounded;
  static const IconData filterList = Icons.filter_list_rounded;
  static const IconData barChart = Icons.bar_chart_rounded;
  static const IconData promo = Icons.redeem_rounded;
  static const IconData newItem = Icons.fiber_new_rounded;

  // Dates
  static const IconData calendar = Icons.calendar_month_rounded;
  static const IconData dateRange = Icons.date_range_rounded;
  static const IconData event = Icons.event_rounded;

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

  // Executive Dashboard
  static const IconData calendarToday = Icons.calendar_today_rounded;
  static const IconData pieChart = Icons.pie_chart_rounded;
  static const IconData donutChart = Icons.donut_small_rounded;
  static const IconData filterAlt = Icons.filter_alt_rounded;
  static const IconData groups = Icons.groups_rounded;
  static const IconData pendingCustomers = Icons.person_search_rounded;
  static const IconData sellInAssist = Icons.auto_awesome_rounded;
  static const IconData link = Icons.link_rounded;
  static const IconData tableChart = Icons.table_chart_rounded;
  static const IconData productMatchReview = Icons.qr_code_scanner_rounded;
  static const IconData undo = Icons.undo_rounded;
  static const IconData merge = Icons.merge_rounded;
  static const IconData block = Icons.block_rounded;
  static const IconData collapseAll = Icons.unfold_less_rounded;
  static const IconData expandAll = Icons.unfold_more_rounded;
  static const IconData expandMore = Icons.expand_more_rounded;
  static const IconData expandLess = Icons.expand_less_rounded;
  static const IconData premium = Icons.workspace_premium_rounded;
}

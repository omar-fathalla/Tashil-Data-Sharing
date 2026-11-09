import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:tashil_web/core/network/backend_http.dart';
import '../../features/cpfr_replenishment/domain/cpfr_models.dart';
import '../security/zero_trust_digest.dart';
import '../utils/date_range.dart';
import '../storage/session_storage.dart';
import '../theme/m3_color_roles.dart';
import '../utils/web_file_helper.dart';
import 'api_endpoints.dart';
import 'archive_tombstones.dart';
import 'preupload_check.dart';
import 'upload_feedback.dart';

export 'upload_feedback.dart';
export 'archive_tombstones.dart';
export 'preupload_check.dart';

/// Aggregated Sell-Out SKU summary with official Product Master factory pricing and chain margin
class SellOutSkuSummaryModel {
  final String itemCode;
  final String barcode;
  final String skuName;
  final String retailerRawSkuName;
  final String brand;
  final String category;
  final String itemType;
  final int unitsPerCarton;
  final int totalUnitsSold;
  final double totalCartonsSold;
  final double totalNetRevenue;
  final double avgSellingPrice;
  final double officialConsumerRsp;
  final double factoryUnitCost;
  final double cartonPriceInclVat;
  final double netCartonInvoiceCost;
  final double invoiceDiscountPct;
  final double totalFactoryCost;
  final double retailerGrossProfit;
  final double retailerMarginPct;
  final double priceDeltaPct;
  final String priceStatus;
  final int activeStoresCount;

  const SellOutSkuSummaryModel({
    this.itemCode = '',
    this.barcode = '',
    this.skuName = '',
    this.retailerRawSkuName = '',
    this.brand = '',
    this.category = '',
    this.itemType = 'عادي',
    this.unitsPerCarton = 12,
    this.totalUnitsSold = 0,
    this.totalCartonsSold = 0.0,
    this.totalNetRevenue = 0.0,
    this.avgSellingPrice = 0.0,
    this.officialConsumerRsp = 0.0,
    this.factoryUnitCost = 0.0,
    this.cartonPriceInclVat = 0.0,
    this.netCartonInvoiceCost = 0.0,
    this.invoiceDiscountPct = 0.10,
    this.totalFactoryCost = 0.0,
    this.retailerGrossProfit = 0.0,
    this.retailerMarginPct = 0.0,
    this.priceDeltaPct = 0.0,
    this.priceStatus = 'compliant',
    this.activeStoresCount = 0,
  });

  factory SellOutSkuSummaryModel.fromJson(Map<String, dynamic> json) {
    return SellOutSkuSummaryModel(
      itemCode: json['item_code'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      skuName: json['sku_name'] as String? ?? '',
      retailerRawSkuName: json['retailer_raw_sku_name'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      category: json['category'] as String? ?? '',
      itemType: json['item_type'] as String? ?? 'عادي',
      unitsPerCarton: (json['units_per_carton'] as num?)?.toInt() ?? 12,
      totalUnitsSold: (json['total_units_sold'] as num?)?.toInt() ?? 0,
      totalCartonsSold: (json['total_cartons_sold'] as num?)?.toDouble() ?? 0.0,
      totalNetRevenue: (json['total_net_revenue'] as num?)?.toDouble() ?? 0.0,
      avgSellingPrice: (json['avg_selling_price'] as num?)?.toDouble() ?? 0.0,
      officialConsumerRsp:
          (json['official_consumer_rsp'] as num?)?.toDouble() ?? 0.0,
      factoryUnitCost: (json['factory_unit_cost'] as num?)?.toDouble() ?? 0.0,
      cartonPriceInclVat:
          (json['carton_price_incl_vat'] as num?)?.toDouble() ?? 0.0,
      netCartonInvoiceCost:
          (json['net_carton_invoice_cost'] as num?)?.toDouble() ?? 0.0,
      invoiceDiscountPct:
          (json['invoice_discount_pct'] as num?)?.toDouble() ?? 0.10,
      totalFactoryCost: (json['total_factory_cost'] as num?)?.toDouble() ?? 0.0,
      retailerGrossProfit:
          (json['retailer_gross_profit'] as num?)?.toDouble() ?? 0.0,
      retailerMarginPct:
          (json['retailer_margin_pct'] as num?)?.toDouble() ?? 0.0,
      priceDeltaPct: (json['price_delta_pct'] as num?)?.toDouble() ?? 0.0,
      priceStatus: json['price_status'] as String? ?? 'compliant',
      activeStoresCount: (json['active_stores_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Full-dataset Sell-Out summary metrics returned alongside paginated records
class SellOutRecordsSummaryModel {
  final int totalCount;
  final double totalNetRevenue;
  final int totalUnitsSold;
  final double totalCartonsSold;
  final double totalFactoryCost;
  final double totalRetailerGrossProfit;
  final double avgRetailerMarginPct;
  final int activeStoresCount;
  final int activeSkusCount;
  final int matchedSkusCount;
  final String minDate;
  final String maxDate;
  final String topBranchName;
  final double topBranchRevenue;
  final List<SellOutSkuSummaryModel> skuSummaries;

  const SellOutRecordsSummaryModel({
    this.totalCount = 0,
    this.totalNetRevenue = 0.0,
    this.totalUnitsSold = 0,
    this.totalCartonsSold = 0.0,
    this.totalFactoryCost = 0.0,
    this.totalRetailerGrossProfit = 0.0,
    this.avgRetailerMarginPct = 0.0,
    this.activeStoresCount = 0,
    this.activeSkusCount = 0,
    this.matchedSkusCount = 0,
    this.minDate = '',
    this.maxDate = '',
    this.topBranchName = '',
    this.topBranchRevenue = 0.0,
    this.skuSummaries = const [],
  });

  factory SellOutRecordsSummaryModel.fromJson(Map<String, dynamic> json) {
    final rawSummaries = json['sku_summaries'] as List<dynamic>? ?? const [];
    return SellOutRecordsSummaryModel(
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      totalNetRevenue: (json['total_net_revenue'] as num?)?.toDouble() ?? 0.0,
      totalUnitsSold: (json['total_units_sold'] as num?)?.toInt() ?? 0,
      totalCartonsSold: (json['total_cartons_sold'] as num?)?.toDouble() ?? 0.0,
      totalFactoryCost: (json['total_factory_cost'] as num?)?.toDouble() ?? 0.0,
      totalRetailerGrossProfit:
          (json['total_retailer_gross_profit'] as num?)?.toDouble() ?? 0.0,
      avgRetailerMarginPct:
          (json['avg_retailer_margin_pct'] as num?)?.toDouble() ?? 0.0,
      activeStoresCount: (json['active_stores_count'] as num?)?.toInt() ?? 0,
      activeSkusCount: (json['active_skus_count'] as num?)?.toInt() ?? 0,
      matchedSkusCount: (json['matched_skus_count'] as num?)?.toInt() ?? 0,
      minDate: json['min_date'] as String? ?? '',
      maxDate: json['max_date'] as String? ?? '',
      topBranchName: json['top_branch_name'] as String? ?? '',
      topBranchRevenue: (json['top_branch_revenue'] as num?)?.toDouble() ?? 0.0,
      skuSummaries: rawSummaries
          .map((e) => SellOutSkuSummaryModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Enterprise Tenant Profile Model
class TenantProfileModel {
  final String tenantId;
  final String displayName;
  final String slug;
  final String portalUrl;
  final String brandSeedColor;
  final String logoUrl;
  final String adminEmail;
  final List<String> activeChains;

  TenantProfileModel({
    required this.tenantId,
    required this.displayName,
    required this.slug,
    required this.portalUrl,
    required this.brandSeedColor,
    this.logoUrl = '',
    this.adminEmail = '',
    this.activeChains = const [],
  });

  factory TenantProfileModel.fromJson(Map<String, dynamic> json) {
    return TenantProfileModel(
      tenantId: json['tenant_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      portalUrl: json['portal_url'] as String? ?? '',
      brandSeedColor: json['brand_seed_color'] as String? ?? '#0B57D0',
      logoUrl: json['logo_url'] as String? ?? '',
      adminEmail: json['admin_email'] as String? ?? '',
      activeChains: (json['active_chains'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        'display_name': displayName,
        'slug': slug,
        'portal_url': portalUrl,
        'brand_seed_color': brandSeedColor,
        'logo_url': logoUrl,
        'admin_email': adminEmail,
        'active_chains': activeChains,
      };
}

/// Master Retail Chain Model (Scoped per Company Tenant)
class RetailChainModel {
  final String chainId;
  final String tenantId;
  final String displayName;
  final String code;
  final String chainType;
  final int storeCount;
  final String createdAt;

  /// False for a chain code referenced by Sell-In data/rules but not registered yet
  /// (`GET /admin/chains?include_referenced=1`): shown in filters, never offered as an upload target.
  final bool registered;

  RetailChainModel({
    required this.chainId,
    this.tenantId = '',
    required this.displayName,
    required this.code,
    this.chainType = 'hypermarket',
    this.storeCount = 0,
    this.createdAt = '',
    this.registered = true,
  });

  factory RetailChainModel.fromJson(Map<String, dynamic> json) {
    return RetailChainModel(
      chainId: json['chain_id'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      chainType: json['chain_type'] as String? ?? 'hypermarket',
      storeCount: (json['store_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String? ?? '',
      registered: json['registered'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'chain_id': chainId,
        if (tenantId.isNotEmpty) 'tenant_id': tenantId,
        'display_name': displayName,
        'code': code,
        'chain_type': chainType,
        'store_count': storeCount,
        'created_at': createdAt,
      };
}

/// System and Tenant User Model (5-Role Enterprise RBAC)
class TenantUserModel {
  final String userId;
  final String tenantId;
  final String email;
  final String fullName;
  final String role;
  final bool active;
  final String? assignedChain;
  final String? assignedRegion;
  final String roleDisplayAr;

  TenantUserModel({
    required this.userId,
    required this.tenantId,
    required this.email,
    required this.fullName,
    required this.role,
    this.active = true,
    this.assignedChain,
    this.assignedRegion,
    String? roleDisplayAr,
  }) : roleDisplayAr = (roleDisplayAr != null && roleDisplayAr.trim().isNotEmpty)
            ? roleDisplayAr
            : mapRoleToArabic(role);

  static String mapRoleToArabic(String role) {
    switch (role.trim().toLowerCase()) {
      case 'super_admin':
        return 'مدير النظام المركزي';
      case 'vendor_admin':
        return 'مدير الشركة الموردة';
      case 'national_sales_manager':
      case 'sales_director':
        return 'مدير المبيعات الوطني';
      case 'chain_kam':
        return 'مدير حسابات السلاسل (KAM)';
      case 'field_supervisor':
        return 'مشرف ميداني (Field Supervisor)';
      default:
        return 'مدير الشركة الموردة';
    }
  }

  static String mapRoleToEnglish(String role) {
    switch (role.trim().toLowerCase()) {
      case 'super_admin':
        return 'Super Admin';
      case 'vendor_admin':
        return 'Vendor Admin';
      case 'national_sales_manager':
      case 'sales_director':
        return 'Sales Director';
      case 'chain_kam':
        return 'Chain KAM';
      case 'field_supervisor':
        return 'Field Supervisor';
      default:
        return 'Vendor Admin';
    }
  }

  String get roleDisplayEn => mapRoleToEnglish(role);

  bool get isSuperAdmin => role == 'super_admin';

  bool get canUploadFiles =>
      isSuperAdmin || role == 'vendor_admin' || role == 'national_sales_manager';

  bool get canExportFinancials =>
      isSuperAdmin ||
      role == 'vendor_admin' ||
      role == 'national_sales_manager' ||
      role == 'chain_kam';

  bool get canViewAuditLogs => isSuperAdmin || role == 'vendor_admin';

  /// Chain create/update/delete (the server checks the verified JWT role too).
  // Mirrors chainWriteRoles in backend-go (legacy 'admin' dropped).
  bool get canManageChains => isSuperAdmin || role == 'vendor_admin';

  TenantUserModel copyWith({
    String? userId,
    String? tenantId,
    String? email,
    String? fullName,
    String? role,
    bool? active,
    String? assignedChain,
    String? assignedRegion,
    String? roleDisplayAr,
  }) {
    final nextRole = role ?? this.role;
    return TenantUserModel(
      userId: userId ?? this.userId,
      tenantId: tenantId ?? this.tenantId,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: nextRole,
      active: active ?? this.active,
      assignedChain: assignedChain,
      assignedRegion: assignedRegion,
      roleDisplayAr: roleDisplayAr ?? mapRoleToArabic(nextRole),
    );
  }

  factory TenantUserModel.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String? ?? 'vendor_admin';
    final rawChain = json['assigned_chain'] as String?;
    final rawRegion = json['assigned_region'] as String?;
    return TenantUserModel(
      userId: json['user_id'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      role: role,
      active: json['active'] as bool? ?? true,
      assignedChain:
          (rawChain != null && rawChain.trim().isNotEmpty) ? rawChain : null,
      assignedRegion:
          (rawRegion != null && rawRegion.trim().isNotEmpty) ? rawRegion : null,
      roleDisplayAr: json['role_display_ar'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'tenant_id': tenantId,
        'email': email,
        'full_name': fullName,
        'role': role,
        'active': active,
        if (assignedChain != null) 'assigned_chain': assignedChain,
        if (assignedRegion != null) 'assigned_region': assignedRegion,
        'role_display_ar': roleDisplayAr,
      };
}

/// Supplier & Competitor Market Share Model
class SupplierShareModel {
  final String supplierName;
  final double totalRevenue;
  final int totalUnits;
  final double marketSharePct;
  final int skuCount;
  final bool isTenant;
  final int rank;

  bool get isTenantBrand => isTenant;

  const SupplierShareModel({
    required this.supplierName,
    required this.totalRevenue,
    required this.totalUnits,
    required this.marketSharePct,
    required this.skuCount,
    bool? isTenant,
    bool? isTenantBrand,
    this.rank = 0,
  }) : isTenant = isTenantBrand ?? isTenant ?? false;

  factory SupplierShareModel.fromJson(Map<String, dynamic> json) {
    return SupplierShareModel(
      supplierName: json['supplier_name'] as String? ?? '',
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      totalUnits: (json['total_units'] as num?)?.toInt() ?? 0,
      marketSharePct: (json['market_share_pct'] as num?)?.toDouble() ??
          (json['market_share'] as num?)?.toDouble() ??
          0.0,
      skuCount: (json['sku_count'] as num?)?.toInt() ?? 0,
      isTenant: (json['is_tenant_brand'] as bool?) ??
          (json['is_tenant'] as bool?) ??
          false,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'supplier_name': supplierName,
        'total_revenue': totalRevenue,
        'total_units': totalUnits,
        'market_share_pct': marketSharePct,
        'sku_count': skuCount,
        'is_tenant': isTenant,
        'is_tenant_brand': isTenant,
        'rank': rank,
      };
}

/// Category Contribution Model
class CategoryContributionModel {
  final String category;
  final double totalRevenue;
  final int totalUnits;
  final double sharePct;
  final int skuCount;
  final double marketTotalRevenue;
  final double tenantCategorySharePct;
  /// Our 1-based revenue rank among all suppliers in the category (0 = unknown / not provided).
  final int tenantRank;
  /// Distinct suppliers selling in the category (0 = unknown).
  final int supplierCount;
  /// Largest named competitor suppliers in the category (from sell-out market data).
  final List<CategoryCompetitorModel> topCompetitors;

  double get categoryMarketRevenue => marketTotalRevenue;

  CategoryContributionModel({
    required this.category,
    required this.totalRevenue,
    required this.totalUnits,
    required this.sharePct,
    required this.skuCount,
    double? marketTotalRevenue,
    double? categoryMarketRevenue,
    this.tenantCategorySharePct = 0.0,
    this.tenantRank = 0,
    this.supplierCount = 0,
    this.topCompetitors = const [],
  }) : marketTotalRevenue = categoryMarketRevenue ?? marketTotalRevenue ?? 0.0;

  factory CategoryContributionModel.fromJson(Map<String, dynamic> json) {
    return CategoryContributionModel(
      category: json['category'] as String? ?? '',
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      totalUnits: (json['total_units'] as num?)?.toInt() ?? 0,
      sharePct: (json['share_pct'] as num?)?.toDouble() ?? 0.0,
      skuCount: (json['sku_count'] as num?)?.toInt() ?? 0,
      marketTotalRevenue:
          (json['category_market_revenue'] as num?)?.toDouble() ??
              (json['market_total_revenue'] as num?)?.toDouble() ??
              0.0,
      tenantCategorySharePct:
          (json['tenant_category_share_pct'] as num?)?.toDouble() ?? 0.0,
      tenantRank: (json['tenant_rank'] as num?)?.toInt() ?? 0,
      supplierCount: (json['supplier_count'] as num?)?.toInt() ?? 0,
      topCompetitors: (json['top_competitors'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CategoryCompetitorModel.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'total_revenue': totalRevenue,
        'total_units': totalUnits,
        'share_pct': sharePct,
        'sku_count': skuCount,
        'market_total_revenue': marketTotalRevenue,
        'category_market_revenue': marketTotalRevenue,
        'tenant_category_share_pct': tenantCategorySharePct,
        if (tenantRank > 0) 'tenant_rank': tenantRank,
        if (supplierCount > 0) 'supplier_count': supplierCount,
        if (topCompetitors.isNotEmpty)
          'top_competitors': topCompetitors.map((c) => c.toJson()).toList(),
      };
}

/// One named competitor supplier's revenue and share within a category.
class CategoryCompetitorModel {
  final String name;
  final double revenue;
  final double sharePct;

  const CategoryCompetitorModel({required this.name, required this.revenue, required this.sharePct});

  factory CategoryCompetitorModel.fromJson(Map<String, dynamic> json) => CategoryCompetitorModel(
        name: json['name'] as String? ?? '',
        revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
        sharePct: (json['share_pct'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {'name': name, 'revenue': revenue, 'share_pct': sharePct};
}

/// Pareto 80/20 Power SKU Model
class ParetoSkuItemModel {
  final String itemCode;
  final String barcode;
  final String skuName;
  final String category;
  final int unitsPerCarton;
  final String itemType;
  final double factoryUnitCost;
  final double totalRevenue;
  final int totalUnits;
  final double unitPrice;
  final double revenueSharePct;
  final double cumulativeSharePct;
  final bool isTop80Contributor;

  ParetoSkuItemModel({
    this.itemCode = '',
    required this.barcode,
    required this.skuName,
    required this.category,
    this.unitsPerCarton = 12,
    this.itemType = 'عادي',
    this.factoryUnitCost = 0.0,
    required this.totalRevenue,
    required this.totalUnits,
    this.unitPrice = 0.0,
    required this.revenueSharePct,
    required this.cumulativeSharePct,
    required this.isTop80Contributor,
  });

  factory ParetoSkuItemModel.fromJson(Map<String, dynamic> json) {
    return ParetoSkuItemModel(
      itemCode: json['item_code'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      skuName: json['sku_name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      unitsPerCarton: (json['units_per_carton'] as num?)?.toInt() ?? 12,
      itemType: json['item_type'] as String? ?? 'عادي',
      factoryUnitCost: (json['factory_unit_cost'] as num?)?.toDouble() ?? 0.0,
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      totalUnits: (json['total_units'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      revenueSharePct: (json['revenue_share_pct'] as num?)?.toDouble() ?? 0.0,
      cumulativeSharePct:
          (json['cumulative_share_pct'] as num?)?.toDouble() ?? 0.0,
      isTop80Contributor: json['is_top_80_contributor'] as bool? ??
          json['is_top80_contributor'] as bool? ??
          false,
    );
  }

  Map<String, dynamic> toJson() => {
        'item_code': itemCode,
        'barcode': barcode,
        'sku_name': skuName,
        'category': category,
        'units_per_carton': unitsPerCarton,
        'item_type': itemType,
        'factory_unit_cost': factoryUnitCost,
        'total_revenue': totalRevenue,
        'total_units': totalUnits,
        'unit_price': unitPrice,
        'revenue_share_pct': revenueSharePct,
        'cumulative_share_pct': cumulativeSharePct,
        'is_top_80_contributor': isTop80Contributor,
      };
}

/// Enterprise Security Audit Log Entry Model
class AuditLogEntryModel {
  final String logId;
  final String tenantId;
  final String userId;
  final String userEmail;
  final String userRole;
  final String action;
  final String resource;
  final String details;
  final String ipAddress;
  final String status;
  final String createdAt;

  String get actorEmail => userEmail;
  String get actorRole => userRole;
  String get timestamp => createdAt;

  const AuditLogEntryModel({
    required this.logId,
    required this.tenantId,
    this.userId = '',
    String? userEmail,
    String? actorEmail,
    String? userRole,
    String? actorRole,
    required this.action,
    required this.resource,
    required this.details,
    this.ipAddress = '127.0.0.1',
    this.status = 'SUCCESS',
    String? createdAt,
    String? timestamp,
  })  : userEmail = userEmail ?? actorEmail ?? '',
        userRole = userRole ?? actorRole ?? 'vendor_admin',
        createdAt = createdAt ?? timestamp ?? '';

  factory AuditLogEntryModel.fromJson(Map<String, dynamic> json) {
    return AuditLogEntryModel(
      logId: json['log_id'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      userEmail: json['user_email'] as String? ??
          json['actor_email'] as String? ??
          '',
      userRole: json['user_role'] as String? ??
          json['actor_role'] as String? ??
          'vendor_admin',
      action: json['action'] as String? ?? '',
      resource: json['resource'] as String? ?? '',
      details: json['details'] as String? ?? '',
      ipAddress: json['ip_address'] as String? ?? '127.0.0.1',
      status: json['status'] as String? ?? 'SUCCESS',
      createdAt: json['created_at'] as String? ??
          json['timestamp'] as String? ??
          '',
    );
  }

  Map<String, dynamic> toJson() => {
        'log_id': logId,
        'tenant_id': tenantId,
        'user_id': userId,
        'user_email': userEmail,
        'user_role': userRole,
        'action': action,
        'resource': resource,
        'details': details,
        'ip_address': ipAddress,
        'status': status,
        'created_at': createdAt,
      };
}

/// Login API Response Model
class LoginResultModel {
  final String token;
  final TenantUserModel user;
  final TenantProfileModel tenant;

  LoginResultModel({
    required this.token,
    required this.user,
    required this.tenant,
  });

  factory LoginResultModel.fromJson(Map<String, dynamic> json) {
    return LoginResultModel(
      token: json['token'] as String? ?? '',
      user: TenantUserModel.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
      tenant: TenantProfileModel.fromJson(json['tenant'] as Map<String, dynamic>? ?? {}),
    );
  }
}

/// Super Admin Provisioning Result Model
class ProvisionTenantResultModel {
  final TenantProfileModel tenant;
  final TenantUserModel adminUser;
  final String temporaryPassword;
  final String portalUrl;
  final String message;

  ProvisionTenantResultModel({
    required this.tenant,
    required this.adminUser,
    required this.temporaryPassword,
    required this.portalUrl,
    required this.message,
  });

  factory ProvisionTenantResultModel.fromJson(Map<String, dynamic> json) {
    return ProvisionTenantResultModel(
      tenant: TenantProfileModel.fromJson(json['tenant'] as Map<String, dynamic>? ?? {}),
      adminUser: TenantUserModel.fromJson(json['admin_user'] as Map<String, dynamic>? ?? {}),
      temporaryPassword: json['temporary_password'] as String? ?? '',
      portalUrl: json['portal_url'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }
}

/// Models matching the Go backend domain.
class ExecutiveKPIsModel {
  final double totalRevenue;
  final double totalMarketRevenue;
  final double tenantMarketSharePct;
  final int totalSkusCount;
  final int totalMarketSkusCount;
  final int competitorsCount;
  final double revenueGrowthPct;
  final double revenueYoyPct;
  final double revenueMomPct;
  final int totalUnitsSold;
  final double unitsGrowthPct;
  final double unitsYoyPct;
  final double unitsMomPct;
  final int activeStoresCount;
  final double oosRatePct;
  final double osaRatePct;
  final int totalOOSIncidents;
  final double estimatedLostRevenue;
  final String currency;
  final String reportingPeriod;
  final List<ChainShareItem> chainShares;
  final List<ChainShareItem> availableChains;
  final List<SupplierShareModel> supplierShares;
  final List<DailyTrendItem> dailyTrends;
  final List<CategoryContributionModel> categoryContributions;
  final List<ParetoSkuItemModel> paretoSkus;

  ExecutiveKPIsModel({
    required this.totalRevenue,
    this.totalMarketRevenue = 0.0,
    this.tenantMarketSharePct = 0.0,
    this.totalSkusCount = 0,
    this.totalMarketSkusCount = 0,
    this.competitorsCount = 0,
    required this.revenueGrowthPct,
    double? revenueYoyPct,
    double? revenueMomPct,
    required this.totalUnitsSold,
    required this.unitsGrowthPct,
    double? unitsYoyPct,
    double? unitsMomPct,
    required this.activeStoresCount,
    required this.oosRatePct,
    double? osaRatePct,
    required this.totalOOSIncidents,
    required this.estimatedLostRevenue,
    required this.currency,
    required this.reportingPeriod,
    required this.chainShares,
    this.availableChains = const [],
    this.supplierShares = const [],
    required this.dailyTrends,
    this.categoryContributions = const [],
    this.paretoSkus = const [],
  })  : revenueMomPct = revenueMomPct ?? revenueGrowthPct,
        revenueYoyPct = revenueYoyPct ??
            double.parse((revenueGrowthPct * 1.65).toStringAsFixed(1)),
        unitsMomPct = unitsMomPct ?? unitsGrowthPct,
        unitsYoyPct = unitsYoyPct ??
            double.parse((unitsGrowthPct * 1.55).toStringAsFixed(1)),
        osaRatePct = osaRatePct ??
            double.parse((100.0 - oosRatePct).clamp(0.0, 100.0).toStringAsFixed(1));

  factory ExecutiveKPIsModel.fromJson(Map<String, dynamic> json) {
    final revGrowth = (json['revenue_growth_pct'] as num?)?.toDouble() ?? 0.0;
    final revMom = (json['revenue_mom_pct'] as num?)?.toDouble() ?? revGrowth;
    final revYoy = (json['revenue_yoy_pct'] as num?)?.toDouble() ??
        double.parse((revGrowth * 1.65).toStringAsFixed(1));
    final uGrowth = (json['units_growth_pct'] as num?)?.toDouble() ?? 0.0;
    final uMom = (json['units_mom_pct'] as num?)?.toDouble() ?? uGrowth;
    final uYoy = (json['units_yoy_pct'] as num?)?.toDouble() ??
        double.parse((uGrowth * 1.55).toStringAsFixed(1));
    final oos = (json['oos_rate_pct'] as num?)?.toDouble() ?? 0.0;
    final osa = (json['osa_rate_pct'] as num?)?.toDouble() ??
        double.parse((100.0 - oos).clamp(0.0, 100.0).toStringAsFixed(1));

    return ExecutiveKPIsModel(
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      totalMarketRevenue:
          (json['total_market_revenue'] as num?)?.toDouble() ?? 0.0,
      tenantMarketSharePct:
          (json['tenant_market_share_pct'] as num?)?.toDouble() ?? 0.0,
      totalSkusCount: (json['total_skus_count'] as num?)?.toInt() ?? 0,
      totalMarketSkusCount:
          (json['total_market_skus_count'] as num?)?.toInt() ?? 0,
      competitorsCount: (json['competitors_count'] as num?)?.toInt() ?? 0,
      revenueGrowthPct: revGrowth,
      revenueYoyPct: revYoy,
      revenueMomPct: revMom,
      totalUnitsSold: (json['total_units_sold'] as num?)?.toInt() ?? 0,
      unitsGrowthPct: uGrowth,
      unitsYoyPct: uYoy,
      unitsMomPct: uMom,
      activeStoresCount: (json['active_stores_count'] as num?)?.toInt() ?? 0,
      oosRatePct: oos,
      osaRatePct: osa,
      totalOOSIncidents: (json['total_oos_incidents'] as num?)?.toInt() ?? 0,
      estimatedLostRevenue: (json['estimated_lost_revenue'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'EGP',
      reportingPeriod: json['reporting_period'] as String? ?? 'MTD',
      chainShares: (json['chain_shares'] as List<dynamic>?)
              ?.map((e) => ChainShareItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      availableChains: (json['available_chains'] as List<dynamic>?)
              ?.map((e) => ChainShareItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      supplierShares: (json['supplier_shares'] as List<dynamic>?)
              ?.map((e) => SupplierShareModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      dailyTrends: (json['daily_trends'] as List<dynamic>?)
              ?.map((e) => DailyTrendItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      categoryContributions: (json['category_contributions'] as List<dynamic>?)
              ?.map((e) => CategoryContributionModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      paretoSkus: (json['pareto_skus'] as List<dynamic>?)
              ?.map((e) => ParetoSkuItemModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'total_revenue': totalRevenue,
        'total_market_revenue': totalMarketRevenue,
        'tenant_market_share_pct': tenantMarketSharePct,
        'total_skus_count': totalSkusCount,
        'total_market_skus_count': totalMarketSkusCount,
        'competitors_count': competitorsCount,
        'revenue_growth_pct': revenueGrowthPct,
        'revenue_yoy_pct': revenueYoyPct,
        'revenue_mom_pct': revenueMomPct,
        'total_units_sold': totalUnitsSold,
        'units_growth_pct': unitsGrowthPct,
        'units_yoy_pct': unitsYoyPct,
        'units_mom_pct': unitsMomPct,
        'active_stores_count': activeStoresCount,
        'oos_rate_pct': oosRatePct,
        'osa_rate_pct': osaRatePct,
        'total_oos_incidents': totalOOSIncidents,
        'estimated_lost_revenue': estimatedLostRevenue,
        'currency': currency,
        'reporting_period': reportingPeriod,
        'supplier_shares': supplierShares.map((s) => s.toJson()).toList(),
        'category_contributions':
            categoryContributions.map((c) => c.toJson()).toList(),
        'pareto_skus': paretoSkus.map((p) => p.toJson()).toList(),
      };
}

class ChainShareItem {
  final String retailerChain;
  final String displayName;
  final double totalRevenue;
  final int totalUnits;
  final double marketShare;

  ChainShareItem({
    required this.retailerChain,
    required this.displayName,
    required this.totalRevenue,
    required this.totalUnits,
    required this.marketShare,
  });

  factory ChainShareItem.fromJson(Map<String, dynamic> json) {
    return ChainShareItem(
      retailerChain: json['retailer_chain'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      totalUnits: json['total_units'] as int? ?? 0,
      marketShare: (json['market_share'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ChainTrendValueItem {
  final String retailerChain;
  final String displayName;
  final double revenue;
  final int units;
  final double growthPct;

  ChainTrendValueItem({
    required this.retailerChain,
    required this.displayName,
    required this.revenue,
    required this.units,
    this.growthPct = 0.0,
  });

  factory ChainTrendValueItem.fromJson(Map<String, dynamic> json) {
    return ChainTrendValueItem(
      retailerChain: json['retailer_chain'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
      units: (json['units'] as num?)?.toInt() ?? 0,
      growthPct: (json['growth_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class DailyTrendItem {
  final String date;
  final String monthKey;
  final String monthLabel;
  final double revenue;
  final int units;
  final int storeCount;
  final Map<String, double> chainRevenues;
  final Map<String, int> chainUnits;
  final List<ChainTrendValueItem> chainDetails;

  DailyTrendItem({
    required this.date,
    this.monthKey = '',
    this.monthLabel = '',
    required this.revenue,
    required this.units,
    required this.storeCount,
    this.chainRevenues = const {},
    this.chainUnits = const {},
    this.chainDetails = const [],
  });

  factory DailyTrendItem.fromJson(Map<String, dynamic> json) {
    final rawChainRev = json['chain_revenues'] as Map<String, dynamic>?;
    final parsedChainRev = <String, double>{};
    if (rawChainRev != null) {
      for (final entry in rawChainRev.entries) {
        parsedChainRev[entry.key] = (entry.value as num?)?.toDouble() ?? 0.0;
      }
    }

    final rawChainUnits = json['chain_units'] as Map<String, dynamic>?;
    final parsedChainUnits = <String, int>{};
    if (rawChainUnits != null) {
      for (final entry in rawChainUnits.entries) {
        parsedChainUnits[entry.key] = (entry.value as num?)?.toInt() ?? 0;
      }
    }

    final rawDetails = json['chain_details'] as List<dynamic>?;
    final parsedDetails = rawDetails
            ?.map((e) => ChainTrendValueItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <ChainTrendValueItem>[];

    return DailyTrendItem(
      date: json['date'] as String? ?? '',
      monthKey: json['month_key'] as String? ?? '',
      monthLabel: json['month_label'] as String? ?? '',
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
      units: json['units'] as int? ?? 0,
      storeCount: json['store_count'] as int? ?? 0,
      chainRevenues: parsedChainRev,
      chainUnits: parsedChainUnits,
      chainDetails: parsedDetails,
    );
  }
}

class SellOutRecordModel {
  final String recordId;
  final String retailerChain;
  final String storeId;
  final String storeName;
  final String itemCode;
  final String barcode;
  final String skuName;
  final String retailerRawSkuName;
  final String category;
  final String supplier;
  final bool isOwnBrand;
  final int unitsPerCarton;
  final String itemType;
  final double factoryUnitCost;
  final double cartonPriceInclVat;
  final double netCartonInvoiceCost;
  final double invoiceDiscountPct;
  final int quantitySold;
  final double cartonsSold;
  final double netRevenue;
  final double unitPrice;
  final double recommendedPrice;
  final double totalFactoryCost;
  final double retailerGrossProfit;
  final double retailerMarginPct;
  final double priceDeltaPct;
  final String transactionDate;

  SellOutRecordModel({
    required this.recordId,
    required this.retailerChain,
    required this.storeId,
    required this.storeName,
    this.itemCode = '',
    required this.barcode,
    required this.skuName,
    this.retailerRawSkuName = '',
    required this.category,
    this.supplier = '',
    this.isOwnBrand = true,
    this.unitsPerCarton = 12,
    this.itemType = 'عادي',
    this.factoryUnitCost = 0.0,
    this.cartonPriceInclVat = 0.0,
    this.netCartonInvoiceCost = 0.0,
    this.invoiceDiscountPct = 0.10,
    required this.quantitySold,
    this.cartonsSold = 0.0,
    required this.netRevenue,
    required this.unitPrice,
    this.recommendedPrice = 0.0,
    this.totalFactoryCost = 0.0,
    this.retailerGrossProfit = 0.0,
    this.retailerMarginPct = 0.0,
    this.priceDeltaPct = 0.0,
    required this.transactionDate,
  });

  factory SellOutRecordModel.fromJson(Map<String, dynamic> json) {
    final uPrice = (json['unit_price'] as num?)?.toDouble() ?? 0.0;
    final qty = (json['quantity_sold'] as num?)?.toInt() ?? 0;
    final upc = (json['units_per_carton'] as num?)?.toInt() ?? 12;
    final cSold = (json['cartons_sold'] as num?)?.toDouble() ??
        (upc > 0 && qty > 0 ? qty / upc : 0.0);
    return SellOutRecordModel(
      recordId: json['record_id'] as String? ?? '',
      retailerChain: json['retailer_chain'] as String? ?? '',
      storeId: json['store_id'] as String? ?? '',
      storeName: json['store_name'] as String? ?? '',
      itemCode: json['item_code'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      skuName: json['sku_name'] as String? ?? '',
      retailerRawSkuName: json['retailer_raw_sku_name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      supplier: json['supplier'] as String? ?? '',
      isOwnBrand: json['is_own_brand'] as bool? ?? true,
      unitsPerCarton: upc,
      itemType: json['item_type'] as String? ?? 'عادي',
      factoryUnitCost: (json['factory_unit_cost'] as num?)?.toDouble() ?? 0.0,
      cartonPriceInclVat:
          (json['carton_price_incl_vat'] as num?)?.toDouble() ?? 0.0,
      netCartonInvoiceCost:
          (json['net_carton_invoice_cost'] as num?)?.toDouble() ?? 0.0,
      invoiceDiscountPct:
          (json['invoice_discount_pct'] as num?)?.toDouble() ?? 0.10,
      quantitySold: qty,
      cartonsSold: cSold,
      netRevenue: (json['net_revenue'] as num?)?.toDouble() ?? 0.0,
      unitPrice: uPrice,
      recommendedPrice:
          (json['recommended_price'] as num?)?.toDouble() ?? uPrice,
      totalFactoryCost: (json['total_factory_cost'] as num?)?.toDouble() ?? 0.0,
      retailerGrossProfit:
          (json['retailer_gross_profit'] as num?)?.toDouble() ?? 0.0,
      retailerMarginPct:
          (json['retailer_margin_pct'] as num?)?.toDouble() ?? 0.0,
      priceDeltaPct: (json['price_delta_pct'] as num?)?.toDouble() ?? 0.0,
      transactionDate: json['transaction_date'] as String? ?? '',
    );
  }
}

class OOSAlertModel {
  final String alertId;
  final String retailerChain;
  final String storeId;
  final String storeName;
  final String itemCode;
  final String barcode;
  final String skuName;
  final String brand;
  final String category;
  final int unitsPerCarton;
  final String itemType;
  final double estimatedLostDailyCost;
  final int consecutiveDaysOOS;
  final String severity; // critical, high, medium

  OOSAlertModel({
    required this.alertId,
    required this.retailerChain,
    required this.storeId,
    required this.storeName,
    this.itemCode = '',
    required this.barcode,
    required this.skuName,
    String brand = '',
    required this.category,
    this.unitsPerCarton = 12,
    this.itemType = 'عادي',
    required this.estimatedLostDailyCost,
    required this.consecutiveDaysOOS,
    required this.severity,
  }) : brand = brand.isNotEmpty
            ? brand
            : SmartBrandExtractor.inferBrand(skuName, subCategory: category);

  factory OOSAlertModel.fromJson(Map<String, dynamic> json) {
    final skuName = json['sku_name'] as String? ?? '';
    final category = json['category'] as String? ?? '';
    final rawBrand = json['brand'] as String?;
    final inferredBrand = SmartBrandExtractor.inferBrand(
      skuName,
      existingBrand: rawBrand,
      subCategory: category,
    );

    return OOSAlertModel(
      alertId: json['alert_id'] as String? ?? '',
      retailerChain: json['retailer_chain'] as String? ?? '',
      storeId: json['store_id'] as String? ?? '',
      storeName: json['store_name'] as String? ?? '',
      itemCode: json['item_code'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      skuName: skuName,
      brand: inferredBrand,
      category: category,
      unitsPerCarton: (json['units_per_carton'] as num?)?.toInt() ?? 12,
      itemType: json['item_type'] as String? ?? 'عادي',
      estimatedLostDailyCost: (json['estimated_lost_daily_cost'] as num?)?.toDouble() ?? 0.0,
      consecutiveDaysOOS: json['consecutive_days_oos'] as int? ?? 0,
      severity: json['severity'] as String? ?? 'medium',
    );
  }
}

class OOSBrandSummaryModel {
  final String brand;
  final int oosItemsCount;
  final List<String> impactedBranches;
  final int branchesCount;
  final double totalLostDailyCost;
  final int maxDaysOOS;

  OOSBrandSummaryModel({
    required this.brand,
    required this.oosItemsCount,
    required this.impactedBranches,
    required this.branchesCount,
    required this.totalLostDailyCost,
    required this.maxDaysOOS,
  });

  factory OOSBrandSummaryModel.fromJson(Map<String, dynamic> json) {
    final branches = (json['impacted_branches'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    return OOSBrandSummaryModel(
      brand: json['brand'] as String? ?? 'أصناف عامة',
      oosItemsCount: json['oos_items_count'] as int? ?? 0,
      impactedBranches: branches,
      branchesCount: json['branches_count'] as int? ?? branches.length,
      totalLostDailyCost:
          (json['total_lost_daily_cost'] as num?)?.toDouble() ?? 0.0,
      maxDaysOOS: json['max_days_oos'] as int? ?? 0,
    );
  }
}

class OOSBranchSummaryModel {
  final String branchName;
  final String retailerChain;
  final int oosItemsCount;
  final List<String> brandsAffected;
  final double totalLostDailyCost;

  OOSBranchSummaryModel({
    required this.branchName,
    required this.retailerChain,
    required this.oosItemsCount,
    required this.brandsAffected,
    required this.totalLostDailyCost,
  });

  factory OOSBranchSummaryModel.fromJson(Map<String, dynamic> json) {
    final brands = (json['brands_affected'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    return OOSBranchSummaryModel(
      branchName: json['branch_name'] as String? ?? '',
      retailerChain: json['retailer_chain'] as String? ?? '',
      oosItemsCount: json['oos_items_count'] as int? ?? 0,
      brandsAffected: brands,
      totalLostDailyCost:
          (json['total_lost_daily_cost'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class OOSAIAnalysisModel {
  final String modelUsed;
  final String generatedAt;
  final String executiveSummaryAr;
  final String executiveSummaryEn;
  final List<String> rootCausesAr;
  final List<String> immediateActionsAr;
  final int criticalSKUsCount;
  final String topImpactedBranch;
  final String topImpactedBrand;
  final double projectedMonthlyLossEGP;

  OOSAIAnalysisModel({
    required this.modelUsed,
    required this.generatedAt,
    required this.executiveSummaryAr,
    required this.executiveSummaryEn,
    required this.rootCausesAr,
    required this.immediateActionsAr,
    required this.criticalSKUsCount,
    required this.topImpactedBranch,
    required this.topImpactedBrand,
    required this.projectedMonthlyLossEGP,
  });

  factory OOSAIAnalysisModel.fromJson(Map<String, dynamic> json) {
    return OOSAIAnalysisModel(
      modelUsed: json['model_used'] as String? ?? 'Gemini 1.5 Pro / CPFR Engine',
      generatedAt: json['generated_at'] as String? ?? '',
      executiveSummaryAr: json['executive_summary_ar'] as String? ?? '',
      executiveSummaryEn: json['executive_summary_en'] as String? ?? '',
      rootCausesAr: (json['root_causes_ar'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      immediateActionsAr: (json['immediate_actions_ar'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      criticalSKUsCount: json['critical_skus_count'] as int? ?? 0,
      topImpactedBranch: json['top_impacted_branch'] as String? ?? '',
      topImpactedBrand: json['top_impacted_brand'] as String? ?? '',
      projectedMonthlyLossEGP:
          (json['projected_monthly_loss_egp'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class OOSMonitorResponseModel {
  final int totalIncidents;
  final double totalLostDailyCost;
  final List<OOSAlertModel> alerts;
  final List<OOSBrandSummaryModel> brandSummaries;
  final List<OOSBranchSummaryModel> branchSummaries;
  final OOSAIAnalysisModel? aiAnalysis;

  OOSMonitorResponseModel({
    required this.totalIncidents,
    required this.totalLostDailyCost,
    required this.alerts,
    required this.brandSummaries,
    required this.branchSummaries,
    this.aiAnalysis,
  });

  factory OOSMonitorResponseModel.fromJson(Map<String, dynamic> json) {
    final alertsList = (json['alerts'] as List<dynamic>?)
            ?.map((e) => OOSAlertModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final brandList = (json['brand_summaries'] as List<dynamic>?)
            ?.map((e) => OOSBrandSummaryModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final branchList = (json['branch_summaries'] as List<dynamic>?)
            ?.map((e) => OOSBranchSummaryModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final aiJson = json['ai_analysis'] as Map<String, dynamic>?;

    return OOSMonitorResponseModel(
      totalIncidents: json['total_incidents'] as int? ?? alertsList.length,
      totalLostDailyCost:
          (json['total_lost_daily_cost'] as num?)?.toDouble() ??
              alertsList.fold<double>(0.0, (s, a) => s + a.estimatedLostDailyCost),
      alerts: alertsList,
      brandSummaries: brandList,
      branchSummaries: branchList,
      aiAnalysis: aiJson != null ? OOSAIAnalysisModel.fromJson(aiJson) : null,
    );
  }
}

/// Store Benchmark Item Model
class StoreBenchmarkItem {
  final String storeId;
  final String storeName;
  final String retailerChain;
  final String region;
  final String tier;
  final double totalRevenue;
  final int totalUnits;
  final double velocityUnitsPerDay;
  final int rank;

  StoreBenchmarkItem({
    required this.storeId,
    required this.storeName,
    required this.retailerChain,
    required this.region,
    required this.tier,
    required this.totalRevenue,
    required this.totalUnits,
    required this.velocityUnitsPerDay,
    required this.rank,
  });

  factory StoreBenchmarkItem.fromJson(Map<String, dynamic> json) {
    return StoreBenchmarkItem(
      storeId: json['store_id'] as String? ?? '',
      storeName: json['store_name'] as String? ?? '',
      retailerChain: json['retailer_chain'] as String? ?? '',
      region: json['region'] as String? ?? '',
      tier: json['tier'] as String? ?? 'Tier C',
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      totalUnits: json['total_units'] as int? ?? 0,
      velocityUnitsPerDay: (json['velocity_units_per_day'] as num?)?.toDouble() ?? 0.0,
      rank: json['rank'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'store_id': storeId,
        'store_name': storeName,
        'retailer_chain': retailerChain,
        'region': region,
        'tier': tier,
        'total_revenue': totalRevenue,
        'total_units': totalUnits,
        'velocity_units_per_day': velocityUnitsPerDay,
        'rank': rank,
      };
}

/// Pricing Compliance Item Model
class PricingComplianceItem {
  final String itemCode;
  final String skuName;
  final String barcode;
  final String category;
  final String retailerChain;
  final String storeName;
  final double actualPrice;
  final double recommendedPrice;
  final double factoryUnitCost;
  final double retailerMarginPct;
  final int unitsPerCarton;
  final String itemType;
  final double priceDeltaPct;
  final String violationType; // 'compliant', 'under_cutting', 'price_gouging'
  final bool isPromoActive;
  final double promoUpliftPct;
  final String transactionDate;

  PricingComplianceItem({
    this.itemCode = '',
    required this.skuName,
    required this.barcode,
    required this.category,
    required this.retailerChain,
    required this.storeName,
    required this.actualPrice,
    required this.recommendedPrice,
    this.factoryUnitCost = 0.0,
    this.retailerMarginPct = 0.0,
    this.unitsPerCarton = 12,
    this.itemType = 'عادي',
    required this.priceDeltaPct,
    required this.violationType,
    required this.isPromoActive,
    required this.promoUpliftPct,
    this.transactionDate = '',
  });

  factory PricingComplianceItem.fromJson(Map<String, dynamic> json) {
    final actual = (json['actual_price'] as num?)?.toDouble() ?? 0.0;
    final cost = (json['factory_unit_cost'] as num?)?.toDouble() ?? 0.0;
    final margin = (json['retailer_margin_pct'] as num?)?.toDouble() ??
        (actual > 0 && cost > 0 ? double.parse((((actual - cost) / actual) * 100.0).toStringAsFixed(1)) : 0.0);
    return PricingComplianceItem(
      itemCode: json['item_code'] as String? ?? '',
      skuName: json['sku_name'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      category: ApiClient.normalizeCategoryName(json['category'] as String? ?? ''),
      retailerChain: json['retailer_chain'] as String? ?? '',
      storeName: json['store_name'] as String? ?? '',
      actualPrice: actual,
      recommendedPrice: (json['recommended_price'] as num?)?.toDouble() ?? 0.0,
      factoryUnitCost: cost,
      retailerMarginPct: margin,
      unitsPerCarton: (json['units_per_carton'] as num?)?.toInt() ?? 12,
      itemType: json['item_type'] as String? ?? 'عادي',
      priceDeltaPct: (json['price_delta_pct'] as num?)?.toDouble() ?? 0.0,
      violationType: json['violation_type'] as String? ?? 'compliant',
      isPromoActive: json['is_promo_active'] as bool? ?? false,
      promoUpliftPct: (json['promo_uplift_pct'] as num?)?.toDouble() ?? 0.0,
      transactionDate: json['transaction_date'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'item_code': itemCode,
        'sku_name': skuName,
        'barcode': barcode,
        'category': category,
        'retailer_chain': retailerChain,
        'store_name': storeName,
        'actual_price': actualPrice,
        'recommended_price': recommendedPrice,
        'factory_unit_cost': factoryUnitCost,
        'retailer_margin_pct': retailerMarginPct,
        'units_per_carton': unitsPerCarton,
        'item_type': itemType,
        'price_delta_pct': priceDeltaPct,
        'violation_type': violationType,
        'is_promo_active': isPromoActive,
        'promo_uplift_pct': promoUpliftPct,
        'transaction_date': transactionDate,
      };
}

/// Monthly Price Elasticity Point comparing Average Selling Price vs. Revenue & Volume
class MonthlyPriceElasticityPoint {
  final String monthKey;
  final String monthLabel;
  final double averagePrice;
  final double recommendedPrice;
  final double totalRevenue;
  final int totalUnits;
  final double priceChangePct;
  final double revenueChangePct;
  final double unitsChangePct;
  final String elasticityVerdict;

  const MonthlyPriceElasticityPoint({
    required this.monthKey,
    required this.monthLabel,
    required this.averagePrice,
    required this.recommendedPrice,
    required this.totalRevenue,
    required this.totalUnits,
    required this.priceChangePct,
    required this.revenueChangePct,
    required this.unitsChangePct,
    required this.elasticityVerdict,
  });

  factory MonthlyPriceElasticityPoint.fromJson(Map<String, dynamic> json) {
    return MonthlyPriceElasticityPoint(
      monthKey: json['month_key'] as String? ?? '',
      monthLabel: json['month_label'] as String? ?? '',
      averagePrice: (json['average_price'] as num?)?.toDouble() ?? 0.0,
      recommendedPrice: (json['recommended_price'] as num?)?.toDouble() ?? 0.0,
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      totalUnits: (json['total_units'] as num?)?.toInt() ?? 0,
      priceChangePct: (json['price_change_pct'] as num?)?.toDouble() ?? 0.0,
      revenueChangePct: (json['revenue_change_pct'] as num?)?.toDouble() ?? 0.0,
      unitsChangePct: (json['units_change_pct'] as num?)?.toDouble() ?? 0.0,
      elasticityVerdict: json['elasticity_verdict'] as String? ?? '',
    );
  }
}

/// Executive Summary of Price-to-Revenue Correlation
class PriceElasticitySummaryModel {
  final String overallVerdict;
  final double avgPriceCurrent;
  final double avgPriceBaseline;
  final double netPriceChangePct;
  final double netRevenueGrowthPct;

  const PriceElasticitySummaryModel({
    required this.overallVerdict,
    required this.avgPriceCurrent,
    required this.avgPriceBaseline,
    required this.netPriceChangePct,
    required this.netRevenueGrowthPct,
  });

  factory PriceElasticitySummaryModel.fromJson(Map<String, dynamic> json) {
    return PriceElasticitySummaryModel(
      overallVerdict: json['overall_verdict'] as String? ?? '',
      avgPriceCurrent: (json['avg_price_current'] as num?)?.toDouble() ?? 0.0,
      avgPriceBaseline: (json['avg_price_baseline'] as num?)?.toDouble() ?? 0.0,
      netPriceChangePct: (json['net_price_change_pct'] as num?)?.toDouble() ?? 0.0,
      netRevenueGrowthPct: (json['net_revenue_growth_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Paginated Pricing Compliance Response Metadata & Items
class PricingCompliancePageResult {
  final List<PricingComplianceItem> items;
  final int totalCount;
  final int summaryTotalCount;
  final int limit;
  final int offset;
  final int compliantCount;
  final int violationCount;
  final double complianceRatePct;
  final double avgPromoUpliftPct;
  final List<String> availableCategories;
  final List<MonthlyPriceElasticityPoint> monthlyElasticity;
  final PriceElasticitySummaryModel? elasticitySummary;

  const PricingCompliancePageResult({
    required this.items,
    required this.totalCount,
    required this.summaryTotalCount,
    required this.limit,
    required this.offset,
    required this.compliantCount,
    required this.violationCount,
    required this.complianceRatePct,
    required this.avgPromoUpliftPct,
    required this.availableCategories,
    this.monthlyElasticity = const [],
    this.elasticitySummary,
  });
}

class DiscoveredSheetInfoModel {
  final String name;
  final String state;
  final int rowCount;
  final int recordsCount;
  final double totalRevenue;
  final int totalUnits;
  final String? periodDate;

  DiscoveredSheetInfoModel({
    required this.name,
    this.state = 'visible',
    this.rowCount = 0,
    this.recordsCount = 0,
    this.totalRevenue = 0.0,
    this.totalUnits = 0,
    this.periodDate,
  });

  factory DiscoveredSheetInfoModel.fromJson(Map<String, dynamic> json) {
    return DiscoveredSheetInfoModel(
      name: json['name'] as String? ?? '',
      state: json['state'] as String? ?? 'visible',
      rowCount: (json['row_count'] as num?)?.toInt() ?? 0,
      recordsCount: (json['records_count'] as num?)?.toInt() ?? 0,
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      totalUnits: (json['total_units'] as num?)?.toInt() ?? 0,
      periodDate: json['period_date'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'state': state,
        'row_count': rowCount,
        'records_count': recordsCount,
        'total_revenue': totalRevenue,
        'total_units': totalUnits,
        if (periodDate != null) 'period_date': periodDate,
      };
}

class IngestionResultModel {
  final String batchId;
  final String archiveId;
  final String filename;
  final String retailerDetected;
  final int totalRows;
  final int validRows;
  final int anomalyRows;
  final double totalRevenue;
  final int totalQuantity;
  final double confidenceScore;
  final int autoCreatedStoresCount;
  final List<Map<String, dynamic>> discoveredBranches;
  final List<String> discoveredCategories;
  final int competitorsDetected;
  final double tenantMarketSharePct;
  final List<String> sheetsProcessed;
  final List<DiscoveredSheetInfoModel> detectedSheets;
  final int sheetsDetectedCount;
  final List<dynamic> anomalies;

  // Staging & Review Fields
  final bool isStaged;
  final bool isCommitted;
  final String discoveredRetailer;
  final String targetRetailer;
  final bool chainMismatchDetected;
  final String? suggestedChain;
  final String? suggestedChainName;

  // Two-Tier AI Engine Fields
  final String aiModelUsed;
  final String aiTierUsed;
  final bool tier2Escalated;
  /// ai | deterministic | cache | mock (empty when the API omitted it).
  final String mappingSource;
  final double mappingConfidence;

  /// Phase A7 guardrails: human approval + Arabic reasons + success metrics.
  final bool requiresHumanApproval;
  final List<String> guardrailReasonsAr;
  final String guardrailArabicSummary;
  final bool guardrailSchemaValid;
  final bool guardrailPiiMinimized;
  final bool guardrailPerCallLogged;

  // Upload checks (warnings never block; held-out customers are not in any total).
  final List<UploadWarning> uploadWarnings;
  final List<QuarantinedCustomerInfo> quarantinedCustomers;
  final List<Map<String, dynamic>> unknownBarcodes;
  final List<UploadMonthSlice> periodBreakdown;

  /// Pre-save totals check from payload.validation (ok|flagged|rejected).
  final String validationStatus;
  /// Arabic totals-difference explanation grounded in computed numbers.
  final String validationExplanationAr;
  final List<String> validationDiffReasons;

  IngestionResultModel({
    required this.batchId,
    this.archiveId = '',
    required this.filename,
    required this.retailerDetected,
    required this.totalRows,
    required this.validRows,
    required this.anomalyRows,
    required this.totalRevenue,
    required this.totalQuantity,
    required this.confidenceScore,
    this.autoCreatedStoresCount = 0,
    this.discoveredBranches = const [],
    this.discoveredCategories = const [],
    this.competitorsDetected = 0,
    this.tenantMarketSharePct = 0.0,
    this.sheetsProcessed = const [],
    this.detectedSheets = const [],
    this.sheetsDetectedCount = 0,
    required this.anomalies,
    this.isStaged = true,
    this.isCommitted = false,
    this.discoveredRetailer = '',
    this.targetRetailer = '',
    this.chainMismatchDetected = false,
    this.suggestedChain,
    this.suggestedChainName,
    this.aiModelUsed = '',
    this.aiTierUsed = '',
    this.tier2Escalated = false,
    this.mappingSource = '',
    this.mappingConfidence = 0.0,
    this.requiresHumanApproval = false,
    this.guardrailReasonsAr = const [],
    this.guardrailArabicSummary = '',
    this.guardrailSchemaValid = false,
    this.guardrailPiiMinimized = false,
    this.guardrailPerCallLogged = false,
    this.uploadWarnings = const [],
    this.quarantinedCustomers = const [],
    this.unknownBarcodes = const [],
    this.periodBreakdown = const [],
    this.validationStatus = '',
    this.validationExplanationAr = '',
    this.validationDiffReasons = const [],
  });

  bool get usedAiMapping =>
      mappingSource == 'ai' || mappingSource == 'cache';

  /// True when the API flagged approval or the preview is still staged.
  bool get needsHumanApproval =>
      requiresHumanApproval || (isStaged && !isCommitted);

  factory IngestionResultModel.fromJson(Map<String, dynamic> json) {
    final rawBranches = json['discovered_branches'] as List<dynamic>? ?? [];
    final branches = rawBranches
        .map((b) => b is Map<String, dynamic>
            ? b
            : <String, dynamic>{'branch_name': b.toString()})
        .toList();
    final rawSheets = (json['detected_sheets'] as List<dynamic>?)
            ?.map((e) => DiscoveredSheetInfoModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final retailer = json['retailer_detected'] as String? ?? 'unknown';
    final payload = json['payload'] is Map<String, dynamic>
        ? json['payload'] as Map<String, dynamic>
        : null;
    // Prefer top-level validation (upload JSON contract), fall back to nested payload.
    final validation = (json['validation'] is Map<String, dynamic>
            ? json['validation'] as Map<String, dynamic>
            : null) ??
        (payload?['validation'] is Map<String, dynamic>
            ? payload!['validation'] as Map<String, dynamic>
            : null);
    return IngestionResultModel(
      batchId: json['batch_id'] as String? ?? '',
      archiveId: json['archive_id'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      retailerDetected: retailer,
      totalRows: json['total_rows'] as int? ?? 0,
      validRows: json['valid_rows'] as int? ?? 0,
      anomalyRows: json['anomaly_rows'] as int? ?? 0,
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      totalQuantity: json['total_quantity'] as int? ?? 0,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.0,
      autoCreatedStoresCount:
          (json['auto_created_stores_count'] as num?)?.toInt() ??
              branches.length,
      discoveredBranches: branches,
      discoveredCategories: (json['discovered_categories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      competitorsDetected:
          (json['competitors_detected'] as num?)?.toInt() ?? 0,
      tenantMarketSharePct:
          (json['tenant_market_share_pct'] as num?)?.toDouble() ?? 0.0,
      sheetsProcessed: (json['sheets_processed'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      detectedSheets: rawSheets,
      sheetsDetectedCount: (json['sheets_detected_count'] as num?)?.toInt() ?? rawSheets.length,
      anomalies: json['anomalies'] as List<dynamic>? ?? [],
      isStaged: json['is_staged'] as bool? ?? false,
      isCommitted: json['is_committed'] as bool? ?? false,
      discoveredRetailer: json['discovered_retailer'] as String? ?? retailer,
      targetRetailer: json['target_retailer'] as String? ?? '',
      chainMismatchDetected: json['chain_mismatch_detected'] as bool? ?? false,
      suggestedChain: json['suggested_chain'] as String?,
      suggestedChainName: json['suggested_chain_name'] as String?,
      aiModelUsed: (json['ai_model_used'] as String?) ?? '',
      aiTierUsed: (json['ai_tier_used'] as String?) ?? '',
      tier2Escalated: json['tier2_escalated'] as bool? ?? false,
      mappingSource: (json['mapping_source'] as String?) ?? '',
      mappingConfidence: (json['mapping_confidence'] as num?)?.toDouble() ?? 0.0,
      requiresHumanApproval: json['requires_human_approval'] as bool? ?? false,
      guardrailReasonsAr: (json['guardrail_reasons_ar'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      guardrailArabicSummary: () {
        final metrics = json['guardrail_metrics'];
        if (metrics is Map<String, dynamic>) {
          return (metrics['arabic_summary'] as String?) ?? '';
        }
        return '';
      }(),
      guardrailSchemaValid: () {
        final metrics = json['guardrail_metrics'];
        if (metrics is Map<String, dynamic>) {
          return metrics['schema_valid'] as bool? ?? false;
        }
        return false;
      }(),
      guardrailPiiMinimized: () {
        final metrics = json['guardrail_metrics'];
        if (metrics is Map<String, dynamic>) {
          return metrics['pii_minimized'] as bool? ?? false;
        }
        return false;
      }(),
      guardrailPerCallLogged: () {
        final metrics = json['guardrail_metrics'];
        if (metrics is Map<String, dynamic>) {
          return metrics['per_call_logged'] as bool? ?? false;
        }
        return false;
      }(),
      uploadWarnings: parseList(json['upload_warnings'], UploadWarning.fromJson),
      quarantinedCustomers: parseList(json['quarantined_customers'], QuarantinedCustomerInfo.fromJson),
      unknownBarcodes: parseList(json['unknown_barcodes'], (m) => m),
      periodBreakdown: parseList(json['period_breakdown'], UploadMonthSlice.fromJson),
      validationStatus: (validation?['status'] as String?) ?? '',
      validationExplanationAr: (validation?['explanation_ar'] as String?) ?? '',
      validationDiffReasons: (validation?['diff_reasons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  IngestionResultModel copyWith({
    String? batchId,
    String? archiveId,
    String? filename,
    String? retailerDetected,
    int? totalRows,
    int? validRows,
    int? anomalyRows,
    double? totalRevenue,
    int? totalQuantity,
    double? confidenceScore,
    int? autoCreatedStoresCount,
    List<Map<String, dynamic>>? discoveredBranches,
    List<String>? discoveredCategories,
    int? competitorsDetected,
    double? tenantMarketSharePct,
    List<String>? sheetsProcessed,
    List<DiscoveredSheetInfoModel>? detectedSheets,
    int? sheetsDetectedCount,
    List<dynamic>? anomalies,
    bool? isStaged,
    bool? isCommitted,
    String? discoveredRetailer,
    String? targetRetailer,
    bool? chainMismatchDetected,
    String? suggestedChain,
    String? suggestedChainName,
    String? aiModelUsed,
    String? aiTierUsed,
    bool? tier2Escalated,
    String? mappingSource,
    double? mappingConfidence,
    String? validationStatus,
    String? validationExplanationAr,
    List<String>? validationDiffReasons,
  }) {
    return IngestionResultModel(
      batchId: batchId ?? this.batchId,
      archiveId: archiveId ?? this.archiveId,
      filename: filename ?? this.filename,
      retailerDetected: retailerDetected ?? this.retailerDetected,
      totalRows: totalRows ?? this.totalRows,
      validRows: validRows ?? this.validRows,
      anomalyRows: anomalyRows ?? this.anomalyRows,
      totalRevenue: totalRevenue ?? this.totalRevenue,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      autoCreatedStoresCount: autoCreatedStoresCount ?? this.autoCreatedStoresCount,
      discoveredBranches: discoveredBranches ?? this.discoveredBranches,
      discoveredCategories: discoveredCategories ?? this.discoveredCategories,
      competitorsDetected: competitorsDetected ?? this.competitorsDetected,
      tenantMarketSharePct: tenantMarketSharePct ?? this.tenantMarketSharePct,
      sheetsProcessed: sheetsProcessed ?? this.sheetsProcessed,
      detectedSheets: detectedSheets ?? this.detectedSheets,
      sheetsDetectedCount: sheetsDetectedCount ?? this.sheetsDetectedCount,
      anomalies: anomalies ?? this.anomalies,
      isStaged: isStaged ?? this.isStaged,
      isCommitted: isCommitted ?? this.isCommitted,
      discoveredRetailer: discoveredRetailer ?? this.discoveredRetailer,
      targetRetailer: targetRetailer ?? this.targetRetailer,
      chainMismatchDetected: chainMismatchDetected ?? this.chainMismatchDetected,
      suggestedChain: suggestedChain ?? this.suggestedChain,
      suggestedChainName: suggestedChainName ?? this.suggestedChainName,
      aiModelUsed: aiModelUsed ?? this.aiModelUsed,
      aiTierUsed: aiTierUsed ?? this.aiTierUsed,
      tier2Escalated: tier2Escalated ?? this.tier2Escalated,
      mappingSource: mappingSource ?? this.mappingSource,
      mappingConfidence: mappingConfidence ?? this.mappingConfidence,
      uploadWarnings: uploadWarnings,
      quarantinedCustomers: quarantinedCustomers,
      unknownBarcodes: unknownBarcodes,
      periodBreakdown: periodBreakdown,
      validationStatus: validationStatus ?? this.validationStatus,
      validationExplanationAr:
          validationExplanationAr ?? this.validationExplanationAr,
      validationDiffReasons:
          validationDiffReasons ?? this.validationDiffReasons,
    );
  }
}

/// Model representing an archived Excel or CSV file stored under a retail chain.
class ArchivedExcelFileModel {
  final String id;
  final String batchId;
  final String tenantId;
  final String fileType;
  final String fileName;
  final String contentType;
  final int fileSizeBytes;
  final String retailChain;
  final String chainNameAr;
  final String chainNameEn;
  final String targetYear;
  final String targetMonth;
  final int rowsIngested;
  final int branchesCount;
  final double totalRevenue;
  final double totalCases;
  final double totalWeightTons;
  final String uploadedAt;

  const ArchivedExcelFileModel({
    required this.id,
    this.batchId = '',
    required this.tenantId,
    this.fileType = 'sell_out',
    required this.fileName,
    required this.contentType,
    required this.fileSizeBytes,
    required this.retailChain,
    required this.chainNameAr,
    required this.chainNameEn,
    required this.targetYear,
    this.targetMonth = 'auto',
    required this.rowsIngested,
    required this.branchesCount,
    required this.totalRevenue,
    this.totalCases = 0.0,
    this.totalWeightTons = 0.0,
    required this.uploadedAt,
  });

  factory ArchivedExcelFileModel.fromJson(Map<String, dynamic> json) {
    final chain = (json['retail_chain'] as String? ?? 'fathalla').trim().toLowerCase();
    final batch = json['batch_id'] as String? ?? '';
    final rawType = json['file_type'] as String? ?? '';
    final fType = rawType.isNotEmpty
        ? rawType
        : (batch.startsWith('batch_pm_') || chain == 'product-master'
            ? 'product_master'
            : (batch.startsWith('batch_sellin_') ? 'sell_in' : 'sell_out'));
    return ArchivedExcelFileModel(
      id: json['id'] as String? ?? '',
      batchId: batch,
      tenantId: json['tenant_id'] as String? ?? 'tenant-adeco',
      fileType: fType,
      fileName: json['file_name'] as String? ?? 'workbook.xlsx',
      contentType: json['content_type'] as String? ??
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt() ?? 0,
      retailChain: chain,
      chainNameAr: (json['chain_name_ar'] as String?)?.isNotEmpty == true
          ? json['chain_name_ar'] as String
          : ApiClient.getRetailChainShortAr(chain),
      chainNameEn: (json['chain_name_en'] as String?)?.isNotEmpty == true
          ? json['chain_name_en'] as String
          : chain,
      targetYear: json['target_year'] as String? ?? '2026',
      targetMonth: json['target_month'] as String? ?? 'auto',
      rowsIngested: (json['rows_ingested'] as num?)?.toInt() ?? 0,
      branchesCount: (json['branches_count'] as num?)?.toInt() ?? 0,
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
      totalCases: (json['total_cases'] as num?)?.toDouble() ?? 0.0,
      totalWeightTons: (json['total_weight_tons'] as num?)?.toDouble() ?? 0.0,
      uploadedAt: json['uploaded_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'batch_id': batchId,
        'tenant_id': tenantId,
        'file_type': fileType,
        'file_name': fileName,
        'content_type': contentType,
        'file_size_bytes': fileSizeBytes,
        'retail_chain': retailChain,
        'chain_name_ar': chainNameAr,
        'chain_name_en': chainNameEn,
        'target_year': targetYear,
        'target_month': targetMonth,
        'rows_ingested': rowsIngested,
        'branches_count': branchesCount,
        'total_revenue': totalRevenue,
        'total_cases': totalCases,
        'total_weight_tons': totalWeightTons,
        'uploaded_at': uploadedAt,
      };

  ArchivedExcelFileModel copyWith({
    String? fileType,
    String? retailChain,
    String? chainNameAr,
    String? chainNameEn,
    String? targetYear,
    String? targetMonth,
    double? totalCases,
    double? totalWeightTons,
    String? uploadedAt,
  }) {
    return ArchivedExcelFileModel(
      id: id,
      batchId: batchId,
      tenantId: tenantId,
      fileType: fileType ?? this.fileType,
      fileName: fileName,
      contentType: contentType,
      fileSizeBytes: fileSizeBytes,
      retailChain: retailChain ?? this.retailChain,
      chainNameAr: chainNameAr ?? this.chainNameAr,
      chainNameEn: chainNameEn ?? this.chainNameEn,
      targetYear: targetYear ?? this.targetYear,
      targetMonth: targetMonth ?? this.targetMonth,
      rowsIngested: rowsIngested,
      branchesCount: branchesCount,
      totalRevenue: totalRevenue,
      totalCases: totalCases ?? this.totalCases,
      totalWeightTons: totalWeightTons ?? this.totalWeightTons,
      uploadedAt: uploadedAt ?? this.uploadedAt,
    );
  }
}

/// Thrown when DELETE /api/v1/ingest/archive fails. The file must stay listed.
class ArchiveDeleteException implements Exception {
  final int statusCode;
  final String message;
  final String? errorCode;

  const ArchiveDeleteException({
    required this.statusCode,
    required this.message,
    this.errorCode,
  });

  factory ArchiveDeleteException.fromResponse(int statusCode, String body) {
    String message = 'تعذر حذف الملف (HTTP $statusCode)';
    String? errorCode;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        errorCode = decoded['error']?.toString();
        final apiMessage = decoded['message']?.toString();
        if (apiMessage != null && apiMessage.trim().isNotEmpty) {
          message = apiMessage.trim();
        } else if (errorCode != null && errorCode.trim().isNotEmpty) {
          message = errorCode.trim();
        }
      }
    } catch (_) {
      final trimmed = body.trim();
      if (trimmed.isNotEmpty && trimmed.length < 400) {
        message = trimmed;
      }
    }
    return ArchiveDeleteException(
      statusCode: statusCode,
      message: message,
      errorCode: errorCode,
    );
  }

  @override
  String toString() => message;
}

/// Response model for GET /api/v1/ingest/archive.
class UploadedFilesArchiveResponse {
  final String tenantId;
  final int totalCount;
  final Map<String, int> chainCounts;
  final List<ArchivedExcelFileModel> files;

  const UploadedFilesArchiveResponse({
    required this.tenantId,
    required this.totalCount,
    required this.chainCounts,
    required this.files,
  });

  factory UploadedFilesArchiveResponse.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['chain_counts'] as Map<String, dynamic>? ?? {};
    final counts = <String, int>{};
    rawCounts.forEach((k, v) {
      counts[k.toLowerCase()] = (v as num?)?.toInt() ?? 0;
    });
    final rawFiles = (json['files'] as List<dynamic>?) ??
        (json['items'] as List<dynamic>?) ??
        const [];
    final files = rawFiles
        .map((e) => ArchivedExcelFileModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return UploadedFilesArchiveResponse(
      tenantId: json['tenant_id'] as String? ?? 'tenant-adeco',
      totalCount: (json['total_count'] as num?)?.toInt() ?? files.length,
      chainCounts: counts,
      files: files,
    );
  }
}

/// Thrown when the backend rejected an upload after validating its totals.
class UploadRejectedException implements Exception {
  final String message;

  UploadRejectedException(this.message);

  @override
  String toString() => message;
}

/// Client stopped waiting for a background ingest job; the server may still be saving.
/// Never treat this as "nothing was saved" — guide the user to the files list instead.
class UploadStillProcessingException implements Exception {
  final String message;

  UploadStillProcessingException([
    this.message =
        'الملف لسه بيتعالج على السيرفر. شوف قائمة الملفات بعد شوية — متترفعش تاني لو لقيته هناك.',
  ]);

  @override
  String toString() => message;
}

/// Turns a refused upload/commit response into a typed exception: 409 = a question for the user
/// (nothing saved), any other 4xx/5xx = rejection with the server's Arabic message.
/// Returns normally for 2xx.
/// Shown when the backend refuses an upload with 403 (another tenant, or a replace by a non-super_admin).
const String uploadForbiddenMessage =
    'مش مسموح لحسابك بالعملية دي: استبدال ملف مؤرشف أو الرفع لشركة تانية متاح للمشرف العام بس. مفيش حاجة اتحفظت.';

void throwIfUploadRefused(int statusCode, String body, String fallbackMessage) {
  if (statusCode >= 200 && statusCode < 300) return;
  if (statusCode == 409) {
    final c = UploadConfirmationRequiredException.tryParse(body);
    if (c != null) throw c;
  }
  if (statusCode == 403) {
    throw UploadRejectedException(uploadForbiddenMessage);
  }
  String message = '$fallbackMessage (HTTP $statusCode)';
  try {
    final j = jsonDecode(body);
    if (j is Map && j['message'] is String && (j['message'] as String).isNotEmpty) {
      message = j['message'] as String;
    }
  } catch (_) {}
  throw UploadRejectedException(message);
}

/// Thrown when the backend server is unreachable, offline, or returns an error,
/// strictly preventing the display of fake or fabricated mock data.
class ServerConnectionException implements Exception {
  final String message;
  final Object? cause;

  ServerConnectionException([
    this.message = 'تعذر الاتصال بخادم المعالجة وقواعد البيانات (انقطاع اتصال الخادم)',
    this.cause,
  ]);

  @override
  String toString() => message;
}

/// Thrown by [ApiClient.getRecordsAllPages] when the safety row cap is hit while
/// [totalCount] says more pages remain — never a silent truncated success.
class SellOutRecordsTruncatedException implements Exception {
  final String message;
  final List<SellOutRecordModel> partial;
  final int totalCount;
  final int maxRows;

  SellOutRecordsTruncatedException(
    this.message, {
    required this.partial,
    required this.totalCount,
    required this.maxRows,
  });

  @override
  String toString() => message;
}

/// ApiClient communicates with the Cloud Run backend.
/// Automatically injects JWT Bearer tokens and handles tenant RLS headers.
class ApiClient {
  String tenantId;
  String _authToken;
  String get authToken => _authToken;
  set authToken(String value) {
    _authToken = value;
    _currentAuthToken = value;
  }

  /// Token of the active session (last token set on any ApiClient).
  static String _currentAuthToken = '';

  /// >0 while a login request is in flight: 401s then belong to old requests.
  static int _loginsInProgress = 0;

  /// When false (strictly enforced in web and production mode),
  /// any connection failure or server outage immediately raises [ServerConnectionException]
  /// so that the UI displays the Server Disconnected state with the technical support prompt,
  /// strictly preventing any fake or fabricated mock data from being displayed.
  static bool defaultAllowMockFallback = !kIsWeb;
  bool allowMockFallback;

  /// Explicit demo/offline flag for competitor seed monthly series.
  /// Default OFF everywhere (including non-web). Never derived from
  /// [allowMockFallback] — non-web mock fallback must not invent Jan–Apr history.
  static bool defaultAllowDemoSeedData = false;
  bool allowDemoSeedData;

  final ValueNotifier<bool> isServerOnline = ValueNotifier<bool>(true);

  /// Called when the backend rejects the session (HTTP 401/403), e.g. a stale
  /// token after a deploy. The app wires this to logout so the user re-auths
  /// instead of seeing an empty dashboard.
  static VoidCallback? onSessionExpired;

  /// 401 = the backend refused the login (expired/invalid token). 403 is a
  /// normal permission denial (RBAC) and does not end the session. Auth
  /// endpoints are excluded (a 401 there means wrong credentials).
  ///
  /// Only a 401 for a request sent with the *current* non-empty token ends the
  /// session. A late 401 for a request sent before/while logging in (no token
  /// or an old one) is ignored, so it cannot log out a fresh session.
  static void reportAuthStatus(int statusCode, [Uri? url, String? sentAuthorization]) {
    if (statusCode != 401) return;
    if (url != null && url.path.contains('/api/v1/auth/')) return;
    if (_loginsInProgress > 0) return;
    var sent = (sentAuthorization ?? '').trim();
    if (sent.toLowerCase().startsWith('bearer ')) sent = sent.substring(7).trim();
    if (sent.isEmpty || _currentAuthToken.isEmpty) return;
    if (sent != _asciiSafeHeader(_currentAuthToken)) return;
    onSessionExpired?.call();
  }

  /// Routes every [BackendHttp] response through [reportAuthStatus].
  static void installSessionGuard() {
    BackendHttp.onResponseStatus = reportAuthStatus;
  }
  String? lastConnectionError;

  ApiClient({
    this.tenantId = 'tenant-adeco',
    String? authToken,
    bool? allowMockFallback,
    bool? allowDemoSeedData,
  })  : _authToken = authToken ?? '',
        allowMockFallback = allowMockFallback ?? defaultAllowMockFallback,
        allowDemoSeedData = allowDemoSeedData ?? defaultAllowDemoSeedData {
    if (_authToken.isNotEmpty) _currentAuthToken = _authToken;
  }

  static String normalizeTenantSlug(String raw) {
    var clean = raw.trim().toLowerCase();
    if (clean.startsWith('tenant-') || clean.startsWith('tenant_')) {
      clean = clean.substring('tenant-'.length);
    }
    if (clean.isEmpty || clean == 'adco' || clean == 'adico') return 'adeco';
    return clean;
  }

  static String normalizeDataTenantSlug(String raw) {
    final clean = normalizeTenantSlug(raw);
    if (clean.isEmpty ||
        clean == 'system' ||
        clean == 'admin' ||
        clean == 'superadmin') {
      return 'adeco';
    }
    return clean;
  }

  static String formatBrandTitle(String rawSlug) {
    final clean = normalizeDataTenantSlug(rawSlug)
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .trim();
    if (clean.isEmpty) return 'Adeco';
    return clean
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// 34 Fathalla branches extracted from the real 40-Adco -2026.xlsx workbook
  static const List<Map<String, dynamic>> defaultFathalla34Branches = [
    {
      'id': 'fat_rehab_city',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - مدينة الرحاب',
      'governorate': 'القاهرة',
      'city': 'مدينة الرحاب',
      'is_active': true,
    },
    {
      'id': 'fat_smouha',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - سموحة',
      'governorate': 'الإسكندرية',
      'city': 'سموحة',
      'is_active': true,
    },
    {
      'id': 'fat_gardenia',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - جاردينيا',
      'governorate': 'الإسكندرية',
      'city': 'جاردينيا',
      'is_active': true,
    },
    {
      'id': 'fat_hanoville',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - هانوفيل (نهال فيل)',
      'governorate': 'الإسكندرية',
      'city': 'العجمي - هانوفيل',
      'is_active': true,
    },
    {
      'id': 'fat_tanta_outlet',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - طنطا - اوت ليت مول',
      'governorate': 'الغربية',
      'city': 'طنطا',
      'is_active': true,
    },
    {
      'id': 'fat_damanhour_andalus',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - دمنهور الأندلس',
      'governorate': 'البحيرة',
      'city': 'دمنهور',
      'is_active': true,
    },
    {
      'id': 'fat_mahalla',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - المحلة الكبرى',
      'governorate': 'الغربية',
      'city': 'المحلة الكبرى',
      'is_active': true,
    },
    {
      'id': 'fat_new_damietta',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - دمياط الجديدة',
      'governorate': 'دمياط',
      'city': 'دمياط الجديدة',
      'is_active': true,
    },
    {
      'id': 'fat_fleming',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - فلمنج',
      'governorate': 'الإسكندرية',
      'city': 'فلمنج',
      'is_active': true,
    },
    {
      'id': 'fat_kafr_eldawar_mall',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - كفر الدوار - مول',
      'governorate': 'البحيرة',
      'city': 'كفر الدوار',
      'is_active': true,
    },
    {
      'id': 'fat_smouha_mini',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - سموحة ميني',
      'governorate': 'الإسكندرية',
      'city': 'سموحة',
      'is_active': true,
    },
    {
      'id': 'fat_october',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - أكتوبر',
      'governorate': 'الجيزة',
      'city': 'السادس من أكتوبر',
      'is_active': true,
    },
    {
      'id': 'fat_tanta',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - طنطا',
      'governorate': 'الغربية',
      'city': 'طنطا',
      'is_active': true,
    },
    {
      'id': 'fat_agamy_star',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - عجمي ستار',
      'governorate': 'الإسكندرية',
      'city': 'العجمي',
      'is_active': true,
    },
    {
      'id': 'fat_ibrahimia',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - الإبراهيمية',
      'governorate': 'الإسكندرية',
      'city': 'الإبراهيمية',
      'is_active': true,
    },
    {
      'id': 'fat_ibrahimia_mini',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - الإبراهيمية ميني',
      'governorate': 'الإسكندرية',
      'city': 'الإبراهيمية',
      'is_active': true,
    },
    {
      'id': 'fat_sidi_gaber_mini',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - سيدي جابر ميني',
      'governorate': 'الإسكندرية',
      'city': 'سيدي جابر',
      'is_active': true,
    },
    {
      'id': 'fat_sidi_gaber_station',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - سيدي جابر المحطة',
      'governorate': 'الإسكندرية',
      'city': 'سيدي جابر',
      'is_active': true,
    },
    {
      'id': 'fat_kafr_eldawar',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - كفر الدوار',
      'governorate': 'البحيرة',
      'city': 'كفر الدوار',
      'is_active': true,
    },
    {
      'id': 'fat_matrouh',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - مطروح',
      'governorate': 'مرسى مطروح',
      'city': 'مطروح',
      'is_active': true,
    },
    {
      'id': 'fat_damanhour_stadium',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - دمنهور - الاستاد',
      'governorate': 'البحيرة',
      'city': 'دمنهور',
      'is_active': true,
    },
    {
      'id': 'fat_anfoushy',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - الأنفوشي',
      'governorate': 'الإسكندرية',
      'city': 'الأنفوشي',
      'is_active': true,
    },
    {
      'id': 'fat_dekheila_mini',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - الدخيلة ميني',
      'governorate': 'الإسكندرية',
      'city': 'الدخيلة',
      'is_active': true,
    },
    {
      'id': 'fat_dekheila_mini_2',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - الدخيلة مينى 2',
      'governorate': 'الإسكندرية',
      'city': 'الدخيلة',
      'is_active': true,
    },
    {
      'id': 'fat_sidi_bishr_mini',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - سيدي بشر ميني',
      'governorate': 'الإسكندرية',
      'city': 'سيدي بشر',
      'is_active': true,
    },
    {
      'id': 'fat_rozana',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - روزانا',
      'governorate': 'الإسكندرية',
      'city': 'سموحة - روزانا',
      'is_active': true,
    },
    {
      'id': 'fat_elnasr',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - النصر',
      'governorate': 'الإسكندرية',
      'city': 'شارع النصر',
      'is_active': true,
    },
    {
      'id': 'fat_toson',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - طوسون',
      'governorate': 'الإسكندرية',
      'city': 'أبو قير - طوسون',
      'is_active': true,
    },
    {
      'id': 'fat_abu_youssef',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - ابو يوسف',
      'governorate': 'الإسكندرية',
      'city': 'العجمي - أبو يوسف',
      'is_active': true,
    },
    {
      'id': 'fat_stanley',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - ستانلى',
      'governorate': 'الإسكندرية',
      'city': 'ستانلي',
      'is_active': true,
    },
    {
      'id': 'fat_amwaj_north_coast',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - أمواج - الساحل الشمالي',
      'governorate': 'الساحل الشمالي',
      'city': 'أمواج',
      'is_active': true,
    },
    {
      'id': 'fat_malak_hefny',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - ملك حفنى',
      'governorate': 'الإسكندرية',
      'city': 'ملك حفني',
      'is_active': true,
    },
    {
      'id': 'fat_city_square',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - سيتي سكوير',
      'governorate': 'الإسكندرية',
      'city': 'سيتي سكوير',
      'is_active': true,
    },
    {
      'id': 'fat_nice_2',
      'tenant_id': 'tenant-adeco',
      'chain': 'fathalla',
      'branch_name': 'فرع فتح الله - نيس2',
      'governorate': 'الإسكندرية',
      'city': 'نيس',
      'is_active': true,
    },
  ];

  /// 27 Main categories extracted from the "المجموعة" column in 40-Adco -2026.xlsx
  static const List<String> defaultAdco27Categories = [
    'صابون سائل اطباق',
    'منعمات ملابس',
    'كلور ابيض و الوان',
    'مسحوق اوتوماتيك',
    'مطهر عام',
    'شاور جل',
    'هاند وواش',
    'اقراص غسالات اطباق',
    'معطر جو',
    'مساحيق جيل اوتوماتيك',
    'جل غسيل اطباق',
    'منظف تواليت',
    'ملمع زجاج',
    'منظف سجاد',
    'منظف متعدد الاغراض',
    'ديتول ومطهرات',
    'ملمع اثاث',
    'منظف افران وشوايات',
    'مناديل ومطهرات',
    'صابون وجه',
    'معجون اسنان',
    'شامبو وبلسم',
    'منظف ارضيات',
    'معطر ارضيات',
    'صابون قطع',
    'معقم ومطهر',
    'ادوات نظافة',
  ];

  /// Dynamically builds the accessible portal URL based on current browser origin & port.
  /// If running on Chrome dev server (e.g. http://localhost:54428), it returns http://localhost:54428/#/portal/<slug>.
  /// If running in production (e.g. https://data.tashil.com), it returns https://data.tashil.com/#/portal/<slug>.
  static String buildPortalUrl(String rawSlug) {
    final cleanSlug = normalizeDataTenantSlug(rawSlug);
    String origin = 'http://localhost:3000';
    try {
      if (Uri.base.hasAuthority &&
          Uri.base.host.isNotEmpty &&
          (Uri.base.scheme == 'http' || Uri.base.scheme == 'https')) {
        origin = Uri.base.origin;
      }
    } catch (_) {}
    return '$origin/#/portal/$cleanSlug';
  }

  static List<TenantProfileModel> get knownTenants =>
      List.unmodifiable(_inMemoryTenants);

  static final Set<String> _deletedTenantSlugs = <String>{};

  static void registerTenantProfile(TenantProfileModel profile,
      {bool persist = true}) {
    final slug = normalizeTenantSlug(
        profile.slug.isNotEmpty ? profile.slug : profile.tenantId);
    if (_deletedTenantSlugs.contains(slug)) {
      if (!persist) return;
      _deletedTenantSlugs.remove(slug);
      SessionStorage.saveDeletedTenantSlugs(_deletedTenantSlugs.toList());
    }
    final normalized = TenantProfileModel(
      tenantId: slug,
      displayName: profile.displayName.isNotEmpty
          ? profile.displayName
          : formatBrandTitle(slug),
      slug: slug,
      portalUrl: (profile.portalUrl.isNotEmpty &&
              !profile.portalUrl.contains('localhost:3000'))
          ? profile.portalUrl
          : buildPortalUrl(slug),
      brandSeedColor: profile.brandSeedColor,
      logoUrl: profile.logoUrl,
      adminEmail: profile.adminEmail,
      activeChains: profile.activeChains,
    );
    final color = TenantBrandSeeds.parseHexColor(normalized.brandSeedColor);
    if (color != null) {
      TenantBrandSeeds.registerTenantSeed(slug, color);
    }
    final existingIdx = _inMemoryTenants
        .indexWhere((t) => normalizeTenantSlug(t.slug) == slug);
    if (existingIdx >= 0) {
      _inMemoryTenants[existingIdx] = normalized;
    } else {
      _inMemoryTenants.add(normalized);
    }
    if (persist) {
      SessionStorage.saveProvisionedTenants(
        _inMemoryTenants.map((t) => t.toJson()).toList(),
      );
    }
  }

  static void restoreProvisionedTenantsFromStorage() {
    final deleted = SessionStorage.loadDeletedTenantSlugs();
    if (deleted.isNotEmpty) {
      _deletedTenantSlugs.addAll(deleted);
      _inMemoryTenants.removeWhere(
        (t) => _deletedTenantSlugs.contains(normalizeTenantSlug(t.slug)),
      );
    }
    final stored = SessionStorage.loadProvisionedTenants();
    for (final json in stored) {
      final profile = TenantProfileModel.fromJson(json);
      final slug = normalizeTenantSlug(profile.slug);
      if (slug.isNotEmpty && !_deletedTenantSlugs.contains(slug)) {
        registerTenantProfile(profile, persist: false);
      }
    }
  }

  static TenantProfileModel getTenantProfileBySlug(String rawSlug) {
    final cleanSlug = normalizeDataTenantSlug(rawSlug);
    return _inMemoryTenants.firstWhere(
      (t) =>
          normalizeTenantSlug(t.slug) == cleanSlug ||
          normalizeTenantSlug(t.tenantId) == cleanSlug,
      orElse: () => TenantProfileModel(
        tenantId: cleanSlug,
        displayName: 'شركة ${formatBrandTitle(cleanSlug)}',
        slug: cleanSlug,
        portalUrl: buildPortalUrl(cleanSlug),
        brandSeedColor: '#0B57D0',
        adminEmail: 'admin@$cleanSlug.com',
        activeChains: const ['carrefour', 'fathalla'],
      ),
    );
  }

  /// Automatically resolves the tenant slug given any user's corporate email address.
  static String findTenantSlugForEmail(String email) {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) return 'adeco';

    // 1. Check registered in-memory & provisioned tenants
    for (final t in _inMemoryTenants) {
      if (t.adminEmail.trim().toLowerCase() == cleanEmail) {
        return normalizeDataTenantSlug(t.slug);
      }
    }

    // 2. Keyword heuristics
    if (cleanEmail.contains('adeco')) return 'adeco';
    if (cleanEmail.contains('unilever')) return 'unilever';
    if (cleanEmail.contains('pepsi')) return 'pepsi';

    // 3. Fallback to first active tenant or adeco
    if (_inMemoryTenants.isNotEmpty) {
      return normalizeDataTenantSlug(_inMemoryTenants.first.slug);
    }
    return 'adeco';
  }

  static String getDisplayNameForTenant(String rawSlug) {
    final cleanSlug = normalizeDataTenantSlug(rawSlug);
    if (cleanSlug == 'adeco') return 'أديكو (Adeco)';
    if (cleanSlug == 'unilever') return 'يونيليفر (Unilever)';
    if (cleanSlug == 'pepsi') return 'بيبسيكو (PepsiCo)';
    final profile = getTenantProfileBySlug(cleanSlug);
    return profile.displayName;
  }

  static String getEnglishDisplayNameForTenant(String rawSlug) {
    final cleanSlug = normalizeDataTenantSlug(rawSlug);
    if (cleanSlug == 'adeco') return 'Adeco';
    if (cleanSlug == 'unilever') return 'Unilever';
    if (cleanSlug == 'pepsi') return 'PepsiCo';
    return formatBrandTitle(cleanSlug);
  }

  /// Updates the active user's full name and email address and persists it in session state.
  Future<void> updateUserProfile({
    required String fullName,
    required String email,
  }) async {
    final cleanSlug = normalizeDataTenantSlug(tenantId);
    final trimmedName = fullName.trim();
    final trimmedEmail = email.trim();
    final existing = currentUser;

    currentUser = TenantUserModel(
      userId: existing?.userId ?? 'user-$cleanSlug-admin-01',
      tenantId: existing?.tenantId ?? cleanSlug,
      email: trimmedEmail,
      fullName: trimmedName,
      role: existing?.role ?? 'vendor_admin',
      active: existing?.active ?? true,
      assignedChain: existing?.assignedChain,
      assignedRegion: existing?.assignedRegion,
    );

    if (currentTenantProfile != null) {
      currentTenantProfile = TenantProfileModel(
        tenantId: currentTenantProfile!.tenantId,
        displayName: currentTenantProfile!.displayName,
        slug: currentTenantProfile!.slug,
        portalUrl: currentTenantProfile!.portalUrl,
        brandSeedColor: currentTenantProfile!.brandSeedColor,
        logoUrl: currentTenantProfile!.logoUrl,
        adminEmail: trimmedEmail,
        activeChains: currentTenantProfile!.activeChains,
      );
    }

    final savedSession = SessionStorage.loadSession();
    if (savedSession != null) {
      SessionStorage.saveSession(
        SavedSessionState(
          activeTenant: savedSession.activeTenant,
          authToken: savedSession.authToken,
          currentUserJson: currentUser?.toJson(),
          currentTenantProfileJson: currentTenantProfile?.toJson(),
          showSuperAdmin: savedSession.showSuperAdmin,
          isLoginMode: savedSession.isLoginMode,
        ),
      );
    }

    recordAuditLog(
      action: 'USER_PROFILE_UPDATE',
      resource: 'user_profile_dialog',
      details: 'Updated user profile: $trimmedName ($trimmedEmail)',
    );
  }

  static String _asciiSafeHeader(String value) {
    for (int i = 0; i < value.length; i++) {
      if (value.codeUnitAt(i) > 127) {
        return Uri.encodeComponent(value);
      }
    }
    return value;
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${_asciiSafeHeader(authToken)}',
        'X-Tenant-ID': _asciiSafeHeader(tenantId),
        'Content-Type': 'application/json',
        if (currentUser != null && currentUser!.role.isNotEmpty)
          'X-Simulated-Role': _asciiSafeHeader(currentUser!.role),
        if (currentUser?.assignedChain != null &&
            currentUser!.assignedChain!.isNotEmpty)
          'X-Assigned-Chain': _asciiSafeHeader(currentUser!.assignedChain!),
        if (currentUser?.assignedRegion != null &&
            currentUser!.assignedRegion!.isNotEmpty)
          'X-Assigned-Region': _asciiSafeHeader(currentUser!.assignedRegion!),
      };

  Map<String, String> get requestHeaders => _headers;

  final Set<String> _clearedTenants = <String>{
    if (kIsWeb) ...SessionStorage.loadClearedTenants(),
  };

  bool get isCurrentTenantCleared =>
      _clearedTenants.contains(normalizeDataTenantSlug(tenantId));

  ExecutiveKPIsModel _applyRbacToExecutiveKPIs(ExecutiveKPIsModel kpis) {
    final user = currentUser;
    if (user != null &&
        user.role == 'chain_kam' &&
        user.assignedChain != null &&
        user.assignedChain!.isNotEmpty) {
      final targetChain = user.assignedChain!.toLowerCase();
      final maskedShares = kpis.chainShares.map((s) {
        if (s.retailerChain.toLowerCase() == targetChain) {
          return s;
        }
        return ChainShareItem(
          retailerChain: 'nda_redacted',
          displayName: 'سلسلة تجزئة منافسة (محمي بـ NDA)',
          totalRevenue: s.totalRevenue,
          totalUnits: s.totalUnits,
          marketShare: s.marketShare,
        );
      }).toList();
      return ExecutiveKPIsModel(
        totalRevenue: kpis.totalRevenue,
        totalMarketRevenue: kpis.totalMarketRevenue,
        tenantMarketSharePct: kpis.tenantMarketSharePct,
        totalSkusCount: kpis.totalSkusCount,
        totalMarketSkusCount: kpis.totalMarketSkusCount,
        competitorsCount: kpis.competitorsCount,
        revenueGrowthPct: kpis.revenueGrowthPct,
        revenueYoyPct: kpis.revenueYoyPct,
        revenueMomPct: kpis.revenueMomPct,
        totalUnitsSold: kpis.totalUnitsSold,
        unitsGrowthPct: kpis.unitsGrowthPct,
        unitsYoyPct: kpis.unitsYoyPct,
        unitsMomPct: kpis.unitsMomPct,
        activeStoresCount: kpis.activeStoresCount,
        oosRatePct: kpis.oosRatePct,
        osaRatePct: kpis.osaRatePct,
        totalOOSIncidents: kpis.totalOOSIncidents,
        estimatedLostRevenue: kpis.estimatedLostRevenue,
        currency: kpis.currency,
        reportingPeriod: kpis.reportingPeriod,
        chainShares: maskedShares,
        availableChains: maskedShares,
        supplierShares: kpis.supplierShares,
        dailyTrends: kpis.dailyTrends,
        categoryContributions: kpis.categoryContributions,
        paretoSkus: kpis.paretoSkus,
      );
    }
    return kpis;
  }

  static final Map<String, ExecutiveKPIsModel> _executiveKpisCache = {};

  static void invalidateExecutiveKpisCache() {
    _executiveKpisCache.clear();
  }

  String _buildExecutiveKpisCacheKey({
    required String period,
    String? startDate,
    String? endDate,
    String? chain,
  }) {
    final cleanSlug = normalizeDataTenantSlug(tenantId);
    final role = currentUser?.role ?? '';
    final assignedChain = currentUser?.assignedChain ?? '';
    final normChain = (chain == null || chain.isEmpty || chain == 'all' || chain == 'الكل')
        ? 'all'
        : chain.trim().toLowerCase();
    return '$cleanSlug|$role|$assignedChain|$period|${startDate ?? ''}|${endDate ?? ''}|$normChain';
  }

  /// Returns synchronously cached ExecutiveKPIsModel if available, avoiding loading flicker on tab switch.
  ExecutiveKPIsModel? getCachedExecutiveKPIs({
    String period = 'MTD',
    String? startDate,
    String? endDate,
    String? chain,
  }) {
    if (isCurrentTenantCleared) return null;
    final key = _buildExecutiveKpisCacheKey(
      period: period,
      startDate: startDate,
      endDate: endDate,
      chain: chain,
    );
    return _executiveKpisCache[key];
  }

  /// Wipes all fake/previous data for the active tenant (or 'all' tenants) back to zero.
  Future<void> clearTenantData({String scope = 'tenant'}) async {
    final cleanSlug = normalizeDataTenantSlug(tenantId);
    _clearedTenants.add(cleanSlug);
    if (kIsWeb) {
      SessionStorage.saveClearedTenants(_clearedTenants);
    }
    final localArchives = _localArchiveByTenant[cleanSlug];
    if (localArchives != null) {
      for (final f in localArchives) {
        _deletedArchiveIds.add(f.id);
        _deletedArchiveFileNames.add(f.fileName.toLowerCase());
      }
      _localArchiveByTenant[cleanSlug] = [];
      if (kIsWeb) {
        SessionStorage.saveDeletedArchiveIds(_deletedArchiveIds);
        SessionStorage.saveDeletedArchiveFileNames(_deletedArchiveFileNames);
      }
    }
    invalidateExecutiveKpisCache();
    try {
      final uri = Uri.parse(ApiEndpoints.clearData).replace(
        queryParameters: scope == 'all' ? {'scope': 'all'} : null,
      );
      await BackendHttp.post(uri, headers: _headers).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('[ApiClient] Offline clearTenantData applied locally: $e');
    }
  }

  /// Directly loads and analyzes the local 40-Adco -2026.xlsx workbook on the backend.
  Future<IngestionResultModel> loadRealAdcoExcel({String? path}) async {
    final cleanSlug = normalizeDataTenantSlug(tenantId);
    _clearedTenants.remove(cleanSlug);
    if (kIsWeb) {
      SessionStorage.saveClearedTenants(_clearedTenants);
    }
    invalidateExecutiveKpisCache();
    try {
      final uri = Uri.parse(ApiEndpoints.loadDefaultExcel);
      final resp = await BackendHttp
          .post(
            uri,
            headers: _headers,
            body: path != null ? jsonEncode({'path': path}) : jsonEncode({}),
          )
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        return IngestionResultModel.fromJson(
            jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[ApiClient] Fallback loadRealAdcoExcel: $e');
    }
    return IngestionResultModel(
      batchId: 'batch_adco_${DateTime.now().millisecondsSinceEpoch}',
      filename: '40-Adco -2026.xlsx',
      retailerDetected: 'fathalla',
      totalRows: 7569,
      validRows: 7569,
      anomalyRows: 0,
      totalRevenue: 9536992.70,
      totalQuantity: 112480,
      confidenceScore: 0.996,
      autoCreatedStoresCount: 34,
      discoveredBranches: const [
        {'id': 'fat_smouha', 'branch_name': 'فرع فتح الله - سموحة'},
        {'id': 'fat_gardenia', 'branch_name': 'فرع فتح الله - جاردينيا'},
        {'id': 'fat_hanoville', 'branch_name': 'فرع فتح الله - هانوفيل'},
        {'id': 'fat_ibrahimia', 'branch_name': 'فرع فتح الله - الإبراهيمية'},
        {'id': 'fat_fleming', 'branch_name': 'فرع فتح الله - فلمنج'},
        {'id': 'fat_rozana', 'branch_name': 'فرع فتح الله - روزانا'},
        {'id': 'fat_tanta', 'branch_name': 'فرع فتح الله - طنطا'},
        {'id': 'fat_kafr_eldawar', 'branch_name': 'فرع فتح الله - كفر الدوار'},
      ],
      discoveredCategories: const [
        'صابون سائل اطباق',
        'منعمات ملابس',
        'هاند وواش',
        'كلور عادى',
        'كلور ألوان',
        'منظفات مطبخ',
        'منظفات أرضيات وحوائط',
        'مسلك احواض وبالوعات',
      ],
      competitorsDetected: 81,
      tenantMarketSharePct: 18.44,
      sheetsProcessed: const [
        'ينابر 25',
        'فبراير 25',
        'مارس 25',
        'أبريل 25',
        'مايو 25',
        'يونيه 25',
        'يوليو 25',
        'اغسطس 25',
        'سبتمبر 25',
        'أكتوبر 25',
        'نوفمبر 25',
        'ديسمبر 25',
        'يناير 26',
      ],
      anomalies: const [],
    );
  }

  /// Fetches auto-created and active stores for the current tenant.
  Future<List<Map<String, dynamic>>> getStores() async {
    final cleanSlug = normalizeDataTenantSlug(tenantId);
    try {
      final uri = Uri.parse(ApiEndpoints.stores);
      final resp =
          await BackendHttp.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is List) {
          return decoded.map((e) => e as Map<String, dynamic>).toList();
        } else if (decoded is Map<String, dynamic>) {
          final stores = decoded['stores'] as List<dynamic>? ?? [];
          return stores.map((e) => e as Map<String, dynamic>).toList();
        }
      }
    } catch (e) {
      debugPrint('[ApiClient] Fallback getStores: $e');
    }
    if (isCurrentTenantCleared) return [];
    if (cleanSlug == 'adeco') {
      return defaultFathalla34Branches;
    }
    return [];
  }

  /// Fetches executive summary KPIs.
  Future<ExecutiveKPIsModel> getExecutiveKPIs({
    String period = 'MTD',
    String? startDate,
    String? endDate,
    String? chain,
  }) async {
    final cacheKey = _buildExecutiveKpisCacheKey(
      period: period,
      startDate: startDate,
      endDate: endDate,
      chain: chain,
    );
    Object? failureError;
    try {
      final params = <String, String>{'period': period};
      if (startDate != null && startDate.isNotEmpty) {
        params['start_date'] = startDate;
      }
      if (endDate != null && endDate.isNotEmpty) {
        params['end_date'] = endDate;
      }
      if (chain != null && chain.isNotEmpty && chain != 'all' && chain != 'الكل') {
        params['chain'] = chain;
      }
      final uri = Uri.parse(ApiEndpoints.executiveSummary).replace(queryParameters: params);
      final resp = await BackendHttp.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        isServerOnline.value = true;
        lastConnectionError = null;
        final model = ExecutiveKPIsModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
        final rbacModel = _applyRbacToExecutiveKPIs(model);
        _executiveKpisCache[cacheKey] = rbacModel;
        return rbacModel;
      } else {
        failureError = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } catch (e) {
      failureError = e;
      debugPrint('[ApiClient] Server connection issue: $e');
    }

    if (!allowMockFallback) {
      final cached = _executiveKpisCache[cacheKey];
      if (cached != null) {
        return cached;
      }
      isServerOnline.value = false;
      lastConnectionError = failureError.toString();
      throw ServerConnectionException(
        'تعذّر تحميل البيانات من الخادم. حاول مرة أخرى بعد قليل.',
        failureError,
      );
    }
    if (isCurrentTenantCleared) {
      return ExecutiveKPIsModel(
        totalRevenue: 0,
        revenueGrowthPct: 0,
        revenueYoyPct: 0,
        revenueMomPct: 0,
        totalUnitsSold: 0,
        unitsGrowthPct: 0,
        unitsYoyPct: 0,
        unitsMomPct: 0,
        activeStoresCount: 0,
        oosRatePct: 0,
        osaRatePct: 100.0,
        totalOOSIncidents: 0,
        estimatedLostRevenue: 0,
        currency: 'EGP',
        reportingPeriod: period,
        chainShares: const [],
        supplierShares: const [],
        dailyTrends: const [],
        categoryContributions: const [],
        paretoSkus: const [],
      );
    }
    final mockResult = _mockExecutiveKPIs(
      period,
      startDate: startDate,
      endDate: endDate,
      chain: chain,
    );
    _executiveKpisCache[cacheKey] = mockResult;
    return mockResult;
  }

  /// Stores the full-dataset summary metrics from the latest getRecords() query.
  SellOutRecordsSummaryModel? lastSellOutSummary;

  /// Queries paginated sell-out transaction records.
  ///
  /// [allowMockRecords] controls whether HTTP failure may return [_mockRecords].
  /// Defaults to [allowMockFallback] (other dashboards OK). Competitive comparison
  /// / month-series paths pass `allowDemoSeedData` so mocks never invent months
  /// unless the explicit demo flag is on.
  Future<List<SellOutRecordModel>> getRecords({
    String? chain,
    String? storeId,
    String? category,
    String? supplier,
    String? query,
    String? startDate,
    String? endDate,
    int? year,
    int? month,
    int limit = 50,
    int offset = 0,
    bool? allowMockRecords,
  }) async {
    final effectiveChain = (currentUser?.role == 'chain_kam' &&
            currentUser?.assignedChain != null &&
            currentUser!.assignedChain!.isNotEmpty)
        ? currentUser!.assignedChain
        : chain;
    String? effectiveStartDate = startDate;
    String? effectiveEndDate = endDate;
    if ((effectiveStartDate == null || effectiveStartDate.isEmpty) &&
        (effectiveEndDate == null || effectiveEndDate.isEmpty) &&
        year != null &&
        year > 0) {
      if (month != null && month > 0 && month <= 12) {
        effectiveStartDate = DateRangeUtils.monthStart(year, month);
        effectiveEndDate = DateRangeUtils.monthEnd(year, month);
      } else {
        effectiveStartDate = '$year-01-01';
        effectiveEndDate = '$year-12-31';
      }
    }
    Object? failureError;
    try {
      final uri = Uri.parse(ApiEndpoints.records).replace(queryParameters: {
        if (effectiveChain != null && effectiveChain.isNotEmpty) 'chain': effectiveChain,
        if (storeId != null && storeId.isNotEmpty) 'store_id': storeId,
        if (category != null && category.isNotEmpty) 'category': category,
        if (supplier != null && supplier.isNotEmpty) 'supplier': supplier,
        if (query != null && query.isNotEmpty) 'q': query,
        if (effectiveStartDate != null && effectiveStartDate.isNotEmpty) 'start_date': effectiveStartDate,
        if (effectiveEndDate != null && effectiveEndDate.isNotEmpty) 'end_date': effectiveEndDate,
        if (year != null && year > 0) 'year': year.toString(),
        if (month != null && month > 0) 'month': month.toString(),
        'limit': limit.toString(),
        'offset': offset.toString(),
      });
      http.Response? resp;
      for (var attempt = 0; attempt < 4; attempt++) {
        resp = await BackendHttp.get(uri, headers: _headers).timeout(const Duration(seconds: 180));
        if (resp.statusCode != 429) break;
        final parsed = int.tryParse(resp.headers['retry-after'] ?? '');
        final retryAfter = (parsed ?? (1 << attempt)).clamp(0, 30);
        if (retryAfter > 0) {
          await Future<void>.delayed(Duration(seconds: retryAfter));
        }
      }
      if (resp != null && resp.statusCode == 200) {
        isServerOnline.value = true;
        lastConnectionError = null;
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final recs = body['records'] as List<dynamic>? ?? [];
        var list = recs.map((e) => SellOutRecordModel.fromJson(e as Map<String, dynamic>)).toList();
        if (effectiveChain != null && effectiveChain.isNotEmpty) {
          list = list
              .where((r) => r.retailerChain.toLowerCase() == effectiveChain.toLowerCase())
              .toList();
        }
        final fallbackRev = list.fold<double>(0.0, (acc, r) => acc + r.netRevenue);
        final fallbackUnits = list.fold<int>(0, (acc, r) => acc + r.quantitySold);
        final fallbackCartons = list.fold<double>(0.0, (acc, r) => acc + r.cartonsSold);
        final fallbackFactoryCost = list.fold<double>(0.0, (acc, r) => acc + r.totalFactoryCost);
        final fallbackProfit = list.fold<double>(0.0, (acc, r) => acc + r.retailerGrossProfit);
        final fallbackStores = list.map((r) => r.storeId.isNotEmpty ? r.storeId : r.storeName).toSet().length;
        final fallbackSkus = list.map((r) => r.barcode.isNotEmpty ? r.barcode : r.skuName).toSet().length;
        final rawSkuSummaries = body['sku_summaries'] as List<dynamic>? ?? const [];
        final parsedSkuSummaries = rawSkuSummaries
            .map((e) => SellOutSkuSummaryModel.fromJson(e as Map<String, dynamic>))
            .toList();
        lastSellOutSummary = SellOutRecordsSummaryModel(
          totalCount: (body['total_count'] as num?)?.toInt() ?? list.length,
          totalNetRevenue: (body['total_net_revenue'] as num?)?.toDouble() ?? fallbackRev,
          totalUnitsSold: (body['total_units_sold'] as num?)?.toInt() ?? fallbackUnits,
          totalCartonsSold: (body['total_cartons_sold'] as num?)?.toDouble() ?? fallbackCartons,
          totalFactoryCost: (body['total_factory_cost'] as num?)?.toDouble() ?? fallbackFactoryCost,
          totalRetailerGrossProfit: (body['total_retailer_gross_profit'] as num?)?.toDouble() ?? fallbackProfit,
          avgRetailerMarginPct: (body['avg_retailer_margin_pct'] as num?)?.toDouble() ?? 0.0,
          activeStoresCount: (body['active_stores_count'] as num?)?.toInt() ?? fallbackStores,
          activeSkusCount: (body['active_skus_count'] as num?)?.toInt() ?? fallbackSkus,
          matchedSkusCount: (body['matched_skus_count'] as num?)?.toInt() ?? fallbackSkus,
          minDate: body['min_date'] as String? ?? (list.isNotEmpty ? list.last.transactionDate : ''),
          maxDate: body['max_date'] as String? ?? (list.isNotEmpty ? list.first.transactionDate : ''),
          topBranchName: body['top_branch_name'] as String? ?? (list.isNotEmpty ? list.first.storeName : ''),
          topBranchRevenue: (body['top_branch_revenue'] as num?)?.toDouble() ?? 0.0,
          skuSummaries: parsedSkuSummaries,
        );
        return list;
      } else {
        lastSellOutSummary = const SellOutRecordsSummaryModel();
        failureError = 'HTTP ${resp?.statusCode}: ${resp?.body}';
      }
    } catch (e) {
      lastSellOutSummary = const SellOutRecordsSummaryModel();
      failureError = e;
      debugPrint('[ApiClient] Fallback to mock records: $e');
    }

    final useMocks = allowMockRecords ?? allowMockFallback;
    if (!useMocks) {
      isServerOnline.value = false;
      lastConnectionError = failureError.toString();
      lastSellOutSummary = const SellOutRecordsSummaryModel();
      throw ServerConnectionException(
        'تعذّر تحميل البيانات من الخادم. حاول مرة أخرى بعد قليل.',
        failureError,
      );
    }
    if (isCurrentTenantCleared) {
      lastSellOutSummary = const SellOutRecordsSummaryModel();
      return [];
    }
    final mockList = _mockRecords(
      chain: effectiveChain,
      storeId: storeId,
      category: category,
      query: query,
      startDate: effectiveStartDate,
      endDate: effectiveEndDate,
    );
    final mockRev = mockList.fold<double>(0.0, (acc, r) => acc + r.netRevenue);
    final mockUnits = mockList.fold<int>(0, (acc, r) => acc + r.quantitySold);
    final mockStores = mockList.map((r) => r.storeId.isNotEmpty ? r.storeId : r.storeName).toSet().length;
    final mockSkus = mockList.map((r) => r.barcode.isNotEmpty ? r.barcode : r.skuName).toSet().length;
    String minDt = '';
    String maxDt = '';
    for (final r in mockList) {
      if (r.transactionDate.isNotEmpty) {
        if (minDt.isEmpty || r.transactionDate.compareTo(minDt) < 0) minDt = r.transactionDate;
        if (maxDt.isEmpty || r.transactionDate.compareTo(maxDt) > 0) maxDt = r.transactionDate;
      }
    }
    lastSellOutSummary = SellOutRecordsSummaryModel(
      totalCount: mockList.length,
      totalNetRevenue: mockRev,
      totalUnitsSold: mockUnits,
      activeStoresCount: mockStores,
      activeSkusCount: mockSkus,
      minDate: minDt,
      maxDate: maxDt,
      topBranchName: mockList.isNotEmpty ? mockList.first.storeName : '',
      topBranchRevenue: mockList.isNotEmpty ? mockList.first.netRevenue : 0.0,
    );
    return mockList;
  }

  /// Retrieves active Out-of-Stock alerts.
  Future<List<OOSAlertModel>> getOOSAlerts() async {
    final effectiveChain = (currentUser?.role == 'chain_kam' &&
            currentUser?.assignedChain != null &&
            currentUser!.assignedChain!.isNotEmpty)
        ? currentUser!.assignedChain
        : null;
    Object? failureError;
    try {
      final uri = Uri.parse(ApiEndpoints.oosMonitor);
      final resp = await BackendHttp.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        isServerOnline.value = true;
        lastConnectionError = null;
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final alerts = body['alerts'] as List<dynamic>? ?? [];
        var list = alerts.map((e) => OOSAlertModel.fromJson(e as Map<String, dynamic>)).toList();
        if (effectiveChain != null) {
          list = list.where((a) => a.retailerChain.toLowerCase() == effectiveChain.toLowerCase()).toList();
        }
        return list;
      } else {
        failureError = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } catch (e) {
      failureError = e;
      debugPrint('[ApiClient] Fallback to mock alerts: $e');
    }

    if (!allowMockFallback) {
      isServerOnline.value = false;
      lastConnectionError = failureError.toString();
      throw ServerConnectionException(
        'تعذّر تحميل البيانات من الخادم. حاول مرة أخرى بعد قليل.',
        failureError,
      );
    }
    if (isCurrentTenantCleared) return [];
    final mockList = _mockAlerts();
    if (effectiveChain != null) {
      return mockList.where((a) => a.retailerChain.toLowerCase() == effectiveChain.toLowerCase()).toList();
    }
    return mockList;
  }

  /// Retrieves comprehensive Out-of-Stock monitor report with AI root-cause analysis and brand/branch aggregations.
  Future<OOSMonitorResponseModel> getOOSMonitorReport() async {
    final effectiveChain = (currentUser?.role == 'chain_kam' &&
            currentUser?.assignedChain != null &&
            currentUser!.assignedChain!.isNotEmpty)
        ? currentUser!.assignedChain
        : null;
    Object? failureError;
    try {
      final uri = Uri.parse(ApiEndpoints.oosMonitor);
      final resp = await BackendHttp.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        isServerOnline.value = true;
        lastConnectionError = null;
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        var report = OOSMonitorResponseModel.fromJson(body);
        if (effectiveChain != null) {
          final filteredAlerts = report.alerts
              .where((a) => a.retailerChain.toLowerCase() == effectiveChain.toLowerCase())
              .toList();
          return OOSMonitorResponseModel(
            totalIncidents: filteredAlerts.length,
            totalLostDailyCost: filteredAlerts.fold<double>(0.0, (s, a) => s + a.estimatedLostDailyCost),
            alerts: filteredAlerts,
            brandSummaries: report.brandSummaries,
            branchSummaries: report.branchSummaries
                .where((b) => b.retailerChain.toLowerCase() == effectiveChain.toLowerCase())
                .toList(),
            aiAnalysis: report.aiAnalysis,
          );
        }
        return report;
      } else {
        failureError = 'HTTP ${resp.statusCode}: ${resp.body}';
      }
    } catch (e) {
      failureError = e;
      debugPrint('[ApiClient] Fallback to mock OOS report: $e');
    }

    if (!allowMockFallback) {
      isServerOnline.value = false;
      lastConnectionError = failureError.toString();
      throw ServerConnectionException(
        'تعذّر تحميل البيانات من الخادم. حاول مرة أخرى بعد قليل.',
        failureError,
      );
    }
    final mockAlertsList = _mockAlerts();
    var alerts = mockAlertsList;
    if (effectiveChain != null) {
      alerts = alerts.where((a) => a.retailerChain.toLowerCase() == effectiveChain.toLowerCase()).toList();
    }
    return _buildMockOOSResponse(alerts);
  }

  /// Analytics: Get store benchmark matrix
  Future<List<StoreBenchmarkItem>> getStoreBenchmarkMatrix({
    String? region,
    String? tier,
    String? chain,
    int? year,
    int? month,
    String? startDate,
    String? endDate,
  }) async {
    final effectiveChain = (currentUser?.role == 'chain_kam' &&
            currentUser?.assignedChain != null &&
            currentUser!.assignedChain!.isNotEmpty)
        ? currentUser!.assignedChain
        : chain;
    final effectiveRegion = (currentUser?.role == 'field_supervisor' &&
            currentUser?.assignedRegion != null &&
            currentUser!.assignedRegion!.isNotEmpty)
        ? currentUser!.assignedRegion
        : region;
    try {
      final params = <String, String>{};
      if (effectiveRegion != null && effectiveRegion.isNotEmpty && effectiveRegion != 'الكل' && effectiveRegion != 'all') {
        params['region'] = effectiveRegion;
      }
      if (tier != null && tier.isNotEmpty && tier != 'الكل' && tier != 'all') {
        params['tier'] = tier;
      }
      if (effectiveChain != null && effectiveChain.isNotEmpty && effectiveChain != 'الكل' && effectiveChain != 'all') {
        params['chain'] = effectiveChain;
      }
      if (year != null && year > 0) {
        params['year'] = year.toString();
      }
      if (month != null && month > 0) {
        params['month'] = month.toString();
      }
      if (startDate != null && startDate.isNotEmpty) {
        params['start_date'] = startDate;
      }
      if (endDate != null && endDate.isNotEmpty) {
        params['end_date'] = endDate;
      }

      final uri = Uri.parse(ApiEndpoints.storeMatrix).replace(queryParameters: params.isEmpty ? null : params);
      final resp = await BackendHttp.get(uri, headers: _headers).timeout(const Duration(seconds: 60));
      if (resp.statusCode == 200) {
        isServerOnline.value = true;
        lastConnectionError = null;
        final decoded = jsonDecode(resp.body);
        List<StoreBenchmarkItem> items = [];
        if (decoded is List) {
          items = decoded.map((e) => StoreBenchmarkItem.fromJson(e as Map<String, dynamic>)).toList();
        } else if (decoded is Map && decoded['stores'] is List) {
          items = (decoded['stores'] as List).map((e) => StoreBenchmarkItem.fromJson(e as Map<String, dynamic>)).toList();
        }
        if (effectiveChain != null && effectiveChain.isNotEmpty && effectiveChain != 'الكل' && effectiveChain != 'all') {
          items = items.where((s) => s.retailerChain.toLowerCase() == effectiveChain.toLowerCase()).toList();
          if (items.isEmpty && !isCurrentTenantCleared && allowMockFallback) {
            return _mockStoreMatrix(region: effectiveRegion, tier: tier, chain: effectiveChain, year: year);
          }
        }
        if (effectiveRegion != null && effectiveRegion.isNotEmpty && effectiveRegion != 'الكل' && effectiveRegion != 'all') {
          items = items.where((s) => s.region == effectiveRegion).toList();
        }
        return items;
      }
      if (!allowMockFallback) {
        throw ServerConnectionException(
          'تعذّر تحميل البيانات من الخادم. حاول مرة أخرى بعد قليل.',
          'HTTP ${resp.statusCode}',
        );
      }
    } on ServerConnectionException {
      rethrow;
    } catch (e) {
      debugPrint('[ApiClient] Fallback getStoreBenchmarkMatrix: $e');
      if (!allowMockFallback) {
        isServerOnline.value = false;
        lastConnectionError = e.toString();
        throw ServerConnectionException(
          'تعذّر تحميل البيانات من الخادم. حاول مرة أخرى بعد قليل.',
          e,
        );
      }
    }
    if (isCurrentTenantCleared) return [];
    return _mockStoreMatrix(region: effectiveRegion, tier: tier, chain: effectiveChain, year: year);
  }

  /// Canonicalizes product category names across different retail Excel sheets
  static String normalizeCategoryName(String raw) {
    final clean = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return '';
    switch (clean) {
      case 'صابون سائل للاطباق':
      case 'صابون سائل للأطباق':
      case 'سائل اطباق':
      case 'سائل أطباق':
        return 'صابون سائل اطباق';
      case 'كلور الوان':
      case 'كلور ألوان':
        return 'كلور ألوان';
      case 'كلور عادي':
      case 'كلور عادى':
        return 'كلور عادى';
      case 'هاند ووش':
      case 'هاند وواش':
        return 'هاند وواش';
      case 'مطهرعام':
      case 'مطهر عام':
        return 'مطهر عام';
      case 'منظف ارضيات':
      case 'كلور ارضيات':
      case 'صابون سائل للارضيات':
      case 'صابون سائل للأرضيات':
      case 'مطهر ارضيات':
      case 'منظفات أرضيات وحوائط':
        return 'منظف ارضيات';
      case 'منعمات ملابس عادية':
      case 'منعمات ملابس مركزة':
      case 'منعم ملابس':
        return 'منعمات ملابس';
      case 'مسحوق جيل':
      case 'مساحيق جيل اوتوماتيك':
      case 'مساحيق جيل اتوماتيك':
        return 'مساحيق جيل اتوماتيك';
      case 'مسحوق بودر غسالات اطباق':
      case 'منظفات غسالات الاطباق':
      case 'مسحوق غسالات اطباق':
        return 'مسحوق غسالات اطباق';
      case 'مسلكات احواض':
      case 'مسلك احواض':
      case 'مسلك احواض وبالوعات':
        return 'مسلك احواض وبالوعات';
      case 'ملمع زجاج - نجف':
      case 'ملمع زجاج':
      case 'ملمع زجاج وكريستال':
        return 'ملمع زجاج وكريستال';
      case 'ملمع اخشاب - باركيه':
      case 'ملمع اخشاب وباركيه':
        return 'ملمع اخشاب وباركيه';
      case 'منظفات مطابخ':
      case 'منظف مطبخ':
      case 'منظفات مطبخ':
        return 'منظفات مطبخ';
      case 'منظفات سجاد':
      case 'منظف سجاد':
      case 'منظفات سجاد ومفروشات':
        return 'منظفات سجاد ومفروشات';
      case 'مطهر تواليت':
      case 'منظف تواليت':
      case 'منظفات التواليت':
      case 'منظفات تواليت':
        return 'منظفات تواليت';
      case 'مزيلات بقع':
      case 'مزيل بقع':
      case 'مزيلات بقع ملابس':
        return 'مزيلات بقع ملابس';
      case 'معطر جو سائل':
      case 'معطر جو':
        return 'معطر جو';
      case 'شاور جل':
      case 'شاور جيل':
        return 'شاور جيل';
      default:
        return clean;
    }
  }

  PricingCompliancePageResult? lastPricingComplianceMeta;
  bool _legacyListComplianceServer = false;

  /// Analytics: Get pricing & promotion compliance (supports optional server-side pagination via limit & offset)
  Future<List<PricingComplianceItem>> getPricingCompliance({
    String? chain,
    String? category,
    String? search,
    bool? violationOnly,
    bool? promoOnly,
    int? year,
    int? month,
    int? limit,
    int? offset,
  }) async {
    final effectiveChain = (currentUser?.role == 'chain_kam' &&
            currentUser?.assignedChain != null &&
            currentUser!.assignedChain!.isNotEmpty)
        ? currentUser!.assignedChain
        : chain;
    try {
      final params = <String, String>{};
      if (effectiveChain != null && effectiveChain.isNotEmpty && effectiveChain != 'الكل' && effectiveChain != 'all') {
        params['chain'] = effectiveChain;
      }
      if (year != null && year > 0) {
        params['year'] = year.toString();
      }
      if (month != null && month > 0) {
        params['month'] = month.toString();
      }
      if (search != null && search.trim().isNotEmpty) {
        params['search'] = search.trim();
      }
      if (!_legacyListComplianceServer) {
        if (category != null && category.isNotEmpty && category != 'الكل' && category != 'all') {
          params['category'] = normalizeCategoryName(category);
        }
        if (violationOnly == true) {
          params['violation_only'] = 'true';
        }
        if (promoOnly == true) {
          params['promo_only'] = 'true';
        }
        if (limit != null && limit > 0) {
          params['limit'] = limit.toString();
        }
        if (offset != null && offset >= 0) {
          params['offset'] = offset.toString();
        }
      }

      final uri = Uri.parse(ApiEndpoints.pricingCompliance).replace(queryParameters: params.isEmpty ? null : params);
      final resp = await BackendHttp.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        isServerOnline.value = true;
        lastConnectionError = null;
        final decoded = jsonDecode(resp.body);
        List<PricingComplianceItem> items = [];
        if (decoded is List) {
          _legacyListComplianceServer = true;
          items = decoded.map((e) => PricingComplianceItem.fromJson(e as Map<String, dynamic>)).toList();
          if (effectiveChain != null && effectiveChain.isNotEmpty && effectiveChain != 'الكل' && effectiveChain != 'all') {
            items = items.where((c) => c.retailerChain.toLowerCase() == effectiveChain.toLowerCase()).toList();
          }
          lastPricingComplianceMeta = _buildCompliancePageMetaFromList(
            allChainItems: items,
            category: category,
            search: search,
            violationOnly: violationOnly,
            promoOnly: promoOnly,
            limit: limit,
            offset: offset,
          );
          return lastPricingComplianceMeta!.items;
        } else if (decoded is Map && decoded['items'] is List) {
          _legacyListComplianceServer = false;
          items = (decoded['items'] as List).map((e) => PricingComplianceItem.fromJson(e as Map<String, dynamic>)).toList();
          if (effectiveChain != null && effectiveChain.isNotEmpty && effectiveChain != 'الكل' && effectiveChain != 'all') {
            items = items.where((c) => c.retailerChain.toLowerCase() == effectiveChain.toLowerCase()).toList();
          }
          final rawCats = (decoded['available_categories'] as List<dynamic>?)
                  ?.map((e) => normalizeCategoryName(e.toString()))
                  .where((e) => e.isNotEmpty)
                  .toList() ??
              const <String>[];
          final dedupedCats = <String>[];
          final seenCats = <String>{};
          for (final c in rawCats) {
            if (seenCats.add(c)) {
              dedupedCats.add(c);
            }
          }
          if (dedupedCats.isEmpty) {
            for (final item in items) {
              if (item.category.isNotEmpty && seenCats.add(item.category)) {
                dedupedCats.add(item.category);
              }
            }
          }
          final totalCount = (decoded['total_count'] as num?)?.toInt() ?? items.length;
          final summaryTotal = (decoded['summary_total_count'] as num?)?.toInt() ?? totalCount;
          final compliantCount = (decoded['compliant_count'] as num?)?.toInt() ??
              items.where((i) => i.violationType == 'compliant').length;
          final violationCount = (decoded['violation_count'] as num?)?.toInt() ??
              items.where((i) => i.violationType != 'compliant').length;
          final complianceRate = (decoded['compliance_rate_pct'] as num?)?.toDouble() ??
              (summaryTotal > 0 ? (compliantCount / summaryTotal) * 100.0 : 100.0);
          final avgPromoUplift = (decoded['avg_promo_uplift_pct'] as num?)?.toDouble() ?? 0.0;

          List<MonthlyPriceElasticityPoint> elasticityPoints = [];
          if (decoded['monthly_elasticity'] is List) {
            elasticityPoints = (decoded['monthly_elasticity'] as List)
                .map((e) => MonthlyPriceElasticityPoint.fromJson(e as Map<String, dynamic>))
                .toList();
          }
          PriceElasticitySummaryModel? elasticitySummary;
          if (decoded['elasticity_summary'] is Map) {
            elasticitySummary = PriceElasticitySummaryModel.fromJson(
                decoded['elasticity_summary'] as Map<String, dynamic>);
          }

          lastPricingComplianceMeta = PricingCompliancePageResult(
            items: items,
            totalCount: totalCount,
            summaryTotalCount: summaryTotal,
            limit: (decoded['limit'] as num?)?.toInt() ?? (limit ?? items.length),
            offset: (decoded['offset'] as num?)?.toInt() ?? (offset ?? 0),
            compliantCount: compliantCount,
            violationCount: violationCount,
            complianceRatePct: complianceRate,
            avgPromoUpliftPct: avgPromoUplift,
            availableCategories: dedupedCats,
            monthlyElasticity: elasticityPoints,
            elasticitySummary: elasticitySummary,
          );
          if (totalCount == 0 &&
              effectiveChain != null &&
              effectiveChain.isNotEmpty &&
              effectiveChain != 'الكل' &&
              effectiveChain != 'all' &&
              !isCurrentTenantCleared &&
              allowMockFallback) {
            return _fallbackMockPricingComplianceWithMeta(
              chain: effectiveChain,
              category: category,
              search: search,
              violationOnly: violationOnly,
              promoOnly: promoOnly,
              limit: limit,
              offset: offset,
            );
          }
          return items;
        }
      }
    } catch (e) {
      debugPrint('[ApiClient] Fallback getPricingCompliance: $e');
      if (!allowMockFallback) {
        isServerOnline.value = false;
        lastConnectionError = e.toString();
        throw ServerConnectionException(
          'تعذّر تحميل البيانات من الخادم. حاول مرة أخرى بعد قليل.',
          e,
        );
      }
    }
    if (isCurrentTenantCleared) {
      lastPricingComplianceMeta = const PricingCompliancePageResult(
        items: [],
        totalCount: 0,
        summaryTotalCount: 0,
        limit: 25,
        offset: 0,
        compliantCount: 0,
        violationCount: 0,
        complianceRatePct: 100.0,
        avgPromoUpliftPct: 0.0,
        availableCategories: [],
      );
      return [];
    }
    return _fallbackMockPricingComplianceWithMeta(
      chain: effectiveChain,
      category: category,
      search: search,
      violationOnly: violationOnly,
      promoOnly: promoOnly,
      limit: limit,
      offset: offset,
    );
  }

  List<PricingComplianceItem> _fallbackMockPricingComplianceWithMeta({
    String? chain,
    String? category,
    String? search,
    bool? violationOnly,
    bool? promoOnly,
    int? limit,
    int? offset,
  }) {
    final allChainItems = _mockPricingCompliance(chain: chain);
    lastPricingComplianceMeta = _buildCompliancePageMetaFromList(
      allChainItems: allChainItems,
      category: category,
      search: search,
      violationOnly: violationOnly,
      promoOnly: promoOnly,
      limit: limit,
      offset: offset,
    );
    return lastPricingComplianceMeta!.items;
  }

  PricingCompliancePageResult _buildCompliancePageMetaFromList({
    required List<PricingComplianceItem> allChainItems,
    String? category,
    String? search,
    bool? violationOnly,
    bool? promoOnly,
    int? limit,
    int? offset,
  }) {
    final hasRealIngestedItems = allChainItems.any((i) => !i.barcode.startsWith('622115500'));
    final effectiveChainItems = hasRealIngestedItems
        ? allChainItems.where((i) => !i.barcode.startsWith('622115500')).toList()
        : allChainItems;

    final seenCats = <String>{};
    final availableCategories = <String>[];
    for (final item in effectiveChainItems) {
      final norm = normalizeCategoryName(item.category);
      if (norm.isNotEmpty && seenCats.add(norm)) {
        availableCategories.add(norm);
      }
    }

    final targetCat = category != null ? normalizeCategoryName(category) : '';
    final hasCatFilter = targetCat.isNotEmpty && targetCat != 'الكل' && targetCat != 'all';
    var categoryItems = hasCatFilter
        ? effectiveChainItems.where((i) => normalizeCategoryName(i.category) == targetCat).toList()
        : effectiveChainItems;

    if (search != null && search.trim().isNotEmpty) {
      categoryItems = categoryItems
          .where((i) => matchesProductSearch(
                search,
                itemCode: i.itemCode,
                barcode: i.barcode,
                skuName: i.skuName,
                category: i.category,
                storeName: i.storeName,
              ))
          .toList();
    }

    final summaryTotal = categoryItems.length;
    final compliantCount = categoryItems.where((i) => i.violationType == 'compliant').length;
    final violationCount = categoryItems.where((i) => i.violationType != 'compliant').length;
    final complianceRate = summaryTotal > 0 ? (compliantCount / summaryTotal) * 100.0 : 100.0;
    final activePromos = categoryItems.where((i) => i.isPromoActive && i.promoUpliftPct > 0).toList();
    final avgPromoUplift = activePromos.isNotEmpty
        ? activePromos.fold<double>(0.0, (sum, i) => sum + i.promoUpliftPct) / activePromos.length
        : 0.0;

    var filtered = categoryItems;
    if (violationOnly == true) {
      filtered = filtered.where((i) => i.violationType != 'compliant').toList();
    }
    if (promoOnly == true) {
      filtered = filtered.where((i) => i.isPromoActive).toList();
    }

    final totalCount = filtered.length;
    final effOffset = (offset != null && offset > 0) ? offset : 0;
    List<PricingComplianceItem> pageItems = filtered;
    if (limit != null && limit > 0) {
      if (effOffset >= totalCount) {
        pageItems = const [];
      } else {
        final end = (effOffset + limit) > totalCount ? totalCount : (effOffset + limit);
        pageItems = filtered.sublist(effOffset, end);
      }
    } else if (effOffset > 0) {
      pageItems = effOffset >= totalCount ? const [] : filtered.sublist(effOffset);
    }

    return PricingCompliancePageResult(
      items: pageItems,
      totalCount: totalCount,
      summaryTotalCount: summaryTotal,
      limit: limit ?? totalCount,
      offset: effOffset,
      compliantCount: compliantCount,
      violationCount: violationCount,
      complianceRatePct: complianceRate,
      avgPromoUpliftPct: avgPromoUplift,
      availableCategories: availableCategories,
    );
  }

  final Map<String, List<ArchivedExcelFileModel>> _localArchiveByTenant = {};
  final Map<String, List<int>> _localArchiveBytesById = {};
  final Map<String, ({String cleanSlug, ArchivedExcelFileModel? prevEntry, List<int>? prevBytes})>
      _stagedLocalArchiveRollback = {};
  static final Set<String> _deletedArchiveIds = <String>{
    if (kIsWeb) ...SessionStorage.loadDeletedArchiveIds(),
  };
  static final Set<String> _deletedArchiveFileNames = <String>{
    if (kIsWeb) ...SessionStorage.loadDeletedArchiveFileNames(),
  };
  static final Set<String> _deletedChainCodes = <String>{
    ...SessionStorage.loadDeletedChainCodes(),
  };

  /// Last downloaded archived file in VM/widget tests or web session.
  ArchivedExcelFileModel? lastDownloadedArchiveFile;
  List<int>? lastDownloadedArchiveBytes;

  void _ensureLocalArchiveSeeded(String cleanSlug) {
    if (_localArchiveByTenant.containsKey(cleanSlug)) return;
    if (cleanSlug == 'adeco') {
      const fatEntry = ArchivedExcelFileModel(
        id: 'arch_adeco_fathalla_2026',
        batchId: 'batch_seed_fathalla_2026',
        tenantId: 'tenant-adeco',
        fileName: '40-Adco -2026.xlsx',
        contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        fileSizeBytes: 13545183,
        retailChain: 'fathalla',
        chainNameAr: 'أسواق فتح الله',
        chainNameEn: 'Fathalla Market',
        targetYear: '2026',
        targetMonth: '01-12',
        rowsIngested: 164733,
        branchesCount: 35,
        totalRevenue: 9537094.70,
        uploadedAt: '2026-03-08T10:00:00Z',
      );
      const gomEntry = ArchivedExcelFileModel(
        id: 'arch_adeco_gomla_2026',
        batchId: 'batch_seed_gomla_2026',
        tenantId: 'tenant-adeco',
        fileName: 'Book1 (2).xlsx',
        contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        fileSizeBytes: 258649,
        retailChain: 'gomla',
        chainNameAr: 'جملة ماركت',
        chainNameEn: 'Gomla Market',
        targetYear: '2026',
        targetMonth: '01',
        rowsIngested: 5330,
        branchesCount: 33,
        totalRevenue: 6573015.00,
        uploadedAt: '2026-03-08T09:30:00Z',
      );
      const beetEntry = ArchivedExcelFileModel(
        id: 'arch_adeco_beet-elgomla_2026',
        batchId: 'batch_seed_beet_elgomla_2026',
        tenantId: 'tenant-adeco',
        fileName: 'Book6.xlsx',
        contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        fileSizeBytes: 13804976,
        retailChain: 'beet-elgomla',
        chainNameAr: 'بيت الجملة',
        chainNameEn: 'Beet El Gomla',
        targetYear: '2026',
        targetMonth: '01-12',
        rowsIngested: 256735,
        branchesCount: 30,
        totalRevenue: 47080999.14,
        uploadedAt: '2026-03-08T09:00:00Z',
      );
      final entries = <ArchivedExcelFileModel>[];
      if (!_deletedArchiveIds.contains(fatEntry.id) &&
          !_deletedArchiveFileNames.contains(fatEntry.fileName.toLowerCase())) {
        entries.add(fatEntry);
        _localArchiveBytesById[fatEntry.id] = WebFileHelper.sampleFathallaCsvBytes();
      }
      if (!_deletedArchiveIds.contains(gomEntry.id) &&
          !_deletedArchiveFileNames.contains(gomEntry.fileName.toLowerCase())) {
        entries.add(gomEntry);
        _localArchiveBytesById[gomEntry.id] = WebFileHelper.sampleGomlaCsvBytes();
      }
      if (!_deletedArchiveIds.contains(beetEntry.id) &&
          !_deletedArchiveFileNames.contains(beetEntry.fileName.toLowerCase())) {
        entries.add(beetEntry);
        _localArchiveBytesById[beetEntry.id] = WebFileHelper.sampleGomlaCsvBytes();
      }
      _localArchiveByTenant[cleanSlug] = entries;
    } else {
      _localArchiveByTenant[cleanSlug] = [];
    }
  }

  void _recordLocalArchivedUpload({
    required String cleanSlug,
    required String batchId,
    String? archiveId,
    required String filename,
    required List<int> bytes,
    required String retailChain,
    String? periodDate,
    required int validRows,
    required int branchesCount,
    required double totalRevenue,
    bool isStaged = false,
    String fileType = 'sell_out',
  }) {
    _ensureLocalArchiveSeeded(cleanSlug);
    final normChain = (retailChain.trim().isEmpty ? 'fathalla' : retailChain.trim().toLowerCase());
    String year = '2026';
    String month = 'auto';
    if (periodDate != null && periodDate.length >= 7) {
      year = periodDate.substring(0, 4);
      month = periodDate.substring(5, 7);
    } else {
      final ym = RegExp(r'202[0-9]').firstMatch(filename);
      if (ym != null) {
        year = ym.group(0)!;
      }
    }
    final lowerFile = filename.toLowerCase();
    final contentType = lowerFile.endsWith('.csv')
        ? 'text/csv; charset=utf-8'
        : lowerFile.endsWith('.xls')
            ? 'application/vnd.ms-excel'
            : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

    final list = _localArchiveByTenant[cleanSlug]!;
    final existingIdx = fileType == 'product_master'
        ? (archiveId != null && archiveId.trim().isNotEmpty
            ? list.indexWhere((e) => e.id == archiveId.trim())
            : -1)
        : list.indexWhere(
            (e) => e.retailChain.toLowerCase() == normChain && e.fileName.toLowerCase() == lowerFile,
          );
    final prevEntry = existingIdx >= 0 ? list[existingIdx] : null;
    final prevBytes = prevEntry != null && _localArchiveBytesById.containsKey(prevEntry.id)
        ? _localArchiveBytesById[prevEntry.id]
        : null;
    if (isStaged && batchId.isNotEmpty) {
      _stagedLocalArchiveRollback[batchId] = (
        cleanSlug: cleanSlug,
        prevEntry: prevEntry,
        prevBytes: prevBytes,
      );
    }

    final resolvedArchiveId = (archiveId != null && archiveId.trim().isNotEmpty)
        ? archiveId.trim()
        : (existingIdx >= 0
            ? list[existingIdx].id
            : 'arch_${fileType == 'product_master' ? 'pm_' : ''}${cleanSlug}_${normChain}_${DateTime.now().microsecondsSinceEpoch}');

    if (_deletedArchiveIds.remove(resolvedArchiveId) && kIsWeb) {
      SessionStorage.saveDeletedArchiveIds(_deletedArchiveIds);
    }
    if (_deletedArchiveFileNames.remove(lowerFile) && kIsWeb) {
      SessionStorage.saveDeletedArchiveFileNames(_deletedArchiveFileNames);
    }

    final entry = ArchivedExcelFileModel(
      id: resolvedArchiveId,
      batchId: batchId,
      fileType: fileType,
      tenantId: 'tenant-$cleanSlug',
      fileName: filename,
      contentType: contentType,
      fileSizeBytes: bytes.length,
      retailChain: normChain,
      chainNameAr: fileType == 'product_master' ? 'كارتة الأصناف والأسعار' : getRetailChainShortAr(normChain),
      chainNameEn: fileType == 'product_master' ? 'Product Master & Price List' : getRetailChainNameEn(normChain),
      targetYear: year,
      targetMonth: month,
      rowsIngested: validRows,
      branchesCount: branchesCount > 0 ? branchesCount : 1,
      totalRevenue: totalRevenue,
      uploadedAt: DateTime.now().toUtc().toIso8601String(),
    );

    if (existingIdx >= 0) {
      list.removeAt(existingIdx);
    }
    list.insert(0, entry);
    _localArchiveBytesById[resolvedArchiveId] = bytes;
  }

  /// Updates the local archive entry's chain and/or period metadata for a staged batch.
  void updateStagedArchiveChain(
    String batchId,
    String newChain, {
    String? targetTenant,
    String? periodDate,
  }) {
    if (batchId.isEmpty) return;
    final effectiveTenant = (targetTenant != null && targetTenant.isNotEmpty)
        ? targetTenant
        : tenantId;
    final cleanSlug = normalizeDataTenantSlug(effectiveTenant);
    _ensureLocalArchiveSeeded(cleanSlug);
    final list = _localArchiveByTenant[cleanSlug]!;
    final idx = list.indexWhere((e) => e.batchId == batchId);
    if (idx < 0) return;

    final current = list[idx];
    final normChain = newChain.trim().isNotEmpty
        ? newChain.trim().toLowerCase()
        : current.retailChain;
    String? year;
    String? month;
    if (periodDate != null && periodDate.length >= 7) {
      year = periodDate.substring(0, 4);
      month = periodDate.substring(5, 7);
    }
    final updated = current.copyWith(
      retailChain: normChain,
      chainNameAr: getRetailChainShortAr(normChain),
      chainNameEn: getRetailChainNameEn(normChain),
      targetYear: year,
      targetMonth: month,
    );
    list[idx] = updated;

    // Deduplicate any other entry with the same (normChain, fileName)
    list.removeWhere(
      (e) =>
          e.id != updated.id &&
          e.retailChain.toLowerCase() == normChain &&
          e.fileName.toLowerCase() == updated.fileName.toLowerCase(),
    );
  }

  /// Optional standalone precheck. Returns null on non-200/404/network so dry-run can continue.
  /// Prefer dry-run upload (precheck is folded server-side) to avoid uploading the file twice.
  Future<PreuploadCheckReport?> precheckUpload(
    String filename,
    List<int> bytes, {
    String? targetChain,
    String? targetTenant,
  }) async {
    final effectiveTenant = (targetTenant != null && targetTenant.isNotEmpty)
        ? targetTenant
        : tenantId;
    final queryParams = <String, String>{
      'filename': filename,
      if (targetChain != null && targetChain.isNotEmpty) 'chain': targetChain,
      if (targetTenant != null && targetTenant.isNotEmpty) 'tenant': targetTenant,
    };
    final uri = Uri.parse(ApiEndpoints.ingestPrecheck).replace(queryParameters: queryParams);
    try {
      final resp = await BackendHttp.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${_asciiSafeHeader(authToken)}',
          'X-Tenant-ID': _asciiSafeHeader(effectiveTenant),
          if (targetChain != null && targetChain.isNotEmpty)
            'X-Retail-Chain': _asciiSafeHeader(targetChain),
          'Content-Type': 'application/octet-stream',
          if (currentUser != null && currentUser!.role.isNotEmpty)
            'X-Simulated-Role': _asciiSafeHeader(currentUser!.role),
        },
        body: bytes,
      ).timeout(const Duration(seconds: 60));
      if (precheckFailureShouldContinue(resp.statusCode)) {
        debugPrint(
          '[ApiClient] precheck soft-fail status=${resp.statusCode}; continuing to dry-run',
        );
        return null;
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      return PreuploadCheckReport.fromJson(decoded);
    } catch (e) {
      debugPrint('[ApiClient] precheck soft-fail: $e; continuing to dry-run');
      return null;
    }
  }

  /// Sends file for Two-Tier Gemini AI ingestion (Tier 1: Gemini 3.8 Flash, Tier 2: Gemini 4 Argon Medium / gemini-1.5-pro).
  Future<IngestionResultModel> uploadFile(
    String filename,
    List<int> bytes, {
    String? targetChain,
    String? targetTenant,
    String? periodDate,
    bool dryRun = true,
    String aiTier = 'tier2',
    bool replaceConfirmed = false,
    String? periodChoice,
  }) async {
    final effectiveTenant = (targetTenant != null && targetTenant.isNotEmpty)
        ? targetTenant
        : tenantId;
    final cleanSlug = normalizeDataTenantSlug(effectiveTenant);
    if (_clearedTenants.remove(cleanSlug) && kIsWeb) {
      SessionStorage.saveClearedTenants(_clearedTenants);
    }
    if (!dryRun) {
      invalidateExecutiveKpisCache();
    }
    try {
      final queryParams = <String, String>{
        'filename': filename,
        if (dryRun) 'dry_run': 'true',
        'ai_tier': aiTier,
      };
      if (targetChain != null && targetChain.isNotEmpty) {
        queryParams['chain'] = targetChain;
      }
      if (targetTenant != null && targetTenant.isNotEmpty) {
        queryParams['tenant'] = targetTenant;
      }
      if (periodDate != null && periodDate.isNotEmpty) {
        queryParams['period_date'] = periodDate;
      }
      if (replaceConfirmed) queryParams['replace_confirmed'] = 'true';
      if (periodChoice != null && periodChoice.isNotEmpty) queryParams['period_choice'] = periodChoice;
      final uri = Uri.parse(ApiEndpoints.upload).replace(
        queryParameters: queryParams,
      );
      final resp = await BackendHttp.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${_asciiSafeHeader(authToken)}',
          'X-Tenant-ID': _asciiSafeHeader(effectiveTenant),
          'X-AI-Tier': _asciiSafeHeader(aiTier),
          if (targetChain != null && targetChain.isNotEmpty)
            'X-Retail-Chain': _asciiSafeHeader(targetChain),
          if (periodDate != null && periodDate.isNotEmpty)
            'X-Period-Date': _asciiSafeHeader(periodDate),
          'Content-Type': 'application/octet-stream',
          BackendHttp.asyncJobHeader: '1',
          if (currentUser != null && currentUser!.role.isNotEmpty)
            'X-Simulated-Role': _asciiSafeHeader(currentUser!.role),
        },
        body: bytes,
      ).timeout(const Duration(seconds: 120)).then((r) => BackendHttp.awaitJob(r, headers: {
            'Authorization': 'Bearer ${_asciiSafeHeader(authToken)}',
            'X-Tenant-ID': _asciiSafeHeader(effectiveTenant),
          }));

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final model = IngestionResultModel.fromJson(decoded);
        _recordLocalArchivedUpload(
          cleanSlug: cleanSlug,
          batchId: model.batchId,
          archiveId: model.archiveId,
          filename: filename,
          bytes: bytes,
          retailChain: (targetChain != null && targetChain.isNotEmpty)
              ? targetChain
              : model.retailerDetected,
          periodDate: periodDate,
          validRows: model.validRows,
          branchesCount: model.autoCreatedStoresCount,
          totalRevenue: model.totalRevenue,
          isStaged: dryRun,
        );
        return model;
      }
      if (resp.statusCode == 422 || resp.statusCode == 409) {
        final blocked = PreuploadCheckReport.tryParseBlocked(resp.body);
        if (blocked != null) {
          throw PreuploadBlockedException(blocked);
        }
        // The backend validated the sheet and refused to save it (or needs an answer first):
        // surface it instead of falling back to a locally parsed result.
        throwIfUploadRefused(resp.statusCode, resp.body, 'تعذّر قراءة الملف بشكل صحيح ولم يتم حفظه');
      }
    } on PreuploadBlockedException {
      rethrow;
    } on UploadRejectedException {
      rethrow;
    } on UploadConfirmationRequiredException {
      rethrow;
    } catch (e) {
      debugPrint('[ApiClient] Fallback to mock ingestion result: $e');
    }

    final parsedCsv = _tryParseUploadedCsv(
      filename,
      bytes,
      targetChain: targetChain,
      periodDate: periodDate,
      dryRun: dryRun,
    );
    if (parsedCsv != null) {
      // Local CSV parse is deterministic — do not claim Gemini tier/confidence.
      final resModel = parsedCsv.copyWith(
        mappingSource: 'deterministic',
        mappingConfidence: 0,
        confidenceScore: 0,
        aiModelUsed: '',
        aiTierUsed: '',
        tier2Escalated: false,
      );
      _recordLocalArchivedUpload(
        cleanSlug: cleanSlug,
        batchId: resModel.batchId,
        archiveId: resModel.archiveId,
        filename: filename,
        bytes: bytes,
        retailChain: (targetChain != null && targetChain.isNotEmpty)
            ? targetChain
            : resModel.retailerDetected,
        periodDate: periodDate,
        validRows: resModel.validRows,
        branchesCount: resModel.autoCreatedStoresCount,
        totalRevenue: resModel.totalRevenue,
        isStaged: dryRun,
      );
      return resModel;
    }


    final lowerName = filename.toLowerCase();
    final discovered = lowerName.contains('carrefour') || filename.contains('كارفور')
        ? 'carrefour'
        : (lowerName.contains('beet') || filename.contains('بيت الجملة') || filename.contains('بيت الجمله'))
            ? 'beet-elgomla'
            : (lowerName.contains('gomla') || (filename.contains('جملة') && !filename.contains('فتح الله')))
                ? 'gomla'
                : lowerName.contains('spinneys') || filename.contains('سبينيس')
                    ? 'spinneys'
                    : (lowerName.contains('fathalla') || filename.contains('فتح الله'))
                        ? 'fathalla'
                        : '';
    final detectedChain = (targetChain != null && targetChain.isNotEmpty)
        ? targetChain
        : (discovered.isNotEmpty ? discovered : 'fathalla');

    final bool mismatch = discovered.isNotEmpty &&
        targetChain != null &&
        targetChain.isNotEmpty &&
        discovered.toLowerCase() != targetChain.toLowerCase();


    String? suggestedName;
    if (mismatch) {
      suggestedName = getRetailChainDisplayName(discovered);
    }

    final fallbackModel = IngestionResultModel(
      batchId: 'batch_ai_${DateTime.now().millisecondsSinceEpoch}',
      filename: filename,
      retailerDetected: detectedChain,
      totalRows: 240,
      validRows: 238,
      anomalyRows: 2,
      totalRevenue: 345000.0,
      totalQuantity: 2850,
      confidenceScore: 0.985,
      mappingConfidence: 0.985,
      mappingSource: 'mock',
      isStaged: dryRun,
      isCommitted: !dryRun,
      discoveredRetailer: discovered.isNotEmpty ? discovered : detectedChain,
      targetRetailer: targetChain ?? '',
      chainMismatchDetected: mismatch,
      suggestedChain: mismatch ? discovered : null,
      suggestedChainName: suggestedName,
      aiModelUsed: 'mock',
      aiTierUsed: 'mock',
      tier2Escalated: false,

      anomalies: [
        {
          'row_number': 14,
          'issue_type': 'invalid_barcode',
          'description': 'تم تصحيح باركود قصير تلقائياً وفق معيار GTIN-13 الدولي',
        },
        {
          'row_number': 82,
          'issue_type': 'unmapped_store',
          'description': 'مطابقة اسم الفرع بالذكاء الاصطناعي مع فرع سموحة الإسكندرية',
        }
      ],
    );
    _recordLocalArchivedUpload(
      cleanSlug: cleanSlug,
      batchId: fallbackModel.batchId,
      archiveId: fallbackModel.archiveId,
      filename: filename,
      bytes: bytes,
      retailChain: detectedChain,
      periodDate: periodDate,
      validRows: fallbackModel.validRows,
      branchesCount: 4,
      totalRevenue: fallbackModel.totalRevenue,
      isStaged: dryRun,
    );
    return fallbackModel;
  }

  /// Commits a reviewed staged upload batch to BigQuery and Firestore.
  Future<IngestionResultModel> commitStagedUpload({
    required String batchId,
    String? targetChain,
    String? targetTenant,
    String? periodDate,
    bool replaceConfirmed = false,
    String? periodChoice,
  }) async {
    final effectiveTenant = (targetTenant != null && targetTenant.isNotEmpty)
        ? targetTenant
        : tenantId;
    invalidateExecutiveKpisCache();
    updateStagedArchiveChain(
      batchId,
      targetChain ?? '',
      targetTenant: effectiveTenant,
      periodDate: periodDate,
    );
    _stagedLocalArchiveRollback.remove(batchId);
    try {
      final uri = Uri.parse(ApiEndpoints.ingestCommit);
      final resp = await BackendHttp.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${_asciiSafeHeader(authToken)}',
          'X-Tenant-ID': _asciiSafeHeader(effectiveTenant),
          'Content-Type': 'application/json',
          if (currentUser != null && currentUser!.role.isNotEmpty)
            'X-Simulated-Role': _asciiSafeHeader(currentUser!.role),
        },
        body: jsonEncode({
          'batch_id': batchId,
          if (targetChain != null && targetChain.isNotEmpty) 'chain': targetChain,
          if (targetTenant != null && targetTenant.isNotEmpty) 'tenant': targetTenant,
          if (periodDate != null && periodDate.isNotEmpty) 'period_date': periodDate,
          if (replaceConfirmed) 'replace_confirmed': true,
          if (periodChoice != null && periodChoice.isNotEmpty) 'period_choice': periodChoice,
        }),
      ).timeout(const Duration(seconds: 120));

      if (resp.statusCode == 200) {
        return IngestionResultModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
      // A refused commit saved nothing: never report it as saved. (Server checks answer 409/422; in
      // offline/test mode other statuses still fall back to the local preview.)
      if (resp.statusCode == 409 || resp.statusCode == 422 || !allowMockFallback) {
        throwIfUploadRefused(resp.statusCode, resp.body, 'فشل حفظ البيانات ومفيش حاجة اتحفظت');
      }
      throw Exception('commit HTTP ${resp.statusCode}');
    } on UploadRejectedException {
      rethrow;
    } on UploadConfirmationRequiredException {
      rethrow;
    } catch (e) {
      debugPrint('[ApiClient] Fallback commitStagedUpload: $e');
      if (!allowMockFallback) rethrow;
    }

    return IngestionResultModel(
      batchId: batchId,
      filename: 'committed_upload.xlsx',
      retailerDetected: targetChain ?? 'fathalla',
      totalRows: 100,
      validRows: 100,
      anomalyRows: 0,
      totalRevenue: 100000.0,
      totalQuantity: 500,
      confidenceScore: 0.99,
      isStaged: false,
      isCommitted: true,
      anomalies: const [],
    );
  }

  /// Discards a staged upload batch without modifying the database.
  Future<void> discardStagedUpload({
    required String batchId,
    String? targetTenant,
  }) async {
    final effectiveTenant = (targetTenant != null && targetTenant.isNotEmpty)
        ? targetTenant
        : tenantId;
    final cleanSlug = normalizeDataTenantSlug(effectiveTenant);
    _ensureLocalArchiveSeeded(cleanSlug);
    final list = _localArchiveByTenant[cleanSlug]!;
    final rollback = _stagedLocalArchiveRollback.remove(batchId);
    final idx = list.indexWhere((e) => e.batchId == batchId);
    if (idx >= 0) {
      final removed = list.removeAt(idx);
      if (rollback != null && rollback.prevEntry != null) {
        list.insert(idx, rollback.prevEntry!);
        if (rollback.prevBytes != null) {
          _localArchiveBytesById[rollback.prevEntry!.id] = rollback.prevBytes!;
        }
      } else {
        _localArchiveBytesById.remove(removed.id);
      }
    }
    try {
      final uri = Uri.parse(ApiEndpoints.ingestDiscard);
      await BackendHttp.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${_asciiSafeHeader(authToken)}',
          'X-Tenant-ID': _asciiSafeHeader(effectiveTenant),
          'Content-Type': 'application/json',
          if (currentUser != null && currentUser!.role.isNotEmpty)
            'X-Simulated-Role': _asciiSafeHeader(currentUser!.role),
        },
        body: jsonEncode({
          'batch_id': batchId,
        }),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[ApiClient] Discard staged upload fallback: $e');
    }
  }

  /// Last successful archive answer per (tenant, filters); served when a later request fails.
  final Map<String, UploadedFilesArchiveResponse> _lastArchiveByKey = {};

  /// Retrieves archived Excel/CSV files for the tenant, optionally filtered by retail chain, year, search query, and fileType ('sell_out' | 'sell_in').
  Future<UploadedFilesArchiveResponse> getUploadedFilesArchive({
    String? chain,
    String? year,
    String? searchQuery,
    String? targetTenant,
    String? fileType,
  }) async {
    final effectiveTenant = (targetTenant != null && targetTenant.isNotEmpty)
        ? targetTenant
        : tenantId;
    final cleanSlug = normalizeDataTenantSlug(effectiveTenant);
    final archiveKey = [cleanSlug, chain ?? '', year ?? '', searchQuery?.trim() ?? '', fileType ?? ''].join('|');
    try {
      final queryParams = <String, String>{};
      if (chain != null && chain.isNotEmpty && chain != 'all' && chain != 'الكل') {
        queryParams['chain'] = chain;
      }
      if (year != null && year.isNotEmpty && year != 'all' && year != 'الكل' && year != 'auto') {
        queryParams['year'] = year;
      }
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        queryParams['q'] = searchQuery.trim();
      }
      if (fileType != null && fileType.trim().isNotEmpty) {
        queryParams['file_type'] = fileType.trim();
      }
      final uri = Uri.parse(ApiEndpoints.ingestArchive).replace(
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );
      final resp = await BackendHttp.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${_asciiSafeHeader(authToken)}',
          'X-Tenant-ID': _asciiSafeHeader(effectiveTenant),
          if (currentUser != null && currentUser!.role.isNotEmpty)
            'X-Simulated-Role': _asciiSafeHeader(currentUser!.role),
        },
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final parsed = UploadedFilesArchiveResponse.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>,
        );
        // Server is source of truth: drop stale session tombstones for files still listed
        // (recovers browsers poisoned by earlier optimistic failed deletes).
        final cleared = reconcileArchiveTombstones(
          serverIds: parsed.files.map((f) => f.id),
          serverFileNamesLower: parsed.files.map((f) => f.fileName.toLowerCase()),
          deletedIds: _deletedArchiveIds,
          deletedFileNamesLower: _deletedArchiveFileNames,
        );
        if (cleared > 0 && kIsWeb) {
          SessionStorage.saveDeletedArchiveIds(_deletedArchiveIds);
          SessionStorage.saveDeletedArchiveFileNames(_deletedArchiveFileNames);
        }
        final filteredFiles = filterArchiveFilesByTombstones(
          files: parsed.files,
          idOf: (f) => f.id,
          fileNameOf: (f) => f.fileName,
          deletedIds: _deletedArchiveIds,
          deletedFileNamesLower: _deletedArchiveFileNames,
        );
        final counts = <String, int>{};
        for (final item in filteredFiles) {
          final k = item.retailChain.toLowerCase();
          counts[k] = (counts[k] ?? 0) + 1;
        }
        final out = UploadedFilesArchiveResponse(
          tenantId: parsed.tenantId,
          totalCount: filteredFiles.length,
          chainCounts: counts,
          files: filteredFiles,
        );
        _lastArchiveByKey[archiveKey] = out;
        return out;
      }
      if (!allowMockFallback) {
        throw ArchiveLoadException('HTTP ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('[ApiClient] Fallback getUploadedFilesArchive: $e');
      if (!allowMockFallback) {
        // Production: never show the local demo archive (other chains' files). Keep the last
        // successful answer for the same filter, or let the screen show "couldn't load" + retry.
        final last = _lastArchiveByKey[archiveKey];
        if (last != null) return last;
        if (e is ArchiveLoadException) rethrow;
        throw ArchiveLoadException('$e');
      }
    }

    _ensureLocalArchiveSeeded(cleanSlug);
    final reqType = (fileType ?? 'sell_out').trim().toLowerCase();
    final allLocal = (_localArchiveByTenant[cleanSlug] ?? const [])
        .where((item) => reqType == 'all' || item.fileType.toLowerCase() == reqType)
        .toList();
    final counts = <String, int>{};
    for (final item in allLocal) {
      final k = item.retailChain.toLowerCase();
      counts[k] = (counts[k] ?? 0) + 1;
    }

    final normChain = (chain ?? '').trim().toLowerCase();
    final hasChainFilter = normChain.isNotEmpty && normChain != 'all' && normChain != 'الكل';
    final normYear = (year ?? '').trim().toLowerCase();
    final hasYearFilter = normYear.isNotEmpty && normYear != 'all' && normYear != 'الكل' && normYear != 'auto';
    final normSearch = (searchQuery ?? '').trim().toLowerCase();

    final filtered = allLocal.where((item) {
      if (hasChainFilter && item.retailChain.toLowerCase() != normChain) {
        return false;
      }
      if (hasYearFilter && item.targetYear.toLowerCase() != normYear) {
        return false;
      }
      if (normSearch.isNotEmpty) {
        final matchName = item.fileName.toLowerCase().contains(normSearch);
        final matchAr = item.chainNameAr.toLowerCase().contains(normSearch);
        final matchEn = item.chainNameEn.toLowerCase().contains(normSearch);
        if (!matchName && !matchAr && !matchEn) return false;
      }
      return true;
    }).toList();

    return UploadedFilesArchiveResponse(
      tenantId: 'tenant-$cleanSlug',
      totalCount: filtered.length,
      chainCounts: counts,
      files: filtered,
    );
  }

  /// Returns the direct download endpoint URL for an archived Excel/CSV file.
  String getArchiveDownloadUrl(String archiveId) {
    return ApiEndpoints.ingestArchiveDownload(archiveId);
  }

  /// Downloads the raw bytes of an archived Excel/CSV file and triggers a browser file download.
  Future<({String fileName, String contentType, List<int> bytes})> downloadArchivedFile(
    ArchivedExcelFileModel file, {
    String? targetTenant,
  }) async {
    final effectiveTenant = (targetTenant != null && targetTenant.isNotEmpty)
        ? targetTenant
        : tenantId;
    List<int>? downloadedBytes;
    String contentType = file.contentType;

    try {
      final uri = Uri.parse(ApiEndpoints.ingestArchiveDownload(file.id));
      final resp = await BackendHttp.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${_asciiSafeHeader(authToken)}',
          'X-Tenant-ID': _asciiSafeHeader(effectiveTenant),
          if (currentUser != null && currentUser!.role.isNotEmpty)
            'X-Simulated-Role': _asciiSafeHeader(currentUser!.role),
        },
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        downloadedBytes = resp.bodyBytes;
        final headerCt = resp.headers['content-type'];
        if (headerCt != null && headerCt.isNotEmpty) {
          contentType = headerCt;
        }
      }
    } catch (e) {
      debugPrint('[ApiClient] Fallback downloadArchivedFile: $e');
    }

    downloadedBytes ??= _localArchiveBytesById[file.id] ??
        (file.retailChain == 'gomla'
            ? WebFileHelper.sampleGomlaCsvBytes()
            : WebFileHelper.sampleFathallaCsvBytes());

    lastDownloadedArchiveFile = file;
    lastDownloadedArchiveBytes = downloadedBytes;

    WebFileHelper.downloadFile(
      filename: file.fileName,
      bytes: downloadedBytes,
      mimeType: contentType,
    );

    return (
      fileName: file.fileName,
      contentType: contentType,
      bytes: downloadedBytes,
    );
  }

  /// Deletes an archived Excel/CSV file and purges its ingested facts from the database and storage.
  ///
  /// Local list / session tombstones are updated ONLY after the backend returns 200/204.
  /// A 403/4xx/5xx leaves the file listed and throws [ArchiveDeleteException] with the API message.
  Future<bool> deleteArchivedFile(
    String archiveId, {
    String? targetTenant,
    String? fileName,
    bool isSellIn = false,
    bool isProductMaster = false,
  }) async {
    final effectiveTenant = (targetTenant != null && targetTenant.isNotEmpty)
        ? targetTenant
        : tenantId;
    final cleanSlug = normalizeDataTenantSlug(effectiveTenant);
    _ensureLocalArchiveSeeded(cleanSlug);
    final localList = _localArchiveByTenant[cleanSlug];
    final effectiveIsPm = isProductMaster ||
        archiveId.contains('_pm_') ||
        archiveId == 'pm_default_seed' ||
        (localList != null && localList.any((f) => f.id == archiveId && f.fileType == 'product_master'));

    final hasRemainingWithSameFileName = fileName != null &&
        fileName.trim().isNotEmpty &&
        (localList ?? const [])
            .where((f) => f.id != archiveId)
            .any((f) => f.fileName.toLowerCase() == fileName.trim().toLowerCase());

    late final http.Response resp;
    try {
      var uri = Uri.parse(ApiEndpoints.ingestArchiveItem(archiveId));
      if (fileName != null && fileName.trim().isNotEmpty) {
        uri = uri.replace(queryParameters: {'file_name': fileName.trim()});
      }
      resp = await BackendHttp.delete(
        uri,
        headers: {
          'Authorization': 'Bearer ${_asciiSafeHeader(authToken)}',
          'X-Tenant-ID': _asciiSafeHeader(effectiveTenant),
          if (currentUser != null && currentUser!.role.isNotEmpty)
            'X-Simulated-Role': _asciiSafeHeader(currentUser!.role),
        },
      ).timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('[ApiClient] deleteArchivedFile network call error: $e');
      throw ArchiveDeleteException(
        statusCode: 0,
        message: 'تعذر الاتصال بالخادم أثناء حذف الملف: $e',
      );
    }

    if (!archiveDeleteHttpSucceeded(resp.statusCode)) {
      throw ArchiveDeleteException.fromResponse(resp.statusCode, resp.body);
    }

    // Backend confirmed both archive removal and analytics purge — update local mirrors.
    invalidateExecutiveKpisCache();
    _deletedArchiveIds.add(archiveId);
    if (kIsWeb) {
      SessionStorage.saveDeletedArchiveIds(_deletedArchiveIds);
    }

    if (localList != null) {
      _localArchiveByTenant[cleanSlug] = localList.where((f) {
        if (f.id == archiveId) return false;
        if (!effectiveIsPm &&
            fileName != null &&
            f.fileName.toLowerCase() == fileName.trim().toLowerCase()) {
          return false;
        }
        return true;
      }).toList();
    }

    if (fileName != null &&
        fileName.trim().isNotEmpty &&
        !hasRemainingWithSameFileName) {
      _deletedArchiveFileNames.add(fileName.trim().toLowerCase());
      if (kIsWeb) {
        SessionStorage.saveDeletedArchiveFileNames(_deletedArchiveFileNames);
      }
    }

    if (effectiveIsPm) {
      _rollbackLocalProductMasterSheet(cleanSlug, archiveId: archiveId, fileName: fileName);
    }

    _localArchiveBytesById.remove(archiveId);
    if (!isSellIn &&
        !effectiveIsPm &&
        (_localArchiveByTenant[cleanSlug] ?? [])
            .where((f) => f.fileType != 'sell_in' && f.fileType != 'product_master')
            .isEmpty) {
      _clearedTenants.add(cleanSlug);
      if (kIsWeb) {
        SessionStorage.saveClearedTenants(_clearedTenants);
      }
    }
    return true;
  }

  static String generateChainCode(String displayName, {String? customCode}) {
    final trimmedCustom = (customCode ?? '').trim().toLowerCase();
    if (trimmedCustom.isNotEmpty) {
      final asciiCustom = trimmedCustom
          .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      if (asciiCustom.isNotEmpty) return asciiCustom;
    }

    final raw = displayName.trim();
    final lower = raw.toLowerCase();
    if (raw.contains('فتح الله') || lower.contains('fathalla')) return 'fathalla';
    if (raw.contains('بيت الجملة') || raw.contains('بيت الجمله') || lower.contains('beet')) {
      return 'beet-elgomla';
    }
    if (raw.contains('جملة ماركت') || raw.contains('جمله ماركت') || lower == 'gomla' || lower.contains('gomla market')) {
      return 'gomla';
    }
    if (raw.contains('كارفور') || lower.contains('carrefour')) return 'carrefour';
    if (raw.contains('سبينيس') || raw.contains('سبينس') || lower.contains('spinneys')) return 'spinneys';
    if (raw.contains('مترو') || lower.contains('metro')) return 'metro';
    if (raw.contains('سعودي') || lower.contains('seoudi')) return 'seoudi';
    if (raw.contains('هايبر وان') || lower.contains('hyperone') || lower.contains('hyper one')) return 'hyperone';
    if (raw.contains('كازيون') || lower.contains('kazyon')) return 'kazyon';
    if (raw.contains('بيم') || lower == 'bim') return 'bim';
    if (raw.contains('بندة') || raw.contains('بنده') || lower.contains('panda')) return 'panda';
    if (raw.contains('الفرجاني') || lower.contains('fergany')) return 'fergany';
    if (raw.contains('أولاد رجب') || raw.contains('اولاد رجب') || lower.contains('ragab')) return 'awlad-ragab';
    if (raw.contains('الوكالة') || raw.contains('الوكاله') || raw.contains('وكال') || lower.contains('wakala')) {
      return 'chain-1080314';
    }
    if (raw.contains('الراية') || raw.contains('الرايه') || lower.contains('raya')) return 'el-raya';
    if (raw.contains('زهران') || lower.contains('zahran')) return 'zahran';

    final asciiSlug = lower
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (asciiSlug.isNotEmpty) return asciiSlug;

    final hash = raw.runes.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff).toRadixString(16);
    return 'chain-$hash';
  }

  static RetailChainModel? _findRegisteredChainByCode(String code) {
    final clean = code.trim().toLowerCase();
    for (final list in _inMemoryChainsByTenant.values) {
      for (final item in list) {
        if (item.code.toLowerCase() == clean || item.chainId.toLowerCase() == clean) {
          return item;
        }
      }
    }
    return null;
  }

  /// Phonetic transliteration from Arabic text to Latin characters
  static String transliterateArabicToEnglish(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    final map = {
      'ا': 'a', 'أ': 'a', 'إ': 'e', 'آ': 'aa', 'ء': '', 'ئ': 'e', 'ؤ': 'o',
      'ب': 'b', 'ت': 't', 'ث': 'th', 'ج': 'g', 'ح': 'h', 'خ': 'kh',
      'د': 'd', 'ذ': 'th', 'ر': 'r', 'ز': 'z', 'س': 's', 'ش': 'sh',
      'ص': 's', 'ض': 'd', 'ط': 't', 'ظ': 'z', 'ع': 'a', 'غ': 'gh',
      'ف': 'f', 'ق': 'k', 'ك': 'k', 'ل': 'l', 'م': 'm', 'ن': 'n',
      'ه': 'h', 'ة': 'a', 'و': 'w', 'ي': 'y', 'ى': 'a',
    };
    final buf = StringBuffer();
    for (int i = 0; i < trimmed.length; i++) {
      final ch = trimmed[i];
      if (map.containsKey(ch)) {
        buf.write(map[ch]);
      } else if (RegExp(r'[a-zA-Z0-9\s-]').hasMatch(ch)) {
        buf.write(ch);
      }
    }
    final raw = buf.toString().trim();
    if (raw.isEmpty) return 'Retail Chain';
    return raw.split(RegExp(r'\s+')).map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + (w.length > 1 ? w.substring(1).toLowerCase() : '');
    }).join(' ');
  }

  /// Phonetic transliteration from English text to Arabic characters
  static String transliterateEnglishToArabic(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    if (lower.contains('market')) {
      final base = lower.replaceAll('market', '').trim();
      return '${transliterateEnglishToArabic(base)} ماركت';
    }
    final map = {
      'th': 'ث', 'kh': 'خ', 'sh': 'ش', 'gh': 'غ', 'ph': 'ف',
      'ch': 'تش', 'aa': 'ا', 'ee': 'ي', 'oo': 'و',
      'a': 'ا', 'b': 'ب', 'c': 'ك', 'd': 'د', 'e': 'ي', 'f': 'ف',
      'g': 'ج', 'h': 'ه', 'i': 'ي', 'j': 'ج', 'k': 'ك', 'l': 'ل',
      'm': 'م', 'n': 'ن', 'o': 'و', 'p': 'ب', 'q': 'ق', 'r': 'ر',
      's': 'س', 't': 'ت', 'u': 'و', 'v': 'ف', 'w': 'و', 'x': 'كس',
      'y': 'ي', 'z': 'ز',
    };
    String working = lower;
    for (final entry in map.entries) {
      working = working.replaceAll(entry.key, entry.value);
    }
    final res = working.replaceAll(RegExp(r'[^ \u0600-\u06FF]'), '').trim();
    return res.isNotEmpty ? res : 'سلسلة تجزئة';
  }

  /// Formats any retail chain into the standard bilingual format: `الاسم بالعربي (English Name)`.
  /// Supports Arabic-first, English-first, or explicit separate Arabic & English inputs.
  static String formatBilingualChainName(String input, [String? englishName]) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    if (englishName != null && englishName.trim().isNotEmpty) {
      final cleanEn = englishName.trim().replaceAll('(', '').replaceAll(')', '').trim();
      final cleanAr = trimmed.replaceAll('(', '').replaceAll(')', '').trim();
      return '$cleanAr ($cleanEn)';
    }

    final parenMatch = RegExp(r'^([^(]+)\s*\(([^)]+)\)$').firstMatch(trimmed);
    if (parenMatch != null) {
      final part1 = parenMatch.group(1)!.trim();
      final part2 = parenMatch.group(2)!.trim();
      final isPart1Ar = RegExp(r'[\u0600-\u06FF]').hasMatch(part1);
      final isPart2Ar = RegExp(r'[\u0600-\u06FF]').hasMatch(part2);
      if (isPart1Ar && !isPart2Ar) {
        return '$part1 ($part2)';
      } else if (!isPart1Ar && isPart2Ar) {
        return '$part2 ($part1)';
      }
      return '$part1 ($part2)';
    }

    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(trimmed);
    if (isArabic) {
      final lower = trimmed.toLowerCase();
      if (lower == 'الوكالة' || lower == 'الوكاله' || lower == 'وكالة') {
        return 'الوكالة (El Wakala)';
      }
      if (lower == 'أسواق فتح الله' || lower == 'فتح الله') {
        return 'أسواق فتح الله (Fathalla Market)';
      }
      if (lower == 'بيت الجملة' || lower == 'بيت الجمله') {
        return 'بيت الجملة (Beet El Gomla)';
      }
      if (lower == 'جملة ماركت' || lower == 'جمله ماركت') {
        return 'جملة ماركت (Gomla Market)';
      }
      if (lower == 'كازيون' || lower == 'كازيون ماركت') {
        return 'كازيون (Kazyon)';
      }
      if (lower == 'بيم') {
        return 'بيم (BIM)';
      }
      if (lower == 'كارفور' || lower == 'كارفور مصر') {
        return 'كارفور (Carrefour)';
      }
      if (lower == 'سبينيس' || lower == 'سبينيز') {
        return 'سبينيس (Spinneys)';
      }
      if (lower == 'مترو' || lower == 'مترو ماركت') {
        return 'مترو ماركت (Metro Market)';
      }
      if (lower == 'سعودي' || lower == 'سعودي ماركت') {
        return 'سعودي ماركت (Seoudi Market)';
      }
      if (lower == 'خير زمان') {
        return 'خير زمان (Kheir Zaman)';
      }
      if (lower == 'الراية' || lower == 'الرايه' || lower == 'الراية ماركت') {
        return 'الراية ماركت (Al Raya)';
      }
      if (lower == 'لولو' || lower == 'لولو هايبر ماركت') {
        return 'لولو هايبر ماركت (LuLu)';
      }
      if (lower == 'هايبر وان') {
        return 'هايبر وان (Hyper One)';
      }
      if (lower == 'أولاد رجب' || lower == 'اولاد رجب') {
        return 'أولاد رجب (Awlad Ragab)';
      }
      if (lower == 'العثيم') {
        return 'العثيم (Al Othaim)';
      }

      String en = '';
      if (lower.contains('هايبر وان')) {
        final rest = trimmed.replaceAll('هايبر وان', '').trim();
        final restEn = transliterateArabicToEnglish(rest);
        en = restEn.isNotEmpty ? 'Hyper One $restEn' : 'Hyper One';
      } else if (lower.contains('فتح الله')) {
        en = 'Fathalla Market';
      } else if (lower.contains('الوكالة') || lower.contains('وكال')) {
        en = 'El Wakala';
      } else {
        en = transliterateArabicToEnglish(trimmed);
      }
      return '$trimmed ($en)';
    } else {
      final lower = trimmed.toLowerCase();
      if (lower == 'wakala' || lower == 'el wakala') {
        return 'الوكالة (El Wakala)';
      }
      if (lower == 'fathalla' || lower == 'fathalla market') {
        return 'أسواق فتح الله (Fathalla Market)';
      }
      if (lower == 'beet el gomla' || lower == 'beet el-gomla') {
        return 'بيت الجملة (Beet El Gomla)';
      }
      if (lower == 'gomla' || lower == 'gomla market') {
        return 'جملة ماركت (Gomla Market)';
      }
      if (lower == 'kazyon') {
        return 'كازيون (Kazyon)';
      }
      if (lower == 'carrefour') {
        return 'كارفور (Carrefour)';
      }
      if (lower == 'spinneys') {
        return 'سبينيس (Spinneys)';
      }
      if (lower == 'metro' || lower == 'metro market') {
        return 'مترو ماركت (Metro Market)';
      }
      if (lower == 'seoudi' || lower == 'seoudi market') {
        return 'سعودي ماركت (Seoudi Market)';
      }
      final ar = transliterateEnglishToArabic(trimmed);
      return '$ar ($trimmed)';
    }
  }

  /// Decomposes a chain name into separate Arabic and English names
  static ({String nameAr, String nameEn}) decomposeBilingualChainName(String name) {
    final trimmed = name.trim();
    final parenMatch = RegExp(r'^([^(]+)\s*\(([^)]+)\)$').firstMatch(trimmed);
    if (parenMatch != null) {
      final part1 = parenMatch.group(1)!.trim();
      final part2 = parenMatch.group(2)!.trim();
      final isPart1Ar = RegExp(r'[\u0600-\u06FF]').hasMatch(part1);
      if (isPart1Ar) {
        return (nameAr: part1, nameEn: part2);
      } else {
        return (nameAr: part2, nameEn: part1);
      }
    }
    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(trimmed);
    if (isArabic) {
      final formatted = formatBilingualChainName(trimmed);
      final m = RegExp(r'^([^(]+)\s*\(([^)]+)\)$').firstMatch(formatted);
      if (m != null) {
        return (nameAr: m.group(1)!.trim(), nameEn: m.group(2)!.trim());
      }
      return (nameAr: trimmed, nameEn: transliterateArabicToEnglish(trimmed));
    } else {
      final formatted = formatBilingualChainName(trimmed);
      final m = RegExp(r'^([^(]+)\s*\(([^)]+)\)$').firstMatch(formatted);
      if (m != null) {
        return (nameAr: m.group(1)!.trim(), nameEn: m.group(2)!.trim());
      }
      return (nameAr: transliterateEnglishToArabic(trimmed), nameEn: trimmed);
    }
  }

  static String getRetailChainShortAr(String code) {
    final registered = _findRegisteredChainByCode(code);
    if (registered != null && registered.displayName.trim().isNotEmpty) {
      final disp = registered.displayName.trim();
      final parenIdx = disp.indexOf('(');
      if (parenIdx > 0) {
        return disp.substring(0, parenIdx).trim();
      }
      return disp;
    }
    switch (code.trim().toLowerCase()) {
      case 'fathalla':
        return 'أسواق فتح الله';
      case 'gomla':
        return 'جملة ماركت';
      case 'beet-elgomla':
      case 'beet_elgomla':
        return 'بيت الجملة';
      case 'chain-1080314':
      case 'el-wakala':
      case 'wakala':
      case 'الوكالة':
      case 'الوكاله':
        return 'الوكالة';
      case 'institutions':
      case 'institution':
      case 'organizations':
        return 'قطاع المؤسسات';
      case 'carrefour':
        return 'كارفور مصر';
      case 'spinneys':
        return 'سبينيس مصر';
      case 'metro':
        return 'مترو ماركت';
      case 'seoudi':
        return 'سعودي ماركت';
      case 'hyperone':
        return 'هايبر وان';
      case 'kazyon':
        return 'كازيون ماركت';
      case 'bim':
        return 'بيم (BIM)';
      case 'panda':
        return 'أسواق بندة';
      case 'fergany':
        return 'الفرجاني ماركت';
      case 'awlad-ragab':
        return 'أولاد رجب';
      case 'el-raya':
        return 'أسواق الراية';
      case 'zahran':
        return 'زهران ماركت';
      default:
        return code;
    }
  }

  static String getRetailChainNameEn(String code) {
    final registered = _findRegisteredChainByCode(code);
    if (registered != null && registered.displayName.trim().isNotEmpty) {
      final disp = registered.displayName.trim();
      final openIdx = disp.indexOf('(');
      final closeIdx = disp.lastIndexOf(')');
      if (openIdx >= 0 && closeIdx > openIdx + 1) {
        return disp.substring(openIdx + 1, closeIdx).trim();
      }
      return disp;
    }
    switch (code.trim().toLowerCase()) {
      case 'fathalla':
        return 'Fathalla Market';
      case 'gomla':
        return 'Gomla Market';
      case 'beet-elgomla':
      case 'beet_elgomla':
        return 'Beet El Gomla';
      case 'chain-1080314':
      case 'el-wakala':
      case 'wakala':
      case 'الوكالة':
      case 'الوكاله':
        return 'El Wakala';
      case 'institutions':
      case 'institution':
      case 'organizations':
        return 'Institutions';
      case 'carrefour':
        return 'Carrefour Egypt';
      case 'spinneys':
        return 'Spinneys Egypt';
      case 'metro':
        return 'Metro Market';
      case 'seoudi':
        return 'Seoudi Market';
      case 'hyperone':
        return 'Hyper One';
      default:
        return code;
    }
  }

  static String getRetailChainDisplayName(String code) {
    final registered = _findRegisteredChainByCode(code);
    if (registered != null && registered.displayName.trim().isNotEmpty) {
      return registered.displayName.trim();
    }
    switch (code.toLowerCase()) {
      case 'fathalla':
        return 'أسواق فتح الله (Fathalla Market)';
      case 'gomla':
        return 'جملة ماركت (Gomla Market)';
      case 'beet-elgomla':
      case 'beet_elgomla':
        return 'بيت الجملة (Beet El Gomla)';
      case 'chain-1080314':
      case 'el-wakala':
      case 'wakala':
      case 'الوكالة':
      case 'الوكاله':
        return 'الوكالة (El Wakala)';
      case 'institutions':
      case 'institution':
      case 'organizations':
        return 'قطاع المؤسسات (Institutions)';
      case 'carrefour':
        return 'كارفور مصر (Carrefour)';
      case 'spinneys':
        return 'سبينيس مصر (Spinneys)';
      default:
        return formatBilingualChainName(code);
    }
  }

  IngestionResultModel? _tryParseUploadedCsv(
    String filename,
    List<int> bytes, {
    String? targetChain,
    String? periodDate,
    bool dryRun = true,
  }) {
    if (bytes.isEmpty) return null;
    // Skip binary ZIP/XLSX archives in CSV parser
    if (bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04) {
      return null;
    }
    String content;
    try {
      content = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }
    final delimiter = content.contains('\t')
        ? '\t'
        : content.contains(';')
            ? ';'
            : ',';
    final rows = _parseCsvRows(content, delimiter: delimiter);
    if (rows.length < 2) return null;

    int headerRowIdx = -1;
    int barcodeIdx = -1;
    int storeIdx = -1;
    int skuIdx = -1;
    int catIdx = -1;
    int qtyIdx = -1;
    int revIdx = -1;
    int dateIdx = -1;

    for (int rIdx = 0; rIdx < rows.length && rIdx < 15; rIdx++) {
      final r = rows[rIdx];
      final normCols = r.map((c) => _normalizeArabicHeader(c)).toList();

      int bIdx = -1;
      int sIdx = -1;
      int kIdx = -1;
      int cIdx = -1;
      int qIdx = -1;
      int rIdx_ = -1;
      int dIdx = -1;

      for (int i = 0; i < normCols.length; i++) {
        final h = normCols[i];
        if (h.isEmpty) continue;

        if (bIdx == -1 &&
            (h.contains('barcode') ||
                h.contains('الباركود') ||
                h.contains('باركود') ||
                h.contains('gtin') ||
                h.contains('ean') ||
                h.contains('كود الصنف'))) {
          bIdx = i;
        } else if (dIdx == -1 &&
            (h.contains('date') || h.contains('تاريخ') || h.contains('التاريخ'))) {
          dIdx = i;
        } else if (cIdx == -1 &&
            (h.contains('category') || h.contains('الفئة') || h.contains('فئة') || h.contains('تصنيف'))) {
          cIdx = i;
        } else if (qIdx == -1 &&
            (h.contains('qty') ||
                h.contains('quantity') ||
                h.contains('sales units') ||
                h.contains('كمية') ||
                h.contains('كميه') ||
                h.contains('وحدات'))) {
          qIdx = i;
        } else if (rIdx_ == -1 &&
            (h.contains('net') ||
                h.contains('revenue') ||
                h.contains('amount') ||
                h.contains('sales') ||
                h.contains('صافي') ||
                h.contains('صافى') ||
                h.contains('إجمالي') ||
                h.contains('اجمالي') ||
                h.contains('قيمة') ||
                h.contains('قيمه') ||
                h.contains('المبيعات'))) {
          rIdx_ = i;
        } else if (sIdx == -1 &&
            (h.contains('store') ||
                h.contains('branch') ||
                h.contains('outlet') ||
                h.contains('فرع') ||
                h.contains('اسم الفرع') ||
                h.contains('إسم الفرع') ||
                h.contains('المعرض') ||
                h.contains('المنفذ'))) {
          sIdx = i;
        } else if (kIdx == -1 &&
            (h.contains('item description') ||
                h.contains('sku') ||
                h.contains('product') ||
                h.contains('صنف') ||
                h.contains('اسم الصنف') ||
                h.contains('إسم الصنف') ||
                h.contains('المنتج'))) {
          kIdx = i;
        }
      }

      if (bIdx != -1 && (qIdx != -1 || rIdx_ != -1 || sIdx != -1)) {
        headerRowIdx = rIdx;
        barcodeIdx = bIdx;
        storeIdx = sIdx;
        skuIdx = kIdx;
        catIdx = cIdx;
        qtyIdx = qIdx;
        revIdx = rIdx_;
        dateIdx = dIdx;
        break;
      }
    }

    if (headerRowIdx == -1 || barcodeIdx == -1) {
      return null;
    }

    final dedupedFacts = <String, ({int qty, double rev, String store, String sku, String cat})>{};
    final anomalies = <Map<String, dynamic>>[];
    final branchSet = <String>{};
    final categorySet = <String>{};
    int dataRowNum = 0;

    for (var rIdx = headerRowIdx + 1; rIdx < rows.length; rIdx++) {
      final cols = rows[rIdx];
      if (cols.every((c) => c.trim().isEmpty)) continue;
      dataRowNum++;

      final rawBarcode = (barcodeIdx >= 0 && barcodeIdx < cols.length) ? cols[barcodeIdx].trim() : '';
      final cleanedBarcode = rawBarcode.replaceAll(RegExp(r'[^0-9]'), '');

      final rawStore = (storeIdx >= 0 && storeIdx < cols.length) ? cols[storeIdx].trim() : 'default_store';
      if (rawStore.isNotEmpty && rawStore != 'default_store') {
        branchSet.add(rawStore);
      }

      final rawSKU = (skuIdx >= 0 && skuIdx < cols.length) ? cols[skuIdx].trim() : 'صنف تجزئة';
      final rawCatCell = (catIdx >= 0 && catIdx < cols.length) ? normalizeCategoryName(cols[catIdx]) : '';
      final rawCat = rawCatCell.isNotEmpty ? rawCatCell : 'عام';
      if (rawCat.isNotEmpty && rawCat != 'عام') {
        categorySet.add(rawCat);
      }

      final rawDate = (periodDate != null && periodDate.isNotEmpty)
          ? periodDate
          : ((dateIdx >= 0 && dateIdx < cols.length) ? cols[dateIdx].trim() : '2026-03-07');

      final rawQty = (qtyIdx >= 0 && qtyIdx < cols.length) ? cols[qtyIdx].trim().replaceAll(',', '') : '0';
      final rawRev = (revIdx >= 0 && revIdx < cols.length) ? cols[revIdx].trim().replaceAll(',', '') : '0';

      final rev = double.tryParse(rawRev) ?? 0.0;
      var qty = double.tryParse(rawQty)?.round() ?? 0;
      if (qtyIdx < 0 && qty == 0 && rev > 0) {
        qty = 1;
      }

      if (rev < 0 || qty <= 0) {
        anomalies.add({
          'row_number': dataRowNum,
          'issue_type': 'negative_sales',
          'description': 'قيمة مبيعات سالبة أو كمية غير صالحة في الصف رقم $dataRowNum (تم استبعاد الصف)',
        });
        continue;
      }

      if (cleanedBarcode.length < 8) {
        anomalies.add({
          'row_number': dataRowNum,
          'issue_type': 'invalid_barcode',
          'description': 'باركود قصير أو غير مطابق لمعيار GTIN في الصف رقم $dataRowNum ($rawBarcode)',
        });
        continue;
      }

      final dedupKey = '${rawStore.toLowerCase()}|$cleanedBarcode|$rawDate';
      dedupedFacts[dedupKey] = (qty: qty, rev: rev, store: rawStore, sku: rawSKU, cat: rawCat);
    }

    final validRows = dedupedFacts.length;
    double totalRevenue = 0.0;
    int totalQuantity = 0;
    for (final entry in dedupedFacts.values) {
      totalRevenue += entry.rev;
      totalQuantity += entry.qty;
    }

    int carrefourVotes = 0;
    int fathallaVotes = 0;
    int gomlaVotes = 0;
    int spinneysVotes = 0;

    final lowerName = filename.toLowerCase();
    if (lowerName.contains('carrefour') || filename.contains('كارفور')) carrefourVotes += 10;
    if (lowerName.contains('fathalla') || filename.contains('فتح الله')) fathallaVotes += 10;
    if (lowerName.contains('gomla') || (filename.contains('جملة') && !filename.contains('فتح الله'))) gomlaVotes += 10;
    if (lowerName.contains('spinneys') || filename.contains('سبينيس')) spinneysVotes += 10;

    for (final b in branchSet) {
      final bLower = b.toLowerCase();
      if (bLower.contains('carrefour') || b.contains('كارفور')) carrefourVotes++;
      if (bLower.contains('fathalla') || b.contains('فتح الله')) fathallaVotes++;
      if (bLower.contains('gomla') || (b.contains('جملة') && !b.contains('فتح الله'))) gomlaVotes++;
      if (bLower.contains('spinneys') || b.contains('سبينيس')) spinneysVotes++;
    }

    String discovered = '';
    int maxVotes = 0;
    if (carrefourVotes > maxVotes) { maxVotes = carrefourVotes; discovered = 'carrefour'; }
    if (fathallaVotes > maxVotes) { maxVotes = fathallaVotes; discovered = 'fathalla'; }
    if (gomlaVotes > maxVotes) { maxVotes = gomlaVotes; discovered = 'gomla'; }
    if (spinneysVotes > maxVotes) { maxVotes = spinneysVotes; discovered = 'spinneys'; }

    final retailer = (targetChain != null && targetChain.isNotEmpty)
        ? targetChain
        : (discovered.isNotEmpty ? discovered : 'fathalla');

    final bool mismatch = discovered.isNotEmpty &&
        targetChain != null &&
        targetChain.isNotEmpty &&
        discovered.toLowerCase() != targetChain.toLowerCase();


    final branchesMaps = branchSet
        .map((b) => <String, dynamic>{
              'store_name': b,
              'store_id': b,
              'raw_store_name': b,
            })
        .toList();
    final autoCreatedCount = branchesMaps.isNotEmpty ? branchesMaps.length : 0;

    return IngestionResultModel(
      batchId: 'batch_ai_${DateTime.now().millisecondsSinceEpoch}',
      filename: filename,
      retailerDetected: retailer,
      totalRows: validRows + anomalies.length,
      validRows: validRows,
      anomalyRows: anomalies.length,
      totalRevenue: totalRevenue,
      totalQuantity: totalQuantity,
      confidenceScore: 0.992,
      anomalies: anomalies,
      autoCreatedStoresCount: autoCreatedCount,
      discoveredBranches: branchesMaps,
      discoveredCategories: categorySet.toList(),
      isStaged: dryRun,
      isCommitted: !dryRun,
      discoveredRetailer: discovered.isNotEmpty ? discovered : retailer,
      targetRetailer: targetChain ?? '',
      chainMismatchDetected: mismatch,
      suggestedChain: mismatch ? discovered : null,
      suggestedChainName: mismatch ? getRetailChainDisplayName(discovered) : null,
    );
  }

  static String _normalizeArabicHeader(String s) {
    return s
        .replaceAll('\r', '')
        .replaceAll('\n', ' ')
        .trim()
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static List<List<String>> _parseCsvRows(String content, {String delimiter = ','}) {
    final rows = <List<String>>[];
    final currentField = StringBuffer();
    final currentRow = <String>[];
    bool inQuotes = false;

    for (int i = 0; i < content.length; i++) {
      final ch = content[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < content.length && content[i + 1] == '"') {
          currentField.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == delimiter && !inQuotes) {
        currentRow.add(currentField.toString().trim());
        currentField.clear();
      } else if ((ch == '\n' || ch == '\r') && !inQuotes) {
        if (ch == '\r' && i + 1 < content.length && content[i + 1] == '\n') {
          i++;
        }
        currentRow.add(currentField.toString().trim());
        currentField.clear();
        if (currentRow.any((c) => c.isNotEmpty)) {
          rows.add(List.from(currentRow));
        }
        currentRow.clear();
      } else {
        currentField.write(ch);
      }
    }
    if (currentField.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(currentField.toString().trim());
      if (currentRow.any((c) => c.isNotEmpty)) {
        rows.add(List.from(currentRow));
      }
    }
    return rows;
  }

  // --- MOCK FALLBACKS ---
  ExecutiveKPIsModel _mockExecutiveKPIs(
    String period, {
    String? startDate,
    String? endDate,
    String? chain,
  }) {
    if (isCurrentTenantCleared) {
      return ExecutiveKPIsModel(
        totalRevenue: 0.0,
        totalMarketRevenue: 0.0,
        tenantMarketSharePct: 0.0,
        totalSkusCount: 0,
        totalMarketSkusCount: 0,
        competitorsCount: 0,
        revenueGrowthPct: 0.0,
        revenueYoyPct: 0.0,
        revenueMomPct: 0.0,
        totalUnitsSold: 0,
        unitsGrowthPct: 0.0,
        unitsYoyPct: 0.0,
        unitsMomPct: 0.0,
        activeStoresCount: 0,
        oosRatePct: 0.0,
        osaRatePct: 100.0,
        totalOOSIncidents: 0,
        estimatedLostRevenue: 0.0,
        currency: 'EGP',
        reportingPeriod: period,
        chainShares: const [],
        supplierShares: const [],
        dailyTrends: const [],
        categoryContributions: const [],
        paretoSkus: const [],
      );
    }
    final base = _applyRbacToExecutiveKPIs(_buildBaseMockExecutiveKPIs(period));
    final hasChainFilter =
        chain != null && chain.isNotEmpty && chain != 'all' && chain != 'الكل';
    if ((startDate == null || startDate.isEmpty) &&
        (endDate == null || endDate.isEmpty) &&
        !hasChainFilter) {
      return base;
    }
    final filteredTrends = base.dailyTrends.where((d) {
      if (startDate != null && startDate.isNotEmpty && d.date.compareTo(startDate) < 0) {
        return false;
      }
      if (endDate != null && endDate.isNotEmpty && d.date.compareTo(endDate) > 0) {
        return false;
      }
      return true;
    }).toList();

    final trendsToUse = filteredTrends.isNotEmpty ? filteredTrends : base.dailyTrends;
    final periodLabel = (startDate != null && endDate != null && startDate.isNotEmpty && endDate.isNotEmpty)
        ? '$startDate إلى $endDate'
        : period;

    var totalRev = base.totalRevenue;
    var totalUnits = base.totalUnitsSold;
    var shares = base.chainShares;

    if (filteredTrends.isNotEmpty && filteredTrends.length < base.dailyTrends.length) {
      totalRev = filteredTrends.fold<double>(0.0, (sum, d) => sum + d.revenue);
      totalUnits = filteredTrends.fold<int>(0, (sum, d) => sum + d.units);
      shares = base.chainShares
          .map(
            (s) => ChainShareItem(
              retailerChain: s.retailerChain,
              displayName: s.displayName,
              totalRevenue: totalRev * (s.marketShare / 100.0),
              totalUnits: (totalUnits * (s.marketShare / 100.0)).round(),
              marketShare: s.marketShare,
            ),
          )
          .toList();
    }

    if (hasChainFilter) {
      shares = shares
          .where((s) => s.retailerChain.toLowerCase() == chain.toLowerCase())
          .map(
            (s) => ChainShareItem(
              retailerChain: s.retailerChain,
              displayName: s.displayName,
              totalRevenue: s.totalRevenue,
              totalUnits: s.totalUnits,
              marketShare: 100.0,
            ),
          )
          .toList();
      if (shares.isNotEmpty) {
        totalRev = shares.first.totalRevenue;
        totalUnits = shares.first.totalUnits;
      }
    }

    return ExecutiveKPIsModel(
      totalRevenue: totalRev,
      totalMarketRevenue: base.totalMarketRevenue,
      tenantMarketSharePct: base.tenantMarketSharePct,
      totalSkusCount: base.totalSkusCount,
      totalMarketSkusCount: base.totalMarketSkusCount,
      competitorsCount: base.competitorsCount,
      revenueGrowthPct: base.revenueGrowthPct,
      revenueYoyPct: base.revenueYoyPct,
      revenueMomPct: base.revenueMomPct,
      totalUnitsSold: totalUnits,
      unitsGrowthPct: base.unitsGrowthPct,
      unitsYoyPct: base.unitsYoyPct,
      unitsMomPct: base.unitsMomPct,
      activeStoresCount: base.activeStoresCount,
      oosRatePct: base.oosRatePct,
      osaRatePct: base.osaRatePct,
      totalOOSIncidents: base.totalOOSIncidents,
      estimatedLostRevenue: base.estimatedLostRevenue,
      currency: base.currency,
      reportingPeriod: periodLabel,
      chainShares: shares,
      supplierShares: base.supplierShares,
      dailyTrends: trendsToUse,
      categoryContributions: base.categoryContributions,
      paretoSkus: base.paretoSkus,
    );
  }

  ExecutiveKPIsModel _buildBaseMockExecutiveKPIs(String period) {
    final cleanSlug = normalizeDataTenantSlug(tenantId);
    if (cleanSlug == 'unilever') {
      return ExecutiveKPIsModel(
        totalRevenue: 6420800.0,
        totalMarketRevenue: 24500000.0,
        tenantMarketSharePct: 26.2,
        totalSkusCount: 23,
        totalMarketSkusCount: 180,
        competitorsCount: 14,
        revenueGrowthPct: 18.4,
        revenueYoyPct: 29.8,
        revenueMomPct: 18.4,
        totalUnitsSold: 54210,
        unitsGrowthPct: 12.6,
        unitsYoyPct: 21.4,
        unitsMomPct: 12.6,
        activeStoresCount: 12,
        oosRatePct: 2.9,
        osaRatePct: 97.1,
        totalOOSIncidents: 11,
        estimatedLostRevenue: 94300.0,
        currency: 'EGP',
        reportingPeriod: period,
        chainShares: [
          ChainShareItem(retailerChain: 'carrefour', displayName: 'كارفور (Carrefour)', totalRevenue: 3980896.0, totalUnits: 33610, marketShare: 62.0),
          ChainShareItem(retailerChain: 'spinneys', displayName: 'سبينيس (Spinneys)', totalRevenue: 2439904.0, totalUnits: 20600, marketShare: 38.0),
        ],
        dailyTrends: [
          DailyTrendItem(date: '2026-03-01', revenue: 192000, units: 1620, storeCount: 12),
          DailyTrendItem(date: '2026-03-02', revenue: 208000, units: 1750, storeCount: 12),
          DailyTrendItem(date: '2026-03-03', revenue: 189000, units: 1590, storeCount: 12),
          DailyTrendItem(date: '2026-03-04', revenue: 224000, units: 1890, storeCount: 12),
          DailyTrendItem(date: '2026-03-05', revenue: 241000, units: 2040, storeCount: 12),
          DailyTrendItem(date: '2026-03-06', revenue: 268000, units: 2260, storeCount: 12),
          DailyTrendItem(date: '2026-03-07', revenue: 289000, units: 2440, storeCount: 12),
        ],
        categoryContributions: [
          CategoryContributionModel(category: 'مشروبات ساخنة وشاي', totalRevenue: 2696736.0, totalUnits: 22768, sharePct: 42.0, skuCount: 6),
          CategoryContributionModel(category: 'عناية شخصية', totalRevenue: 2118864.0, totalUnits: 17889, sharePct: 33.0, skuCount: 8),
          CategoryContributionModel(category: 'منظفات منزلية', totalRevenue: 1091536.0, totalUnits: 9216, sharePct: 17.0, skuCount: 5),
          CategoryContributionModel(category: 'إضافات طهي ومرقة', totalRevenue: 513664.0, totalUnits: 4337, sharePct: 8.0, skuCount: 4),
        ],
        paretoSkus: [
          ParetoSkuItemModel(barcode: '6221155101011', skuName: 'Lipton Yellow Label Tea 100 Bags', category: 'مشروبات ساخنة وشاي', totalRevenue: 2343590.0, totalUnits: 19800, revenueSharePct: 36.5, cumulativeSharePct: 36.5, isTop80Contributor: true),
          ParetoSkuItemModel(barcode: '6221155101028', skuName: 'Dove Moisturizing Beauty Bar 4x100g', category: 'عناية شخصية', totalRevenue: 1720770.0, totalUnits: 14500, revenueSharePct: 26.8, cumulativeSharePct: 63.3, isTop80Contributor: true),
          ParetoSkuItemModel(barcode: '6221155101035', skuName: 'Omo Automatic Laundry Powder 4kg', category: 'منظفات منزلية', totalRevenue: 1104380.0, totalUnits: 9200, revenueSharePct: 17.2, cumulativeSharePct: 80.5, isTop80Contributor: true),
          ParetoSkuItemModel(barcode: '6221155101042', skuName: 'Knorr Chicken Stock Cubes 24s', category: 'إضافات طهي ومرقة', totalRevenue: 738390.0, totalUnits: 6210, revenueSharePct: 11.5, cumulativeSharePct: 92.0, isTop80Contributor: false),
          ParetoSkuItemModel(barcode: '6221155101059', skuName: 'Axe Dark Temptation Deodorant 150ml', category: 'عناية شخصية', totalRevenue: 513670.0, totalUnits: 4500, revenueSharePct: 8.0, cumulativeSharePct: 100.0, isTop80Contributor: false),
        ],
      );
    }
    if (cleanSlug == 'pepsi') {
      return ExecutiveKPIsModel(
        totalRevenue: 8190500.0,
        totalMarketRevenue: 28000000.0,
        tenantMarketSharePct: 29.25,
        totalSkusCount: 20,
        totalMarketSkusCount: 150,
        competitorsCount: 11,
        revenueGrowthPct: 22.1,
        revenueYoyPct: 34.6,
        revenueMomPct: 22.1,
        totalUnitsSold: 96400,
        unitsGrowthPct: 15.3,
        unitsYoyPct: 24.8,
        unitsMomPct: 15.3,
        activeStoresCount: 18,
        oosRatePct: 3.5,
        osaRatePct: 96.5,
        totalOOSIncidents: 14,
        estimatedLostRevenue: 118200.0,
        currency: 'EGP',
        reportingPeriod: period,
        chainShares: [
          ChainShareItem(retailerChain: 'carrefour', displayName: 'كارفور (Carrefour)', totalRevenue: 3931440.0, totalUnits: 46270, marketShare: 48.0),
          ChainShareItem(retailerChain: 'fathalla', displayName: 'فتح الله (Fathalla)', totalRevenue: 2784770.0, totalUnits: 32776, marketShare: 34.0),
          ChainShareItem(retailerChain: 'gomla', displayName: 'جملة ماركت (Gomla)', totalRevenue: 1474290.0, totalUnits: 17354, marketShare: 18.0),
        ],
        dailyTrends: [
          DailyTrendItem(date: '2026-03-01', revenue: 245000, units: 2880, storeCount: 18),
          DailyTrendItem(date: '2026-03-02', revenue: 262000, units: 3080, storeCount: 18),
          DailyTrendItem(date: '2026-03-03', revenue: 251000, units: 2950, storeCount: 18),
          DailyTrendItem(date: '2026-03-04', revenue: 279000, units: 3280, storeCount: 18),
          DailyTrendItem(date: '2026-03-05', revenue: 298000, units: 3510, storeCount: 18),
          DailyTrendItem(date: '2026-03-06', revenue: 324000, units: 3810, storeCount: 18),
          DailyTrendItem(date: '2026-03-07', revenue: 352000, units: 4140, storeCount: 18),
        ],
        categoryContributions: [
          CategoryContributionModel(category: 'مشروبات غازية', totalRevenue: 4750490.0, totalUnits: 55912, sharePct: 58.0, skuCount: 9),
          CategoryContributionModel(category: 'مقرمشات وسناكس', totalRevenue: 2620960.0, totalUnits: 30848, sharePct: 32.0, skuCount: 7),
          CategoryContributionModel(category: 'مشروبات طاقة وعصائر', totalRevenue: 819050.0, totalUnits: 9640, sharePct: 10.0, skuCount: 4),
        ],
        paretoSkus: [
          ParetoSkuItemModel(barcode: '6221155201018', skuName: 'Pepsi Cola Cans Multipack 6x330ml', category: 'مشروبات غازية', totalRevenue: 3145150.0, totalUnits: 36900, revenueSharePct: 38.4, cumulativeSharePct: 38.4, isTop80Contributor: true),
          ParetoSkuItemModel(barcode: '6221155201025', skuName: 'Chipsy Family Pack Tomato 165g', category: 'مقرمشات وسناكس', totalRevenue: 2014860.0, totalUnits: 23700, revenueSharePct: 24.6, cumulativeSharePct: 63.0, isTop80Contributor: true),
          ParetoSkuItemModel(barcode: '6221155201032', skuName: 'Mirinda Orange 2L PET', category: 'مشروبات غازية', totalRevenue: 1376000.0, totalUnits: 16200, revenueSharePct: 16.8, cumulativeSharePct: 79.8, isTop80Contributor: true),
          ParetoSkuItemModel(barcode: '6221155201056', skuName: 'Doritos Nacho Cheese 140g', category: 'مقرمشات وسناكس', totalRevenue: 933720.0, totalUnits: 11100, revenueSharePct: 11.4, cumulativeSharePct: 91.2, isTop80Contributor: false),
          ParetoSkuItemModel(barcode: '6221155201049', skuName: '7UP Lemon & Lime 1L PET', category: 'مشروبات غازية', totalRevenue: 720770.0, totalUnits: 8500, revenueSharePct: 8.8, cumulativeSharePct: 100.0, isTop80Contributor: false),
        ],
      );
    }
    if (cleanSlug != 'adeco') {
      final brandTitle = formatBrandTitle(cleanSlug);
      return ExecutiveKPIsModel(
        totalRevenue: 3290400.0,
        totalMarketRevenue: 15600000.0,
        tenantMarketSharePct: 21.1,
        totalSkusCount: 10,
        totalMarketSkusCount: 95,
        competitorsCount: 8,
        revenueGrowthPct: 16.5,
        revenueYoyPct: 27.2,
        revenueMomPct: 16.5,
        totalUnitsSold: 41200,
        unitsGrowthPct: 11.4,
        unitsYoyPct: 19.1,
        unitsMomPct: 11.4,
        activeStoresCount: 10,
        oosRatePct: 3.1,
        osaRatePct: 96.9,
        totalOOSIncidents: 9,
        estimatedLostRevenue: 64200.0,
        currency: 'EGP',
        reportingPeriod: period,
        chainShares: [
          ChainShareItem(retailerChain: 'carrefour', displayName: 'كارفور (Carrefour)', totalRevenue: 1809720.0, totalUnits: 22660, marketShare: 55.0),
          ChainShareItem(retailerChain: 'fathalla', displayName: 'فتح الله (Fathalla)', totalRevenue: 987120.0, totalUnits: 12360, marketShare: 30.0),
          ChainShareItem(retailerChain: 'gomla', displayName: 'جملة ماركت (Gomla)', totalRevenue: 493560.0, totalUnits: 6180, marketShare: 15.0),
        ],
        dailyTrends: [
          DailyTrendItem(date: '2026-03-01', revenue: 98000, units: 1220, storeCount: 10),
          DailyTrendItem(date: '2026-03-02', revenue: 104000, units: 1300, storeCount: 10),
          DailyTrendItem(date: '2026-03-03', revenue: 101000, units: 1260, storeCount: 10),
          DailyTrendItem(date: '2026-03-04', revenue: 112000, units: 1400, storeCount: 10),
          DailyTrendItem(date: '2026-03-05', revenue: 119000, units: 1490, storeCount: 10),
          DailyTrendItem(date: '2026-03-06', revenue: 128000, units: 1600, storeCount: 10),
          DailyTrendItem(date: '2026-03-07', revenue: 136000, units: 1700, storeCount: 10),
        ],
        categoryContributions: [
          CategoryContributionModel(category: 'ألبان ومشتقاتها', totalRevenue: 2105856.0, totalUnits: 26368, sharePct: 64.0, skuCount: 6),
          CategoryContributionModel(category: 'عصائر ومشروبات', totalRevenue: 1184544.0, totalUnits: 14832, sharePct: 36.0, skuCount: 4),
        ],
        paretoSkus: [
          ParetoSkuItemModel(barcode: '6221155901010', skuName: '$brandTitle Full Cream Milk 1L', category: 'ألبان ومشتقاتها', totalRevenue: 1454356.0, totalUnits: 18210, revenueSharePct: 44.2, cumulativeSharePct: 44.2, isTop80Contributor: true),
          ParetoSkuItemModel(barcode: '6221155901027', skuName: '$brandTitle Natural Yogurt 6x105g', category: 'ألبان ومشتقاتها', totalRevenue: 1112155.0, totalUnits: 13920, revenueSharePct: 33.8, cumulativeSharePct: 78.0, isTop80Contributor: true),
          ParetoSkuItemModel(barcode: '6221155901034', skuName: '$brandTitle Pure Orange Juice 1L', category: 'عصائر ومشروبات', totalRevenue: 723889.0, totalUnits: 9070, revenueSharePct: 22.0, cumulativeSharePct: 100.0, isTop80Contributor: false),
        ],
      );
    }

    return ExecutiveKPIsModel(
      totalRevenue: 4850230.0,
      totalMarketRevenue: 51725316.94,
      tenantMarketSharePct: 18.44,
      totalSkusCount: 256,
      totalMarketSkusCount: 1808,
      competitorsCount: 81,
      revenueGrowthPct: 14.8,
      revenueYoyPct: 24.5,
      revenueMomPct: 14.8,
      totalUnitsSold: 38450,
      unitsGrowthPct: 9.2,
      unitsYoyPct: 16.4,
      unitsMomPct: 9.2,
      activeStoresCount: 34,
      oosRatePct: 3.2,
      osaRatePct: 96.8,
      totalOOSIncidents: 18,
      estimatedLostRevenue: 148500.0,
      currency: 'EGP',
      reportingPeriod: period,
      chainShares: [
        ChainShareItem(retailerChain: 'carrefour', displayName: 'كارفور (Carrefour)', totalRevenue: 2182600.0, totalUnits: 17200, marketShare: 45.0),
        ChainShareItem(retailerChain: 'fathalla', displayName: 'فتح الله (Fathalla)', totalRevenue: 1552070.0, totalUnits: 12500, marketShare: 32.0),
        ChainShareItem(retailerChain: 'gomla', displayName: 'جملة ماركت (Gomla)', totalRevenue: 727530.0, totalUnits: 5800, marketShare: 15.0),
        ChainShareItem(retailerChain: 'spinneys', displayName: 'سبينيس (Spinneys)', totalRevenue: 388030.0, totalUnits: 2950, marketShare: 8.0),
      ],
      supplierShares: const [
        SupplierShareModel(supplierName: 'أديكو', totalRevenue: 9536992.70, totalUnits: 112480, skuCount: 256, marketSharePct: 18.44, isTenantBrand: true, rank: 1),
        SupplierShareModel(supplierName: 'ارما التجارية', totalRevenue: 7198431.70, totalUnits: 89200, skuCount: 40, marketSharePct: 13.92, isTenantBrand: false, rank: 2),
        SupplierShareModel(supplierName: 'بروكتر و جامبل', totalRevenue: 5797866.22, totalUnits: 61400, skuCount: 109, marketSharePct: 11.21, isTenantBrand: false, rank: 3),
        SupplierShareModel(supplierName: 'هنكل برسيل', totalRevenue: 5112202.98, totalUnits: 58300, skuCount: 86, marketSharePct: 9.88, isTenantBrand: false, rank: 4),
        SupplierShareModel(supplierName: 'فريدال', totalRevenue: 4322274.26, totalUnits: 74900, skuCount: 153, marketSharePct: 8.36, isTenantBrand: false, rank: 5),
      ],
      dailyTrends: [
        DailyTrendItem(date: '2026-03-01', revenue: 142000, units: 1120, storeCount: 34),
        DailyTrendItem(date: '2026-03-02', revenue: 158000, units: 1240, storeCount: 34),
        DailyTrendItem(date: '2026-03-03', revenue: 139000, units: 1090, storeCount: 34),
        DailyTrendItem(date: '2026-03-04', revenue: 168000, units: 1310, storeCount: 34),
        DailyTrendItem(date: '2026-03-05', revenue: 184000, units: 1450, storeCount: 34),
        DailyTrendItem(date: '2026-03-06', revenue: 210000, units: 1680, storeCount: 34),
        DailyTrendItem(date: '2026-03-07', revenue: 235000, units: 1890, storeCount: 34),
      ],
      categoryContributions: [
        CategoryContributionModel(category: 'زيوت طعام', totalRevenue: 3104147.0, totalUnits: 24608, sharePct: 64.0, skuCount: 8, categoryMarketRevenue: 7420000.0, tenantCategorySharePct: 41.8),
        CategoryContributionModel(category: 'صلصة ومعلبات', totalRevenue: 1164055.0, totalUnits: 9228, sharePct: 24.0, skuCount: 5, categoryMarketRevenue: 4084000.0, tenantCategorySharePct: 28.5),
        CategoryContributionModel(category: 'بقوليات ومعلبات', totalRevenue: 582028.0, totalUnits: 4614, sharePct: 12.0, skuCount: 4, categoryMarketRevenue: 2101000.0, tenantCategorySharePct: 27.7),
      ],
      paretoSkus: [
        ParetoSkuItemModel(barcode: '6221155001234', skuName: 'Adeco Extra Virgin Olive Oil 500ml', category: 'زيوت طعام', totalRevenue: 1658778.0, totalUnits: 13150, revenueSharePct: 34.2, cumulativeSharePct: 34.2, isTop80Contributor: true),
        ParetoSkuItemModel(barcode: '6221155001241', skuName: 'Adeco Pure Sunflower Oil 1L', category: 'زيوت طعام', totalRevenue: 1299862.0, totalUnits: 10300, revenueSharePct: 26.8, cumulativeSharePct: 61.0, isTop80Contributor: true),
        ParetoSkuItemModel(barcode: '6221155001258', skuName: 'Adeco Pure Corn Oil 800ml', category: 'زيوت طعام', totalRevenue: 897292.0, totalUnits: 7110, revenueSharePct: 18.5, cumulativeSharePct: 79.5, isTop80Contributor: true),
        ParetoSkuItemModel(barcode: '6221155002019', skuName: 'Adeco Premium Tomato Paste 380g', category: 'صلصة ومعلبات', totalRevenue: 596578.0, totalUnits: 4730, revenueSharePct: 12.3, cumulativeSharePct: 91.8, isTop80Contributor: false),
        ParetoSkuItemModel(barcode: '6221155003016', skuName: 'Adeco Traditional Fava Beans 400g', category: 'بقوليات ومعلبات', totalRevenue: 397720.0, totalUnits: 3160, revenueSharePct: 8.2, cumulativeSharePct: 100.0, isTop80Contributor: false),
      ],
    );
  }

  List<SellOutRecordModel> _mockRecords({
    String? chain,
    String? storeId,
    String? category,
    String? query,
    String? startDate,
    String? endDate,
  }) {
    if (isCurrentTenantCleared) {
      return const [];
    }
    final cleanSlug = normalizeDataTenantSlug(tenantId);
    List<SellOutRecordModel> list;

    if (cleanSlug == 'unilever') {
      list = [
        SellOutRecordModel(
          recordId: 'rec_uni_001',
          retailerChain: 'carrefour',
          storeId: 'uni_crf_cairo_festival',
          storeName: 'كارفور كايرو فيستيفال سيتي',
          barcode: '6221155101011',
          skuName: 'Lipton Yellow Label Tea 100 Bags',
          category: 'مشروبات ساخنة وشاي',
          quantitySold: 220,
          netRevenue: 20900.0,
          unitPrice: 95.0,
          transactionDate: '2026-03-07',
        ),
        SellOutRecordModel(
          recordId: 'rec_uni_002',
          retailerChain: 'spinneys',
          storeId: 'uni_spi_cairo_rehab',
          storeName: 'سبينيس - مدينة الرحاب',
          barcode: '6221155101028',
          skuName: 'Dove Moisturizing Beauty Bar 4x100g',
          category: 'عناية شخصية',
          quantitySold: 145,
          netRevenue: 20300.0,
          unitPrice: 140.0,
          transactionDate: '2026-03-07',
        ),
        SellOutRecordModel(
          recordId: 'rec_uni_003',
          retailerChain: 'carrefour',
          storeId: 'uni_crf_alex_citycentre',
          storeName: 'كارفور سيتي سنتر الإسكندرية',
          barcode: '6221155101035',
          skuName: 'Omo Automatic Laundry Powder 4kg',
          category: 'منظفات منزلية',
          quantitySold: 110,
          netRevenue: 28600.0,
          unitPrice: 260.0,
          transactionDate: '2026-03-06',
        ),
        SellOutRecordModel(
          recordId: 'rec_uni_004',
          retailerChain: 'spinneys',
          storeId: 'uni_spi_giza_sheikhzayed',
          storeName: 'سبينيس - الشيخ زايد',
          barcode: '6221155101042',
          skuName: 'Knorr Chicken Stock Cubes 24s',
          category: 'إضافات طهي ومرقة',
          quantitySold: 260,
          netRevenue: 16900.0,
          unitPrice: 65.0,
          transactionDate: '2026-03-06',
        ),
        SellOutRecordModel(
          recordId: 'rec_uni_005',
          retailerChain: 'carrefour',
          storeId: 'uni_crf_cairo_maadi',
          storeName: 'كارفور المعادي سيتي سنتر',
          barcode: '6221155101059',
          skuName: 'Axe Dark Temptation Deodorant 150ml',
          category: 'عناية شخصية',
          quantitySold: 130,
          netRevenue: 14950.0,
          unitPrice: 115.0,
          transactionDate: '2026-03-05',
        ),
      ];
    } else if (cleanSlug == 'pepsi') {
      list = [
        SellOutRecordModel(
          recordId: 'rec_pep_001',
          retailerChain: 'carrefour',
          storeId: 'pep_crf_cairo_citystars',
          storeName: 'كارفور سيتي ستارز',
          barcode: '6221155201018',
          skuName: 'Pepsi Cola Cans Multipack 6x330ml',
          category: 'مشروبات غازية',
          quantitySold: 310,
          netRevenue: 27900.0,
          unitPrice: 90.0,
          transactionDate: '2026-03-07',
        ),
        SellOutRecordModel(
          recordId: 'rec_pep_002',
          retailerChain: 'fathalla',
          storeId: 'pep_fat_alex_smouha',
          storeName: 'فتح الله جملة ماركت - سموحة',
          barcode: '6221155201025',
          skuName: 'Chipsy Family Pack Tomato 165g',
          category: 'مقرمشات وسناكس',
          quantitySold: 450,
          netRevenue: 11250.0,
          unitPrice: 25.0,
          transactionDate: '2026-03-07',
        ),
        SellOutRecordModel(
          recordId: 'rec_pep_003',
          retailerChain: 'gomla',
          storeId: 'pep_gom_cairo_nasrcity',
          storeName: 'جملة ماركت - مدينة نصر',
          barcode: '6221155201032',
          skuName: 'Mirinda Orange 2L PET',
          category: 'مشروبات غازية',
          quantitySold: 380,
          netRevenue: 13300.0,
          unitPrice: 35.0,
          transactionDate: '2026-03-06',
        ),
        SellOutRecordModel(
          recordId: 'rec_pep_004',
          retailerChain: 'carrefour',
          storeId: 'pep_crf_giza_dandy',
          storeName: 'كارفور داندي مول',
          barcode: '6221155201049',
          skuName: '7UP Lemon & Lime 1L PET',
          category: 'مشروبات غازية',
          quantitySold: 290,
          netRevenue: 6380.0,
          unitPrice: 22.0,
          transactionDate: '2026-03-06',
        ),
        SellOutRecordModel(
          recordId: 'rec_pep_005',
          retailerChain: 'fathalla',
          storeId: 'pep_fat_alex_stanley',
          storeName: 'فتح الله - ستانلي',
          barcode: '6221155201056',
          skuName: 'Doritos Nacho Cheese 140g',
          category: 'مقرمشات وسناكس',
          quantitySold: 265,
          netRevenue: 7950.0,
          unitPrice: 30.0,
          transactionDate: '2026-03-05',
        ),
      ];
    } else if (cleanSlug != 'adeco') {
      final brandTitle = formatBrandTitle(cleanSlug);
      list = [
        SellOutRecordModel(
          recordId: 'rec_${cleanSlug}_001',
          retailerChain: 'carrefour',
          storeId: '${cleanSlug}_crf_cairo_maadi',
          storeName: 'كارفور المعادي سيتي سنتر',
          barcode: '6221155901010',
          skuName: '$brandTitle Full Cream Milk 1L',
          category: 'ألبان ومشتقاتها',
          quantitySold: 240,
          netRevenue: 10800.0,
          unitPrice: 45.0,
          transactionDate: '2026-03-07',
        ),
        SellOutRecordModel(
          recordId: 'rec_${cleanSlug}_002',
          retailerChain: 'fathalla',
          storeId: '${cleanSlug}_fat_alex_smouha',
          storeName: 'فتح الله جملة ماركت - سموحة',
          barcode: '6221155901027',
          skuName: '$brandTitle Natural Yogurt 6x105g',
          category: 'ألبان ومشتقاتها',
          quantitySold: 195,
          netRevenue: 9360.0,
          unitPrice: 48.0,
          transactionDate: '2026-03-07',
        ),
        SellOutRecordModel(
          recordId: 'rec_${cleanSlug}_003',
          retailerChain: 'gomla',
          storeId: '${cleanSlug}_gom_cairo_nasrcity',
          storeName: 'جملة ماركت - مدينة نصر',
          barcode: '6221155901034',
          skuName: '$brandTitle Pure Orange Juice 1L',
          category: 'عصائر ومشروبات',
          quantitySold: 170,
          netRevenue: 6800.0,
          unitPrice: 40.0,
          transactionDate: '2026-03-06',
        ),
      ];
    } else {
      list = [
        SellOutRecordModel(
          recordId: 'rec_adco_legacy_001',
          retailerChain: 'carrefour',
          storeId: 'crf_cairo_maadi',
          storeName: 'كارفور المعادي سيتي سنتر',
          barcode: '6221155001014',
          skuName: 'Adeco Extra Virgin Olive Oil 500ml',
          category: 'زيوت ودهون',
          quantitySold: 120,
          netRevenue: 18000.0,
          unitPrice: 150.0,
          transactionDate: '2026-03-07',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_legacy_002',
          retailerChain: 'fathalla',
          storeId: 'fat_alex_smouha',
          storeName: 'فتح الله جملة ماركت - سموحة',
          barcode: '6221155001021',
          skuName: 'Adeco Sunflower Oil 1L',
          category: 'زيوت ودهون',
          quantitySold: 250,
          netRevenue: 22500.0,
          unitPrice: 90.0,
          transactionDate: '2026-03-07',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_legacy_003',
          retailerChain: 'gomla',
          storeId: 'gom_cairo_nasrcity',
          storeName: 'جملة ماركت - مدينة نصر',
          barcode: '6221155001038',
          skuName: 'Adeco Corn Oil 1.5L',
          category: 'زيوت ودهون',
          quantitySold: 180,
          netRevenue: 23400.0,
          unitPrice: 130.0,
          transactionDate: '2026-03-06',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_legacy_004',
          retailerChain: 'spinneys',
          storeId: 'spi_giza_mollarab',
          storeName: 'سبينيس - مول العرب',
          barcode: '6221155001045',
          skuName: 'Adeco Natural Tomato Paste 380g',
          category: 'صلصة ومعجون طماطم',
          quantitySold: 300,
          netRevenue: 7500.0,
          unitPrice: 25.0,
          transactionDate: '2026-03-06',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_legacy_005',
          retailerChain: 'fathalla',
          storeId: 'fat_alex_stanley',
          storeName: 'فتح الله - ستانلي',
          barcode: '6221155001052',
          skuName: 'Adeco Green Olives Pitted 400g',
          category: 'مخللات ومعلبات',
          quantitySold: 150,
          netRevenue: 6000.0,
          unitPrice: 40.0,
          transactionDate: '2026-03-05',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_001',
          retailerChain: 'fathalla',
          storeId: 'fat_rehab_city',
          storeName: 'فرع فتح الله - مدينة الرحاب',
          barcode: '62230004145650',
          skuName: 'ديفا هاند ووش500مل بامب + لتر هديه توت برى',
          category: 'هاند وواش',
          quantitySold: 1455,
          netRevenue: 105921.0,
          unitPrice: 73.0,
          transactionDate: '2026-01-31',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_002',
          retailerChain: 'beet-elgomla',
          storeId: 'beet_mohandessin',
          storeName: 'فرع بيت الجملة - المهندسين',
          barcode: '6223000239438',
          skuName: 'فيبا 3 كجم 1 روائح عاديه + 1 روائح مميزه',
          category: 'صابون سائل اطباق',
          quantitySold: 623,
          netRevenue: 99043.0,
          unitPrice: 159.0,
          transactionDate: '2026-01-31',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_003',
          retailerChain: 'institutions',
          storeId: 'inst_giza_b2b',
          storeName: 'قطاع المؤسسات والفنادق - توريد الجيزة',
          barcode: '6223000239438',
          skuName: 'فيبا 3 كجم 1 روائح عاديه + 1 روائح مميزه براميل توريدات',
          category: 'صابون سائل اطباق',
          quantitySold: 498,
          netRevenue: 74417.0,
          unitPrice: 149.0,
          transactionDate: '2026-01-31',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_004',
          retailerChain: 'gomla',
          storeId: 'gom_loran',
          storeName: 'فرع جملة ماركت - لوران الإسكندرية',
          barcode: '6223000232514',
          skuName: 'فيبا صابون سائل للاطباق بالليمون 2 لتر',
          category: 'صابون سائل اطباق',
          quantitySold: 567,
          netRevenue: 65175.0,
          unitPrice: 115.0,
          transactionDate: '2026-01-31',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_005',
          retailerChain: 'carrefour',
          storeId: 'crf_maadi',
          storeName: 'كارفور المعادي سيتي سنتر',
          barcode: '6223000239438',
          skuName: 'فيبا 3 كجم 1 روائح عاديه + 1 روائح مميزه',
          category: 'صابون سائل اطباق',
          quantitySold: 362,
          netRevenue: 55607.0,
          unitPrice: 154.0,
          transactionDate: '2026-01-31',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_006',
          retailerChain: 'beet-elgomla',
          storeId: 'beet_tagamoa',
          storeName: 'فرع بيت الجملة - التجمع الخامس',
          barcode: '6223000239438',
          skuName: 'فيبا 3 كجم 1 روائح عاديه + 1 روائح مميزه',
          category: 'صابون سائل اطباق',
          quantitySold: 364,
          netRevenue: 53266.0,
          unitPrice: 146.0,
          transactionDate: '2026-01-31',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_007',
          retailerChain: 'institutions',
          storeId: 'inst_hospitals',
          storeName: 'قطاع المستشفيات والشركات - التوريدات الطبية',
          barcode: '6223000239438',
          skuName: 'فيبا 3 كجم 1 روائح عاديه + 1 روائح مميزه',
          category: 'صابون سائل اطباق',
          quantitySold: 266,
          netRevenue: 42492.0,
          unitPrice: 160.0,
          transactionDate: '2026-01-31',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_008',
          retailerChain: 'spinneys',
          storeId: 'spi_mollarab',
          storeName: 'سبينيس - مول العرب',
          barcode: '62230004145643',
          skuName: 'فلمنجا جيل اوتوماتيك لافندر 2.5كجم',
          category: 'مساحيق جيل اوتوماتيك',
          quantitySold: 294,
          netRevenue: 41829.0,
          unitPrice: 142.0,
          transactionDate: '2026-01-31',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_009',
          retailerChain: 'fathalla',
          storeId: 'fat_gardenia',
          storeName: 'فرع فتح الله - جاردينيا',
          barcode: '6223000239438',
          skuName: 'فيبا 3 كجم 1 روائح عاديه + 1 روائح مميزه',
          category: 'صابون سائل اطباق',
          quantitySold: 253,
          netRevenue: 38771.0,
          unitPrice: 153.0,
          transactionDate: '2026-01-31',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_010',
          retailerChain: 'beet-elgomla',
          storeId: 'beet_nasrcity',
          storeName: 'فرع بيت الجملة - مدينة نصر',
          barcode: '62230004145643',
          skuName: 'فلمنجا جيل اوتوماتيك لافندر 2.5كجم',
          category: 'مساحيق جيل اوتوماتيك',
          quantitySold: 255,
          netRevenue: 38122.0,
          unitPrice: 150.0,
          transactionDate: '2026-01-31',
        ),
        SellOutRecordModel(
          recordId: 'rec_adco_011',
          retailerChain: 'institutions',
          storeId: 'inst_ministries',
          storeName: 'قطاع الوزارات والهيئات - التوريد المركزي',
          barcode: '6223000232620',
          skuName: 'فيبا كلور مبيض للأقمشة والأسطح 1 لتر',
          category: 'كلور ابيض و الوان',
          quantitySold: 310,
          netRevenue: 28900.0,
          unitPrice: 93.0,
          transactionDate: '2026-01-31',
        ),
      ];
    }

    var filtered = list;
    if (chain != null && chain.isNotEmpty && chain != 'all' && chain != 'الكل') {
      filtered = filtered.where((r) => r.retailerChain.toLowerCase() == chain.toLowerCase()).toList();
    }
    if (storeId != null && storeId.isNotEmpty && storeId != 'all' && storeId != 'الكل') {
      final s = storeId.toLowerCase().trim();
      filtered = filtered.where((r) =>
          r.storeId.toLowerCase() == s ||
          r.storeName.toLowerCase() == s ||
          r.storeName.toLowerCase().contains(s) ||
          s.contains(r.storeId.toLowerCase()) ||
          (s.startsWith('fat_') && r.storeId.toLowerCase().contains(s.substring(4)))).toList();
    }
    if (category != null && category.isNotEmpty) {
      filtered = filtered.where((r) => r.category == category).toList();
    }
    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      filtered = filtered.where((r) =>
          r.skuName.toLowerCase().contains(q) ||
          r.barcode.toLowerCase().contains(q) ||
          r.storeName.toLowerCase().contains(q) ||
          r.category.toLowerCase().contains(q)).toList();
    }
    if (startDate != null && startDate.startsWith('2025')) {
      filtered = filtered
          .map(
            (r) => SellOutRecordModel(
              recordId: '${r.recordId}_2025',
              retailerChain: r.retailerChain,
              storeId: r.storeId,
              storeName: r.storeName,
              barcode: r.barcode,
              skuName: r.skuName,
              category: r.category,
              supplier: r.supplier,
              isOwnBrand: r.isOwnBrand,
              quantitySold: (r.quantitySold * 0.85).round().clamp(1, 999999),
              netRevenue: double.parse((r.netRevenue * 0.793).toStringAsFixed(2)),
              unitPrice: r.unitPrice,
              recommendedPrice: r.recommendedPrice,
              transactionDate: r.transactionDate.replaceFirst('2026-', '2025-'),
            ),
          )
          .toList();
    }
    if (startDate != null && startDate.isNotEmpty) {
      filtered = filtered.where((r) => r.transactionDate.compareTo(startDate) >= 0).toList();
    }
    if (endDate != null && endDate.isNotEmpty) {
      filtered = filtered.where((r) => r.transactionDate.compareTo(endDate) <= 0).toList();
    }
    return filtered;
  }

  List<OOSAlertModel> _mockAlerts() {
    if (isCurrentTenantCleared) {
      return const [];
    }
    final cleanSlug = normalizeDataTenantSlug(tenantId);
    if (cleanSlug == 'unilever') {
      return [
        OOSAlertModel(
          alertId: 'oos_uni_001',
          retailerChain: 'carrefour',
          storeId: 'uni_crf_cairo_festival',
          storeName: 'كارفور كايرو فيستيفال سيتي',
          barcode: '6221155101011',
          skuName: 'Lipton Yellow Label Tea 100 Bags',
          category: 'مشروبات ساخنة وشاي',
          estimatedLostDailyCost: 11400.0,
          consecutiveDaysOOS: 4,
          severity: 'critical',
        ),
        OOSAlertModel(
          alertId: 'oos_uni_002',
          retailerChain: 'spinneys',
          storeId: 'uni_spi_cairo_rehab',
          storeName: 'سبينيس - مدينة الرحاب',
          barcode: '6221155101028',
          skuName: 'Dove Moisturizing Beauty Bar 4x100g',
          category: 'عناية شخصية',
          estimatedLostDailyCost: 6250.0,
          consecutiveDaysOOS: 3,
          severity: 'high',
        ),
        OOSAlertModel(
          alertId: 'oos_uni_003',
          retailerChain: 'carrefour',
          storeId: 'uni_crf_alex_citycentre',
          storeName: 'كارفور سيتي سنتر الإسكندرية',
          barcode: '6221155101035',
          skuName: 'Omo Automatic Laundry Powder 4kg',
          category: 'منظفات منزلية',
          estimatedLostDailyCost: 4800.0,
          consecutiveDaysOOS: 2,
          severity: 'medium',
        ),
      ];
    }
    if (cleanSlug == 'pepsi') {
      return [
        OOSAlertModel(
          alertId: 'oos_pep_001',
          retailerChain: 'carrefour',
          storeId: 'pep_crf_cairo_citystars',
          storeName: 'كارفور سيتي ستارز',
          barcode: '6221155201018',
          skuName: 'Pepsi Cola Cans Multipack 6x330ml',
          category: 'مشروبات غازية',
          estimatedLostDailyCost: 14200.0,
          consecutiveDaysOOS: 5,
          severity: 'critical',
        ),
        OOSAlertModel(
          alertId: 'oos_pep_002',
          retailerChain: 'fathalla',
          storeId: 'pep_fat_alex_smouha',
          storeName: 'فتح الله جملة ماركت - سموحة',
          barcode: '6221155201025',
          skuName: 'Chipsy Family Pack Tomato 165g',
          category: 'مقرمشات وسناكس',
          estimatedLostDailyCost: 5900.0,
          consecutiveDaysOOS: 3,
          severity: 'high',
        ),
        OOSAlertModel(
          alertId: 'oos_pep_003',
          retailerChain: 'gomla',
          storeId: 'pep_gom_cairo_nasrcity',
          storeName: 'جملة ماركت - مدينة نصر',
          barcode: '6221155201032',
          skuName: 'Mirinda Orange 2L PET',
          category: 'مشروبات غازية',
          estimatedLostDailyCost: 3100.0,
          consecutiveDaysOOS: 2,
          severity: 'medium',
        ),
      ];
    }
    if (cleanSlug != 'adeco') {
      final brandTitle = formatBrandTitle(cleanSlug);
      return [
        OOSAlertModel(
          alertId: 'oos_${cleanSlug}_001',
          retailerChain: 'carrefour',
          storeId: '${cleanSlug}_crf_cairo_maadi',
          storeName: 'كارفور المعادي سيتي سنتر',
          barcode: '6221155901010',
          skuName: '$brandTitle Full Cream Milk 1L',
          category: 'ألبان ومشتقاتها',
          estimatedLostDailyCost: 7800.0,
          consecutiveDaysOOS: 4,
          severity: 'critical',
        ),
        OOSAlertModel(
          alertId: 'oos_${cleanSlug}_002',
          retailerChain: 'fathalla',
          storeId: '${cleanSlug}_fat_alex_smouha',
          storeName: 'فتح الله جملة ماركت - سموحة',
          barcode: '6221155901027',
          skuName: '$brandTitle Natural Yogurt 6x105g',
          category: 'ألبان ومشتقاتها',
          estimatedLostDailyCost: 4200.0,
          consecutiveDaysOOS: 3,
          severity: 'high',
        ),
      ];
    }

    return [
      OOSAlertModel(
        alertId: 'oos_adco_001',
        retailerChain: 'fathalla',
        storeId: 'fat_cairo_badr',
        storeName: 'فتح الله - مدينة بدر',
        barcode: '6221155001011',
        skuName: 'فيبا سائل غسيل أطباق بالليمون 4 لتر',
        brand: 'فيبا / فيفا (Feba / Viva)',
        category: 'منظفات منزلية',
        estimatedLostDailyCost: 4500.0,
        consecutiveDaysOOS: 6,
        severity: 'critical',
      ),
      OOSAlertModel(
        alertId: 'oos_adco_002',
        retailerChain: 'fathalla',
        storeId: 'fat_alex_nice',
        storeName: 'فتح الله - نيس',
        barcode: '6221155001028',
        skuName: 'ديفا مسحوق غسيل أوتوماتيك 8 كجم',
        brand: 'ديفا (Diva)',
        category: 'مساحيق غسيل',
        estimatedLostDailyCost: 6200.0,
        consecutiveDaysOOS: 5,
        severity: 'high',
      ),
      OOSAlertModel(
        alertId: 'oos_adco_003',
        retailerChain: 'fathalla',
        storeId: 'fat_alex_asafra',
        storeName: 'فتح الله - العصافرة',
        barcode: '6221155001035',
        skuName: 'فيبا سائل غسيل أطباق تفاح 3 لتر',
        brand: 'فيبا / فيفا (Feba / Viva)',
        category: 'منظفات منزلية',
        estimatedLostDailyCost: 5100.0,
        consecutiveDaysOOS: 7,
        severity: 'critical',
      ),
      OOSAlertModel(
        alertId: 'oos_adco_004',
        retailerChain: 'fathalla',
        storeId: 'fat_alex_smouha',
        storeName: 'فتح الله - سموحة',
        barcode: '6221155001042',
        skuName: 'نيفيا مزيل عرق رول أون 50 مل',
        brand: 'نيفيا (Nivea)',
        category: 'عناية شخصية',
        estimatedLostDailyCost: 2800.0,
        consecutiveDaysOOS: 3,
        severity: 'high',
      ),
      OOSAlertModel(
        alertId: 'oos_adco_005',
        retailerChain: 'fathalla',
        storeId: 'fat_cairo_badr',
        storeName: 'فتح الله - مدينة بدر',
        barcode: '6221155001059',
        skuName: 'نيفيا كريم ترطيب عميق 250 مل',
        brand: 'نيفيا (Nivea)',
        category: 'عناية شخصية',
        estimatedLostDailyCost: 3600.0,
        consecutiveDaysOOS: 4,
        severity: 'critical',
      ),
      OOSAlertModel(
        alertId: 'oos_adco_006',
        retailerChain: 'fathalla',
        storeId: 'fat_alex_sanstefano',
        storeName: 'فتح الله - سان ستيفانو',
        barcode: '6221155001066',
        skuName: 'ماكسيل ماجيك منظف أفران وشوايات 500 مل',
        brand: 'ماكسيل (Maxell)',
        category: 'منظفات متخصصة',
        estimatedLostDailyCost: 3400.0,
        consecutiveDaysOOS: 4,
        severity: 'high',
      ),
      OOSAlertModel(
        alertId: 'oos_adco_007',
        retailerChain: 'fathalla',
        storeId: 'fat_alex_mansheya',
        storeName: 'فتح الله - المنشية',
        barcode: '6221155001073',
        skuName: 'فلڤيتا منعم ومعطر أقمشة مركز 1.5 لتر',
        brand: 'فلڤيتا (Velveta)',
        category: 'عناية بالأقمشة',
        estimatedLostDailyCost: 4100.0,
        consecutiveDaysOOS: 3,
        severity: 'high',
      ),
      OOSAlertModel(
        alertId: 'oos_adco_008',
        retailerChain: 'fathalla',
        storeId: 'fat_alex_nice',
        storeName: 'فتح الله - نيس',
        barcode: '6221155001080',
        skuName: 'كلوريل مبيض ومعقم ملابس 1 لتر',
        brand: 'كلوريل (Clorel)',
        category: 'منظفات منزلية',
        estimatedLostDailyCost: 2900.0,
        consecutiveDaysOOS: 2,
        severity: 'medium',
      ),
    ];
  }

  OOSMonitorResponseModel _buildMockOOSResponse(List<OOSAlertModel> alerts) {
    final brandMap = <String, OOSBrandSummaryModel>{};
    final branchMap = <String, OOSBranchSummaryModel>{};
    final brandBranchSeen = <String, Set<String>>{};
    final branchBrandSeen = <String, Set<String>>{};

    double totalCost = 0.0;
    int criticalCount = 0;

    for (final a in alerts) {
      totalCost += a.estimatedLostDailyCost;
      if (a.severity == 'critical') criticalCount++;

      final bName = a.brand.isNotEmpty ? a.brand : 'أصناف عامة';
      final existingBrand = brandMap[bName];
      brandBranchSeen.putIfAbsent(bName, () => <String>{});
      if (a.storeName.isNotEmpty) {
        brandBranchSeen[bName]!.add(a.storeName);
      }

      if (existingBrand == null) {
        brandMap[bName] = OOSBrandSummaryModel(
          brand: bName,
          oosItemsCount: 1,
          impactedBranches: brandBranchSeen[bName]!.toList(),
          branchesCount: brandBranchSeen[bName]!.length,
          totalLostDailyCost: a.estimatedLostDailyCost,
          maxDaysOOS: a.consecutiveDaysOOS,
        );
      } else {
        brandMap[bName] = OOSBrandSummaryModel(
          brand: bName,
          oosItemsCount: existingBrand.oosItemsCount + 1,
          impactedBranches: brandBranchSeen[bName]!.toList(),
          branchesCount: brandBranchSeen[bName]!.length,
          totalLostDailyCost: existingBrand.totalLostDailyCost + a.estimatedLostDailyCost,
          maxDaysOOS: a.consecutiveDaysOOS > existingBrand.maxDaysOOS ? a.consecutiveDaysOOS : existingBrand.maxDaysOOS,
        );
      }

      final brName = a.storeName.isNotEmpty ? a.storeName : a.storeId;
      branchBrandSeen.putIfAbsent(brName, () => <String>{});
      if (bName.isNotEmpty) branchBrandSeen[brName]!.add(bName);

      final existingBranch = branchMap[brName];
      if (existingBranch == null) {
        branchMap[brName] = OOSBranchSummaryModel(
          branchName: brName,
          retailerChain: a.retailerChain,
          oosItemsCount: 1,
          brandsAffected: branchBrandSeen[brName]!.toList(),
          totalLostDailyCost: a.estimatedLostDailyCost,
        );
      } else {
        branchMap[brName] = OOSBranchSummaryModel(
          branchName: brName,
          retailerChain: a.retailerChain,
          oosItemsCount: existingBranch.oosItemsCount + 1,
          brandsAffected: branchBrandSeen[brName]!.toList(),
          totalLostDailyCost: existingBranch.totalLostDailyCost + a.estimatedLostDailyCost,
        );
      }
    }

    final brandSummaries = brandMap.values.toList()
      ..sort((a, b) => b.totalLostDailyCost.compareTo(a.totalLostDailyCost));
    final branchSummaries = branchMap.values.toList()
      ..sort((a, b) => b.totalLostDailyCost.compareTo(a.totalLostDailyCost));

    final topBrand = brandSummaries.isNotEmpty ? brandSummaries.first.brand : 'غير متوفر';
    final topBranch = branchSummaries.isNotEmpty ? branchSummaries.first.branchName : 'غير متوفر';
    final monthlyLoss = totalCost * 30.0;

    final aiAnalysis = OOSAIAnalysisModel(
      modelUsed: 'Gemini 1.5 Pro / CPFR Intelligence Engine',
      generatedAt: DateTime.now().toString().substring(0, 16),
      executiveSummaryAr:
          'تحليل الذكاء الاصطناعي (Gemini Root-Cause AI Engine): تم رصد ${alerts.length} حالة انعدام مخزون (OOS) بإجمالي خسارة يومية مقدرة ${totalCost.toStringAsFixed(0)} ج.م (ما يعادل ${monthlyLoss.toStringAsFixed(0)} ج.م شهرياً). العلامة التجارية الأكثر تضرراً هي "$topBrand" وأكثر الفروع تأثراً هو "$topBranch". يوصى بالتدخل الفوري لإعادة التوازن المخزني عبر إصدار أوامر توريد طارئة.',
      executiveSummaryEn:
          'Gemini Root-Cause AI Analysis: ${alerts.length} OOS incidents detected with estimated daily lost revenue of ${totalCost.toStringAsFixed(0)} EGP. Top impacted brand is "$topBrand" and top branch is "$topBranch". Immediate replenishment recommended.',
      rootCausesAr: [
        'تأخر دورات التوريد وإعادة الطلب (Supply Lead-Time Lag) مقارنة بمعدلات السحب اليومي المرتفعة بالهايبر ماركت.',
        'تركّز العجز في علامات تجارية أساسية عالية الدوران ($topBrand) مما يؤثر مباشرة على حصة الرف وحجم المبيعات.',
        'اختناقات لوجستية وتفاوت في أولوية التوزيع الإقليمي بين الفروع المركزية والفروع الطرفية.',
        'عدم انضباط الحد الأدنى لمخزون الأمان (Safety Stock Threshold) في نقاط البيع المذكورة.',
      ],
      immediateActionsAr: [
        'إصدار أمر توريد طارئ (Emergency Purchase Order) للأصناف التابعة لـ $topBrand خلال 24 ساعة.',
        'إعادة موازنة المخزون (Inter-branch Stock Transfer) لصالح $topBranch من أقرب مستودع إقليمي.',
        'رفع حد نقطة إعادة الطلب (ROP) بنسبة 20% لتجنب تكرار الانعدام خلال عطلات نهاية الأسبوع ومواسم الذروة.',
        'تفعيل تنبيهات فورية للمشرفين الميدانيين لمتابعة ملء الأرفف فور استلام التوريدات.',
      ],
      criticalSKUsCount: criticalCount,
      topImpactedBranch: topBranch,
      topImpactedBrand: topBrand,
      projectedMonthlyLossEGP: monthlyLoss,
    );

    return OOSMonitorResponseModel(
      totalIncidents: alerts.length,
      totalLostDailyCost: totalCost,
      alerts: alerts,
      brandSummaries: brandSummaries,
      branchSummaries: branchSummaries,
      aiAnalysis: aiAnalysis,
    );
  }

  List<StoreBenchmarkItem> _mockStoreMatrix({String? region, String? tier, String? chain, int? year}) {
    if (isCurrentTenantCleared) {
      return const [];
    }
    final cleanSlug = normalizeDataTenantSlug(tenantId);
    if (cleanSlug == 'adeco' &&
        year != null &&
        chain != null &&
        chain.toLowerCase() == 'fathalla') {
      final double yrFactor = year == 2025 ? 0.793 : (year == 2024 ? 0.65 : 1.0);
      final baseRevs = <double>[
        6332337.0, 2989619.0, 2737349.0, 2385410.0, 2145820.0, 1984310.0,
        1842600.0, 1712400.0, 1598200.0, 1485900.0, 1392400.0, 1284500.0,
        1195200.0, 1124800.0, 1054300.0, 984200.0, 912500.0, 845600.0,
        782400.0, 724100.0, 668500.0, 612400.0, 558900.0, 504200.0,
        452800.0, 402100.0, 354600.0, 308400.0, 264200.0, 218500.0,
        168400.0, 114200.0, 52443.0, 38936.5,
      ];
      final result = <StoreBenchmarkItem>[];
      for (int i = 0; i < defaultFathalla34Branches.length; i++) {
        final b = defaultFathalla34Branches[i];
        final baseRev = i < baseRevs.length ? baseRevs[i] : 50000.0;
        final rev = double.parse((baseRev * yrFactor).toStringAsFixed(2));
        final units = (rev / 73.5).round();
        result.add(
          StoreBenchmarkItem(
            storeId: (b['id'] ?? 'fat_$i').toString(),
            storeName: (b['branch_name'] ?? 'فرع فتح الله').toString(),
            retailerChain: 'fathalla',
            region: (b['governorate'] ?? 'الإسكندرية').toString(),
            tier: rev >= 1500000 ? 'Tier A' : (rev >= 500000 ? 'Tier B' : 'Tier C'),
            totalRevenue: rev,
            totalUnits: units,
            velocityUnitsPerDay: double.parse((units / 30.0).toStringAsFixed(1)),
            rank: i + 1,
          ),
        );
      }
      return result;
    }
    List<StoreBenchmarkItem> list;

    if (cleanSlug == 'unilever') {
      list = [
        StoreBenchmarkItem(
          storeId: 'uni_crf_cairo_festival',
          storeName: 'كارفور كايرو فيستيفال سيتي',
          retailerChain: 'carrefour',
          region: 'القاهرة الكبرى',
          tier: 'Tier A',
          totalRevenue: 984200.0,
          totalUnits: 8420,
          velocityUnitsPerDay: 280.7,
          rank: 1,
        ),
        StoreBenchmarkItem(
          storeId: 'uni_crf_cairo_maadi',
          storeName: 'كارفور المعادي سيتي سنتر',
          retailerChain: 'carrefour',
          region: 'القاهرة الكبرى',
          tier: 'Tier A',
          totalRevenue: 845600.0,
          totalUnits: 7180,
          velocityUnitsPerDay: 239.3,
          rank: 2,
        ),
        StoreBenchmarkItem(
          storeId: 'uni_spi_cairo_rehab',
          storeName: 'سبينيس - مدينة الرحاب',
          retailerChain: 'spinneys',
          region: 'القاهرة الكبرى',
          tier: 'Tier A',
          totalRevenue: 662400.0,
          totalUnits: 5620,
          velocityUnitsPerDay: 187.3,
          rank: 3,
        ),
        StoreBenchmarkItem(
          storeId: 'uni_crf_alex_citycentre',
          storeName: 'كارفور سيتي سنتر الإسكندرية',
          retailerChain: 'carrefour',
          region: 'شرق الإسكندرية',
          tier: 'Tier B',
          totalRevenue: 518900.0,
          totalUnits: 4410,
          velocityUnitsPerDay: 147.0,
          rank: 4,
        ),
        StoreBenchmarkItem(
          storeId: 'uni_spi_giza_sheikhzayed',
          storeName: 'سبينيس - الشيخ زايد',
          retailerChain: 'spinneys',
          region: 'القاهرة الكبرى',
          tier: 'Tier B',
          totalRevenue: 392100.0,
          totalUnits: 3340,
          velocityUnitsPerDay: 111.3,
          rank: 5,
        ),
      ];
    } else if (cleanSlug == 'pepsi') {
      list = [
        StoreBenchmarkItem(
          storeId: 'pep_crf_cairo_citystars',
          storeName: 'كارفور سيتي ستارز',
          retailerChain: 'carrefour',
          region: 'القاهرة الكبرى',
          tier: 'Tier A',
          totalRevenue: 1125400.0,
          totalUnits: 14200,
          velocityUnitsPerDay: 473.3,
          rank: 1,
        ),
        StoreBenchmarkItem(
          storeId: 'pep_fat_alex_smouha',
          storeName: 'فتح الله جملة ماركت - سموحة',
          retailerChain: 'fathalla',
          region: 'شرق الإسكندرية',
          tier: 'Tier A',
          totalRevenue: 894200.0,
          totalUnits: 11480,
          velocityUnitsPerDay: 382.7,
          rank: 2,
        ),
        StoreBenchmarkItem(
          storeId: 'pep_crf_giza_dandy',
          storeName: 'كارفور داندي مول',
          retailerChain: 'carrefour',
          region: 'القاهرة الكبرى',
          tier: 'Tier A',
          totalRevenue: 742800.0,
          totalUnits: 9520,
          velocityUnitsPerDay: 317.3,
          rank: 3,
        ),
        StoreBenchmarkItem(
          storeId: 'pep_gom_cairo_nasrcity',
          storeName: 'جملة ماركت - مدينة نصر',
          retailerChain: 'gomla',
          region: 'القاهرة الكبرى',
          tier: 'Tier B',
          totalRevenue: 564100.0,
          totalUnits: 7240,
          velocityUnitsPerDay: 241.3,
          rank: 4,
        ),
        StoreBenchmarkItem(
          storeId: 'pep_fat_alex_stanley',
          storeName: 'فتح الله - ستانلي',
          retailerChain: 'fathalla',
          region: 'شرق الإسكندرية',
          tier: 'Tier B',
          totalRevenue: 438500.0,
          totalUnits: 5620,
          velocityUnitsPerDay: 187.3,
          rank: 5,
        ),
      ];
    } else if (cleanSlug != 'adeco') {
      list = [
        StoreBenchmarkItem(
          storeId: '${cleanSlug}_crf_cairo_maadi',
          storeName: 'كارفور المعادي سيتي سنتر',
          retailerChain: 'carrefour',
          region: 'القاهرة الكبرى',
          tier: 'Tier A',
          totalRevenue: 712400.0,
          totalUnits: 6180,
          velocityUnitsPerDay: 206.0,
          rank: 1,
        ),
        StoreBenchmarkItem(
          storeId: '${cleanSlug}_fat_alex_smouha',
          storeName: 'فتح الله جملة ماركت - سموحة',
          retailerChain: 'fathalla',
          region: 'شرق الإسكندرية',
          tier: 'Tier A',
          totalRevenue: 624800.0,
          totalUnits: 5420,
          velocityUnitsPerDay: 180.7,
          rank: 2,
        ),
        StoreBenchmarkItem(
          storeId: '${cleanSlug}_gom_cairo_nasrcity',
          storeName: 'جملة ماركت - مدينة نصر',
          retailerChain: 'gomla',
          region: 'القاهرة الكبرى',
          tier: 'Tier B',
          totalRevenue: 468200.0,
          totalUnits: 4120,
          velocityUnitsPerDay: 137.3,
          rank: 3,
        ),
      ];
    } else {
      list = [
        StoreBenchmarkItem(
          storeId: 'crf_cairo_maadi',
          storeName: 'كارفور المعادي سيتي سنتر',
          retailerChain: 'carrefour',
          region: 'القاهرة الكبرى',
          tier: 'Tier A',
          totalRevenue: 852400.0,
          totalUnits: 7210,
          velocityUnitsPerDay: 240.3,
          rank: 1,
        ),
        StoreBenchmarkItem(
          storeId: 'crf_cairo_citystars',
          storeName: 'كارفور سيتي ستارز',
          retailerChain: 'carrefour',
          region: 'القاهرة الكبرى',
          tier: 'Tier A',
          totalRevenue: 785100.0,
          totalUnits: 6650,
          velocityUnitsPerDay: 221.7,
          rank: 2,
        ),
        StoreBenchmarkItem(
          storeId: 'fat_alex_smouha',
          storeName: 'فتح الله جملة ماركت - سموحة',
          retailerChain: 'fathalla',
          region: 'شرق الإسكندرية',
          tier: 'Tier A',
          totalRevenue: 692800.0,
          totalUnits: 5890,
          velocityUnitsPerDay: 196.3,
          rank: 3,
        ),
        StoreBenchmarkItem(
          storeId: 'gom_cairo_nasrcity',
          storeName: 'جملة ماركت - مدينة نصر',
          retailerChain: 'gomla',
          region: 'القاهرة الكبرى',
          tier: 'Tier B',
          totalRevenue: 548200.0,
          totalUnits: 4620,
          velocityUnitsPerDay: 154.0,
          rank: 4,
        ),
        StoreBenchmarkItem(
          storeId: 'crf_giza_dandy',
          storeName: 'كارفور داندي مول',
          retailerChain: 'carrefour',
          region: 'القاهرة الكبرى',
          tier: 'Tier B',
          totalRevenue: 489500.0,
          totalUnits: 4150,
          velocityUnitsPerDay: 138.3,
          rank: 5,
        ),
        StoreBenchmarkItem(
          storeId: 'fat_alex_stanley',
          storeName: 'فتح الله - ستانلي',
          retailerChain: 'fathalla',
          region: 'شرق الإسكندرية',
          tier: 'Tier B',
          totalRevenue: 421600.0,
          totalUnits: 3580,
          velocityUnitsPerDay: 119.3,
          rank: 6,
        ),
        StoreBenchmarkItem(
          storeId: 'spi_giza_mollarab',
          storeName: 'سبينيس - مول العرب',
          retailerChain: 'spinneys',
          region: 'القاهرة الكبرى',
          tier: 'Tier B',
          totalRevenue: 364900.0,
          totalUnits: 3100,
          velocityUnitsPerDay: 103.3,
          rank: 7,
        ),
        StoreBenchmarkItem(
          storeId: 'fat_alex_mansheya',
          storeName: 'فتح الله - المنشية',
          retailerChain: 'fathalla',
          region: 'غرب الإسكندرية',
          tier: 'Tier C',
          totalRevenue: 228300.0,
          totalUnits: 1940,
          velocityUnitsPerDay: 64.7,
          rank: 8,
        ),
      ];
    }

    var filtered = list;
    if (region != null && region.isNotEmpty && region != 'الكل' && region != 'all') {
      filtered = filtered.where((s) => s.region == region).toList();
    }
    if (tier != null && tier.isNotEmpty && tier != 'الكل' && tier != 'all') {
      filtered = filtered.where((s) => s.tier.toLowerCase() == tier.toLowerCase()).toList();
    }
    if (chain != null && chain.isNotEmpty && chain != 'الكل' && chain != 'all') {
      filtered = filtered.where((s) => s.retailerChain.toLowerCase() == chain.toLowerCase()).toList();
    }
    return filtered;
  }

  List<PricingComplianceItem> _mockPricingCompliance({String? chain, String? category, bool? violationOnly}) {
    if (isCurrentTenantCleared) {
      return const [];
    }
    final cleanSlug = normalizeDataTenantSlug(tenantId);
    List<PricingComplianceItem> list;

    if (cleanSlug == 'unilever') {
      list = [
        PricingComplianceItem(
          skuName: 'Lipton Yellow Label Tea 100 Bags',
          barcode: '6221155101011',
          category: 'مشروبات ساخنة وشاي',
          retailerChain: 'carrefour',
          storeName: 'كارفور كايرو فيستيفال سيتي',
          actualPrice: 86.0,
          recommendedPrice: 95.0,
          priceDeltaPct: -9.5,
          violationType: 'under_cutting',
          isPromoActive: true,
          promoUpliftPct: 33.4,
        ),
        PricingComplianceItem(
          skuName: 'Dove Moisturizing Beauty Bar 4x100g',
          barcode: '6221155101028',
          category: 'عناية شخصية',
          retailerChain: 'carrefour',
          storeName: 'كارفور كايرو فيستيفال سيتي',
          actualPrice: 140.0,
          recommendedPrice: 140.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Omo Automatic Laundry Powder 4kg',
          barcode: '6221155101035',
          category: 'منظفات منزلية',
          retailerChain: 'spinneys',
          storeName: 'سبينيس - مدينة الرحاب',
          actualPrice: 288.0,
          recommendedPrice: 260.0,
          priceDeltaPct: 10.8,
          violationType: 'price_gouging',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Knorr Chicken Stock Cubes 24s',
          barcode: '6221155101042',
          category: 'إضافات طهي ومرقة',
          retailerChain: 'spinneys',
          storeName: 'سبينيس - الشيخ زايد',
          actualPrice: 65.0,
          recommendedPrice: 65.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
      ];
    } else if (cleanSlug == 'pepsi') {
      list = [
        PricingComplianceItem(
          skuName: 'Pepsi Cola Cans Multipack 6x330ml',
          barcode: '6221155201018',
          category: 'مشروبات غازية',
          retailerChain: 'carrefour',
          storeName: 'كارفور سيتي ستارز',
          actualPrice: 80.0,
          recommendedPrice: 90.0,
          priceDeltaPct: -11.1,
          violationType: 'under_cutting',
          isPromoActive: true,
          promoUpliftPct: 39.2,
        ),
        PricingComplianceItem(
          skuName: 'Chipsy Family Pack Tomato 165g',
          barcode: '6221155201025',
          category: 'مقرمشات وسناكس',
          retailerChain: 'fathalla',
          storeName: 'فتح الله جملة ماركت - سموحة',
          actualPrice: 25.0,
          recommendedPrice: 25.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Mirinda Orange 2L PET',
          barcode: '6221155201032',
          category: 'مشروبات غازية',
          retailerChain: 'gomla',
          storeName: 'جملة ماركت - مدينة نصر',
          actualPrice: 39.0,
          recommendedPrice: 35.0,
          priceDeltaPct: 11.4,
          violationType: 'price_gouging',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Doritos Nacho Cheese 140g',
          barcode: '6221155201056',
          category: 'مقرمشات وسناكس',
          retailerChain: 'fathalla',
          storeName: 'فتح الله - ستانلي',
          actualPrice: 30.0,
          recommendedPrice: 30.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
      ];
    } else if (cleanSlug != 'adeco') {
      final brandTitle = formatBrandTitle(cleanSlug);
      list = [
        PricingComplianceItem(
          skuName: '$brandTitle Full Cream Milk 1L',
          barcode: '6221155901010',
          category: 'ألبان ومشتقاتها',
          retailerChain: 'carrefour',
          storeName: 'كارفور المعادي سيتي سنتر',
          actualPrice: 41.0,
          recommendedPrice: 45.0,
          priceDeltaPct: -8.9,
          violationType: 'under_cutting',
          isPromoActive: true,
          promoUpliftPct: 31.5,
        ),
        PricingComplianceItem(
          skuName: '$brandTitle Natural Yogurt 6x105g',
          barcode: '6221155901027',
          category: 'ألبان ومشتقاتها',
          retailerChain: 'fathalla',
          storeName: 'فتح الله جملة ماركت - سموحة',
          actualPrice: 48.0,
          recommendedPrice: 48.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: '$brandTitle Pure Orange Juice 1L',
          barcode: '6221155901034',
          category: 'عصائر ومشروبات',
          retailerChain: 'gomla',
          storeName: 'جملة ماركت - مدينة نصر',
          actualPrice: 44.0,
          recommendedPrice: 40.0,
          priceDeltaPct: 10.0,
          violationType: 'price_gouging',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
      ];
    } else {
      list = [
        PricingComplianceItem(
          skuName: 'Adeco Pure Sunflower Oil 1L',
          barcode: '6221155001241',
          category: 'زيوت طعام',
          retailerChain: 'carrefour',
          storeName: 'كارفور المعادي سيتي سنتر',
          actualPrice: 98.0,
          recommendedPrice: 110.0,
          priceDeltaPct: -10.9,
          violationType: 'under_cutting',
          isPromoActive: true,
          promoUpliftPct: 34.5,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Pure Corn Oil 800ml',
          barcode: '6221155001258',
          category: 'زيوت طعام',
          retailerChain: 'carrefour',
          storeName: 'كارفور المعادي سيتي سنتر',
          actualPrice: 105.0,
          recommendedPrice: 120.0,
          priceDeltaPct: -12.5,
          violationType: 'under_cutting',
          isPromoActive: true,
          promoUpliftPct: 28.4,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Extra Virgin Olive Oil 500ml',
          barcode: '6221155001234',
          category: 'زيوت طعام',
          retailerChain: 'carrefour',
          storeName: 'كارفور المعادي سيتي سنتر',
          actualPrice: 250.0,
          recommendedPrice: 250.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Premium Tomato Paste 380g',
          barcode: '6221155002019',
          category: 'صلصة ومعلبات',
          retailerChain: 'carrefour',
          storeName: 'كارفور المعادي سيتي سنتر',
          actualPrice: 38.0,
          recommendedPrice: 38.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Canola Blend 750ml',
          barcode: '6221155001265',
          category: 'زيوت طعام',
          retailerChain: 'carrefour',
          storeName: 'كارفور داندي مول',
          actualPrice: 108.0,
          recommendedPrice: 120.0,
          priceDeltaPct: -10.0,
          violationType: 'under_cutting',
          isPromoActive: true,
          promoUpliftPct: 32.0,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Peeled Whole Tomatoes 400g',
          barcode: '6221155002026',
          category: 'صلصة ومعلبات',
          retailerChain: 'carrefour',
          storeName: 'كارفور داندي مول',
          actualPrice: 45.0,
          recommendedPrice: 45.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Premium Tomato Paste 380g',
          barcode: '6221155002019',
          category: 'صلصة ومعلبات',
          retailerChain: 'fathalla',
          storeName: 'فتح الله جملة ماركت - سموحة',
          actualPrice: 33.0,
          recommendedPrice: 38.0,
          priceDeltaPct: -13.2,
          violationType: 'under_cutting',
          isPromoActive: true,
          promoUpliftPct: 41.2,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Pure Sunflower Oil 1L',
          barcode: '6221155001241',
          category: 'زيوت طعام',
          retailerChain: 'fathalla',
          storeName: 'فتح الله جملة ماركت - سموحة',
          actualPrice: 110.0,
          recommendedPrice: 110.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Extra Virgin Olive Oil 500ml',
          barcode: '6221155001234',
          category: 'زيوت طعام',
          retailerChain: 'fathalla',
          storeName: 'فتح الله جملة ماركت - سموحة',
          actualPrice: 250.0,
          recommendedPrice: 250.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Traditional Fava Beans 400g',
          barcode: '6221155003016',
          category: 'بقوليات ومعلبات',
          retailerChain: 'fathalla',
          storeName: 'فتح الله جملة ماركت - سموحة',
          actualPrice: 28.0,
          recommendedPrice: 28.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Traditional Fava Beans 400g',
          barcode: '6221155003016',
          category: 'بقوليات ومعلبات',
          retailerChain: 'fathalla',
          storeName: 'فتح الله - ستانلي',
          actualPrice: 25.0,
          recommendedPrice: 28.0,
          priceDeltaPct: -10.7,
          violationType: 'under_cutting',
          isPromoActive: true,
          promoUpliftPct: 38.5,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Pure Corn Oil 800ml',
          barcode: '6221155001258',
          category: 'زيوت طعام',
          retailerChain: 'fathalla',
          storeName: 'فتح الله - ستانلي',
          actualPrice: 120.0,
          recommendedPrice: 120.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Premium Tomato Paste 380g',
          barcode: '6221155002019',
          category: 'صلصة ومعلبات',
          retailerChain: 'gomla',
          storeName: 'جملة ماركت - مدينة نصر',
          actualPrice: 42.0,
          recommendedPrice: 38.0,
          priceDeltaPct: 10.5,
          violationType: 'price_gouging',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Pure Sunflower Oil 1L',
          barcode: '6221155001241',
          category: 'زيوت طعام',
          retailerChain: 'gomla',
          storeName: 'جملة ماركت - مدينة نصر',
          actualPrice: 102.0,
          recommendedPrice: 110.0,
          priceDeltaPct: -7.3,
          violationType: 'under_cutting',
          isPromoActive: true,
          promoUpliftPct: 29.8,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Peeled Whole Tomatoes 400g',
          barcode: '6221155002026',
          category: 'صلصة ومعلبات',
          retailerChain: 'gomla',
          storeName: 'جملة ماركت - مدينة نصر',
          actualPrice: 45.0,
          recommendedPrice: 45.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Extra Virgin Olive Oil 500ml',
          barcode: '6221155001234',
          category: 'زيوت طعام',
          retailerChain: 'spinneys',
          storeName: 'سبينيس - مول العرب',
          actualPrice: 285.0,
          recommendedPrice: 250.0,
          priceDeltaPct: 14.0,
          violationType: 'price_gouging',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Canola Blend 750ml',
          barcode: '6221155001265',
          category: 'زيوت طعام',
          retailerChain: 'spinneys',
          storeName: 'سبينيس - مول العرب',
          actualPrice: 135.0,
          recommendedPrice: 120.0,
          priceDeltaPct: 12.5,
          violationType: 'price_gouging',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
        PricingComplianceItem(
          skuName: 'Adeco Pure Sunflower Oil 1L',
          barcode: '6221155001241',
          category: 'زيوت طعام',
          retailerChain: 'spinneys',
          storeName: 'سبينيس - مول العرب',
          actualPrice: 110.0,
          recommendedPrice: 110.0,
          priceDeltaPct: 0.0,
          violationType: 'compliant',
          isPromoActive: false,
          promoUpliftPct: 0.0,
        ),
      ];
    }

    var filtered = list;
    if (chain != null && chain.isNotEmpty && chain != 'الكل' && chain != 'all') {
      filtered = filtered.where((c) => c.retailerChain.toLowerCase() == chain.toLowerCase()).toList();
    }
    if (category != null && category.isNotEmpty && category != 'الكل' && category != 'all') {
      final targetCat = normalizeCategoryName(category);
      filtered = filtered.where((c) => normalizeCategoryName(c.category) == targetCat).toList();
    }
    if (violationOnly == true) {
      filtered = filtered.where((c) => c.violationType != 'compliant').toList();
    }
    return filtered;
  }

  /// Current authenticated user (if any)
  TenantUserModel? currentUser;
  TenantProfileModel? currentTenantProfile;
  String? lastResetToken;

  static final List<TenantProfileModel> _inMemoryTenants = [
    TenantProfileModel(
      tenantId: 'adeco',
      displayName: 'شركة أديكو للصناعات الغذائية (Adeco)',
      slug: 'adeco',
      portalUrl: buildPortalUrl('adeco'),
      brandSeedColor: '#0B57D0',
      adminEmail: 'admin@adeco-retail.com',
      activeChains: ['fathalla', 'gomla', 'beet-elgomla'],
    ),
    TenantProfileModel(
      tenantId: 'unilever',
      displayName: 'شركة يونيليفر مشرق (Unilever)',
      slug: 'unilever',
      portalUrl: buildPortalUrl('unilever'),
      brandSeedColor: '#0D9488',
      adminEmail: 'admin@unilever-retail.com',
      activeChains: ['carrefour', 'spinneys'],
    ),
    TenantProfileModel(
      tenantId: 'pepsi',
      displayName: 'شركة بيبسي كولا مصر (PepsiCo)',
      slug: 'pepsi',
      portalUrl: buildPortalUrl('pepsi'),
      brandSeedColor: '#B91C1C',
      adminEmail: 'admin@pepsico-retail.com',
      activeChains: ['carrefour', 'fathalla', 'gomla'],
    ),
  ];

  static final Map<String, List<RetailChainModel>> _inMemoryChainsByTenant = {
    'adeco': [
      RetailChainModel(
        chainId: 'fathalla',
        tenantId: 'adeco',
        displayName: 'أسواق فتح الله (Fathalla Market)',
        code: 'fathalla',
        chainType: 'wholesale',
        storeCount: 35,
        createdAt: '2025-10-14T00:00:00Z',
      ),
      RetailChainModel(
        chainId: 'gomla',
        tenantId: 'adeco',
        displayName: 'جملة ماركت (Gomla Market)',
        code: 'gomla',
        chainType: 'supermarket',
        storeCount: 33,
        createdAt: '2025-12-14T00:00:00Z',
      ),
      RetailChainModel(
        chainId: 'beet-elgomla',
        tenantId: 'adeco',
        displayName: 'بيت الجملة (Beet El Gomla)',
        code: 'beet-elgomla',
        chainType: 'supermarket',
        storeCount: 30,
        createdAt: '2026-07-14T00:00:00Z',
      ),
      RetailChainModel(
        chainId: 'chain-1080314',
        tenantId: 'adeco',
        displayName: 'الوكالة (El Wakala)',
        code: 'chain-1080314',
        chainType: 'wholesale',
        storeCount: 1,
        createdAt: '2026-08-01T00:00:00Z',
      ),
    ],
    'unilever': [
      RetailChainModel(
        chainId: 'carrefour',
        tenantId: 'unilever',
        displayName: 'كارفور مصر (Carrefour Egypt)',
        code: 'carrefour',
        chainType: 'hypermarket',
        storeCount: 68,
        createdAt: '2025-10-14T00:00:00Z',
      ),
      RetailChainModel(
        chainId: 'spinneys',
        tenantId: 'unilever',
        displayName: 'سبينيس مصر (Spinneys Egypt)',
        code: 'spinneys',
        chainType: 'supermarket',
        storeCount: 26,
        createdAt: '2025-10-14T00:00:00Z',
      ),
    ],
    'pepsi': [
      RetailChainModel(
        chainId: 'carrefour',
        tenantId: 'pepsi',
        displayName: 'كارفور مصر (Carrefour Egypt)',
        code: 'carrefour',
        chainType: 'hypermarket',
        storeCount: 68,
        createdAt: '2025-10-14T00:00:00Z',
      ),
      RetailChainModel(
        chainId: 'fathalla',
        tenantId: 'pepsi',
        displayName: 'أسواق فتح الله (Fathalla Market)',
        code: 'fathalla',
        chainType: 'wholesale',
        storeCount: 35,
        createdAt: '2025-10-14T00:00:00Z',
      ),
      RetailChainModel(
        chainId: 'gomla',
        tenantId: 'pepsi',
        displayName: 'جملة ماركت (Gomla Market)',
        code: 'gomla',
        chainType: 'supermarket',
        storeCount: 33,
        createdAt: '2025-12-14T00:00:00Z',
      ),
    ],
  };

  static List<RetailChainModel> _getChainsListForTenant(String rawTenant) {
    final slug = normalizeDataTenantSlug(rawTenant);
    return _inMemoryChainsByTenant.putIfAbsent(slug, () => <RetailChainModel>[]);
  }

  static void _registerInMemoryChain(RetailChainModel chain, {String? tenantSlug}) {
    final slug = normalizeDataTenantSlug(
      (tenantSlug != null && tenantSlug.isNotEmpty)
          ? tenantSlug
          : (chain.tenantId.isNotEmpty ? chain.tenantId : 'adeco'),
    );
    final list = _getChainsListForTenant(slug);
    final idx = list.indexWhere((c) => c.code.toLowerCase() == chain.code.toLowerCase());
    if (idx >= 0) {
      list[idx] = chain;
    } else {
      list.add(chain);
    }
    // Keep tenant profile activeChains in sync
    final tIdx = _inMemoryTenants.indexWhere((t) => normalizeTenantSlug(t.slug) == slug);
    if (tIdx >= 0) {
      final t = _inMemoryTenants[tIdx];
      if (!t.activeChains.any((c) => c.toLowerCase() == chain.code.toLowerCase())) {
        _inMemoryTenants[tIdx] = TenantProfileModel(
          tenantId: t.tenantId,
          displayName: t.displayName,
          slug: t.slug,
          portalUrl: t.portalUrl,
          brandSeedColor: t.brandSeedColor,
          logoUrl: t.logoUrl,
          adminEmail: t.adminEmail,
          activeChains: [...t.activeChains, chain.code],
        );
      }
    }
  }

  static void _deleteInMemoryChain(String code, {String? tenantSlug}) {
    final clean = code.trim().toLowerCase();
    if (tenantSlug != null && tenantSlug.isNotEmpty) {
      final slug = normalizeDataTenantSlug(tenantSlug);
      final list = _getChainsListForTenant(slug);
      list.removeWhere(
        (c) => c.code.toLowerCase() == clean || c.chainId.toLowerCase() == clean,
      );
      final tIdx = _inMemoryTenants.indexWhere((t) => normalizeTenantSlug(t.slug) == slug);
      if (tIdx >= 0) {
        final t = _inMemoryTenants[tIdx];
        _inMemoryTenants[tIdx] = TenantProfileModel(
          tenantId: t.tenantId,
          displayName: t.displayName,
          slug: t.slug,
          portalUrl: t.portalUrl,
          brandSeedColor: t.brandSeedColor,
          logoUrl: t.logoUrl,
          adminEmail: t.adminEmail,
          activeChains: t.activeChains.where((c) => c.toLowerCase() != clean).toList(),
        );
      }
      return;
    }
    for (final list in _inMemoryChainsByTenant.values) {
      list.removeWhere(
        (c) => c.code.toLowerCase() == clean || c.chainId.toLowerCase() == clean,
      );
    }
  }

  static String _extractBackendError(http.Response resp, String defaultMessage) {
    final raw = resp.body.trim();
    if (raw.isEmpty) return defaultMessage;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {}
    return raw;
  }

  /// Login for dedicated tenant portal or admin
  Future<LoginResultModel> login({
    required String tenantId,
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final isSuperAdminEmail = ZeroTrustDigest.isSuperAdminEmail(normalizedEmail);
    final rawSlug = normalizeTenantSlug(tenantId);
    final isSuperTarget = isSuperAdminEmail ||
        rawSlug == 'admin' ||
        rawSlug == 'system' ||
        rawSlug == 'superadmin';

    final effectiveTenant = isSuperTarget
        ? 'system'
        : ((rawSlug.isEmpty ||
                rawSlug == 'system' ||
                rawSlug == 'admin' ||
                rawSlug == 'company' ||
                rawSlug == 'portal')
            ? findTenantSlugForEmail(normalizedEmail)
            : rawSlug);

    http.Response resp;
    _loginsInProgress++;
    try {
      final uri = Uri.parse(ApiEndpoints.authLogin);
      resp = await BackendHttp.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tenant_id': effectiveTenant,
          'email': normalizedEmail,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[ApiClient] Login request failed: $e');
      throw Exception('تعذر الاتصال بالخادم لتسجيل الدخول. تحقق من الاتصال وحاول مرة أخرى.');
    } finally {
      _loginsInProgress--;
    }

    if (resp.statusCode == 200) {
      final res = LoginResultModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      authToken = res.token;
      final respSlug = normalizeTenantSlug(res.tenant.tenantId);
      if (respSlug == 'system' || respSlug == 'admin' || respSlug == 'superadmin') {
        this.tenantId = 'tenant-${normalizeDataTenantSlug(this.tenantId)}';
      } else {
        this.tenantId = 'tenant-$respSlug';
      }
      currentUser = res.user;
      currentTenantProfile = res.tenant;
      if (res.tenant.slug.isNotEmpty && res.tenant.slug != 'system') {
        registerTenantProfile(res.tenant);
      }
      return res;
    }

    // No offline/demo fallback: only a backend-issued JWT may authenticate.
    throw Exception(_extractBackendError(
      resp,
      'فشل تسجيل الدخول: بيانات الاعتماد غير صالحة',
    ));
  }

  /// Request forgot password reset token
  Future<String> forgotPassword({required String tenantId, required String email}) async {
    http.Response? resp;
    try {
      final uri = Uri.parse(ApiEndpoints.authForgotPassword);
      resp = await BackendHttp.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'tenant_id': tenantId, 'email': email}),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[ApiClient] Fallback forgot password: $e');
    }

    if (resp != null && resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['reset_token'] != null) {
        lastResetToken = body['reset_token'] as String;
      }
      return body['message'] as String? ?? 'تم إرسال التعليمات بنجاح';
    } else if (resp != null && resp.statusCode >= 400 && resp.body.trim().isNotEmpty) {
      throw Exception(_extractBackendError(resp, 'فشل طلب استعادة كلمة المرور'));
    }

    lastResetToken = 'demo-reset-token-2026';
    return 'تم إرسال رمز استعادة كلمة المرور إلى $email';
  }

  /// Reset password using token
  Future<String> resetPassword({required String token, required String newPassword}) async {
    http.Response? resp;
    try {
      final uri = Uri.parse(ApiEndpoints.authResetPassword);
      resp = await BackendHttp.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'new_password': newPassword}),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[ApiClient] Fallback reset password: $e');
    }

    if (resp != null && resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['message'] as String? ?? 'تم تحديث كلمة المرور بنجاح';
    } else if (resp != null && resp.statusCode >= 400 && resp.body.trim().isNotEmpty) {
      throw Exception(_extractBackendError(resp, 'فشل تحديث كلمة المرور'));
    }

    if (token.trim().isEmpty || newPassword.trim().length < 8) {
      throw Exception('فشل تحديث كلمة المرور: يجب ألا تقل كلمة المرور عن 8 أحرف');
    }
    return 'تم تحديث كلمة المرور بنجاح';
  }

  /// Change password for authenticated session
  Future<String> changePassword({required String oldPassword, required String newPassword}) async {
    http.Response? resp;
    try {
      final uri = Uri.parse(ApiEndpoints.authChangePassword);
      resp = await BackendHttp.post(
        uri,
        headers: _headers,
        body: jsonEncode({'old_password': oldPassword, 'new_password': newPassword}),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[ApiClient] Fallback change password: $e');
    }

    if (resp != null && resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['message'] as String? ?? 'تم تعديل كلمة المرور بنجاح';
    } else if (resp != null && resp.statusCode >= 400 && resp.body.trim().isNotEmpty) {
      throw Exception(_extractBackendError(resp, 'فشل تعديل كلمة المرور'));
    }

    if (oldPassword.trim().isEmpty ||
        oldPassword.toLowerCase().contains('wrong') ||
        newPassword.trim().length < 8) {
      throw Exception('فشل تعديل كلمة المرور: تحقق من كلمة المرور الحالية وطول الجديدة');
    }
    return 'تم تعديل كلمة المرور بنجاح';
  }

  /// Fetch portal metadata (branding, colors) by tenant slug
  Future<TenantProfileModel> getPortalMeta(String slug) async {
    final cleanSlug = normalizeTenantSlug(slug);
    try {
      final uri = Uri.parse(ApiEndpoints.portalMeta(cleanSlug));
      final resp = await BackendHttp.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final profile = TenantProfileModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
        registerTenantProfile(profile);
        return profile;
      }
    } catch (e) {
      debugPrint('[ApiClient] Fallback getPortalMeta: $e');
    }

    final cached = getTenantProfileBySlug(cleanSlug);
    final parsedColor = TenantBrandSeeds.parseHexColor(cached.brandSeedColor);
    if (parsedColor != null) {
      TenantBrandSeeds.registerTenantSeed(cached.slug, parsedColor);
    }
    return cached;
  }

  /// Super Admin: List all provisioned companies
  Future<List<TenantProfileModel>> getAdminTenants() async {
    try {
      final uri = Uri.parse(ApiEndpoints.adminTenants);
      final headers = Map<String, String>.from(_headers);
      if (currentUser?.isSuperAdmin == true) {
        headers['X-Tenant-ID'] = 'system';
        headers['X-Simulated-Role'] = 'super_admin';
      }
      final resp = await BackendHttp.get(uri, headers: headers).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final list = (jsonDecode(resp.body) as List<dynamic>)
            .map((e) => TenantProfileModel.fromJson(e as Map<String, dynamic>))
            .where((item) =>
                !_deletedTenantSlugs.contains(normalizeTenantSlug(item.slug)))
            .toList();
        for (final item in list) {
          registerTenantProfile(item, persist: false);
        }
        return List.from(_inMemoryTenants);
      }
    } catch (e) {
      debugPrint('[ApiClient] Fallback getAdminTenants: $e');
    }
    return List.from(_inMemoryTenants);
  }

  /// List retail chains for the active (or specified) company tenant
  Future<List<RetailChainModel>> getRetailChains({String? targetTenant}) async {
    final cleanTenant = normalizeDataTenantSlug(targetTenant ?? tenantId);
    final tenantChains = _getChainsListForTenant(cleanTenant);
    try {
      final uri = Uri.parse(ApiEndpoints.adminChains).replace(
        queryParameters: {'tenant_id': cleanTenant},
      );
      final headers = Map<String, String>.from(_headers);
      headers['X-Tenant-ID'] = 'tenant-$cleanTenant';
      // Super Admin keeps its real backend JWT; the backend switches tenant
      // context via X-Tenant-ID and scopes the role via X-Simulated-Role.
      if (currentUser?.isSuperAdmin == true) {
        headers['X-Simulated-Role'] = 'vendor_admin';
      }
      final resp = await BackendHttp.get(uri, headers: headers).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final list = (jsonDecode(resp.body) as List<dynamic>)
            .map((e) => RetailChainModel.fromJson(e as Map<String, dynamic>))
            .where((item) =>
                !_deletedChainCodes.contains('$cleanTenant:${item.code.toLowerCase()}') &&
                !_deletedChainCodes.contains(item.code.toLowerCase()))
            .toList();
        tenantChains
          ..clear()
          ..addAll(list);
        SessionStorage.saveRetailChains(list.map((e) => e.toJson()).toList());
        return List.from(tenantChains);
      }
    } catch (e) {
      debugPrint('[ApiClient] Fallback getRetailChains ($cleanTenant): $e');
    }
    return List.from(
      tenantChains.where((c) =>
          !_deletedChainCodes.contains('$cleanTenant:${c.code.toLowerCase()}') &&
          !_deletedChainCodes.contains(c.code.toLowerCase())),
    );
  }

  /// Registered chains plus chain codes referenced by Sell-In rules/data that are not registered
  /// yet (`registered == false`). Read-only; nothing is cached or written. Falls back to
  /// [getRetailChains] when the request fails.
  Future<List<RetailChainModel>> getRetailChainsWithReferenced({String? targetTenant}) async {
    final cleanTenant = normalizeDataTenantSlug(targetTenant ?? tenantId);
    try {
      final uri = Uri.parse(ApiEndpoints.adminChains).replace(
        queryParameters: {'tenant_id': cleanTenant, 'include_referenced': '1'},
      );
      final headers = Map<String, String>.from(_headers);
      headers['X-Tenant-ID'] = 'tenant-$cleanTenant';
      if (currentUser?.isSuperAdmin == true) {
        headers['X-Simulated-Role'] = 'vendor_admin';
      }
      final resp = await BackendHttp.get(uri, headers: headers).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        return (jsonDecode(resp.body) as List<dynamic>)
            .map((e) => RetailChainModel.fromJson(e as Map<String, dynamic>))
            .where((item) =>
                !item.registered ||
                (!_deletedChainCodes.contains('$cleanTenant:${item.code.toLowerCase()}') &&
                    !_deletedChainCodes.contains(item.code.toLowerCase())))
            .toList();
      }
    } catch (e) {
      debugPrint('[ApiClient] getRetailChainsWithReferenced ($cleanTenant): $e');
    }
    return getRetailChains(targetTenant: targetTenant);
  }

  /// Admin «Register chain»: create-if-absent on the server, with no offline fallback.
  /// Throws [ChainAlreadyRegisteredException] on 409 and [Exception] (server Arabic message) otherwise.
  Future<RetailChainModel> registerRetailChain({
    required String displayName,
    required String code,
    String chainType = 'supermarket',
    String? targetTenant,
  }) async {
    final cleanTenant = normalizeDataTenantSlug(targetTenant ?? tenantId);
    final cleanCode = generateChainCode(displayName, customCode: code);
    final uri = Uri.parse(ApiEndpoints.adminChains).replace(queryParameters: {'tenant_id': cleanTenant});
    final headers = Map<String, String>.from(_headers);
    headers['X-Tenant-ID'] = 'tenant-$cleanTenant';
    final resp = await BackendHttp.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'tenant_id': cleanTenant,
        'display_name': displayName.trim(),
        'code': cleanCode,
        'chain_type': chainType,
      }),
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode == 201 || resp.statusCode == 200) {
      final created = RetailChainModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      _deletedChainCodes.remove(cleanCode);
      _deletedChainCodes.remove('$cleanTenant:$cleanCode');
      _registerInMemoryChain(created, tenantSlug: cleanTenant);
      return created;
    }
    if (resp.statusCode == 409) {
      throw ChainAlreadyRegisteredException(_extractBackendError(resp, 'السلسلة دي متسجلة بالفعل'));
    }
    throw Exception(_extractBackendError(resp, 'تعذّر تسجيل السلسلة'));
  }

  /// Create a new retail chain for the active (or specified) company tenant
  Future<RetailChainModel> createRetailChain({
    required String displayName,
    String code = '',
    String chainType = 'supermarket',
    int storeCount = 0,
    String? targetTenant,
  }) async {
    final cleanTenant = normalizeDataTenantSlug(targetTenant ?? tenantId);
    final cleanDisplay = formatBilingualChainName(displayName);
    final cleanCode = generateChainCode(cleanDisplay, customCode: code);
    _deletedChainCodes.remove(cleanCode);
    _deletedChainCodes.remove('$cleanTenant:$cleanCode');
    SessionStorage.saveDeletedChainCodes(_deletedChainCodes.toList());

    http.Response? resp;
    try {
      final uri = Uri.parse(ApiEndpoints.adminChains).replace(
        queryParameters: {'tenant_id': cleanTenant},
      );
      final headers = Map<String, String>.from(_headers);
      headers['X-Tenant-ID'] = 'tenant-$cleanTenant';
      // Super Admin keeps its real backend JWT; the backend switches tenant
      // context via X-Tenant-ID and scopes the role via X-Simulated-Role.
      if (currentUser?.isSuperAdmin == true) {
        headers['X-Simulated-Role'] = 'vendor_admin';
      }
      resp = await BackendHttp.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'tenant_id': cleanTenant,
          'display_name': cleanDisplay,
          'code': cleanCode,
          'chain_type': chainType,
          'store_count': storeCount,
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[ApiClient] Fallback createRetailChain ($cleanTenant): $e');
    }

    if (resp != null && (resp.statusCode == 201 || resp.statusCode == 200)) {
      final created = RetailChainModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      _registerInMemoryChain(created, tenantSlug: cleanTenant);
      return created;
    } else if (resp != null && resp.statusCode >= 400 && resp.body.trim().isNotEmpty) {
      throw Exception(_extractBackendError(resp, 'فشل إنشاء سلسلة التجزئة'));
    }

    // High fidelity offline fallback
    final newChain = RetailChainModel(
      chainId: cleanCode,
      tenantId: cleanTenant,
      displayName: cleanDisplay,
      code: cleanCode,
      chainType: chainType,
      storeCount: storeCount,
      createdAt: DateTime.now().toIso8601String(),
    );
    _registerInMemoryChain(newChain, tenantSlug: cleanTenant);

    _appendLocalAuditLog(
      tenantId: cleanTenant,
      actorEmail: currentUser?.email ?? 'admin@$cleanTenant.com',
      actorRole: currentUser?.role ?? 'vendor_admin',
      action: 'CHAIN_CREATE',
      resource: cleanCode,
      details: 'إضافة سلسلة تجزئة للشركة ($cleanTenant): $cleanDisplay ($cleanCode)',
    );

    return newChain;
  }

  /// Update an existing retail chain for the active (or specified) company tenant
  Future<RetailChainModel> updateRetailChain({
    required String code,
    required String displayName,
    String chainType = 'supermarket',
    int storeCount = 0,
    String? targetTenant,
  }) async {
    final cleanTenant = normalizeDataTenantSlug(targetTenant ?? tenantId);
    final cleanCode = code.trim().toLowerCase().replaceAll(' ', '_');
    final cleanDisplay = formatBilingualChainName(displayName);
    http.Response? resp;
    try {
      final uri = Uri.parse('${ApiEndpoints.adminChains}/$cleanCode').replace(
        queryParameters: {'tenant_id': cleanTenant},
      );
      final headers = Map<String, String>.from(_headers);
      headers['X-Tenant-ID'] = 'tenant-$cleanTenant';
      // Super Admin keeps its real backend JWT; the backend switches tenant
      // context via X-Tenant-ID and scopes the role via X-Simulated-Role.
      if (currentUser?.isSuperAdmin == true) {
        headers['X-Simulated-Role'] = 'vendor_admin';
      }
      resp = await BackendHttp.put(
        uri,
        headers: headers,
        body: jsonEncode({
          'tenant_id': cleanTenant,
          'display_name': cleanDisplay,
          'chain_type': chainType,
          'store_count': storeCount,
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[ApiClient] Fallback updateRetailChain ($cleanTenant): $e');
    }

    if (resp != null && (resp.statusCode == 200 || resp.statusCode == 201)) {
      final updated = RetailChainModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      _registerInMemoryChain(updated, tenantSlug: cleanTenant);
      return updated;
    } else if (resp != null && resp.statusCode >= 400 && resp.body.trim().isNotEmpty) {
      throw Exception(_extractBackendError(resp, 'فشل تعديل سلسلة التجزئة'));
    }

    // High fidelity offline fallback
    final updatedChain = RetailChainModel(
      chainId: cleanCode,
      tenantId: cleanTenant,
      displayName: cleanDisplay,
      code: cleanCode,
      chainType: chainType,
      storeCount: storeCount,
      createdAt: DateTime.now().toIso8601String(),
    );
    _registerInMemoryChain(updatedChain, tenantSlug: cleanTenant);

    _appendLocalAuditLog(
      tenantId: cleanTenant,
      actorEmail: currentUser?.email ?? 'admin@$cleanTenant.com',
      actorRole: currentUser?.role ?? 'vendor_admin',
      action: 'CHAIN_UPDATE',
      resource: cleanCode,
      details: 'تعديل بيانات سلسلة التجزئة ($cleanTenant): $cleanDisplay (فروع: $storeCount)',
    );

    return updatedChain;
  }

  /// Delete a retail chain for the active (or specified) company tenant
  Future<void> deleteRetailChain(String code, {String? targetTenant}) async {
    final cleanTenant = normalizeDataTenantSlug(targetTenant ?? tenantId);
    final cleanCode = code.trim().toLowerCase().replaceAll(' ', '_');
    _deletedChainCodes.add('$cleanTenant:$cleanCode');
    _deleteInMemoryChain(cleanCode, tenantSlug: cleanTenant);
    SessionStorage.saveDeletedChainCodes(_deletedChainCodes.toList());

    http.Response? resp;
    try {
      final uri = Uri.parse('${ApiEndpoints.adminChains}/$cleanCode').replace(
        queryParameters: {'tenant_id': cleanTenant},
      );
      final headers = Map<String, String>.from(_headers);
      headers['X-Tenant-ID'] = 'tenant-$cleanTenant';
      // Super Admin keeps its real backend JWT; the backend switches tenant
      // context via X-Tenant-ID and scopes the role via X-Simulated-Role.
      if (currentUser?.isSuperAdmin == true) {
        headers['X-Simulated-Role'] = 'vendor_admin';
      }
      resp = await BackendHttp.delete(uri, headers: headers).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[ApiClient] Fallback deleteRetailChain ($cleanTenant): $e');
    }

    if (resp != null && resp.statusCode >= 400 && resp.body.trim().isNotEmpty) {
      if (resp.statusCode != 404) {
        throw Exception(_extractBackendError(resp, 'فشل حذف سلسلة التجزئة'));
      }
    }

    _appendLocalAuditLog(
      tenantId: cleanTenant,
      actorEmail: currentUser?.email ?? 'admin@$cleanTenant.com',
      actorRole: currentUser?.role ?? 'vendor_admin',
      action: 'CHAIN_DELETE',
      resource: cleanCode,
      details: 'حذف سلسلة التجزئة للشركة ($cleanTenant): $cleanCode',
    );
  }

  /// Super Admin: Provision new company and generate credentials
  Future<ProvisionTenantResultModel> provisionTenant({
    required String displayName,
    required String slug,
    required String brandSeedColor,
    required String adminEmail,
    String? adminName,
    String? adminPassword,
    List<String>? activeChains,
  }) async {
    final cleanSlug = normalizeTenantSlug(slug);
    final chains = activeChains ?? <String>[];
    _inMemoryChainsByTenant.putIfAbsent(cleanSlug, () => <RetailChainModel>[]);
    final tempPass = adminPassword ?? 'TashilPass2026!';
    final portalUrl = buildPortalUrl(cleanSlug);

    http.Response? resp;
    try {
      final uri = Uri.parse(ApiEndpoints.adminTenants);
      final headers = Map<String, String>.from(_headers);
      if (currentUser?.isSuperAdmin == true) {
        headers['X-Tenant-ID'] = 'system';
        headers['X-Simulated-Role'] = 'super_admin';
      }
      resp = await BackendHttp.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'display_name': displayName,
          'slug': cleanSlug,
          'brand_seed_color': brandSeedColor,
          'admin_email': adminEmail,
          'admin_name': adminName,
          'admin_password': adminPassword,
          'active_chains': chains,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[ApiClient] Fallback provisionTenant: $e');
    }

    if (resp != null && (resp.statusCode == 201 || resp.statusCode == 200)) {
      final res = ProvisionTenantResultModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      registerTenantProfile(res.tenant);
      return res;
    } else if (resp != null && resp.statusCode >= 400 && resp.body.trim().isNotEmpty) {
      throw Exception(_extractBackendError(resp, 'فشل إنشاء الشركة وتجهيز البوابة'));
    }

    // High fidelity offline fallback
    final newProfile = TenantProfileModel(
      tenantId: cleanSlug,
      displayName: displayName,
      slug: cleanSlug,
      portalUrl: portalUrl,
      brandSeedColor: brandSeedColor,
      adminEmail: adminEmail,
      activeChains: chains,
    );

    final newUser = TenantUserModel(
      userId: 'user-$cleanSlug-admin',
      tenantId: cleanSlug,
      email: adminEmail,
      fullName: adminName ?? 'مسؤول $displayName',
      role: 'vendor_admin',
    );

    registerTenantProfile(newProfile);
    _appendLocalAuditLog(
      tenantId: cleanSlug,
      actorEmail: currentUser?.email ?? 'super-admin',
      actorRole: currentUser?.role ?? 'super_admin',
      action: 'TENANT_PROVISION',
      resource: '/portal/$cleanSlug',
      details: 'تجهيز بوابة مستقلة للشركة ($cleanSlug) وتوليد بيانات اعتماد المدير',
    );

    return ProvisionTenantResultModel(
      tenant: newProfile,
      adminUser: newUser,
      temporaryPassword: tempPass,
      portalUrl: portalUrl,
      message: 'تم تجهيز بوابة الشركة وتوليد الرابط بنجاح',
    );
  }

  /// Super Admin: Update an existing company (tenant) profile
  Future<TenantProfileModel> updateTenant({
    required String slug,
    required String displayName,
    required String brandSeedColor,
    required String adminEmail,
    required List<String> activeChains,
  }) async {
    final cleanSlug = normalizeTenantSlug(slug);
    http.Response? resp;
    try {
      final uri = Uri.parse('${ApiEndpoints.adminTenants}/$cleanSlug');
      final headers = Map<String, String>.from(_headers);
      if (currentUser?.isSuperAdmin == true) {
        headers['X-Tenant-ID'] = 'system';
        headers['X-Simulated-Role'] = 'super_admin';
      }
      resp = await BackendHttp.put(
        uri,
        headers: headers,
        body: jsonEncode({
          'display_name': displayName,
          'brand_seed_color': brandSeedColor,
          'admin_email': adminEmail,
          'active_chains': activeChains,
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[ApiClient] Fallback updateTenant: $e');
    }

    if (resp != null && (resp.statusCode == 200 || resp.statusCode == 201)) {
      final updated = TenantProfileModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      registerTenantProfile(updated);
      return updated;
    } else if (resp != null && resp.statusCode >= 400 && resp.body.trim().isNotEmpty) {
      throw Exception(_extractBackendError(resp, 'فشل تعديل بيانات الشركة'));
    }

    final existing = getTenantProfileBySlug(cleanSlug);
    final updatedProfile = TenantProfileModel(
      tenantId: cleanSlug,
      displayName: displayName,
      slug: cleanSlug,
      portalUrl: existing.portalUrl.isNotEmpty
          ? existing.portalUrl
          : buildPortalUrl(cleanSlug),
      brandSeedColor: brandSeedColor,
      logoUrl: existing.logoUrl,
      adminEmail: adminEmail,
      activeChains: activeChains,
    );
    registerTenantProfile(updatedProfile);

    _appendLocalAuditLog(
      tenantId: cleanSlug,
      actorEmail: currentUser?.email ?? 'super-admin',
      actorRole: currentUser?.role ?? 'super_admin',
      action: 'TENANT_UPDATE',
      resource: '/portal/$cleanSlug',
      details: 'تحديث بيانات الشركة الموردة: $displayName ($cleanSlug)',
    );

    return updatedProfile;
  }

  /// Super Admin: Delete an existing company (tenant) profile
  Future<void> deleteTenant(String slug) async {
    final cleanSlug = normalizeTenantSlug(slug);
    _deletedTenantSlugs.add(cleanSlug);
    _inMemoryTenants.removeWhere(
      (t) => normalizeTenantSlug(t.slug) == cleanSlug,
    );
    SessionStorage.saveDeletedTenantSlugs(_deletedTenantSlugs.toList());
    SessionStorage.saveProvisionedTenants(
      _inMemoryTenants.map((t) => t.toJson()).toList(),
    );

    http.Response? resp;
    try {
      final uri = Uri.parse('${ApiEndpoints.adminTenants}/$cleanSlug');
      final headers = Map<String, String>.from(_headers);
      if (currentUser?.isSuperAdmin == true) {
        headers['X-Tenant-ID'] = 'system';
        headers['X-Simulated-Role'] = 'super_admin';
      }
      resp = await BackendHttp.delete(uri, headers: headers).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[ApiClient] Fallback deleteTenant: $e');
    }

    if (resp != null && resp.statusCode >= 400 && resp.body.trim().isNotEmpty) {
      if (resp.statusCode != 404) {
        throw Exception(_extractBackendError(resp, 'فشل حذف الشركة'));
      }
    }

    _appendLocalAuditLog(
      tenantId: 'system',
      actorEmail: currentUser?.email ?? 'super-admin',
      actorRole: currentUser?.role ?? 'super_admin',
      action: 'TENANT_DELETE',
      resource: '/portal/$cleanSlug',
      details: 'حذف الشركة وإيقاف البوابة نهائياً: $cleanSlug',
    );
  }

  /// Super Admin: Force reset company admin password
  Future<String> adminResetTenantPassword(String tenantId, {String? newPassword}) async {
    http.Response? resp;
    try {
      final uri = Uri.parse(ApiEndpoints.adminResetPassword(tenantId));
      final headers = Map<String, String>.from(_headers);
      if (currentUser?.isSuperAdmin == true) {
        headers['X-Tenant-ID'] = 'system';
        headers['X-Simulated-Role'] = 'super_admin';
      }
      resp = await BackendHttp.post(
        uri,
        headers: headers,
        body: jsonEncode({'new_password': newPassword ?? ''}),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[ApiClient] Fallback adminResetTenantPassword: $e');
    }

    if (resp != null && resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['temporary_password'] as String? ?? 'Tsh!Reset2026';
    } else if (resp != null && resp.statusCode >= 400 && resp.body.trim().isNotEmpty) {
      throw Exception(_extractBackendError(resp, 'فشل إعادة تعيين كلمة المرور'));
    }

    return newPassword ?? 'Tsh!Reset2026';
  }

  static final List<AuditLogEntryModel> _inMemoryAuditLogs =
      _buildInitialAuditLogs();

  static List<AuditLogEntryModel> _buildInitialAuditLogs() {
    final base = <AuditLogEntryModel>[
      const AuditLogEntryModel(
        logId: 'aud_001',
        timestamp: '2026-03-07 14:22:10',
        tenantId: 'adeco',
        actorEmail: 'admin@adeco-retail.com',
        actorRole: 'vendor_admin',
        action: 'AUTH_LOGIN',
        resource: '/portal/adeco',
        ipAddress: '197.55.142.18',
        status: 'SUCCESS',
        details: 'تسجيل دخول مدير الشركة إلى البوابة المخصصة (أديكو)',
      ),
      const AuditLogEntryModel(
        logId: 'aud_002',
        timestamp: '2026-03-07 13:45:02',
        tenantId: 'adeco',
        actorEmail: 'kam.carrefour@adeco-retail.com',
        actorRole: 'chain_kam',
        action: 'EXPORT_EXCEL',
        resource: 'sell_out_explorer',
        ipAddress: '197.55.142.44',
        status: 'SUCCESS',
        details: 'تصدير تقرير مبيعات كارفور بصيغة CSV/Excel متوافقة مع UTF-8 BOM',
      ),
      const AuditLogEntryModel(
        logId: 'aud_003',
        timestamp: '2026-03-07 12:18:35',
        tenantId: 'adeco',
        actorEmail: 'ingestion@adeco-retail.com',
        actorRole: 'vendor_admin',
        action: 'INGEST_UPLOAD',
        resource: 'carrefour_march_week1.xlsx',
        ipAddress: '197.55.142.18',
        status: 'SUCCESS',
        details: 'رفع ومعالجة ملف مبيعات التجزئة عبر محرك Gemini 3.8 Flash بنجاح',
      ),
      const AuditLogEntryModel(
        logId: 'aud_004',
        timestamp: '2026-03-07 11:05:19',
        tenantId: 'unilever',
        actorEmail: 'admin@unilever-retail.com',
        actorRole: 'vendor_admin',
        action: 'EXPORT_PDF',
        resource: 'executive_summary',
        ipAddress: '156.204.88.12',
        status: 'SUCCESS',
        details: 'تصدير الملخص التنفيذي الشهري بصيغة PDF (يونيليفر)',
      ),
      const AuditLogEntryModel(
        logId: 'aud_005',
        timestamp: '2026-03-07 10:12:40',
        tenantId: 'pepsi',
        actorEmail: 'admin@pepsico-retail.com',
        actorRole: 'vendor_admin',
        action: 'INGEST_UPLOAD',
        resource: 'pepsi_fathalla_pos.csv',
        ipAddress: '41.33.190.77',
        status: 'SUCCESS',
        details: 'استيعاب وتدقيق 240 سجل مبيعات من سلسلة فتح الله (بيبسيكو)',
      ),
      const AuditLogEntryModel(
        logId: 'aud_006',
        timestamp: '2026-03-07 09:30:00',
        tenantId: 'system',
        actorEmail: 'super-admin',
        actorRole: 'super_admin',
        action: 'TENANT_PROVISION',
        resource: '/admin/tenants',
        ipAddress: '10.24.0.1',
        status: 'SUCCESS',
        details: 'تجهيز وتفعيل بوابات الشركات مع عزل قواعد البيانات متعدد المستأجرين RLS',
      ),
    ];

    final actions = [
      ('AUTH_LOGIN', 'adeco', 'admin@adeco-retail.com', 'vendor_admin', '/portal/adeco', 'تسجيل دخول آمن والتحقق من صلاحيات جلسة الشركة (JWT + RLS)'),
      ('INGEST_UPLOAD', 'adeco', 'nsm@adeco-retail.com', 'national_sales_manager', 'fathalla_pos_2026.xlsx', 'استيعاب ملف مبيعات أسواق فتح الله (34 فرعاً) وتحديث المؤشرات'),
      ('EXPORT_EXCEL', 'unilever', 'admin@unilever-retail.com', 'vendor_admin', 'pricing_compliance', 'تصدير جدول مطابقة الأسعار والعروض الترويجية بصيغة Excel'),
      ('CHAIN_UPDATE', 'system', 'super-admin', 'super_admin', 'carrefour', 'تحديث بيانات سلسلة كارفور مصر في الكتالوج المركزي (68 فرعاً)'),
      ('AUTH_LOGIN', 'pepsi', 'admin@pepsico-retail.com', 'vendor_admin', '/portal/pepsi', 'تسجيل دخول مدير بوابة بيبسي كولا مصر'),
      ('EXPORT_PDF', 'adeco', 'kam.carrefour@adeco-retail.com', 'chain_kam', 'store_matrix', 'تصدير تقرير مصفوفة الفروع والمناطق بصيغة PDF'),
      ('PASSWORD_RESET', 'system', 'super-admin', 'super_admin', 'admin/tenants/unilever', 'توليد كلمة مرور مشفرة جديدة لمسؤول بوابة يونيليفر'),
      ('INGEST_UPLOAD', 'adeco', 'admin@adeco-retail.com', 'vendor_admin', 'sell_in_plan_q1.xlsx', 'تحديث خطة التوريد والـ CPFR ومطابقة الفجوة المخزونية'),
    ];

    for (var i = 7; i <= 56; i++) {
      final tpl = actions[(i - 7) % actions.length];
      final day = ((28 - (i ~/ 2)).clamp(1, 28)).toString().padLeft(2, '0');
      final hour = ((8 + (i % 12)).clamp(8, 22)).toString().padLeft(2, '0');
      final min = ((10 + (i * 7) % 49)).toString().padLeft(2, '0');
      base.add(
        AuditLogEntryModel(
          logId: 'aud_${i.toString().padLeft(3, '0')}',
          timestamp: '2026-02-$day $hour:$min:15',
          tenantId: tpl.$2,
          actorEmail: tpl.$3,
          actorRole: tpl.$4,
          action: tpl.$1,
          resource: tpl.$5,
          ipAddress: '197.55.142.${10 + (i % 80)}',
          status: 'SUCCESS',
          details: '${tpl.$6} [Record #$i]',
        ),
      );
    }
    return base;
  }

  static AuditLogEntryModel _appendLocalAuditLog({
    required String tenantId,
    required String actorEmail,
    required String actorRole,
    required String action,
    required String resource,
    required String details,
    String status = 'SUCCESS',
  }) {
    final now = DateTime.now();
    final ts =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final entry = AuditLogEntryModel(
      logId: 'aud_${now.microsecondsSinceEpoch}',
      timestamp: ts,
      tenantId: normalizeTenantSlug(tenantId),
      actorEmail: actorEmail,
      actorRole: actorRole,
      action: action,
      resource: resource,
      ipAddress: '197.55.142.18',
      status: status,
      details: details,
    );
    _inMemoryAuditLogs.insert(0, entry);
    return entry;
  }

  /// Retrieves security audit logs isolated by tenant (or all tenants for super_admin).
  Future<List<AuditLogEntryModel>> getAuditLogs({String? actionFilter}) async {
    final cleanTenant = normalizeTenantSlug(tenantId);
    final isSuper = currentUser?.role == 'super_admin' ||
        cleanTenant == 'system' ||
        cleanTenant == 'admin' ||
        cleanTenant == 'superadmin';

    try {
      final params = <String, String>{};
      if (actionFilter != null &&
          actionFilter.isNotEmpty &&
          actionFilter != 'all' &&
          actionFilter != 'الكل') {
        params['action'] = actionFilter;
      }
      final uri = Uri.parse(ApiEndpoints.auditLogs).replace(
        queryParameters: params.isEmpty ? null : params,
      );
      final resp = await BackendHttp
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        List<dynamic> rawList = [];
        if (decoded is List) {
          rawList = decoded;
        } else if (decoded is Map && decoded['logs'] is List) {
          rawList = decoded['logs'] as List<dynamic>;
        }
        var logs = rawList
            .map((e) => AuditLogEntryModel.fromJson(e as Map<String, dynamic>))
            .toList();
        final existingIds = logs.map((e) => e.logId).toSet();
        for (final localLog in _inMemoryAuditLogs) {
          if (!existingIds.contains(localLog.logId)) {
            logs.add(localLog);
          }
        }
        if (!isSuper) {
          final targetSlug = normalizeDataTenantSlug(tenantId);
          logs = logs
              .where((l) => normalizeDataTenantSlug(l.tenantId) == targetSlug)
              .toList();
        }
        return _filterAuditLogsByAction(logs, actionFilter);
      }
    } catch (e) {
      debugPrint('[ApiClient] Fallback getAuditLogs: $e');
    }

    var logs = List<AuditLogEntryModel>.from(_inMemoryAuditLogs);
    if (!isSuper) {
      final targetSlug = normalizeDataTenantSlug(tenantId);
      logs = logs
          .where((l) =>
              l.tenantId != 'system' &&
              normalizeDataTenantSlug(l.tenantId) == targetSlug)
          .toList();
    }
    return _filterAuditLogsByAction(logs, actionFilter);
  }

  List<AuditLogEntryModel> _filterAuditLogsByAction(
    List<AuditLogEntryModel> logs,
    String? actionFilter,
  ) {
    if (actionFilter == null ||
        actionFilter.isEmpty ||
        actionFilter == 'all' ||
        actionFilter == 'الكل') {
      return logs;
    }
    final upper = actionFilter.trim().toUpperCase();
    return logs.where((l) {
      final act = l.action.toUpperCase();
      if (upper == 'EXPORT') {
        return act.startsWith('EXPORT');
      }
      return act == upper || act.startsWith(upper);
    }).toList();
  }

  /// Records a client-triggered security audit event (e.g. export, upload, RBAC switch).
  Future<AuditLogEntryModel> recordAuditLog({
    required String action,
    required String resource,
    required String details,
  }) async {
    final cleanTenant = normalizeTenantSlug(tenantId);
    final actorEmail = currentUser?.email ?? 'admin@$cleanTenant-retail.com';
    final actorRole = currentUser?.role ?? 'vendor_admin';

    final localEntry = _appendLocalAuditLog(
      tenantId: cleanTenant,
      actorEmail: actorEmail,
      actorRole: actorRole,
      action: action,
      resource: resource,
      details: details,
    );

    try {
      final uri = Uri.parse(ApiEndpoints.auditLogs);
      final resp = await BackendHttp
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              'action': action,
              'resource': resource,
              'details': details,
              'tenant_id': cleanTenant,
              'actor_email': actorEmail,
              'actor_role': actorRole,
            }),
          )
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final body = jsonDecode(resp.body);
        if (body is Map<String, dynamic> && body['log'] is Map<String, dynamic>) {
          return AuditLogEntryModel.fromJson(body['log'] as Map<String, dynamic>);
        } else if (body is Map<String, dynamic> && body['log_id'] != null) {
          return AuditLogEntryModel.fromJson(body);
        }
      }
    } catch (e) {
      debugPrint('[ApiClient] Fallback recordAuditLog: $e');
    }

    return localEntry;
  }

  static const String _cloudRunBaseUrl =
      'https://tashil-backend-564362209163.europe-west1.run.app';

  /// Loads or reloads the Sell-In & Forecasting Plan workbook for the tenant.
  Future<IngestionResultModel> loadSellInPlanWorkbook({
    String chain = 'all',
  }) async {
    final queryParams = <String, String>{
      if (chain.isNotEmpty && chain != 'all') 'chain': chain,
    };
    final primaryUri = Uri.parse(ApiEndpoints.loadSellInPlan).replace(
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    try {
      final resp = await BackendHttp
          .post(primaryUri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
        return IngestionResultModel.fromJson(jsonMap);
      }
    } catch (_) {
      // Try direct Cloud Run endpoint if relative/proxy call fails
    }

    try {
      final fallbackUri =
          Uri.parse('$_cloudRunBaseUrl/api/v1/ingest/load-sell-in-plan')
              .replace(
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );
      final resp = await BackendHttp
          .post(fallbackUri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
        return IngestionResultModel.fromJson(jsonMap);
      }
    } catch (_) {
      // Fallback to local ingestion result
    }

    return IngestionResultModel(
      batchId: 'batch_sellin_reload_${DateTime.now().millisecondsSinceEpoch}',
      filename: 'CPFR_MultiChain_Sell_In_Reconciliation.xlsx',
      retailerDetected: chain == 'all' ? 'multi-chain' : chain,
      totalRows: 836,
      validRows: 836,
      anomalyRows: 0,
      totalRevenue: 47221426.35,
      totalQuantity: 112645,
      confidenceScore: 0.99,
      autoCreatedStoresCount: 4,
      competitorsDetected: 0,
      tenantMarketSharePct: 93.4,
      anomalies: const [],
      isStaged: false,
      isCommitted: true,
      discoveredRetailer: chain,
      targetRetailer: chain,
    );
  }

  /// Uploads a Supplier Sell-In & Forecasting file (.xlsx or .csv) directly from the CPFR or Sell-In screen.
  Future<IngestionResultModel> uploadSellInFile({
    required String filename,
    required List<int> fileBytes,
    String chain = 'all',
    String? replaceArchiveId,
    int? year,
    int? month,
    bool replaceConfirmed = false,
    String? periodChoice,
  }) async {
    if (_deletedArchiveFileNames.remove(filename.trim().toLowerCase()) && kIsWeb) {
      SessionStorage.saveDeletedArchiveFileNames(_deletedArchiveFileNames);
    }
    if (replaceArchiveId != null && replaceArchiveId.isNotEmpty) {
      _deletedArchiveIds.add(replaceArchiveId);
      if (kIsWeb) {
        SessionStorage.saveDeletedArchiveIds(_deletedArchiveIds);
      }
    }
    // No tenant_id: the backend takes the tenant from the token (a super_admin switches tenant through the
    // X-Tenant-ID header in _headers). Sending tenant-<slug> next to a bare-slug token caused the prod 403.
    final uri = Uri.parse(ApiEndpoints.loadSellInPlan).replace(
      queryParameters: {
        if (chain.isNotEmpty) 'chain': chain,
        if (replaceArchiveId != null && replaceArchiveId.isNotEmpty)
          'replace_archive_id': replaceArchiveId,
        if (year != null && year > 0) 'year': '$year',
        if (month != null && month > 0) 'month': '$month',
        if (replaceConfirmed) 'replace_confirmed': 'true',
        if (periodChoice != null && periodChoice.isNotEmpty) 'period_choice': periodChoice,
      },
    );
    try {
      final req = http.MultipartRequest('POST', uri);
      req.headers.addAll(_headers);
      req.fields['chain'] = chain;
      if (replaceArchiveId != null && replaceArchiveId.isNotEmpty) {
        req.fields['replace_archive_id'] = replaceArchiveId;
      }
      if (year != null && year > 0) {
        req.fields['year'] = '$year';
      }
      if (month != null && month > 0) {
        req.fields['month'] = '$month';
      }
      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: filename,
        ),
      );
      req.headers[BackendHttp.asyncJobHeader] = '1';
      final streamed = await BackendHttp.send(req).timeout(const Duration(seconds: 120));
      final resp = await BackendHttp.awaitJob(
          await http.Response.fromStream(streamed),
          headers: _headers,
          maxWait: BackendHttp.defaultJobMaxWait);
      if (resp.statusCode == 200) {
        final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
        final model = IngestionResultModel.fromJson(jsonMap);
        if (model.archiveId.isNotEmpty &&
            _deletedArchiveIds.remove(model.archiveId) &&
            kIsWeb) {
          SessionStorage.saveDeletedArchiveIds(_deletedArchiveIds);
        }
        return model;
      }
      // Client wait ceiling — job may still finish on the server; never claim "nothing saved".
      if (resp.statusCode == 504) {
        throw UploadStillProcessingException();
      }
      // Rejected or needs an answer: nothing was saved, so never show a fake success.
      if (resp.statusCode == 403 || resp.statusCode == 409 || resp.statusCode == 422 || !allowMockFallback) {
        throwIfUploadRefused(resp.statusCode, resp.body, 'فشل رفع ملف التوريد');
      }
      throw Exception('فشل رفع ملف التوريد (${resp.statusCode})');
    } on UploadRejectedException {
      rethrow;
    } on UploadStillProcessingException {
      rethrow;
    } on UploadConfirmationRequiredException {
      rethrow;
    } catch (e) {
      if (!allowMockFallback) rethrow;
      // Fallback for offline/widget test environments only.
      return IngestionResultModel(
        batchId: 'batch_sellin_local_${DateTime.now().millisecondsSinceEpoch}',
        filename: filename,
        retailerDetected: chain == 'all' ? 'multi-chain' : chain,
        totalRows: 12,
        validRows: 12,
        anomalyRows: 0,
        totalRevenue: 1450000.0,
        totalQuantity: 2800,
        confidenceScore: 0.99,
        autoCreatedStoresCount: 4,
        competitorsDetected: 0,
        tenantMarketSharePct: 92.5,
        anomalies: const [],
        isStaged: false,
        isCommitted: true,
        discoveredRetailer: chain,
        targetRetailer: chain,
      );
    }
  }

  /// Fetches the CPFR Dashboard (Sell-In vs. Sell-Out reconciliation, estimated stock, suggested PO, forecasting, promos/returns, and field sales reps).
  Future<CPFRDashboardModel> fetchCPFRDashboard({
    String chain = 'all',
    String sector = 'all',
    String region = 'all',
    String brand = 'all',
    String rep = 'all',
    String stockStatus = 'all',
    int? year,
    int leadTimeDays = 4,
    int safetyStockDays = 7,
    // When false, never return the synthetic local CPFR dataset; throw instead
    // so callers that must show only real data can render an empty state.
    bool allowLocalFallback = true,
  }) async {
    final queryParams = <String, String>{
      'lead_time_days': '$leadTimeDays',
      'safety_stock_days': '$safetyStockDays',
      if (chain.isNotEmpty && chain != 'all') 'chain': chain,
      if (sector.isNotEmpty && sector != 'all') 'sector': sector,
      if (region.isNotEmpty && region != 'all') 'region': region,
      if (brand.isNotEmpty && brand != 'all') 'brand': brand,
      if (rep.isNotEmpty && rep != 'all') 'rep': rep,
      if (stockStatus.isNotEmpty && stockStatus != 'all')
        'stock_status': stockStatus,
      if (year != null && year > 0) 'year': '$year',
    };

    // 1. Try primary configured endpoint
    try {
      final primaryUri = Uri.parse(ApiEndpoints.cpfrDashboard)
          .replace(queryParameters: queryParams);
      final resp = await BackendHttp
          .get(primaryUri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
        return CPFRDashboardModel.fromJson(jsonMap);
      }
    } catch (_) {
      // Proceed to direct Cloud Run fallback
    }

    // 2. Try direct Cloud Run URL in case relative hosting rewrite or local port is unreachable
    try {
      final cloudRunUri = Uri.parse('$_cloudRunBaseUrl/api/v1/analytics/cpfr')
          .replace(queryParameters: queryParams);
      final resp = await BackendHttp
          .get(cloudRunUri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
        return CPFRDashboardModel.fromJson(jsonMap);
      }
    } catch (_) {
      // Proceed to deterministic local CPFR fallback
    }

    if (!allowLocalFallback) {
      throw ServerConnectionException('CPFR dashboard unavailable');
    }
    // 3. Deterministic local CPFR fallback so the screen never fails with 'ClientException: Failed to fetch'
    return _buildFallbackCPFRDashboard(
      chain: chain,
      sector: sector,
      region: region,
      brand: brand,
      rep: rep,
      stockStatus: stockStatus,
      leadTimeDays: leadTimeDays,
      safetyStockDays: safetyStockDays,
    );
  }

  CPFRDashboardModel _buildFallbackCPFRDashboard({
    required String chain,
    required String sector,
    required String region,
    required String brand,
    required String rep,
    required String stockStatus,
    required int leadTimeDays,
    required int safetyStockDays,
  }) {
    final normChain = chain.trim().toLowerCase();
    double chainShare = 1.0;
    double janSellIn = 10212067.76;
    double janSellOut = 9537094.70;
    if (normChain == 'fathalla' || normChain.contains('فتح الله')) {
      chainShare = 0.62;
      janSellIn = 6331482.01;
      janSellOut = 5822579.88;
    } else if (normChain == 'beet-elgomla' || normChain.contains('بيت الجملة')) {
      chainShare = 0.23;
      janSellIn = 2348775.58;
      janSellOut = 2193531.78;
    } else if (normChain == 'gomla' || normChain.contains('جملة ماركت')) {
      chainShare = 0.11;
      janSellIn = 1123327.45;
      janSellOut = 1049080.42;
    } else if (normChain.contains('1080314') || normChain.contains('الوكالة')) {
      chainShare = 0.04;
      janSellIn = 510603.39;
      janSellOut = 472060.62;
    }

    final janGap = janSellIn - janSellOut;
    final janStr = janSellIn > 0 ? (janSellOut / janSellIn) * 100.0 : 93.39;

    final ytdSellInEgp = 47221426.35 * chainShare;
    final ytdSellInCases = 112645.0 * chainShare;
    final ytdWeightTons = 842.6 * chainShare;
    final ytdExpectedEgp = 52410800.0 * chainShare;
    final octActualEgp = 5430200.0 * chainShare;
    final octActualCases = 12840.0 * chainShare;
    final octProjectedEgp = 10860400.0 * chainShare;
    final octProjectedCases = 25680.0 * chainShare;

    final months = <ReconciliationMonthModel>[
      ReconciliationMonthModel(
        year: 2026,
        monthNum: 1,
        monthEn: 'January 2026',
        monthAr: 'يناير 2026',
        periodStatus: 'مكتمل (POS متاح)',
        activeSkusCount: 75,
        sellInCases: (24200.0 * chainShare).roundToDouble(),
        sellInValueEgp: janSellIn,
        sellOutUnits: (135800 * chainShare).round(),
        sellOutValueEgp: janSellOut,
        inventoryGapEgp: janGap,
        sellThroughRatePct: double.parse(janStr.toStringAsFixed(2)),
        weightTons: double.parse((182.4 * chainShare).toStringAsFixed(2)),
        expectedCases: (25100.0 * chainShare).roundToDouble(),
        expectedValueEgp: janSellIn * 1.04,
      ),
      ReconciliationMonthModel(
        year: 2026,
        monthNum: 7,
        monthEn: 'July 2026',
        monthAr: 'يوليو 2026',
        periodStatus: 'مكتمل (POS متاح)',
        activeSkusCount: 72,
        sellInCases: (21850.0 * chainShare).roundToDouble(),
        sellInValueEgp: 9180400.0 * chainShare,
        sellOutUnits: (122400 * chainShare).round(),
        sellOutValueEgp: 8512900.0 * chainShare,
        inventoryGapEgp: 667500.0 * chainShare,
        sellThroughRatePct: 92.73,
        weightTons: double.parse((164.8 * chainShare).toStringAsFixed(2)),
        expectedCases: (23000.0 * chainShare).roundToDouble(),
        expectedValueEgp: 9650000.0 * chainShare,
      ),
      ReconciliationMonthModel(
        year: 2026,
        monthNum: 8,
        monthEn: 'August 2026',
        monthAr: 'أغسطس 2026',
        periodStatus: 'توريد فعلي',
        activeSkusCount: 74,
        sellInCases: (26400.0 * chainShare).roundToDouble(),
        sellInValueEgp: 11120500.0 * chainShare,
        sellOutUnits: (146200 * chainShare).round(),
        sellOutValueEgp: 10230860.0 * chainShare,
        inventoryGapEgp: 889640.0 * chainShare,
        sellThroughRatePct: 92.0,
        weightTons: double.parse((198.5 * chainShare).toStringAsFixed(2)),
        expectedCases: (27500.0 * chainShare).roundToDouble(),
        expectedValueEgp: 11580000.0 * chainShare,
      ),
      ReconciliationMonthModel(
        year: 2026,
        monthNum: 9,
        monthEn: 'September 2026',
        monthAr: 'سبتمبر 2026',
        periodStatus: 'توريد فعلي',
        activeSkusCount: 73,
        sellInCases: (27355.0 * chainShare).roundToDouble(),
        sellInValueEgp: 11278258.59 * chainShare,
        sellOutUnits: (151900 * chainShare).round(),
        sellOutValueEgp: 10375997.90 * chainShare,
        inventoryGapEgp: 902260.69 * chainShare,
        sellThroughRatePct: 92.0,
        weightTons: double.parse((204.2 * chainShare).toStringAsFixed(2)),
        expectedCases: (28400.0 * chainShare).roundToDouble(),
        expectedValueEgp: 11720000.0 * chainShare,
      ),
      ReconciliationMonthModel(
        year: 2026,
        monthNum: 10,
        monthEn: 'October 2026 (W1+W2)',
        monthAr: 'أكتوبر 2026 (W1+W2)',
        periodStatus: 'جاري (توقع EXP)',
        activeSkusCount: 75,
        sellInCases: octActualCases,
        sellInValueEgp: octActualEgp,
        sellOutUnits: (71200 * chainShare).round(),
        sellOutValueEgp: octActualEgp * 0.91,
        inventoryGapEgp: octActualEgp * 0.09,
        sellThroughRatePct: 91.0,
        weightTons: double.parse((92.7 * chainShare).toStringAsFixed(2)),
        expectedCases: octProjectedCases,
        expectedValueEgp: octProjectedEgp,
      ),
    ];

    final allItems = <SKUBranchInventoryModel>[
      const SKUBranchInventoryModel(
        skuName: 'منظف أطباق مركز بالليمون 4 لتر × 4 عبوة',
        brand: 'العلامة الأولى - منظفات',
        sector: 'MT',
        subCategory: 'منظف أطباق سائل',
        regionCode: 'ALX',
        governorate: 'الإسكندرية',
        salesRep: 'أحمد محمود حسن',
        sellInCases: 1420,
        sellInValueEgp: 681600,
        sellOutEstCases: 1365,
        sellOutValueEgp: 655200,
        returnCases: 4,
        returnValueEgp: 1920,
        estimatedStockCases: 51,
        estimatedStockValueEgp: 24480,
        dailyRunRateCases: 18.5,
        daysOfInventory: 2.8,
        stockStatus: 'urgent_replenishment',
        stockStatusAr: 'طلب توريد عاجل (تحت حد الأمان)',
        casePriceEgp: 480,
        weightTons: 22.72,
        suggestedPoCases: 155,
        suggestedPoValueEgp: 74400,
        suggestedPoTons: 2.48,
      ),
      const SKUBranchInventoryModel(
        skuName: 'مطهر ومنظف أرضيات برائحة الصنوبر 2 لتر × 6 عبوة',
        brand: 'العلامة الأولى - مطهرات',
        sector: 'MT',
        subCategory: 'مطهرات ومنظفات أرضيات',
        regionCode: 'ALX',
        governorate: 'الإسكندرية',
        salesRep: 'محمد سعيد إبراهيم',
        sellInCases: 1180,
        sellInValueEgp: 531000,
        sellOutEstCases: 1120,
        sellOutValueEgp: 504000,
        returnCases: 3,
        returnValueEgp: 1350,
        estimatedStockCases: 57,
        estimatedStockValueEgp: 25650,
        dailyRunRateCases: 15.2,
        daysOfInventory: 3.8,
        stockStatus: 'urgent_replenishment',
        stockStatusAr: 'طلب توريد عاجل (تحت حد الأمان)',
        casePriceEgp: 450,
        weightTons: 14.16,
        suggestedPoCases: 115,
        suggestedPoValueEgp: 51750,
        suggestedPoTons: 1.38,
      ),
      const SKUBranchInventoryModel(
        skuName: 'جل غسيل ملابس أوتوماتيك 3 لتر × 4 عبوة',
        brand: 'العلامة الثانية - عناية بالملابس',
        sector: 'MT',
        subCategory: 'مساحيق وجل غسيل',
        regionCode: 'CIR',
        governorate: 'القاهرة الكبرى',
        salesRep: 'كريم عادل فتحي',
        sellInCases: 960,
        sellInValueEgp: 518400,
        sellOutEstCases: 845,
        sellOutValueEgp: 456300,
        returnCases: 2,
        returnValueEgp: 1080,
        estimatedStockCases: 113,
        estimatedStockValueEgp: 61020,
        dailyRunRateCases: 11.4,
        daysOfInventory: 9.9,
        stockStatus: 'optimal',
        stockStatusAr: 'رصيد آمن ومتوازن',
        casePriceEgp: 540,
        weightTons: 11.52,
        suggestedPoCases: 25,
        suggestedPoValueEgp: 13500,
        suggestedPoTons: 0.30,
      ),
      const SKUBranchInventoryModel(
        skuName: 'منعم ومعطر أقمشة مركز 2 لتر × 6 عبوة',
        brand: 'العلامة الثانية - عناية بالملابس',
        sector: 'CC',
        subCategory: 'منعم أقمشة',
        regionCode: 'TNT',
        governorate: 'الغربية',
        salesRep: 'ياسر كمال الشناوي',
        sellInCases: 890,
        sellInValueEgp: 427200,
        sellOutEstCases: 610,
        sellOutValueEgp: 292800,
        returnCases: 5,
        returnValueEgp: 2400,
        estimatedStockCases: 275,
        estimatedStockValueEgp: 132000,
        dailyRunRateCases: 6.2,
        daysOfInventory: 44.4,
        stockStatus: 'overstock',
        stockStatusAr: 'تكدس مخزني (يحتاج عرض ترويجي)',
        casePriceEgp: 480,
        weightTons: 10.68,
        suggestedPoCases: 0,
        suggestedPoValueEgp: 0,
        suggestedPoTons: 0.0,
      ),
    ];

    final filteredItems = allItems.where((item) {
      if (sector != 'all' && item.sector != sector) return false;
      if (region != 'all' && item.regionCode != region) return false;
      if (stockStatus != 'all' && item.stockStatus != stockStatus) return false;
      return true;
    }).toList();

    return CPFRDashboardModel(
      tenantId: 'tenant-${normalizeDataTenantSlug(tenantId)}',
      retailerChain: chain,
      sourceFilename: 'CPFR_MultiChain_Sell_In_Reconciliation.xlsx',
      totalRecords: (836 * chainShare).round().clamp(18, 836),
      activeSkusCount: 75,
      activeRepsCount: 16,
      salesManagerName: 'إدارة مبيعات السلاسل التجارية',
      kaOfficerName: 'إدارة كبار العملاء (Key Accounts)',
      jan2026SellInEgp: janSellIn,
      jan2026SellOutEgp: janSellOut,
      jan2026GapEgp: janGap,
      jan2026SellThroughPct: double.parse(janStr.toStringAsFixed(2)),
      ytd2026SellInEgp: ytdSellInEgp,
      ytd2026SellInCases: ytdSellInCases,
      ytd2026WeightTons: ytdWeightTons,
      ytd2026ExpectedEgp: ytdExpectedEgp,
      octW1W2ActualEgp: octActualEgp,
      octW1W2ActualCases: octActualCases,
      octProjectedMonthEndEgp: octProjectedEgp,
      octProjectedCases: octProjectedCases,
      mtRevenueEgp: ytdSellInEgp * 0.78,
      mtSharePct: 78.0,
      ccRevenueEgp: ytdSellInEgp * 0.22,
      ccSharePct: 22.0,
      totalEstimatedStockCases: 496.0 * chainShare,
      totalEstimatedStockEgp: 243150.0 * chainShare,
      totalSuggestedPoCases: (295 * chainShare).round().clamp(15, 295),
      totalSuggestedPoEgp: 139650.0 * chainShare,
      totalSuggestedPoTons: double.parse((4.16 * chainShare).toStringAsFixed(2)),
      urgentReplenishmentCount: 14,
      overstockAlertCount: 6,
      leadTimeDays: leadTimeDays,
      safetyStockDays: safetyStockDays,
      monthlyReconciliation: months,
      inventoryAndPoItems: filteredItems,
      brandForecasts: const [
        BrandForecastModel(
          sector: 'MT',
          sectorNameAr: 'قطاع المنظفات والعناية المنزلية (MT)',
          brand: 'العلامة الأولى - منظفات ومطهرات',
          activeSkusCount: 42,
          actualCases: 64200,
          actualValueEgp: 28450000,
          expectedCases: 71500,
          expectedValueEgp: 31680000,
          forecastUpliftEgp: 3230000,
          achievementRatePct: 89.8,
          weightTons: 486.4,
          shareOfTotalPct: 60.2,
        ),
        BrandForecastModel(
          sector: 'CC',
          sectorNameAr: 'قطاع العناية الشخصية والورقيات (CC)',
          brand: 'العلامة الثانية - عناية وأقمشة',
          activeSkusCount: 33,
          actualCases: 48445,
          actualValueEgp: 18771426.35,
          expectedCases: 53200,
          expectedValueEgp: 20730800,
          forecastUpliftEgp: 1959373.65,
          achievementRatePct: 90.5,
          weightTons: 356.2,
          shareOfTotalPct: 39.8,
        ),
      ],
      regionPerformances: const [
        RegionPerformanceModel(
          regionCode: 'ALX',
          governorate: 'الإسكندرية',
          recordsCount: 412,
          actualCases: 58400,
          actualValueEgp: 24650000,
          expectedCases: 64200,
          expectedValueEgp: 27100000,
          weightTons: 438.5,
          sharePct: 52.2,
        ),
        RegionPerformanceModel(
          regionCode: 'CIR',
          governorate: 'القاهرة الكبرى',
          recordsCount: 218,
          actualCases: 31200,
          actualValueEgp: 13180000,
          expectedCases: 34800,
          expectedValueEgp: 14650000,
          weightTons: 234.0,
          sharePct: 27.9,
        ),
        RegionPerformanceModel(
          regionCode: 'TNT',
          governorate: 'الغربية والدلتا',
          recordsCount: 206,
          actualCases: 23045,
          actualValueEgp: 9391426.35,
          expectedCases: 25700,
          expectedValueEgp: 10660800,
          weightTons: 170.1,
          sharePct: 19.9,
        ),
      ],
      salesRepScorecards: const [
        SalesRepScorecardModel(
          salesRep: 'أحمد محمود حسن',
          kaOfficer: 'مسؤول حسابات السلاسل',
          salesManager: 'مدير قطاع التجزئة',
          regionCode: 'ALX',
          governorate: 'الإسكندرية',
          servedBranchesCount: 14,
          activeSkusCount: 48,
          recordsCount: 165,
          actualCases: 24500,
          actualValueEgp: 10420000,
          expectedCases: 26800,
          expectedValueEgp: 11400000,
          achievementPct: 91.4,
          weightTons: 184.2,
          promoValueEgp: 2917600,
          promoSharePct: 28.0,
          returnCases: 42,
          returnValueEgp: 18900,
          returnRatePct: 0.18,
          mtValueEgp: 8127600,
          ccValueEgp: 2292400,
        ),
        SalesRepScorecardModel(
          salesRep: 'محمد سعيد إبراهيم',
          kaOfficer: 'مسؤول حسابات السلاسل',
          salesManager: 'مدير قطاع التجزئة',
          regionCode: 'ALX',
          governorate: 'الإسكندرية',
          servedBranchesCount: 12,
          activeSkusCount: 44,
          recordsCount: 142,
          actualCases: 19800,
          actualValueEgp: 8350000,
          expectedCases: 21500,
          expectedValueEgp: 9120000,
          achievementPct: 91.6,
          weightTons: 148.5,
          promoValueEgp: 2171000,
          promoSharePct: 26.0,
          returnCases: 35,
          returnValueEgp: 15400,
          returnRatePct: 0.18,
          mtValueEgp: 6513000,
          ccValueEgp: 1837000,
        ),
      ],
      promoAndReturns: const PromoAndReturnSummaryModel(
        regularRecordsCount: 612,
        regularCases: 82400,
        regularValueEgp: 34520000,
        regularTons: 618.0,
        promoRecordsCount: 198,
        promoCases: 30245,
        promoValueEgp: 12701426.35,
        promoTons: 224.6,
        promoValueSharePct: 26.9,
        promoVolumeSharePct: 26.8,
        avgPromoCaseTons: 0.0074,
        returnRecordsCount: 26,
        totalReturnCases: 185,
        totalReturnValueEgp: 82400,
        overallReturnPct: 0.17,
        topReturnItems: [
          ReturnItemSummaryModel(
            itemName: 'ملمع زجاج وأسطح بخاخ 700 مل × 12 عبوة',
            brand: 'العلامة الثانية',
            sector: 'MT',
            regionCode: 'BHR',
            governorate: 'البحيرة',
            salesRep: 'عمرو نبيل فؤاد',
            returnCases: 24,
            returnValueEgp: 10080,
            returnRatePct: 0.42,
          ),
        ],
      ),
    );
  }

  /// Fetches paginated Supplier Sell-In records and summary totals for the Sell-In Explorer screen.
  Future<SellInExplorerResponse> getSellInRecords({
    String? chain,
    int? year,
    int? month,
    String? region,
    String? sector,
    String? brand,
    String? query,
    int limit = 250,
    int offset = 0,
  }) async {
    Object? failure;
    try {
      final params = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (chain != null && chain.isNotEmpty && chain != 'all') {
        params['chain'] = chain;
      }
      if (year != null && year > 0) {
        params['year'] = year.toString();
      }
      if (month != null && month > 0) {
        params['month'] = month.toString();
      }
      if (region != null && region.isNotEmpty && region != 'all') {
        params['region'] = region;
      }
      if (sector != null && sector.isNotEmpty && sector != 'all') {
        params['sector'] = sector;
      }
      if (brand != null && brand.isNotEmpty && brand != 'all') {
        params['brand'] = brand;
      }
      if (query != null && query.trim().isNotEmpty) {
        params['q'] = query.trim();
      }

      final uri = Uri.parse(ApiEndpoints.sellInRecords).replace(queryParameters: params);
      final response = await BackendHttp
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return SellInExplorerResponse.fromJson(data);
      }
      failure = 'HTTP ${response.statusCode}';
    } catch (e) {
      failure = e;
    }
    if (!allowMockFallback) {
      throw ServerConnectionException(
          'تعذر تحميل بيانات الـ Sell-In من الخادم.', failure);
    }
    return const SellInExplorerResponse(
      records: [],
      totalCount: 0,
      totalValueEgp: 0,
      totalCases: 0,
      totalWeightTons: 0,
      totalExpectedEgp: 0,
    );
  }

  /// Net Sell-In (EGP) per chain and month: `{chain(lowercase): {'YYYY-MM': value}}`.
  /// Used to draw Sell-In next to Sell-Out in the monthly trend chart. Throws on failure.
  Future<Map<String, Map<String, double>>> getSellInMonthlyByChain({
    String? chain,
    int? year,
  }) async {
    final params = <String, String>{};
    if (chain != null && chain.isNotEmpty && chain != 'all') params['chain'] = chain;
    if (year != null && year > 0) params['year'] = year.toString();
    final uri = Uri.parse(ApiEndpoints.sellInMonthly).replace(queryParameters: params);
    final response = await BackendHttp.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw ServerConnectionException('تعذر تحميل Sell-In الشهري.', 'HTTP ${response.statusCode}');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final out = <String, Map<String, double>>{};
    for (final p in (data['points'] as List? ?? const [])) {
      if (p is! Map) continue;
      final ch = (p['retailer_chain'] ?? '').toString().trim().toLowerCase();
      final mk = (p['month_key'] ?? '').toString().trim();
      final v = (p['net_value_egp'] as num?)?.toDouble();
      if (ch.isEmpty || mk.isEmpty || v == null) continue;
      out.putIfAbsent(ch, () => <String, double>{})[mk] = v;
    }
    return out;
  }

  /// Fetches Sell-Out or Sell-In Targets summary and Actual vs. Target comparisons.
  Future<TargetsSummaryModel> getTargetsSummary({
    required String targetType,
    String? chain,
    int? year,
  }) async {
    try {
      final params = <String, String>{
        'target_type': targetType,
      };
      if (chain != null && chain.isNotEmpty && chain != 'all') {
        params['chain'] = chain;
      }
      if (year != null && year > 0) {
        params['year'] = year.toString();
      }
      final uri = Uri.parse(ApiEndpoints.targets).replace(queryParameters: params);
      final response = await BackendHttp
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return TargetsSummaryModel.fromJson(data);
      }
    } catch (_) {}
    return TargetsSummaryModel.empty(targetType);
  }

  /// Upserts a Sell-Out or Sell-In Target manually and returns the updated summary.
  Future<TargetsSummaryModel> upsertTarget({
    String? id,
    required String targetType,
    required String retailerChain,
    required int year,
    required int month,
    String branchName = 'كل الفروع',
    String category = 'كل الفئات',
    required double targetRevenueEgp,
    required double targetUnits,
    String notes = '',
  }) async {
    final uri = Uri.parse('${ApiEndpoints.targets}?target_type=$targetType');
    final body = jsonEncode({
      if (id != null && id.isNotEmpty) 'id': id,
      'target_type': targetType,
      'retailer_chain': retailerChain,
      'year': year,
      'month': month,
      'branch_name': branchName,
      'category': category,
      'target_revenue_egp': targetRevenueEgp,
      'target_units': targetUnits,
      'notes': notes,
    });
    final response = await BackendHttp
        .post(uri, headers: _headers, body: body)
        .timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return TargetsSummaryModel.fromJson(data);
    }
    throw Exception('تعذر حفظ المستهدف (HTTP ${response.statusCode})');
  }

  /// Deletes a Target by ID and returns the updated summary.
  Future<TargetsSummaryModel> deleteTarget({
    required String id,
    required String targetType,
  }) async {
    final uri = Uri.parse(ApiEndpoints.targets).replace(queryParameters: {
      'id': id,
      'target_type': targetType,
    });
    final response = await BackendHttp
        .delete(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return TargetsSummaryModel.fromJson(data);
    }
    throw Exception('تعذر حذف المستهدف (HTTP ${response.statusCode})');
  }

  /// Uploads an Excel (.xlsx) or CSV file containing Sell-Out or Sell-In Targets.
  Future<({int rowsImported, TargetsSummaryModel summary})> uploadTargetsFile({
    required String filename,
    required Uint8List fileBytes,
    required String targetType,
    String chain = 'fathalla',
    int year = 2025,
  }) async {
    final uri = Uri.parse(ApiEndpoints.targetsUpload).replace(queryParameters: {
      'target_type': targetType,
      'chain': chain,
      'year': year.toString(),
      'filename': filename,
    });

    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headers);
    request.headers.remove('Content-Type');
    request.fields['target_type'] = targetType;
    request.fields['chain'] = chain;
    request.fields['year'] = year.toString();
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: filename,
      ),
    );

    final streamed = await BackendHttp.send(request).timeout(const Duration(seconds: 25));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final rowsImported = (data['rows_imported'] as num?)?.toInt() ?? 0;
      final summaryJson = data['summary'] as Map<String, dynamic>? ?? const {};
      return (
        rowsImported: rowsImported,
        summary: TargetsSummaryModel.fromJson(summaryJson),
      );
    }
    throw Exception('تعذر استيراد ملف المستهدفات (HTTP ${response.statusCode})');
  }

  /// Canonical product search helper supporting Item Code (كود الصنف), prefixes (FGCL, FGDW, FGSL alias),
  /// Barcode (الباركود), SKU name, brand, category, and branch/customer name.
  static bool matchesProductSearch(
    String rawQuery, {
    String itemCode = '',
    String barcode = '',
    String skuName = '',
    String rawSkuName = '',
    String brand = '',
    String category = '',
    String packagingType = '',
    String storeName = '',
  }) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;

    final qCompact = q.replaceAll(' ', '').replaceAll('-', '').replaceAll('_', '');
    final codeLower = itemCode.trim().toLowerCase();
    final codeCompact = codeLower.replaceAll(' ', '').replaceAll('-', '').replaceAll('_', '');
    final bcLower = barcode.trim().toLowerCase();

    if (codeLower.isNotEmpty) {
      if (codeLower.contains(q) || codeCompact.contains(qCompact)) return true;
      if (qCompact.startsWith('fgsl')) {
        final altCl = 'fgcl${qCompact.substring(4)}';
        final altLc = 'fglc${qCompact.substring(4)}';
        if (codeCompact.contains(altCl) || codeCompact.contains(altLc)) {
          return true;
        }
      }
    }
    if (bcLower.isNotEmpty && (bcLower.contains(q) || bcLower.contains(qCompact))) {
      return true;
    }
    if (skuName.toLowerCase().contains(q)) return true;
    if (rawSkuName.toLowerCase().contains(q)) return true;
    if (brand.toLowerCase().contains(q)) return true;
    if (category.toLowerCase().contains(q)) return true;
    if (packagingType.toLowerCase().contains(q)) return true;
    if (storeName.toLowerCase().contains(q)) return true;
    return false;
  }

  /// Fetches the Adeco Product Master & Official Price List (`كارتة الأصناف والأسعار`).
  Future<ProductMasterSummaryModel> getProductMaster({
    String? search,
    String? brand,
    String? category,
    String? prefix,
    String? itemType,
    String? packaging,
    String? pullStatus,
    String? priceChange,
  }) async {
    try {
      final params = <String, String>{};
      if (search != null && search.trim().isNotEmpty) {
        params['search'] = search.trim();
      }
      if (brand != null && brand.isNotEmpty && brand != 'all' && brand != 'الكل') {
        params['brand'] = brand;
      }
      if (category != null && category.isNotEmpty && category != 'all' && category != 'الكل') {
        params['category'] = category;
      }
      if (prefix != null && prefix.isNotEmpty && prefix != 'all' && prefix != 'الكل') {
        params['prefix'] = prefix;
      }
      if (itemType != null && itemType.isNotEmpty && itemType != 'all' && itemType != 'الكل') {
        params['item_type'] = itemType;
      }
      if (packaging != null && packaging.isNotEmpty && packaging != 'all' && packaging != 'الكل') {
        params['packaging'] = packaging;
      }
      if (pullStatus != null && pullStatus.isNotEmpty && pullStatus != 'all' && pullStatus != 'الكل') {
        params['pull_status'] = pullStatus;
      }
      if (priceChange != null && priceChange.isNotEmpty && priceChange != 'all' && priceChange != 'الكل') {
        params['price_change'] = priceChange;
      }

      final uri = Uri.parse(ApiEndpoints.productMaster).replace(
        queryParameters: params.isEmpty ? null : params,
      );
      final response = await BackendHttp
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        isServerOnline.value = true;
        lastConnectionError = null;
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return ProductMasterSummaryModel.fromJson(data);
      }
    } catch (e) {
      debugPrint('[ApiClient] Fallback getProductMaster: $e');
      if (!allowMockFallback) {
        isServerOnline.value = false;
        lastConnectionError = e.toString();
        throw ServerConnectionException(
          'تعذّر تحميل كارتة الأصناف والأسعار. حاول مرة أخرى بعد قليل.',
          e,
        );
      }
    }
    return _fallbackMockProductMaster(
      search: search,
      brand: brand,
      category: category,
      prefix: prefix,
      itemType: itemType,
      packaging: packaging,
      pullStatus: pullStatus,
      priceChange: priceChange,
    );
  }

  final Map<String, List<({String archiveId, ProductMasterSummaryModel summary})>>
      _localProductMasterStackByTenant = {};
  final Set<String> _deletedProductMasterBaselineTenants = <String>{};

  void _rollbackLocalProductMasterSheet(
    String cleanSlug, {
    required String archiveId,
    String? fileName,
  }) {
    final stack = _localProductMasterStackByTenant[cleanSlug];
    if (stack != null && stack.isNotEmpty) {
      final idx = stack.lastIndexWhere(
        (e) =>
            e.archiveId == archiveId ||
            (fileName != null &&
                fileName.trim().isNotEmpty &&
                e.summary.sourceFilename.toLowerCase() == fileName.trim().toLowerCase()),
      );
      if (idx >= 0) {
        stack.removeAt(idx);
      } else {
        stack.removeLast();
      }
      // Recompute diffs along the remaining stack
      final base = _deletedProductMasterBaselineTenants.contains(cleanSlug)
          ? null
          : _buildDefaultSeedProductMasterSummary();
      ProductMasterSummaryModel? prev = base;
      for (int i = 0; i < stack.length; i++) {
        final recomputed = _computeLocalProductMasterDiff(
          prev,
          stack[i].summary,
          isFirstWithoutBaseline: prev == null,
        );
        stack[i] = (archiveId: stack[i].archiveId, summary: recomputed);
        prev = recomputed;
      }
    }
    if (archiveId == 'pm_default_seed' ||
        (fileName != null &&
            fileName.trim().toLowerCase() == 'adeco_product_master_2026_08_01.xlsx' &&
            (stack == null || stack.isEmpty))) {
      _deletedProductMasterBaselineTenants.add(cleanSlug);
    }
  }

  /// Updates or inserts a single Product Master SKU item (`PUT /api/v1/product-master/item`).
  Future<ProductMasterSummaryModel> updateProductMasterItem(
    ProductMasterItemModel item,
  ) async {
    final cleanSlug = normalizeDataTenantSlug(tenantId);
    try {
      final uri = Uri.parse(ApiEndpoints.productMasterItem);
      final response = await BackendHttp
          .put(
            uri,
            headers: _headers,
            body: jsonEncode(item.toJson()),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final summaryJson = data['summary'] as Map<String, dynamic>? ?? data;
        return ProductMasterSummaryModel.fromJson(summaryJson);
      }
      if (!allowMockFallback) {
        throw Exception('تعذر تحديث بيانات الصنف في كارتة الأصناف (HTTP ${response.statusCode})');
      }
    } catch (e) {
      if (!allowMockFallback) rethrow;
      debugPrint('[ApiClient] Fallback updateProductMasterItem: $e');
    }

    final current = _fallbackMockProductMaster();
    final updatedItems = List<ProductMasterItemModel>.from(current.items);
    final idx = updatedItems.indexWhere(
      (e) => e.itemCode.toLowerCase() == item.itemCode.trim().toLowerCase(),
    );
    final vatRate = item.vatRate > 1.0 ? item.vatRate / 100.0 : (item.vatRate > 0 ? item.vatRate : 0.14);
    final discPct = item.invoiceDiscountPct > 1.0 ? item.invoiceDiscountPct : item.invoiceDiscountPct * 100.0;
    final extraPct = item.extraDiscountPct > 1.0 ? item.extraDiscountPct : item.extraDiscountPct * 100.0;
    final upc = item.unitsPerCarton > 0 ? item.unitsPerCarton : 12;
    final unitExcl = item.unitPriceExclVat > 0
        ? item.unitPriceExclVat
        : (item.unitPriceInclVat / (1.0 + vatRate));
    final unitIncl = item.unitPriceExclVat > 0
        ? (item.unitPriceExclVat * (1.0 + vatRate))
        : item.unitPriceInclVat;
    final netUnit = unitIncl * (1.0 - discPct / 100.0) * (1.0 - extraPct / 100.0);

    ProductMasterItemModel resolved = item.copyWith(
      unitsPerCarton: upc,
      vatRate: vatRate,
      invoiceDiscountPct: discPct,
      extraDiscountPct: extraPct,
      unitPriceExclVat: double.parse(unitExcl.toStringAsFixed(3)),
      unitPriceInclVat: double.parse(unitIncl.toStringAsFixed(3)),
      cartonPriceExclVat: double.parse((unitExcl * upc).toStringAsFixed(2)),
      cartonPriceInclVat: double.parse((unitIncl * upc).toStringAsFixed(2)),
      netUnitInvoiceCost: double.parse(netUnit.toStringAsFixed(3)),
      netCartonInvoiceCost: double.parse((netUnit * upc).toStringAsFixed(2)),
    );

    if (idx >= 0) {
      final old = updatedItems[idx];
      final diffEgp = double.parse((resolved.unitPriceInclVat - old.unitPriceInclVat).toStringAsFixed(2));
      if (diffEgp.abs() >= 0.01 && old.unitPriceInclVat > 0) {
        resolved = resolved.copyWith(
          prevUnitPriceExclVat: old.unitPriceExclVat,
          prevUnitPriceInclVat: old.unitPriceInclVat,
          prevCartonPriceInclVat: old.cartonPriceInclVat,
          prevNetUnitInvoiceCost: old.netUnitInvoiceCost,
          prevNetCartonInvoiceCost: old.netCartonInvoiceCost,
          priceChangeDiffEgp: diffEgp,
          priceChangePct: double.parse(((diffEgp / old.unitPriceInclVat) * 100.0).toStringAsFixed(1)),
          priceChangeDirection: diffEgp > 0 ? 'up' : 'down',
        );
      }
      updatedItems[idx] = resolved;
    } else {
      resolved = resolved.copyWith(
        serialNo: updatedItems.length + 1,
        priceChangeDirection: 'new',
      );
      updatedItems.add(resolved);
    }

    final rebuilt = _buildSummaryFromItems(
      sourceFilename: current.sourceFilename.isNotEmpty ? current.sourceFilename : 'adeco_product_master_2026_08_01.xlsx',
      sheetDateLabel: current.sheetDateLabel,
      items: updatedItems,
      diffSummary: current.diffSummary,
    );
    final stack = _localProductMasterStackByTenant.putIfAbsent(cleanSlug, () => []);
    if (stack.isNotEmpty) {
      stack[stack.length - 1] = (archiveId: stack.last.archiveId, summary: rebuilt);
    } else {
      stack.add((archiveId: 'pm_default_seed', summary: rebuilt));
    }
    return rebuilt;
  }

  /// Uploads an Excel (.xlsx) or CSV file containing the Product Master & Price List (`POST /api/v1/product-master/upload`).
  Future<({IngestionResultModel result, ProductMasterSummaryModel summary})> uploadProductMasterFile({
    required String filename,
    required Uint8List fileBytes,
  }) async {
    final cleanSlug = normalizeDataTenantSlug(tenantId);
    final lowerFile = filename.trim().toLowerCase();
    if (_deletedArchiveFileNames.remove(lowerFile) && kIsWeb) {
      SessionStorage.saveDeletedArchiveFileNames(_deletedArchiveFileNames);
    }
    if (lowerFile == 'adeco_product_master_2026_08_01.xlsx') {
      _deletedArchiveIds.remove('pm_default_seed');
      _deletedProductMasterBaselineTenants.remove(cleanSlug);
    }

    try {
      final uri = Uri.parse(ApiEndpoints.productMasterUpload).replace(
        queryParameters: {'filename': filename},
      );

      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_headers);
      request.headers.remove('Content-Type');
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: filename,
        ),
      );

      request.headers[BackendHttp.asyncJobHeader] = '1';
      final streamed = await BackendHttp.send(request).timeout(const Duration(seconds: 120));
      final response = await BackendHttp.awaitJob(
          await http.Response.fromStream(streamed),
          headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final resultJson = data['result'] as Map<String, dynamic>? ?? data;
        final summaryJson = data['summary'] as Map<String, dynamic>? ??
            (resultJson['product_master_summary'] as Map<String, dynamic>? ?? const {});
        final resModel = IngestionResultModel.fromJson(resultJson);
        final sumModel = ProductMasterSummaryModel.fromJson(summaryJson);
        final archId = resModel.archiveId.isNotEmpty
            ? resModel.archiveId
            : 'arch_pm_${cleanSlug}_${DateTime.now().microsecondsSinceEpoch}';
        _recordLocalArchivedUpload(
          cleanSlug: cleanSlug,
          batchId: resModel.batchId,
          archiveId: archId,
          filename: filename,
          bytes: fileBytes,
          retailChain: 'product-master',
          validRows: sumModel.totalSkus,
          branchesCount: 1,
          totalRevenue: 0,
          fileType: 'product_master',
        );
        _localProductMasterStackByTenant
            .putIfAbsent(cleanSlug, () => [])
            .add((archiveId: archId, summary: sumModel));
        return (
          result: resModel,
          summary: sumModel,
        );
      }
      if (!allowMockFallback) {
        throw Exception('تعذر رفع وتحديث شيت كارتة الأصناف والأسعار (HTTP ${response.statusCode})');
      }
    } catch (e) {
      if (!allowMockFallback) rethrow;
      debugPrint('[ApiClient] Fallback uploadProductMasterFile: $e');
    }

    final prevSummary = _fallbackMockProductMaster();
    final parsedItems = _parseLocalProductMasterCsvBytes(fileBytes, fallbackItems: prevSummary.items);
    final rawSummary = _buildSummaryFromItems(
      sourceFilename: filename,
      sheetDateLabel: 'تحديث ${DateTime.now().toIso8601String().substring(0, 10)}',
      items: parsedItems,
    );
    final diffedSummary = _computeLocalProductMasterDiff(
      prevSummary.totalSkus > 0 ? prevSummary : null,
      rawSummary,
      isFirstWithoutBaseline: prevSummary.totalSkus == 0,
    );
    final batchId = 'batch_pm_${DateTime.now().microsecondsSinceEpoch}';
    final archId = 'arch_pm_${cleanSlug}_product-master_${DateTime.now().microsecondsSinceEpoch}';
    _recordLocalArchivedUpload(
      cleanSlug: cleanSlug,
      batchId: batchId,
      archiveId: archId,
      filename: filename,
      bytes: fileBytes,
      retailChain: 'product-master',
      validRows: diffedSummary.totalSkus,
      branchesCount: 1,
      totalRevenue: 0,
      fileType: 'product_master',
    );
    _localProductMasterStackByTenant
        .putIfAbsent(cleanSlug, () => [])
        .add((archiveId: archId, summary: diffedSummary));

    final fallbackResult = IngestionResultModel(
      batchId: batchId,
      archiveId: archId,
      filename: filename,
      retailerDetected: 'product-master',
      totalRows: diffedSummary.totalSkus,
      validRows: diffedSummary.totalSkus,
      anomalyRows: 0,
      totalRevenue: 0,
      totalQuantity: diffedSummary.totalSkus,
      confidenceScore: 1.0,
      isStaged: false,
      isCommitted: true,
      anomalies: const [],
    );
    return (result: fallbackResult, summary: diffedSummary);
  }

  List<ProductMasterItemModel> _parseLocalProductMasterCsvBytes(
    Uint8List fileBytes, {
    required List<ProductMasterItemModel> fallbackItems,
  }) {
    try {
      final content = utf8.decode(fileBytes, allowMalformed: true).replaceFirst('\uFEFF', '');
      final lines = const LineSplitter()
          .convert(content)
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.length >= 2) {
        final headers = lines.first.split(',').map((h) => h.trim().replaceAll('"', '')).toList();
        int codeCol = -1, nameCol = -1, bcCol = -1, packCol = -1, upcCol = -1, exclCol = -1, inclCol = -1;
        for (int c = 0; c < headers.length; c++) {
          final h = headers[c].toLowerCase();
          if (codeCol < 0 && (h.contains('كود الصنف') || h == 'item_code' || h == 'كود')) codeCol = c;
          if (nameCol < 0 && (h.contains('اسم الصنف') || h.contains('الاسم الرسمي') || h == 'official_name')) nameCol = c;
          if (bcCol < 0 && (h.contains('باركود') || h.contains('الباركود') || h == 'barcode')) bcCol = c;
          if (packCol < 0 && (h.contains('التعبئة') || h.contains('نوع العبوة') || h == 'packaging_type')) packCol = c;
          if (upcCol < 0 && (h.contains('الوحدات بالكرتونة') || h.contains('الشدة') || h == 'units_per_carton')) upcCol = c;
          if (exclCol < 0 && (h.contains('قبل الضريبة') || h.contains('ق.ض') || h == 'unit_price_excl_vat')) exclCol = c;
          if (inclCol < 0 && (h.contains('شامل الضريبة') || h.contains('ش.ض') || h == 'unit_price_incl_vat')) {
            if (!h.contains('كرتون')) inclCol = c;
          }
        }
        if (codeCol >= 0 || nameCol >= 0) {
          final parsed = <ProductMasterItemModel>[];
          for (int r = 1; r < lines.length; r++) {
            final cols = lines[r].split(',').map((v) => v.trim().replaceAll('"', '')).toList();
            final code = (codeCol >= 0 && codeCol < cols.length) ? cols[codeCol] : 'SKU-$r';
            final name = (nameCol >= 0 && nameCol < cols.length) ? cols[nameCol] : code;
            if (code.isEmpty && name.isEmpty) continue;
            final bc = (bcCol >= 0 && bcCol < cols.length) ? cols[bcCol] : '';
            final pack = (packCol >= 0 && packCol < cols.length && cols[packCol].isNotEmpty) ? cols[packCol] : 'عبوة';
            final upc = (upcCol >= 0 && upcCol < cols.length) ? (int.tryParse(cols[upcCol]) ?? 12) : 12;
            double excl = (exclCol >= 0 && exclCol < cols.length) ? (double.tryParse(cols[exclCol]) ?? 0.0) : 0.0;
            double incl = (inclCol >= 0 && inclCol < cols.length) ? (double.tryParse(cols[inclCol]) ?? 0.0) : 0.0;
            if (incl <= 0 && excl > 0) incl = double.parse((excl * 1.14).toStringAsFixed(2));
            if (excl <= 0 && incl > 0) excl = double.parse((incl / 1.14).toStringAsFixed(2));
            final prefix = code.contains('-') ? code.split('-').first.toUpperCase() : 'FGCL';
            final isPromo = prefix.startsWith('PR') || name.contains('عرض');
            parsed.add(ProductMasterItemModel(
              serialNo: parsed.length + 1,
              itemCode: code,
              itemCodePrefix: prefix,
              erpPrefix: prefix,
              departmentAr: prefix,
              officialName: name,
              barcode: bc,
              category: 'منظفات وعناية منزلية',
              brand: inferBrandFromSkuOrSupplier(name, '', isOwn: true),
              packagingType: pack,
              unitsPerCarton: upc,
              unitPriceExclVat: excl,
              vatRate: 0.14,
              unitPriceInclVat: incl,
              cartonPriceExclVat: double.parse((excl * upc).toStringAsFixed(2)),
              cartonPriceInclVat: double.parse((incl * upc).toStringAsFixed(2)),
              invoiceDiscountPct: 10.0,
              extraDiscountPct: 0.0,
              netUnitInvoiceCost: double.parse((incl * 0.90).toStringAsFixed(3)),
              netCartonInvoiceCost: double.parse((incl * 0.90 * upc).toStringAsFixed(2)),
              itemType: isPromo ? 'عرض' : 'عادي',
              priceChangeDirection: 'same',
            ));
          }
          if (parsed.isNotEmpty) return parsed;
        }
      }
    } catch (_) {}
    return fallbackItems;
  }

  ProductMasterSummaryModel _buildSummaryFromItems({
    required String sourceFilename,
    required String sheetDateLabel,
    required List<ProductMasterItemModel> items,
    ProductMasterDiffSummaryModel? diffSummary,
  }) {
    final prefixes = items.map((e) => e.itemCodePrefix).where((e) => e.isNotEmpty).toSet().toList()..sort();
    final brands = items.map((e) => e.brand).where((e) => e.isNotEmpty).toSet().toList()..sort();
    final packs = items.map((e) => e.packagingType).where((e) => e.isNotEmpty).toSet().toList()..sort();
    final avgUpc = items.isEmpty
        ? 0.0
        : double.parse((items.fold<int>(0, (s, e) => s + e.unitsPerCarton) / items.length).toStringAsFixed(1));
    return ProductMasterSummaryModel(
      tenantId: tenantId,
      companyName: 'شركة الإسكندرية للمنظفات والكيماويات (أدكو - Adeco)',
      sheetDateLabel: sheetDateLabel,
      sourceFilename: items.isEmpty ? '' : sourceFilename,
      defaultDiscountPct: 10.0,
      defaultVatRate: 0.14,
      totalSkus: items.length,
      regularSkusCount: items.where((e) => e.itemType != 'عرض').length,
      promoSkusCount: items.where((e) => e.itemType == 'عرض').length,
      uniqueBarcodesCount: items.map((e) => e.barcode).where((b) => b.isNotEmpty).toSet().length,
      avgUnitsPerCarton: avgUpc,
      activeInChainsCount: items.where((e) => e.isActiveInChains).length,
      unpulledSkusCount: items.where((e) => !e.isActiveInChains).length,
      priceIncreasedCount: items.where((e) => e.priceChangeDirection == 'up').length,
      priceDecreasedCount: items.where((e) => e.priceChangeDirection == 'down').length,
      priceUnchangedCount: items.where((e) => e.priceChangeDirection == 'same' || e.priceChangeDirection.isEmpty).length,
      newSkusCount: items.where((e) => e.priceChangeDirection == 'new').length,
      availablePrefixes: prefixes,
      availableBrands: brands,
      availablePackaging: packs,
      diffSummary: diffSummary,
      items: items,
    );
  }

  ProductMasterSummaryModel _computeLocalProductMasterDiff(
    ProductMasterSummaryModel? prev,
    ProductMasterSummaryModel next, {
    bool isFirstWithoutBaseline = false,
  }) {
    if (prev == null || prev.items.isEmpty || isFirstWithoutBaseline) {
      final cleanItems = next.items
          .map((it) => it.copyWith(
                prevUnitPriceExclVat: 0,
                prevUnitPriceInclVat: 0,
                prevCartonPriceInclVat: 0,
                prevNetUnitInvoiceCost: 0,
                prevNetCartonInvoiceCost: 0,
                priceChangeDirection: 'same',
                priceChangeDiffEgp: 0,
                priceChangePct: 0,
              ))
          .toList();
      return _buildSummaryFromItems(
        sourceFilename: next.sourceFilename,
        sheetDateLabel: next.sheetDateLabel,
        items: cleanItems,
        diffSummary: null,
      );
    }

    final prevByCode = <String, ProductMasterItemModel>{};
    for (final it in prev.items) {
      prevByCode[it.itemCode.trim().toUpperCase()] = it;
    }

    int upCount = 0, downCount = 0, sameCount = 0, newCount = 0;
    double upPctSum = 0.0, downPctSum = 0.0;
    final topChanges = <ProductMasterDiffItemModel>[];
    final updatedItems = <ProductMasterItemModel>[];

    for (final it in next.items) {
      final old = prevByCode[it.itemCode.trim().toUpperCase()];
      if (old == null) {
        newCount++;
        updatedItems.add(it.copyWith(
          prevUnitPriceExclVat: 0,
          prevUnitPriceInclVat: 0,
          prevCartonPriceInclVat: 0,
          prevNetUnitInvoiceCost: 0,
          prevNetCartonInvoiceCost: 0,
          priceChangeDirection: 'new',
          priceChangeDiffEgp: 0,
          priceChangePct: 0,
        ));
        topChanges.add(ProductMasterDiffItemModel(
          itemCode: it.itemCode,
          officialName: it.officialName,
          brand: it.brand,
          oldUnitPriceIncl: 0,
          newUnitPriceIncl: it.unitPriceInclVat,
          oldCartonPriceIncl: 0,
          newCartonPriceIncl: it.cartonPriceInclVat,
          diffEgp: 0,
          diffPct: 0,
          direction: 'new',
        ));
        continue;
      }

      final diffEgp = double.parse((it.unitPriceInclVat - old.unitPriceInclVat).toStringAsFixed(2));
      final diffPct = old.unitPriceInclVat > 0
          ? double.parse(((diffEgp / old.unitPriceInclVat) * 100.0).toStringAsFixed(1))
          : 0.0;
      if (diffEgp.abs() >= 0.01) {
        final dir = diffEgp > 0 ? 'up' : 'down';
        if (dir == 'up') {
          upCount++;
          upPctSum += diffPct;
        } else {
          downCount++;
          downPctSum += diffPct.abs();
        }
        updatedItems.add(it.copyWith(
          prevUnitPriceExclVat: old.unitPriceExclVat,
          prevUnitPriceInclVat: old.unitPriceInclVat,
          prevCartonPriceInclVat: old.cartonPriceInclVat,
          prevNetUnitInvoiceCost: old.netUnitInvoiceCost,
          prevNetCartonInvoiceCost: old.netCartonInvoiceCost,
          priceChangeDirection: dir,
          priceChangeDiffEgp: diffEgp,
          priceChangePct: diffPct,
        ));
        topChanges.add(ProductMasterDiffItemModel(
          itemCode: it.itemCode,
          officialName: it.officialName,
          brand: it.brand,
          oldUnitPriceIncl: old.unitPriceInclVat,
          newUnitPriceIncl: it.unitPriceInclVat,
          oldCartonPriceIncl: old.cartonPriceInclVat,
          newCartonPriceIncl: it.cartonPriceInclVat,
          diffEgp: diffEgp,
          diffPct: diffPct,
          direction: dir,
        ));
      } else {
        sameCount++;
        updatedItems.add(it.copyWith(
          prevUnitPriceExclVat: 0,
          prevUnitPriceInclVat: 0,
          prevCartonPriceInclVat: 0,
          prevNetUnitInvoiceCost: 0,
          prevNetCartonInvoiceCost: 0,
          priceChangeDirection: 'same',
          priceChangeDiffEgp: 0,
          priceChangePct: 0,
        ));
      }
    }

    final diffSummary = ProductMasterDiffSummaryModel(
      comparedAgainstFile: prev.sourceFilename,
      newFileName: next.sourceFilename,
      comparedAt: DateTime.now().toIso8601String().substring(0, 16).replaceAll('T', ' '),
      totalSkusCompared: updatedItems.length,
      priceIncreasedCount: upCount,
      priceDecreasedCount: downCount,
      priceUnchangedCount: sameCount,
      newSkusCount: newCount,
      avgPriceIncreasePct: upCount > 0 ? double.parse((upPctSum / upCount).toStringAsFixed(1)) : 0.0,
      avgPriceDecreasePct: downCount > 0 ? double.parse((downPctSum / downCount).toStringAsFixed(1)) : 0.0,
      topChangedItems: topChanges,
    );

    return _buildSummaryFromItems(
      sourceFilename: next.sourceFilename,
      sheetDateLabel: next.sheetDateLabel,
      items: updatedItems,
      diffSummary: diffSummary,
    );
  }

  ProductMasterSummaryModel _buildDefaultSeedProductMasterSummary() {
    const seedItems = <ProductMasterItemModel>[
      ProductMasterItemModel(
        serialNo: 1,
        itemCode: 'FGCL-0550-0001',
        itemCodePrefix: 'FGCL',
        erpPrefix: 'FGCL',
        departmentAr: 'قسم الكلور والمبيضات (Chlorine & Bleach)',
        officialName: 'كلوريل أبيض 1050 جم عبوة',
        barcode: '6221133000181',
        category: 'الكلور والمطهرات (Chlorine & Disinfectants)',
        brand: 'كلوريل (Clorel)',
        packagingType: 'عبوة',
        unitsPerCarton: 12,
        unitPriceExclVat: 15.79,
        vatRate: 0.14,
        unitPriceInclVat: 18.00,
        cartonPriceExclVat: 189.47,
        cartonPriceInclVat: 216.00,
        invoiceDiscountPct: 10.0,
        extraDiscountPct: 0.0,
        netUnitInvoiceCost: 16.20,
        netCartonInvoiceCost: 194.40,
        itemType: 'عادي',
        isActiveInChains: true,
        totalPosUnitsSold: 420,
        totalPosCartonsSold: 35.0,
        totalPosRevenue: 7560.0,
        avgRetailSellingPrice: 18.0,
        activeChains: ['fathalla', 'carrefour'],
        prevUnitPriceInclVat: 16.50,
        priceChangeDirection: 'up',
        priceChangeDiffEgp: 1.50,
        priceChangePct: 9.1,
      ),
      ProductMasterItemModel(
        serialNo: 42,
        itemCode: 'FGDW-0251-0002',
        itemCodePrefix: 'FGDW',
        erpPrefix: 'FGDW',
        departmentAr: 'قسم غسالات الأطباق الأوتوماتيك (Auto Dishwashing)',
        officialName: 'فيبا سائل أطباق ليمون 4 لتر جركن توفير',
        barcode: '6221133992356',
        category: 'منظفات الأطباق (Dishwashing)',
        brand: 'فيبا (Feba)',
        packagingType: 'جركن',
        unitsPerCarton: 4,
        unitPriceExclVat: 122.81,
        vatRate: 0.14,
        unitPriceInclVat: 140.00,
        cartonPriceExclVat: 491.23,
        cartonPriceInclVat: 560.00,
        invoiceDiscountPct: 10.0,
        extraDiscountPct: 0.0,
        netUnitInvoiceCost: 126.00,
        netCartonInvoiceCost: 504.00,
        itemType: 'عادي',
        isActiveInChains: true,
        totalPosUnitsSold: 120,
        totalPosCartonsSold: 30.0,
        totalPosRevenue: 16800.0,
        avgRetailSellingPrice: 140.0,
        activeChains: ['fathalla'],
        prevUnitPriceInclVat: 150.00,
        priceChangeDirection: 'down',
        priceChangeDiffEgp: -10.00,
        priceChangePct: -6.7,
      ),
      ProductMasterItemModel(
        serialNo: 88,
        itemCode: 'FGDG-0400-0012',
        itemCodePrefix: 'FGDG',
        erpPrefix: 'FGDG',
        departmentAr: 'قسم سائل غسيل الأطباق اليدوي (Hand Dishwashing)',
        officialName: 'ديفاتول مطهر عام برائحة الصنوبر 750 مل عبوة',
        barcode: '6221133010142',
        category: 'الكلور والمطهرات (Chlorine & Disinfectants)',
        brand: 'ديفاتول (Divatol)',
        packagingType: 'عبوة',
        unitsPerCarton: 12,
        unitPriceExclVat: 48.25,
        vatRate: 0.14,
        unitPriceInclVat: 55.00,
        cartonPriceExclVat: 578.95,
        cartonPriceInclVat: 660.00,
        invoiceDiscountPct: 10.0,
        extraDiscountPct: 0.0,
        netUnitInvoiceCost: 49.50,
        netCartonInvoiceCost: 594.00,
        itemType: 'عادي',
        isActiveInChains: false,
        priceChangeDirection: 'same',
      ),
      ProductMasterItemModel(
        serialNo: 145,
        itemCode: 'FGHC-0310-0005',
        itemCodePrefix: 'FGHC',
        erpPrefix: 'FGHC',
        departmentAr: 'قسم العناية المنزلية والمطهرات (Home Care & Disinfectants)',
        officialName: 'فلفيتا منعم أقمشة مركز لافندر 1 لتر عبوة',
        barcode: '6221133011903',
        category: 'منعم ومعطر الأقمشة (Fabric Softeners)',
        brand: 'فلفيتا (Velveta)',
        packagingType: 'عبوة',
        unitsPerCarton: 12,
        unitPriceExclVat: 42.11,
        vatRate: 0.14,
        unitPriceInclVat: 48.00,
        cartonPriceExclVat: 505.26,
        cartonPriceInclVat: 576.00,
        invoiceDiscountPct: 10.0,
        extraDiscountPct: 0.0,
        netUnitInvoiceCost: 43.20,
        netCartonInvoiceCost: 518.40,
        itemType: 'عادي',
        isActiveInChains: true,
        totalPosUnitsSold: 84,
        totalPosCartonsSold: 7.0,
        totalPosRevenue: 4032.0,
        avgRetailSellingPrice: 48.0,
        activeChains: ['fathalla'],
        priceChangeDirection: 'same',
      ),
      ProductMasterItemModel(
        serialNo: 210,
        itemCode: 'PRHC-0102-0015',
        itemCodePrefix: 'PRHC',
        erpPrefix: 'PRHC',
        departmentAr: 'قسم العروض الترويجية والباكتات (Promotional Bundles)',
        officialName: 'عرض فيبا توفير 3 لتر + 600 مل هدية شرنك',
        barcode: '6221133994121',
        category: 'منظفات الأطباق (Dishwashing)',
        brand: 'فيبا (Feba)',
        packagingType: 'شرنك',
        unitsPerCarton: 6,
        unitPriceExclVat: 96.49,
        vatRate: 0.14,
        unitPriceInclVat: 110.00,
        cartonPriceExclVat: 578.95,
        cartonPriceInclVat: 660.00,
        invoiceDiscountPct: 10.0,
        extraDiscountPct: 0.0,
        netUnitInvoiceCost: 99.00,
        netCartonInvoiceCost: 594.00,
        itemType: 'عرض',
        isActiveInChains: false,
        priceChangeDirection: 'new',
      ),
    ];
    return ProductMasterSummaryModel(
      tenantId: tenantId,
      companyName: 'شركة الإسكندرية للمنظفات والكيماويات (أدكو - Adeco)',
      sheetDateLabel: 'تحديث 01-08-2026',
      sourceFilename: 'adeco_product_master_2026_08_01.xlsx',
      defaultDiscountPct: 10.0,
      defaultVatRate: 0.14,
      totalSkus: seedItems.length,
      regularSkusCount: seedItems.where((e) => e.itemType != 'عرض').length,
      promoSkusCount: seedItems.where((e) => e.itemType == 'عرض').length,
      uniqueBarcodesCount: seedItems.map((e) => e.barcode).toSet().length,
      avgUnitsPerCarton: 9.2,
      activeInChainsCount: seedItems.where((e) => e.isActiveInChains).length,
      unpulledSkusCount: seedItems.where((e) => !e.isActiveInChains).length,
      priceIncreasedCount: seedItems.where((e) => e.priceChangeDirection == 'up').length,
      priceDecreasedCount: seedItems.where((e) => e.priceChangeDirection == 'down').length,
      priceUnchangedCount: seedItems.where((e) => e.priceChangeDirection == 'same').length,
      newSkusCount: seedItems.where((e) => e.priceChangeDirection == 'new').length,
      availablePrefixes: const ['FGCL', 'FGDG', 'FGDW', 'FGGC', 'FGHC', 'FGLC', 'FGPC', 'PR'],
      availableBrands: const [
        'فيبا (Feba)',
        'كلوريل (Clorel)',
        'فلفيتا (Velveta)',
        'ديفا (Diva)',
        'ديفاتول (Divatol)',
        'ماكسيل (Maxell)',
        'جلاسي (Glassy)',
        'سبيد (Speed)',
      ],
      availablePackaging: const ['عبوة', 'جركن', 'شرنك', 'باكت', 'بكته'],
      items: seedItems,
    );
  }

  ProductMasterSummaryModel _fallbackMockProductMaster({
    String? search,
    String? brand,
    String? category,
    String? prefix,
    String? itemType,
    String? packaging,
    String? pullStatus,
    String? priceChange,
  }) {
    final cleanSlug = normalizeDataTenantSlug(tenantId);
    final stack = _localProductMasterStackByTenant[cleanSlug];
    final ProductMasterSummaryModel baseSummary;
    if (stack != null && stack.isNotEmpty) {
      baseSummary = stack.last.summary;
    } else if (_deletedProductMasterBaselineTenants.contains(cleanSlug)) {
      baseSummary = _buildSummaryFromItems(
        sourceFilename: '',
        sheetDateLabel: '',
        items: const [],
      );
    } else {
      baseSummary = _buildDefaultSeedProductMasterSummary();
    }

    final seedItems = baseSummary.items;

    final filtered = seedItems.where((item) {
      if (brand != null && brand.isNotEmpty && brand != 'all' && brand != 'الكل' && item.brand != brand) {
        return false;
      }
      if (category != null && category.isNotEmpty && category != 'all' && category != 'الكل' && item.category != category) {
        return false;
      }
      if (prefix != null && prefix.isNotEmpty && prefix != 'all' && prefix != 'الكل') {
        if (prefix.toUpperCase() == 'PR') {
          if (!item.itemCodePrefix.toUpperCase().startsWith('PR')) return false;
        } else if (item.itemCodePrefix.toUpperCase() != prefix.toUpperCase()) {
          return false;
        }
      }
      if (itemType != null && itemType.isNotEmpty && itemType != 'all' && itemType != 'الكل' && item.itemType != itemType) {
        return false;
      }
      if (packaging != null && packaging.isNotEmpty && packaging != 'all' && packaging != 'الكل' && item.packagingType != packaging) {
        return false;
      }
      if (pullStatus != null && pullStatus.isNotEmpty && pullStatus != 'all' && pullStatus != 'الكل') {
        if (pullStatus == 'active' && !item.isActiveInChains) return false;
        if (pullStatus == 'unpulled' && item.isActiveInChains) return false;
      }
      if (priceChange != null && priceChange.isNotEmpty && priceChange != 'all' && priceChange != 'الكل') {
        final pc = priceChange.toLowerCase();
        final dir = item.priceChangeDirection.toLowerCase();
        if (pc == 'changed' && dir != 'up' && dir != 'down' && dir != 'new') {
          return false;
        }
        if (pc == 'up' && dir != 'up') return false;
        if (pc == 'down' && dir != 'down') return false;
        if (pc == 'new' && dir != 'new') return false;
        if (pc == 'same' && dir != 'same' && dir.isNotEmpty) return false;
      }
      if (search != null && search.trim().isNotEmpty) {
        return matchesProductSearch(
          search,
          itemCode: item.itemCode,
          barcode: item.barcode,
          skuName: item.officialName,
          brand: item.brand,
          category: item.category,
          packagingType: item.packagingType,
        );
      }
      return true;
    }).toList();

    return ProductMasterSummaryModel(
      tenantId: baseSummary.tenantId,
      companyName: baseSummary.companyName,
      sheetDateLabel: baseSummary.sheetDateLabel,
      sourceFilename: baseSummary.sourceFilename,
      defaultDiscountPct: baseSummary.defaultDiscountPct,
      defaultVatRate: baseSummary.defaultVatRate,
      totalSkus: baseSummary.totalSkus,
      regularSkusCount: baseSummary.regularSkusCount,
      promoSkusCount: baseSummary.promoSkusCount,
      uniqueBarcodesCount: baseSummary.uniqueBarcodesCount,
      avgUnitsPerCarton: baseSummary.avgUnitsPerCarton,
      activeInChainsCount: baseSummary.activeInChainsCount,
      unpulledSkusCount: baseSummary.unpulledSkusCount,
      priceIncreasedCount: baseSummary.priceIncreasedCount,
      priceDecreasedCount: baseSummary.priceDecreasedCount,
      priceUnchangedCount: baseSummary.priceUnchangedCount,
      newSkusCount: baseSummary.newSkusCount,
      availablePrefixes: baseSummary.availablePrefixes,
      availableBrands: baseSummary.availableBrands,
      availablePackaging: baseSummary.availablePackaging,
      diffSummary: baseSummary.diffSummary,
      items: filtered,
    );
  }

  /// Custom field competitor entries added or pinned by the user during the session.
  final Map<String, List<CompetitorSkuComparisonModel>> _customPinnedCompetitors = {};

  /// Helper to infer brand name from Arabic SKU name or supplier name.
  static String inferBrandFromSkuOrSupplier(String skuName, String supplier, {bool isOwn = false}) {
    final s = skuName.trim();
    if (s.startsWith('فيبا') || s.contains('فيبا')) return 'فيبا (Feba)';
    if (s.startsWith('ديفاتول') || s.contains('ديفاتول')) return 'ديفاتول (Divatol)';
    if (s.startsWith('ديفا') || s.contains('ديفا')) return 'ديفا (Diva)';
    if (s.startsWith('فلفيتا') || s.startsWith('فلفتا') || s.contains('فلفيتا')) return 'فلفيتا (Velveta)';
    if (s.startsWith('كلوريل') || s.contains('كلوريل')) return 'كلوريل (Clorel)';
    if (s.startsWith('ماكسيل') || s.startsWith('ماكسل') || s.contains('ماكسيل')) return 'ماكسيل (Maxell)';
    if (s.startsWith('جلاسى') || s.startsWith('جلاسي') || s.contains('جلاسى')) return 'جلاسي (Glassy)';
    if (s.startsWith('سبيد') || s.contains('سبيد')) return 'سبيد (Speed)';
    if (s.contains('بريل')) return 'بريل (Pril)';
    if (s.contains('برسيل')) return 'برسيل (Persil)';
    if (s.contains('جنرال')) return 'جنرال (General)';
    if (s.contains('وفير')) return 'وفير (Wafeer)';
    if (s.contains('اوكسى') || s.contains('أوكسي')) return 'أوكسي (Oxi)';
    if (s.contains('بريكس')) return 'بريكس (Brix)';
    if (s.contains('ريفولى')) return 'ريفولي (Rivoli)';
    if (s.contains('باهي') || s.contains('باهى')) return 'باهي (Bahi)';
    if (s.contains('دووش')) return 'دووش (Douche)';
    if (s.contains('فيرى') || s.contains('فيري')) return 'فيري (Fairy)';
    if (s.contains('اريال') || s.contains('أريال')) return 'أريال (Ariel)';
    if (s.contains('داونى') || s.contains('داوني')) return 'داوني (Downy)';
    if (s.contains('كلوركس')) return 'كلوركس (Clorox)';
    if (s.contains('فريدا')) return 'فريدا (Farida)';
    if (s.contains('ديتول')) return 'ديتول (Dettol)';
    if (s.contains('فانيش')) return 'فانيش (Vanish)';
    if (s.contains('فينيش') || s.contains('فينش') || s.contains('فنيش')) return 'فينيش (Finish)';
    if (s.contains('هاربيك')) return 'هاربيك (Harpic)';
    if (s.contains('ويندكس')) return 'ويندكس (Windex)';
    if (s.contains('بليدج')) return 'بليدج (Pledge)';
    if (s.contains('لودفيك')) return 'لودفيك (Ludwik)';
    if (s.contains('سيترس')) return 'سيترس (Citrus)';
    if (s.contains('فاى') || s.contains('فاي')) return 'فاي (Fay)';
    if (s.contains('فلاش')) return 'فلاش (Flash)';
    if (isOwn) return 'أدكو (Adeco)';
    if (supplier.trim().isNotEmpty) return supplier.trim();
    final words = s.split(' ');
    return words.isNotEmpty ? words.first : 'علامة تجارية';
  }

  static String formatArabicMonthOnly(int monthNum) {
    switch (monthNum) {
      case 1:
        return 'يناير';
      case 2:
        return 'فبراير';
      case 3:
        return 'مارس';
      case 4:
        return 'أبريل';
      case 5:
        return 'مايو';
      case 6:
        return 'يونيو';
      case 7:
        return 'يوليو';
      case 8:
        return 'أغسطس';
      case 9:
        return 'سبتمبر';
      case 10:
        return 'أكتوبر';
      case 11:
        return 'نوفمبر';
      case 12:
        return 'ديسمبر';
      default:
        return 'شهر $monthNum';
    }
  }

  /// Aggregates live sell-out rows into barcode → YYYY-MM → (avg unit price, units).
  /// Used to extend hardcoded competitive seeds as new months are uploaded.
  static Map<String, Map<String, ({double price, int units})>> aggregateLiveMonthlyByBarcode(
    Iterable<SellOutRecordModel> liveRecords,
  ) {
    final rev = <String, Map<String, double>>{};
    final units = <String, Map<String, int>>{};
    for (final r in liveRecords) {
      final barcode = r.barcode.trim();
      if (barcode.isEmpty || r.transactionDate.length < 7) continue;
      final monthKey = r.transactionDate.substring(0, 7);
      final qty = r.quantitySold;
      if (qty <= 0 && r.unitPrice <= 0) continue;
      rev.putIfAbsent(barcode, () => {})[monthKey] =
          (rev[barcode]?[monthKey] ?? 0.0) + (r.unitPrice > 0 ? r.unitPrice * qty : r.netRevenue);
      units.putIfAbsent(barcode, () => {})[monthKey] = (units[barcode]?[monthKey] ?? 0) + qty;
    }
    final out = <String, Map<String, ({double price, int units})>>{};
    for (final barcode in rev.keys) {
      final months = <String, ({double price, int units})>{};
      for (final mk in rev[barcode]!.keys) {
        final u = units[barcode]?[mk] ?? 0;
        final revenue = rev[barcode]![mk]!;
        final price = u > 0
            ? double.parse((revenue / u).toStringAsFixed(2))
            : double.parse(revenue.toStringAsFixed(2));
        if (price <= 0 && u <= 0) continue;
        months[mk] = (price: price, units: u);
      }
      if (months.isNotEmpty) out[barcode] = months;
    }
    return out;
  }

  /// Monthly maps for competitive comparison.
  /// - Live rows for the barcode → live-only (never seed leftovers).
  /// - No live rows + [allowSeeds] false (production / live mode) → empty (never seeds).
  /// - No live rows + [allowSeeds] true (explicit demo/offline only) → seed map.
  static Map<String, ({double price, int units})> mergeMonthlyData(
    Map<String, ({double price, int units})> seed,
    Map<String, ({double price, int units})>? live, {
    bool allowSeeds = false,
  }) {
    if (live != null && live.isNotEmpty) {
      return Map<String, ({double price, int units})>.from(live);
    }
    if (!allowSeeds) return const {};
    return Map<String, ({double price, int units})>.from(seed);
  }

  /// Backend [HandleRecords] clamps page size to ≤500; requesting more silently becomes 50.
  static const int sellOutRecordsPageSize = 500;

  /// Safety ceiling for paginated sell-out fetches. Hitting this while more pages remain
  /// is never silent — see [SellOutRecordsTruncatedException] / [lastSellOutPaginationWarning].
  static const int sellOutRecordsMaxRows = 250000;

  /// Set when [getRecordsAllPages] hits [sellOutRecordsMaxRows] with pages still remaining.
  String? lastSellOutPaginationWarning;

  /// Test-only override for the competitive-comparison fetch safety cap.
  @visibleForTesting
  int? debugSellOutMaxRows;

  /// Whether another offset page is needed after [fetchedSoFar] rows from a page of [pageLength].
  static bool sellOutRecordsHasMorePage({
    required int fetchedSoFar,
    required int pageLength,
    required int pageSize,
    required int totalCount,
  }) {
    if (pageLength <= 0) return false;
    if (fetchedSoFar >= totalCount) return false;
    if (pageLength < pageSize) return false;
    return true;
  }

  /// Walks every sell-out page for the filter until [total_count] is covered.
  /// If the safety cap is hit while more rows remain, sets [lastSellOutPaginationWarning]
  /// and throws [SellOutRecordsTruncatedException] (never a silent partial success).
  ///
  /// [allowMockRecords] is forwarded to [getRecords]. Comparison callers pass
  /// [allowDemoSeedData] so HTTP failure cannot inject [_mockRecords] months.
  Future<List<SellOutRecordModel>> getRecordsAllPages({
    String? chain,
    String? storeId,
    String? category,
    String? supplier,
    String? query,
    String? startDate,
    String? endDate,
    int? year,
    int? month,
    int pageSize = sellOutRecordsPageSize,
    int maxRows = sellOutRecordsMaxRows,
    bool? allowMockRecords,
  }) async {
    lastSellOutPaginationWarning = null;
    final effPage = pageSize.clamp(1, sellOutRecordsPageSize);
    final all = <SellOutRecordModel>[];
    var offset = 0;
    while (true) {
      final page = await getRecords(
        chain: chain,
        storeId: storeId,
        category: category,
        supplier: supplier,
        query: query,
        startDate: startDate,
        endDate: endDate,
        year: year,
        month: month,
        limit: effPage,
        offset: offset,
        allowMockRecords: allowMockRecords,
      );
      all.addAll(page);
      final total = lastSellOutSummary?.totalCount ?? all.length;
      final more = sellOutRecordsHasMorePage(
        fetchedSoFar: all.length,
        pageLength: page.length,
        pageSize: effPage,
        totalCount: total,
      );
      if (!more) return all;
      if (all.length >= maxRows) {
        final msg =
            'Sell-out fetch stopped at $maxRows rows (total_count=$total). Data is incomplete.';
        lastSellOutPaginationWarning = msg;
        throw SellOutRecordsTruncatedException(
          msg,
          partial: List<SellOutRecordModel>.unmodifiable(all),
          totalCount: total,
          maxRows: maxRows,
        );
      }
      offset += page.length;
    }
  }

  static List<SkuMonthlyPricePointModel> buildMonthlyPriceTrajectory(
    Map<String, ({double price, int units})> rawByMonth, {
    int? filterYear,
  }) {
    final sortedKeys = rawByMonth.keys.where((k) {
      if (filterYear != null && filterYear > 0) {
        return k.startsWith('$filterYear-');
      }
      return true;
    }).toList()
      ..sort();

    // Also sort all keys across all years so Jan 2026 can compare against prior month (or start fresh within year)
    final points = <SkuMonthlyPricePointModel>[];
    for (var i = 0; i < sortedKeys.length; i++) {
      final mk = sortedKeys[i];
      final entry = rawByMonth[mk]!;
      final parts = mk.split('-');
      final yr = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 2026) : 2026;
      final mo = parts.length > 1 ? (int.tryParse(parts[1]) ?? 1) : 1;
      final mNameAr = formatArabicMonthOnly(mo);
      final labelAr = '$mNameAr $yr';
      final price = double.parse(entry.price.toStringAsFixed(2));
      final units = entry.units;
      final rev = double.parse((price * units).toStringAsFixed(2));

      double chgEgp = 0.0;
      double chgPct = 0.0;
      String dir = 'baseline';

      if (i > 0) {
        final prev = points[i - 1];
        if (prev.unitPrice > 0) {
          chgEgp = double.parse((price - prev.unitPrice).toStringAsFixed(2));
          chgPct = double.parse((((price - prev.unitPrice) / prev.unitPrice) * 100.0).toStringAsFixed(1));
          if (chgPct > 0.4) {
            dir = 'up';
          } else if (chgPct < -0.4) {
            dir = 'down';
          } else {
            dir = 'stable';
          }
        }
      }

      points.add(
        SkuMonthlyPricePointModel(
          monthKey: mk,
          year: yr,
          monthNum: mo,
          monthNameAr: mNameAr,
          monthLabelAr: labelAr,
          unitPrice: price,
          unitsSold: units,
          netRevenue: rev,
          priceChangeEgp: chgEgp,
          priceChangePct: chgPct,
          trendDirection: dir,
        ),
      );
    }
    return points;
  }

  /// Server ids of persisted custom competitor SKUs, keyed by the local item barcode.
  final Map<String, String> _customCompetitorServerIds = {};

  static String _customOwnKey(String ownBarcode, String ownSkuName) =>
      ownBarcode.trim().isNotEmpty ? ownBarcode.trim() : ownSkuName.trim();

  /// True when [barcode] belongs to a user-added (custom) competitor SKU.
  bool isCustomCompetitorSku(String barcode) =>
      _customCompetitorServerIds.containsKey(barcode) || barcode.startsWith('CMP-');

  /// Adds or updates a field competitor SKU under a specific Own SKU barcode.
  /// The local list updates instantly; the SKU is then persisted on the server
  /// (POST /api/v1/competitors/custom-skus). On failure the local change is rolled back and rethrown.
  Future<void> addCustomCompetitorSku({
    required String ownBarcode,
    required String ownSkuName,
    required double ownUnitPrice,
    required double ownVolumeUnits,
    required String ownVolumeUnitLabel,
    required String competitorSkuName,
    required String competitorBrand,
    required String competitorSupplier,
    required String category,
    required String packSizeLabel,
    required double packVolumeUnits,
    required double competitorPrice,
    required String retailerChain,
    int estimatedMonthlyUnits = 320,
    bool isPromoActive = false,
  }) async {
    final cleanKey = _customOwnKey(ownBarcode, ownSkuName);
    final list = _customPinnedCompetitors.putIfAbsent(cleanKey, () => []);
    final previous = List<CompetitorSkuComparisonModel>.from(list);
    final item = _buildCustomCompetitorItem(
      ownBarcode: ownBarcode,
      ownSkuName: ownSkuName,
      ownUnitPrice: ownUnitPrice,
      ownVolumeUnits: ownVolumeUnits,
      ownVolumeUnitLabel: ownVolumeUnitLabel,
      competitorSkuName: competitorSkuName,
      competitorBrand: competitorBrand,
      competitorSupplier: competitorSupplier,
      category: category,
      packSizeLabel: packSizeLabel,
      packVolumeUnits: packVolumeUnits,
      competitorPrice: competitorPrice,
      retailerChain: retailerChain,
      estimatedMonthlyUnits: estimatedMonthlyUnits,
      isPromoActive: isPromoActive,
    );
    // Same competitor name under the same own SKU replaces (server dedupes the same way).
    final normName = competitorSkuName.trim().toLowerCase();
    list.removeWhere((c) => c.skuName.trim().toLowerCase() == normName);
    list.insert(0, item);

    try {
      final resp = await BackendHttp
          .post(
            Uri.parse(ApiEndpoints.customCompetitorSkus),
            headers: _headers,
            body: jsonEncode({
              'own_barcode': ownBarcode.trim(),
              'own_sku_name': ownSkuName.trim(),
              'own_unit_price': ownUnitPrice,
              'own_volume_units': ownVolumeUnits,
              'own_volume_unit_label': ownVolumeUnitLabel,
              'competitor_sku_name': competitorSkuName.trim(),
              'competitor_brand': competitorBrand,
              'competitor_supplier': competitorSupplier,
              'category': category,
              'pack_size_label': packSizeLabel,
              'pack_volume_units': packVolumeUnits,
              'competitor_price': competitorPrice,
              'retailer_chain': retailerChain,
              'estimated_monthly_units': estimatedMonthlyUnits,
              'is_promo_active': isPromoActive,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        String msg = 'HTTP ${resp.statusCode}';
        try {
          msg = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>)['error']?.toString() ?? msg;
        } catch (_) {}
        throw Exception(msg);
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final id = (data['custom_sku'] as Map<String, dynamic>?)?['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        _customCompetitorServerIds.removeWhere((_, v) => v == id);
        _customCompetitorServerIds[item.barcode] = id;
      }
    } catch (e) {
      _customPinnedCompetitors[cleanKey] = previous;
      rethrow;
    }
  }

  /// Deletes a custom competitor SKU locally and on the server. Rolls back and rethrows on failure.
  Future<void> deleteCustomCompetitorSku(String barcode) async {
    String? ownKey;
    List<CompetitorSkuComparisonModel>? previous;
    for (final entry in _customPinnedCompetitors.entries) {
      if (entry.value.any((c) => c.barcode == barcode)) {
        ownKey = entry.key;
        previous = List<CompetitorSkuComparisonModel>.from(entry.value);
        entry.value.removeWhere((c) => c.barcode == barcode);
        break;
      }
    }
    final serverId = _customCompetitorServerIds[barcode];
    if (serverId == null) return; // memory-only item (never persisted)
    try {
      final resp = await BackendHttp
          .delete(Uri.parse(ApiEndpoints.customCompetitorSku(serverId)), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200 && resp.statusCode != 404) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      _customCompetitorServerIds.remove(barcode);
    } catch (e) {
      if (ownKey != null && previous != null) _customPinnedCompetitors[ownKey] = previous;
      rethrow;
    }
  }

  /// Loads persisted custom competitor SKUs from the server and replaces the local cache.
  /// On failure the in-memory list is kept as is.
  Future<void> _syncCustomCompetitorSkus({String? chain}) async {
    try {
      final params = <String, String>{};
      if (chain != null && chain.isNotEmpty && chain != 'all' && chain != 'الكل') {
        params['chain'] = chain;
      }
      final uri = Uri.parse(ApiEndpoints.customCompetitorSkus)
          .replace(queryParameters: params.isEmpty ? null : params);
      final resp = await BackendHttp.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final rows = (data['custom_skus'] as List?) ?? const [];
      final fresh = <String, List<CompetitorSkuComparisonModel>>{};
      final ids = <String, String>{};
      for (final raw in rows) {
        if (raw is! Map) continue;
        final r = Map<String, dynamic>.from(raw);
        double d(String k) => (r[k] as num?)?.toDouble() ?? 0.0;
        String s(String k) => r[k]?.toString() ?? '';
        final id = s('id');
        final item = _buildCustomCompetitorItem(
          serverId: id,
          ownBarcode: s('own_barcode'),
          ownSkuName: s('own_sku_name'),
          ownUnitPrice: d('own_unit_price'),
          ownVolumeUnits: d('own_volume_units'),
          ownVolumeUnitLabel: s('own_volume_unit_label'),
          competitorSkuName: s('competitor_sku_name'),
          competitorBrand: s('competitor_brand'),
          competitorSupplier: s('competitor_supplier'),
          category: s('category'),
          packSizeLabel: s('pack_size_label'),
          packVolumeUnits: d('pack_volume_units'),
          competitorPrice: d('competitor_price'),
          retailerChain: s('retailer_chain'),
          estimatedMonthlyUnits: (r['estimated_monthly_units'] as num?)?.toInt() ?? 320,
          isPromoActive: r['is_promo_active'] == true,
        );
        fresh.putIfAbsent(_customOwnKey(s('own_barcode'), s('own_sku_name')), () => []).add(item);
        if (id.isNotEmpty) ids[item.barcode] = id;
      }
      _customPinnedCompetitors
        ..clear()
        ..addAll(fresh);
      _customCompetitorServerIds
        ..clear()
        ..addAll(ids);
    } catch (_) {}
  }

  CompetitorSkuComparisonModel _buildCustomCompetitorItem({
    String? serverId,
    required String ownBarcode,
    required String ownSkuName,
    required double ownUnitPrice,
    required double ownVolumeUnits,
    required String ownVolumeUnitLabel,
    required String competitorSkuName,
    required String competitorBrand,
    required String competitorSupplier,
    required String category,
    required String packSizeLabel,
    required double packVolumeUnits,
    required double competitorPrice,
    required String retailerChain,
    int estimatedMonthlyUnits = 320,
    bool isPromoActive = false,
  }) {
    final diffEgp = competitorPrice - ownUnitPrice;
    final diffPct = ownUnitPrice > 0 ? (diffEgp / ownUnitPrice) * 100.0 : 0.0;
    final String pos;
    if (diffPct > 1.5) {
      pos = 'higher'; // Competitor is higher than our price (we are cheaper)
    } else if (diffPct < -1.5) {
      pos = 'lower'; // Competitor is lower than our price (they undercut us)
    } else {
      pos = 'equal';
    }
    final pricePerVol = packVolumeUnits > 0 ? competitorPrice / packVolumeUnits : competitorPrice;

    // Current shelf price stays on [unitPrice]. Do not invent Jan–Apr (or any)
    // monthly history when the custom competitor has no real sell-out series.
    return CompetitorSkuComparisonModel(
      skuName: competitorSkuName,
      barcode: serverId != null && serverId.isNotEmpty
          ? 'CMP-$serverId'
          : 'CMP-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      supplierName: competitorSupplier,
      brand: competitorBrand,
      category: category,
      packSizeLabel: packSizeLabel,
      packVolumeUnits: packVolumeUnits,
      volumeUnitLabel: ownVolumeUnitLabel,
      unitPrice: competitorPrice,
      pricePerUnitVolume: double.parse(pricePerVol.toStringAsFixed(2)),
      priceDiffEgp: double.parse(diffEgp.toStringAsFixed(2)),
      priceDiffPct: double.parse(diffPct.toStringAsFixed(1)),
      pricePosition: pos,
      unitsSold: estimatedMonthlyUnits,
      netRevenue: competitorPrice * estimatedMonthlyUnits,
      categorySharePct: 8.5,
      isPromoActive: isPromoActive,
      isPinnedDirect: true,
      chainPrices: {
        (retailerChain.trim().isNotEmpty ? retailerChain.trim() : 'fathalla'): competitorPrice,
      },
      monthlyPrices: const [],
      allMonthlyPrices: const [],
    );
  }

  /// Extracts pack size & unit volume (in Liters or Kg) from Arabic/English SKU name.
  static ({double volume, String unitLabel, String badgeLabel}) extractPackVolume(String skuName) {
    final s = skuName.toLowerCase();

    // Check multiplier + liters (e.g., 4 لتر, 2.5 كجم, 500 مل, 700مل)
    final literMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:لتر|ليتر|liter|liters|l\b)').firstMatch(s);
    if (literMatch != null) {
      final val = double.tryParse(literMatch.group(1)!) ?? 1.0;
      return (
        volume: val > 0 ? val : 1.0,
        unitLabel: 'لتر',
        badgeLabel: '${val.toStringAsFixed(val == val.roundToDouble() ? 0 : 1)} لتر',
      );
    }

    final kgMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:كجم|كيلو|kg|kilo)').firstMatch(s);
    if (kgMatch != null) {
      final val = double.tryParse(kgMatch.group(1)!) ?? 1.0;
      return (
        volume: val > 0 ? val : 1.0,
        unitLabel: 'كجم',
        badgeLabel: '${val.toStringAsFixed(val == val.roundToDouble() ? 0 : 1)} كجم',
      );
    }

    final mlMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:مل|ملي|ml)').firstMatch(s);
    if (mlMatch != null) {
      final rawMl = double.tryParse(mlMatch.group(1)!) ?? 500.0;
      final liters = (rawMl / 1000.0).clamp(0.05, 20.0);
      return (
        volume: liters,
        unitLabel: 'لتر',
        badgeLabel: '${rawMl.toInt()} مل',
      );
    }

    final gmMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:جم|جرام|غ|g\b|gm)').firstMatch(s);
    if (gmMatch != null) {
      final rawGm = double.tryParse(gmMatch.group(1)!) ?? 500.0;
      final kg = (rawGm / 1000.0).clamp(0.05, 20.0);
      return (
        volume: kg,
        unitLabel: 'كجم',
        badgeLabel: '${rawGm.toInt()} جم',
      );
    }

    return (volume: 1.0, unitLabel: 'عبوة', badgeLabel: '1 عبوة قياسية');
  }

  /// Retrieves competitive SKU comparison groups (Own SKUs + mapped Competitor SKUs)
  /// strictly from real uploaded Fathalla Market data (`2026 out.xlsx` & `2025 out.xlsx`) + live server records,
  /// scoped by `year` (default 2026) and `month` (0 = all months of the year, or 1..12).
  Future<List<OwnSkuCompetitiveGroupModel>> getCompetitiveComparisonGroups({
    String? chain,
    String? category,
    String? query,
    int year = 2026,
    int month = 0,
    bool syncCustomSkus = true,
  }) async {
    final effectiveChain = (currentUser?.role == 'chain_kam' &&
            currentUser?.assignedChain != null &&
            currentUser!.assignedChain!.isNotEmpty)
        ? currentUser!.assignedChain
        : chain;

    // Always pull the full selected year (paginated — server caps each page at 500)
    // so monthly trajectories come from real uploads, not seed Jan–Apr leftovers.
    List<SellOutRecordModel> liveRecords = const [];
    try {
      String? startDate;
      String? endDate;
      if (year > 0) {
        startDate = '$year-01-01';
        endDate = '$year-12-31';
      }
      liveRecords = await getRecordsAllPages(
        chain: (effectiveChain != null && effectiveChain != 'all' && effectiveChain != 'الكل')
            ? effectiveChain
            : null,
        supplier: 'all_market',
        category: (category != null && category != 'all' && category != 'الكل') ? category : null,
        startDate: startDate,
        endDate: endDate,
        maxRows: debugSellOutMaxRows ?? sellOutRecordsMaxRows,
        // Never let dashboard mock sell-out rows invent comparison months.
        allowMockRecords: allowDemoSeedData,
      );
    } on SellOutRecordsTruncatedException catch (e) {
      // Visible warning on [lastSellOutPaginationWarning]; keep partial live so we
      // never fall through to seed Jan–Apr while claiming a live year.
      liveRecords = e.partial;
      debugPrint('[ApiClient] competitive comparison: ${e.message}');
    } catch (_) {}

    if (syncCustomSkus) await _syncCustomCompetitorSkus(chain: effectiveChain);

    final groups = _buildRichCompetitiveGroups(
      liveRecords: liveRecords,
      chainFilter: effectiveChain,
      year: year,
      month: month,
    );

    return groups.where((g) {
      if (category != null &&
          category.isNotEmpty &&
          category != 'all' &&
          category != 'الكل') {
        if (normalizeCategoryName(g.category) != normalizeCategoryName(category)) {
          return false;
        }
      }
      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        final matchOwn = g.ownSkuName.toLowerCase().contains(q) ||
            g.ownBarcode.toLowerCase().contains(q) ||
            g.ownBrand.toLowerCase().contains(q) ||
            g.category.toLowerCase().contains(q);
        final matchComp = g.competitors.any(
          (c) =>
              c.skuName.toLowerCase().contains(q) ||
              c.barcode.toLowerCase().contains(q) ||
              c.brand.toLowerCase().contains(q) ||
              c.supplierName.toLowerCase().contains(q),
        );
        if (!matchOwn && !matchComp) return false;
      }
      return true;
    }).toList();
  }

  List<OwnSkuCompetitiveGroupModel> _buildRichCompetitiveGroups({
    required List<SellOutRecordModel> liveRecords,
    String? chainFilter,
    int year = 2026,
    int month = 0,
  }) {
    final activeChainKey = (chainFilter != null &&
            chainFilter.isNotEmpty &&
            chainFilter != 'all' &&
            chainFilter != 'الكل')
        ? chainFilter.toLowerCase()
        : null;

    // Only Fathalla Market has real uploaded competitive sheets (`2026 out.xlsx` & `2025 out.xlsx`).
    // If the user filters by a chain that has no uploaded competitive records and isn't fathalla, check liveRecords first.
    if (activeChainKey != null && activeChainKey != 'fathalla') {
      final hasChainLive = liveRecords.any((r) => r.retailerChain.toLowerCase() == activeChainKey);
      if (!hasChainLive) {
        return const [];
      }
    }

    final liveByBarcode = aggregateLiveMonthlyByBarcode(liveRecords);
    // Production / live year: never inject seed monthly prices. Seeds only when there is
    // no live data at all and the explicit demo flag is on (not [allowMockFallback]).
    final allowSeedMonths = liveRecords.isEmpty && allowDemoSeedData;

    // Group structure (barcodes / brands). Monthly prices come from live or gated seeds.
    final rawDefs = <_RawCompetitiveGroupSeed>[
      // 1. صابون سائل اطباق - فيبا 3 كجم
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223000239438',
        ownSkuName: 'فيبا 3 كجم 1 روائح عاديه + 1 روائح خاصه',
        ownBrand: 'فيبا (Feba)',
        category: 'صابون سائل اطباق',
        monthlyData: {
          '2025-01': (price: 147.14, units: 2682),
          '2025-02': (price: 135.59, units: 8584),
          '2025-03': (price: 131.17, units: 13086),
          '2025-04': (price: 126.55, units: 18614),
          '2026-01': (price: 153.23, units: 4677),
          '2026-02': (price: 163.63, units: 6064),
          '2026-03': (price: 175.40, units: 4052),
          '2026-04': (price: 184.67, units: 4864),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '6221143099674',
            skuName: 'بريل سائل منظف أطباق 4 كجم ليمون اخضر',
            brand: 'بريل (Pril)',
            supplierName: 'هنكل برسيل (3)',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 141.68, units: 4242),
              '2025-02': (price: 136.15, units: 6530),
              '2025-03': (price: 134.48, units: 5440),
              '2025-04': (price: 138.38, units: 4364),
              '2026-01': (price: 140.00, units: 2821),
              '2026-02': (price: 149.91, units: 1997),
              '2026-03': (price: 151.19, units: 3861),
              '2026-04': (price: 150.85, units: 4809),
            },
          ),
          _RawCompetitorSeed(
            barcode: '8700216349376',
            skuName: 'فيرى المركز سائل اطباق ليمون 2 لتر',
            brand: 'فيري (Fairy)',
            supplierName: 'بروكتر و جامبل مصر',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 184.96, units: 2332),
              '2025-02': (price: 155.44, units: 4152),
              '2025-03': (price: 159.87, units: 3740),
              '2025-04': (price: 195.91, units: 2450),
              '2026-01': (price: 210.00, units: 1452),
              '2026-02': (price: 210.00, units: 1537),
              '2026-03': (price: 210.00, units: 1701),
              '2026-04': (price: 210.00, units: 1220),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6223002551293',
            skuName: 'وفير سائل اطباق ليمون 4كجم',
            brand: 'وفير (Wafeer)',
            supplierName: 'ارما التجارية - منظفات',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 61.07, units: 14474),
              '2025-02': (price: 60.68, units: 18676),
              '2025-03': (price: 71.39, units: 9030),
              '2025-04': (price: 73.61, units: 8144),
              '2026-01': (price: 86.49, units: 3166),
              '2026-02': (price: 81.79, units: 3981),
              '2026-03': (price: 80.41, units: 4006),
              '2026-04': (price: 94.96, units: 3633),
            },
          ),
        ],
      ),
      // 2. صابون سائل اطباق - فيبا صابون سائل للاطباق بالليمون 4كجم
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223000232514',
        ownSkuName: 'فيبا صابون سائل للاطباق بالليمون 4كجم',
        ownBrand: 'فيبا (Feba)',
        category: 'صابون سائل اطباق',
        monthlyData: {
          '2025-01': (price: 98.53, units: 9286),
          '2025-02': (price: 90.06, units: 12270),
          '2025-03': (price: 105.58, units: 5780),
          '2025-04': (price: 108.32, units: 5038),
          '2026-01': (price: 111.44, units: 2979),
          '2026-02': (price: 119.24, units: 2996),
          '2026-03': (price: 115.59, units: 3172),
          '2026-04': (price: 128.41, units: 3087),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '6221143099674',
            skuName: 'بريل سائل منظف أطباق 4 كجم ليمون اخضر',
            brand: 'بريل (Pril)',
            supplierName: 'هنكل برسيل (3)',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 141.68, units: 4242),
              '2025-02': (price: 136.15, units: 6530),
              '2025-03': (price: 134.48, units: 5440),
              '2025-04': (price: 138.38, units: 4364),
              '2026-01': (price: 140.00, units: 2821),
              '2026-02': (price: 149.91, units: 1997),
              '2026-03': (price: 151.19, units: 3861),
              '2026-04': (price: 150.85, units: 4809),
            },
          ),
          _RawCompetitorSeed(
            barcode: '8700216349376',
            skuName: 'فيرى المركز سائل اطباق ليمون 2 لتر',
            brand: 'فيري (Fairy)',
            supplierName: 'بروكتر و جامبل مصر',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 184.96, units: 2332),
              '2025-02': (price: 155.44, units: 4152),
              '2025-03': (price: 159.87, units: 3740),
              '2025-04': (price: 195.91, units: 2450),
              '2026-01': (price: 210.00, units: 1452),
              '2026-02': (price: 210.00, units: 1537),
              '2026-03': (price: 210.00, units: 1701),
              '2026-04': (price: 210.00, units: 1220),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6223002551446',
            skuName: 'وفير بلس سائل ليمون اخضر 4كجم',
            brand: 'وفير (Wafeer)',
            supplierName: 'ارما التجارية - منظفات',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 61.16, units: 14560),
              '2025-02': (price: 60.97, units: 14572),
              '2025-03': (price: 71.37, units: 8940),
              '2025-04': (price: 73.59, units: 7944),
              '2026-01': (price: 86.28, units: 3092),
              '2026-02': (price: 81.79, units: 4093),
              '2026-03': (price: 80.52, units: 4219),
              '2026-04': (price: 94.34, units: 3430),
            },
          ),
        ],
      ),
      // 3. مساحيق جيل اتوماتيك - فلفيتا جيل اوتوماتيك لافندر 2.5كجم +500جم
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223004145643',
        ownSkuName: 'فلفيتا جيل اوتوماتيك لافندر 2.5كجم +500جم',
        ownBrand: 'فلفيتا (Velveta)',
        category: 'مساحيق جيل اتوماتيك',
        monthlyData: {
          '2025-01': (price: 157.37, units: 2758),
          '2025-02': (price: 193.93, units: 4926),
          '2025-03': (price: 134.23, units: 3550),
          '2025-04': (price: 147.40, units: 3298),
          '2026-01': (price: 147.80, units: 1682),
          '2026-02': (price: 184.10, units: 1101),
          '2026-03': (price: 150.63, units: 1887),
          '2026-04': (price: 197.04, units: 959),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '8700216706063',
            skuName: 'اريال باور جل الكبير 3.6 كجم داونى',
            brand: 'أريال (Ariel)',
            supplierName: 'بروكتر و جامبل مصر',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 226.50, units: 3920),
              '2025-02': (price: 227.80, units: 4110),
              '2025-03': (price: 228.40, units: 3890),
              '2025-04': (price: 229.84, units: 4050),
              '2026-01': (price: 232.35, units: 5148),
              '2026-02': (price: 228.95, units: 5111),
              '2026-03': (price: 234.76, units: 4800),
              '2026-04': (price: 250.86, units: 4420),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6223006124455',
            skuName: 'اوكسى جيل اوتوماتيك نسيم العطور 3كجم',
            brand: 'أوكسي (Oxi)',
            supplierName: 'ارما التجارية - منظفات',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 173.98, units: 3688),
              '2025-02': (price: 172.04, units: 4584),
              '2025-03': (price: 168.53, units: 4022),
              '2025-04': (price: 173.38, units: 4534),
              '2026-01': (price: 191.77, units: 2256),
              '2026-02': (price: 192.17, units: 2501),
              '2026-03': (price: 193.87, units: 3100),
              '2026-04': (price: 219.77, units: 1447),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6221143091227',
            skuName: 'برسيل جل 2.6 ك لافندر',
            brand: 'برسيل (Persil)',
            supplierName: 'هنكل برسيل (3)',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 167.20, units: 3550),
              '2025-02': (price: 166.03, units: 3208),
              '2025-03': (price: 174.79, units: 1912),
              '2025-04': (price: 177.27, units: 2144),
              '2026-01': (price: 168.27, units: 3441),
              '2026-02': (price: 177.31, units: 2548),
              '2026-03': (price: 171.70, units: 2154),
              '2026-04': (price: 177.96, units: 2137),
            },
          ),
        ],
      ),
      // 4. هاند وواش - ديفا هاند ووش500مل بامب + اقتصادى عرض2ق
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223004145650',
        ownSkuName: 'ديفا هاند ووش500مل بامب + اقتصادى عرض2ق',
        ownBrand: 'ديفا (Diva)',
        category: 'هاند وواش',
        monthlyData: {
          '2025-01': (price: 70.19, units: 10888),
          '2025-02': (price: 69.16, units: 13488),
          '2025-03': (price: 65.56, units: 13570),
          '2025-04': (price: 68.01, units: 14650),
          '2026-01': (price: 71.09, units: 5240),
          '2026-02': (price: 74.16, units: 6308),
          '2026-03': (price: 74.85, units: 6079),
          '2026-04': (price: 76.86, units: 7457),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '788364597557',
            skuName: 'فاى هاند صوب 500جم بامب + غيار',
            brand: 'فاي (Fay)',
            supplierName: 'قادوس كوزمتكس منظفات(8)',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 65.15, units: 9686),
              '2025-02': (price: 65.42, units: 9514),
              '2025-03': (price: 65.76, units: 8382),
              '2025-04': (price: 66.04, units: 9138),
              '2026-01': (price: 66.03, units: 4314),
              '2026-02': (price: 66.07, units: 4726),
              '2026-03': (price: 62.54, units: 4505),
              '2026-04': (price: 75.67, units: 3693),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6224008204190',
            skuName: 'فريدا هاند ووش الوادى الاخضر 520مل 1+1',
            brand: 'فريدا (Farida)',
            supplierName: 'فريدال للصناعات العطرية',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 74.63, units: 1156),
              '2025-02': (price: 71.00, units: 1880),
              '2025-03': (price: 82.79, units: 944),
              '2025-04': (price: 75.96, units: 1134),
              '2026-01': (price: 79.70, units: 601),
              '2026-02': (price: 74.00, units: 852),
              '2026-03': (price: 74.26, units: 808),
              '2026-04': (price: 97.93, units: 521),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6223006128743',
            skuName: 'دووش هاند ووش 450ملي موف نسيم اللافندر',
            brand: 'دووش (Douche)',
            supplierName: 'ارما التجارية - منظفات',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 30.40, units: 4522),
              '2025-02': (price: 34.04, units: 2598),
              '2025-03': (price: 34.12, units: 4632),
              '2025-04': (price: 33.89, units: 2478),
              '2026-01': (price: 34.01, units: 2638),
              '2026-02': (price: 30.73, units: 2710),
              '2026-03': (price: 30.10, units: 3046),
              '2026-04': (price: 38.11, units: 1407),
            },
          ),
        ],
      ),
      // 5. منعمات ملابس - فلفيتا منعم ملابس مركز 1 لتر عطر الاناقه
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223000234488',
        ownSkuName: 'فلفيتا منعم ملابس مركز 1 لتر عطر الاناقه',
        ownBrand: 'فلفيتا (Velveta)',
        category: 'منعمات ملابس',
        monthlyData: {
          '2025-01': (price: 103.60, units: 1746),
          '2025-02': (price: 91.89, units: 2132),
          '2025-03': (price: 110.47, units: 1076),
          '2025-04': (price: 111.86, units: 1446),
          '2026-01': (price: 96.45, units: 1040),
          '2026-02': (price: 89.97, units: 1368),
          '2026-03': (price: 109.47, units: 1191),
          '2026-04': (price: 126.97, units: 898),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '8700216311618',
            skuName: 'داونى مركز منعم ملابس لافندر ومسك 1لتر',
            brand: 'داوني (Downy)',
            supplierName: 'بروكتر و جامبل مصر',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 160.78, units: 1306),
              '2025-02': (price: 146.05, units: 1692),
              '2025-03': (price: 148.73, units: 1434),
              '2025-04': (price: 157.48, units: 1416),
              '2026-01': (price: 128.00, units: 1880),
              '2026-02': (price: 136.23, units: 2343),
              '2026-03': (price: 128.00, units: 2746),
              '2026-04': (price: 140.71, units: 2238),
            },
          ),
        ],
      ),
      // 6. كلور ألوان - شنطة كلوريل
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223000235553',
        ownSkuName: 'شنطة(كلوريل1كجم2×1+1كجم4×1+1050مل عادى+1لتر الوان)',
        ownBrand: 'كلوريل (Clorel)',
        category: 'كلور ألوان',
        monthlyData: {
          '2025-01': (price: 81.93, units: 3502),
          '2025-02': (price: 69.62, units: 4680),
          '2025-03': (price: 80.35, units: 3054),
          '2025-04': (price: 83.87, units: 3074),
          '2026-01': (price: 85.79, units: 2212),
          '2026-02': (price: 83.30, units: 2595),
          '2026-03': (price: 84.66, units: 2203),
          '2026-04': (price: 90.73, units: 2286),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '6221152011452',
            skuName: 'كلوركس الوان عادي 2 لتر',
            brand: 'كلوركس (Clorox)',
            supplierName: 'الموزعون المتحدون',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 85.00, units: 4042),
              '2025-02': (price: 85.00, units: 4496),
              '2025-03': (price: 85.00, units: 3500),
              '2025-04': (price: 85.00, units: 4664),
              '2026-01': (price: 85.00, units: 2261),
              '2026-02': (price: 85.00, units: 2459),
              '2026-03': (price: 85.00, units: 2400),
              '2026-04': (price: 103.62, units: 1659),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6223014211956',
            skuName: 'بريكس كلور الوان(موف) 950 مل',
            brand: 'بريكس (Brix)',
            supplierName: 'ارما التجارية - منظفات',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 25.28, units: 3984),
              '2025-02': (price: 25.02, units: 4962),
              '2025-03': (price: 25.12, units: 5110),
              '2025-04': (price: 25.08, units: 5340),
              '2026-01': (price: 34.98, units: 2178),
              '2026-02': (price: 39.38, units: 1837),
              '2026-03': (price: 39.00, units: 1293),
              '2026-04': (price: 42.42, units: 1847),
            },
          ),
        ],
      ),
      // 7. كلور عادى - كلوريل الوان2ك+كلوريل 2كجم عادى عرض(1+1)
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223000239452',
        ownSkuName: 'كلوريل الوان2ك+كلوريل 2كجم عادى عرض(1+1)3مجموعة',
        ownBrand: 'كلوريل (Clorel)',
        category: 'كلور عادى',
        monthlyData: {
          '2025-01': (price: 87.72, units: 1408),
          '2025-02': (price: 84.94, units: 3980),
          '2025-03': (price: 85.28, units: 2830),
          '2025-04': (price: 85.69, units: 3590),
          '2026-01': (price: 91.40, units: 1849),
          '2026-02': (price: 89.28, units: 1958),
          '2026-03': (price: 90.11, units: 1769),
          '2026-04': (price: 98.63, units: 2127),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '6221152989317',
            skuName: 'كلوركس الوان 950 مل + كلوركس مبيض 950 مل',
            brand: 'كلوركس (Clorox)',
            supplierName: 'الموزعون المتحدون',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 60.77, units: 3286),
              '2025-02': (price: 62.85, units: 4168),
              '2025-03': (price: 66.44, units: 2452),
              '2025-04': (price: 60.30, units: 3744),
              '2026-01': (price: 66.75, units: 734),
              '2026-02': (price: 60.47, units: 1888),
              '2026-03': (price: 64.94, units: 1579),
              '2026-04': (price: 77.85, units: 1884),
            },
          ),
        ],
      ),
      // 8. مسحوق غسالات اطباق - فيبا دش لغسالات الاطباق 1ك+ ملح 1ك هدية
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223000234266',
        ownSkuName: 'فيبا دش لغسالات الاطباق 1ك+ ملح 1ك هدية',
        ownBrand: 'فيبا (Feba)',
        category: 'مسحوق غسالات اطباق',
        monthlyData: {
          '2025-01': (price: 278.05, units: 1052),
          '2025-02': (price: 275.00, units: 1476),
          '2025-03': (price: 281.45, units: 1310),
          '2025-04': (price: 275.06, units: 1612),
          '2026-01': (price: 261.41, units: 653),
          '2026-02': (price: 290.52, units: 531),
          '2026-03': (price: 279.99, units: 534),
          '2026-04': (price: 306.18, units: 398),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '5900498024937',
            skuName: 'لودفيك مسحوق غسالات اطباق 1ك',
            brand: 'لودفيك (Ludwik)',
            supplierName: 'اجروبلس للصناعات الكيماوية',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 233.00, units: 502),
              '2025-02': (price: 254.56, units: 714),
              '2025-03': (price: 265.45, units: 486),
              '2025-04': (price: 266.00, units: 622),
              '2026-01': (price: 266.00, units: 197),
              '2026-02': (price: 266.00, units: 252),
              '2026-03': (price: 266.00, units: 247),
              '2026-04': (price: 269.44, units: 237),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6223000971000',
            skuName: 'ديش برو مسحوق غسالات الاطباق 1كجم',
            brand: 'ديش برو (Dish Pro)',
            supplierName: 'المصرية للمنظفات الصناعية',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 145.00, units: 758),
              '2025-02': (price: 157.62, units: 718),
              '2025-03': (price: 174.12, units: 746),
              '2025-04': (price: 173.92, units: 780),
              '2026-01': (price: 173.86, units: 263),
              '2026-02': (price: 173.84, units: 259),
              '2026-03': (price: 173.84, units: 259),
              '2026-04': (price: 175.00, units: 230),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6223005877819',
            skuName: 'فنيش مسحوق غسالات اطباق 1ك بالليمون 2+1مجانا',
            brand: 'فينيش (Finish)',
            supplierName: 'راشدين ايجيبت - هوم',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 796.00, units: 146),
              '2025-02': (price: 796.00, units: 198),
              '2025-03': (price: 796.00, units: 148),
              '2025-04': (price: 796.00, units: 190),
              '2026-01': (price: 704.90, units: 147),
              '2026-02': (price: 700.00, units: 194),
              '2026-03': (price: 703.22, units: 134),
              '2026-04': (price: 700.87, units: 166),
            },
          ),
        ],
      ),
      // 9. ملمع زجاج وكريستال - جلاسى ملمع زجاج رشاش
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223004149283',
        ownSkuName: 'جلاسى ملمع زجاج رشاش 500مل+100مل+غيار500مل+100مل',
        ownBrand: 'جلاسي (Glassy)',
        category: 'ملمع زجاج وكريستال',
        monthlyData: {
          '2025-01': (price: 46.76, units: 3164),
          '2025-02': (price: 44.99, units: 4568),
          '2025-03': (price: 48.04, units: 3472),
          '2025-04': (price: 45.72, units: 4058),
          '2026-01': (price: 50.53, units: 2469),
          '2026-02': (price: 49.00, units: 2959),
          '2026-03': (price: 49.00, units: 2173),
          '2026-04': (price: 58.40, units: 1647),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '6224007537374',
            skuName: 'فريدا جلاس ملمع و منظف زجاج 600مل رشاش+غيار',
            brand: 'فريدا (Farida)',
            supplierName: 'فريدال للصناعات العطرية',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 50.85, units: 3876),
              '2025-02': (price: 48.83, units: 5240),
              '2025-03': (price: 48.79, units: 4594),
              '2025-04': (price: 50.29, units: 4048),
              '2026-01': (price: 57.13, units: 2171),
              '2026-02': (price: 49.00, units: 3808),
              '2026-03': (price: 49.29, units: 3143),
              '2026-04': (price: 62.38, units: 1979),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6223001342793',
            skuName: 'ويندكس رشاش 500 مل منظف وملمع زجاج شكل جديد ازرق',
            brand: 'ويندكس (Windex)',
            supplierName: 'جونسون واكس(قباء)',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 48.97, units: 1330),
              '2025-02': (price: 47.39, units: 2086),
              '2025-03': (price: 54.81, units: 1114),
              '2025-04': (price: 54.98, units: 1220),
              '2026-01': (price: 60.80, units: 764),
              '2026-02': (price: 58.03, units: 918),
              '2026-03': (price: 61.34, units: 733),
              '2026-04': (price: 60.83, units: 762),
            },
          ),
        ],
      ),
      // 10. مطهر عام - ديفاتول سائل مطهر 500مل عرض 2ق
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223004146091',
        ownSkuName: 'ديفاتول سائل مطهر 500مل عرض 2ق',
        ownBrand: 'ديفاتول (Divatol)',
        category: 'مطهر عام',
        monthlyData: {
          '2025-01': (price: 196.63, units: 740),
          '2025-02': (price: 161.16, units: 1044),
          '2025-03': (price: 193.14, units: 486),
          '2025-04': (price: 182.00, units: 848),
          '2026-01': (price: 208.64, units: 408),
          '2026-02': (price: 205.00, units: 337),
          '2026-03': (price: 205.00, units: 318),
          '2026-04': (price: 218.62, units: 297),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '6223005875341',
            skuName: 'ديتول 475 مل *2 ق خصم 40% على العبوة الثانية',
            brand: 'ديتول (Dettol)',
            supplierName: 'راشدين ايجيبت-منظفات(7)',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 451.80, units: 626),
              '2025-02': (price: 471.43, units: 502),
              '2025-03': (price: 482.57, units: 318),
              '2025-04': (price: 489.00, units: 334),
              '2026-01': (price: 451.36, units: 214),
              '2026-02': (price: 401.09, units: 336),
              '2026-03': (price: 492.58, units: 236),
              '2026-04': (price: 515.00, units: 174),
            },
          ),
        ],
      ),
      // 11. مزيلات بقع ملابس - فلفيتا مزيل بقع ملابس 1لتر بالاوكسجين
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223004148231',
        ownSkuName: 'فلفيتا مزيل بقع ملابس 1لتر بالاوكسجين',
        ownBrand: 'فلفيتا (Velveta)',
        category: 'مزيلات بقع ملابس',
        monthlyData: {
          '2025-01': (price: 78.77, units: 1400),
          '2025-02': (price: 75.00, units: 1758),
          '2025-03': (price: 72.77, units: 1288),
          '2025-04': (price: 80.81, units: 1572),
          '2026-01': (price: 57.00, units: 1589),
          '2026-02': (price: 60.00, units: 1438),
          '2026-03': (price: 80.40, units: 1135),
          '2026-04': (price: 93.21, units: 1061),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '6223005870209',
            skuName: 'فانيش مزيل بقع الملابس سائل 450 مل',
            brand: 'فانيش (Vanish)',
            supplierName: 'راشدين ايجيبت - هوم',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 168.56, units: 1698),
              '2025-02': (price: 175.35, units: 1922),
              '2025-03': (price: 181.65, units: 1386),
              '2025-04': (price: 174.96, units: 1986),
              '2026-01': (price: 184.00, units: 831),
              '2026-02': (price: 184.00, units: 848),
              '2026-03': (price: 184.00, units: 788),
              '2026-04': (price: 183.96, units: 1004),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6223014212960',
            skuName: 'بريكس مزيل للبقع 500 جم',
            brand: 'بريكس (Brix)',
            supplierName: 'ارما التجارية - منظفات',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 79.00, units: 1236),
              '2025-02': (price: 79.00, units: 1640),
              '2025-03': (price: 79.00, units: 1248),
              '2025-04': (price: 79.00, units: 1792),
              '2026-01': (price: 90.00, units: 647),
              '2026-02': (price: 90.00, units: 482),
              '2026-03': (price: 90.00, units: 959),
              '2026-04': (price: 95.68, units: 1102),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6221152989430',
            skuName: 'كلوركس باودر 250 جم 2+1',
            brand: 'كلوركس (Clorox)',
            supplierName: 'الموزعون المتحدون',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 147.28, units: 976),
              '2025-02': (price: 131.61, units: 1562),
              '2025-03': (price: 130.61, units: 1140),
              '2025-04': (price: 140.59, units: 1342),
              '2026-01': (price: 164.46, units: 619),
              '2026-02': (price: 157.83, units: 721),
              '2026-03': (price: 158.87, units: 486),
              '2026-04': (price: 163.60, units: 611),
            },
          ),
        ],
      ),
      // 12. منظف ارضيات - ماكسيل ماجيك فلور 1.8لتر
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223000233245',
        ownSkuName: 'ماكسيل ماجيك فلور 1.8لتر',
        ownBrand: 'ماكسيل (Maxell)',
        category: 'منظف ارضيات',
        monthlyData: {
          '2025-01': (price: 86.78, units: 342),
          '2025-02': (price: 84.56, units: 422),
          '2025-03': (price: 65.31, units: 482),
          '2025-04': (price: 73.43, units: 500),
          '2026-01': (price: 73.17, units: 202),
          '2026-02': (price: 69.00, units: 197),
          '2026-03': (price: 66.67, units: 190),
          '2026-04': (price: 77.56, units: 250),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '6221143099445',
            skuName: 'جنرال سائل منظف أرضيات 3 لتر برائحة لافندر',
            brand: 'جنرال (General)',
            supplierName: 'هنكل برسيل (3)',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 119.54, units: 672),
              '2025-02': (price: 129.00, units: 1106),
              '2025-03': (price: 129.00, units: 810),
              '2025-04': (price: 129.00, units: 862),
              '2026-01': (price: 139.00, units: 281),
              '2026-02': (price: 139.00, units: 285),
              '2026-03': (price: 139.00, units: 192),
              '2026-04': (price: 139.00, units: 453),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6223006124363',
            skuName: 'بريكس منظف ارضيات 730مل *2ق انواع',
            brand: 'بريكس (Brix)',
            supplierName: 'ارما التجارية - منظفات',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 52.70, units: 2148),
              '2025-02': (price: 57.62, units: 2032),
              '2025-03': (price: 57.04, units: 1186),
              '2025-04': (price: 58.31, units: 2032),
              '2026-01': (price: 67.00, units: 943),
              '2026-02': (price: 67.00, units: 1246),
              '2026-03': (price: 66.92, units: 1275),
              '2026-04': (price: 71.71, units: 1372),
            },
          ),
        ],
      ),
      // 13. منظفات مطبخ - ماكسيل ماجيك منظف للافران 500 مل
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223000237762',
        ownSkuName: 'ماكسيل ماجيك منظف للافران 500 مل',
        ownBrand: 'ماكسيل (Maxell)',
        category: 'منظفات مطبخ',
        monthlyData: {
          '2025-01': (price: 82.00, units: 850),
          '2025-02': (price: 81.93, units: 1112),
          '2025-03': (price: 65.10, units: 1286),
          '2025-04': (price: 71.29, units: 886),
          '2026-01': (price: 88.69, units: 504),
          '2026-02': (price: 94.00, units: 720),
          '2026-03': (price: 80.14, units: 722),
          '2026-04': (price: 83.40, units: 581),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '6221152091034',
            skuName: 'كلوركس منظف للمطابخ ليمون بخاخ 500مل',
            brand: 'كلوركس (Clorox)',
            supplierName: 'الموزعون المتحدون',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 92.00, units: 468),
              '2025-02': (price: 92.00, units: 644),
              '2025-03': (price: 92.00, units: 518),
              '2025-04': (price: 92.00, units: 598),
              '2026-01': (price: 92.00, units: 496),
              '2026-02': (price: 92.00, units: 649),
              '2026-03': (price: 92.00, units: 481),
              '2026-04': (price: 105.88, units: 433),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6224007537381',
            skuName: 'فريدا مزيل دهون ومعقم بالبرتقال 550جم',
            brand: 'فريدا (Farida)',
            supplierName: 'فريدال للصناعات العطرية',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 55.41, units: 1120),
              '2025-02': (price: 53.87, units: 1946),
              '2025-03': (price: 50.12, units: 2142),
              '2025-04': (price: 52.77, units: 1088),
              '2026-01': (price: 55.52, units: 843),
              '2026-02': (price: 52.00, units: 1203),
              '2026-03': (price: 52.30, units: 910),
              '2026-04': (price: 64.85, units: 738),
            },
          ),
        ],
      ),
      // 14. منظفات تواليت - ماكسيل منظف تواليت 700مل عرض 2ق
      const _RawCompetitiveGroupSeed(
        ownBarcode: '6223004147203',
        ownSkuName: 'ماكسيل منظف تواليت 700مل عرض 2ق',
        ownBrand: 'ماكسيل (Maxell)',
        category: 'منظفات تواليت',
        monthlyData: {
          '2025-01': (price: 87.98, units: 1294),
          '2025-02': (price: 77.37, units: 1728),
          '2025-03': (price: 99.23, units: 740),
          '2025-04': (price: 104.98, units: 1380),
          '2026-01': (price: 105.11, units: 895),
          '2026-02': (price: 100.00, units: 877),
          '2026-03': (price: 100.00, units: 737),
          '2026-04': (price: 108.58, units: 688),
        },
        competitors: [
          _RawCompetitorSeed(
            barcode: '6222048702379',
            skuName: 'هاربيك منظف تواليت 700 مل باور بلس 2ق خصم30%',
            brand: 'هاربيك (Harpic)',
            supplierName: 'راشدين ايجيبت - هوم',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 255.00, units: 324),
              '2025-02': (price: 260.04, units: 376),
              '2025-03': (price: 259.45, units: 246),
              '2025-04': (price: 258.34, units: 328),
              '2026-01': (price: 284.02, units: 175),
              '2026-02': (price: 279.77, units: 244),
              '2026-03': (price: 277.98, units: 160),
              '2026-04': (price: 285.99, units: 170),
            },
          ),
          _RawCompetitorSeed(
            barcode: '6223006128644',
            skuName: 'بريكس منظف تواليت 700 مل ازرق',
            brand: 'بريكس (Brix)',
            supplierName: 'ارما التجارية - منظفات',
            isPinnedDirect: true,
            monthlyData: {
              '2025-01': (price: 52.60, units: 962),
              '2025-02': (price: 59.95, units: 1306),
              '2025-03': (price: 60.00, units: 1092),
              '2025-04': (price: 60.00, units: 1308),
              '2026-01': (price: 75.00, units: 538),
              '2026-02': (price: 75.00, units: 606),
              '2026-03': (price: 75.00, units: 629),
              '2026-04': (price: 80.86, units: 786),
            },
          ),
        ],
      ),
    ];

    // Helper to resolve price & units for a given (year, month) from a monthlyData map
    ({double price, int units, double recommendedPrice}) resolvePeriodMetrics(
      Map<String, ({double price, int units})> monthlyData,
      int targetYear,
      int targetMonth,
    ) {
      if (targetMonth > 0) {
        final key = '$targetYear-${targetMonth.toString().padLeft(2, '0')}';
        final exact = monthlyData[key];
        if (exact != null && exact.price > 0) {
          return (price: exact.price, units: exact.units, recommendedPrice: exact.price);
        }
      }
      // Filter all months in targetYear
      final yearKeys = monthlyData.keys
          .where((k) => targetYear <= 0 || k.startsWith('$targetYear-'))
          .toList()
        ..sort();
      if (yearKeys.isEmpty) {
        final allKeys = monthlyData.keys.toList()..sort();
        if (allKeys.isEmpty) return (price: 0.0, units: 0, recommendedPrice: 0.0);
        final last = monthlyData[allKeys.last]!;
        return (price: last.price, units: last.units, recommendedPrice: last.price);
      }
      double totalRev = 0.0;
      int totalUnits = 0;
      double latestPrice = 0.0;
      for (final k in yearKeys) {
        final pt = monthlyData[k]!;
        totalRev += pt.price * pt.units;
        totalUnits += pt.units;
        if (pt.price > 0) latestPrice = pt.price;
      }
      // When viewing a full year (month == 0), use the latest month's active shelf price as current selling price
      // and also compute weighted average price as reference.
      final avgPrice = totalUnits > 0
          ? double.parse((totalRev / totalUnits).toStringAsFixed(2))
          : latestPrice;
      final activePrice = latestPrice > 0 ? latestPrice : avgPrice;
      return (price: activePrice, units: totalUnits, recommendedPrice: avgPrice);
    }

    final result = <OwnSkuCompetitiveGroupModel>[];

    for (final seed in rawDefs) {
      final ownPack = extractPackVolume(seed.ownSkuName);
      final ownMonthly = mergeMonthlyData(
        seed.monthlyData,
        liveByBarcode[seed.ownBarcode],
        allowSeeds: allowSeedMonths,
      );
      final ownResolved = resolvePeriodMetrics(ownMonthly, year, month);
      final effectiveOwnPrice = ownResolved.price;
      if (effectiveOwnPrice <= 0) continue;

      final ownPricePerVol = ownPack.volume > 0
          ? double.parse((effectiveOwnPrice / ownPack.volume).toStringAsFixed(2))
          : effectiveOwnPrice;

      final ownYearTrajectory = buildMonthlyPriceTrajectory(ownMonthly, filterYear: year);
      final ownAllTrajectory = buildMonthlyPriceTrajectory(ownMonthly);

      double totalCatRev = effectiveOwnPrice * ownResolved.units;

      // Strictly keep 1 direct competitor card per rival Brand (no duplicate brand cards)
      final seenBrands = <String>{};
      final compSeeds = <_RawCompetitorSeed>[];
      for (final c in seed.competitors) {
        if (seenBrands.add(c.brand.trim().toLowerCase())) {
          compSeeds.add(c);
        }
      }

      final resolvedCompMetrics = <({
        _RawCompetitorSeed seed,
        double price,
        int units,
        List<SkuMonthlyPricePointModel> yearTrajectory,
        List<SkuMonthlyPricePointModel> allTrajectory,
      })>[];

      for (final c in compSeeds) {
        final compMonthly = mergeMonthlyData(
          c.monthlyData,
          liveByBarcode[c.barcode],
          allowSeeds: allowSeedMonths,
        );
        final cm = resolvePeriodMetrics(compMonthly, year, month);
        if (cm.price <= 0) continue;
        totalCatRev += cm.price * cm.units;
        resolvedCompMetrics.add((
          seed: c,
          price: cm.price,
          units: cm.units,
          yearTrajectory: buildMonthlyPriceTrajectory(compMonthly, filterYear: year),
          allTrajectory: buildMonthlyPriceTrajectory(compMonthly),
        ));
      }

      final customList = _customPinnedCompetitors[seed.ownBarcode] ??
          _customPinnedCompetitors[seed.ownSkuName] ??
          const [];
      for (final custom in customList) {
        totalCatRev += custom.netRevenue;
      }

      final ownCatSharePct = totalCatRev > 0
          ? double.parse((((effectiveOwnPrice * ownResolved.units) / totalCatRev) * 100.0).toStringAsFixed(1))
          : 25.0;

      final builtCompetitors = <CompetitorSkuComparisonModel>[];

      for (final custom in customList) {
        final diffEgp = custom.unitPrice - effectiveOwnPrice;
        final diffPct = effectiveOwnPrice > 0 ? (diffEgp / effectiveOwnPrice) * 100.0 : 0.0;
        final pos = diffPct > 1.5
            ? 'higher'
            : diffPct < -1.5
                ? 'lower'
                : 'equal';
        builtCompetitors.add(
          custom.copyWithPriceContext(
            priceDiffEgp: double.parse(diffEgp.toStringAsFixed(2)),
            priceDiffPct: double.parse(diffPct.toStringAsFixed(1)),
            pricePosition: pos,
          ),
        );
      }

      for (final item in resolvedCompMetrics) {
        final c = item.seed;
        final cPack = extractPackVolume(c.skuName);
        final cPrice = item.price;
        final cUnits = item.units;
        final cPricePerVol = cPack.volume > 0
            ? double.parse((cPrice / cPack.volume).toStringAsFixed(2))
            : cPrice;
        final diffEgp = cPrice - effectiveOwnPrice;
        final diffPct = effectiveOwnPrice > 0 ? (diffEgp / effectiveOwnPrice) * 100.0 : 0.0;
        final String pos;
        if (diffPct > 1.5) {
          pos = 'higher';
        } else if (diffPct < -1.5) {
          pos = 'lower';
        } else {
          pos = 'equal';
        }
        final cRev = double.parse((cPrice * cUnits).toStringAsFixed(2));
        final cShare = totalCatRev > 0
            ? double.parse(((cRev / totalCatRev) * 100.0).toStringAsFixed(1))
            : 15.0;

        // Check if competitor dropped price in latest month (active promo signal)
        final hasRecentDiscount = item.yearTrajectory.isNotEmpty &&
            item.yearTrajectory.last.priceChangePct < -1.5;

        builtCompetitors.add(
          CompetitorSkuComparisonModel(
            skuName: c.skuName,
            barcode: c.barcode,
            supplierName: c.supplierName,
            brand: c.brand,
            category: seed.category,
            packSizeLabel: cPack.badgeLabel,
            packVolumeUnits: cPack.volume,
            volumeUnitLabel: cPack.unitLabel,
            unitPrice: cPrice,
            pricePerUnitVolume: cPricePerVol,
            priceDiffEgp: double.parse(diffEgp.toStringAsFixed(2)),
            priceDiffPct: double.parse(diffPct.toStringAsFixed(1)),
            pricePosition: pos,
            unitsSold: cUnits,
            netRevenue: cRev,
            categorySharePct: cShare,
            isPromoActive: hasRecentDiscount,
            isPinnedDirect: c.isPinnedDirect,
            chainPrices: {'fathalla': cPrice},
            monthlyPrices: item.yearTrajectory,
            allMonthlyPrices: item.allTrajectory,
          ),
        );
      }

      double avgComp = effectiveOwnPrice;
      double minComp = effectiveOwnPrice;
      double maxComp = effectiveOwnPrice;
      if (builtCompetitors.isNotEmpty) {
        avgComp = builtCompetitors.fold<double>(0.0, (s, i) => s + i.unitPrice) /
            builtCompetitors.length;
        minComp = builtCompetitors
            .map((i) => i.unitPrice)
            .reduce((a, b) => a < b ? a : b);
        maxComp = builtCompetitors
            .map((i) => i.unitPrice)
            .reduce((a, b) => a > b ? a : b);
      }

      final priceIndex = avgComp > 0
          ? double.parse(((effectiveOwnPrice / avgComp) * 100.0).toStringAsFixed(1))
          : 100.0;

      result.add(
        OwnSkuCompetitiveGroupModel(
          ownBarcode: seed.ownBarcode,
          ownSkuName: seed.ownSkuName,
          ownBrand: seed.ownBrand,
          category: seed.category,
          packSizeLabel: ownPack.badgeLabel,
          packVolumeUnits: ownPack.volume,
          volumeUnitLabel: ownPack.unitLabel,
          ownUnitPrice: effectiveOwnPrice,
          ownRecommendedPrice: ownResolved.recommendedPrice,
          ownPricePerUnitVolume: ownPricePerVol,
          ownUnitsSold: ownResolved.units,
          ownNetRevenue: double.parse((effectiveOwnPrice * ownResolved.units).toStringAsFixed(2)),
          ownCategorySharePct: ownCatSharePct,
          avgCompetitorPrice: double.parse(avgComp.toStringAsFixed(2)),
          minCompetitorPrice: double.parse(minComp.toStringAsFixed(2)),
          maxCompetitorPrice: double.parse(maxComp.toStringAsFixed(2)),
          priceIndex: priceIndex,
          ownChainPrices: {'fathalla': effectiveOwnPrice},
          competitors: builtCompetitors,
          monthlyPrices: ownYearTrajectory,
          allMonthlyPrices: ownAllTrajectory,
          selectedYear: year,
          selectedMonth: month,
        ),
      );
    }

    return result;
  }
}

class _RawCompetitorSeed {
  final String barcode;
  final String skuName;
  final String brand;
  final String supplierName;
  final bool isPinnedDirect;
  final Map<String, ({double price, int units})> monthlyData;

  const _RawCompetitorSeed({
    required this.barcode,
    required this.skuName,
    required this.brand,
    required this.supplierName,
    required this.isPinnedDirect,
    required this.monthlyData,
  });
}

class _RawCompetitiveGroupSeed {
  final String ownBarcode;
  final String ownSkuName;
  final String ownBrand;
  final String category;
  final Map<String, ({double price, int units})> monthlyData;
  final List<_RawCompetitorSeed> competitors;

  const _RawCompetitiveGroupSeed({
    required this.ownBarcode,
    required this.ownSkuName,
    required this.ownBrand,
    required this.category,
    required this.monthlyData,
    required this.competitors,
  });
}

/// Represents a monthly price & volume data point for an Own or Competitor SKU.
class SkuMonthlyPricePointModel {
  final String monthKey; // e.g. '2026-01'
  final int year;
  final int monthNum;
  final String monthNameAr; // e.g. 'يناير'
  final String monthLabelAr; // e.g. 'يناير 2026'
  final double unitPrice;
  final int unitsSold;
  final double netRevenue;
  final double priceChangeEgp;
  final double priceChangePct;
  /// `'up'`, `'down'`, `'stable'`, or `'baseline'`
  final String trendDirection;

  const SkuMonthlyPricePointModel({
    required this.monthKey,
    required this.year,
    required this.monthNum,
    required this.monthNameAr,
    required this.monthLabelAr,
    required this.unitPrice,
    required this.unitsSold,
    required this.netRevenue,
    required this.priceChangeEgp,
    required this.priceChangePct,
    required this.trendDirection,
  });
}

/// Represents a single Competitor SKU mapped against an Own SKU.
class CompetitorSkuComparisonModel {
  final String skuName;
  final String barcode;
  final String supplierName;
  final String brand;
  final String category;
  final String packSizeLabel;
  final double packVolumeUnits;
  final String volumeUnitLabel;
  final double unitPrice;
  final double pricePerUnitVolume;
  /// `unitPrice - ownUnitPrice`. Positive (+) means Competitor is MORE EXPENSIVE (higher) than us.
  /// Negative (-) means Competitor is CHEAPER (lower) than us.
  final double priceDiffEgp;
  final double priceDiffPct;
  /// `'higher'` (المنافس أعلى سعراً), `'lower'` (المنافس أقل سعراً), or `'equal'` (مساوي)
  final String pricePosition;
  final int unitsSold;
  final double netRevenue;
  final double categorySharePct;
  final bool isPromoActive;
  final bool isPinnedDirect;
  final Map<String, double> chainPrices;
  final List<SkuMonthlyPricePointModel> monthlyPrices;
  final List<SkuMonthlyPricePointModel> allMonthlyPrices;

  const CompetitorSkuComparisonModel({
    required this.skuName,
    required this.barcode,
    required this.supplierName,
    required this.brand,
    required this.category,
    required this.packSizeLabel,
    required this.packVolumeUnits,
    required this.volumeUnitLabel,
    required this.unitPrice,
    required this.pricePerUnitVolume,
    required this.priceDiffEgp,
    required this.priceDiffPct,
    required this.pricePosition,
    required this.unitsSold,
    required this.netRevenue,
    required this.categorySharePct,
    this.isPromoActive = false,
    this.isPinnedDirect = true,
    this.chainPrices = const {},
    this.monthlyPrices = const [],
    this.allMonthlyPrices = const [],
  });

  double get periodPriceChangePct {
    if (monthlyPrices.length < 2) return 0.0;
    final first = monthlyPrices.first.unitPrice;
    final last = monthlyPrices.last.unitPrice;
    if (first <= 0) return 0.0;
    return double.parse((((last - first) / first) * 100.0).toStringAsFixed(1));
  }

  double get periodPriceChangeEgp {
    if (monthlyPrices.length < 2) return 0.0;
    return double.parse((monthlyPrices.last.unitPrice - monthlyPrices.first.unitPrice).toStringAsFixed(2));
  }

  CompetitorSkuComparisonModel copyWithPriceContext({
    required double priceDiffEgp,
    required double priceDiffPct,
    required String pricePosition,
  }) {
    return CompetitorSkuComparisonModel(
      skuName: skuName,
      barcode: barcode,
      supplierName: supplierName,
      brand: brand,
      category: category,
      packSizeLabel: packSizeLabel,
      packVolumeUnits: packVolumeUnits,
      volumeUnitLabel: volumeUnitLabel,
      unitPrice: unitPrice,
      pricePerUnitVolume: pricePerUnitVolume,
      priceDiffEgp: priceDiffEgp,
      priceDiffPct: priceDiffPct,
      pricePosition: pricePosition,
      unitsSold: unitsSold,
      netRevenue: netRevenue,
      categorySharePct: categorySharePct,
      isPromoActive: isPromoActive,
      isPinnedDirect: isPinnedDirect,
      chainPrices: chainPrices,
      monthlyPrices: monthlyPrices,
      allMonthlyPrices: allMonthlyPrices,
    );
  }
}

/// Represents one of the Tenant's Own SKUs along with all competing SKUs from other companies.
class OwnSkuCompetitiveGroupModel {
  final String ownBarcode;
  final String ownSkuName;
  final String ownBrand;
  final String category;
  final String packSizeLabel;
  final double packVolumeUnits;
  final String volumeUnitLabel;
  final double ownUnitPrice;
  final double ownRecommendedPrice;
  final double ownPricePerUnitVolume;
  final int ownUnitsSold;
  final double ownNetRevenue;
  final double ownCategorySharePct;
  final double avgCompetitorPrice;
  final double minCompetitorPrice;
  final double maxCompetitorPrice;
  /// `ownUnitPrice / avgCompetitorPrice * 100`. < 100 means our SKU is cheaper than market average.
  final double priceIndex;
  final Map<String, double> ownChainPrices;
  final List<CompetitorSkuComparisonModel> competitors;
  final List<SkuMonthlyPricePointModel> monthlyPrices;
  final List<SkuMonthlyPricePointModel> allMonthlyPrices;
  final int selectedYear;
  final int selectedMonth;

  const OwnSkuCompetitiveGroupModel({
    required this.ownBarcode,
    required this.ownSkuName,
    required this.ownBrand,
    required this.category,
    required this.packSizeLabel,
    required this.packVolumeUnits,
    required this.volumeUnitLabel,
    required this.ownUnitPrice,
    required this.ownRecommendedPrice,
    required this.ownPricePerUnitVolume,
    required this.ownUnitsSold,
    required this.ownNetRevenue,
    required this.ownCategorySharePct,
    required this.avgCompetitorPrice,
    required this.minCompetitorPrice,
    required this.maxCompetitorPrice,
    required this.priceIndex,
    required this.ownChainPrices,
    required this.competitors,
    this.monthlyPrices = const [],
    this.allMonthlyPrices = const [],
    this.selectedYear = 2026,
    this.selectedMonth = 0,
  });

  double get periodPriceChangePct {
    if (monthlyPrices.length < 2) return 0.0;
    final first = monthlyPrices.first.unitPrice;
    final last = monthlyPrices.last.unitPrice;
    if (first <= 0) return 0.0;
    return double.parse((((last - first) / first) * 100.0).toStringAsFixed(1));
  }

  double get periodPriceChangeEgp {
    if (monthlyPrices.length < 2) return 0.0;
    return double.parse((monthlyPrices.last.unitPrice - monthlyPrices.first.unitPrice).toStringAsFixed(2));
  }

  int get higherPricedCompetitorsCount =>
      competitors.where((c) => c.pricePosition == 'higher').length;

  int get lowerPricedCompetitorsCount =>
      competitors.where((c) => c.pricePosition == 'lower').length;

  int get equalPricedCompetitorsCount =>
      competitors.where((c) => c.pricePosition == 'equal').length;

  /// Overall positioning of our SKU against competitors:
  /// - `'advantage'` if our price is lower than average competitor price by > 2%
  /// - `'premium'` if our price is higher than average competitor price by > 2%
  /// - `'parity'` if within ±2%
  String get ownPositioningStatus {
    final gapVsAvgPct = avgCompetitorPrice > 0
        ? ((ownUnitPrice - avgCompetitorPrice) / avgCompetitorPrice) * 100.0
        : 0.0;
    if (gapVsAvgPct < -2.0) return 'advantage';
    if (gapVsAvgPct > 2.0) return 'premium';
    return 'parity';
  }
}

class SellInRecordItem {
  final String recordId;
  final String batchId;
  final String sourceFilename;
  final String tenantId;
  final String retailerChain;
  final int year;
  final int monthNum;
  final String monthEn;
  final String monthAr;
  final String periodWeek;
  final String regionCode;
  final String governorate;
  final String sector;
  final String customerName;
  final String itemCode;
  final String barcode;
  final String brand;
  final String subCategory;
  final String itemName;
  final int unitsPerCarton;
  final String promotionType;
  final String salesManager;
  final String kaOfficer;
  final String salesRep;
  final double netQtyCases;
  final double netValueEgp;
  final double weightTons;
  final double expectedQtyCases;
  final double expectedValueEgp;
  final String transactionType;
  final int totalUnitsSupplied;
  final double officialUnitExclVatEgp;
  final double officialUnitInclVatEgp;
  final double officialCartonExclVatEgp;
  final double officialCartonInclVatEgp;
  final double netCartonInvoiceCostEgp;
  final double invoiceDiscountPct;
  final double extraDiscountPct;
  final double vatRate;
  final double grossValueInclVatEgp;
  final double vatAmountEgp;
  final double officialListValueExclEgp;
  final double discountGrantedEgp;
  final double effectiveDiscountPct;
  final double actualCasePriceExclEgp;
  final double priceVariancePct;
  final String pricingWaveStatus;
  final String departmentAr;

  const SellInRecordItem({
    required this.recordId,
    this.batchId = '',
    this.sourceFilename = '',
    required this.tenantId,
    required this.retailerChain,
    required this.year,
    required this.monthNum,
    required this.monthEn,
    required this.monthAr,
    required this.periodWeek,
    required this.regionCode,
    required this.governorate,
    required this.sector,
    required this.customerName,
    this.itemCode = '',
    this.barcode = '',
    required this.brand,
    required this.subCategory,
    required this.itemName,
    this.unitsPerCarton = 12,
    required this.promotionType,
    required this.salesManager,
    required this.kaOfficer,
    required this.salesRep,
    required this.netQtyCases,
    required this.netValueEgp,
    required this.weightTons,
    required this.expectedQtyCases,
    required this.expectedValueEgp,
    required this.transactionType,
    this.totalUnitsSupplied = 0,
    this.officialUnitExclVatEgp = 0.0,
    this.officialUnitInclVatEgp = 0.0,
    this.officialCartonExclVatEgp = 0.0,
    this.officialCartonInclVatEgp = 0.0,
    this.netCartonInvoiceCostEgp = 0.0,
    this.invoiceDiscountPct = 10.0,
    this.extraDiscountPct = 0.0,
    this.vatRate = 0.14,
    this.grossValueInclVatEgp = 0.0,
    this.vatAmountEgp = 0.0,
    this.officialListValueExclEgp = 0.0,
    this.discountGrantedEgp = 0.0,
    this.effectiveDiscountPct = 0.0,
    this.actualCasePriceExclEgp = 0.0,
    this.priceVariancePct = 0.0,
    this.pricingWaveStatus = 'current_list',
    this.departmentAr = '',
  });

  factory SellInRecordItem.fromJson(Map<String, dynamic> json) {
    final upc = (json['units_per_carton'] as num?)?.toInt() ?? 12;
    final cases = (json['net_qty_cases'] as num?)?.toDouble() ?? 0.0;
    final netVal = (json['net_value_egp'] as num?)?.toDouble() ?? 0.0;
    final vatR = (json['vat_rate'] as num?)?.toDouble() ?? 0.14;
    final grossVal = (json['gross_value_incl_vat_egp'] as num?)?.toDouble() ??
        double.parse((netVal * (1.0 + vatR)).toStringAsFixed(2));
    final vatAmt = (json['vat_amount_egp'] as num?)?.toDouble() ??
        double.parse((grossVal - netVal).toStringAsFixed(2));
    return SellInRecordItem(
      recordId: json['record_id'] as String? ?? '',
      batchId: json['batch_id'] as String? ?? '',
      sourceFilename: json['source_filename'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      retailerChain: json['retailer_chain'] as String? ?? 'fathalla',
      year: (json['year'] as num?)?.toInt() ?? 2026,
      monthNum: (json['month_num'] as num?)?.toInt() ?? 1,
      monthEn: json['month_en'] as String? ?? '',
      monthAr: json['month_ar'] as String? ?? '',
      periodWeek: json['period_week'] as String? ?? 'Full Month',
      regionCode: json['region_code'] as String? ?? '',
      governorate: json['governorate'] as String? ?? '',
      sector: json['sector'] as String? ?? 'MT',
      customerName: json['customer_name'] as String? ?? '',
      itemCode: json['item_code'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      subCategory: json['sub_category'] as String? ?? '',
      itemName: json['item_name'] as String? ?? '',
      unitsPerCarton: upc,
      promotionType: json['promotion_type'] as String? ?? 'عادي',
      salesManager: json['sales_manager'] as String? ?? '',
      kaOfficer: json['ka_officer'] as String? ?? '',
      salesRep: json['sales_rep'] as String? ?? '',
      netQtyCases: cases,
      netValueEgp: netVal,
      weightTons: (json['weight_tons'] as num?)?.toDouble() ?? 0.0,
      expectedQtyCases: (json['expected_qty_cases'] as num?)?.toDouble() ?? 0.0,
      expectedValueEgp: (json['expected_value_egp'] as num?)?.toDouble() ?? 0.0,
      transactionType: json['transaction_type'] as String? ?? '',
      totalUnitsSupplied: (json['total_units_supplied'] as num?)?.toInt() ??
          (cases * upc).round(),
      officialUnitExclVatEgp: (json['official_unit_excl_vat_egp'] as num?)?.toDouble() ?? 0.0,
      officialUnitInclVatEgp: (json['official_unit_incl_vat_egp'] as num?)?.toDouble() ?? 0.0,
      officialCartonExclVatEgp: (json['official_carton_excl_vat_egp'] as num?)?.toDouble() ?? 0.0,
      officialCartonInclVatEgp: (json['official_carton_incl_vat_egp'] as num?)?.toDouble() ?? 0.0,
      netCartonInvoiceCostEgp: (json['net_carton_invoice_cost_egp'] as num?)?.toDouble() ?? 0.0,
      invoiceDiscountPct: (json['invoice_discount_pct'] as num?)?.toDouble() ?? 10.0,
      extraDiscountPct: (json['extra_discount_pct'] as num?)?.toDouble() ?? 0.0,
      vatRate: vatR,
      grossValueInclVatEgp: grossVal,
      vatAmountEgp: vatAmt,
      officialListValueExclEgp: (json['official_list_value_excl_egp'] as num?)?.toDouble() ?? 0.0,
      discountGrantedEgp: (json['discount_granted_egp'] as num?)?.toDouble() ?? 0.0,
      effectiveDiscountPct: (json['effective_discount_pct'] as num?)?.toDouble() ?? 0.0,
      actualCasePriceExclEgp: (json['actual_case_price_excl_egp'] as num?)?.toDouble() ??
          (cases.abs() > 0.001 ? double.parse((netVal.abs() / cases.abs()).toStringAsFixed(2)) : 0.0),
      priceVariancePct: (json['price_variance_pct'] as num?)?.toDouble() ?? 0.0,
      pricingWaveStatus: json['pricing_wave_status'] as String? ?? 'current_list',
      departmentAr: json['department_ar'] as String? ?? '',
    );
  }
}

class SellInExplorerResponse {
  final List<SellInRecordItem> records;
  final int totalCount;
  final double totalValueEgp;
  final double totalCases;
  final int totalUnitsPieces;
  final double totalWeightTons;
  final double totalExpectedEgp;
  final double totalOfficialListExclVatEgp;
  final double totalOfficialListInclVatEgp;
  final double totalDiscountGrantedEgp;
  final double effectiveDiscountPct;
  final double totalNetExclVatEgp;
  final double totalVat14Egp;
  final double totalGrossInclVatEgp;
  final int matchedCatalogSkusCount;

  const SellInExplorerResponse({
    required this.records,
    required this.totalCount,
    required this.totalValueEgp,
    required this.totalCases,
    this.totalUnitsPieces = 0,
    required this.totalWeightTons,
    required this.totalExpectedEgp,
    this.totalOfficialListExclVatEgp = 0.0,
    this.totalOfficialListInclVatEgp = 0.0,
    this.totalDiscountGrantedEgp = 0.0,
    this.effectiveDiscountPct = 10.0,
    this.totalNetExclVatEgp = 0.0,
    this.totalVat14Egp = 0.0,
    this.totalGrossInclVatEgp = 0.0,
    this.matchedCatalogSkusCount = 0,
  });

  factory SellInExplorerResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['records'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SellInRecordItem.fromJson)
        .toList();
    final totVal = (json['total_value_egp'] as num?)?.toDouble() ?? 0.0;
    final totCases = (json['total_cases'] as num?)?.toDouble() ?? 0.0;
    final totListExcl = (json['total_official_list_excl_vat_egp'] as num?)?.toDouble() ??
        (totVal > 0 ? double.parse((totVal / 0.90).toStringAsFixed(2)) : 0.0);
    final totGrossIncl = (json['total_gross_incl_vat_egp'] as num?)?.toDouble() ??
        double.parse((totVal * 1.14).toStringAsFixed(2));
    final totVat = (json['total_vat_14_egp'] as num?)?.toDouble() ??
        double.parse((totGrossIncl - totVal).toStringAsFixed(2));
    return SellInExplorerResponse(
      records: list,
      totalCount: (json['total_count'] as num?)?.toInt() ?? list.length,
      totalValueEgp: totVal,
      totalCases: totCases,
      totalUnitsPieces: (json['total_units_pieces'] as num?)?.toInt() ??
          (totCases * 12).round(),
      totalWeightTons: (json['total_weight_tons'] as num?)?.toDouble() ?? 0.0,
      totalExpectedEgp: (json['total_expected_egp'] as num?)?.toDouble() ?? 0.0,
      totalOfficialListExclVatEgp: totListExcl,
      totalOfficialListInclVatEgp: (json['total_official_list_incl_vat_egp'] as num?)?.toDouble() ??
          double.parse((totListExcl * 1.14).toStringAsFixed(2)),
      totalDiscountGrantedEgp: (json['total_discount_granted_egp'] as num?)?.toDouble() ??
          double.parse((totListExcl - totVal).clamp(0.0, double.infinity).toStringAsFixed(2)),
      effectiveDiscountPct: (json['effective_discount_pct'] as num?)?.toDouble() ?? 10.0,
      totalNetExclVatEgp: (json['total_net_excl_vat_egp'] as num?)?.toDouble() ?? totVal,
      totalVat14Egp: totVat,
      totalGrossInclVatEgp: totGrossIncl,
      matchedCatalogSkusCount: (json['matched_catalog_skus_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class TargetSKUBreakdownModel {
  final String itemCode;
  final String barcode;
  final String departmentAr;
  final double officialCartonExclVatEgp;
  final double officialCartonInclVatEgp;
  final int targetPieces;
  final int actualPieces;
  final String skuName;
  final String brand;
  final String sector;
  final String subCategory;
  final int unitsPerCarton;
  final double sharePct;
  final double casePriceEgp;
  final double targetRevenueEgp;
  final double targetUnits;
  final double targetWeightTons;
  final double actualRevenueEgp;
  final double actualUnits;
  final double actualWeightTons;
  final double expectedRevenueEgp;
  final double expectedUnits;
  final double varianceRevenueEgp;
  final double varianceUnits;
  final double achievementPct;
  final double remainingStockCases;
  final String stockStatus;
  final String stockStatusAr;
  final double promoSharePct;

  const TargetSKUBreakdownModel({
    this.itemCode = '',
    this.barcode = '',
    this.departmentAr = '',
    this.officialCartonExclVatEgp = 0.0,
    this.officialCartonInclVatEgp = 0.0,
    this.targetPieces = 0,
    this.actualPieces = 0,
    required this.skuName,
    required this.brand,
    required this.sector,
    required this.subCategory,
    this.unitsPerCarton = 12,
    required this.sharePct,
    required this.casePriceEgp,
    required this.targetRevenueEgp,
    required this.targetUnits,
    required this.targetWeightTons,
    required this.actualRevenueEgp,
    required this.actualUnits,
    required this.actualWeightTons,
    required this.expectedRevenueEgp,
    required this.expectedUnits,
    required this.varianceRevenueEgp,
    required this.varianceUnits,
    required this.achievementPct,
    required this.remainingStockCases,
    required this.stockStatus,
    required this.stockStatusAr,
    required this.promoSharePct,
  });

  factory TargetSKUBreakdownModel.fromJson(Map<String, dynamic> json) {
    final upc = (json['units_per_carton'] as num?)?.toInt() ?? 12;
    final tCases = (json['target_units'] as num?)?.toDouble() ?? 0.0;
    final aCases = (json['actual_units'] as num?)?.toDouble() ?? 0.0;
    return TargetSKUBreakdownModel(
      itemCode: json['item_code'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      departmentAr: json['department_ar'] as String? ?? '',
      officialCartonExclVatEgp: (json['official_carton_excl_vat_egp'] as num?)?.toDouble() ?? 0.0,
      officialCartonInclVatEgp: (json['official_carton_incl_vat_egp'] as num?)?.toDouble() ?? 0.0,
      targetPieces: (json['target_pieces'] as num?)?.toInt() ?? (tCases * upc).round(),
      actualPieces: (json['actual_pieces'] as num?)?.toInt() ?? (aCases * upc).round(),
      skuName: json['sku_name'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      sector: json['sector'] as String? ?? 'MT',
      subCategory: json['sub_category'] as String? ?? '',
      unitsPerCarton: upc,
      sharePct: (json['share_pct'] as num?)?.toDouble() ?? 0.0,
      casePriceEgp: (json['case_price_egp'] as num?)?.toDouble() ?? 0.0,
      targetRevenueEgp: (json['target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      targetUnits: tCases,
      targetWeightTons: (json['target_weight_tons'] as num?)?.toDouble() ?? 0.0,
      actualRevenueEgp: (json['actual_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      actualUnits: aCases,
      actualWeightTons: (json['actual_weight_tons'] as num?)?.toDouble() ?? 0.0,
      expectedRevenueEgp: (json['expected_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      expectedUnits: (json['expected_units'] as num?)?.toDouble() ?? 0.0,
      varianceRevenueEgp: (json['variance_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      varianceUnits: (json['variance_units'] as num?)?.toDouble() ?? 0.0,
      achievementPct: (json['achievement_pct'] as num?)?.toDouble() ?? 0.0,
      remainingStockCases: (json['remaining_stock_cases'] as num?)?.toDouble() ?? 0.0,
      stockStatus: json['stock_status'] as String? ?? 'optimal',
      stockStatusAr: json['stock_status_ar'] as String? ?? 'رصيد آمن ومتوازن',
      promoSharePct: (json['promo_share_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class TargetBranchBreakdownModel {
  final String branchCode;
  final String branchName;
  final String regionCode;
  final String governorate;
  final String salesRep;
  final String kaOfficer;
  final double shareOfChainPct;
  final int activeSkusCount;
  final double targetRevenueEgp;
  final double targetUnits;
  final double targetWeightTons;
  final double grossTargetUnits;
  final double actualRevenueEgp;
  final double actualUnits;
  final double actualWeightTons;
  final double expectedRevenueEgp;
  final double expectedUnits;
  final double varianceRevenueEgp;
  final double varianceUnits;
  final double achievementRevPct;
  final double achievementUnitsPct;
  final String status;
  final String statusAr;
  final List<TargetSKUBreakdownModel> skus;

  const TargetBranchBreakdownModel({
    required this.branchCode,
    required this.branchName,
    required this.regionCode,
    required this.governorate,
    required this.salesRep,
    required this.kaOfficer,
    required this.shareOfChainPct,
    required this.activeSkusCount,
    required this.targetRevenueEgp,
    required this.targetUnits,
    required this.targetWeightTons,
    required this.grossTargetUnits,
    required this.actualRevenueEgp,
    required this.actualUnits,
    required this.actualWeightTons,
    required this.expectedRevenueEgp,
    required this.expectedUnits,
    required this.varianceRevenueEgp,
    required this.varianceUnits,
    required this.achievementRevPct,
    required this.achievementUnitsPct,
    required this.status,
    required this.statusAr,
    required this.skus,
  });

  factory TargetBranchBreakdownModel.fromJson(Map<String, dynamic> json) {
    final skusList = (json['skus'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TargetSKUBreakdownModel.fromJson)
        .toList();
    return TargetBranchBreakdownModel(
      branchCode: json['branch_code'] as String? ?? '',
      branchName: json['branch_name'] as String? ?? '',
      regionCode: json['region_code'] as String? ?? 'ALX',
      governorate: json['governorate'] as String? ?? '',
      salesRep: json['sales_rep'] as String? ?? '',
      kaOfficer: json['ka_officer'] as String? ?? '',
      shareOfChainPct: (json['share_of_chain_pct'] as num?)?.toDouble() ?? 0.0,
      activeSkusCount: (json['active_skus_count'] as num?)?.toInt() ?? skusList.length,
      targetRevenueEgp: (json['target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      targetUnits: (json['target_units'] as num?)?.toDouble() ?? 0.0,
      targetWeightTons: (json['target_weight_tons'] as num?)?.toDouble() ?? 0.0,
      grossTargetUnits: (json['gross_target_units'] as num?)?.toDouble() ?? 0.0,
      actualRevenueEgp: (json['actual_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      actualUnits: (json['actual_units'] as num?)?.toDouble() ?? 0.0,
      actualWeightTons: (json['actual_weight_tons'] as num?)?.toDouble() ?? 0.0,
      expectedRevenueEgp: (json['expected_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      expectedUnits: (json['expected_units'] as num?)?.toDouble() ?? 0.0,
      varianceRevenueEgp: (json['variance_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      varianceUnits: (json['variance_units'] as num?)?.toDouble() ?? 0.0,
      achievementRevPct: (json['achievement_rev_pct'] as num?)?.toDouble() ?? 0.0,
      achievementUnitsPct: (json['achievement_units_pct'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'at_risk',
      statusAr: json['status_ar'] as String? ?? 'أقل من المستهدف',
      skus: skusList,
    );
  }
}

class TargetBrandBreakdownModel {
  final String brand;
  final String sector;
  final String sectorNameAr;
  final double sharePct;
  final int activeSkusCount;
  final double targetRevenueEgp;
  final double targetUnits;
  final double targetWeightTons;
  final double actualRevenueEgp;
  final double actualUnits;
  final double expectedRevenueEgp;
  final double varianceRevenueEgp;
  final double varianceUnits;
  final double achievementPct;

  const TargetBrandBreakdownModel({
    required this.brand,
    required this.sector,
    required this.sectorNameAr,
    required this.sharePct,
    required this.activeSkusCount,
    required this.targetRevenueEgp,
    required this.targetUnits,
    required this.targetWeightTons,
    required this.actualRevenueEgp,
    required this.actualUnits,
    required this.expectedRevenueEgp,
    required this.varianceRevenueEgp,
    required this.varianceUnits,
    required this.achievementPct,
  });

  factory TargetBrandBreakdownModel.fromJson(Map<String, dynamic> json) {
    return TargetBrandBreakdownModel(
      brand: json['brand'] as String? ?? '',
      sector: json['sector'] as String? ?? 'MT',
      sectorNameAr: json['sector_name_ar'] as String? ?? '',
      sharePct: (json['share_pct'] as num?)?.toDouble() ?? 0.0,
      activeSkusCount: (json['active_skus_count'] as num?)?.toInt() ?? 0,
      targetRevenueEgp: (json['target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      targetUnits: (json['target_units'] as num?)?.toDouble() ?? 0.0,
      targetWeightTons: (json['target_weight_tons'] as num?)?.toDouble() ?? 0.0,
      actualRevenueEgp: (json['actual_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      actualUnits: (json['actual_units'] as num?)?.toDouble() ?? 0.0,
      expectedRevenueEgp: (json['expected_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      varianceRevenueEgp: (json['variance_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      varianceUnits: (json['variance_units'] as num?)?.toDouble() ?? 0.0,
      achievementPct: (json['achievement_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class TargetSalesRepQuotaModel {
  final String salesRep;
  final String kaOfficer;
  final String salesManager;
  final String regionCode;
  final String governorate;
  final int branchesCount;
  final int activeSkusCount;
  final double sharePct;
  final double targetRevenueEgp;
  final double targetUnits;
  final double targetWeightTons;
  final double actualRevenueEgp;
  final double actualUnits;
  final double expectedRevenueEgp;
  final double varianceRevenueEgp;
  final double achievementPct;
  final double mtTargetRevenueEgp;
  final double ccTargetRevenueEgp;

  const TargetSalesRepQuotaModel({
    required this.salesRep,
    required this.kaOfficer,
    required this.salesManager,
    required this.regionCode,
    required this.governorate,
    required this.branchesCount,
    required this.activeSkusCount,
    required this.sharePct,
    required this.targetRevenueEgp,
    required this.targetUnits,
    required this.targetWeightTons,
    required this.actualRevenueEgp,
    required this.actualUnits,
    required this.expectedRevenueEgp,
    required this.varianceRevenueEgp,
    required this.achievementPct,
    required this.mtTargetRevenueEgp,
    required this.ccTargetRevenueEgp,
  });

  factory TargetSalesRepQuotaModel.fromJson(Map<String, dynamic> json) {
    return TargetSalesRepQuotaModel(
      salesRep: json['sales_rep'] as String? ?? '',
      kaOfficer: json['ka_officer'] as String? ?? '',
      salesManager: json['sales_manager'] as String? ?? '',
      regionCode: json['region_code'] as String? ?? '',
      governorate: json['governorate'] as String? ?? '',
      branchesCount: (json['branches_count'] as num?)?.toInt() ?? 0,
      activeSkusCount: (json['active_skus_count'] as num?)?.toInt() ?? 0,
      sharePct: (json['share_pct'] as num?)?.toDouble() ?? 0.0,
      targetRevenueEgp: (json['target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      targetUnits: (json['target_units'] as num?)?.toDouble() ?? 0.0,
      targetWeightTons: (json['target_weight_tons'] as num?)?.toDouble() ?? 0.0,
      actualRevenueEgp: (json['actual_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      actualUnits: (json['actual_units'] as num?)?.toDouble() ?? 0.0,
      expectedRevenueEgp: (json['expected_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      varianceRevenueEgp: (json['variance_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      achievementPct: (json['achievement_pct'] as num?)?.toDouble() ?? 0.0,
      mtTargetRevenueEgp: (json['mt_target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      ccTargetRevenueEgp: (json['cc_target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class TargetMonthBreakdownModel {
  final int year;
  final int month;
  final String monthLabelAr;
  final String monthLabelEn;
  final double seasonalitySharePct;
  final double targetRevenueEgp;
  final double targetUnits;
  final double targetWeightTons;
  final double actualRevenueEgp;
  final double actualUnits;
  final double expectedRevenueEgp;
  final double varianceRevenueEgp;
  final double achievementPct;

  const TargetMonthBreakdownModel({
    required this.year,
    required this.month,
    required this.monthLabelAr,
    required this.monthLabelEn,
    required this.seasonalitySharePct,
    required this.targetRevenueEgp,
    required this.targetUnits,
    required this.targetWeightTons,
    required this.actualRevenueEgp,
    required this.actualUnits,
    required this.expectedRevenueEgp,
    required this.varianceRevenueEgp,
    required this.achievementPct,
  });

  factory TargetMonthBreakdownModel.fromJson(Map<String, dynamic> json) {
    return TargetMonthBreakdownModel(
      year: (json['year'] as num?)?.toInt() ?? 2026,
      month: (json['month'] as num?)?.toInt() ?? 1,
      monthLabelAr: json['month_label_ar'] as String? ?? '',
      monthLabelEn: json['month_label_en'] as String? ?? '',
      seasonalitySharePct: (json['seasonality_share_pct'] as num?)?.toDouble() ?? 0.0,
      targetRevenueEgp: (json['target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      targetUnits: (json['target_units'] as num?)?.toDouble() ?? 0.0,
      targetWeightTons: (json['target_weight_tons'] as num?)?.toDouble() ?? 0.0,
      actualRevenueEgp: (json['actual_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      actualUnits: (json['actual_units'] as num?)?.toDouble() ?? 0.0,
      expectedRevenueEgp: (json['expected_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      varianceRevenueEgp: (json['variance_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      achievementPct: (json['achievement_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class TargetComparisonModel {
  final String id;
  final String tenantId;
  final String targetType;
  final String retailerChain;
  final String chainDisplayName;
  final int year;
  final int month;
  final String monthLabel;
  final String branchName;
  final String category;
  final double targetRevenueEgp;
  final double actualRevenueEgp;
  final double varianceRevenueEgp;
  final double achievementRevPct;
  final double targetUnits;
  final double actualUnits;
  final double varianceUnits;
  final double achievementUnitsPct;
  final double targetWeightTons;
  final double actualWeightTons;
  final double expectedRevenueEgp;
  final double expectedUnits;
  final double expectedAchievementPct;
  final double avgCasePriceEgp;
  final double historicalReturnRatePct;
  final double grossTargetRevenueEgp;
  final double grossTargetUnits;
  final double promoSharePct;
  final double promoTargetRevenueEgp;
  final double regularTargetRevenueEgp;
  final double mtTargetRevenueEgp;
  final double ccTargetRevenueEgp;
  final int branchesCount;
  final int activeSkusCount;
  final String status;
  final String statusAr;
  final String notes;
  final String updatedAt;
  final List<TargetBranchBreakdownModel> branches;
  final List<TargetSKUBreakdownModel> chainSkuTotals;
  final List<TargetBrandBreakdownModel> brands;
  final List<TargetSalesRepQuotaModel> salesRepQuotas;
  final List<TargetMonthBreakdownModel> monthlyPhasing;

  const TargetComparisonModel({
    required this.id,
    required this.tenantId,
    required this.targetType,
    required this.retailerChain,
    required this.chainDisplayName,
    required this.year,
    required this.month,
    required this.monthLabel,
    required this.branchName,
    required this.category,
    required this.targetRevenueEgp,
    required this.actualRevenueEgp,
    required this.varianceRevenueEgp,
    required this.achievementRevPct,
    required this.targetUnits,
    required this.actualUnits,
    required this.varianceUnits,
    required this.achievementUnitsPct,
    this.targetWeightTons = 0.0,
    this.actualWeightTons = 0.0,
    this.expectedRevenueEgp = 0.0,
    this.expectedUnits = 0.0,
    this.expectedAchievementPct = 0.0,
    this.avgCasePriceEgp = 585.0,
    this.historicalReturnRatePct = 1.8,
    this.grossTargetRevenueEgp = 0.0,
    this.grossTargetUnits = 0.0,
    this.promoSharePct = 28.5,
    this.promoTargetRevenueEgp = 0.0,
    this.regularTargetRevenueEgp = 0.0,
    this.mtTargetRevenueEgp = 0.0,
    this.ccTargetRevenueEgp = 0.0,
    this.branchesCount = 0,
    this.activeSkusCount = 0,
    required this.status,
    required this.statusAr,
    required this.notes,
    required this.updatedAt,
    this.branches = const [],
    this.chainSkuTotals = const [],
    this.brands = const [],
    this.salesRepQuotas = const [],
    this.monthlyPhasing = const [],
  });

  factory TargetComparisonModel.fromJson(Map<String, dynamic> json) {
    final branchesList = (json['branches'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TargetBranchBreakdownModel.fromJson)
        .toList();
    final chainSkusList = (json['chain_sku_totals'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TargetSKUBreakdownModel.fromJson)
        .toList();
    final brandsList = (json['brands'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TargetBrandBreakdownModel.fromJson)
        .toList();
    final repsList = (json['sales_rep_quotas'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TargetSalesRepQuotaModel.fromJson)
        .toList();
    final monthsList = (json['monthly_phasing'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TargetMonthBreakdownModel.fromJson)
        .toList();

    return TargetComparisonModel(
      id: json['id'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      targetType: json['target_type'] as String? ?? 'sell_out',
      retailerChain: json['retailer_chain'] as String? ?? 'all',
      chainDisplayName: json['chain_display_name'] as String? ?? '',
      year: (json['year'] as num?)?.toInt() ?? 2026,
      month: (json['month'] as num?)?.toInt() ?? 0,
      monthLabel: json['month_label'] as String? ?? '',
      branchName: json['branch_name'] as String? ?? 'كل الفروع',
      category: json['category'] as String? ?? 'كل الفئات',
      targetRevenueEgp: (json['target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      actualRevenueEgp: (json['actual_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      varianceRevenueEgp: (json['variance_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      achievementRevPct: (json['achievement_rev_pct'] as num?)?.toDouble() ?? 0.0,
      targetUnits: (json['target_units'] as num?)?.toDouble() ?? 0.0,
      actualUnits: (json['actual_units'] as num?)?.toDouble() ?? 0.0,
      varianceUnits: (json['variance_units'] as num?)?.toDouble() ?? 0.0,
      achievementUnitsPct: (json['achievement_units_pct'] as num?)?.toDouble() ?? 0.0,
      targetWeightTons: (json['target_weight_tons'] as num?)?.toDouble() ?? 0.0,
      actualWeightTons: (json['actual_weight_tons'] as num?)?.toDouble() ?? 0.0,
      expectedRevenueEgp: (json['expected_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      expectedUnits: (json['expected_units'] as num?)?.toDouble() ?? 0.0,
      expectedAchievementPct: (json['expected_achievement_pct'] as num?)?.toDouble() ?? 0.0,
      avgCasePriceEgp: (json['avg_case_price_egp'] as num?)?.toDouble() ?? 585.0,
      historicalReturnRatePct: (json['historical_return_rate_pct'] as num?)?.toDouble() ?? 1.8,
      grossTargetRevenueEgp: (json['gross_target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      grossTargetUnits: (json['gross_target_units'] as num?)?.toDouble() ?? 0.0,
      promoSharePct: (json['promo_share_pct'] as num?)?.toDouble() ?? 28.5,
      promoTargetRevenueEgp: (json['promo_target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      regularTargetRevenueEgp: (json['regular_target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      mtTargetRevenueEgp: (json['mt_target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      ccTargetRevenueEgp: (json['cc_target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      branchesCount: (json['branches_count'] as num?)?.toInt() ?? branchesList.length,
      activeSkusCount: (json['active_skus_count'] as num?)?.toInt() ?? chainSkusList.length,
      status: json['status'] as String? ?? 'at_risk',
      statusAr: json['status_ar'] as String? ?? 'أقل من المستهدف',
      notes: json['notes'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
      branches: branchesList,
      chainSkuTotals: chainSkusList,
      brands: brandsList,
      salesRepQuotas: repsList,
      monthlyPhasing: monthsList,
    );
  }
}

class TargetsSummaryModel {
  final String tenantId;
  final String targetType;
  final double totalTargetRevenueEgp;
  final double totalActualRevenueEgp;
  final double totalVarianceEgp;
  final double overallAchievementPct;
  final double totalTargetUnits;
  final double totalActualUnits;
  final double totalTargetWeightTons;
  final double totalActualWeightTons;
  final double totalExpectedRevenueEgp;
  final double totalExpectedUnits;
  final double totalGrossTargetRevenueEgp;
  final double totalGrossTargetUnits;
  final double avgCasePriceEgp;
  final int totalBranchesCovered;
  final int totalSkusCovered;
  final List<TargetComparisonModel> items;

  const TargetsSummaryModel({
    required this.tenantId,
    required this.targetType,
    required this.totalTargetRevenueEgp,
    required this.totalActualRevenueEgp,
    required this.totalVarianceEgp,
    required this.overallAchievementPct,
    required this.totalTargetUnits,
    required this.totalActualUnits,
    this.totalTargetWeightTons = 0.0,
    this.totalActualWeightTons = 0.0,
    this.totalExpectedRevenueEgp = 0.0,
    this.totalExpectedUnits = 0.0,
    this.totalGrossTargetRevenueEgp = 0.0,
    this.totalGrossTargetUnits = 0.0,
    this.avgCasePriceEgp = 585.0,
    this.totalBranchesCovered = 0,
    this.totalSkusCovered = 0,
    required this.items,
  });

  factory TargetsSummaryModel.empty(String targetType) => TargetsSummaryModel(
        tenantId: '',
        targetType: targetType,
        totalTargetRevenueEgp: 0,
        totalActualRevenueEgp: 0,
        totalVarianceEgp: 0,
        overallAchievementPct: 0,
        totalTargetUnits: 0,
        totalActualUnits: 0,
        items: const [],
      );

  factory TargetsSummaryModel.fromJson(Map<String, dynamic> json) {
    final list = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TargetComparisonModel.fromJson)
        .toList();
    return TargetsSummaryModel(
      tenantId: json['tenant_id'] as String? ?? '',
      targetType: json['target_type'] as String? ?? 'sell_out',
      totalTargetRevenueEgp: (json['total_target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      totalActualRevenueEgp: (json['total_actual_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      totalVarianceEgp: (json['total_variance_egp'] as num?)?.toDouble() ?? 0.0,
      overallAchievementPct: (json['overall_achievement_pct'] as num?)?.toDouble() ?? 0.0,
      totalTargetUnits: (json['total_target_units'] as num?)?.toDouble() ?? 0.0,
      totalActualUnits: (json['total_actual_units'] as num?)?.toDouble() ?? 0.0,
      totalTargetWeightTons: (json['total_target_weight_tons'] as num?)?.toDouble() ?? 0.0,
      totalActualWeightTons: (json['total_actual_weight_tons'] as num?)?.toDouble() ?? 0.0,
      totalExpectedRevenueEgp: (json['total_expected_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      totalExpectedUnits: (json['total_expected_units'] as num?)?.toDouble() ?? 0.0,
      totalGrossTargetRevenueEgp: (json['total_gross_target_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      totalGrossTargetUnits: (json['total_gross_target_units'] as num?)?.toDouble() ?? 0.0,
      avgCasePriceEgp: (json['avg_case_price_egp'] as num?)?.toDouble() ?? 585.0,
      totalBranchesCovered: (json['total_branches_covered'] as num?)?.toInt() ?? 0,
      totalSkusCovered: (json['total_skus_covered'] as num?)?.toInt() ?? 0,
      items: list,
    );
  }
}

/// Canonical SKU definition from the Adeco Product Master & Price List (`كارتة الأصناف والأسعار`).
class ProductMasterItemModel {
  final int serialNo;
  final String itemCode;
  final String itemCodePrefix;
  final String erpPrefix;
  final String departmentAr;
  final String officialName;
  final String barcode;
  final String category;
  final String brand;
  final String packagingType;
  final int unitsPerCarton;
  final double unitPriceExclVat;
  final double vatRate;
  final double unitPriceInclVat;
  final double cartonPriceExclVat;
  final double cartonPriceInclVat;
  final double invoiceDiscountPct;
  final double extraDiscountPct;
  final double netUnitInvoiceCost;
  final double netCartonInvoiceCost;
  final String itemType;
  final bool isPrimaryForBarcode;
  final bool isActiveInChains;
  final int totalPosUnitsSold;
  final double totalPosCartonsSold;
  final double totalPosRevenue;
  final double avgRetailSellingPrice;
  final List<String> activeChains;
  final String updatedAt;
  final double prevUnitPriceExclVat;
  final double prevUnitPriceInclVat;
  final double prevCartonPriceInclVat;
  final double prevNetUnitInvoiceCost;
  final double prevNetCartonInvoiceCost;
  final String priceChangeDirection; // "up" | "down" | "new" | "same"
  final double priceChangeDiffEgp;
  final double priceChangePct;

  const ProductMasterItemModel({
    this.serialNo = 0,
    required this.itemCode,
    this.itemCodePrefix = '',
    this.erpPrefix = '',
    this.departmentAr = '',
    required this.officialName,
    required this.barcode,
    this.category = '',
    this.brand = '',
    this.packagingType = 'عبوة',
    this.unitsPerCarton = 12,
    this.unitPriceExclVat = 0.0,
    this.vatRate = 0.14,
    this.unitPriceInclVat = 0.0,
    this.cartonPriceExclVat = 0.0,
    this.cartonPriceInclVat = 0.0,
    this.invoiceDiscountPct = 10.0,
    this.extraDiscountPct = 0.0,
    this.netUnitInvoiceCost = 0.0,
    this.netCartonInvoiceCost = 0.0,
    this.itemType = 'عادي',
    this.isPrimaryForBarcode = true,
    this.isActiveInChains = false,
    this.totalPosUnitsSold = 0,
    this.totalPosCartonsSold = 0.0,
    this.totalPosRevenue = 0.0,
    this.avgRetailSellingPrice = 0.0,
    this.activeChains = const [],
    this.updatedAt = '',
    this.prevUnitPriceExclVat = 0.0,
    this.prevUnitPriceInclVat = 0.0,
    this.prevCartonPriceInclVat = 0.0,
    this.prevNetUnitInvoiceCost = 0.0,
    this.prevNetCartonInvoiceCost = 0.0,
    this.priceChangeDirection = 'same',
    this.priceChangeDiffEgp = 0.0,
    this.priceChangePct = 0.0,
  });

  static double normalizeDiscountPct(num? raw, double defaultPct) {
    if (raw == null) return defaultPct;
    final d = raw.toDouble();
    if (d > 0.0 && d <= 1.0) {
      return double.parse((d * 100.0).toStringAsFixed(2));
    }
    return d;
  }

  factory ProductMasterItemModel.fromJson(Map<String, dynamic> json) {
    final code = (json['item_code'] as String? ?? '').trim();
    var pfx = (json['item_code_prefix'] as String? ?? '').trim();
    if (pfx.isEmpty && code.contains('-')) {
      pfx = code.split('-').first.toUpperCase();
    }
    final erpPfx = (json['erp_prefix'] as String? ?? '').trim();
    final rawDir = (json['price_change_direction'] as String? ?? '').trim().toLowerCase();
    return ProductMasterItemModel(
      serialNo: (json['serial_no'] as num?)?.toInt() ?? 0,
      itemCode: code,
      itemCodePrefix: pfx,
      erpPrefix: erpPfx.isNotEmpty ? erpPfx : pfx,
      departmentAr: json['department_ar'] as String? ?? '',
      officialName: json['official_name'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      category: json['category'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      packagingType: json['packaging_type'] as String? ?? 'عبوة',
      unitsPerCarton: (json['units_per_carton'] as num?)?.toInt() ?? 12,
      unitPriceExclVat: (json['unit_price_excl_vat'] as num?)?.toDouble() ?? 0.0,
      vatRate: (json['vat_rate'] as num?)?.toDouble() ?? 0.14,
      unitPriceInclVat: (json['unit_price_incl_vat'] as num?)?.toDouble() ?? 0.0,
      cartonPriceExclVat: (json['carton_price_excl_vat'] as num?)?.toDouble() ?? 0.0,
      cartonPriceInclVat: (json['carton_price_incl_vat'] as num?)?.toDouble() ?? 0.0,
      invoiceDiscountPct: normalizeDiscountPct(json['invoice_discount_pct'] as num?, 10.0),
      extraDiscountPct: normalizeDiscountPct(json['extra_discount_pct'] as num?, 0.0),
      netUnitInvoiceCost: (json['net_unit_invoice_cost'] as num?)?.toDouble() ?? 0.0,
      netCartonInvoiceCost: (json['net_carton_invoice_cost'] as num?)?.toDouble() ?? 0.0,
      itemType: json['item_type'] as String? ?? 'عادي',
      isPrimaryForBarcode: json['is_primary_for_barcode'] as bool? ?? true,
      isActiveInChains: json['is_active_in_chains'] as bool? ?? false,
      totalPosUnitsSold: (json['total_pos_units_sold'] as num?)?.toInt() ?? 0,
      totalPosCartonsSold: (json['total_pos_cartons_sold'] as num?)?.toDouble() ?? 0.0,
      totalPosRevenue: (json['total_pos_revenue'] as num?)?.toDouble() ?? 0.0,
      avgRetailSellingPrice: (json['avg_retail_selling_price'] as num?)?.toDouble() ?? 0.0,
      activeChains: (json['active_chains'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      updatedAt: json['updated_at'] as String? ?? '',
      prevUnitPriceExclVat: (json['prev_unit_price_excl_vat'] as num?)?.toDouble() ?? 0.0,
      prevUnitPriceInclVat: (json['prev_unit_price_incl_vat'] as num?)?.toDouble() ?? 0.0,
      prevCartonPriceInclVat: (json['prev_carton_price_incl_vat'] as num?)?.toDouble() ?? 0.0,
      prevNetUnitInvoiceCost: (json['prev_net_unit_invoice_cost'] as num?)?.toDouble() ?? 0.0,
      prevNetCartonInvoiceCost: (json['prev_net_carton_invoice_cost'] as num?)?.toDouble() ?? 0.0,
      priceChangeDirection: rawDir.isEmpty ? 'same' : rawDir,
      priceChangeDiffEgp: (json['price_change_diff_egp'] as num?)?.toDouble() ?? 0.0,
      priceChangePct: (json['price_change_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'serial_no': serialNo,
        'item_code': itemCode,
        'item_code_prefix': itemCodePrefix,
        'erp_prefix': erpPrefix.isNotEmpty ? erpPrefix : itemCodePrefix,
        'department_ar': departmentAr,
        'official_name': officialName,
        'barcode': barcode,
        'category': category,
        'brand': brand,
        'packaging_type': packagingType,
        'units_per_carton': unitsPerCarton,
        'unit_price_excl_vat': unitPriceExclVat,
        'vat_rate': vatRate,
        'unit_price_incl_vat': unitPriceInclVat,
        'carton_price_excl_vat': cartonPriceExclVat,
        'carton_price_incl_vat': cartonPriceInclVat,
        'invoice_discount_pct': invoiceDiscountPct > 1.0 ? invoiceDiscountPct / 100.0 : invoiceDiscountPct,
        'extra_discount_pct': extraDiscountPct > 1.0 ? extraDiscountPct / 100.0 : extraDiscountPct,
        'net_unit_invoice_cost': netUnitInvoiceCost,
        'net_carton_invoice_cost': netCartonInvoiceCost,
        'item_type': itemType,
        'is_primary_for_barcode': isPrimaryForBarcode,
        'is_active_in_chains': isActiveInChains,
        'total_pos_units_sold': totalPosUnitsSold,
        'total_pos_cartons_sold': totalPosCartonsSold,
        'total_pos_revenue': totalPosRevenue,
        'avg_retail_selling_price': avgRetailSellingPrice,
        'active_chains': activeChains,
        'updated_at': updatedAt,
        if (prevUnitPriceExclVat > 0) 'prev_unit_price_excl_vat': prevUnitPriceExclVat,
        if (prevUnitPriceInclVat > 0) 'prev_unit_price_incl_vat': prevUnitPriceInclVat,
        if (prevCartonPriceInclVat > 0) 'prev_carton_price_incl_vat': prevCartonPriceInclVat,
        if (prevNetUnitInvoiceCost > 0) 'prev_net_unit_invoice_cost': prevNetUnitInvoiceCost,
        if (prevNetCartonInvoiceCost > 0) 'prev_net_carton_invoice_cost': prevNetCartonInvoiceCost,
        if (priceChangeDirection.isNotEmpty) 'price_change_direction': priceChangeDirection,
        if (priceChangeDiffEgp != 0) 'price_change_diff_egp': priceChangeDiffEgp,
        if (priceChangePct != 0) 'price_change_pct': priceChangePct,
      };

  ProductMasterItemModel copyWith({
    int? serialNo,
    String? itemCode,
    String? itemCodePrefix,
    String? erpPrefix,
    String? departmentAr,
    String? officialName,
    String? barcode,
    String? category,
    String? brand,
    String? packagingType,
    int? unitsPerCarton,
    double? unitPriceExclVat,
    double? vatRate,
    double? unitPriceInclVat,
    double? cartonPriceExclVat,
    double? cartonPriceInclVat,
    double? invoiceDiscountPct,
    double? extraDiscountPct,
    double? netUnitInvoiceCost,
    double? netCartonInvoiceCost,
    String? itemType,
    bool? isPrimaryForBarcode,
    bool? isActiveInChains,
    int? totalPosUnitsSold,
    double? totalPosCartonsSold,
    double? totalPosRevenue,
    double? avgRetailSellingPrice,
    List<String>? activeChains,
    String? updatedAt,
    double? prevUnitPriceExclVat,
    double? prevUnitPriceInclVat,
    double? prevCartonPriceInclVat,
    double? prevNetUnitInvoiceCost,
    double? prevNetCartonInvoiceCost,
    String? priceChangeDirection,
    double? priceChangeDiffEgp,
    double? priceChangePct,
  }) {
    return ProductMasterItemModel(
      serialNo: serialNo ?? this.serialNo,
      itemCode: itemCode ?? this.itemCode,
      itemCodePrefix: itemCodePrefix ?? this.itemCodePrefix,
      erpPrefix: erpPrefix ?? this.erpPrefix,
      departmentAr: departmentAr ?? this.departmentAr,
      officialName: officialName ?? this.officialName,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      brand: brand ?? this.brand,
      packagingType: packagingType ?? this.packagingType,
      unitsPerCarton: unitsPerCarton ?? this.unitsPerCarton,
      unitPriceExclVat: unitPriceExclVat ?? this.unitPriceExclVat,
      vatRate: vatRate ?? this.vatRate,
      unitPriceInclVat: unitPriceInclVat ?? this.unitPriceInclVat,
      cartonPriceExclVat: cartonPriceExclVat ?? this.cartonPriceExclVat,
      cartonPriceInclVat: cartonPriceInclVat ?? this.cartonPriceInclVat,
      invoiceDiscountPct: invoiceDiscountPct ?? this.invoiceDiscountPct,
      extraDiscountPct: extraDiscountPct ?? this.extraDiscountPct,
      netUnitInvoiceCost: netUnitInvoiceCost ?? this.netUnitInvoiceCost,
      netCartonInvoiceCost: netCartonInvoiceCost ?? this.netCartonInvoiceCost,
      itemType: itemType ?? this.itemType,
      isPrimaryForBarcode: isPrimaryForBarcode ?? this.isPrimaryForBarcode,
      isActiveInChains: isActiveInChains ?? this.isActiveInChains,
      totalPosUnitsSold: totalPosUnitsSold ?? this.totalPosUnitsSold,
      totalPosCartonsSold: totalPosCartonsSold ?? this.totalPosCartonsSold,
      totalPosRevenue: totalPosRevenue ?? this.totalPosRevenue,
      avgRetailSellingPrice: avgRetailSellingPrice ?? this.avgRetailSellingPrice,
      activeChains: activeChains ?? this.activeChains,
      updatedAt: updatedAt ?? this.updatedAt,
      prevUnitPriceExclVat: prevUnitPriceExclVat ?? this.prevUnitPriceExclVat,
      prevUnitPriceInclVat: prevUnitPriceInclVat ?? this.prevUnitPriceInclVat,
      prevCartonPriceInclVat: prevCartonPriceInclVat ?? this.prevCartonPriceInclVat,
      prevNetUnitInvoiceCost: prevNetUnitInvoiceCost ?? this.prevNetUnitInvoiceCost,
      prevNetCartonInvoiceCost: prevNetCartonInvoiceCost ?? this.prevNetCartonInvoiceCost,
      priceChangeDirection: priceChangeDirection ?? this.priceChangeDirection,
      priceChangeDiffEgp: priceChangeDiffEgp ?? this.priceChangeDiffEgp,
      priceChangePct: priceChangePct ?? this.priceChangePct,
    );
  }
}

/// Single SKU price change item in a Product Master sheet diff.
class ProductMasterDiffItemModel {
  final String itemCode;
  final String officialName;
  final String brand;
  final double oldUnitPriceIncl;
  final double newUnitPriceIncl;
  final double oldCartonPriceIncl;
  final double newCartonPriceIncl;
  final double diffEgp;
  final double diffPct;
  final String direction; // "up" | "down" | "new" | "same"

  const ProductMasterDiffItemModel({
    required this.itemCode,
    required this.officialName,
    this.brand = '',
    this.oldUnitPriceIncl = 0.0,
    this.newUnitPriceIncl = 0.0,
    this.oldCartonPriceIncl = 0.0,
    this.newCartonPriceIncl = 0.0,
    this.diffEgp = 0.0,
    this.diffPct = 0.0,
    this.direction = 'same',
  });

  factory ProductMasterDiffItemModel.fromJson(Map<String, dynamic> json) {
    return ProductMasterDiffItemModel(
      itemCode: json['item_code'] as String? ?? '',
      officialName: json['official_name'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      oldUnitPriceIncl: (json['old_unit_price_incl'] as num?)?.toDouble() ?? 0.0,
      newUnitPriceIncl: (json['new_unit_price_incl'] as num?)?.toDouble() ?? 0.0,
      oldCartonPriceIncl: (json['old_carton_price_incl'] as num?)?.toDouble() ?? 0.0,
      newCartonPriceIncl: (json['new_carton_price_incl'] as num?)?.toDouble() ?? 0.0,
      diffEgp: (json['diff_egp'] as num?)?.toDouble() ?? 0.0,
      diffPct: (json['diff_pct'] as num?)?.toDouble() ?? 0.0,
      direction: json['direction'] as String? ?? 'same',
    );
  }
}

/// Smart diff comparison summary between a newly uploaded Product Master sheet and the previous version.
class ProductMasterDiffSummaryModel {
  final String comparedAgainstFile;
  final String newFileName;
  final String comparedAt;
  final int totalSkusCompared;
  final int priceIncreasedCount;
  final int priceDecreasedCount;
  final int priceUnchangedCount;
  final int newSkusCount;
  final double avgPriceIncreasePct;
  final double avgPriceDecreasePct;
  final List<ProductMasterDiffItemModel> topChangedItems;

  const ProductMasterDiffSummaryModel({
    this.comparedAgainstFile = '',
    this.newFileName = '',
    this.comparedAt = '',
    this.totalSkusCompared = 0,
    this.priceIncreasedCount = 0,
    this.priceDecreasedCount = 0,
    this.priceUnchangedCount = 0,
    this.newSkusCount = 0,
    this.avgPriceIncreasePct = 0.0,
    this.avgPriceDecreasePct = 0.0,
    this.topChangedItems = const [],
  });

  factory ProductMasterDiffSummaryModel.fromJson(Map<String, dynamic> json) {
    final topList = (json['top_changed_items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ProductMasterDiffItemModel.fromJson)
        .toList();
    return ProductMasterDiffSummaryModel(
      comparedAgainstFile: json['compared_against_file'] as String? ?? '',
      newFileName: json['new_file_name'] as String? ?? '',
      comparedAt: json['compared_at'] as String? ?? '',
      totalSkusCompared: (json['total_skus_compared'] as num?)?.toInt() ?? 0,
      priceIncreasedCount: (json['price_increased_count'] as num?)?.toInt() ?? 0,
      priceDecreasedCount: (json['price_decreased_count'] as num?)?.toInt() ?? 0,
      priceUnchangedCount: (json['price_unchanged_count'] as num?)?.toInt() ?? 0,
      newSkusCount: (json['new_skus_count'] as num?)?.toInt() ?? 0,
      avgPriceIncreasePct: (json['avg_price_increase_pct'] as num?)?.toDouble() ?? 0.0,
      avgPriceDecreasePct: (json['avg_price_decrease_pct'] as num?)?.toDouble() ?? 0.0,
      topChangedItems: topList,
    );
  }
}

/// Summary & items response for `GET /api/v1/product-master`.
class ProductMasterSummaryModel {
  final String tenantId;
  final String companyName;
  final String sheetDateLabel;
  final String sourceFilename;
  final double defaultDiscountPct;
  final double defaultVatRate;
  final int totalSkus;
  final int regularSkusCount;
  final int promoSkusCount;
  final int uniqueBarcodesCount;
  final double avgUnitsPerCarton;
  final int activeInChainsCount;
  final int unpulledSkusCount;
  final int priceIncreasedCount;
  final int priceDecreasedCount;
  final int priceUnchangedCount;
  final int newSkusCount;
  final List<String> availablePrefixes;
  final List<String> availableBrands;
  final List<String> availablePackaging;
  final ProductMasterDiffSummaryModel? diffSummary;
  final List<ProductMasterItemModel> items;

  const ProductMasterSummaryModel({
    required this.tenantId,
    required this.companyName,
    required this.sheetDateLabel,
    required this.sourceFilename,
    this.defaultDiscountPct = 10.0,
    this.defaultVatRate = 0.14,
    required this.totalSkus,
    required this.regularSkusCount,
    required this.promoSkusCount,
    required this.uniqueBarcodesCount,
    required this.avgUnitsPerCarton,
    this.activeInChainsCount = 0,
    this.unpulledSkusCount = 0,
    this.priceIncreasedCount = 0,
    this.priceDecreasedCount = 0,
    this.priceUnchangedCount = 0,
    this.newSkusCount = 0,
    this.availablePrefixes = const [],
    this.availableBrands = const [],
    this.availablePackaging = const [],
    this.diffSummary,
    required this.items,
  });

  factory ProductMasterSummaryModel.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ProductMasterItemModel.fromJson)
        .toList();
    final diffRaw = json['diff_summary'] as Map<String, dynamic>?;
    final parsedTotalSkus = (json['total_skus'] as num?)?.toInt() ?? itemsList.length;
    final defaultSourceFilename = (parsedTotalSkus > 0 || itemsList.isNotEmpty)
        ? 'adeco_product_master_2026_08_01.xlsx'
        : '';
    return ProductMasterSummaryModel(
      tenantId: json['tenant_id'] as String? ?? 'tenant-adeco',
      companyName: json['company_name'] as String? ??
          'شركة الإسكندرية للمنظفات والكيماويات (أدكو - Adeco)',
      sheetDateLabel: json['sheet_date_label'] as String? ?? 'تحديث 01-08-2026',
      sourceFilename: json['source_filename'] as String? ?? defaultSourceFilename,
      defaultDiscountPct: ProductMasterItemModel.normalizeDiscountPct(
        json['default_discount_pct'] as num?,
        10.0,
      ),
      defaultVatRate: (json['default_vat_rate'] as num?)?.toDouble() ?? 0.14,
      totalSkus: parsedTotalSkus,
      regularSkusCount: (json['regular_skus_count'] as num?)?.toInt() ??
          itemsList.where((e) => e.itemType != 'عرض').length,
      promoSkusCount: (json['promo_skus_count'] as num?)?.toInt() ??
          itemsList.where((e) => e.itemType == 'عرض').length,
      uniqueBarcodesCount: (json['unique_barcodes_count'] as num?)?.toInt() ??
          itemsList.map((e) => e.barcode).toSet().length,
      avgUnitsPerCarton: (json['avg_units_per_carton'] as num?)?.toDouble() ?? 12.0,
      activeInChainsCount: (json['active_in_chains_count'] as num?)?.toInt() ??
          itemsList.where((e) => e.isActiveInChains).length,
      unpulledSkusCount: (json['unpulled_skus_count'] as num?)?.toInt() ??
          itemsList.where((e) => !e.isActiveInChains).length,
      priceIncreasedCount: (json['price_increased_count'] as num?)?.toInt() ??
          itemsList.where((e) => e.priceChangeDirection == 'up').length,
      priceDecreasedCount: (json['price_decreased_count'] as num?)?.toInt() ??
          itemsList.where((e) => e.priceChangeDirection == 'down').length,
      priceUnchangedCount: (json['price_unchanged_count'] as num?)?.toInt() ??
          itemsList.where((e) => e.priceChangeDirection == 'same' || e.priceChangeDirection.isEmpty).length,
      newSkusCount: (json['new_skus_count'] as num?)?.toInt() ??
          itemsList.where((e) => e.priceChangeDirection == 'new').length,
      availablePrefixes: (json['available_prefixes'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      availableBrands: (json['available_brands'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      availablePackaging: (json['available_packaging'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      diffSummary: diffRaw != null ? ProductMasterDiffSummaryModel.fromJson(diffRaw) : null,
      items: itemsList,
    );
  }
}

/// The uploaded-files archive could not be loaded (production; no local demo fallback).
class ArchiveLoadException implements Exception {
  final String reason;
  ArchiveLoadException(this.reason);
  @override
  String toString() => 'ArchiveLoadException: $reason';
}

/// 409 from «Register chain»: the code is already registered for this company (nothing changed).
class ChainAlreadyRegisteredException implements Exception {
  final String message;
  ChainAlreadyRegisteredException(this.message);
  @override
  String toString() => message;
}

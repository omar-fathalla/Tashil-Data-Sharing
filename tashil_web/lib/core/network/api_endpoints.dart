import 'dart:async';

class ApiEndpoints {
  ApiEndpoints._();

  /// Unified Cloud Run production backend URL (Single Source of Truth across
  /// Web custom domains like data.sw-com, Firebase Hosting, Antigravity IDE localhost, and Android APK).
  static const String cloudBackendUrl =
      'https://tashil-backend-564362209163.europe-west1.run.app';

  static String get baseUrl {
    const envUrl = String.fromEnvironment('BACKEND_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }
    if (Zone.current[#test.invoker] != null) {
      return 'http://localhost:8080';
    }
    return cloudBackendUrl;
  }

  static String get health => '$baseUrl/healthz';
  static String get upload => '$baseUrl/api/v1/ingest/upload';
  static String get ingestCommit => '$baseUrl/api/v1/ingest/commit';
  static String get ingestDiscard => '$baseUrl/api/v1/ingest/discard';
  static String get ingestArchive => '$baseUrl/api/v1/ingest/archive';
  static String ingestArchiveItem(String archiveId) =>
      '$baseUrl/api/v1/ingest/archive/${Uri.encodeComponent(archiveId)}';
  static String ingestArchiveDownload(String archiveId) =>
      '$baseUrl/api/v1/ingest/archive/${Uri.encodeComponent(archiveId)}/download';
  static String get clearData => '$baseUrl/api/v1/ingest/clear';
  static String get loadDefaultExcel => '$baseUrl/api/v1/ingest/load-default-excel';
  static String get loadSellInPlan => '$baseUrl/api/v1/ingest/load-sell-in-plan';
  static String get executiveSummary => '$baseUrl/api/v1/analytics/executive-summary';
  static String get records => '$baseUrl/api/v1/analytics/records';
  static String get sellInRecords => '$baseUrl/api/v1/analytics/sell-in-records';
  static String get targets => '$baseUrl/api/v1/analytics/targets';
  static String get targetsUpload => '$baseUrl/api/v1/analytics/targets/upload';
  static String get storeMatrix => '$baseUrl/api/v1/analytics/store-matrix';
  static String get pricingCompliance => '$baseUrl/api/v1/analytics/pricing-compliance';
  static String get cpfrDashboard => '$baseUrl/api/v1/analytics/cpfr';
  static String get oosMonitor => '$baseUrl/api/v1/analytics/oos-monitor';
  static String get productMaster => '$baseUrl/api/v1/product-master';
  static String get productMasterItem => '$baseUrl/api/v1/product-master/item';
  static String get productMasterUpload => '$baseUrl/api/v1/product-master/upload';
  static String get stores => '$baseUrl/api/v1/stores';
  static String get tenants => '$baseUrl/api/v1/tenants';
  static String get batches => '$baseUrl/api/v1/batches';

  // Auth & Multi-tenant Routing Endpoints
  static String get authLogin => '$baseUrl/api/v1/auth/login';
  static String get authForgotPassword => '$baseUrl/api/v1/auth/forgot-password';
  static String get authResetPassword => '$baseUrl/api/v1/auth/reset-password';
  static String get authChangePassword => '$baseUrl/api/v1/auth/change-password';
  static String portalMeta(String slug) => '$baseUrl/api/v1/portal/$slug/meta';

  // Super Admin Provisioning & Security Audit Endpoints
  static String get adminTenants => '$baseUrl/api/v1/admin/tenants';
  static String adminResetPassword(String tenantId) => '$baseUrl/api/v1/admin/tenants/$tenantId/reset-password';
  static String get adminChains => '$baseUrl/api/v1/admin/chains';
  static String get auditLogs => '$baseUrl/api/v1/audit/logs';
}

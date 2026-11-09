import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/backend_http.dart';

class BranchMasterBranch {
  final String code;
  final String chainCode;
  final String displayName;
  final bool active;
  final bool unallocated;

  const BranchMasterBranch({
    required this.code,
    required this.chainCode,
    required this.displayName,
    this.active = true,
    this.unallocated = false,
  });

  factory BranchMasterBranch.fromJson(Map<String, dynamic> j) => BranchMasterBranch(
        code: '${j['code'] ?? ''}',
        chainCode: '${j['chain_code'] ?? ''}',
        displayName: '${j['display_name'] ?? ''}',
        active: j['active'] != false,
        unallocated: j['unallocated'] == true,
      );
}

class BranchMasterAlias {
  final String rawName;
  final String branchCode;
  final String source;
  final double confidence;

  const BranchMasterAlias({
    required this.rawName,
    required this.branchCode,
    this.source = '',
    this.confidence = 0,
  });

  factory BranchMasterAlias.fromJson(Map<String, dynamic> j) => BranchMasterAlias(
        rawName: '${j['raw_name'] ?? ''}',
        branchCode: '${j['branch_code'] ?? ''}',
        source: '${j['source'] ?? ''}',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      );
}

class BranchMasterPending {
  final String id;
  final String rawName;
  final String suggestedCode;
  final String suggestedName;
  final String altSuggestedCode;
  final String altSuggestedName;
  final double confidence;
  final String reasonAr;
  final String kind;

  const BranchMasterPending({
    required this.id,
    required this.rawName,
    this.suggestedCode = '',
    this.suggestedName = '',
    this.altSuggestedCode = '',
    this.altSuggestedName = '',
    this.confidence = 0,
    this.reasonAr = '',
    this.kind = '',
  });

  factory BranchMasterPending.fromJson(Map<String, dynamic> j) => BranchMasterPending(
        id: '${j['id'] ?? ''}',
        rawName: '${j['raw_name'] ?? ''}',
        suggestedCode: '${j['suggested_code'] ?? ''}',
        suggestedName: '${j['suggested_name'] ?? ''}',
        altSuggestedCode: '${j['alt_suggested_code'] ?? ''}',
        altSuggestedName: '${j['alt_suggested_name'] ?? ''}',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        reasonAr: '${j['reason_ar'] ?? ''}',
        kind: '${j['kind'] ?? ''}',
      );
}

class BranchMasterState {
  final List<BranchMasterBranch> branches;
  final List<BranchMasterAlias> aliases;
  final List<BranchMasterPending> pending;
  final bool bootstrapDone;

  const BranchMasterState({
    this.branches = const [],
    this.aliases = const [],
    this.pending = const [],
    this.bootstrapDone = false,
  });

  factory BranchMasterState.fromJson(Map<String, dynamic> j) => BranchMasterState(
        branches: [
          for (final e in (j['branches'] as List?) ?? const [])
            if (e is Map) BranchMasterBranch.fromJson(Map<String, dynamic>.from(e)),
        ],
        aliases: [
          for (final e in (j['aliases'] as List?) ?? const [])
            if (e is Map) BranchMasterAlias.fromJson(Map<String, dynamic>.from(e)),
        ],
        pending: [
          for (final e in (j['pending'] as List?) ?? const [])
            if (e is Map) BranchMasterPending.fromJson(Map<String, dynamic>.from(e)),
        ],
        bootstrapDone: j['bootstrap_done'] == true,
      );
}

abstract class BranchMasterDataSource {
  Future<BranchMasterState> load();
  Future<void> updateDisplayName(String branchCode, String displayName);
  Future<void> confirmPending(String pendingId, {String branchCode = '', String newDisplayName = ''});
  Future<void> rejectPending(String pendingId);
}

class HttpBranchMasterDataSource implements BranchMasterDataSource {
  final ApiClient api;
  HttpBranchMasterDataSource(this.api);

  @override
  Future<BranchMasterState> load() async {
    final res = await BackendHttp.get(Uri.parse(ApiEndpoints.branchMaster), headers: api.requestHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('تعذر تحميل بيانات الفروع (HTTP ${res.statusCode})');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return BranchMasterState.fromJson(j);
  }

  @override
  Future<void> updateDisplayName(String branchCode, String displayName) async {
    final res = await BackendHttp.put(
      Uri.parse(ApiEndpoints.branches),
      headers: {...api.requestHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'branch_code': branchCode, 'display_name': displayName}),
    ).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('تعذر تحديث الاسم (HTTP ${res.statusCode})');
    }
  }

  @override
  Future<void> confirmPending(String pendingId, {String branchCode = '', String newDisplayName = ''}) async {
    final res = await BackendHttp.post(
      Uri.parse(ApiEndpoints.branchPendingConfirm),
      headers: {...api.requestHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'pending_id': pendingId,
        'branch_code': branchCode,
        if (newDisplayName.isNotEmpty) 'new_display_name': newDisplayName,
      }),
    ).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('تعذر تأكيد الفرع (HTTP ${res.statusCode})');
    }
  }

  @override
  Future<void> rejectPending(String pendingId) async {
    final res = await BackendHttp.post(
      Uri.parse(ApiEndpoints.branchPendingReject),
      headers: {...api.requestHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'pending_id': pendingId}),
    ).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('تعذر رفض الاقتراح (HTTP ${res.statusCode})');
    }
  }
}

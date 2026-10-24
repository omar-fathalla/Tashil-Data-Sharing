import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_card.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/app_version.dart';
import '../../../../core/network/api_endpoints.dart';

/// Release name of the current web build.
const String kReleaseName = 'ميكول';

/// Super Admin "System version" card: release, web version and the live
/// backend version/commit/revision fetched from GET /api/v1/version.
class SystemVersionCard extends StatefulWidget {
  const SystemVersionCard({super.key, this.fetch});

  /// Optional override for tests.
  final Future<Map<String, dynamic>> Function()? fetch;

  @override
  State<SystemVersionCard> createState() => _SystemVersionCardState();
}

class _SystemVersionCardState extends State<SystemVersionCard> {
  Map<String, dynamic>? _backend;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _defaultFetch() async {
    final resp = await http
        .get(Uri.parse('${ApiEndpoints.baseUrl}/api/v1/version'))
        .timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) throw Exception('status ${resp.statusCode}');
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> _load() async {
    try {
      final data = await (widget.fetch ?? _defaultFetch)();
      if (mounted) setState(() => _backend = data);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    String b(String k) =>
        _backend?[k]?.toString() ?? (_failed ? 'unavailable' : '…');
    final rows = <MapEntry<String, String>>[
      MapEntry('Release', _backend?['release']?.toString() ?? kReleaseName),
      MapEntry('Web version', AppVersion.label),
      MapEntry('Backend version', b('backend_version')),
      MapEntry('Backend revision', b('revision')),
      MapEntry('Backend commit', b('git_commit')),
    ];
    return M3Card.outlined(
      key: const ValueKey('system-version-card'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(AppIcons.info, color: cs.primary),
            const SizedBox(width: 8),
            Text('System version',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              for (final r in rows)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.key,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    SelectableText(r.value,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

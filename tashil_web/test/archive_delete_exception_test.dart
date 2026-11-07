import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';

void main() {
  group('ArchiveDeleteException', () {
    test('parses API forbidden body used by archive delete gate', () {
      final ex = ArchiveDeleteException.fromResponse(
        403,
        jsonEncode({
          'error':
              'Forbidden: your role cannot perform this action (role=vendor_admin; archive delete and clear require super_admin)',
        }),
      );
      expect(ex.statusCode, 403);
      expect(ex.message.toLowerCase(), contains('super_admin'));
      expect(ex.toString(), ex.message);
    });

    test('prefers message field when present', () {
      final ex = ArchiveDeleteException.fromResponse(
        502,
        jsonEncode({
          'error': 'archive_delete_analytics_failed',
          'message':
              'bigquery: failed to remove analytics rows from BigQuery; archive file was left listed',
        }),
      );
      expect(ex.errorCode, 'archive_delete_analytics_failed');
      expect(ex.message, contains('BigQuery'));
    });

    test('falls back for non-json bodies', () {
      final ex = ArchiveDeleteException.fromResponse(500, 'boom');
      expect(ex.message, 'boom');
    });
  });
}

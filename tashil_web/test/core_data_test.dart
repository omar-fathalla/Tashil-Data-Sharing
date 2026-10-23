import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tashil_web/core/data/cache_store.dart';
import 'package:tashil_web/core/data/result.dart';

class _StatusErr implements Exception {
  final int statusCode;
  _StatusErr(this.statusCode);
  @override
  String toString() => 'status $statusCode';
}

void main() {
  group('Result', () {
    test('map / when / getOrElse on Success', () {
      const Result<int> r = Success(2);
      expect(r.isSuccess, isTrue);
      expect(r.map((v) => v * 3).valueOrNull, 6);
      expect(r.when(success: (v) => 'ok$v', failure: (_) => 'ko'), 'ok2');
      expect(r.getOrElse((_) => 0), 2);
      expect(r.errorOrNull, isNull);
    });

    test('map keeps Failure, getOrElse falls back', () {
      const Result<int> r = Failure(AppError.validation('bad'));
      final m = r.map((v) => v.toString());
      expect(m, isA<Failure<String>>());
      expect(m.errorOrNull!.kind, AppErrorKind.validation);
      expect(r.getOrElse((_) => -1), -1);
      expect(r.when(success: (_) => 'ok', failure: (e) => e.message), 'bad');
    });

    test('guard wraps values and classifies errors', () async {
      expect((await Result.guard(() async => 5)).valueOrNull, 5);
      expect((await Result.guard<int>(() async => throw TimeoutException('t'))).errorOrNull!.kind,
          AppErrorKind.network);
      expect((await Result.guard<int>(() async => throw http.ClientException('x'))).errorOrNull!.isNetwork,
          isTrue);
      expect((await Result.guard<int>(() async => throw _StatusErr(401))).errorOrNull!.isAuth, isTrue);
      expect((await Result.guard<int>(() async => throw _StatusErr(503))).errorOrNull!.kind, AppErrorKind.server);
      expect((await Result.guard<int>(() async => throw StateError('s'))).errorOrNull!.kind, AppErrorKind.unknown);
    });

    test('fromStatus mapping', () {
      expect(AppError.fromStatus(403, '').kind, AppErrorKind.auth);
      expect(AppError.fromStatus(404, '').kind, AppErrorKind.notFound);
      expect(AppError.fromStatus(422, '').kind, AppErrorKind.validation);
      expect(AppError.fromStatus(500, '').kind, AppErrorKind.server);
    });
  });

  group('CacheStore', () {
    test('ttl expiry with injected clock', () {
      var now = DateTime(2026, 1, 1);
      final c = CacheStore(defaultTtl: const Duration(minutes: 1), clock: () => now);
      c.put('a', 1);
      expect(c.get<int>('a'), 1);
      now = now.add(const Duration(seconds: 59));
      expect(c.get<int>('a'), 1);
      now = now.add(const Duration(seconds: 1));
      expect(c.get<int>('a'), isNull);
      expect(c.length, 0);
    });

    test('tenant-aware keys, invalidate and invalidatePrefix', () {
      final c = CacheStore();
      final a1 = CacheStore.key('t1', 'f', ['x', 2026]);
      final a2 = CacheStore.key('t1', 'f', ['y', null]);
      final b1 = CacheStore.key('t2', 'f', ['x', 2026]);
      expect(a1, isNot(b1));
      c..put(a1, 1)..put(a2, 2)..put(b1, 3);
      c.invalidate(a2);
      expect(c.contains(a2), isFalse);
      c.invalidatePrefix(CacheStore.prefix('t1', 'f'));
      expect(c.contains(a1), isFalse);
      expect(c.get<int>(b1), 3);
    });

    test('getOrLoad loads once', () async {
      final c = CacheStore();
      var calls = 0;
      Future<int> load() async => ++calls;
      expect(await c.getOrLoad('k', load), 1);
      expect(await c.getOrLoad('k', load), 1);
      expect(calls, 1);
    });
  });
}

import 'dart:async';

import 'package:http/http.dart' as http;

/// Category of an [AppError], used by screens to pick a message / recovery action.
enum AppErrorKind { network, auth, validation, notFound, server, unknown }

/// Typed error carried by a [Failure].
class AppError {
  final AppErrorKind kind;
  final String message;
  final int? statusCode;
  final Object? cause;

  const AppError(this.kind, this.message, {this.statusCode, this.cause});

  const AppError.network([String message = 'تعذر الاتصال بالخادم / Could not reach the server', Object? cause])
      : this(AppErrorKind.network, message, cause: cause);
  const AppError.auth([String message = 'غير مصرح / Unauthorized', int? statusCode = 401])
      : this(AppErrorKind.auth, message, statusCode: statusCode);
  const AppError.validation(String message) : this(AppErrorKind.validation, message, statusCode: 400);
  const AppError.unknown(String message, [Object? cause]) : this(AppErrorKind.unknown, message, cause: cause);

  /// Maps an HTTP status code to an error kind.
  factory AppError.fromStatus(int status, String message) {
    final AppErrorKind kind;
    if (status == 401 || status == 403) {
      kind = AppErrorKind.auth;
    } else if (status == 404) {
      kind = AppErrorKind.notFound;
    } else if (status == 400 || status == 409 || status == 422) {
      kind = AppErrorKind.validation;
    } else if (status >= 500) {
      kind = AppErrorKind.server;
    } else {
      kind = AppErrorKind.unknown;
    }
    return AppError(kind, message, statusCode: status);
  }

  /// Best-effort classification of an arbitrary thrown object.
  factory AppError.from(Object e) {
    if (e is AppError) return e;
    if (e is TimeoutException || e is http.ClientException) {
      return AppError.network('تعذر الاتصال بالخادم / Could not reach the server', e);
    }
    if (e is FormatException) return AppError(AppErrorKind.validation, e.message, cause: e);
    try {
      final status = (e as dynamic).statusCode;
      if (status is int) return AppError.fromStatus(status, e.toString())._withCause(e);
    } catch (_) {}
    final s = e.toString();
    if (s.contains('ClientException') || s.contains('Failed to fetch') || s.contains('XMLHttpRequest')) {
      return AppError.network('تعذر الاتصال بالخادم / Could not reach the server', e);
    }
    return AppError.unknown(s, e);
  }

  AppError _withCause(Object c) => AppError(kind, message, statusCode: statusCode, cause: c);

  bool get isNetwork => kind == AppErrorKind.network;
  bool get isAuth => kind == AppErrorKind.auth;

  @override
  String toString() => message;
}

/// Outcome of a repository call: either [Success] with a value or [Failure] with an [AppError].
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;
  T? get valueOrNull => switch (this) { Success(:final value) => value, Failure() => null };
  AppError? get errorOrNull => switch (this) { Success() => null, Failure(:final error) => error };

  R when<R>({required R Function(T value) success, required R Function(AppError error) failure}) =>
      switch (this) { Success(:final value) => success(value), Failure(:final error) => failure(error) };

  Result<R> map<R>(R Function(T value) f) =>
      switch (this) { Success(:final value) => Success(f(value)), Failure(:final error) => Failure(error) };

  T getOrElse(T Function(AppError error) orElse) =>
      switch (this) { Success(:final value) => value, Failure(:final error) => orElse(error) };

  /// Runs [body] and wraps its value or any thrown error.
  static Future<Result<T>> guard<T>(Future<T> Function() body) async {
    try {
      return Success(await body());
    } catch (e) {
      return Failure(AppError.from(e));
    }
  }
}

final class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

final class Failure<T> extends Result<T> {
  final AppError error;
  const Failure(this.error);
}

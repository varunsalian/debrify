import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../profiles/profile_async_authorization.dart';
import 'mdblist_models.dart';

typedef MdblistApiKeyProvider = Future<String?> Function();

class MdblistTransport {
  final http.Client client;
  final MdblistApiKeyProvider apiKeyProvider;
  final bool Function() featureEnabled;
  final Uri baseUri;
  final Duration timeout;

  MdblistTransport({
    required this.client,
    required this.apiKeyProvider,
    required this.featureEnabled,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 20),
  }) : baseUri = baseUri ?? Uri.parse('https://api.mdblist.com');

  Future<MdblistResult<dynamic>> request(
    String method,
    String path, {
    Map<String, Object?> query = const {},
    Object? body,
    ProfileAsyncAuthorization? capability,
    bool allowWhenDisabled = false,
    bool allowNotFound = false,
  }) async {
    if (!allowWhenDisabled && !featureEnabled()) {
      return const MdblistResult.failure(MdblistResultKind.disabled);
    }
    final key = (await apiKeyProvider())?.trim();
    if (key == null || key.isEmpty) {
      return const MdblistResult.failure(MdblistResultKind.unauthenticated);
    }

    Future<http.Response> send() async {
      final params = <String, String>{
        for (final entry in query.entries)
          if (entry.value != null) entry.key: entry.value.toString(),
        'apikey': key,
      };
      final uri = baseUri.replace(
        path: path.startsWith('/') ? path : '/$path',
        queryParameters: params,
      );
      final headers = body == null
          ? const <String, String>{}
          : const {'Content-Type': 'application/json'};
      final encoded = body == null ? null : jsonEncode(body);
      switch (method.toUpperCase()) {
        case 'GET':
          return client.get(uri, headers: headers).timeout(timeout);
        case 'POST':
          return client
              .post(uri, headers: headers, body: encoded)
              .timeout(timeout);
        case 'PUT':
          return client
              .put(uri, headers: headers, body: encoded)
              .timeout(timeout);
        case 'PATCH':
          return client
              .patch(uri, headers: headers, body: encoded)
              .timeout(timeout);
        case 'DELETE':
          return client
              .delete(uri, headers: headers, body: encoded)
              .timeout(timeout);
        default:
          throw ArgumentError.value(method, 'method');
      }
    }

    try {
      final response = capability == null
          ? await send()
          : await capability.runIfCurrentAsOutbound(send);
      final status = response.statusCode;
      if (status == 401) {
        return MdblistResult.failure(
          MdblistResultKind.unauthenticated,
          statusCode: status,
        );
      }
      if (status == 403) {
        return MdblistResult.failure(
          MdblistResultKind.denied,
          statusCode: status,
        );
      }
      if (status == 404) {
        return MdblistResult.failure(
          allowNotFound
              ? MdblistResultKind.notFound
              : MdblistResultKind.notFound,
          statusCode: status,
        );
      }
      if (status == 409) {
        return MdblistResult.failure(
          MdblistResultKind.conflict,
          statusCode: status,
        );
      }
      if (status == 429) {
        return MdblistResult.failure(
          MdblistResultKind.rateLimited,
          statusCode: status,
          retryAfter: _retryAfter(response.headers['retry-after']),
        );
      }
      if (status < 200 || status >= 300) {
        return MdblistResult.failure(
          MdblistResultKind.transientFailure,
          statusCode: status,
        );
      }
      if (response.body.trim().isEmpty) {
        return MdblistResult.success(
          null,
          statusCode: status,
          headers: response.headers,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map &&
          (decoded['error'] != null || decoded['response'] == false)) {
        return MdblistResult.failure(
          MdblistResultKind.malformedResponse,
          statusCode: status,
        );
      }
      return MdblistResult.success(
        decoded,
        statusCode: status,
        headers: response.headers,
      );
    } on TimeoutException {
      return const MdblistResult.failure(MdblistResultKind.transientFailure);
    } on FormatException {
      return const MdblistResult.failure(MdblistResultKind.malformedResponse);
    } catch (_) {
      return const MdblistResult.failure(MdblistResultKind.transientFailure);
    }
  }

  Duration? _retryAfter(String? raw) {
    final seconds = int.tryParse(raw ?? '');
    if (seconds != null) return Duration(seconds: seconds);
    final date = raw == null ? null : DateTime.tryParse(raw)?.toUtc();
    if (date == null) return null;
    final delay = date.difference(DateTime.now().toUtc());
    return delay.isNegative ? Duration.zero : delay;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Credentials consumed by the profile-independent WebDAV protocol layer.
///
/// Profile-facing callers must authorize access to the connection resource
/// before constructing this value. The future sync engine intentionally uses
/// the same client with its device-owned, sealed credentials.
final class WebDavCredentials {
  const WebDavCredentials({required this.username, required this.password});

  final String username;
  final String password;

  bool get isEmpty => username.isEmpty && password.isEmpty;
}

enum WebDavErrorKind {
  authentication,
  notFound,
  conflict,
  preconditionFailed,
  quota,
  transient,
  timeout,
  network,
  tls,
  malformedResponse,
  unsafeRedirect,
  invalidRequest,
  unexpectedStatus,
}

final class WebDavException implements Exception {
  const WebDavException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.uri,
    this.cause,
  });

  final WebDavErrorKind kind;
  final String message;
  final int? statusCode;
  final Uri? uri;
  final Object? cause;

  factory WebDavException.malformed(String message, {Object? cause}) =>
      WebDavException(
        kind: WebDavErrorKind.malformedResponse,
        message: message,
        cause: cause,
      );

  @override
  String toString() => message;
}

final class WebDavResponseMetadata {
  const WebDavResponseMetadata({
    required this.statusCode,
    required this.uri,
    required this.headers,
    this.serverDate,
    this.etag,
  });

  final int statusCode;
  final Uri uri;
  final Map<String, String> headers;
  final DateTime? serverDate;
  final String? etag;
}

final class WebDavBytesResult {
  const WebDavBytesResult({required this.bytes, required this.metadata});

  final Uint8List bytes;
  final WebDavResponseMetadata metadata;
}

final class WebDavFileResult {
  const WebDavFileResult({
    required this.file,
    required this.bytesWritten,
    required this.metadata,
  });

  final File file;
  final int bytesWritten;
  final WebDavResponseMetadata metadata;
}

final class WebDavExistenceResult {
  const WebDavExistenceResult({required this.exists, required this.metadata});

  final bool exists;
  final WebDavResponseMetadata metadata;
}

/// Low-level WebDAV transport with no profile/session dependency.
///
/// All requests disable the platform client's redirect handling. One redirect
/// is followed manually only when it stays on the enrolled origin and keeps
/// the scheme. Body-bearing WebDAV methods replay only for 307/308.
final class WebDavProtocolClient {
  WebDavProtocolClient({
    required Uri endpoint,
    required this.credentials,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : endpoint = _normalizeEndpoint(endpoint),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  factory WebDavProtocolClient.fromUrl({
    required String endpoint,
    required WebDavCredentials credentials,
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
  }) => WebDavProtocolClient(
    endpoint: parseEndpoint(endpoint),
    credentials: credentials,
    client: client,
    timeout: timeout,
  );

  static const int defaultSmallDocumentLimit = 4 * 1024 * 1024;
  static const int maxPathSegments = 128;

  // File PUTs need a size-aware deadline: a fixed request timeout would make
  // every 128 MiB backup fail on an otherwise healthy connection below tens
  // of Mbit/s. The base timeout remains the setup/response allowance, while
  // this deliberately conservative floor budgets the streamed body itself.
  static const int _minimumBudgetedUploadBytesPerSecond = 8 * 1024;

  final Uri endpoint;
  final WebDavCredentials credentials;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  static Uri parseEndpoint(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'WebDAV server URL is empty',
      );
    }
    // Uri treats `server.example:8443/dav` as a URI whose scheme is
    // `server.example`. Only `scheme://` is an explicit scheme here so the
    // common host:port form still receives the safe HTTPS default.
    final hasExplicitScheme = RegExp(
      r'^[A-Za-z][A-Za-z0-9+.-]*://',
    ).hasMatch(trimmed);
    final withScheme = hasExplicitScheme ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'Enter a valid HTTP or HTTPS WebDAV server URL',
      );
    }
    return uri;
  }

  static bool isInsecureUrl(String source) {
    final uri = Uri.tryParse(source.trim());
    return uri?.scheme.toLowerCase() == 'http';
  }

  static Map<String, String> buildAuthorizationHeaders(
    WebDavCredentials credentials,
  ) {
    final headers = <String, String>{'Accept': '*/*'};
    if (!credentials.isEmpty) {
      final token = base64Encode(
        utf8.encode('${credentials.username}:${credentials.password}'),
      );
      headers[HttpHeaders.authorizationHeader] = 'Basic $token';
    }
    return headers;
  }

  static Uri resolvePath({
    required Uri endpoint,
    required String path,
    bool collection = false,
  }) {
    final normalizedEndpoint = _normalizeEndpoint(endpoint);
    final relative = _relativeSegments(path);
    final base = normalizedEndpoint.pathSegments.where(
      (segment) => segment.isNotEmpty,
    );
    return normalizedEndpoint
        .replace(
          pathSegments: <String>[...base, ...relative, if (collection) ''],
        )
        .removeFragment();
  }

  Map<String, String> get authorizationHeaders =>
      buildAuthorizationHeaders(credentials);

  Uri uriForPath(String path, {bool collection = false}) =>
      resolvePath(endpoint: endpoint, path: path, collection: collection);

  Future<WebDavResponseMetadata> putBytes({
    required String path,
    required List<int> bytes,
    required int maxBytes,
    String contentType = 'application/octet-stream',
    String? ifNoneMatch,
    String? ifMatch,
    bool createParents = true,
    Future<void> Function()? beforeSend,
  }) async {
    if (maxBytes < 0 || bytes.length > maxBytes) {
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'WebDAV upload exceeds its byte limit',
      );
    }
    final immutableBytes = Uint8List.fromList(bytes);
    return _put(
      path: path,
      contentLength: immutableBytes.length,
      contentType: contentType,
      ifNoneMatch: ifNoneMatch,
      ifMatch: ifMatch,
      createParents: createParents,
      beforeSend: beforeSend,
      body: _RequestBody.bytes(immutableBytes),
    );
  }

  Future<WebDavResponseMetadata> uploadFile({
    required String path,
    required File file,
    required int maxBytes,
    String contentType = 'application/octet-stream',
    String? ifNoneMatch,
    String? ifMatch,
    bool createParents = true,
    Future<void> Function()? beforeSend,
  }) async {
    final length = await file.length();
    if (maxBytes < 0 || length > maxBytes) {
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'WebDAV upload exceeds its byte limit',
      );
    }
    return _put(
      path: path,
      contentLength: length,
      contentType: contentType,
      ifNoneMatch: ifNoneMatch,
      ifMatch: ifMatch,
      createParents: createParents,
      beforeSend: beforeSend,
      body: _RequestBody.file(file, length),
    );
  }

  Future<WebDavResponseMetadata> _put({
    required String path,
    required int contentLength,
    required String contentType,
    required String? ifNoneMatch,
    required String? ifMatch,
    required bool createParents,
    required Future<void> Function()? beforeSend,
    required _RequestBody body,
  }) async {
    final normalizedPath = _normalizeRelativePath(path);
    if (normalizedPath.isEmpty || normalizedPath.endsWith('/')) {
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'A WebDAV file path is required',
      );
    }
    final headers = <String, String>{
      ...authorizationHeaders,
      HttpHeaders.contentTypeHeader: contentType,
      if (ifNoneMatch != null) HttpHeaders.ifNoneMatchHeader: ifNoneMatch,
      if (ifMatch != null) HttpHeaders.ifMatchHeader: ifMatch,
    };

    Future<http.StreamedResponse> send() => _sendFollowingRedirects(
      method: 'PUT',
      initialUri: uriForPath(normalizedPath),
      headers: headers,
      body: body,
      beforeSend: beforeSend,
    );

    var response = await send();
    if (response.statusCode == HttpStatus.conflict && createParents) {
      await _discard(response);
      await ensureCollection(
        _parentPath(normalizedPath),
        beforeSend: beforeSend,
      );
      response = await send();
    }
    return _finishMetadata(response, accepted: _isSuccess);
  }

  Future<WebDavBytesResult> getBytes({
    required String path,
    required int maxBytes,
    Duration? bodyInactivityTimeout,
    Future<void> Function()? beforeSend,
  }) async {
    final response = await _sendFollowingRedirects(
      method: 'GET',
      initialUri: uriForPath(path),
      headers: authorizationHeaders,
      beforeSend: beforeSend,
    );
    await _throwUnlessAccepted(response, _isSuccess);
    final bytes = await _readBounded(
      response,
      maxBytes,
      inactivityTimeout: bodyInactivityTimeout,
    );
    return WebDavBytesResult(bytes: bytes, metadata: _metadata(response));
  }

  Future<WebDavFileResult> downloadToFile({
    required String path,
    required File destination,
    required int maxBytes,
    Future<void> Function()? beforeSend,
  }) async {
    final response = await _sendFollowingRedirects(
      method: 'GET',
      initialUri: uriForPath(path),
      headers: authorizationHeaders,
      beforeSend: beforeSend,
    );
    await _throwUnlessAccepted(response, _isSuccess);
    if (maxBytes < 0 ||
        (response.contentLength != null &&
            response.contentLength! > maxBytes)) {
      await response.stream.listen(null).cancel();
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'WebDAV download exceeds its byte limit',
      );
    }

    await destination.parent.create(recursive: true);
    IOSink? sink;
    var written = 0;
    try {
      sink = destination.openWrite(mode: FileMode.writeOnly);
      await for (final chunk in _responseChunks(
        response,
        totalTimeout: _bodyDeadline(response.contentLength ?? maxBytes),
      )) {
        if (written > maxBytes - chunk.length) {
          throw const WebDavException(
            kind: WebDavErrorKind.invalidRequest,
            message: 'WebDAV download exceeds its byte limit',
          );
        }
        sink.add(chunk);
        written += chunk.length;
      }
      await sink.flush();
      await sink.close();
      sink = null;
      return WebDavFileResult(
        file: destination,
        bytesWritten: written,
        metadata: _metadata(response),
      );
    } catch (_) {
      await sink?.close();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  Future<WebDavExistenceResult> exists({
    required String path,
    bool collection = false,
    Future<void> Function()? beforeSend,
  }) async {
    var response = await _sendFollowingRedirects(
      method: 'HEAD',
      initialUri: uriForPath(path, collection: collection),
      headers: authorizationHeaders,
      beforeSend: beforeSend,
    );
    if (response.statusCode == HttpStatus.notFound) {
      final metadata = _metadata(response);
      await _discard(response);
      return WebDavExistenceResult(exists: false, metadata: metadata);
    }
    if (response.statusCode == HttpStatus.methodNotAllowed ||
        response.statusCode == HttpStatus.notImplemented) {
      await _discard(response);
      response = await _propfindResponse(
        path: path,
        depth: 0,
        collection: collection,
        body:
            '<?xml version="1.0" encoding="utf-8" ?>'
            '<D:propfind xmlns:D="DAV:"><D:prop><D:getetag/>'
            '<D:getlastmodified/><D:getcontentlength/></D:prop></D:propfind>',
        beforeSend: beforeSend,
      );
      if (response.statusCode == HttpStatus.notFound) {
        final metadata = _metadata(response);
        await _discard(response);
        return WebDavExistenceResult(exists: false, metadata: metadata);
      }
      await _throwUnlessAccepted(response, _isSuccess);
      final metadata = _metadata(response);
      final requestedUri =
          response.request?.url ?? uriForPath(path, collection: collection);
      try {
        final bytes = await _readBounded(response, defaultSmallDocumentLimit);
        return WebDavExistenceResult(
          exists: true,
          metadata: _metadataWithDavValidator(metadata, bytes, requestedUri),
        );
      } catch (_) {
        // The bounded read has already consumed or cancelled this one-shot
        // response stream. Existence was proven by the successful PROPFIND;
        // validator enrichment is optional.
        return WebDavExistenceResult(exists: true, metadata: metadata);
      }
    }
    final metadata = await _finishMetadata(response, accepted: _isSuccess);
    return WebDavExistenceResult(exists: true, metadata: metadata);
  }

  Future<WebDavBytesResult> propfind({
    required String path,
    required int depth,
    required String body,
    int maxBytes = defaultSmallDocumentLimit,
    bool collection = false,
    Future<void> Function()? beforeSend,
  }) async {
    final response = await _propfindResponse(
      path: path,
      depth: depth,
      body: body,
      collection: collection,
      beforeSend: beforeSend,
    );
    await _throwUnlessAccepted(response, _isSuccess);
    return WebDavBytesResult(
      bytes: await _readBounded(response, maxBytes),
      metadata: _metadata(response),
    );
  }

  Future<http.StreamedResponse> _propfindResponse({
    required String path,
    required int depth,
    bool collection = false,
    String body =
        '<?xml version="1.0" encoding="utf-8" ?>'
        '<D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/>'
        '</D:prop></D:propfind>',
    Future<void> Function()? beforeSend,
  }) => _sendFollowingRedirects(
    method: 'PROPFIND',
    initialUri: uriForPath(path, collection: collection),
    headers: <String, String>{
      ...authorizationHeaders,
      'Depth': '$depth',
      HttpHeaders.contentTypeHeader: 'application/xml; charset=utf-8',
    },
    body: _RequestBody.bytes(Uint8List.fromList(utf8.encode(body))),
    beforeSend: beforeSend,
  );

  static WebDavResponseMetadata _metadataWithDavValidator(
    WebDavResponseMetadata metadata,
    Uint8List bytes,
    Uri requestedUri,
  ) {
    // Best-effort enrichment: existence was already proven by the 2xx/207
    // status. A body without parseable DAV properties simply yields no
    // validator (the remote-change poll then reports disabledNoValidators),
    // preserving the M1 `exists` contract for minimal servers.
    final XmlDocument document;
    try {
      document = XmlDocument.parse(utf8.decode(bytes));
    } on Exception {
      return metadata;
    }
    XmlElement? target;
    for (final response in document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'response',
    )) {
      final href = _directChildText(response, 'href');
      if (href == null || !_sameDavTarget(requestedUri, href)) continue;
      target = response;
      break;
    }
    if (target == null) return metadata;
    XmlElement? properties;
    for (final propstat in target.children.whereType<XmlElement>().where(
      (element) => element.name.local == 'propstat',
    )) {
      final status = _directChildText(propstat, 'status');
      if (status == null || !RegExp(r'\s2\d\d(?:\s|$)').hasMatch(status)) {
        continue;
      }
      properties = propstat.children.whereType<XmlElement>().firstWhere(
        (element) => element.name.local == 'prop',
        orElse: () => XmlElement(XmlName('prop')),
      );
      break;
    }
    if (properties == null) return metadata;
    final etag = _directChildText(properties, 'getetag')?.trim();
    final lastModified = _directChildText(
      properties,
      'getlastmodified',
    )?.trim();
    final contentLength = _directChildText(
      properties,
      'getcontentlength',
    )?.trim();
    final headers = <String, String>{
      ...metadata.headers,
      if (lastModified != null && lastModified.isNotEmpty)
        HttpHeaders.lastModifiedHeader: lastModified,
      if (contentLength != null && int.tryParse(contentLength) != null)
        HttpHeaders.contentLengthHeader: contentLength,
    };
    return WebDavResponseMetadata(
      statusCode: metadata.statusCode,
      uri: metadata.uri,
      headers: Map<String, String>.unmodifiable(headers),
      serverDate: metadata.serverDate,
      etag: etag == null || etag.isEmpty ? null : etag,
    );
  }

  static String? _directChildText(XmlElement parent, String localName) {
    for (final child in parent.children.whereType<XmlElement>()) {
      if (child.name.local == localName) return child.innerText;
    }
    return null;
  }

  static bool _sameDavTarget(Uri requested, String href) {
    final parsed = Uri.tryParse(href.trim());
    if (parsed == null) return false;
    final resolved = requested.resolveUri(parsed);
    return resolved.scheme == requested.scheme &&
        resolved.host == requested.host &&
        resolved.port == requested.port &&
        resolved.path == requested.path &&
        resolved.query == requested.query;
  }

  Future<WebDavResponseMetadata> deletePath({
    required String path,
    bool collection = false,
    Future<void> Function()? beforeSend,
  }) async {
    final response = await _sendFollowingRedirects(
      method: 'DELETE',
      initialUri: uriForPath(path, collection: collection),
      headers: authorizationHeaders,
      beforeSend: beforeSend,
    );
    return _finishMetadata(response, accepted: _isSuccess);
  }

  Future<WebDavResponseMetadata?> ensureCollection(
    String path, {
    Future<void> Function()? beforeSend,
  }) async {
    final normalized = _normalizeRelativePath(
      path,
    ).replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) return null;
    final segments = _relativeSegments(normalized);
    if (segments.length > maxPathSegments) {
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'WebDAV path has too many folders',
      );
    }

    Future<WebDavResponseMetadata?> createAt(int count) async {
      if (count <= 0) return null;
      final partial = segments.take(count).join('/');
      var response = await _sendFollowingRedirects(
        method: 'MKCOL',
        initialUri: uriForPath(partial, collection: true),
        headers: authorizationHeaders,
        beforeSend: beforeSend,
      );
      if (_isSuccess(response.statusCode) ||
          response.statusCode == HttpStatus.methodNotAllowed) {
        return _finishMetadata(
          response,
          accepted: (status) =>
              _isSuccess(status) || status == HttpStatus.methodNotAllowed,
        );
      }
      if (response.statusCode != HttpStatus.conflict) {
        return _finishMetadata(response, accepted: _isSuccess);
      }
      await _discard(response);
      await createAt(count - 1);
      response = await _sendFollowingRedirects(
        method: 'MKCOL',
        initialUri: uriForPath(partial, collection: true),
        headers: authorizationHeaders,
        beforeSend: beforeSend,
      );
      return _finishMetadata(
        response,
        accepted: (status) =>
            _isSuccess(status) || status == HttpStatus.methodNotAllowed,
      );
    }

    return createAt(segments.length);
  }

  Future<http.StreamedResponse> _sendFollowingRedirects({
    required String method,
    required Uri initialUri,
    required Map<String, String> headers,
    _RequestBody? body,
    Future<void> Function()? beforeSend,
  }) async {
    var uri = initialUri;
    for (var hop = 0; hop <= 1; hop++) {
      final response = await _sendOnce(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
        beforeSend: beforeSend,
      );
      if (!_isRedirect(response.statusCode)) return response;

      final location = response.headers[HttpHeaders.locationHeader];
      if (location == null || location.trim().isEmpty) return response;
      if (hop == 1) {
        await _discard(response);
        throw WebDavException(
          kind: WebDavErrorKind.unsafeRedirect,
          message: 'WebDAV refused a redirect chain longer than one hop',
          statusCode: response.statusCode,
          uri: uri,
        );
      }
      final next = uri.resolve(location);
      if (!_sameOrigin(endpoint, next) || next.scheme != endpoint.scheme) {
        await _discard(response);
        throw WebDavException(
          kind: WebDavErrorKind.unsafeRedirect,
          message: 'WebDAV refused a cross-origin or insecure redirect',
          statusCode: response.statusCode,
          uri: next,
        );
      }
      final canReplay =
          method == 'GET' ||
          method == 'HEAD' ||
          response.statusCode == HttpStatus.temporaryRedirect ||
          response.statusCode == HttpStatus.permanentRedirect;
      if (!canReplay) {
        await _discard(response);
        throw WebDavException(
          kind: WebDavErrorKind.unsafeRedirect,
          message: 'WebDAV refused a redirect that could change $method',
          statusCode: response.statusCode,
          uri: next,
        );
      }
      await _discard(response);
      uri = next;
    }
    throw const WebDavException(
      kind: WebDavErrorKind.unsafeRedirect,
      message: 'WebDAV redirect could not be resolved',
    );
  }

  Future<http.StreamedResponse> _sendOnce({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required _RequestBody? body,
    required Future<void> Function()? beforeSend,
  }) async {
    try {
      await beforeSend?.call();
      final future = () async {
        if (body?.file case final file?) {
          final request = http.StreamedRequest(method, uri)
            ..followRedirects = false
            ..contentLength = body!.length;
          request.headers.addAll(headers);
          final responseFuture = _client.send(request);
          try {
            await request.sink.addStream(file.openRead());
            await request.sink.close();
          } catch (error, stackTrace) {
            // Sending starts consuming the request stream immediately. If the
            // file stream or sink fails, observe the already-started response
            // future and close the sink so neither error nor request is left
            // orphaned.
            responseFuture.ignore();
            try {
              await request.sink.close();
            } catch (_) {}
            Error.throwWithStackTrace(error, stackTrace);
          }
          return responseFuture;
        }
        final request = http.Request(method, uri)
          ..followRedirects = false
          ..headers.addAll(headers);
        if (body?.bytes case final bytes?) request.bodyBytes = bytes;
        return _client.send(request);
      }();
      return await future.timeout(_deadlineFor(body));
    } on TimeoutException catch (error) {
      throw WebDavException(
        kind: WebDavErrorKind.timeout,
        message: 'WebDAV request timed out',
        uri: uri,
        cause: error,
      );
    } on HandshakeException catch (error) {
      throw WebDavException(
        kind: WebDavErrorKind.tls,
        message: 'WebDAV secure connection failed',
        uri: uri,
        cause: error,
      );
    } on SocketException catch (error) {
      throw WebDavException(
        kind: WebDavErrorKind.network,
        message: 'Could not reach the WebDAV server',
        uri: uri,
        cause: error,
      );
    } on http.ClientException catch (error) {
      final tls =
          error.message.toLowerCase().contains('certificate') ||
          error.message.toLowerCase().contains('handshake');
      throw WebDavException(
        kind: tls ? WebDavErrorKind.tls : WebDavErrorKind.network,
        message: tls
            ? 'WebDAV secure connection failed'
            : 'Could not reach the WebDAV server',
        uri: uri,
        cause: error,
      );
    }
  }

  Duration _deadlineFor(_RequestBody? body) {
    if (body == null || body.file == null || body.length == 0) return timeout;
    final transferMicros =
        (body.length * Duration.microsecondsPerSecond +
            _minimumBudgetedUploadBytesPerSecond -
            1) ~/
        _minimumBudgetedUploadBytesPerSecond;
    return timeout + Duration(microseconds: transferMicros);
  }

  Future<WebDavResponseMetadata> _finishMetadata(
    http.StreamedResponse response, {
    required bool Function(int status) accepted,
  }) async {
    await _throwUnlessAccepted(response, accepted);
    final metadata = _metadata(response);
    await _discard(response);
    return metadata;
  }

  Future<void> _throwUnlessAccepted(
    http.StreamedResponse response,
    bool Function(int status) accepted,
  ) async {
    if (accepted(response.statusCode)) return;
    final error = _errorForResponse(response);
    await _discard(response);
    throw error;
  }

  WebDavException _errorForResponse(http.StreamedResponse response) {
    final status = response.statusCode;
    final kind = switch (status) {
      HttpStatus.unauthorized ||
      HttpStatus.forbidden => WebDavErrorKind.authentication,
      HttpStatus.notFound => WebDavErrorKind.notFound,
      HttpStatus.conflict || HttpStatus.locked => WebDavErrorKind.conflict,
      HttpStatus.preconditionFailed => WebDavErrorKind.preconditionFailed,
      HttpStatus.insufficientStorage => WebDavErrorKind.quota,
      HttpStatus.requestTimeout ||
      HttpStatus.tooManyRequests => WebDavErrorKind.transient,
      >= 500 && <= 599 => WebDavErrorKind.transient,
      _ => WebDavErrorKind.unexpectedStatus,
    };
    final message = switch (kind) {
      WebDavErrorKind.authentication => 'WebDAV authentication failed',
      WebDavErrorKind.notFound => 'WebDAV file or folder was not found',
      WebDavErrorKind.conflict => 'WebDAV request conflicts with server state',
      WebDavErrorKind.preconditionFailed =>
        'WebDAV precondition failed because the file already changed',
      WebDavErrorKind.quota => 'The WebDAV server is out of storage',
      WebDavErrorKind.transient =>
        'The WebDAV server is temporarily unavailable',
      _ => 'WebDAV request failed: $status',
    };
    return WebDavException(
      kind: kind,
      message: message,
      statusCode: status,
      uri: response.request?.url,
    );
  }

  Future<Uint8List> _readBounded(
    http.StreamedResponse response,
    int maxBytes, {
    Duration? inactivityTimeout,
  }) async {
    if (maxBytes < 0 ||
        (response.contentLength != null &&
            response.contentLength! > maxBytes)) {
      await response.stream.listen(null).cancel();
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'WebDAV response exceeds its byte limit',
      );
    }
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in _responseChunks(
      response,
      inactivityTimeout: inactivityTimeout,
      totalTimeout: _bodyDeadline(
        response.contentLength ?? maxBytes,
        allowance: inactivityTimeout,
      ),
    )) {
      if (length > maxBytes - chunk.length) {
        throw const WebDavException(
          kind: WebDavErrorKind.invalidRequest,
          message: 'WebDAV response exceeds its byte limit',
        );
      }
      builder.add(chunk);
      length += chunk.length;
    }
    return builder.takeBytes();
  }

  WebDavResponseMetadata _metadata(http.StreamedResponse response) {
    DateTime? serverDate;
    final rawDate = response.headers[HttpHeaders.dateHeader];
    if (rawDate != null) {
      try {
        serverDate = HttpDate.parse(rawDate).toUtc();
      } on Exception {
        serverDate = null;
      }
    }
    return WebDavResponseMetadata(
      statusCode: response.statusCode,
      uri: response.request?.url ?? endpoint,
      headers: Map<String, String>.unmodifiable(response.headers),
      serverDate: serverDate,
      etag: response.headers[HttpHeaders.etagHeader],
    );
  }

  Stream<List<int>> _responseChunks(
    http.StreamedResponse response, {
    Duration? inactivityTimeout,
    Duration? totalTimeout,
  }) async* {
    final uri = response.request?.url ?? endpoint;
    final chunks = StreamIterator<List<int>>(response.stream);
    final elapsed = Stopwatch()..start();
    final total = totalTimeout ?? timeout;
    try {
      while (true) {
        final remaining = total - elapsed.elapsed;
        if (remaining <= Duration.zero) throw TimeoutException('Body deadline');
        final idle = inactivityTimeout ?? timeout;
        if (!await chunks.moveNext().timeout(
          remaining < idle ? remaining : idle,
        )) {
          break;
        }
        yield chunks.current;
      }
    } on TimeoutException catch (error) {
      throw WebDavException(
        kind: WebDavErrorKind.timeout,
        message: 'WebDAV response timed out',
        statusCode: response.statusCode,
        uri: uri,
        cause: error,
      );
    } on HandshakeException catch (error) {
      throw WebDavException(
        kind: WebDavErrorKind.tls,
        message: 'WebDAV secure connection failed',
        statusCode: response.statusCode,
        uri: uri,
        cause: error,
      );
    } on SocketException catch (error) {
      throw WebDavException(
        kind: WebDavErrorKind.network,
        message: 'WebDAV response was interrupted',
        statusCode: response.statusCode,
        uri: uri,
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw WebDavException(
        kind: WebDavErrorKind.network,
        message: 'WebDAV response was interrupted',
        statusCode: response.statusCode,
        uri: uri,
        cause: error,
      );
    } on WebDavException catch (error) {
      // A response already exists here, so its status is always known. The
      // invariant "any post-response body failure carries THIS response's
      // status" must hold for every exit: pass an inner exception through only
      // when its status already matches, otherwise re-stamp it (a null or a
      // mismatched inner status must never mask the real response status).
      if (error.statusCode == response.statusCode) rethrow;
      throw WebDavException(
        kind: error.kind,
        message: error.message,
        statusCode: response.statusCode,
        uri: error.uri ?? uri,
        cause: error.cause ?? error,
      );
    } catch (error) {
      throw WebDavException(
        kind: WebDavErrorKind.network,
        message: 'WebDAV response was interrupted',
        statusCode: response.statusCode,
        uri: uri,
        cause: error,
      );
    } finally {
      await chunks.cancel();
    }
  }

  // Transfers get a size-aware total deadline as well as an inactivity limit.
  // Small metadata/error drains use the ordinary request allowance.
  Duration _bodyDeadline(int bytes, {Duration? allowance}) =>
      (allowance ?? timeout) +
      Duration(
        microseconds:
            (bytes *
                    Duration.microsecondsPerSecond /
                    _minimumBudgetedUploadBytesPerSecond)
                .ceil(),
      );

  Future<void> _discard(http.StreamedResponse response) async {
    var discarded = 0;
    await for (final chunk in _responseChunks(response)) {
      discarded += chunk.length;
      if (discarded > 64 * 1024) break;
    }
  }

  static bool _isSuccess(int status) => status >= 200 && status < 300;

  static bool _isRedirect(int status) => status >= 300 && status < 400;

  static bool _sameOrigin(Uri a, Uri b) =>
      a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
      a.host.toLowerCase() == b.host.toLowerCase() &&
      a.port == b.port;

  static Uri _normalizeEndpoint(Uri uri) {
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'Enter a valid HTTP or HTTPS WebDAV server URL',
      );
    }
    return uri.removeFragment();
  }

  static List<String> _relativeSegments(String path) {
    final segments = path
        .trim()
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.length > maxPathSegments ||
        segments.any((segment) => segment == '.' || segment == '..')) {
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'WebDAV path is invalid',
      );
    }
    return segments;
  }

  static String _normalizeRelativePath(String path) =>
      _relativeSegments(path).join('/');

  static String _parentPath(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

final class _RequestBody {
  const _RequestBody._({this.bytes, this.file, required this.length});

  factory _RequestBody.bytes(Uint8List bytes) =>
      _RequestBody._(bytes: bytes, length: bytes.length);

  factory _RequestBody.file(File file, int length) =>
      _RequestBody._(file: file, length: length);

  final Uint8List? bytes;
  final File? file;
  final int length;
}

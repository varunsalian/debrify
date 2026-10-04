import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Adapt dart:io requests to the fixture's zone-owned MockClient. Production
/// TMDB creates IOClient directly, so the package:http factory zone alone
/// cannot intercept it. No sockets, DNS, TLS or real credentials are used.
class MergedFixtureHttpClient implements HttpClient {
  final http.Client client = http.Client();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(client, method, url);
  @override
  void close({bool force = false}) => client.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  _Headers([Map<String, String> values = const {}]) : values = {...values};
  final Map<String, String> values;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  void forEach(void Function(String, List<String>) action) {
    values.forEach((key, value) => action(key, [value]));
  }

  @override
  List<String>? operator [](String name) =>
      values.containsKey(name.toLowerCase())
      ? [values[name.toLowerCase()]!]
      : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.client, this.method, this.uri);
  final http.Client client;
  @override
  final String method;
  @override
  final Uri uri;
  @override
  final HttpHeaders headers = _Headers();
  final bytes = <int>[];
  @override
  void add(List<int> data) => bytes.addAll(data);
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    final request = http.Request(method, uri)..bodyBytes = bytes;
    headers.forEach((key, values) => request.headers[key] = values.join(','));
    return _Response(await client.send(request));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.response);
  final http.StreamedResponse response;
  @override
  int get statusCode => response.statusCode;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  int get contentLength => response.contentLength ?? -1;
  @override
  String get reasonPhrase => response.reasonPhrase ?? '';
  @override
  bool get isRedirect => response.isRedirect;
  @override
  bool get persistentConnection => response.persistentConnection;
  @override
  HttpHeaders get headers => _Headers(response.headers);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => response.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'tmdb_transport_socket.dart';

/// Changes TCP address selection, then performs TLS using the original URI
/// hostname, including SNI and normal certificate verification.
class TmdbHttpClient extends IOClient {
  factory TmdbHttpClient({TmdbDnsCache? dnsCache}) {
    final connections = TmdbConnections(dnsCache: dnsCache);
    final transport = connections.httpClient();
    return TmdbHttpClient._(transport, connections);
  }
  TmdbHttpClient._(super.client, this._connections);
  final TmdbConnections _connections;

  /// Only callers performing idempotent API reads opt into host failover.
  Uri readUri(Uri uri) => _connections.readUri(uri);
  void reportTransportFailure(Uri uri) =>
      _connections.reportTransportFailure(uri);

  @override
  Future<IOStreamedResponse> send(http.BaseRequest request) async {
    try {
      return await super.send(request);
    } on http.ClientException {
      _connections.reportTransportFailure(request.url);
      rethrow;
    } on SocketException {
      _connections.reportTransportFailure(request.url);
      rethrow;
    } on TlsException {
      _connections.reportTransportFailure(request.url);
      rethrow;
    }
  }

  @override
  void close() {
    _connections.close();
    super.close();
  }
}

/// Share only public DNS answers, never sockets, requests or credentials.
/// Short-lived metadata clients can retain the fallback route without sharing
/// cancellation ownership of their transports.
class TmdbDnsCache {
  List<InternetAddress> addresses = [];
  DateTime? expires;
  DateTime? retryAt;
  DateTime? preferPublicUntil;
  DateTime? alternateUntil;
  DateTime? alternateRetryAt;
}

/// TMDB API only: never intercept proxies, artwork, addons, or other providers.
/// Public DNS receives a hostname lookup, never API headers or query strings.
class TmdbConnections {
  TmdbConnections({
    TmdbDnsCache? dnsCache,
    http.Client Function()? dnsClientFactory,
    Future<ConnectionTask<Socket>> Function(dynamic, int)? startConnect,
    DateTime Function()? now,
    this.connectBudget = const Duration(seconds: 2),
    this.dnsBudget = const Duration(seconds: 2),
    this.tlsBudget = const Duration(seconds: 5),
  }) : _dnsCache = dnsCache ?? TmdbDnsCache(),
       _ownsDnsCache = dnsCache == null,
       _dnsFactory =
           dnsClientFactory ??
           (() => IOClient(
             HttpClient()..connectionTimeout = const Duration(seconds: 2),
           )),
       _startConnect = startConnect ?? startSocket,
       _now = now ?? DateTime.now;

  static const host = 'api.themoviedb.org';
  static const alternateHost = 'api.tmdb.org';
  final http.Client Function() _dnsFactory;
  final _dnsClients = <http.Client>{};
  final Future<ConnectionTask<Socket>> Function(dynamic, int) _startConnect;
  final DateTime Function() _now;
  final Duration connectBudget;
  final Duration dnsBudget;
  final Duration tlsBudget;
  final _handshakes = <void Function()>{};
  final _active = <_ConnectionAttempt>{};
  final TmdbDnsCache _dnsCache;
  final bool _ownsDnsCache;
  Future<List<InternetAddress>>? _resolving;
  bool _closed = false;
  String? _lastConnectedAddress;

  Uri readUri(Uri uri) {
    if (!_closed &&
        uri.scheme == 'https' &&
        uri.host == host &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        uri.path.startsWith('/3/') &&
        (_dnsCache.alternateUntil?.isAfter(_now()) ?? false)) {
      return uri.replace(host: alternateHost);
    }
    return uri;
  }

  /// Some DNS interception endpoints accept TCP and reset TLS/HTTP instead
  /// of refusing the connection. Remember that failure across request leases
  /// so retries don't repeatedly reconnect to the same intercepted route.
  void reportTransportFailure(Uri uri) {
    if (_closed || uri.scheme != 'https' || uri.port != 443) {
      return;
    }
    if (uri.host == alternateHost) {
      // A network may block either hostname. Let the next bounded attempt
      // return to the primary/public-DNS route if the alternate also fails.
      _dnsCache.alternateUntil = null;
      _dnsCache.alternateRetryAt = _now().add(const Duration(seconds: 30));
      return;
    }
    if (uri.host != host) return;
    if (!(_dnsCache.alternateRetryAt?.isAfter(_now()) ?? false)) {
      _dnsCache.alternateUntil = _now().add(const Duration(minutes: 5));
    }
    _dnsCache.preferPublicUntil = _now().add(const Duration(minutes: 5));
    // A successful TCP connect is not proof that this edge can serve HTTP.
    // Move the failed route behind its alternatives, rather than making every
    // retry choose the same cached address again.
    final addresses = List<InternetAddress>.of(_dnsCache.addresses);
    final index = addresses.indexWhere(
      (a) => a.address == _lastConnectedAddress,
    );
    if (index >= 0 && addresses.length > 1) {
      addresses.add(addresses.removeAt(index));
      _dnsCache.addresses = addresses;
    }
  }

  static Future<ConnectionTask<Socket>> startSocket(
    dynamic host,
    int port,
  ) async {
    final task = await RawSocket.startConnect(host, port);
    return ConnectionTask.fromSocket(
      task.socket.then(TmdbTransportSocket.new),
      task.cancel,
    );
  }

  HttpClient httpClient({SecurityContext? context}) {
    return HttpClient(context: context)
      ..connectionFactory = (uri, proxyHost, proxyPort) async {
        // The SDK upgrades proxy tunnels itself and requires its own Socket
        // implementation for that operation. Do not wrap proxy transports.
        if (proxyHost != null) {
          if (_closed) throw const SocketException('TMDB client is closed');
          return Socket.startConnect(proxyHost, proxyPort!);
        }
        final task = await connect(uri, proxyHost, proxyPort);
        // HttpClient owns CONNECT/TLS negotiation for configured proxies.
        if (uri.scheme != 'https' || proxyHost != null) return task;
        Socket? raw;
        var cancelled = false;
        final interrupted = Completer<TmdbTransportSocket>();
        // Cancellation can precede TCP completion and the handshake race.
        interrupted.future.ignore();
        void cancel() {
          cancelled = true;
          if (!interrupted.isCompleted) {
            interrupted.completeError(
              const SocketException('TMDB connection cancelled'),
            );
          }
          task.cancel();
          raw?.destroy();
        }

        _handshakes.add(cancel);
        final secured = (() async {
          raw = await task.socket;
          if (cancelled || _closed) {
            raw!.destroy();
            throw const SocketException('TMDB connection cancelled');
          }
          try {
            final transport = (raw! as TmdbTransportSocket).transport;
            final handshake =
                RawSecureSocket.secure(
                  transport,
                  host: uri.host,
                  context: context,
                ).then((socket) {
                  if (cancelled || _closed) {
                    socket.close();
                    throw const SocketException('TMDB connection cancelled');
                  }
                  return TmdbTransportSocket(socket);
                });
            final secure = await Future.any([handshake, interrupted.future])
                .timeout(
                  tlsBudget,
                  onTimeout: () {
                    cancel();
                    throw const SocketException('TMDB TLS handshake timed out');
                  },
                );
            if (cancelled || _closed) {
              secure.destroy();
              throw const SocketException('TMDB connection cancelled');
            }
            return secure;
          } catch (_) {
            raw!.destroy();
            rethrow;
          }
        })();
        return ConnectionTask.fromSocket(
          secured.whenComplete(() => _handshakes.remove(cancel)),
          cancel,
        );
      };
  }

  Future<ConnectionTask<Socket>> connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    if (_closed) throw const SocketException('TMDB client is closed');
    if (proxyHost != null ||
        uri.scheme != 'https' ||
        uri.host != host ||
        uri.port != 443) {
      return _startConnect(proxyHost ?? uri.host, proxyPort ?? uri.port);
    }
    final attempt = _ConnectionAttempt();
    _active.add(attempt);
    final socket = _connect(
      attempt,
    ).whenComplete(() => _active.remove(attempt));
    return ConnectionTask.fromSocket(socket, attempt.cancel);
  }

  Future<Socket> _open(dynamic address, _ConnectionAttempt attempt) async {
    attempt.check();
    ConnectionTask<Socket>? task;
    var expired = false;
    var connected = false;
    try {
      return await (() async {
        task = await _startConnect(address, 443);
        if (expired || attempt.cancelled) {
          task!.cancel();
          throw const SocketException('TMDB connection cancelled');
        }
        attempt.tasks.add(task!);
        final socket = await task!.socket;
        if (expired || attempt.cancelled) {
          socket.destroy();
          throw const SocketException('TMDB connection cancelled');
        }
        connected = true;
        _lastConnectedAddress = address is InternetAddress
            ? address.address
            : socket.remoteAddress.address;
        return socket;
      })().timeout(connectBudget);
    } finally {
      expired = true;
      if (task != null) {
        attempt.tasks.remove(task);
        if (!connected) task!.cancel();
      }
    }
  }

  Future<Socket> _connect(_ConnectionAttempt attempt) async {
    final preferPublic = _dnsCache.preferPublicUntil?.isAfter(_now()) ?? false;
    final cached =
        _dnsCache.expires != null && _now().isBefore(_dnsCache.expires!)
        ? _dnsCache.addresses
        : preferPublic
        ? await _resolve()
        : const <InternetAddress>[];
    for (final address in cached.take(2)) {
      try {
        return await _open(address, attempt);
      } on SocketException {
        attempt.check();
      } on TimeoutException {
        attempt.check();
      }
    }
    if (cached.isNotEmpty) {
      _dnsCache.addresses = [];
      _dnsCache.expires = null;
    }
    if (!preferPublic) {
      try {
        return await _open(host, attempt);
      } on SocketException {
        attempt.check();
      } on TimeoutException {
        attempt.check();
      }
    }
    final addresses = await _resolve();
    attempt.check();
    for (final address in addresses.take(2)) {
      try {
        return await _open(address, attempt);
      } on SocketException {
        attempt.check();
      } on TimeoutException {
        attempt.check();
      }
    }
    // Public DNS can itself be blocked. Do not permanently exclude a working
    // local route merely because an earlier connection was interrupted.
    if (preferPublic) return _open(host, attempt);
    throw const SocketException('TMDB connection failed after DNS fallback');
  }

  Future<List<InternetAddress>> _resolve() async {
    if (_closed) throw const SocketException('TMDB client is closed');
    if (_dnsCache.expires != null && _now().isBefore(_dnsCache.expires!))
      return _dnsCache.addresses;
    if (_dnsCache.retryAt != null && _now().isBefore(_dnsCache.retryAt!))
      return [];
    final pending = _resolving;
    if (pending != null) return pending;
    final work = _lookup();
    _resolving = work;
    try {
      return await work;
    } finally {
      if (identical(_resolving, work)) _resolving = null;
    }
  }

  Future<List<InternetAddress>> _lookup() async {
    for (final endpoint in [
      Uri.https('dns.google', '/resolve', {
        'name': host,
        'type': 'A',
        'edns_client_subnet': '0.0.0.0/0',
      }),
      Uri.https('cloudflare-dns.com', '/dns-query', {
        'name': host,
        'type': 'A',
      }),
    ]) {
      if (_closed) throw const SocketException('TMDB client is closed');
      try {
        final client = _dnsFactory();
        _dnsClients.add(client);
        final (List<InternetAddress>, int) answer;
        try {
          answer = await _query(endpoint, client).timeout(dnsBudget);
        } finally {
          _dnsClients.remove(client);
          client.close();
        }
        if (_closed) throw const SocketException('TMDB client is closed');
        _dnsCache.addresses = answer.$1;
        _dnsCache.expires = _now().add(Duration(seconds: answer.$2));
        _dnsCache.retryAt = null;
        return _dnsCache.addresses;
      } catch (_) {
        // A failed resolver is bounded; try the independent secondary once.
      }
    }
    _dnsCache.retryAt = _now().add(const Duration(seconds: 10));
    return [];
  }

  Future<(List<InternetAddress>, int)> _query(
    Uri endpoint,
    http.Client client,
  ) async {
    final request = http.Request('GET', endpoint)
      ..followRedirects = false
      ..headers['Accept'] = 'application/dns-json';
    final response = await client.send(request);
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(dnsBudget)) {
      if (bytes.length + chunk.length > 32768) {
        throw const FormatException('DNS response too large');
      }
      bytes.addAll(chunk);
    }
    if (response.statusCode != 200) {
      throw const FormatException('DNS HTTP error');
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map || data['Status'] != 0 || data['Answer'] is! List) {
      throw const FormatException('Invalid DNS response');
    }
    final addresses = <InternetAddress>[];
    var ttl = 300;
    for (final record in data['Answer'] as List) {
      if (record is! Map || record['type'] != 1 || record['data'] is! String) {
        continue;
      }
      final address = InternetAddress.tryParse(record['data'] as String);
      if (address == null || address.type != InternetAddressType.IPv4) continue;
      final b = address.rawAddress;
      if (b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168)) {
        continue;
      }
      if (record['TTL'] is! int || (record['TTL'] as int) < 0) continue;
      final seconds = record['TTL'] as int;
      if (seconds < ttl) ttl = seconds;
      if (!addresses.any((a) => a.address == address.address)) {
        addresses.add(address);
      }
    }
    if (addresses.isEmpty) {
      throw const FormatException('No public DNS addresses');
    }
    return (addresses, ttl);
  }

  void close() {
    _closed = true;
    for (final cancel in _handshakes.toList()) {
      cancel();
    }
    for (final attempt in _active.toList()) {
      attempt.cancel();
    }
    for (final client in _dnsClients.toList()) {
      client.close();
    }
    if (_ownsDnsCache) _dnsCache.addresses = [];
  }
}

class _ConnectionAttempt {
  bool cancelled = false;
  final tasks = <ConnectionTask<Socket>>{};
  void check() {
    if (cancelled) throw const SocketException('TMDB connection cancelled');
  }

  void cancel() {
    cancelled = true;
    for (final task in tasks.toList()) {
      task.cancel();
    }
  }
}

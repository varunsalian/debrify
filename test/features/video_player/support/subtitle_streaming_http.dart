import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../support/catalog_detail_http_transport.dart';
import 'video_player_environment.dart';

/// Header delivery and body delivery are distinct held boundaries. The real
/// player still creates its own client, times both operations and closes it.
class SubtitleStreamingHttp extends HttpOverrides {
  SubtitleStreamingHttp(this.fallback);
  final VideoPlayerHttp fallback;
  final routes = <String, Future<http.StreamedResponse> Function()>{};
  final requests = <http.BaseRequest>[];
  final closed = <int>[];
  final clientRequests = <int, List<Uri>>{};
  int _next = 0;

  List<int> closedFor(String url) => closed
      .where((id) => clientRequests[id]?.contains(Uri.parse(url)) ?? false)
      .toList();

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final id = _next++;
    clientRequests[id] = [];
    return http.runWithClient(
      CatalogFixtureHttpClient.new,
      () => _StreamingClient((request, body) async {
        requests.add(request);
        clientRequests[id]!.add(request.url);
        final route = routes[request.url.toString()];
        if (route != null) return route();
        final copy = http.Request(request.method, request.url)
          ..headers.addAll(request.headers)
          ..bodyBytes = await body.toBytes();
        fallback.requests.add(copy);
        final response = fallback.handler != null
            ? await fallback.handler!(copy)
            : fallback.replies[copy.url.toString()] ?? http.Response('{}', 404);
        return http.StreamedResponse(
          Stream.value(response.bodyBytes),
          response.statusCode,
          contentLength: response.contentLength,
          headers: response.headers,
        );
      }, () => closed.add(id)),
    );
  }
}

class _StreamingClient extends MockClient {
  _StreamingClient(super.fn, this.onClose) : super.streaming();
  final void Function() onClose;
  @override
  void close() {
    onClose();
    super.close();
  }
}

final class SubtitleFileBarrier extends IOOverrides {
  SubtitleFileBarrier(this.path, this.stage);
  final String path;
  final String stage;
  final entered = Completer<void>();
  final release = Completer<void>();
  final writes = <({List<int> bytes, bool flush})>[];
  final IOOverrides _real = _NativeFiles();

  @override
  File createFile(String name) {
    final file = _real.createFile(name);
    return name == path ? _HeldFile(file, this) : file;
  }

  Future<void> wait(String operation) async {
    if (stage != operation) return;
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }
}

final class _NativeFiles extends IOOverrides {}

class _HeldFile implements File {
  _HeldFile(this.file, this.barrier);
  final File file;
  final SubtitleFileBarrier barrier;
  @override
  String get path => file.path;
  @override
  bool existsSync() => file.existsSync();
  @override
  int lengthSync() => file.lengthSync();
  @override
  void deleteSync({bool recursive = false}) =>
      file.deleteSync(recursive: recursive);
  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    barrier.writes.add((bytes: List.of(bytes), flush: flush));
    await barrier.wait('write');
    return file.writeAsBytes(bytes, mode: mode, flush: flush);
  }

  @override
  Future<File> rename(String newPath) async {
    await barrier.wait('rename');
    return file.rename(newPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected fixture file call: ${invocation.memberName}',
  );
}

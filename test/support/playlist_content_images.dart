import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real Image.network path decodes one fixed bundled PNG. Metadata has
/// episode thumbnails; playlist items themselves deliberately have no poster.
class PlaylistContentImages implements HttpClient {
  final Uint8List bytes;
  PlaylistContentImages(this.bytes);
  static Future<PlaylistContentImages> load() async => PlaylistContentImages(
    (await rootBundle.load('assets/app_icon.png')).buffer.asUint8List(),
  );
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    expect(url.host, 'artwork.test');
    return _ImageRequest(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageRequest implements HttpClientRequest {
  final Uint8List bytes;
  _ImageRequest(this.bytes);
  @override
  HttpHeaders get headers => _ImageHeaders();
  @override
  Future<HttpClientResponse> close() async => _ImageResponse(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  final Uint8List bytes;
  _ImageResponse(this.bytes);
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

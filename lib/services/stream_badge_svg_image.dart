import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import '../utils/stream_badge_svg.dart';

/// SVGs share Flutter's ordinary decoded-image cache, keyed by URL AND bounded
/// output size. Rows retain only bitmap images, never a live vector renderer.
@immutable
class StreamBadgeSvgImage extends ImageProvider<StreamBadgeSvgImage> {
  const StreamBadgeSvgImage(
    this.url, {
    required this.maxWidth,
    required this.maxHeight,
    this.loadBytes,
  });
  final String url;
  final int maxWidth;
  final int maxHeight;
  final Future<Uint8List> Function(String)? loadBytes;
  static final _work = _SvgWorkQueue();
  static final _cache = CacheManager(
    Config(
      'stream-badge-svg-v1',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 64,
      fileService: BadgeSvgFileService(),
    ),
  );

  @override
  Future<StreamBadgeSvgImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    StreamBadgeSvgImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    _work.run(() async {
      try {
        final bytes = await (loadBytes ?? _loadBytes)(url);
        final text = await compute(
          validateBadgeSvg,
          bytes,
          debugLabel: 'Validate badge SVG',
        );
        final picture = await vg.loadPicture(SvgStringLoader(text), null);
        try {
          final size = picture.size;
          if (!size.width.isFinite ||
              !size.height.isFinite ||
              size.width <= 0 ||
              size.height <= 0) {
            throw const FormatException('Invalid SVG dimensions');
          }
          final scale = math.min(
            maxWidth.clamp(1, 1024) / size.width,
            maxHeight.clamp(1, 256) / size.height,
          );
          final width = (size.width * scale).round().clamp(1, 1024);
          final height = (size.height * scale).round().clamp(1, 256);
          final recorder = ui.PictureRecorder();
          ui.Canvas(recorder)
            ..scale(scale)
            ..drawPicture(picture.picture);
          final scaled = recorder.endRecording();
          try {
            return ImageInfo(image: await scaled.toImage(width, height));
          } finally {
            scaled.dispose();
          }
        } finally {
          picture.picture.dispose();
        }
      } catch (_) {
        // Do not retain a failed pending image; a later mount may retry.
        scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
        rethrow;
      }
    }),
  );

  static Future<Uint8List> _loadBytes(String url) async {
    // An extensionless SVG may already have been downloaded by the normal PNG
    // loader before decoding failed. Reuse those bytes, including offline.
    final existing = !isBadgeSvgUrl(url)
        ? await DefaultCacheManager().getFileFromCache(url)
        : null;
    final file = existing != null && existing.validTill.isAfter(DateTime.now())
        ? existing.file
        : await _cache.getSingleFile(url);
    if (await file.length() > maxBadgeSvgBytes) {
      throw const FormatException('SVG too large');
    }
    return file.readAsBytes();
  }

  @override
  bool operator ==(Object other) =>
      other is StreamBadgeSvgImage &&
      url == other.url &&
      maxWidth == other.maxWidth &&
      maxHeight == other.maxHeight &&
      loadBytes == other.loadBytes;
  @override
  int get hashCode => Object.hash(url, maxWidth, maxHeight, loadBytes);
}

/// The file cache bounds object count; this service also caps bytes and total
/// network time, including servers that omit Content-Length or trickle data.
class BadgeSvgFileService extends FileService {
  BadgeSvgFileService({
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 8),
  }) : _clientFactory = clientFactory ?? http.Client.new {
    concurrentFetches = 4;
  }
  final http.Client Function() _clientFactory;
  final Duration timeout;
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final client = _clientFactory();
    try {
      return await (() async {
        final uri = Uri.parse(url);
        if (uri.scheme != 'https' && uri.scheme != 'http') {
          throw const FormatException('Unsupported SVG URL');
        }
        final request = http.Request('GET', uri);
        if (headers != null) request.headers.addAll(headers);
        final response = await client.send(request);
        final bytes = BytesBuilder(copy: false);
        if (response.statusCode == 200) {
          if ((response.contentLength ?? 0) > maxBadgeSvgBytes) {
            throw const FormatException('SVG too large');
          }
          await for (final chunk in response.stream) {
            if (bytes.length + chunk.length > maxBadgeSvgBytes) {
              throw const FormatException('SVG too large');
            }
            bytes.add(chunk);
          }
        }
        return _SvgFileResponse(HttpGetResponse(response), bytes.takeBytes());
      })().timeout(timeout);
    } finally {
      client.close();
    }
  }
}

class _SvgFileResponse implements FileServiceResponse {
  _SvgFileResponse(this.response, this.bytes);
  final FileServiceResponse response;
  final Uint8List bytes;
  @override
  Stream<List<int>> get content => Stream.value(bytes);
  @override
  int get contentLength => bytes.length;
  @override
  int get statusCode => response.statusCode;
  @override
  DateTime get validTill => response.validTill;
  @override
  String? get eTag => response.eTag;
  @override
  String get fileExtension => '.svg';
}

class _SvgWorkQueue {
  int _active = 0;
  final _waiting = Queue<Completer<void>>();
  Future<T> run<T>(Future<T> Function() job) async {
    if (_active >= 4) {
      if (_waiting.length >= 512) throw StateError('SVG queue full');
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      return await job();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}

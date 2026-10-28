import 'package:http/http.dart' as http;

import '../../../models/torrent.dart';
import '../../../services/direct_source_authorization.dart';
import '../../../services/download_service.dart';
import '../../../services/iptv_source_search.dart';
import '../../../services/media_server_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';

enum SourceDownloadStatus {
  findingEpisode,
  resolving,
  unsupported,
  episodeMissing,
  episodeUnavailable,
  connectionChanged,
  noUrl,
  queued,
  failed,
  retired,
}

/// Prepares an explicitly requested download in its originating profile.
/// Once the queue accepts it, the existing device-job owner controls its lifetime.
class SourceDownload {
  const SourceDownload({
    this.clientFactory = http.Client.new,
    this.enqueue = _enqueue,
  });

  final http.Client Function() clientFactory;
  final Future<void> Function(String, Torrent, bool Function()) enqueue;

  static bool supports(Torrent source) => !MediaServerService.owns(source);

  static Future<void> _enqueue(
    String url,
    Torrent source,
    bool Function() canContinue,
  ) async {
    await DownloadService.instance.enqueueDownload(
      url: url,
      fileName: source.displayTitle,
      torrentName: source.displayTitle,
      canContinue: canContinue,
    );
  }

  /// [canContinue] is the requesting screen's lifetime. As before the
  /// refactor, it stops the action only up to "Resolving download URL…" (the
  /// IPTV episode lookup and the first authorization). From then on the
  /// accepted download is queued even if the user leaves; only a change of the
  /// captured profile session retires it.
  Future<SourceDownloadStatus> download(
    Torrent source, {
    required bool Function() canContinue,
    void Function(SourceDownloadStatus)? onProgress,
  }) {
    final owner = ProfileSessionMemory.captureOwner();
    bool ownerCurrent() => owner == ProfileSessionMemory.captureOwner();
    bool active() => ownerCurrent() && canContinue();
    Future<SourceDownloadStatus> run() async {
      if (!active()) return SourceDownloadStatus.retired;
      if (!supports(source)) return SourceDownloadStatus.unsupported;
      if (IptvSourceSearch.isDeferredXtreamSeries(source)) {
        onProgress?.call(SourceDownloadStatus.findingEpisode);
        final resolution = await IptvSourceSearch.resolveXtreamSeriesEpisode(
          source,
        );
        if (!active()) return SourceDownloadStatus.retired;
        if (resolution.source == null) {
          return resolution.status == IptvEpisodeResolutionStatus.missing
              ? SourceDownloadStatus.episodeMissing
              : SourceDownloadStatus.episodeUnavailable;
        }
        source = resolution.source!;
      }
      try {
        await DirectSourceAuthorization.authorize(source);
      } catch (_) {
        return active()
            ? SourceDownloadStatus.connectionChanged
            : SourceDownloadStatus.retired;
      }
      if (!active()) return SourceDownloadStatus.retired;
      final raw = source.directUrl ?? '';
      if (raw.isEmpty) return SourceDownloadStatus.noUrl;
      onProgress?.call(SourceDownloadStatus.resolving);
      final resolved = await _resolve(raw, ownerCurrent);
      if (!ownerCurrent()) return SourceDownloadStatus.retired;
      try {
        await DirectSourceAuthorization.authorize(source);
        if (!ownerCurrent()) return SourceDownloadStatus.retired;
        await enqueue(resolved, source, ownerCurrent);
        return ownerCurrent()
            ? SourceDownloadStatus.queued
            : SourceDownloadStatus.retired;
      } catch (_) {
        return ownerCurrent()
            ? SourceDownloadStatus.failed
            : SourceDownloadStatus.retired;
      }
    }

    final scope = owner.scope;
    return scope == null
        ? ProfileRuntime.withoutCapturedScope(run)
        : ProfileRuntime.withCapturedScope(scope, run);
  }

  /// Preserve the legacy ten-hop, relative-location, best-effort HEAD policy.
  Future<String> _resolve(String url, bool Function() active) async {
    var current = url;
    for (var redirects = 0; redirects < 10 && active(); redirects++) {
      try {
        final uri = Uri.parse(current);
        final client = clientFactory();
        try {
          final request = http.Request('HEAD', uri)..followRedirects = false;
          request.headers['User-Agent'] =
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
          final response = await client
              .send(request)
              .timeout(const Duration(seconds: 10));
          if (!active()) return current;
          if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
            final location = response.headers['location'];
            if (location != null && location.isNotEmpty) {
              current = uri.resolve(location).toString();
              continue;
            }
          }
          return current;
        } finally {
          client.close();
        }
      } catch (_) {
        break;
      }
    }
    return current;
  }
}

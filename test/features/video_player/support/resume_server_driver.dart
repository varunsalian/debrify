import 'dart:convert';
import 'package:debrify/models/media_server.dart';
import 'package:debrify/models/media_server_library.dart';
import 'package:debrify/models/playback_resume_policy.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/media_server_client.dart';
import 'package:debrify/services/media_server_service.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'video_player_environment.dart';

class ResumeServerClient extends MockClient {
  ResumeServerClient(super.fn, this.onClose);
  final VoidCallback onClose;
  @override
  void close() {
    onClose();
    super.close();
  }
}

/// Existing factories plus real openLibrary().sources() identities. Neither
/// the watch controller nor its Expando targets are replaced by the fixture.
class ResumeServerDriver {
  ResumeServerDriver(this.t, this.f);
  final WidgetTester t;
  final VideoPlayerEnvironment f;
  final reports = <http.Request>[];
  final closed = <int>[];
  int clients = 0;
  Future<void> Function(http.Request)? beforeReport;

  /// Optional barrier at every synthetic server request, e.g. to hold the
  /// watch preparation reads; [heldRequest] marks the held ones for settle.
  Future<void> Function(http.Request)? beforeRequest;
  bool Function(http.Request)? heldRequest;
  final previousService = MediaServerService.clientFactory;
  final previousWatch = MediaServerWatchSync.clientFactory;
  late List<Torrent> sources;
  Future<void> prepare() async {
    MediaServerService.clientFactory = () {
      final id = clients++;
      return MediaServerClient(
        client: ResumeServerClient((request) async {
          final activity = f.actions.begin(
            'server:${request.method} ${request.url.path}',
            held: beforeReport != null || (heldRequest?.call(request) ?? false),
          );
          try {
            await beforeRequest?.call(request);
            Object response;
            final path = request.url.path;
            if (path.endsWith('/AuthenticateByName')) {
              response = {
                'User': {'Id': 'p14user'},
                'AccessToken': 'p14-synthetic-access',
                'ServerId': 'p14server',
              };
            } else if (path.endsWith('/System/Info')) {
              return http.Response('', 403);
            } else if (path.endsWith('/System/Info/Public')) {
              response = {'Id': 'p14server'};
            } else if (path.endsWith('/Users/p14user')) {
              response = {
                'Id': 'p14user',
                'Policy': {'IsAdministrator': false},
              };
            } else if (path.contains('/Sessions/Playing') ||
                path.contains('/PlayedItems/')) {
              reports.add(request);
              await beforeReport?.call(request);
              return http.Response('', 204);
            } else if (path.endsWith('/PlaybackInfo')) {
              response = {
                'PlaySessionId': 'p14-watch',
                'MediaSources': [
                  for (final height in [1080, 2160])
                    {
                      'Id': 'version_$height',
                      'SupportsDirectPlay': true,
                      'Protocol': 'File',
                      'Container': 'mkv',
                      'Size': 12345678,
                      'MediaStreams': [
                        {'Type': 'Video', 'Height': height, 'Codec': 'hevc'},
                      ],
                    },
                ],
              };
            } else if (path.contains('/Users/p14user/Items/')) {
              response = {
                'Id': 'item1',
                'Name': 'P14 library recording',
                'Type': 'Video',
                'RunTimeTicks': 1200000 * 10000,
                'UserData': {
                  'Played': false,
                  'PlaybackPositionTicks': 0,
                  'LastPlayedDate': '2026-01-01T00:00:00Z',
                },
              };
            } else {
              throw StateError('Unexpected synthetic server endpoint $path');
            }
            return http.Response(jsonEncode(response), 200);
          } finally {
            activity.complete();
          }
        }, () => closed.add(id)),
      );
    };
    MediaServerWatchSync.clientFactory = () =>
        MediaServerService.clientFactory();
    await f.finish(t, MediaServerWatchSync.setEnabled(true));
    await f.finish(
      t,
      MediaServerService.connect(
        kind: MediaServerKind.jellyfin,
        label: 'P14 synthetic library',
        baseUrl: 'https://server.test/base/',
        username: 'p14-user',
        password: 'p14-synthetic-password',
      ),
    );
    final connection = (await f.finish(
      t,
      MediaServerService.connections(),
    )).single;
    final library = await f.finish(
      t,
      MediaServerService.openLibrary(connection.id),
    );
    sources = await f.finish(
      t,
      library.sources(
        MediaServerLibraryItem.fromJson({'Id': 'item1', 'Type': 'Video'}),
      ),
    );
    expect(sources, hasLength(2));
    expect(MediaServerService.watchTargetFor(sources.first), isNotNull);
  }

  VideoPlayerScreen screen() {
    final source = sources.first;
    final target = MediaServerService.watchTargetFor(source)!;
    return VideoPlayerScreen(
      videoUrl: source.directUrl!,
      title: source.displayTitle,
      httpHeaders: source.httpHeaders,
      contentImdbId: target.contentId,
      contentType: target.isMovie ? 'movie' : 'series',
      contentTitle: 'P14 library recording',
      contentSeason: target.season,
      contentEpisode: target.episode,
      stremioSources: sources,
      stremioCurrentSourceIndex: 0,
      resolveStremioSource: (source) async => source.directUrl,
      resumePolicy: PlaybackResumePolicy.catalogCanonical,
    );
  }

  Map<String, dynamic> body(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;
  Future<void> disposePlayback() async {
    final before = closed.length;
    await t.pumpWidget(const SizedBox.shrink());
    await f.until(t, () => f.player.disposed.isCompleted);
    await f.until(
      t,
      () => closed.length > before,
      reason:
          'Original server watch client closes before fixture transport resets',
    );
    await f.actions.settle(t);
  }

  void restoreFactories() {
    MediaServerService.clientFactory = previousService;
    MediaServerWatchSync.clientFactory = previousWatch;
  }
}

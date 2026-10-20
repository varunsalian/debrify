import 'dart:convert';

import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

const _first = PlaylistEntry(url: 'https://player.test/r0.mp4', title: 'r0');

/// Starts on a plain entry, then Next lands on the lazy [entry] through the
/// ordinary playlist load (not the startup resolver).
Future<TvEpisodeDriver> _start(
  WidgetTester t,
  PlaylistEntry entry, {
  Future<void> Function(TvEpisodeDriver d)? seed,
  http.Response? Function(http.Request request)? network,
}) async {
  final d = TvEpisodeDriver(t);
  await d.initialize();
  if (seed != null) await seed(d);
  d.f.network.handler = (r) => network?.call(r) ?? http.Response('{}', 404);
  await d.mount(
    screen: VideoPlayerScreen(
      videoUrl: _first.url,
      title: 'Lazy',
      viewMode: PlaylistViewMode.raw,
      disableAutoResume: true,
      startIndex: 0,
      playlist: [_first, entry],
    ),
  );
  return d;
}

Future<void> _next(TvEpisodeDriver d) async {
  final dynamic callback = playerControls(d.t).onNext!;
  await d.f.finish<dynamic>(
    d.t,
    d.observe<dynamic>(() => callback()) as Future<dynamic>,
  );
  await d.f.advance(d.t, const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'P18 Torbox torrent entry resolves through requestdl with its ids and opens the link',
    (t) async {
      final requests = <Uri>[];
      final d = await _start(
        t,
        const PlaylistEntry(
          url: '',
          title: 'tb',
          provider: 'torbox',
          torboxTorrentId: 41,
          torboxFileId: 7,
        ),
        seed: (d) => d.f.finish(t, TorboxStorage.saveTorboxApiKey('tb-key')),
        network: (r) {
          if (r.url.path.endsWith('/torrents/requestdl')) {
            requests.add(r.url);
            return http.Response(
              jsonEncode({'success': true, 'data': 'https://cdn.test/tb.mkv'}),
              200,
            );
          }
          return null;
        },
      );
      try {
        await _next(d);
        expect(requests, hasLength(1));
        expect(requests.single.queryParameters['torrent_id'], '41');
        expect(requests.single.queryParameters['file_id'], '7');
        expect(requests.single.queryParameters['token'], 'tb-key');
        expect(d.opens.last.uri, 'https://cdn.test/tb.mkv');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Torbox web-download entry prefers the webdl API over the torrent API',
    (t) async {
      final paths = <String>[];
      final d = await _start(
        t,
        const PlaylistEntry(
          url: '',
          title: 'web',
          torboxTorrentId: 41,
          torboxWebDownloadId: 99,
          torboxFileId: 3,
        ),
        seed: (d) => d.f.finish(t, TorboxStorage.saveTorboxApiKey('tb-key')),
        network: (r) {
          if (r.url.host == 'api.torbox.app') {
            paths.add(r.url.path);
            return http.Response(
              jsonEncode({'success': true, 'data': 'https://cdn.test/web.mkv'}),
              200,
            );
          }
          return null;
        },
      );
      try {
        await _next(d);
        expect(paths, ['/v1/api/webdl/requestdl']);
        expect(d.opens.last.uri, 'https://cdn.test/web.mkv');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Torbox entry without an API key reports the reason and opens nothing',
    (t) async {
      final d = await _start(
        t,
        const PlaylistEntry(
          url: '',
          title: 'tb',
          torboxTorrentId: 41,
          torboxFileId: 7,
        ),
      );
      try {
        final before = d.opens.length;
        await _next(d);
        expect(
          find.text('Failed to prepare video: Missing Torbox API key'),
          findsOneWidget,
        );
        expect(d.opens.length, before);
        expect(d.opens.last.uri, _first.url);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Real-Debrid restricted link is unrestricted with the stored key',
    (t) async {
      final bodies = <String>[];
      final auth = <String?>[];
      final d = await _start(
        t,
        const PlaylistEntry(
          url: '',
          title: 'rd',
          restrictedLink: 'https://real-debrid.com/d/ABC',
        ),
        seed: (d) => d.f.finish(t, RealDebridStorage.saveApiKey('rd-key')),
        network: (r) {
          if (r.url.path.endsWith('/unrestrict/link')) {
            bodies.add(r.body);
            auth.add(r.headers['authorization'] ?? r.headers['Authorization']);
            return http.Response(
              jsonEncode({'download': 'https://cdn.test/rd.mkv'}),
              200,
            );
          }
          return null;
        },
      );
      try {
        await _next(d);
        expect(
          bodies.single,
          contains(Uri.encodeQueryComponent('https://real-debrid.com/d/ABC')),
        );
        expect(auth.single, 'Bearer rd-key');
        expect(d.opens.last.uri, 'https://cdn.test/rd.mkv');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Real-Debrid empty download field becomes a preparation failure',
    (t) async {
      final d = await _start(
        t,
        const PlaylistEntry(
          url: '',
          title: 'rd',
          restrictedLink: 'https://real-debrid.com/d/ABC',
        ),
        seed: (d) => d.f.finish(t, RealDebridStorage.saveApiKey('rd-key')),
        network: (r) => r.url.path.endsWith('/unrestrict/link')
            ? http.Response(jsonEncode({'download': ''}), 200)
            : null,
      );
      try {
        final before = d.opens.length;
        await _next(d);
        expect(
          find.textContaining(
            'Failed to prepare video: Real Debrid link failed:',
          ),
          findsOneWidget,
        );
        expect(d.opens.length, before);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P18 AllDebrid locked link is unlocked on demand', (t) async {
    final unlocked = <String>[];
    final d = await _start(
      t,
      const PlaylistEntry(
        url: '',
        title: 'ad',
        allDebridLink: 'https://alldebrid.com/f/LOCK',
      ),
      seed: (d) =>
          d.f.finish(t, AllDebridStorage.saveAllDebridApiKey('ad-key')),
      network: (r) {
        if (r.url.path.endsWith('/link/unlock')) {
          unlocked.add(r.body);
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {'link': 'https://cdn.test/ad.mkv'},
            }),
            200,
          );
        }
        return null;
      },
    );
    try {
      await _next(d);
      expect(unlocked, hasLength(1));
      expect(d.opens.last.uri, 'https://cdn.test/ad.mkv');
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P18 Premiumize cloud item id re-fetches a fresh link before the infohash path',
    (t) async {
      final paths = <String>[];
      final d = await _start(
        t,
        const PlaylistEntry(
          url: '',
          title: 'pm',
          premiumizeItemId: 'item-5',
          premiumizeHash: 'abc',
          premiumizePath: 'Show/ep.mkv',
        ),
        seed: (d) =>
            d.f.finish(t, PremiumizeStorage.savePremiumizeApiKey('pm-key')),
        network: (r) {
          if (r.url.host == 'www.premiumize.me') {
            paths.add(r.url.path);
            return http.Response(
              jsonEncode({
                'status': 'success',
                'name': 'ep.mkv',
                'link': 'https://cdn.test/pm-item.mkv',
              }),
              200,
            );
          }
          return null;
        },
      );
      try {
        await _next(d);
        expect(paths, ['/api/item/details']);
        expect(d.opens.last.uri, 'https://cdn.test/pm-item.mkv');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Premiumize infohash entry picks the direct link whose path matches',
    (t) async {
      final d = await _start(
        t,
        const PlaylistEntry(
          url: '',
          title: 'pm',
          provider: 'premiumize',
          premiumizeHash: 'abc',
          premiumizePath: 'Show/ep2.mkv',
        ),
        seed: (d) =>
            d.f.finish(t, PremiumizeStorage.savePremiumizeApiKey('pm-key')),
        network: (r) => r.url.path.endsWith('/transfer/directdl')
            ? http.Response(
                jsonEncode({
                  'status': 'success',
                  'content': [
                    {
                      'path': 'Show/ep1.mkv',
                      'size': 1,
                      'link': 'https://cdn.test/ep1.mkv',
                    },
                    {
                      'path': 'Show/ep2.mkv',
                      'size': 1,
                      'link': 'https://cdn.test/ep2.mkv',
                    },
                  ],
                }),
                200,
              )
            : null,
      );
      try {
        await _next(d);
        expect(d.opens.last.uri, 'https://cdn.test/ep2.mkv');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 entry without any link metadata reports it and keeps the current item',
    (t) async {
      final d = await _start(t, const PlaylistEntry(url: '', title: 'bare'));
      try {
        final before = d.opens.length;
        await _next(d);
        expect(
          find.text(
            'Failed to prepare video: No URL metadata available for this entry',
          ),
          findsOneWidget,
        );
        expect(d.opens.length, before);
      } finally {
        await d.close();
      }
    },
  );
}

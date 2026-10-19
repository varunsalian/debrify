import 'dart:convert';

import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

const _first = PlaylistEntry(url: 'https://player.test/f0.mp4', title: 'f0');

typedef _Seed = Future<void> Function(TvEpisodeDriver d);

Future<void> _torbox(TvEpisodeDriver d) =>
    d.f.finish(d.t, TorboxStorage.saveTorboxApiKey('tb-key'));

Future<void> _premiumize(TvEpisodeDriver d) =>
    d.f.finish(d.t, PremiumizeStorage.savePremiumizeApiKey('pm-key'));

Future<void> _allDebrid(TvEpisodeDriver d) =>
    d.f.finish(d.t, AllDebridStorage.saveAllDebridApiKey('ad-key'));

http.Response _directdl(String link) => http.Response(
  jsonEncode({
    'status': 'success',
    'content': [
      {'path': 'Show/ep.mkv', 'size': 1, 'link': link},
    ],
  }),
  200,
);

/// One lazy entry whose resolution fails with a provider-specific reason.
class _Case {
  const _Case(this.label, this.entry, this.message, {this.seed, this.network});

  final String label;
  final PlaylistEntry entry;

  /// The snackbar text after the 'Failed to prepare video: ' prefix starts
  /// with this.
  final String message;
  final _Seed? seed;
  final http.Response? Function(http.Request request)? network;
}

final _cases = <_Case>[
  const _Case(
    'a Torbox provider without file ids',
    PlaylistEntry(url: '', title: 'tb', provider: 'TorBox'),
    'Torbox file metadata missing',
  ),
  const _Case(
    'a Torbox file id without a torrent or web download',
    PlaylistEntry(url: '', title: 'tb', provider: 'torbox', torboxFileId: 7),
    'Torbox file metadata missing',
  ),
  _Case(
    'a Torbox web download whose link request fails',
    const PlaylistEntry(
      url: '',
      title: 'web',
      torboxWebDownloadId: 99,
      torboxFileId: 3,
    ),
    'Torbox link failed: ',
    seed: _torbox,
    network: (r) => r.url.path.endsWith('/webdl/requestdl')
        ? http.Response('{"success":false,"detail":"gone"}', 500)
        : null,
  ),
  _Case(
    'a Torbox link answered with an empty URL',
    const PlaylistEntry(
      url: '',
      title: 'tb',
      torboxTorrentId: 41,
      torboxFileId: 7,
    ),
    'Torbox link failed: ',
    seed: _torbox,
    network: (r) => r.url.path.endsWith('/torrents/requestdl')
        ? http.Response(jsonEncode({'success': true, 'data': ''}), 200)
        : null,
  ),
  const _Case(
    'a PikPak provider without a file id',
    PlaylistEntry(url: '', title: 'pk', provider: 'PikPak'),
    'PikPak file metadata missing',
  ),
  const _Case(
    'a PikPak file id the service cannot resolve',
    PlaylistEntry(url: '', title: 'pk', pikpakFileId: 'pk-9'),
    'PikPak link failed: ',
  ),
  const _Case(
    'a Premiumize cloud item without an API key',
    PlaylistEntry(url: '', title: 'pm', premiumizeItemId: 'item-5'),
    'Missing Premiumize API key',
  ),
  _Case(
    'a Premiumize cloud item that no longer exists',
    const PlaylistEntry(url: '', title: 'pm', premiumizeItemId: 'item-5'),
    'Premiumize link failed: Exception: File not found in Premiumize cloud',
    seed: _premiumize,
    network: (r) => r.url.path.endsWith('/item/details')
        ? http.Response('{"status":"error"}', 200)
        : null,
  ),
  const _Case(
    'a Premiumize provider without hash and path',
    PlaylistEntry(url: '', title: 'pm', provider: 'Premiumize'),
    'Premiumize file metadata missing',
  ),
  const _Case(
    'a Premiumize hash with an empty path',
    PlaylistEntry(
      url: '',
      title: 'pm',
      premiumizeHash: 'abc',
      premiumizePath: '',
    ),
    'Premiumize file metadata missing',
  ),
  const _Case(
    'a Premiumize hash without an API key',
    PlaylistEntry(
      url: '',
      title: 'pm',
      premiumizeHash: 'abc',
      premiumizePath: 'Show/ep.mkv',
    ),
    'Missing Premiumize API key',
  ),
  _Case(
    'a Premiumize hash whose path is not in the transfer',
    const PlaylistEntry(
      url: '',
      title: 'pm',
      premiumizeHash: 'abc',
      premiumizePath: 'Show/other.mkv',
    ),
    'Premiumize link failed: Exception: File not found in Premiumize cloud',
    seed: _premiumize,
    network: (r) => r.url.path.endsWith('/transfer/directdl')
        ? _directdl('https://cdn.test/ep.mkv')
        : null,
  ),
  _Case(
    'a Premiumize match with an empty link',
    const PlaylistEntry(
      url: '',
      title: 'pm',
      premiumizeHash: 'abc',
      premiumizePath: 'Show/ep.mkv',
    ),
    'Premiumize link failed: ',
    seed: _premiumize,
    network: (r) =>
        r.url.path.endsWith('/transfer/directdl') ? _directdl('') : null,
  ),
  const _Case(
    'a Real-Debrid restricted link without an API key',
    PlaylistEntry(
      url: '',
      title: 'rd',
      restrictedLink: 'https://real-debrid.com/d/ABC',
    ),
    'Missing Real Debrid API key',
  ),
  const _Case(
    'an AllDebrid provider without a locked link',
    PlaylistEntry(url: '', title: 'ad', provider: 'AllDebrid'),
    'AllDebrid link metadata missing',
  ),
  const _Case(
    'an AllDebrid locked link without an API key',
    PlaylistEntry(
      url: '',
      title: 'ad',
      allDebridLink: 'https://alldebrid.com/f/LOCK',
    ),
    'Missing AllDebrid API key',
  ),
  _Case(
    'an AllDebrid unlock the service rejects',
    const PlaylistEntry(
      url: '',
      title: 'ad',
      allDebridLink: 'https://alldebrid.com/f/LOCK',
    ),
    'AllDebrid link failed: ',
    seed: _allDebrid,
    network: (r) => r.url.path.endsWith('/link/unlock')
        ? http.Response(
            jsonEncode({
              'status': 'error',
              'error': {'code': 'LINK_DOWN', 'message': 'down'},
            }),
            200,
          )
        : null,
  ),
];

void main() {
  for (final c in _cases) {
    testWidgets('P18 Next to ${c.label} explains why and keeps playing', (
      t,
    ) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        if (c.seed != null) await c.seed!(d);
        d.f.network.handler = (r) =>
            c.network?.call(r) ?? http.Response('{}', 404);
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _first.url,
            title: 'Lazy',
            viewMode: PlaylistViewMode.raw,
            disableAutoResume: true,
            startIndex: 0,
            playlist: [_first, c.entry],
          ),
        );
        final before = d.opens.length;
        final dynamic next = playerControls(t).onNext!;
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => next()) as Future<dynamic>,
        );
        final expected = 'Failed to prepare video: ${c.message}';
        bool shown() => find
            .byWidgetPredicate(
              (w) => w is Text && (w.data ?? '').startsWith(expected),
            )
            .evaluate()
            .isNotEmpty;
        for (var i = 0; i < 40 && !shown(); i++) {
          await d.f.advance(t, const Duration(milliseconds: 500));
        }
        expect(shown(), isTrue, reason: expected);
        expect(d.opens.length, before);
        expect(d.opens.last.uri, _first.url);
      } finally {
        await d.close();
      }
    });
  }
}

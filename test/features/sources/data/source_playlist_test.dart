import 'package:debrify/features/sources/data/source_playlist.dart';
import 'package:debrify/features/sources/models/acquired_source.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'automatic_source_binding_owner_test.dart' show source;

void main() {
  for (final pack in [false, true]) {
    for (final provider in [
      'debrid',
      'torbox',
      'premiumize',
      'alldebrid',
      'pikpak',
    ]) {
      test(
        '$provider ${pack ? 'collection' : 'single'} persists native identity without expiring URLs',
        () {
          final acquired = AcquiredSource(
            title: 'Title',
            playUrl: 'https://expired',
            downloadUrls: ['https://expired'],
            fileName: 'Movie.mkv',
            rdTorrentId: 'rd',
            torboxTorrentId: 42,
            torboxFileId: 1,
            premiumizePath: '/Movie.mkv',
            allDebridLink: 'https://locked-ad',
            restrictedLink: 'https://locked-rd',
            pikpakFileId: 'folder',
            pikpakVideoFileId: 'video',
            playlist: pack
                ? const [
                    PlaylistEntry(
                      url: '',
                      title: 'first',
                      torboxFileId: 1,
                      pikpakFileId: 'one',
                    ),
                    PlaylistEntry(
                      url: '',
                      title: 'second',
                      torboxFileId: 2,
                      pikpakFileId: 'two',
                    ),
                  ]
                : null,
          );
          final item = SourcePlaylist.describe(
            acquired,
            source('hash'),
            provider,
            meta: const PlaybackMeta(
              imdbId: 'tt123',
              contentType: 'movie',
              posterUrl: 'https://poster',
            ),
          );
          expect(
            item['provider'],
            provider == 'debrid' ? 'realdebrid' : provider,
          );
          expect(item['kind'], pack ? 'collection' : 'single');
          expect(item['torrent_hash'], 'hash');
          expect(item['imdbId'], 'tt123');
          expect(item['posterUrl'], 'https://poster');
          expect(item.values, isNot(contains('https://expired')));
          expect(item['count'], pack ? 2 : null);
          switch (provider) {
            case 'debrid':
              expect(item['rdTorrentId'], 'rd');
              expect(item['restrictedLink'], pack ? null : 'https://locked-rd');
              expect(item['url'], pack ? null : '');
            case 'torbox':
              expect(item['torboxTorrentId'], 42);
              expect(item['torboxFileIds'], pack ? [1, 2] : null);
              expect(item['torboxFileId'], pack ? null : 1);
            case 'premiumize':
              expect(item['premiumizePath'], pack ? null : '/Movie.mkv');
            case 'alldebrid':
              expect(item['allDebridLink'], pack ? null : 'https://locked-ad');
            case 'pikpak':
              expect(item['pikpakFileId'], pack ? 'folder' : 'video');
              expect(item['pikpakFileIds'], pack ? ['one', 'two'] : null);
          }
        },
      );
    }
  }
}

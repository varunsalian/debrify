import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:flutter_test/flutter_test.dart';

// Exercise the original public model before moving its declaration. Keep this
// import on the legacy path so the same contract proves compatibility afterward.
void main() {
  const full = PlaylistEntry(
    url: '',
    title: 'Original 日本語',
    hdVideoUrl: 'https://video.invalid/hd',
    audioUrl: 'https://audio.invalid/separate',
    relativePath: '/Season 2/Episode 3.mkv',
    restrictedLink: ' locked link ',
    torrentHash: 'AbCd',
    sizeBytes: 0,
    provider: 'realdebrid',
    torboxTorrentId: 0,
    torboxWebDownloadId: 11,
    torboxFileId: 12,
    pikpakFileId: 'pikpak-file',
    rdTorrentId: 'rd-torrent',
    rdLinkIndex: -1,
    premiumizeHash: 'pm-hash',
    premiumizePath: 'nested/episode.mkv',
    premiumizeItemId: 'pm-item',
    allDebridLink: 'https://alldebrid.invalid/locked',
  );

  test('constructor retains independent lazy-provider and audio metadata', () {
    expect(metadata(full), {
      'url': '',
      'hdVideoUrl': 'https://video.invalid/hd',
      'audioUrl': 'https://audio.invalid/separate',
      'relativePath': '/Season 2/Episode 3.mkv',
      'restrictedLink': ' locked link ',
      'torrentHash': 'AbCd',
      'sizeBytes': 0,
      'provider': 'realdebrid',
      'torboxTorrentId': 0,
      'torboxWebDownloadId': 11,
      'torboxFileId': 12,
      'pikpakFileId': 'pikpak-file',
      'rdTorrentId': 'rd-torrent',
      'rdLinkIndex': -1,
      'premiumizeHash': 'pm-hash',
      'premiumizePath': 'nested/episode.mkv',
      'premiumizeItemId': 'pm-item',
      'allDebridLink': 'https://alldebrid.invalid/locked',
    });
    expect(full.title, 'Original 日本語');
  });

  test(
    'renaming preserves every other field and leaves the source unchanged',
    () {
      for (final title in ['', 'S02E03 café']) {
        final copy = full.copyWithTitle(title);
        expect(copy.title, title);
        expect(metadata(copy), metadata(full));
        expect(identical(copy, full), isFalse);
        expect(full.title, 'Original 日本語');
      }
    },
  );

  test('minimal entries keep optional metadata null when renamed', () {
    const entry = PlaylistEntry(url: 'fallback-url', title: 'old');
    final copy = entry.copyWithTitle('new');
    expect(copy.url, 'fallback-url');
    expect(copy.title, 'new');
    final optional = metadata(copy)..remove('url');
    expect(optional.values, everyElement(isNull));
    expect(metadata(copy), metadata(entry));
  });
}

Map<String, Object?> metadata(PlaylistEntry entry) => {
  'url': entry.url,
  'hdVideoUrl': entry.hdVideoUrl,
  'audioUrl': entry.audioUrl,
  'relativePath': entry.relativePath,
  'restrictedLink': entry.restrictedLink,
  'torrentHash': entry.torrentHash,
  'sizeBytes': entry.sizeBytes,
  'provider': entry.provider,
  'torboxTorrentId': entry.torboxTorrentId,
  'torboxWebDownloadId': entry.torboxWebDownloadId,
  'torboxFileId': entry.torboxFileId,
  'pikpakFileId': entry.pikpakFileId,
  'rdTorrentId': entry.rdTorrentId,
  'rdLinkIndex': entry.rdLinkIndex,
  'premiumizeHash': entry.premiumizeHash,
  'premiumizePath': entry.premiumizePath,
  'premiumizeItemId': entry.premiumizeItemId,
  'allDebridLink': entry.allDebridLink,
};

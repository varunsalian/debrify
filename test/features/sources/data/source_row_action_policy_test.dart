import 'package:debrify/features/sources/data/source_row_action_policy.dart';
import 'package:debrify/features/sources/models/source_row_actions.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent row(StreamType type) => Torrent(
  rowid: 1,
  infohash: 'fixture',
  name: 'Fixture',
  source: 'fixture',
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: type,
);

void main() {
  late List<String> calls;
  late SourceRowActionPolicy policy;
  var media = false;
  var iptv = false;
  var allowed = true;
  var supports = true;
  var copyable = true;
  setUp(() {
    calls = [];
    media = iptv = false;
    allowed = supports = copyable = true;
    policy = SourceRowActionPolicy(
      isMediaServer: (_) {
        calls.add('media');
        return media;
      },
      isIptv: (_) {
        calls.add('iptv');
        return iptv;
      },
      downloadsAllowed: () {
        calls.add('permission');
        return allowed;
      },
    );
  });
  SourceRowActions project(StreamType type) => policy.project(
    row(type),
    canCopy: (_) {
      calls.add('copy');
      return copyable;
    },
    supportsDownload: (_) {
      calls.add('download');
      return supports;
    },
  );

  for (final canCopy in [false, true]) {
    test('torrent copy eligibility=$canCopy never queries stream services', () {
      copyable = canCopy;
      final result = project(StreamType.torrent);
      expect(result.kind, SourceRowActionKind.torrent);
      expect(result.canPin, isTrue);
      expect(result.canCopy, canCopy);
      expect(result.canDownload, isFalse);
      expect(calls, ['copy']);
    });
  }

  test('external link cannot pin and bypasses both source classifiers', () {
    media = iptv = true;
    copyable = false;
    final result = project(StreamType.externalUrl);
    expect(result.kind, SourceRowActionKind.external);
    expect(result.canPin, isFalse);
    expect(result.canCopy, isTrue);
    expect(result.canDownload, isTrue);
    expect(calls, ['permission', 'download']);
  });

  test(
    'media-server classification precedes IPTV and retains direct actions',
    () {
      media = iptv = true;
      final result = project(StreamType.directUrl);
      expect(result.kind, SourceRowActionKind.mediaServer);
      expect(result.canPin, isTrue);
      expect(result.canCopy, isTrue);
      expect(result.canDownload, isTrue);
      expect(calls, ['media', 'permission', 'download']);
    },
  );

  for (final isIptv in [false, true]) {
    test('direct classifier falls through to IPTV=$isIptv then addon', () {
      iptv = isIptv;
      final result = project(StreamType.directUrl);
      expect(
        result.kind,
        isIptv ? SourceRowActionKind.iptv : SourceRowActionKind.addon,
      );
      expect(result.canPin, isTrue);
      expect(result.canCopy, isTrue);
      expect(result.canDownload, isTrue);
      expect(calls, ['media', 'iptv', 'permission', 'download']);
    });
  }

  test(
    'denied permission skips download lookup and is read on each projection',
    () {
      allowed = false;
      expect(project(StreamType.directUrl).canDownload, isFalse);
      expect(calls, ['media', 'iptv', 'permission']);
      calls.clear();
      allowed = true;
      expect(project(StreamType.directUrl).canDownload, isTrue);
      expect(calls, ['media', 'iptv', 'permission', 'download']);
    },
  );

  test('unsupported stream retains copy/pin but never offers download', () {
    supports = false;
    final result = project(StreamType.directUrl);
    expect(result.canDownload, isFalse);
    expect(result.canCopy, isTrue);
    expect(result.canPin, isTrue);
  });
}

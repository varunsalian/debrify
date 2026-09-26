import 'dart:async';

import 'package:debrify/features/sources/data/source_link_copier.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent source({
  bool deferred = false,
  String? url,
  int? season = 1,
  String? episode = 'S01E02',
  String? magnet,
}) => Torrent(
  rowid: 1,
  infohash: 'fixture',
  name: 'Fixture',
  source: deferred ? 'iptv:fixture' : 'fixture',
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  hasRealInfoHash: false,
  streamType: StreamType.directUrl,
  directUrl: url,
  magnetUrl: magnet,
  iptvCatalogType: deferred ? 'series' : null,
  iptvEntryKey: deferred ? 'series:12' : null,
  seasonNumber: season,
  episodeIdentifier: episode,
);

void main() {
  late SourceLinkCopier copier;
  late List<String> events;
  late Completer<IptvEpisodeResolution> resolution;
  late Completer<void> clipboard;
  var active = true;
  setUp(() {
    events = [];
    resolution = Completer<IptvEpisodeResolution>();
    clipboard = Completer<void>();
    active = true;
    copier = SourceLinkCopier(
      isDeferredEpisode: IptvSourceSearch.isDeferredXtreamSeries,
      resolveEpisode: (_) {
        events.add('resolve');
        return resolution.future;
      },
      writeText: (text) {
        events.add('write:$text');
        return clipboard.future;
      },
    );
  });
  Future<SourceLinkCopyResult> copy(Torrent torrent) => copier.copy(
    torrent,
    canContinue: () => active,
    onResolving: () => events.add('resolving'),
  );

  test(
    'copy eligibility retains links and requires an exact episode target',
    () {
      expect(copier.canCopy(source(url: 'https://example.com/movie')), isTrue);
      expect(copier.canCopy(source(deferred: true)), isTrue);
      expect(copier.canCopy(source(deferred: true, episode: 's01e02')), isTrue);
      expect(copier.canCopy(source(deferred: true, season: null)), isFalse);
      expect(copier.canCopy(source(deferred: true, episode: 'S01')), isFalse);
      expect(copier.canCopy(source()), isFalse);
    },
  );

  for (final link in ['https://example.com/movie', 'magnet:?xt=urn:btih:abc']) {
    test('ready link copies without episode resolution: $link', () async {
      final pending = copy(
        link.startsWith('magnet:') ? source(magnet: link) : source(url: link),
      );
      expect(events, ['write:$link']);
      clipboard.complete();
      expect(await pending, SourceLinkCopyResult.copied);
    });
  }

  test('missing episode target requests selection before any I/O', () async {
    expect(
      await copy(source(deferred: true, episode: null)),
      SourceLinkCopyResult.chooseEpisode,
    );
    expect(events, isEmpty);
  });

  test('linkless source performs no clipboard write', () async {
    expect(await copy(source()), SourceLinkCopyResult.noLink);
    expect(events, isEmpty);
  });

  test(
    'deferred resolution precedes exactly one awaited clipboard write',
    () async {
      final pending = copy(source(deferred: true));
      expect(events, ['resolving', 'resolve']);
      resolution.complete(
        IptvEpisodeResolution(
          IptvEpisodeResolutionStatus.resolved,
          source(url: 'https://example.com/episode'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, [
        'resolving',
        'resolve',
        'write:https://example.com/episode',
      ]);
      var finished = false;
      unawaited(pending.then((_) => finished = true));
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      clipboard.complete();
      expect(await pending, SourceLinkCopyResult.copied);
    },
  );

  for (final status in IptvEpisodeResolutionStatus.values) {
    test('no resolved source retains the $status outcome', () async {
      final pending = copy(source(deferred: true));
      resolution.complete(IptvEpisodeResolution(status));
      expect(
        await pending,
        status == IptvEpisodeResolutionStatus.missing
            ? SourceLinkCopyResult.missingEpisode
            : SourceLinkCopyResult.unavailableEpisode,
      );
      expect(events, ['resolving', 'resolve']);
    });
  }

  test('a resolved descriptor without a usable link does not write', () async {
    final pending = copy(source(deferred: true));
    resolution.complete(
      IptvEpisodeResolution(IptvEpisodeResolutionStatus.resolved, source()),
    );
    expect(await pending, SourceLinkCopyResult.noLink);
    expect(events, ['resolving', 'resolve']);
  });

  test('retired entry performs no resolution, progress or write', () async {
    active = false;
    expect(await copy(source(deferred: true)), SourceLinkCopyResult.retired);
    expect(events, isEmpty);
  });

  test('retirement during resolution prevents a clipboard write', () async {
    final pending = copy(source(deferred: true));
    active = false;
    resolution.complete(
      IptvEpisodeResolution(
        IptvEpisodeResolutionStatus.resolved,
        source(url: 'https://example.com/episode'),
      ),
    );
    expect(await pending, SourceLinkCopyResult.retired);
    expect(events, ['resolving', 'resolve']);
  });

  test('retirement during the native write suppresses success', () async {
    final pending = copy(source(url: 'https://example.com/movie'));
    active = false;
    clipboard.complete();
    expect(await pending, SourceLinkCopyResult.retired);
    expect(events, ['write:https://example.com/movie']);
  });

  for (final step in ['resolve', 'write']) {
    test('$step errors propagate without retry', () async {
      final failure = StateError('fixture $step failure');
      final pending = copy(
        step == 'resolve'
            ? source(deferred: true)
            : source(url: 'https://example.com/movie'),
      );
      final assertion = expectLater(pending, throwsA(same(failure)));
      if (step == 'resolve') {
        resolution.completeError(failure);
      } else {
        clipboard.completeError(failure);
      }
      await assertion;
      expect(
        events.where((event) => event == 'resolve').length,
        step == 'resolve' ? 1 : 0,
      );
      expect(
        events.where((event) => event.startsWith('write:')).length,
        step == 'write' ? 1 : 0,
      );
    });
  }
}

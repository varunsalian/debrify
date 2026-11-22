import 'dart:async';

import 'package:debrify/features/sources/data/webdav_listing_cache.dart';
import 'package:debrify/features/sources/data/webdav_source_search.dart';
import 'package:debrify/features/sources/models/webdav_source_status.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_source_tickets.dart';
import 'package:flutter_test/flutter_test.dart';

const nas = WebDavConfig(
  id: 'nas',
  name: 'NAS',
  baseUrl: 'https://dav.example.com/remote/',
  username: 'me',
  password: 'secret',
);

const dune = AdvancedSearchSelection(
  imdbId: 'tt1160419',
  isSeries: false,
  title: 'Dune',
  year: '2021',
);

const severance = AdvancedSearchSelection(
  imdbId: 'tt11280740',
  isSeries: true,
  title: 'Severance',
  year: '2022',
  season: 1,
  episode: 3,
);

WebDavItem dir(String path) =>
    WebDavItem(name: path.split('/').last, path: '$path/', isDirectory: true);

WebDavItem file(String path, {int size = 2000000000}) => WebDavItem(
  name: path.split('/').last,
  path: path,
  isDirectory: false,
  sizeBytes: size,
);

/// A fake server: listings by folder path, with optional gates and failures.
class FakeServer {
  FakeServer(this.tree);

  final Map<String, List<WebDavItem>> tree;
  final calls = <String>[];
  final gates = <String, Completer<void>>{};
  final failures = <String, Object>{};
  var accessChecks = 0;
  Object? accessFailure;

  Future<List<WebDavItem>> list(WebDavConfig config, String path) async {
    calls.add(path);
    final gate = gates[path];
    if (gate != null) await gate.future;
    final failure = failures[path];
    if (failure != null) throw failure;
    return tree[path] ?? const [];
  }

  Future<void> checkAccess(WebDavConfig config) async {
    accessChecks++;
    if (accessFailure != null) throw accessFailure!;
  }
}

class Run {
  final statuses = <WebDavSourceStatus>[];
  final rows = <Torrent>[];
  late List<WebDavSourceStatus> result;
}

Future<Run> run(
  FakeServer server,
  AdvancedSearchSelection selection, {
  WebDavSearchLimits limits = const WebDavSearchLimits(),
  WebDavListingCache? cache,
  bool enabled = true,
  bool Function()? shouldContinue,
}) async {
  final out = Run();
  out.result =
      await WebDavSourceSearch(
        servers: () async => [nas],
        enabled: () async => enabled,
        listFolder: server.list,
        checkAccess: server.checkAccess,
        cache: cache ?? WebDavListingCache(),
        limits: limits,
      ).search(
        selection,
        onStatus: out.statuses.add,
        onRows: (key, rows) {
          expect(key, 'webdav:nas');
          out.rows.addAll(rows);
        },
        shouldContinue: shouldContinue ?? () => true,
      );
  return out;
}

void main() {
  setUp(() {
    ProfileRuntime.scope.value = ProfileScope(
      profileId: 'p1',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
  });

  test('finds a movie by opening only folders that can lead to it', () async {
    final server = FakeServer({
      '': [dir('Movies'), dir('Photos'), dir('Music'), file('notes.txt')],
      'Movies/': [dir('Movies/Dune (2021)'), dir('Movies/Dune (1984)')],
      'Movies/Dune (2021)/': [
        file('Movies/Dune (2021)/Dune.2021.2160p.mkv'),
        file('Movies/Dune (2021)/sample.mkv', size: 5000000),
        dir('Movies/Dune (2021)/Featurettes'),
      ],
    });
    final out = await run(server, dune);

    expect(server.calls, ['', 'Movies/', 'Movies/Dune (2021)/']);
    final row = out.rows.single;
    expect(row.name, 'Dune.2021.2160p.mkv');
    expect(row.source, 'webdav:nas');
    expect(row.streamType, StreamType.directUrl);
    expect(row.hasRealInfoHash, isFalse);
    expect(
      row.directUrl,
      startsWith('https://dav.example.com/remote/Movies/Dune'),
    );
    expect(
      row.httpHeaders!['authorization'] ?? row.httpHeaders!['Authorization'],
      startsWith('Basic '),
    );
    expect(row.addonDisplayName, 'WebDAV · NAS');
    expect(row.streamDescription, 'Movies/Dune (2021)');
    expect(out.statuses.first.phase, WebDavSearchPhase.searching);
    expect(out.statuses.last.phase, WebDavSearchPhase.done);
    expect(out.result.single.found, 1);
    expect(out.result.single.foldersChecked, 3);
    expect(out.result.single.hasIssue, isFalse);
  });

  test('finds an episode through show and season folders only', () async {
    final server = FakeServer({
      '': [dir('TV'), dir('Movies')],
      'TV/': [dir('TV/Severance'), dir('TV/Silo')],
      'TV/Severance/': [
        dir('TV/Severance/Season 1'),
        dir('TV/Severance/Season 2'),
      ],
      'TV/Severance/Season 1/': [
        file('TV/Severance/Season 1/03 - In Perpetuity.mkv'),
        file('TV/Severance/Season 1/04 - The You You Are.mkv'),
      ],
      'Movies/': [dir('Movies/Severance.S01E03.1080p.WEB')],
      'Movies/Severance.S01E03.1080p.WEB/': [
        file('Movies/Severance.S01E03.1080p.WEB/sev.103.mkv'),
        file('Movies/Severance.S01E03.1080p.WEB/Severance.S01E03.mkv'),
      ],
    });
    final out = await run(server, severance);

    expect(server.calls, isNot(contains('TV/Severance/Season 2/')));
    expect(server.calls, isNot(contains('TV/Silo/')));
    expect(out.rows.map((r) => r.name).toSet(), {
      '03 - In Perpetuity.mkv',
      'Severance.S01E03.mkv',
    });
    expect(out.rows.first.episodeIdentifier, 'S01E03');
    expect(out.rows.first.coverageType, 'singleEpisode');
  });

  test('stops at the folder budget and says how to be found faster', () async {
    final server = FakeServer({
      '': [
        dir('Movies'),
        dir('Films'),
        dir('Videos'),
        dir('Media'),
        dir('Library'),
      ],
    });
    final out = await run(
      server,
      dune,
      limits: const WebDavSearchLimits(maxFolders: 3),
    );
    expect(server.calls, hasLength(3));
    final status = out.result.single;
    expect(status.phase, WebDavSearchPhase.folderLimit);
    expect(status.foldersChecked, 3);
    expect(status.resultMessage, contains('Stopped after checking 3 folders'));
    expect(status.hasIssue, isTrue);
  });

  test(
    'a slow server explains itself, then times out keeping rows found',
    () async {
      final server = FakeServer({
        '': [file('Dune.2021.1080p.mkv'), dir('Movies')],
      });
      server.gates['Movies/'] = Completer<void>(); // Never answers.
      final out = await run(
        server,
        dune,
        limits: const WebDavSearchLimits(
          slowAfter: Duration(milliseconds: 20),
          timeLimit: Duration(milliseconds: 120),
        ),
      );
      expect(out.rows.single.name, 'Dune.2021.1080p.mkv');
      final slow = out.statuses.where((s) => s.searching && s.slow);
      expect(slow, isNotEmpty);
      expect(slow.first.progressMessage, contains('one folder at a time'));
      final status = out.result.single;
      expect(status.phase, WebDavSearchPhase.timedOut);
      // Rows were found, so stopping early is not worth a note.
      expect(status.resultMessage, isNull);
      expect(status.hasIssue, isFalse);
    },
  );

  test('an unreachable or rejected server fails with a plain reason', () async {
    final server = FakeServer({});
    server.failures[''] = const WebDavException(
      kind: WebDavErrorKind.authentication,
      message: 'denied',
      statusCode: 401,
    );
    final out = await run(server, dune);
    final status = out.result.single;
    expect(status.phase, WebDavSearchPhase.failed);
    expect(status.resultMessage, contains('rejected its sign-in'));
    expect(out.rows, isEmpty);

    final offline = FakeServer({});
    offline.failures[''] = const WebDavException(
      kind: WebDavErrorKind.network,
      message: 'down',
    );
    expect(
      (await run(offline, dune)).result.single.resultMessage,
      contains("Couldn't reach WebDAV · NAS"),
    );
  });

  test(
    'a folder that fails is skipped and reported, the rest continues',
    () async {
      final server = FakeServer({
        '': [dir('Movies'), dir('Films')],
        'Films/': [file('Films/Dune (2021).mkv')],
      });
      server.failures['Movies/'] = const WebDavException(
        kind: WebDavErrorKind.unexpectedStatus,
        message: '500',
      );
      final out = await run(server, dune);
      expect(out.rows.single.name, 'Dune (2021).mkv');
      final status = out.result.single;
      expect(status.phase, WebDavSearchPhase.done);
      expect(status.failedFolders, 1);
      // A match was found, so the skipped folder is not worth a warning.
      expect(status.resultMessage, isNull);

      final empty = FakeServer({
        '': [dir('Movies')],
      });
      empty.failures['Movies/'] = const WebDavException(
        kind: WebDavErrorKind.unexpectedStatus,
        message: '500',
      );
      expect(
        (await run(empty, dune)).result.single.resultMessage,
        contains('could not be opened'),
      );
    },
  );

  test('cancellation stops requests, progress and rows', () async {
    final server = FakeServer({
      '': [dir('Movies')],
      'Movies/': [file('Movies/Dune.2021.mkv')],
    });
    var live = true;
    server.gates[''] = Completer<void>();
    final pending = run(server, dune, shouldContinue: () => live);
    await Future<void>.delayed(Duration.zero);
    live = false;
    server.gates['']!.complete();
    final out = await pending;
    expect(out.result, isEmpty);
    expect(out.rows, isEmpty);
    expect(server.calls, ['']);
    expect(out.statuses.where((s) => !s.searching), isEmpty);
  });

  test('cached listings are reused but access is still rechecked', () async {
    final tree = {
      '': [dir('Movies')],
      'Movies/': [file('Movies/Dune.2021.mkv')],
    };
    final cache = WebDavListingCache();
    final first = FakeServer(tree);
    await run(first, dune, cache: cache);
    expect(first.calls, ['', 'Movies/']);

    final second = FakeServer(tree);
    final again = await run(second, dune, cache: cache);
    expect(second.calls, isEmpty);
    expect(second.accessChecks, 2);
    expect(again.rows.single.name, 'Dune.2021.mkv');

    final revoked = FakeServer(tree)
      ..accessFailure = const ResourceAuthorizationException('revoked');
    final denied = await run(revoked, dune, cache: cache);
    expect(denied.rows, isEmpty);
    expect(
      denied.result.single.resultMessage,
      contains('not available to this profile'),
    );
  });

  test('nothing is requested when disabled or not a title search', () async {
    final server = FakeServer({'': []});
    expect((await run(server, dune, enabled: false)).result, isEmpty);
    const season = AdvancedSearchSelection(
      imdbId: 'tt1',
      isSeries: true,
      title: 'Severance',
      season: 1,
    );
    expect((await run(server, season)).result, isEmpty);
    const channel = AdvancedSearchSelection(
      imdbId: 'x',
      isSeries: false,
      title: 'News',
      contentType: 'tv',
    );
    expect((await run(server, channel)).result, isEmpty);
    expect(server.calls, isEmpty);
  });

  test(
    'a found row plays only while its profile may still use the server',
    () async {
      final server = FakeServer({
        '': [file('Dune.2021.mkv')],
      });
      final row = (await run(server, dune)).rows.single;
      await WebDavSourceTickets.authorize(row);
      expect(server.accessChecks, 1);

      ProfileRuntime.scope.value = ProfileScope(
        profileId: 'p2',
        dataGeneration: 2,
        sessionEpoch: 2,
      );
      await expectLater(WebDavSourceTickets.authorize(row), throwsStateError);

      final copy = Torrent.fromJson(row.toJson());
      await expectLater(WebDavSourceTickets.authorize(copy), throwsStateError);
    },
  );

  test('a server that never answers is reported as not answering', () async {
    final server = FakeServer({});
    server.gates[''] = Completer<void>();
    final out = await run(
      server,
      dune,
      limits: const WebDavSearchLimits(timeLimit: Duration(milliseconds: 50)),
    );
    final status = out.result.single;
    expect(status.phase, WebDavSearchPhase.timedOut);
    expect(status.unreachable, isTrue);
    expect(status.resultMessage, contains("didn't answer in time"));
  });

  test(
    'an unexpected error skips the folder instead of blaming access',
    () async {
      final server = FakeServer({
        '': [dir('Movies'), dir('Films')],
        'Films/': [file('Films/Dune (2021).mkv')],
      });
      server.failures['Movies/'] = StateError('parser bug');
      final out = await run(server, dune);
      expect(out.rows.single.name, 'Dune (2021).mkv');
      expect(out.result.single.failedFolders, 1);
    },
  );

  test('a huge flat folder is checked in slices and still matches', () async {
    final server = FakeServer({
      '': [
        for (var i = 0; i < 5000; i++)
          dir('Some.Other.Release.$i.2023.1080p.WEB-DL'),
        dir('Dune.2021.2160p.WEB-DL'),
      ],
      'Dune.2021.2160p.WEB-DL/': [file('Dune.2021.2160p.WEB-DL/dune.mkv')],
    });
    final out = await run(server, dune);
    expect(server.calls, ['', 'Dune.2021.2160p.WEB-DL/']);
    expect(out.rows.single.name, 'dune.mkv');
  });

  group('layouts that are not named like a library', () {
    final inception = AdvancedSearchSelection(
      imdbId: 'tt1375666',
      isSeries: false,
      title: 'Inception',
      year: '2010',
    );

    test('opens drive, user and language folders, never system ones', () async {
      final server = FakeServer({
        '': [dir('HDD1'), dir('@eaDir'), dir('#recycle'), dir('Photos')],
        'HDD1/': [dir('HDD1/Media')],
        'HDD1/Media/': [dir('HDD1/Media/English'), dir('HDD1/Media/Hindi')],
        'HDD1/Media/English/': [dir('HDD1/Media/English/Dune (2021)')],
        'HDD1/Media/English/Dune (2021)/': [
          file('HDD1/Media/English/Dune (2021)/Dune.mkv'),
        ],
      });
      final out = await run(server, dune);
      expect(out.rows.single.name, 'Dune.mkv');
      expect(
        server.calls,
        isNot(anyElement(anyOf('@eaDir/', '#recycle/', 'Photos/'))),
      );
      expect(out.result.single.phase, WebDavSearchPhase.done);
    });

    test('collections inside a library are opened after its titles', () async {
      final server = FakeServer({
        '': [dir('Movies')],
        'Movies/': [
          dir('Movies/Christopher Nolan'),
          dir('Movies/Heat (1995)'),
          dir('Movies/Marvel'),
        ],
        'Movies/Christopher Nolan/': [
          dir('Movies/Christopher Nolan/Inception (2010)'),
        ],
        'Movies/Christopher Nolan/Inception (2010)/': [
          file('Movies/Christopher Nolan/Inception (2010)/Inception.mkv'),
        ],
      });
      final out = await run(server, inception);
      expect(out.rows.single.name, 'Inception.mkv');
      expect(server.calls, isNot(contains('Movies/Heat (1995)/')));
    });

    test('a folder holding the title has no categories to open', () async {
      final server = FakeServer({
        '': [dir('Movies')],
        'Movies/': [dir('Movies/Dune (2021)'), dir('Movies/Marvel')],
        'Movies/Dune (2021)/': [file('Movies/Dune (2021)/Dune.mkv')],
      });
      final out = await run(server, dune);
      expect(server.calls, ['', 'Movies/', 'Movies/Dune (2021)/']);
      expect(out.rows, hasLength(1));
    });

    test('a folder of many plain names lists titles and is not opened', () {
      final server = FakeServer({
        '': [for (var i = 0; i < 13; i++) dir('Show Name $i')],
      });
      return run(server, dune).then((out) {
        expect(server.calls, ['']);
        final status = out.result.single;
        expect(status.phase, WebDavSearchPhase.done);
        expect(status.found, 0);
      });
    });

    test('guesses wait for library folders', () async {
      final server = FakeServer({
        '': [dir('Archive'), dir('Movies')],
        'Movies/': [dir('Movies/Heat (1995)')],
      });
      await run(server, dune, limits: const WebDavSearchLimits(concurrency: 1));
      expect(server.calls, ['', 'Movies/', 'Archive/']);
    });

    test('a guess never shares a wave with a library folder', () async {
      final server = FakeServer({
        '': [dir('Movies'), dir('HDD2'), dir('HDD3')],
        'Movies/': [dir('Movies/Dune (2021)')],
        'Movies/Dune (2021)/': [file('Movies/Dune (2021)/Dune.2021.mkv')],
      });
      server.gates['HDD2/'] = Completer<void>(); // A drive that never wakes.
      server.gates['HDD3/'] = Completer<void>();
      final out = await run(
        server,
        dune,
        limits: const WebDavSearchLimits(
          timeLimit: Duration(milliseconds: 300),
        ),
      );
      expect(out.rows.single.name, 'Dune.2021.mkv');
      expect(server.calls, ['', 'Movies/', 'Movies/Dune (2021)/']);
    });

    test('five library levels are searched', () async {
      final server = FakeServer({
        '': [dir('Media')],
        'Media/': [dir('Media/Movies')],
        'Media/Movies/': [dir('Media/Movies/English Movies')],
        'Media/Movies/English Movies/': [dir('Media/Movies/English Movies/HD')],
        'Media/Movies/English Movies/HD/': [
          dir('Media/Movies/English Movies/HD/Movies 2021'),
        ],
        'Media/Movies/English Movies/HD/Movies 2021/': [
          file('Media/Movies/English Movies/HD/Movies 2021/Dune.2021.mkv'),
        ],
      });
      final out = await run(server, dune);
      expect(out.rows.single.name, 'Dune.2021.mkv');
    });

    test('a video content type counts without a video extension', () async {
      final server = FakeServer({
        '': [
          const WebDavItem(
            name: 'Dune 2021',
            path: 'Dune 2021',
            isDirectory: false,
            sizeBytes: 2000000000,
            contentType: 'video/x-matroska',
          ),
        ],
      });
      final out = await run(server, dune);
      expect(out.rows.single.name, 'Dune 2021');
    });

    test('guesses are dropped once the title is found', () async {
      final server = FakeServer({
        '': [dir('Movies'), dir('alice'), dir('bob')],
        'Movies/': [dir('Movies/Dune (2021)')],
        'Movies/Dune (2021)/': [file('Movies/Dune (2021)/Dune.mkv')],
      });
      final out = await run(
        server,
        dune,
        limits: const WebDavSearchLimits(concurrency: 1),
      );
      expect(server.calls, ['', 'Movies/', 'Movies/Dune (2021)/']);
      expect(out.rows, hasLength(1));
    });

    test('a long listing of releases opens none of its plain names', () async {
      final server = FakeServer({
        '': [
          for (var i = 0; i < 60; i++) dir('Other.Release.$i.2023.1080p'),
          dir('Band of Brothers'),
          dir('Cowboy Bebop'),
        ],
      });
      final out = await run(server, dune);
      expect(server.calls, ['']);
      expect(out.result.single.phase, WebDavSearchPhase.done);
    });

    test('a guess that holds another title opens nothing below it', () async {
      final server = FakeServer({
        '': [dir('Band of Brothers'), dir('Movies')],
        'Band of Brothers/': [
          dir('Band of Brothers/Disc 1'),
          dir('Band of Brothers/Bonus'),
          file('Band of Brothers/Part One.mkv'),
        ],
      });
      await run(server, dune);
      expect(
        server.calls,
        unorderedEquals(['', 'Movies/', 'Band of Brothers/']),
      );
    });

    test('guesses go at most two folders deep in a row', () async {
      final server = FakeServer({
        '': [dir('HDD1')],
        'HDD1/': [dir('HDD1/English')],
        'HDD1/English/': [dir('HDD1/English/Action')],
      });
      await run(server, dune);
      expect(server.calls, ['', 'HDD1/', 'HDD1/English/']);
    });
  });
}

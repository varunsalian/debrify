import 'dart:async';

import 'package:debrify/features/sources/data/source_download.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Torrent source({String? url = 'https://fixture.test/start'}) => Torrent(
  rowid: 1,
  infohash: 'url:fixture',
  name: 'Fixture',
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: StreamType.directUrl,
  directUrl: url,
);

class Client extends MockClient {
  Client(super.handler);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final origin = ProfileScope(
    profileId: 'origin',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final incoming = ProfileScope(
    profileId: 'incoming',
    dataGeneration: 1,
    sessionEpoch: 2,
  );
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(origin);
  });
  tearDown(ProfileRuntime.debugReset);

  test(
    'redirect policy preserves methods, relative URLs, names and client cleanup',
    () async {
      final requests = <http.Request>[];
      final clients = <Client>[];
      final statuses = [301, 302, 303, 307, 308, 200];
      String? queued;
      final operation = SourceDownload(
        clientFactory: () {
          final client = Client((request) async {
            requests.add(request);
            return http.Response(
              '',
              statuses[requests.length - 1],
              headers: {'location': '/step${requests.length}'},
            );
          });
          clients.add(client);
          return client;
        },
        enqueue: (url, item, current) async {
          expect(current(), isTrue);
          expect(item.displayTitle, source().displayTitle);
          expect(ProfileRuntime.capture(), origin);
          queued = url;
        },
      );
      final progress = <SourceDownloadStatus>[];
      final result = await ProfileRuntime.withCapturedScope(
        incoming,
        () => operation.download(
          source(),
          canContinue: () => true,
          onProgress: progress.add,
        ),
      );
      expect(result, SourceDownloadStatus.queued);
      expect(progress, [SourceDownloadStatus.resolving]);
      expect(queued, 'https://fixture.test/step5');
      expect(requests, hasLength(6));
      expect(
        requests.every((r) => r.method == 'HEAD' && !r.followRedirects),
        isTrue,
      );
      expect(
        requests.every((r) => r.headers['user-agent']!.contains('Mozilla')),
        isTrue,
      );
      expect(clients.every((c) => c.closed), isTrue);
    },
  );

  test(
    'redirect cycle stops after ten requests and queues the last URL',
    () async {
      var requests = 0;
      String? queued;
      final operation = SourceDownload(
        clientFactory: () => Client(
          (_) async =>
              http.Response('', 302, headers: {'location': '/${++requests}'}),
        ),
        enqueue: (url, _, _) async {
          queued = url;
        },
      );
      expect(
        await operation.download(source(), canContinue: () => true),
        SourceDownloadStatus.queued,
      );
      expect(requests, 10);
      expect(queued, 'https://fixture.test/10');
    },
  );

  test('failed HEAD retains best-effort URL and releases its client', () async {
    final client = Client((_) async => throw http.ClientException('offline'));
    String? queued;
    final operation = SourceDownload(
      clientFactory: () => client,
      enqueue: (url, _, _) async {
        queued = url;
      },
    );
    expect(
      await operation.download(source(), canContinue: () => true),
      SourceDownloadStatus.queued,
    );
    expect(queued, source().directUrl);
    expect(client.closed, isTrue);
  });

  test('profile switch during HEAD stops redirects and enqueue', () async {
    final entered = Completer<void>();
    final release = Completer<http.Response>();
    var requests = 0;
    var enqueues = 0;
    final client = Client((_) async {
      requests++;
      entered.complete();
      return release.future;
    });
    final operation = SourceDownload(
      clientFactory: () => client,
      enqueue: (_, _, _) async {
        enqueues++;
      },
    );
    final pending = operation.download(source(), canContinue: () => true);
    await entered.future;
    ProfileRuntime.publish(incoming);
    release.complete(http.Response('', 302, headers: {'location': '/next'}));
    expect(await pending, SourceDownloadStatus.retired);
    expect(requests, 1);
    expect(enqueues, 0);
    expect(client.closed, isTrue);
  });

  test(
    'leaving the screen while resolving still follows redirects and queues',
    () async {
      // Main queued once past "Resolving download URL…"; only the snackbars
      // depended on the screen still being mounted.
      final entered = Completer<void>();
      final release = Completer<http.Response>();
      var screen = true;
      var requests = 0;
      String? queued;
      bool? guardAtEnqueue;
      final operation = SourceDownload(
        clientFactory: () => Client((request) async {
          requests++;
          if (requests == 1) {
            entered.complete();
            return release.future;
          }
          return http.Response('', 200);
        }),
        enqueue: (url, _, current) async {
          guardAtEnqueue = current();
          queued = url;
        },
      );
      final pending = operation.download(source(), canContinue: () => screen);
      await entered.future;
      screen = false;
      release.complete(http.Response('', 302, headers: {'location': '/next'}));
      expect(await pending, SourceDownloadStatus.queued);
      expect(requests, 2);
      expect(queued, 'https://fixture.test/next');
      expect(guardAtEnqueue, isTrue);
    },
  );

  test(
    'leaving before resolving still stops at the first authorization',
    () async {
      var checks = 0;
      var requests = 0;
      var enqueues = 0;
      final progress = <SourceDownloadStatus>[];
      final operation = SourceDownload(
        clientFactory: () => Client((_) async {
          requests++;
          return http.Response('', 200);
        }),
        enqueue: (_, _, _) async {
          enqueues++;
        },
      );
      // Current at the start, gone by the check after the first authorization.
      final result = await operation.download(
        source(),
        canContinue: () => ++checks == 1,
        onProgress: progress.add,
      );
      expect(result, SourceDownloadStatus.retired);
      expect(progress, isEmpty);
      expect(requests, 0);
      expect(enqueues, 0);
    },
  );

  test(
    'queue receives the profile guard through asynchronous preparation',
    () async {
      final operation = SourceDownload(
        clientFactory: () => Client((_) async => http.Response('', 200)),
        enqueue: (_, _, active) async {
          expect(active(), isTrue);
          ProfileRuntime.publish(incoming);
          await expectLater(
            DownloadService.instance.enqueueDownload(
              url: 'https://fixture.test/file',
              canContinue: active,
            ),
            throwsStateError,
          );
        },
      );
      expect(
        await operation.download(source(), canContinue: () => true),
        SourceDownloadStatus.retired,
      );
    },
  );

  test('missing URL and rejected queue preserve separate outcomes', () async {
    var requests = 0;
    final operation = SourceDownload(
      clientFactory: () => Client((_) async {
        requests++;
        return http.Response('', 200);
      }),
      enqueue: (_, _, _) async => throw StateError('queue unavailable'),
    );
    expect(
      await operation.download(source(url: null), canContinue: () => true),
      SourceDownloadStatus.noUrl,
    );
    expect(requests, 0);
    expect(
      await operation.download(source(), canContinue: () => true),
      SourceDownloadStatus.failed,
    );
  });
}

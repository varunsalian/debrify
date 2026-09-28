import 'dart:convert';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/features/sources/data/provider_source_actions.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'source-actions');
    SharedPreferences.setMockInitialValues({
      'real_debrid_api_key': 'rd',
      'torbox_api_key': 'tb',
      'premiumize_api_key': 'pm',
      'alldebrid_api_key': 'ad',
    });
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  });

  test(
    'pack skips unavailable and rejected files, retaining order and payload',
    () async {
      final queued = <ProviderDownloadRequest>[];
      final actions = ProviderSourceActions(
        owner: ProfileSessionMemory.captureOwner(),
        canContinue: () => true,
        enqueue: (r, active) async {
          expect(active(), isTrue);
          if (r.fileName == 'reject') throw StateError('queue');
          queued.add(r);
        },
      );
      final count = await actions.queueEntries(
        const [
          PlaylistEntry(url: 'https://one', title: 'first'),
          PlaylistEntry(url: '', title: 'missing'),
          PlaylistEntry(url: 'https://reject', title: 'reject'),
          PlaylistEntry(url: 'https://two', title: 'second'),
        ],
        provider: 'realdebrid',
        torrentName: 'Pack',
      );
      expect(count, 2);
      expect(queued.map((e) => e.fileName), ['first', 'second']);
      expect(
        queued.every(
          (e) =>
              e.credentialKey == 'real_debrid_api_key' &&
              e.torrentName == 'Pack',
        ),
        isTrue,
      );
    },
  );
  test(
    'retirement keeps accepted download and prevents remaining entries',
    () async {
      final queued = <String>[];
      final actions = ProviderSourceActions(
        owner: ProfileSessionMemory.captureOwner(),
        canContinue: () => true,
        enqueue: (r, active) async {
          queued.add(r.fileName);
          ProfileSessionMemory.clearAll();
          expect(active(), isFalse);
        },
      );
      expect(
        await actions.queueEntries(
          const [
            PlaylistEntry(url: 'https://one', title: 'first'),
            PlaylistEntry(url: 'https://two', title: 'second'),
          ],
          provider: 'torbox',
          torrentName: 'Pack',
        ),
        1,
      );
      expect(queued, ['first']);
    },
  );
  for (final retire in [false, true]) {
    test(
      'lazy RD resolution ${retire ? 'rejects retired response' : 'queues unlocked URL'}',
      () async {
        final queued = <ProviderDownloadRequest>[];
        var requests = 0;
        final actions = ProviderSourceActions(
          owner: ProfileSessionMemory.captureOwner(),
          canContinue: () => true,
          enqueue: (r, _) async {
            queued.add(r);
          },
        );
        final client = MockClient((r) async {
          requests++;
          expect(r.url.path, endsWith('/unrestrict/link'));
          if (retire) ProfileSessionMemory.clearAll();
          return http.Response(jsonEncode({'download': 'https://ready'}), 200);
        });
        addTearDown(client.close);
        final count = await http.runWithClient(
          () => actions.queueEntries(
            const [
              PlaylistEntry(
                url: '',
                title: 'one',
                restrictedLink: 'https://locked',
              ),
              PlaylistEntry(url: 'https://two', title: 'two'),
            ],
            provider: 'debrid',
            torrentName: 'Pack',
          ),
          () => client,
        );
        expect(requests, 1);
        expect(count, retire ? 0 : 2);
        if (!retire) expect(queued.first.url, 'https://ready');
      },
    );
  }
  test(
    'TorBox ZIP preserves permalink, credentials and retry metadata',
    () async {
      final queued = <ProviderDownloadRequest>[];
      final actions = ProviderSourceActions(
        owner: ProfileSessionMemory.captureOwner(),
        canContinue: () => true,
        enqueue: (r, _) async {
          queued.add(r);
        },
      );
      expect(await actions.queueTorboxZip(42, 'Pack'), isTrue);
      final r = queued.single;
      expect(Uri.parse(r.url).queryParameters, {
        'token': 'tb',
        'torrent_id': '42',
        'zip_link': 'true',
        'redirect': 'true',
      });
      expect(r.fileName, 'Pack.zip');
      expect(r.credentialKey, 'torbox_api_key');
      expect(jsonDecode(r.meta!), {
        'torboxDownload': true,
        'torboxZip': true,
        'torboxTorrentId': 42,
      });
    },
  );
  for (final retireAt in [0, 1, 2, 3]) {
    test(
      'Premiumize ZIP request sequence with retirement at $retireAt',
      () async {
        final paths = <String>[];
        var started = 0;
        final actions = ProviderSourceActions(
          owner: ProfileSessionMemory.captureOwner(),
          canContinue: () => true,
        );
        final client = MockClient((r) async {
          paths.add(r.url.path);
          if (paths.length == retireAt) ProfileSessionMemory.clearAll();
          final body = r.url.path.endsWith('/create')
              ? {'status': 'success', 'id': 'transfer'}
              : r.url.path.endsWith('/list')
              ? {
                  'status': 'success',
                  'transfers': [
                    {'id': 'transfer', 'folder_id': 'folder'},
                  ],
                }
              : {'status': 'success', 'location': 'https://zip'};
          return http.Response(jsonEncode(body), 200);
        });
        addTearDown(client.close);
        final future = http.runWithClient(
          () => actions.premiumizeZipUrl(
            'magnet:test',
            onStarted: () {
              started++;
            },
          ),
          () => client,
        );
        if (retireAt == 0) {
          expect(await future, 'https://zip');
        } else {
          await expectLater(future, throwsStateError);
        }
        expect(started, 1);
        expect(paths.length, retireAt == 0 ? 3 : retireAt);
        expect(paths.any((p) => p.contains('delete')), isFalse);
      },
    );
  }
  test('retired action rejects before any queue or provider request', () async {
    var queued = false;
    final actions = ProviderSourceActions(
      owner: ProfileSessionMemory.captureOwner(),
      canContinue: () => false,
      enqueue: (_, _) async {
        queued = true;
      },
    );
    await expectLater(
      actions.queueUrl(
        'url',
        provider: 'torbox',
        fileName: 'file',
        torrentName: 'name',
      ),
      throwsStateError,
    );
    expect(queued, isFalse);
  });
  for (final keep in [false, true]) {
    test(
      'uncached RD ${keep ? 'keep does not re-add' : 'decline deletes original id'}',
      () async {
        final requests = <http.Request>[];
        final actions = ProviderSourceActions(
          owner: ProfileSessionMemory.captureOwner(),
          canContinue: () => true,
        );
        final client = MockClient((r) async {
          requests.add(r);
          return http.Response('', 204);
        });
        addTearDown(client.close);
        await http.runWithClient(
          () => actions.decideNotCached(
            TorrentNotCachedException('original-id', 'original-key'),
            'debrid',
            'magnet:test',
            keep: keep,
          ),
          () => client,
        );
        expect(requests.length, keep ? 0 : 1);
        if (!keep) {
          expect(
            requests.single.url.path,
            endsWith('/torrents/delete/original-id'),
          );
          expect(
            requests.single.headers['Authorization'],
            'Bearer original-key',
          );
        }
      },
    );
  }
  test(
    'missing Premiumize credential does not start overlay or requests',
    () async {
      SharedPreferences.setMockInitialValues({});
      final actions = ProviderSourceActions(
        owner: ProfileSessionMemory.captureOwner(),
        canContinue: () => true,
      );
      var started = false;
      final client = MockClient((_) async {
        fail('unexpected HTTP request');
      });
      addTearDown(client.close);
      await http.runWithClient(() async {
        expect(
          await actions.premiumizeZipUrl(
            'magnet:test',
            onStarted: () {
              started = true;
            },
          ),
          isNull,
        );
        expect(await actions.transferPremiumize('magnet:test'), isFalse);
      }, () => client);
      expect(started, isFalse);
    },
  );
}

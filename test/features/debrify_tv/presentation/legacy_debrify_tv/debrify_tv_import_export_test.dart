import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:debrify/services/community/magnet_yaml_service.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/debrify_tv_fixture.dart';

String importedYaml([String name = 'Imported original']) =>
    '''
channel_name: "$name"
avoid_nsfw: true
keywords:
  imported:
    torrents:
      - infohash: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
        name: "Imported.720p.mkv"
        size_bytes: 100000000
        seeders: 20
        leechers: 1
        created_unix: 0
        completed: 1
        scraped_date: 0
''';

Future<void> chooseImport(
  WidgetTester t,
  DebrifyTvFixture f,
  String label,
) async {
  f.spotlight.view.onImport();
  await f.settle(t);
  expect(find.text('Where is it coming from?'), findsOneWidget);
  await f.tap(t, find.text(label));
  await f.settle(t);
}

void main() {
  for (final extension in ['zip', 'yaml', 'txt', 'debrify', 'extensionless']) {
    testWidgets('C6 R/O device $extension persists ORIGINAL rows and summary', (
      t,
    ) async {
      await debrifyTvCase(t, (f) async {
        f.style = 'spotlight';
        await f.mount(t);
        final yaml = importedYaml();
        Uint8List bytes;
        if (extension == 'zip' || extension == 'extensionless') {
          final content = utf8.encode(yaml);
          bytes = Uint8List.fromList(
            ZipEncoder().encode(
              Archive()..addFile(
                ArchiveFile('original.yaml', content.length, content),
              ),
            ),
          );
        } else if (extension == 'debrify') {
          bytes = Uint8List.fromList(
            utf8.encode(
              MagnetYamlService.encode(
                yamlContent: yaml,
                channelName: 'Imported original',
              ),
            ),
          );
        } else {
          bytes = Uint8List.fromList(
            utf8.encode(
              extension == 'txt' ? 'imported, original\nimported' : yaml,
            ),
          );
        }
        final name = extension == 'extensionless'
            ? 'Imported original'
            : 'Imported original.$extension';
        f.picker.next = FilePickerResult([
          PlatformFile(name: name, size: bytes.length, bytes: bytes),
        ]);
        await chooseImport(t, f, 'From storage');
        await f.until(t, () => f.spotlight.view.channels.length == 3);
        final rows = await t.runAsync(
          DebrifyTvRepository.instance.fetchAllChannels,
        );
        final row = rows!.singleWhere((c) => c.name == 'Imported original');
        expect(
          row.keywords,
          extension == 'txt' ? ['imported', 'original'] : ['imported'],
        );
        expect(row.avoidNsfw, isTrue);
        if (extension != 'txt') {
          expect(find.text('Imported 1 channel.'), findsOneWidget);
          expect(
            (await t.runAsync(
              () => DebrifyTvCacheService.getEntry(row.channelId),
            ))!.torrents.single.infohash,
            'b' * 40,
          );
          await f.tap(t, find.text('Close'));
        } else {
          expect(find.textContaining('saved'), findsWidgets);
        }
      });
    });
  }

  for (final invalid in ['121', '501', 'empty']) {
    testWidgets(
      'C6 R/O text $invalid limit and empty rejection leave rows unchanged',
      (t) async {
        await debrifyTvCase(t, (f) async {
          f.style = 'spotlight';
          await f.mount(t);
          final content = invalid == '121'
              ? 'x' * 121
              : invalid == '501'
              ? List.generate(501, (i) => 'keyword$i').join(',')
              : '';
          final bytes = Uint8List.fromList(utf8.encode(content));
          f.picker.next = FilePickerResult([
            PlatformFile(
              name: 'Rejected.txt',
              size: bytes.length,
              bytes: bytes,
              readStream: bytes.isEmpty ? Stream.value(<int>[]) : null,
            ),
          ]);
          await chooseImport(t, f, 'From storage');
          await f.settle(t);
          expect(
            find.textContaining(
              invalid == '121'
                  ? 'Keyword exceeds 120 characters'
                  : invalid == '501'
                  ? '500 keywords or fewer'
                  : 'Selected file appears to be empty.',
            ),
            findsOneWidget,
          );
          expect(
            (await t.runAsync(
              DebrifyTvRepository.instance.fetchAllChannels,
            ))!.length,
            2,
          );
        });
      },
    );
  }

  testWidgets('C6 O text accepts exactly 120 characters and 500 keywords', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.style = 'spotlight';
      await f.mount(t);
      final keywords = ['x' * 120, for (var i = 1; i < 500; i++) 'keyword$i'];
      final bytes = Uint8List.fromList(utf8.encode(keywords.join(',')));
      f.picker.next = FilePickerResult([
        PlatformFile(name: 'Limits.txt', size: bytes.length, bytes: bytes),
      ]);
      await chooseImport(t, f, 'From storage');
      await f.settle(t);
      expect(
        find.textContaining('Keyword exceeds 120 characters'),
        findsNothing,
        reason: 'text accepts a 120-character keyword',
      );
      await f.until(
        t,
        () => f.spotlight.view.channels.length == 3,
        frames: 600,
      );
      expect(
        (await t.runAsync(
          DebrifyTvRepository.instance.fetchAllChannels,
        ))!.singleWhere((c) => c.name == 'Limits').keywords,
        keywords,
      );
    });
  });

  for (final status in [200, 404]) {
    testWidgets('C6 R/O URL $status progress request and persisted result', (
      t,
    ) async {
      await debrifyTvCase(t, (f) async {
        f.style = 'spotlight';
        f.onRequest = (r) async => r.url.host == 'channel-original.test'
            ? http.Response(
                importedYaml('URL original'),
                status,
                headers: {'content-type': 'application/yaml'},
              )
            : f.providerResponse(r);
        await f.mount(t);
        await chooseImport(t, f, 'From a link');
        expect(find.text('Paste a channel link'), findsOneWidget);
        await t.enterText(
          find.byType(EditableText).last,
          'https://channel-original.test/channel.yaml',
        );
        await f.tap(t, find.text('Import'));
        if (status == 200) {
          await f.until(
            t,
            () => find.text('Imported 1 channel.').evaluate().isNotEmpty,
          );
          expect(
            f.spotlight.view.channels.map((c) => c.name),
            contains('URL original'),
          );
        } else {
          await f.until(
            t,
            () => find.textContaining('404').evaluate().isNotEmpty,
          );
          expect(f.spotlight.view.channels, hasLength(2));
        }
        expect(f.requests.map(f.requestIdentity), ['GET /channel.yaml']);
      });
    });
  }

  testWidgets('C6 R/O community imports two selections with one failure', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.style = 'spotlight';
      final link = MagnetYamlService.encode(
        yamlContent: importedYaml('Community original'),
        channelName: 'Community original',
      );
      f.onRequest = (r) async {
        if (r.url.path.endsWith('manifest.json')) {
          return f.jsonResponse({
            'version': '1.0',
            'last_updated': '2026-01-02',
            'channels': [
              {
                'id': 'good',
                'name': 'Good original',
                'description': 'Fixture',
                'category': 'Fixture',
                'url': 'https://community-original.test/good.debrify',
                'updated': '2026-01-02',
              },
              {
                'id': 'bad',
                'name': 'Bad original',
                'description': 'Fixture',
                'category': 'Fixture',
                'url': 'https://community-original.test/bad.debrify',
                'updated': '2026-01-02',
              },
            ],
          });
        }
        if (r.url.path.endsWith('good.debrify')) {
          return http.Response(link, 200);
        }
        if (r.url.path.endsWith('bad.debrify')) {
          return http.Response('missing', 404);
        }
        return f.providerResponse(r);
      };
      await f.mount(t);
      await chooseImport(t, f, 'From the community');
      await f.until(t, () => find.text('Good original').evaluate().isNotEmpty);
      await f.tap(t, find.text('Select all'));
      await f.tap(t, find.text('Import 2'));
      await f.until(
        t,
        () => find.text('Imported 1 channel, 1 failed').evaluate().isNotEmpty,
      );
      expect(
        f.spotlight.view.channels.map((c) => c.name),
        contains('Community original'),
      );
      expect(
        f.requests.map(f.requestIdentity),
        containsAllInOrder([
          'GET /mediacontent/community-channels/-/raw/main/manifest.json',
          'GET /good.debrify',
          'GET /bad.debrify',
        ]),
      );
    });
  });

  testWidgets('C6 O copied share link decodes to exact ORIGINAL YAML', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.style = 'spotlight';
      await f.mount(t);
      f.spotlight.view.onShare(f.channels.first);
      await f.until(t, () => find.text('Copy link').evaluate().isNotEmpty);
      await f.tap(t, find.text('Copy link'));
      expect(f.clipboard, hasLength(1));
      final decoded = MagnetYamlService.decode(f.clipboard.single);
      final buffer = StringBuffer(
        'channel_name: "Original channel 1"\navoid_nsfw: false\n\nkeywords:\n',
      );
      for (final keyword in ['one', 'two', 'three']) {
        buffer.write(
          '  $keyword:\n    torrents:\n      - infohash: ${'a' * 40}\n        name: "Original.720p.mkv"\n        size_bytes: 100000000\n        created_unix: ${f.january.millisecondsSinceEpoch ~/ 1000}\n        seeders: 20\n        leechers: 1\n        completed: 1\n        scraped_date: 0\n        sources: ["debrify-tv-original"]\n',
        );
      }
      expect(decoded.channelName, 'Original channel 1');
      expect(decoded.yamlContent, buffer.toString());
    });
  });

  for (final television in [true, false]) {
    testWidgets(
      'C6 R/O export ${television ? 'TV refusal' : 'selection reaches save'}',
      (t) async {
        await debrifyTvCase(t, (f) async {
          f.style = 'spotlight';
          f.television = television;
          await f.mount(t);
          f.spotlight.view.onExport();
          if (television) {
            await f.settle(t);
            expect(
              find.textContaining('Apple TV does not expose'),
              findsOneWidget,
              reason: 'TV export refusal is rendered before waiting',
            );
            await f.until(
              t,
              () => find
                  .textContaining('Apple TV does not expose')
                  .evaluate()
                  .isNotEmpty,
            );
            expect(f.picker.saves, isEmpty);
          } else {
            await f.until(
              t,
              () => find.text('Select all channels').evaluate().isNotEmpty,
            );
            await f.tap(t, find.text('Select all channels'));
            expect(find.text('Export 0 channels'), findsOneWidget);
            await f.tap(t, find.text('Select all channels'));
            await f.tap(t, find.textContaining('Export 2'));
            await f.until(
              t,
              () => find.text('Channel archive saved').evaluate().isNotEmpty,
            );
            final saved = Directory(
              '${f.directory.path}/exports',
            ).listSync().whereType<File>().single;
            final archive = ZipDecoder().decodeBytes(saved.readAsBytesSync());
            expect(archive.files, hasLength(2));
            expect(
              utf8.decode(archive.files.first.content),
              contains('Original channel 1'),
            );
            expect(
              saved.uri.pathSegments.last,
              matches(r'^debrify-tv-channels-\d{12}\.zip$'),
            );
          }
        });
      },
    );
  }
}

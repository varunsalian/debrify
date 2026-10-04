import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/iptv_settings_fixture.dart';

void main() {
  testWidgets(
    'URL add through real form persists fields and microsecond ID with one request',
    (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester, add: true);
        await tester.enterText(
          find.widgetWithText(TvTextField, 'Playlist Name'),
          '  News  ',
        );
        await tester.enterText(
          find.widgetWithText(TvTextField, 'Playlist URL'),
          'https://fixture.invalid/new.m3u',
        );
        await tester.enterText(
          find.widgetWithText(TvTextField, 'EPG URL (XMLTV, optional)'),
          '  https://fixture.invalid/new.xml  ',
        );
        final before = DateTime.now().microsecondsSinceEpoch;
        await f.tap(tester, find.text('Add Playlist').last);
        await f.until(
          tester,
          () => f.playlists.length == 1 && f.member('isAdding') == false,
        );
        await f.frames(tester);
        expect(f.requests, [
          (method: 'GET', url: Uri.parse('https://fixture.invalid/new.m3u')),
        ]);
        late Map<String, dynamic> saved;
        await tester.runAsync(() async {
          saved = await f.resources.resolveSecretForUse(
            context: await ProfileAuthorizationContext.capture(f.registry),
            resourceId: f.playlists.single.connectionResourceId!,
            feature: ProfileFeature.iptv,
          );
          expect(
            (await IptvPlaylistStorage.getIptvPlaylists()).single.toJson(),
            f.playlists.single.toJson(),
          );
        });
        expect(saved['name'], 'News');
        expect(saved['url'], 'https://fixture.invalid/new.m3u');
        expect(saved['epgUrl'], 'https://fixture.invalid/new.xml');
        expect(
          int.parse(saved['id'] as String),
          inInclusiveRange(before, DateTime.now().microsecondsSinceEpoch),
        );
        expect(
          (f.member('nameController') as TextEditingController).text,
          isEmpty,
        );
        expect(
          (f.member('urlController') as TextEditingController).text,
          isEmpty,
        );
        expect(
          (f.member('epgUrlController') as TextEditingController).text,
          isEmpty,
        );
        expect(find.text('Added "News" (1 channels)'), findsOneWidget);
      });
    },
  );

  testWidgets(
    'URL busy flag rejects second real form submission before held fetch completes',
    (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester, add: true);
        await tester.enterText(
          find.widgetWithText(TvTextField, 'Playlist Name'),
          'News',
        );
        await tester.enterText(
          find.widgetWithText(TvTextField, 'Playlist URL'),
          'https://fixture.invalid/new.m3u',
        );
        f.holdAction = 'm3u';
        f.heldHttp = Completer<http.Response>();
        await f.tap(tester, find.text('Add Playlist').last);
        await f.until(
          tester,
          () => f.member('isAdding') == true && f.requests.length == 1,
        );
        final epg = tester.widget<TvTextField>(
          find.widgetWithText(TvTextField, 'EPG URL (XMLTV, optional)'),
        );
        epg.onSubmitted!('');
        await f.frames(tester);
        expect(f.requests.length, 1);
        expect(find.text('Adding...'), findsOneWidget);
        f.heldHttp!.complete(http.Response(iptvFixtureM3u, 200));
        await f.until(
          tester,
          () => f.playlists.length == 1 && f.member('isAdding') == false,
        );
        expect(f.requests.length, 1);
      });
    },
  );

  for (final entry in <({String name, String url, String message})>[
    (name: '', url: '', message: 'Please enter a playlist name'),
    (name: 'News', url: '', message: 'Please enter a playlist URL'),
    (
      name: 'News',
      url: 'file:///tmp/a.m3u',
      message: 'Please enter a valid HTTP/HTTPS URL',
    ),
    (
      name: 'News',
      url: 'https://fixture.invalid/z9.m3u',
      message: 'This playlist URL already exists',
    ),
  ]) {
    testWidgets('URL form validation ${entry.message}', (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester, add: true);
        await tester.enterText(
          find.widgetWithText(TvTextField, 'Playlist Name'),
          entry.name,
        );
        await tester.enterText(
          find.widgetWithText(TvTextField, 'Playlist URL'),
          entry.url,
        );
        await f.tap(tester, find.text('Add Playlist').last);
        await f.frames(tester);
        expect(find.text(entry.message), findsOneWidget);
        expect(f.requests, isEmpty);
        expect(f.playlists.length, 1);
        expect(f.member('isAdding'), isFalse);
      }, sources: [iptvFixtureSource('z9')]);
    });
  }

  for (final empty in [false, true]) {
    testWidgets(
      'URL form failed or empty fetch clears busy and persists nothing empty=$empty',
      (tester) async {
        await iptvSettingsCase(tester, (f) async {
          await f.mount(tester, add: true);
          f.m3uStatus = empty ? 200 : 403;
          f.m3u = empty ? '#EXTM3U\n' : 'denied';
          await tester.enterText(
            find.widgetWithText(TvTextField, 'Playlist Name'),
            'News',
          );
          await tester.enterText(
            find.widgetWithText(TvTextField, 'Playlist URL'),
            'https://fixture.invalid/new.m3u',
          );
          await f.tap(tester, find.text('Add Playlist').last);
          await f.until(
            tester,
            () => f.requests.isNotEmpty && f.member('isAdding') == false,
          );
          expect(f.playlists, isEmpty);
          await tester.runAsync(
            () async =>
                expect(await IptvPlaylistStorage.getIptvPlaylists(), isEmpty),
          );
          expect(
            find.textContaining(
              empty
                  ? 'Playlist is empty or invalid'
                  : 'Failed to load playlist:',
            ),
            findsOneWidget,
          );
        });
      },
    );
  }

  for (final named in [false, true]) {
    testWidgets(
      'Xtream real form normalizes endpoint and persists ${named ? 'custom' : 'fallback'} label',
      (tester) async {
        await iptvSettingsCase(tester, (f) async {
          await f.mount(tester, add: true);
          (f.member('tabController') as TabController).index = 2;
          await tester.pump(const Duration(milliseconds: 350));
          if (named) {
            await tester.enterText(
              find.widgetWithText(TvTextField, 'Playlist Name (optional)'),
              '  My Provider  ',
            );
          }
          await tester.enterText(
            find.widgetWithText(TvTextField, 'Server URL'),
            'fixture.invalid/panel/player_api.php?bad=value',
          );
          await tester.enterText(
            find.widgetWithText(TvTextField, 'Username'),
            '  user  ',
          );
          await tester.enterText(
            find.widgetWithText(TvTextField, 'Password'),
            '  pass  ',
          );
          final before = DateTime.now().millisecondsSinceEpoch;
          await f.tap(tester, find.text('Login & Add'));
          await f.until(
            tester,
            () => f.playlists.length == 1 && f.member('isXcAdding') == false,
          );
          expect(f.requests, [
            (
              method: 'GET',
              url: Uri.parse(
                'http://fixture.invalid/panel/player_api.php?username=user&password=pass',
              ),
            ),
          ]);
          late Map<String, dynamic> saved;
          await tester.runAsync(() async {
            saved = await f.resources.resolveSecretForUse(
              context: await ProfileAuthorizationContext.capture(f.registry),
              resourceId: f.playlists.single.connectionResourceId!,
              feature: ProfileFeature.iptv,
            );
          });
          expect(saved['name'], named ? 'My Provider' : 'user@fixture.invalid');
          expect(saved['url'], '');
          expect(saved['serverUrl'], 'http://fixture.invalid/panel');
          expect(saved['username'], 'user');
          expect(saved['password'], 'pass');
          expect(
            int.parse(saved['id'] as String),
            inInclusiveRange(before, DateTime.now().millisecondsSinceEpoch),
          );
          for (final name in [
            'xcNameController',
            'xcServerController',
            'xcUsernameController',
            'xcPasswordController',
          ]) {
            expect((f.member(name) as TextEditingController).text, isEmpty);
          }
        });
      },
    );
  }

  testWidgets('Xtream busy flag rejects repeated real password submission', (
    tester,
  ) async {
    await iptvSettingsCase(tester, (f) async {
      await f.mount(tester, add: true);
      (f.member('tabController') as TabController).index = 2;
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(
        find.widgetWithText(TvTextField, 'Server URL'),
        'https://fixture.invalid/panel',
      );
      await tester.enterText(
        find.widgetWithText(TvTextField, 'Username'),
        'user',
      );
      await tester.enterText(
        find.widgetWithText(TvTextField, 'Password'),
        'pass',
      );
      f.holdAction = 'login';
      f.heldHttp = Completer<http.Response>();
      await f.tap(tester, find.text('Login & Add'));
      await f.until(
        tester,
        () => f.member('isXcAdding') == true && f.requests.length == 1,
      );
      tester
          .widget<TvTextField>(find.widgetWithText(TvTextField, 'Password'))
          .onSubmitted!('pass');
      await f.frames(tester);
      expect(f.requests.length, 1);
      expect(find.text('Logging in...'), findsOneWidget);
      f.heldHttp!.complete(
        http.Response('{"user_info":{"auth":1,"status":"Active"}}', 200),
      );
      await f.until(
        tester,
        () => f.playlists.length == 1 && f.member('isXcAdding') == false,
      );
      expect(f.requests.length, 1);
    });
  });

  for (final entry
      in <({String server, String user, String password, String message})>[
        (
          server: '',
          user: '',
          password: '',
          message: 'Please enter a server URL',
        ),
        (
          server: 'https://fixture.invalid',
          user: '',
          password: '',
          message: 'Please enter a username',
        ),
        (
          server: 'https://fixture.invalid',
          user: 'u',
          password: '',
          message: 'Please enter a password',
        ),
        (
          server: 'http://',
          user: 'u',
          password: 'p',
          message: 'Please enter a valid server URL',
        ),
      ]) {
    testWidgets('Xtream validation ${entry.message}', (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester, add: true);
        (f.member('tabController') as TabController).index = 2;
        await tester.pump(const Duration(milliseconds: 350));
        await tester.enterText(
          find.widgetWithText(TvTextField, 'Server URL'),
          entry.server,
        );
        await tester.enterText(
          find.widgetWithText(TvTextField, 'Username'),
          entry.user,
        );
        await tester.enterText(
          find.widgetWithText(TvTextField, 'Password'),
          entry.password,
        );
        await f.tap(tester, find.text('Login & Add'));
        await f.frames(tester);
        expect(find.text(entry.message), findsOneWidget);
        expect(f.requests, isEmpty);
        expect(f.playlists, isEmpty);
        expect(f.member('isXcAdding'), isFalse);
      });
    });
  }

  testWidgets('Xtream failed authentication clears busy and retains form', (
    tester,
  ) async {
    await iptvSettingsCase(tester, (f) async {
      await f.mount(tester, add: true);
      (f.member('tabController') as TabController).index = 2;
      await tester.pump(const Duration(milliseconds: 350));
      f.authSuccess = false;
      await tester.enterText(
        find.widgetWithText(TvTextField, 'Server URL'),
        'https://fixture.invalid/panel',
      );
      await tester.enterText(
        find.widgetWithText(TvTextField, 'Username'),
        'user',
      );
      await tester.enterText(
        find.widgetWithText(TvTextField, 'Password'),
        'pass',
      );
      await f.tap(tester, find.text('Login & Add'));
      await f.until(
        tester,
        () => f.requests.isNotEmpty && f.member('isXcAdding') == false,
      );
      expect(f.playlists, isEmpty);
      expect(
        (f.member('xcPasswordController') as TextEditingController).text,
        'pass',
      );
      expect(find.text('Account status: Disabled'), findsOneWidget);
    });
  });

  testWidgets(
    'file picker cancel and extension rejection preserve exact picker arguments',
    (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester, add: true);
        (f.member('tabController') as TabController).index = 1;
        await tester.pump(const Duration(milliseconds: 350));
        await f.tap(tester, find.text('Browse Files'));
        await f.frames(tester);
        expect(f.picker.calls, [
          (type: FileType.any, multiple: false, data: true),
        ]);
        expect(f.playlists, isEmpty);
        f.picker.file(
          'bad.txt',
          Uint8List.fromList(utf8.encode(iptvFixtureM3u)),
        );
        await f.tap(tester, find.text('Browse Files'));
        await f.frames(tester);
        expect(f.picker.calls.length, 2);
        expect(find.text('Please select an M3U or M3U8 file'), findsOneWidget);
        expect(f.playlists, isEmpty);
      });
    },
  );

  testWidgets(
    'file Browse Files stays enabled and a second tap opens a second picker',
    (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester, add: true);
        (f.member('tabController') as TabController).index = 1;
        await tester.pump(const Duration(milliseconds: 350));
        f.picker.hold = true;
        await f.tap(tester, find.text('Browse Files'));
        await f.until(tester, () => f.picker.calls.length == 1);
        await f.tap(tester, find.text('Browse Files'));
        await f.until(tester, () => f.picker.calls.length == 2);
        expect(f.member('isAdding'), isFalse);
        expect(f.member('isXcAdding'), isFalse);
        expect(find.text('Browse Files'), findsOneWidget);
        for (final waiter in f.picker.held) {
          waiter.complete(null);
        }
        await f.frames(tester);
        expect(f.playlists, isEmpty);
      });
    },
  );

  for (final kind in ['utf8_bytes_first', 'latin1_bytes', 'real_path']) {
    testWidgets(
      'file import $kind uses real decoder, name dialog and millisecond ID',
      (tester) async {
        await iptvSettingsCase(tester, (f) async {
          await f.mount(tester, add: true);
          (f.member('tabController') as TabController).index = 1;
          await tester.pump(const Duration(milliseconds: 350));
          final bytes = Uint8List.fromList(
            kind == 'latin1_bytes'
                ? latin1.encode(iptvFixtureM3u)
                : utf8.encode(iptvFixtureM3u),
          );
          final file = File('${f.directory.path}/source.m3u');
          await tester.runAsync(() => file.writeAsBytes(bytes));
          f.picker.file(
            'Café.M3U8',
            kind == 'real_path' ? null : bytes,
            path: kind == 'utf8_bytes_first'
                ? '/missing/ignored.m3u'
                : file.path,
          );
          final before = DateTime.now().millisecondsSinceEpoch;
          await f.tap(tester, find.text('Browse Files'));
          await f.until(
            tester,
            () => find.byType(Dialog).evaluate().isNotEmpty,
          );
          expect(find.text('Café'), findsOneWidget);
          await f.tap(tester, find.text('Import').last);
          await f.until(tester, () => f.playlists.length == 1);
          late Map<String, dynamic> saved;
          await tester.runAsync(() async {
            saved = await f.resources.resolveSecretForUse(
              context: await ProfileAuthorizationContext.capture(f.registry),
              resourceId: f.playlists.single.connectionResourceId!,
              feature: ProfileFeature.iptv,
            );
          });
          expect(saved['name'], 'Café');
          expect(saved['url'], '');
          expect(saved['content'], iptvFixtureM3u);
          expect(
            int.parse(saved['id'] as String),
            inInclusiveRange(before, DateTime.now().millisecondsSinceEpoch),
          );
          expect(f.requests, isEmpty);
          expect(find.text('Imported "Café" (1 channels)'), findsOneWidget);
        });
      },
    );
  }

  testWidgets(
    'file warning uses decoded characters rather than UTF8 bytes across 5 MiB',
    (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester, add: true);
        (f.member('tabController') as TabController).index = 1;
        await tester.pump(const Duration(milliseconds: 350));
        final content =
            '$iptvFixtureM3u#${List.filled(3 * 1024 * 1024, "é").join()}\n';
        final bytes = Uint8List.fromList(utf8.encode(content));
        expect(bytes.length, greaterThan(5 * 1024 * 1024));
        expect(content.length, lessThan(5 * 1024 * 1024));
        f.picker.file('large.m3u', bytes);
        await f.tap(tester, find.text('Browse Files'));
        await f.until(tester, () => find.byType(Dialog).evaluate().isNotEmpty);
        expect(find.textContaining('File is very large'), findsNothing);
        await f.tap(tester, find.text('Cancel'));
        await f.frames(tester);
        expect(f.playlists, isEmpty);
      });
    },
  );
  for (final kind in ['unreadable', 'empty', 'decoded_over_threshold']) {
    testWidgets('file import $kind retains original validation and warning', (
      tester,
    ) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester, add: true);
        (f.member('tabController') as TabController).index = 1;
        await tester.pumpAndSettle();
        final content = kind == 'empty'
            ? '#EXTM3U\n'
            : '$iptvFixtureM3u#${List.filled(5 * 1024 * 1024, "a").join()}\n';
        f.picker.file(
          'input.m3u',
          kind == 'unreadable'
              ? null
              : Uint8List.fromList(utf8.encode(content)),
        );
        await f.tap(tester, find.text('Browse Files'));
        if (kind == 'decoded_over_threshold') {
          await f.until(
            tester,
            () => find.byType(Dialog).evaluate().isNotEmpty,
          );
          expect(
            find.textContaining(
              'File is very large (>5.0MB). This may cause issues.',
            ),
            findsOneWidget,
          );
          await f.tap(tester, find.text('Cancel'));
          await f.frames(tester);
        } else {
          await f.frames(tester);
          expect(
            find.text(
              kind == 'unreadable'
                  ? 'Could not read file content'
                  : 'Playlist is empty or invalid',
            ),
            findsOneWidget,
          );
          expect(find.byType(Dialog), findsNothing);
        }
        expect(f.playlists, isEmpty);
        expect(f.requests, isEmpty);
      });
    });
  }
}

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_connect_controller.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/widgets/webdav_sync/remote_webdav_sync_offer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final server = WebDavConfig(
    id: 'one',
    name: 'Imported account',
    baseUrl: 'https://example.test/dav',
    username: 'alice',
    password: 'secret',
  );

  Future<BuildContext> mount(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold(body: Text('Receiver'));
          },
        ),
      ),
    );
    return context;
  }

  testWidgets('only the chosen account is joined and success is shown', (
    tester,
  ) async {
    final context = await mount(tester);
    const second = WebDavConfig(
      id: 'two',
      name: 'Second account',
      baseUrl: 'https://second.test',
      username: 'bob',
      password: 'other',
    );
    final chosen = <String>[];
    var resumed = false;
    final done = offerRemoteWebDavSync(
      context,
      [server, second],
      isCurrent: () => true,
      requireAdmin: () async {},
      pause: () {},
      resume: () async {
        resumed = true;
      },
      connect: (credentials, confirm, update) async {
        chosen.add(credentials.serverName);
        return WebDavSyncConnectActive(
          WebDavSyncBinding(
            id: 'binding',
            location: WebDavSyncFolderLocation.fromConfig(second, 'Debrify'),
            lifecycle: WebDavSyncLifecycle.active,
            namespaceId: 'circle',
            sealedSecrets: 'sealed',
            updatedAt: DateTime(2026),
          ),
        );
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(second.name));
    await tester.pumpAndSettle();
    await done;
    expect(chosen, [second.name]);
    expect(resumed, isTrue);
    expect(
      find.text('WebDAV Sync connected; first sync complete'),
      findsOneWidget,
    );
  });

  testWidgets('declining the offer does not connect or pause sync', (
    tester,
  ) async {
    final context = await mount(tester);
    final done = offerRemoteWebDavSync(
      context,
      [server],
      isCurrent: () => true,
      requireAdmin: () async {},
      pause: () => fail('must not pause'),
      resume: () async => fail('must not resume'),
      connect: (_, _, _) async => throw StateError('must not connect'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    await done;
  });

  testWidgets(
    'profile switch during offer prevents using imported credentials',
    (tester) async {
      var current = true;
      final context = await mount(tester);
      final done = offerRemoteWebDavSync(
        context,
        [server],
        isCurrent: () => current,
        requireAdmin: () async {},
        pause: () => fail('must not pause'),
        connect: (_, _, _) async => throw StateError('must not connect'),
      );
      await tester.pumpAndSettle();
      current = false;
      await tester.tap(find.text(server.name));
      await tester.pumpAndSettle();
      await done;
    },
  );

  testWidgets('existing account adoption needs a second confirmation', (
    tester,
  ) async {
    final context = await mount(tester);
    final events = <String>[];
    WebDavSyncLoginCredentials? received;
    bool? confirmed;
    final done = offerRemoteWebDavSync(
      context,
      [server],
      isCurrent: () => true,
      requireAdmin: () async {},
      pause: () => events.add('pause'),
      resume: () async => events.add('resume'),
      connect: (credentials, confirm, update) async {
        received = credentials;
        events.add('connect');
        confirmed = await confirm();
        return const WebDavSyncConnectCancelled();
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(server.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Use sync data from this account?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await done;
    expect(events, ['pause', 'connect', 'resume']);
    expect(confirmed, isFalse);
    expect(received!.endpoint.toString(), server.baseUrl);
    expect(received!.username, server.username);
    expect(received!.password, server.password);
    expect(
      find.text('Sync setup cancelled; server credentials remain saved'),
      findsOneWidget,
    );
  });

  testWidgets('setup failure preserves import and resumes the runtime', (
    tester,
  ) async {
    final context = await mount(tester);
    var resumed = false;
    final done = offerRemoteWebDavSync(
      context,
      [server],
      isCurrent: () => true,
      requireAdmin: () async {},
      pause: () {},
      resume: () async {
        resumed = true;
      },
      connect: (_, _, _) async =>
          WebDavSyncConnectPreHandoffFailure(StateError('offline')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(server.name));
    await tester.pumpAndSettle();
    await done;
    expect(resumed, isTrue);
    expect(
      find.text(
        'Server credentials saved, but sync setup failed. Retry in Sync & Migrate.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

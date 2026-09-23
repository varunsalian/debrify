import 'dart:async';
import 'package:debrify/models/media_server.dart';
import 'package:debrify/models/media_server_library.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/media_server_library_panel.dart';
import 'package:debrify/services/media_server_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const server = ConnectionResource(
  id: 'server1',
  type: ConnectionResourceType.mediaServer,
  label: 'Test server',
  ownerProfileId: 'owner',
  publicConfig: {},
  authorizationRevision: 1,
  enabled: true,
);
MediaServerLibraryItem item(String id, String type) =>
    MediaServerLibraryItem.fromJson({'Id': id, 'Name': id, 'Type': type});

class Library implements MediaServerLibraryAccess {
  @override
  ConnectionResource get resource => server;
  @override
  MediaServerKind get kind => MediaServerKind.jellyfin;
  final calls = <String>[];
  Completer<MediaServerLibraryPage>? delayed;
  bool fail = false;
  @override
  Future<void> authorize() async {}
  @override
  Future<Uint8List?> image(String id) async => null;
  @override
  Future<MediaServerLibraryItem> item(String id) async =>
      throw UnimplementedError();
  @override
  Future<List<Torrent>> sources(MediaServerLibraryItem item) async => [];
  @override
  Future<MediaServerLibraryPage> browse({
    String? parentId,
    bool views = false,
    int offset = 0,
    String search = '',
    String sort = 'SortName',
    String mode = 'browse',
    bool episodeOrder = false,
  }) async {
    calls.add('$parentId:$offset:$search');
    if (views) {
      return MediaServerLibraryPage([
        itemRow('Library', 'CollectionFolder'),
      ], null);
    }
    if (fail) throw const MediaServerException('Server unavailable');
    if (search == 'slow') return delayed!.future;
    if (search.isNotEmpty) {
      return MediaServerLibraryPage([itemRow(search, 'Video')], null);
    }
    if (parentId == 'Series') {
      return MediaServerLibraryPage([itemRow('Season', 'Season')], null);
    }
    if (parentId == 'Season') {
      return MediaServerLibraryPage([itemRow('Episode', 'Episode')], null);
    }
    return MediaServerLibraryPage([
      itemRow(offset == 0 ? 'Series' : 'Page two', 'Series'),
    ], offset == 0 ? 60 : null);
  }

  MediaServerLibraryItem itemRow(String id, String type) =>
      MediaServerLibraryItem.fromJson({
        'Id': id.replaceAll(' ', '_'),
        'Name': id,
        'Type': type,
      });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);
  testWidgets('profile change clears old rows before replacement server load', (
    tester,
  ) async {
    var first = true;
    final replacement = Completer<List<ConnectionResource>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaServerLibraryPanel(
            kind: MediaServerKind.jellyfin,
            leading: const Text('Jellyfin'),
            connectionLoader: () async => first ? [server] : replacement.future,
            sessionLoader: (_) async => Library(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Series'), findsWidgets);
    first = false;
    ProfileRuntime.scope.value = ProfileScope(
      profileId: 'new',
      dataGeneration: 2,
      sessionEpoch: 2,
    );
    await tester.pump();
    expect(find.text('Series'), findsNothing);
    replacement.complete([]);
    await tester.pumpAndSettle();
    expect(
      find.text('Connect a Jellyfin server to browse its libraries.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  Future<void> pump(
    WidgetTester tester,
    Library library, {
    bool tv = false,
    Future<List<ConnectionResource>> Function()? loader,
  }) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = tv
        ? const Size(1280, 720)
        : const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: Scaffold(
            body: MediaServerLibraryPanel(
              kind: MediaServerKind.jellyfin,
              isTelevision: tv,
              leading: const Text('Jellyfin'),
              connectionLoader: loader ?? () async => [server],
              sessionLoader: (_) async => library,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final tv in [false, true]) {
    testWidgets('${tv ? 'TV' : 'phone'} folders, back and pagination', (
      tester,
    ) async {
      final library = Library();
      await pump(tester, library, tv: tv);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Series').first);
      await tester.pumpAndSettle();
      expect(library.calls.last, 'Series:0:');
      await tester.tap(find.text('Season').first);
      await tester.pumpAndSettle();
      expect(library.calls.last, 'Season:0:');
      expect(find.text('Episode'), findsWidgets);
      await tester.tap(find.byTooltip('Back to parent'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to parent'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next page'));
      await tester.pumpAndSettle();
      expect(library.calls.last, 'Library:60:');
      expect(find.text('Page two'), findsWidgets);
      await tester.tap(find.text('Previous page'));
      await tester.pumpAndSettle();
      expect(library.calls.last, 'Library:0:');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('refresh removes disconnected server and old library controls', (
    tester,
  ) async {
    var connected = true;
    await pump(
      tester,
      Library(),
      loader: () async => connected ? [server] : [],
    );
    connected = false;
    await tester.tap(find.byTooltip('Refresh servers'));
    await tester.pumpAndSettle();
    expect(
      find.text('Connect a Jellyfin server to browse its libraries.'),
      findsOneWidget,
    );
    expect(find.text('Series'), findsNothing);
    expect(find.byTooltip('Search library'), findsNothing);
  });
  testWidgets('late search response cannot replace the newer query', (
    tester,
  ) async {
    final library = Library()..delayed = Completer<MediaServerLibraryPage>();
    await pump(tester, library);
    await tester.enterText(find.byType(TextField), 'slow');
    await tester.tap(find.byTooltip('Search library'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'new');
    await tester.tap(find.byTooltip('Search library'));
    await tester.pumpAndSettle();
    library.delayed!.complete(
      MediaServerLibraryPage([item('stale', 'Video')], null),
    );
    await tester.pumpAndSettle();
    expect(find.text('new'), findsWidgets);
    expect(find.text('stale'), findsNothing);
  });
  testWidgets('failed page retries successfully', (tester) async {
    final library = Library()..fail = true;
    await pump(tester, library);
    expect(find.text('Server unavailable'), findsOneWidget);
    library.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Series'), findsWidgets);
  });
  testWidgets('TV select activates a focused folder', (tester) async {
    final library = Library();
    await pump(tester, library, tv: true);
    final card = find
        .ancestor(of: find.text('Series').first, matching: find.byType(InkWell))
        .first;
    tester.widget<InkWell>(card).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(library.calls.last, 'Series:0:');
  });
}

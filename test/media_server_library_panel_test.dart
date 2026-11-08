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

/// A server with real latency, so the spinner replaces the grid, and a
/// season long enough that its last episodes start unbuilt.
class SlowLibrary extends Library {
  final served = <String>[];
  bool failNext = false;
  bool episodeGone = false;
  Duration delay = const Duration(milliseconds: 10);
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
    if (views) return super.browse(views: true);
    await Future<void>.delayed(delay);
    served.add('$parentId');
    if (failNext) {
      failNext = false;
      throw const MediaServerException('Server unavailable');
    }
    if (parentId == 'Library') {
      return MediaServerLibraryPage([
        itemRow('Intro', 'Video'),
        itemRow('Series', 'Series'),
        for (var i = 1; i <= 60; i++)
          if (!(episodeGone && i == 54)) itemRow('Ep$i', 'Episode'),
      ], null);
    }
    return MediaServerLibraryPage([itemRow('Season', 'Season')], null);
  }
}

/// The show folder sits second, so its card owns its own focus node.
class LibraryWithIntro extends Library {
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
    if (!views && parentId == 'Library') {
      calls.add('$parentId:$offset:$search');
      return MediaServerLibraryPage([
        itemRow('Intro', 'Video'),
        itemRow('Series', 'Series'),
      ], null);
    }
    return super.browse(
      parentId: parentId,
      views: views,
      offset: offset,
      search: search,
      sort: sort,
      mode: mode,
      episodeOrder: episodeOrder,
    );
  }
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
  testWidgets('TV keeps focus in the grid as folders open and close', (
    tester,
  ) async {
    // A user on Android TV could open a show's folder but never reach its
    // episodes: the spinner disposed the focused card and nothing took over.
    final library = LibraryWithIntro();
    await pump(tester, library, tv: true);
    // The remote reached the show's card without passing the first card.
    Focus.of(tester.element(find.text('Series').first)).requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(library.calls.last, 'Series:0:');
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'media-library-grid',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(library.calls.last, 'Season:0:');
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'media-library-grid',
    );

    await tester.tap(find.byTooltip('Back to parent'));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'media-library-grid',
    );
  });
  testWidgets('TV returns focus to the opened episode after its screen', (
    tester,
  ) async {
    final library = LibraryWithIntro();
    await pump(tester, library, tv: true);
    Focus.of(tester.element(find.text('Series').first)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(library.calls.last, 'Season:0:');

    // Open the episode, then come back from its screen.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'media-library-restore',
    );
  });
  group('TV focus with a slow server', () {
    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

    Future<void> dragTo(WidgetTester tester, String label, double dy) async {
      for (var i = 0; i < 60 && find.text(label).evaluate().isEmpty; i++) {
        await tester.drag(find.byType(GridView), Offset(0, dy));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> openDeepEpisode(WidgetTester tester) async {
      await dragTo(tester, 'Ep54', -300);
      Focus.of(tester.element(find.text('Ep54').first)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    testWidgets('back from a deep episode lands on it, in place', (
      tester,
    ) async {
      await pump(tester, SlowLibrary(), tv: true);
      await openDeepEpisode(tester);

      expect(focused(), 'media-library-restore');
      expect(find.text('Ep54'), findsWidgets);
    });

    testWidgets('the grid keeps focus after a return, as folders change', (
      tester,
    ) async {
      // A FocusNode keeps its context once its card is gone, so a check on
      // the context alone left nothing focused from here on.
      final library = SlowLibrary();
      await pump(tester, library, tv: true);
      await openDeepEpisode(tester);

      await dragTo(tester, 'Series', 300);
      Focus.of(tester.element(find.text('Series').first)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(library.served.last, 'Series');
      expect(focused(), 'media-library-grid');
    });

    testWidgets('a watched episode gone from the list falls back to the top', (
      tester,
    ) async {
      final library = SlowLibrary();
      await pump(tester, library, tv: true);
      library.episodeGone = true;
      await openDeepEpisode(tester);

      expect(find.text('Ep54'), findsNothing);
      expect(focused(), 'media-library-grid');
    });

    testWidgets('a later scroll never steals focus for a missing card', (
      tester,
    ) async {
      final library = SlowLibrary();
      await pump(tester, library, tv: true);
      await openDeepEpisode(tester);
      library.episodeGone = true;
      Focus.of(tester.element(find.text('Ep54').first)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(focused(), 'media-library-grid');

      await dragTo(tester, 'Ep60', -300);
      // Building more cards must not pull focus to a stale request.
      expect(focused(), isNot('media-library-restore'));
    });

    testWidgets('a load finishing under another screen leaves its focus', (
      tester,
    ) async {
      final library = SlowLibrary();
      await pump(tester, library, tv: true);
      Focus.of(tester.element(find.text('Series').first)).requestFocus();
      await tester.pump();
      library.delay = const Duration(seconds: 5);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(); // The folder's load is in flight.

      final top = FocusNode(debugLabel: 'top-route');
      addTearDown(top.dispose);
      Navigator.of(tester.element(find.byType(MediaServerLibraryPanel))).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: Focus(
              focusNode: top,
              autofocus: true,
              child: const Text('x'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1)); // Past the transition.
      expect(focused(), 'top-route');

      await tester.pump(const Duration(seconds: 5)); // The load finishes.
      await tester.pump();
      await tester.pump();

      expect(library.served.last, 'Series');
      expect(focused(), 'top-route');
    });

    testWidgets('a failed reload keeps the place for its Retry', (
      tester,
    ) async {
      final library = SlowLibrary();
      await pump(tester, library, tv: true);
      await dragTo(tester, 'Ep54', -300);
      Focus.of(tester.element(find.text('Ep54').first)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      library.failNext = true;
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(focused(), 'media-library-restore');
    });

    testWidgets('Retry hands focus to the grid when it succeeds', (
      tester,
    ) async {
      final library = SlowLibrary();
      await pump(tester, library, tv: true);
      Focus.of(tester.element(find.text('Series').first)).requestFocus();
      await tester.pump();
      library.failNext = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(focused(), 'media-library-grid');
    });
  });
}

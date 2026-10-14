import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/tracks_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'subtitle_sources_driver.dart';

const identifyScreen = VideoPlayerScreen(
  videoUrl: 'https://player.test/identify.mp4',
  title: 'Launch.Title.2024.mkv',
);

/// Runs the real catalog and subtitle services through one registered addon.
/// Holds network delivery and public await continuations, never private State.
class IdentifyTitleDriver extends SubtitleSourcesDriver {
  IdentifyTitleDriver(super.t, {super.committed, super.configurePlayer});
  FutureOr<http.Response> Function(http.Request)? catalog;
  FutureOr<http.Response> Function(http.Request)? discovery;
  List<Map<String, Object?>> metas = [identityMeta('Chosen title')];
  final catalogQueries = <String>[];
  final subtitlePaths = <String>[];
  MaterialPageRoute<void>? playerRoute;
  bool disposedRoute = false;
  http.Response response(List<Map<String, Object?>> values) =>
      http.Response(jsonEncode({'metas': values}), 200);
  static Map<String, Object?> identityMeta(
    String name, {
    String id = 'tt1200002',
    String type = 'movie',
  }) => {'id': id, 'imdb_id': id, 'name': name, 'type': type};
  Future<void> setupIdentity() async {
    await setup();
    const manifest = 'https://identify.subtitle.test/manifest.json';
    f.network.replies[manifest] = http.Response(
      jsonEncode({
        'id': 'p12-identify',
        'name': 'Identity fixture',
        'version': '1.0.0',
        'types': ['movie', 'series'],
        'resources': ['catalog', 'subtitles'],
        'catalogs': [
          {
            'id': 'search',
            'type': 'movie',
            'extraSupported': ['search'],
          },
        ],
      }),
      200,
    );
    addons.add(await f.finish(t, StremioService.instance.addAddon(manifest)));
    f.network.handler = (r) {
      if (r.url.path.startsWith('/catalog/')) {
        final query = Uri.decodeComponent(
          r.url.path.split('search=').last.replaceFirst(RegExp(r'\.json$'), ''),
        );
        catalogQueries.add(query);
        return catalog?.call(r) ?? response(metas);
      }
      if (r.url.path.startsWith('/subtitles/')) {
        subtitlePaths.add(r.url.path);
        return discovery?.call(r) ?? slots('identify');
      }
      if (r.url.path.endsWith('.srt')) {
        return http.Response(
          '1\n00:00:01,000 --> 00:00:02,000\nIdentity caption\n',
          200,
        );
      }
      return f.network.replies[r.url.toString()] ?? http.Response('{}', 404);
    };
  }

  Future<void> mountIdentity({
    VideoPlayerScreen screen = identifyScreen,
    bool rooted = false,
  }) => observe(() => _mountIdentity(screen: screen, rooted: rooted));
  Future<void> _mountIdentity({
    VideoPlayerScreen screen = identifyScreen,
    bool rooted = false,
  }) async {
    if (!rooted) {
      await mount(screen: screen);
      return;
    }
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: f.navigator,
        theme: ThemeData.dark(),
        home: const Scaffold(),
      ),
    );
    playerRoute = MaterialPageRoute<void>(builder: (_) => screen);
    observe(() => f.navigator.currentState!.push(playerRoute!));
    await f.until(t, () => f.controllers.isNotEmpty);
    player.deliverReady();
    await f.until(t, () => player.calls.any((c) => c.$1 == 'open'));
    publish();
    await f.advance(t, const Duration(seconds: 2));
    await f.until(t, () => periodic.contains(const Duration(seconds: 6)));
  }

  PlayerMenuPanel get panel =>
      t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
  TvTextField get searchField {
    final field = find.byWidgetPredicate(
      (w) =>
          w is TvTextField && w.decoration?.hintText == 'Search movie or show',
    );
    expect(field, findsOneWidget);
    return t.widget<TvTextField>(field);
  }

  Finder get editable => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == 'Search movie or show',
  );
  Future<TracksSheetSubtitleSearchResult?> start(PlayerMenuPanel menu) => f
      .actions
      .start(
        'identify-title public action',
        () => observe(() => menu.onIdentifyTitle!()),
        held: true,
      )
      .future;
  Future<void> sheet() async =>
      f.until(t, () => find.text('FIX THE TITLE').evaluate().isNotEmpty);
  Future<void> found(String label) async =>
      f.until(t, () => find.text(label).evaluate().isNotEmpty);
  Future<void> type(String text) async {
    await t.enterText(editable, text);
    await f.advance(t);
  }

  Future<void> submit(String text) async {
    await type(text);
    await t.testTextInput.receiveAction(TextInputAction.search);
    await f.advance(t);
  }

  Future<void> suffix() async {
    await t.tap(find.byIcon(Icons.arrow_forward_rounded));
    await f.advance(t);
  }

  Future<void> dismiss() async {
    f.navigator.currentState!.pop();
    await f.advance(t);
    await f.advance(t, const Duration(milliseconds: 350));
  }

  Future<void> removePlayer({bool modalExpected = true}) async {
    expect(playerRoute, isNotNull);
    f.navigator.currentState!.removeRoute(playerRoute!);
    disposedRoute = true;
    await f.until(t, () => player.disposed.isCompleted);
    if (modalExpected) {
      expect(
        find.text('FIX THE TITLE').evaluate().isNotEmpty ||
            find.text('Which episode?').evaluate().isNotEmpty,
        isTrue,
      );
    }
  }

  Future<void> episode(String season, String episode) async {
    await found('Which episode?');
    for (final entry in {'Season': season, 'Episode': episode}.entries) {
      await t.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == entry.key,
        ),
        entry.value,
      );
    }
    await t.tap(find.text('Apply'));
    await f.advance(t);
  }

  @override
  Future<void> close() async {
    // A failed assertion must still let the real modal Future return. Disposing
    // the root Navigator alone strands that Future and masks the first failure.
    if ((f.navigator.currentState?.canPop() ?? false) &&
        find.byType(ModalBarrier).evaluate().isNotEmpty) {
      FocusManager.instance.primaryFocus?.unfocus();
      await f.advance(t);
      f.navigator.currentState!.pop();
      await f.advance(t);
      await f.advance(t, const Duration(milliseconds: 350));
    }
    await super.close();
  }

  Future<T> observeFuture<T>(Future<T> Function() action) {
    final completion = Completer<T>();
    observe(
      () => action().then<void>(
        completion.complete,
        onError: completion.completeError,
      ),
    );
    return completion.future;
  }
}

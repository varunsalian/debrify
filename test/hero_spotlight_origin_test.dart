import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/app_route_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'favourites_rows_origin_test.dart'
    show pumpFavourites, closeFavourites;
import 'hero_presenter_origin_test.dart'
    show HeroOriginTransport, prepareHero, focusHero, heroItem;

// PREP ONLY: not executed or green. Public host/row focus and rendered widgets;
// no private State access, copied presenter, native playback or error invocation.
class _PassiveTransport extends HeroOriginTransport {
  _PassiveTransport(List<String> ids)
      : metadataUrls = {
          for (final id in ids)
            Uri.parse('https://hero-meta.invalid/meta/movie/$id.json'),
        },
        logoUrls = {
          for (final id in ids)
            Uri.parse('https://images.metahub.space/logo/medium/$id/img'),
        },
        backgroundUrls = {
          for (final id in ids)
            Uri.parse('https://images.metahub.space/background/medium/$id/img'),
        };

  final Set<Uri> metadataUrls;
  final Set<Uri> logoUrls;
  final Set<Uri> backgroundUrls;
  final unexpected = <Uri>[];
  final logoRequests = <Uri>[];
  final backgroundRequests = <Uri>[];

  Future<http.Response> metadata(http.Request request) {
    if (request.method == 'GET' && metadataUrls.contains(request.url)) {
      return send(request);
    }
    unexpected.add(request.url);
    throw StateError('Unexpected passive metadata transport: ${request.url}');
  }

  Future<http.Response> artwork(http.Request request) async {
    if (request.method == 'GET' && logoUrls.contains(request.url)) {
      logoRequests.add(request.url);
      return http.Response('', 404);
    }
    if (request.method == 'GET' && backgroundUrls.contains(request.url)) {
      backgroundRequests.add(request.url);
      return http.Response('', 404);
    }
    unexpected.add(request.url);
    throw StateError('Unexpected passive artwork transport: ${request.url}');
  }

  void finishMetadata(String id) {
    final held = pending[id];
    if (held == null || held.isCompleted) return;
    held.complete(http.Response(jsonEncode({
      'meta': {
        'id': id,
        'type': 'movie',
        'name': 'Enriched $id',
        'description': 'Passive description $id',
        'imdbRating': '8.1',
        'runtime': '101 min',
      },
    }), 200));
  }
}

Finder _title(String id) => find.byWidgetPredicate((widget) =>
    widget is Text &&
    widget.data == 'Title $id' &&
    widget.maxLines == 2 &&
    widget.style?.fontSize == 38);

// Nearest public render wrapper, independent of either private class's name.
FadeTransition _titleFade(WidgetTester tester, String id) {
  expect(_title(id), findsOneWidget);
  FadeTransition? fade;
  tester.element(_title(id)).visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is FadeTransition) {
      fade = widget;
      return false;
    }
    return true;
  });
  expect(fade, isNotNull);
  return fade!;
}

Future<void> _case(WidgetTester tester, {required bool reduced}) async {
  final ids = reduced
      ? ['tt9987201', 'tt9987202']
      : ['tt9987101', 'tt9987102'];
  final io = _PassiveTransport(ids);
  BaseCacheManager? previousCache;
  CacheManager? cache;
  await http.runWithClient(() async {
    await prepareHero(tester, ids);
    final imageClient = MockClient(io.artwork);
    try {
      // The existing fixture must install path-provider before this first
      // static read: the default manager starts real directory/repository IO.
      await tester.runAsync(() async {
        previousCache = CachedNetworkImageProvider.defaultCacheManager;
        cache = CacheManager(Config(
          'hero-passive-origin-${ids.first}',
          fileService: HttpFileService(httpClient: imageClient),
        ));
        final probe = 'hero-cache-readiness-${ids.first}';
        Future<void> awaitCacheIO(BaseCacheManager manager) async {
          if (manager is! CacheManager) {
            throw StateError('Expected the real CacheManager');
          }
          final repository = manager.config.repo;
          if (repository is! JsonCacheInfoRepository) {
            throw StateError('Expected the Windows/Linux JSON repository');
          }
          final opening = repository.openCompleter;
          if (opening == null) {
            throw StateError('Expected constructor-started repository open');
          }
          // Observe the existing open; no connection increment or cache lookup
          // (even a lookup miss would schedule a real cleanup timer).
          await opening.future;
          await manager.config.fileSystem.createFile(probe);
        }
        await awaitCacheIO(previousCache!);
        await awaitCacheIO(cache!);
        CachedNetworkImageProvider.defaultCacheManager = cache!;
      });
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [appRouteObserver],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(0.8),
            disableAnimations: reduced,
          ),
          child: child!,
        ),
        home: const SearchScreen(isTelevision: true),
      ));
      await pumpFavourites(tester);
      await focusHero(tester, ids.first);
      await pumpFavourites(tester);
      final a = heroItem(tester).value!.id;
      final b = ids.firstWhere((id) => id != a);
      // Visit both real rows once so actual logo failure has reached text;
      // revisit exercises the same session memo without resetting it.
      await focusHero(tester, b);
      await pumpFavourites(tester);
      expect(_title(b), findsOneWidget);
      await focusHero(tester, a);
      await pumpFavourites(tester);
      expect(_title(a), findsOneWidget);
      expect(_titleFade(tester, a).opacity.value, 1);

      await focusHero(tester, b);
      await tester.pump(const Duration(milliseconds: 260));
      expect(heroItem(tester).value!.id, b);
      expect(_title(b), findsOneWidget);
      expect(_titleFade(tester, b).opacity.value, reduced ? 1 : 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_titleFade(tester, b).opacity.value,
          reduced ? equals(1) : allOf(greaterThan(0), lessThan(1)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_titleFade(tester, b).opacity.value, 1);
      expect(find.text('Passive description $b'), findsNothing);
      expect(io.pending[b], isNotNull);
      expect(io.pending[b]!.isCompleted, isFalse);
      final enrichmentTime = tester.binding.clock.now();
      io.finishMetadata(b);
      // Flush the small inline-decoded response and paint its actual rebuild
      // without advancing the animation clock: a replay must not settle unseen.
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(tester.binding.clock.now(), enrichmentTime);
      expect(find.text('Passive description $b'), findsOneWidget);
      expect(_title(b), findsOneWidget);
      expect(find.text('Enriched $b'), findsNothing);
      expect(_titleFade(tester, b).opacity.value, 1);
      await pumpFavourites(tester);
      expect(find.text('Passive description $b'), findsOneWidget);
      expect(_titleFade(tester, b).opacity.value, 1);
      expect(io.logoRequests, isNotEmpty);
      expect(io.unexpected, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      for (final id in io.pending.keys.toList()) {
        io.finishMetadata(id);
      }
      try {
        await closeFavourites(tester);
      } finally {
        final borrowed = previousCache;
        if (borrowed != null) {
          CachedNetworkImageProvider.defaultCacheManager = borrowed;
        }
        try {
          // Finish the owned repository's real file write while the helper's
          // path-provider handler and temporary directory still exist.
          await tester.runAsync(() async => cache?.dispose());
        } finally {
          imageClient.close();
        }
      }
    }
    expect(io.unexpected, isEmpty);
    expect(tester.takeException(), isNull);
  }, () => MockClient(io.metadata));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('actual host title ID restarts cascade; enrichment keeps identity',
      (tester) => _case(tester, reduced: false));
  testWidgets('public reduced motion keeps title cascade settled on focus change',
      (tester) => _case(tester, reduced: true));
}

import 'dart:async';
import 'dart:io';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/detail/detail_episode_cells.dart';
import 'package:debrify/widgets/detail/detail_layout_console.dart';
import 'package:debrify/widgets/detail/detail_layout_dossier.dart';
import 'package:debrify/widgets/detail/detail_layout_marquee.dart';
import 'package:debrify/widgets/detail/detail_layout_premium.dart';
import 'package:debrify/widgets/detail/detail_layout_showcase.dart';
import 'package:debrify/widgets/detail/detail_layout_stage.dart';
import 'package:debrify/widgets/detail/detail_style.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/merged_detail_fixture.dart';
import '../../../../support/merged_detail_goldens.dart';

class EqualMergedMeta extends StremioMeta {
  const EqualMergedMeta() : super(id: 'one', type: 'movie', name: 'One');
  @override
  bool operator ==(Object other) => other is EqualMergedMeta;
  @override
  int get hashCode => 1;
}

void main() {
  final comparator = goldenFileComparator;
  if (comparator is LocalFileComparator) {
    goldenFileComparator = MergedDetailGoldenComparator(
      comparator.basedir.resolve('merged_detail_views_test.dart'),
    );
  }

  for (final style in [
    'classic',
    'marquee',
    'dossier',
    'stage',
    'console',
    'vista',
    'monolith',
    'mosaic',
    'halo',
    'premiere',
    'showcase',
    'unknown',
  ]) {
    testWidgets(
      'production style branch $style mounts its original body and wrappers',
      (t) async {
        await mergedDetailCase(t, (f) async {
          f.item = const StremioMeta(
            id: 'original-movie',
            type: 'movie',
            name: 'Original Movie',
            description: 'A fixed original-code characterization fixture.',
            year: '2026',
            genres: ['Drama'],
            runtime: '104 min',
          );
          await f.mount(t, style: style);
          final type = switch (style) {
            'classic' => null,
            'marquee' => DetailMarquee,
            'dossier' => DetailDossier,
            'stage' => DetailStage,
            'showcase' => DetailShowcase,
            'vista' ||
            'monolith' ||
            'mosaic' ||
            'halo' ||
            'premiere' => DetailPremium,
            _ => DetailConsole,
          };
          for (final candidate in [
            DetailMarquee,
            DetailDossier,
            DetailStage,
            DetailShowcase,
            DetailPremium,
            DetailConsole,
          ]) {
            expect(
              find.byType(candidate),
              candidate == type ? findsOneWidget : findsNothing,
            );
          }
          expect(find.byType(EpisodesPanel), findsNothing);
          if (type != null) {
            expect(
              find.ancestor(
                of: find.byType(type),
                matching: find.byType(DetailThemeScope),
              ),
              findsOneWidget,
            );
            expect(
              find.ancestor(
                of: find.byType(type),
                matching: find.byType(DetailAtmosphere),
              ),
              findsOneWidget,
            );
            expect(
              find.ancestor(
                of: find.byType(type),
                matching: find.byType(DetailHoldHint),
              ),
              findsOneWidget,
            );
          } else {
            expect(find.byType(DetailThemeScope), findsNothing);
            expect(find.text('Original Movie'), findsOneWidget);
          }
          if (type == DetailPremium) {
            expect(
              t.widget<DetailPremium>(find.byType(DetailPremium)).kind.name,
              style,
            );
          }
          if (type != null) {
            final model = (t.widget(find.byType(type)) as dynamic).model;
            expect(model.item.name, 'Original Movie');
            expect(model.isMovie, true);
          } else {
            expect(find.text('Play'), findsOneWidget);
          }
        });
      },
    );
  }
  final captures = [
    (
      name: 'classic_two_pane',
      style: 'classic',
      size: const Size(1200, 900),
      movie: false,
      television: true,
    ),
    (
      name: 'classic_stacked_phone',
      style: 'classic',
      size: const Size(430, 900),
      movie: false,
      television: false,
    ),
    (
      name: 'classic_movie_column',
      style: 'classic',
      size: const Size(1200, 900),
      movie: true,
      television: false,
    ),
    (
      name: 'console',
      style: 'console',
      size: const Size(1200, 900),
      movie: true,
      television: false,
    ),
    (
      name: 'showcase',
      style: 'showcase',
      size: const Size(1200, 900),
      movie: true,
      television: false,
    ),
  ];
  for (final c in captures) {
    testWidgets('reachable pixel golden ${c.name}', (t) async {
      await mergedDetailCase(t, (f) async {
        f.television = c.television;
        f.xtream = !c.movie;
        if (c.movie) {
          f.item = const StremioMeta(
            id: 'original-movie',
            type: 'movie',
            name: 'Original Movie',
            description: 'A fixed original-code characterization fixture.',
            year: '2026',
            genres: ['Drama'],
            runtime: '104 min',
          );
        }
        await f.mount(t, style: c.style, size: c.size);
        expect(f.observation.openingDataReady, true);
        expect(f.observation.trailerBusy, false);
        expect(f.observation.hasTrailer, false);
        final reveals = find.byWidgetPredicate(
          (w) => w.runtimeType.toString().endsWith('StaggerReveal'),
        );
        for (final element
            in find
                .descendant(of: reveals, matching: find.byType(AnimatedBuilder))
                .evaluate()) {
          final animation = (element.widget as AnimatedBuilder).animation;
          if (animation is AnimationController) {
            expect(animation.isCompleted, true);
          }
        }
        if (c.television) {
          (f.access['leftEntry'] as FocusNode).requestFocus();
          await t.pump();
          expect((f.access['leftEntry'] as FocusNode).hasFocus, true);
        } else {
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pump();
        }
        final platform = Platform.isLinux ? 'linux' : 'macos';
        final path = 'test/goldens/merged_detail/$platform/${c.name}.png';
        const captureLinux = bool.fromEnvironment(
          'MERGED_DETAIL_CAPTURE_ORIGINAL_LINUX',
        );
        const requireLinux = bool.fromEnvironment(
          'MERGED_DETAIL_REQUIRE_ORIGINAL_LINUX',
        );
        if (Platform.isLinux &&
            !captureLinux &&
            !requireLinux &&
            !File(path).existsSync()) {
          return;
        }
        expect(
          File(path).existsSync() || autoUpdateGoldenFiles,
          true,
          reason: 'Missing original golden $path',
        );
        await expectLater(
          find.byKey(const ValueKey('merged-canvas')),
          matchesGoldenFile(
            '../../../../goldens/merged_detail/$platform/${c.name}.png',
          ),
        );
      });
    });
  }
  testWidgets('resource and identity owners survive rebuilds', (t) async {
    await mergedDetailCase(t, (f) async {
      f.heldRecommendations = Completer<List<StremioMeta>>();
      await f.mount(t, wait: false);
      expect(f.access['recommendations'], isNull);
      final first = f.access;
      final originals = first['recommendationOriginals'] as Map;
      const a = EqualMergedMeta();
      final b = EqualMergedMeta();
      expect(a, equals(b));
      expect(identical(a, b), false);
      originals[a] = a;
      originals[b] = b;
      expect(originals, hasLength(2));
      originals.clear();
      f.heldRecommendations!.complete([]);
      await f.finishOpening(t);
      f.next((season: 1, episode: 2, started: true), mutation: true);
      await t.pump();
      await t.pump();
      for (final key in [
        'recommendationOriginals',
        'backdropKey',
        'episodesPanelKey',
        'infoScroll',
        'castRailScroll',
        'recommendationRailScroll',
        'leftEntry',
        'infoPane',
        'episodesPane',
        'backButton',
      ]) {
        expect(f.access[key], same(first[key]), reason: key);
      }
    });
  });
}

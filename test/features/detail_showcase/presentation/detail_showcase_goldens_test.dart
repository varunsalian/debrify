import 'dart:io';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/widgets/detail/showcase_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/detail_showcase_fixture.dart';

const captureLinux = bool.fromEnvironment(
  'DETAIL_SHOWCASE_CAPTURE_ORIGINAL_LINUX',
);
const requireLinux = bool.fromEnvironment(
  'DETAIL_SHOWCASE_REQUIRE_ORIGINAL_LINUX',
);

void main() {
  for (final scene in [
    'tv_movie',
    'compact_series',
    'wide_series_bands',
    'compact_guide',
  ]) {
    final platform = Platform.isLinux ? 'linux' : 'macos';
    final path = 'test/goldens/detail_showcase/$platform/$scene.png';
    testWidgets(
      'original pixel golden $scene',
      (t) async {
        final size = switch (scene) {
          'tv_movie' => const Size(1920, 1080),
          'wide_series_bands' => const Size(1280, 2600),
          _ => const Size(390, 844),
        };
        await showcaseCase(
          t,
          (f) async {
            final promised = <Finder>[];
            Widget child;
            var compact = false;
            var touch = false;
            if (scene == 'tv_movie') {
              child = f.page(value: f.model(trailer: false));
              promised.add(find.byType(ShowcaseIdentity));
            } else if (scene == 'compact_series') {
              compact = touch = true;
              child = Column(
                children: [
                  ShowcaseSeasons(view: f.view(), nodes: f.nodes(2, 'season')),
                  const SizedBox(height: 20),
                  ShowcaseEpisodeCardCompact(
                    episode: f.episode(1),
                    focused: false,
                    progress: 25,
                    isNext: true,
                    fallbackImage: null,
                    onOptions: () => f.calls.add('options'),
                  ),
                  const ShowcaseBandNote(text: 'Original series note'),
                ],
              );
              promised.addAll([
                find.byType(ShowcaseSeasons),
                find.byType(ShowcaseEpisodeCardCompact),
                find.byType(ShowcaseBandNote),
              ]);
            } else if (scene == 'compact_guide') {
              compact = touch = true;
              child = ShowcaseGuide(
                guide: showcaseGuide(),
                nodes: f.nodes(3, 'guide'),
                accent: Colors.yellow,
              );
              promised.add(find.byType(ShowcaseGuide));
            } else {
              child = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShowcaseSeasons(view: f.view(), nodes: f.nodes(2, 'season')),
                  SizedBox(
                    height: 360,
                    child: Row(
                      children: [
                        for (var i = 1; i <= 2; i++)
                          ShowcaseEpisodeCell(
                            episode: f.episode(i),
                            focused: false,
                            progress: i == 1 ? 25 : null,
                            isNext: i == 1,
                            fallbackImage: null,
                          ),
                      ],
                    ),
                  ),
                  ShowcaseCast(
                    cast: const [
                      CastMember(name: 'A Person', character: 'Someone'),
                      CastMember(name: 'B Person', character: 'Someone Else'),
                    ],
                    nodes: f.nodes(2, 'cast'),
                  ),
                  ShowcaseSources(
                    sources: const [],
                    nodes: f.nodes(3, 'source'),
                    onOpen: () => f.calls.add('open'),
                    onBrowseAll: () => f.calls.add('browse'),
                  ),
                  ShowcaseRecs(
                    items: const [
                      StremioMeta(
                        id: 'tt1',
                        type: 'movie',
                        name: 'A Recommendation',
                      ),
                    ],
                    nodes: f.nodes(1, 'rec'),
                    onTap: (_) => f.calls.add('tap'),
                  ),
                  ShowcaseGuide(
                    guide: showcaseGuide(),
                    nodes: f.nodes(3, 'guide'),
                    accent: Colors.yellow,
                  ),
                  ShowcaseUniverse(
                    items: const [
                      UniverseTitle(
                        imdbId: 'tt2',
                        name: 'A Related Title',
                        relation: 'Followed by',
                        year: 2026,
                      ),
                    ],
                    nodes: f.nodes(1, 'universe'),
                    onOpen: (_) => f.calls.add('universe'),
                  ),
                  ShowcaseDidYouKnow(
                    entries: const [
                      DidYouKnowEntry(
                        kind: 'Trivia',
                        text: 'A fact about the original production.',
                      ),
                    ],
                    total: 4,
                    countLine: '4 trivia',
                    nodes: f.nodes(2, 'dyk'),
                  ),
                  ShowcaseBandNote(
                    text: 'Original band note',
                    actionLabel: 'Retry',
                    actionNode: f.node('retry'),
                    onAction: () => f.calls.add('action'),
                  ),
                  const ShowcaseDetails(
                    rows: [('Country', 'India'), ('Language', 'English')],
                    awards: 'An award',
                  ),
                ],
              );
              promised.addAll([
                find.byType(ShowcaseSeasons),
                find.byType(ShowcaseEpisodeCell).first,
                find.byType(ShowcaseCast),
                find.byType(ShowcaseSources),
                find.byType(ShowcaseRecs),
                find.byType(ShowcaseGuide),
                find.byType(ShowcaseUniverse),
                find.byType(ShowcaseDidYouKnow),
                find.byType(ShowcaseBandNote),
                find.byType(ShowcaseDetails),
              ]);
            }
            await t.pumpWidget(
              f.host(
                RepaintBoundary(key: const ValueKey('capture'), child: child),
                size: size,
                compact: compact,
                touch: touch,
              ),
            );
            await showcasePump(t);
            if (scene == 'tv_movie') {
              f.primary.requestFocus();
              await showcasePump(t);
              expect(f.primary.hasFocus, isTrue);
            }
            if (scene == 'compact_guide') {
              await t.tap(find.text('Category 1'));
              await showcasePump(t);
              expect(find.text('Plain 1'), findsOneWidget);
            }
            final bounds = Offset.zero & size;
            for (final band in promised) {
              expect(band, findsOneWidget);
              expect(
                t.getRect(band).overlaps(bounds),
                isTrue,
                reason:
                    'promised band must intersect $scene capture bounds: $band',
              );
            }
            expect(t.takeException(), isNull);
            expect(
              File(path).existsSync() || autoUpdateGoldenFiles,
              isTrue,
              reason: 'original golden required: $path',
            );
            await expectLater(
              find.byKey(const ValueKey('capture')),
              matchesGoldenFile(
                '../../../goldens/detail_showcase/$platform/$scene.png',
              ),
            );
          },
          size: size,
          television: scene == 'tv_movie',
        );
      },
      skip:
          Platform.isLinux &&
          !captureLinux &&
          !requireLinux &&
          !File(path).existsSync(),
    );
  }
}

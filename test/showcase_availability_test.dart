import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/metadata_explore_service.dart';
import 'package:debrify/widgets/detail/showcase_availability.dart';
import 'package:debrify/widgets/detail/showcase_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rail focus reveals tiles without moving the vertical page', (
    tester,
  ) async {
    final vertical = ScrollController(initialScrollOffset: 300);
    final nodes = List.generate(12, (_) => FocusNode());
    addTearDown(() {
      vertical.dispose();
      for (final node in nodes) {
        node.dispose();
      }
    });
    tester.view.physicalSize = const Size(600, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: vertical,
            child: Column(
              children: [
                const SizedBox(height: 450),
                ShowcaseAvailabilityBand(
                  row: ShowcaseAvailabilityRow(
                    'watch-rent',
                    'Rent',
                    List.generate(
                      12,
                      (i) => ShowcaseAvailabilityEntry('Provider $i'),
                    ),
                  ),
                  nodes: nodes,
                  accent: Colors.red,
                  onRetry: () {},
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final horizontal = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position;
    final parked = vertical.offset;
    nodes.first.requestFocus();
    await tester.pumpAndSettle();
    expect(vertical.offset, parked);
    // Walk mounted nodes just as Showcase's DPAD ladder does, bringing later
    // tiles into view without letting the rail reposition its parent page.
    for (var i = 1; i < 8; i++) {
      nodes[i].requestFocus();
      await tester.pumpAndSettle();
      expect(nodes[i].hasFocus, isTrue);
      expect(vertical.offset, parked);
    }
    expect(horizontal.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  const data = MetadataExploreData(
    companies: [
      {'id': 1, 'name': 'Studio', 'logo_path': '/studio.png'},
    ],
    networks: [
      {'id': 2, 'name': 'Network'},
    ],
    providers: {
      'flatrate': [
        {'provider_name': 'Provider', 'logo_path': '/provider.png'},
      ],
      'free': [
        {'provider_name': 'Free provider'},
      ],
      'ads': [
        {'provider_name': 'Ads provider'},
      ],
    },
    providerLink: 'https://www.themoviedb.org/movie/1/watch',
  );
  test(
    'toggles gate sections independently and preserve TMDB logos and region',
    () {
      expect(
        showcaseAvailabilityRows(data, MetadataPreferences(features: {})),
        isEmpty,
      );
      final studios = showcaseAvailabilityRows(
        data,
        MetadataPreferences(features: {MetadataFeature.companies}),
      );
      expect(studios, hasLength(1));
      expect(studios.single.entries.map((e) => e.kind), ['company', 'network']);
      expect(
        studios.single.entries.first.logo,
        'https://image.tmdb.org/t/p/w185/studio.png',
      );
      final rows = showcaseAvailabilityRows(
        data,
        MetadataPreferences(
          region: 'IN',
          features: {MetadataFeature.availability},
        ),
      );
      expect(rows.map((r) => r.key), [
        'watch-flatrate',
        'watch-free',
        'watch-ads',
        'watch-attribution',
      ]);
      expect(rows.first.title, contains('IN'));
      expect(
        rows.first.entries.single.logo,
        'https://image.tmdb.org/t/p/w185/provider.png',
      );
      expect(rows.last.entries.single.link, data.providerLink);
    },
  );
  test(
    'empty regional availability is explicit and unsafe links stay inert',
    () {
      final rows = showcaseAvailabilityRows(
        const MetadataExploreData(providerLink: 'https://evil.test/'),
        MetadataPreferences(features: {MetadataFeature.availability}),
      );
      expect(rows.single.entries.single.name, contains('No availability'));
      expect(rows.single.entries.single.link, isNull);
    },
  );
  for (final compact in [true, false]) {
    testWidgets(
      'provider tiles fit long names and enlarged text compact=$compact',
      (tester) async {
        final nodes = [FocusNode(), FocusNode()];
        addTearDown(() {
          for (final node in nodes) {
            node.dispose();
          }
        });
        final width = compact ? 360.0 : 960.0;
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 600),
                textScaler: const TextScaler.linear(1.5),
              ),
              child: Scaffold(
                body: ShowcaseMetricsScope(
                  metrics: ShowcaseMetrics(
                    width,
                    compact: compact,
                    touch: compact,
                  ),
                  child: ShowcaseAvailabilityBand(
                    row: const ShowcaseAvailabilityRow('watch-rent', 'Rent', [
                      ShowcaseAvailabilityEntry(
                        'MGM Plus Roku Premium Channel',
                      ),
                      ShowcaseAvailabilityEntry('Apple TV Store'),
                    ]),
                    nodes: nodes,
                    accent: Colors.red,
                    onRetry: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        nodes.first.requestFocus();
        await tester.pumpAndSettle();
        expect(nodes.first.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

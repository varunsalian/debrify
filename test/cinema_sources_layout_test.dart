import 'package:debrify/models/play_loader_art.dart';
import 'package:debrify/models/stream_badge_rules.dart';
import 'package:debrify/services/stream_badge_matcher.dart';
import 'package:debrify/services/stream_badges_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/format_tag_detector.dart';
import 'package:debrify/widgets/cinema_sources_layout.dart';
import 'package:debrify/widgets/format_badge.dart';
import 'package:debrify/widgets/source_list_scroll_anchor.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:debrify/widgets/stream_badge_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _providers = [
  CinemaSourceProvider(id: null, label: 'All sources', count: 12),
  CinemaSourceProvider(id: 'torrentio', label: 'Torrentio', count: 8),
  CinemaSourceProvider(id: 'jackett', label: 'Jackett', count: 4),
];

void main() {
  test(
    'large available panes use cinema; phones and split views stay compact',
    () {
      for (final size in [
        const Size(768, 1024),
        const Size(1024, 768),
        const Size(1280, 720),
      ]) {
        expect(
          useCinemaSourcesLayout(
            BoxConstraints.tight(size),
            isTelevision: false,
          ),
          isTrue,
        );
      }
      for (final size in [
        const Size(390, 844),
        const Size(844, 390),
        const Size(600, 900),
      ]) {
        expect(
          useCinemaSourcesLayout(
            BoxConstraints.tight(size),
            isTelevision: false,
          ),
          isFalse,
        );
      }
      expect(
        useCinemaSourcesLayout(
          BoxConstraints.tight(const Size(640, 360)),
          isTelevision: true,
        ),
        isTrue,
      );
    },
  );

  for (final (size, tv) in [
    (const Size(640, 360), true),
    (const Size(960, 540), true),
    (const Size(1280, 720), true),
    (const Size(768, 1024), false),
    (const Size(1024, 768), false),
  ]) {
    testWidgets('custom badges wrap without focus reflow at $size, tv=$tv', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = StreamBadgesService.instance;
      service.resetProfileScope();
      addTearDown(service.resetProfileScope);
      final rules = [
        for (final name in [
          '4K UHD',
          'REMUX',
          'DOLBY VISION',
          'HDR10+',
          'TRUEHD',
          'ATMOS',
          '7.1',
          'ENGLISH',
        ])
          StreamBadgeRule(
            id: name,
            groupId: 'formats',
            name: name,
            pattern: 'Movie',
          ),
      ];
      final matcher = StreamBadgeMatcher([
        StreamBadgeRuleset(groups: const [], rules: rules),
      ]);
      service.matcher.value = matcher;
      await tester.runAsync(() => matcher.matchesFor(name: 'Movie'));
      final row = FocusNode();
      addTearDown(row.dispose);
      final key = GlobalKey<CinemaSourcesLayoutState>();
      var plays = 0;
      await tester.pumpWidget(
        _app(
          CinemaSourcesLayout(
            key: key,
            contextTitle: 'A long movie title with enough words to wrap',
            contextLabel: 'Season 2 · Episode 7',
            art: const PlayLoaderArt(
              yearLabel: '2024',
              runtimeLabel: '2h 47m',
              genreLabel: 'Science fiction · Adventure',
            ),
            title: 'Choose a source',
            subtitle: 'Movie sources',
            onBack: () {},
            providers: _providers,
            selectedProvider: null,
            onProviderSelected: (_) {},
            onFocusResults: row.requestFocus,
            isSourceFocused: () => row.hasFocus,
            resultCount: 12,
            isTelevision: tv,
            child: SourceListScrollAnchor(
              child: ListView(
                children: [
                  SourceRow(
                    listIndex: 0,
                    title:
                        'Movie.2024.2160p.UHD.BluRay.REMUX.DV.HDR.HEVC.TrueHD.7.1.Atmos',
                    titleMaxLines: 6,
                    subtitle: '66.8 GB · 248 seeders · Torrentio',
                    focusNode: row,
                    onTap: () => plays++,
                    isTelevision: tv,
                    cinemaLayout: true,
                    showPlayPill: tv,
                    formatTags: FormatTagDetector.detect(
                      'Movie.2160p.REMUX.HDR',
                    ),
                    badgeName: 'Movie',
                    cacheLabel: 'TB | PM',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(StreamBadgeChip), findsNWidgets(rules.length));
      expect(find.byType(FormatBadge), findsNothing);
      expect(find.text('TB | PM'), findsOneWidget);
      final geometry = tester.getSize(find.byType(SourceRow));
      final badgeStrip = tester.widget(find.byType(StreamBadgeStrip));
      row.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(row.hasFocus, isFalse);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'cinema-provider-all',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(row.hasFocus, isTrue);
      expect(tester.getSize(find.byType(SourceRow)), geometry);
      expect(
        identical(tester.widget(find.byType(StreamBadgeStrip)), badgeStrip),
        isTrue,
      );
      expect(plays, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('overflowing providers stay visible going down and back up', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<CinemaSourcesLayoutState>();
    final providers = [
      _providers.first,
      for (var i = 1; i <= 16; i++)
        CinemaSourceProvider(id: '$i', label: 'Provider $i', count: i),
    ];
    await tester.pumpWidget(
      _app(
        CinemaSourcesLayout(
          key: key,
          contextTitle: 'Movie',
          title: 'Choose a source',
          providers: providers,
          selectedProvider: null,
          onProviderSelected: (_) {},
          onFocusResults: () {},
          isSourceFocused: () => false,
          resultCount: 12,
          isTelevision: true,
          child: const SizedBox(),
        ),
      ),
    );
    key.currentState!.focusSelectedProvider();
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    void expectVisible(int index) {
      final provider = providers[index];
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'cinema-provider-${provider.id ?? 'all'}',
      );
      final entry = tester.getRect(
        find.byKey(ValueKey(('cinema-provider', provider.id))),
      );
      expect(
        entry.top,
        greaterThanOrEqualTo(viewport.top - .01),
        reason: '${provider.label} is above the viewport',
      );
      expect(
        entry.bottom,
        lessThanOrEqualTo(viewport.bottom + .01),
        reason: '${provider.label} is below the viewport',
      );
    }

    expectVisible(0);
    for (var i = 1; i < providers.length; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expectVisible(i);
    }
    for (var i = providers.length - 2; i >= 0; i--) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expectVisible(i);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'provider identity survives insertions; removal returns focus to All',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<CinemaSourcesLayoutState>();
      var selected = 'jackett';
      Widget build(
        List<CinemaSourceProvider> providers, {
        bool enabled = true,
      }) => _app(
        CinemaSourcesLayout(
          key: key,
          contextTitle: 'dune part two',
          title: 'Search results',
          providers: providers,
          selectedProvider: selected,
          onProviderSelected: (id) => selected = id ?? 'all',
          onFocusResults: () {},
          isSourceFocused: () => false,
          resultCount: 12,
          isTelevision: true,
          providersEnabled: enabled,
          child: const SizedBox(),
        ),
      );
      await tester.pumpWidget(build(_providers));
      key.currentState!.focusSelectedProvider();
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus;
      await tester.pumpWidget(
        build([
          _providers.first,
          const CinemaSourceProvider(id: 'comet', label: 'Comet', count: 3),
          ..._providers.skip(1),
        ]),
      );
      expect(FocusManager.instance.primaryFocus, same(focused));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selected, 'jackett');
      await tester.pumpWidget(build(_providers.take(2).toList()));
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'cinema-provider-all',
      );
      await tester.pumpWidget(build(_providers, enabled: false));
      await tester.tap(find.text('Torrentio'));
      expect(
        selected,
        'jackett',
        reason: 'multi-select locks source switching',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData.dark(),
  home: AppThemeScope(
    theme: AppThemes.legacy,
    child: Scaffold(body: child),
  ),
);

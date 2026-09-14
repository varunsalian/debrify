import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LoadingBoard extends SpotlightBoard {
  const _LoadingBoard({required super.heroNode})
    : super(
        hero: const [StremioMeta(id: 'alignment', type: 'movie', name: 'Title')],
        sections: const [],
        heroAddon: null,
        onHeroOpen: _open,
        trailersEnabled: false,
      );

  static void _open(StremioMeta item, StremioAddon addon) {}

  @override
  SpotlightBoardState createState() => _LoadingBoardState();
}

class _LoadingBoardState extends SpotlightBoardState {
  bool pending = true;

  @override
  bool metadataArtworkPending(MetadataCategory category) => pending;

  void resolve() => setState(() => pending = false);
}

void main() {
  testWidgets('wide hero freezes alignment only after artwork loading ends', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: Scaffold(body: _LoadingBoard(heroNode: node)),
        ),
      ),
    );
    await tester.pump();
    final state = tester.state<_LoadingBoardState>(find.byType(_LoadingBoard));
    expect(state.heroAlignmentItemId, isNull);
    state.resolve();
    await tester.pump();
    expect(state.heroAlignmentItemId, 'alignment');
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final config in [
    (compact: false, dpad: true, dpr: 1.0, decode: 1400),
    (compact: true, dpad: false, dpr: 1.0, decode: 720),
    (compact: false, dpad: false, dpr: 2.0, decode: 1920),
  ]) {
    final compact = config.compact;
    testWidgets(
      'hero clears forbidden artwork and republishes after reset compact=$compact dpr=${config.dpr}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = (compact
            ? const Size(390, 844)
            : const Size(1280, 800)) * config.dpr;
        tester.view.devicePixelRatio = config.dpr;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final node = FocusNode();
        addTearDown(node.dispose);
        final ambient = <String?>[];
        StremioMeta? opened;
        const original = StremioMeta(
          id: 'unmapped-custom-title',
          type: 'movie',
          name: 'Title',
          background: 'https://example.invalid/original.jpg',
          poster: 'https://example.invalid/poster.jpg',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AppThemeScope(
              theme: AppThemes.legacy,
              child: Scaffold(
                body: SpotlightBoard(
                  hero: const [original],
                  sections: const [],
                  heroNode: node,
                  heroAddon: StremioAddon(
                    id: 'test',
                    name: 'Test',
                    manifestUrl: '',
                    baseUrl: '',
                  ),
                  onHeroOpen: (item, _) => opened = item,
                  onAmbient: (art, _) => ambient.add(art),
                  dpad: config.dpad,
                  trailersEnabled: false,
                ),
              ),
            ),
          ),
        );
        Future<void> settle() async {
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        await settle();
        final rendered = tester.widgetList<CachedNetworkImage>(
            find.byType(CachedNetworkImage)).firstWhere(
                (image) => image.imageUrl == original.background);
        expect(rendered.memCacheWidth, config.decode);
        final board = tester.state<SpotlightBoardState>(find.byType(SpotlightBoard));
        final warmedKey = await board.heroWarmupProvider(rendered.imageUrl)
            .obtainKey(ImageConfiguration.empty);
        final displayedKey = await ResizeImage.resizeIfNeeded(
            rendered.memCacheWidth, rendered.memCacheHeight,
            CachedNetworkImageProvider(rendered.imageUrl, cacheManager: rendered.cacheManager))
            .obtainKey(ImageConfiguration.empty);
        expect(warmedKey, displayedKey,
            reason: 'Preloading must reuse the displayed decoded image entry');
        await MetadataPreferencesService.save(
          MetadataPreferences(
            providers: {MetadataCategory.backgrounds: 'tmdb'},
          ),
        );
        await settle();
        expect(ambient, isNotEmpty);
        expect(ambient.last, isNull);
        if (compact) {
          await tester.tap(find.text('Title').first);
        } else {
          node.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        }
        expect(
          opened,
          same(original),
          reason: 'Details must receive the catalog baseline, not presentation',
        );

        final urls = tester
            .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .map((image) => image.imageUrl);
        expect(urls, isNot(contains(original.background)));
        expect(urls, isNot(contains(original.poster)));
        await MetadataPreferencesService.save(MetadataPreferences());
        await settle();
        expect(ambient.last, original.background);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }
}

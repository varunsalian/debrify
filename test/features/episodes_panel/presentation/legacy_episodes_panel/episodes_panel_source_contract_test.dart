import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../support/episodes_panel_source.dart';

void main() {
  final frozen =
      jsonDecode(
            File(
              'test/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_original_bodies.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  test('public widget byte identity, State header and both public methods', () {
    final facade = File('lib/widgets/episodes_panel.dart').readAsStringSync();
    expect(
      facade,
      contains(
        File(
          'dev/tool/episodes_panel_public_surface.txt',
        ).readAsStringSync().trimRight(),
      ),
    );
    expect(
      facade,
      contains('class EpisodesPanelState extends State<EpisodesPanel> {'),
    );
    for (final member in ['refreshWatchProgress', 'consumeFocusIntent']) {
      expect(
        episodesCanonicalSource(
          episodesOriginalMember('EpisodesPanelState.$member'),
        ),
        episodesCanonicalSource(frozen[member] as String),
      );
    }
  });
  for (final declaration in ['EpisodeFocusIntent', 'EpisodesPanelView']) {
    test('original $declaration public surface and comment fragments', () {
      expect(
        episodesCanonicalSource(episodesOriginalDeclaration(declaration)),
        episodesCanonicalSource(frozen[declaration] as String),
      );
    });
  }
  for (final method in ['initState', 'dispose']) {
    test('original $method complete statement order and comments', () {
      expect(
        episodesCanonicalSource(
          episodesOriginalMember('EpisodesPanelState.$method'),
        ),
        episodesCanonicalSource(frozen[method] as String),
      );
    });
  }
  test(
    'no extra State hooks or playback ownership; all original focus labels',
    () {
      final source = episodesPanelSource();
      for (final hook in [
        'didUpdateWidget',
        'didChangeDependencies',
        'deactivate',
      ]) {
        expect(source, isNot(contains(hook)));
      }
      for (final label in [
        'catalog-ep-back',
        'catalog-ep-season',
        'catalog-ep-retry',
        r'catalog-ep-$i',
        'catalog-select-source-btn',
      ]) {
        expect(source, contains(label));
      }
      for (final symbol in [
        'VideoPlayerLauncher',
        'VideoPlayerScreen',
        'SeriesSourceFetcher',
        'mergeSources',
        'TorrentPlayback',
      ]) {
        expect(source, isNot(contains(symbol)));
      }
      expect(source, isNot(contains('part ')));
    },
  );
  test('source reader retains comment/literal/interpolation identity', () {
    expect(
      episodesCanonicalSource("void f() { print('a b'); }"),
      isNot(episodesCanonicalSource("void f() { print('ab'); }")),
    );
    expect(
      episodesCanonicalSource('void f() {} // original'),
      isNot(episodesCanonicalSource('void f() {} // changed')),
    );
    expect(
      episodesCanonicalSource(r"print('${name}Suffix');"),
      isNot(episodesCanonicalSource(r"print('$nameSuffix');")),
    );
    expect(
      episodesCanonicalSource('f(a,);'),
      episodesCanonicalSource('f( a );'),
    );
  });
}

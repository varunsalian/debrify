import 'package:debrify/features/home/presentation/home_playback_artwork.dart';
import 'package:debrify/models/play_loader_art.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

const rich = PlayLoaderArt(
  backdropUrl: 'https://art.invalid/backdrop',
  logoUrl: 'https://art.invalid/logo',
  certificate: 'PG-13',
  runtimeLabel: '2h',
);
StremioMeta item({
  String id = 'channel:1',
  String title = 'First',
  String? imdbId,
  String? poster,
}) => StremioMeta(
  id: id,
  imdbId: imdbId,
  type: 'movie',
  name: title,
  poster: poster,
);

void main() {
  test('catalog capture supplies derived art for the progress identity', () {
    final owner = HomePlaybackArtwork();
    expect(owner.current, isNull);
    expect(owner.forSelection('tt123', 'First'), isNull);
    owner.capture(
      item(imdbId: 'tt123', poster: ' https://art.invalid/poster '),
    );
    final art = owner.current!;
    expect(art.posterUrl, 'https://art.invalid/poster');
    expect(
      art.backdropUrl,
      'https://images.metahub.space/background/medium/tt123/img',
    );
    expect(art.logoUrl, 'https://images.metahub.space/logo/medium/tt123/img');
    expect(owner.forSelection('tt123', 'First'), same(art));
    expect(owner.forSelection('channel:1', 'First'), isNull);
  });

  test(
    'detail enrichment wins over subsequent catalog captures of the same key',
    () {
      final owner = HomePlaybackArtwork();
      final original = item(poster: 'https://art.invalid/catalog');
      owner.capture(original);
      owner.adopt(original, rich);
      owner.capture(item(title: '  FIRST  '));
      expect(owner.current, same(rich));
      expect(owner.forSelection('channel:1', 'First'), same(rich));
    },
  );

  test(
    'selection matching permits changed punctuation for the same ID only',
    () {
      final owner = HomePlaybackArtwork()
        ..adopt(item(title: 'Original: Title'), rich);
      expect(owner.forSelection('channel:1', 'Original - Title'), same(rich));
      expect(owner.forSelection('channel:2', 'Original: Title'), isNull);
      expect(owner.forSelection(null, 'Original: Title'), isNull);
      expect(owner.forSelection('CHANNEL:1', 'Original: Title'), isNull);
    },
  );

  test(
    'ID-less matching normalizes surrounding space and case but not punctuation',
    () {
      final owner = HomePlaybackArtwork()
        ..adopt(item(id: '', title: '  First Title  '), rich);
      expect(owner.forSelection(null, 'first title'), same(rich));
      expect(owner.forSelection('', ' FIRST TITLE '), same(rich));
      expect(owner.forSelection(null, 'First-Title'), isNull);
      expect(owner.forSelection('channel:1', 'First Title'), isNull);
    },
  );

  test(
    'capturing an empty different title clears both retained artwork and identity',
    () {
      final owner = HomePlaybackArtwork()..adopt(item(), rich);
      owner.capture(item(id: 'channel:2', title: 'Second'));
      expect(owner.current, isNull);
      expect(owner.forSelection('channel:1', 'First'), isNull);
      owner.capture(item(poster: 'https://art.invalid/new'));
      expect(owner.current!.posterUrl, 'https://art.invalid/new');
      expect(owner.current, isNot(same(rich)));
    },
  );

  test('a different capture key replaces prior art even when IDs match', () {
    final owner = HomePlaybackArtwork()..adopt(item(), rich);
    owner.capture(
      item(title: 'Changed title', poster: 'https://art.invalid/new'),
    );
    final replacement = owner.current;
    expect(replacement!.posterUrl, 'https://art.invalid/new');
    expect(replacement.certificate, isNull);
    expect(owner.forSelection('channel:1', 'First'), same(replacement));
  });

  test(
    'an explicitly adopted empty detail object retains its existing precedence',
    () {
      const empty = PlayLoaderArt();
      final owner = HomePlaybackArtwork()..adopt(item(), empty);
      owner.capture(item(poster: 'https://art.invalid/catalog'));
      expect(owner.current, same(empty));
      expect(owner.forSelection('channel:1', 'First'), same(empty));
    },
  );

  test(
    'retention belongs to each view and explicit adoption replaces its title',
    () {
      final first = HomePlaybackArtwork()..adopt(item(), rich);
      final second = HomePlaybackArtwork();
      expect(second.current, isNull);
      const replacement = PlayLoaderArt(
        posterUrl: 'https://art.invalid/second',
      );
      first.adopt(item(id: 'channel:2', title: 'Second'), replacement);
      expect(first.current, same(replacement));
      expect(first.forSelection('channel:1', 'First'), isNull);
      expect(second.forSelection('channel:2', 'Second'), isNull);
    },
  );

  test('separator-containing IDs keep the legacy stored-key fallback', () {
    final owner = HomePlaybackArtwork()
      ..adopt(item(id: 'channel|suffix'), rich);
    expect(owner.forSelection('channel|suffix', 'FIRST'), same(rich));
    expect(owner.forSelection('channel|suffix', 'Different'), isNull);
    expect(owner.forSelection('channel', 'Different'), same(rich));
  });
}

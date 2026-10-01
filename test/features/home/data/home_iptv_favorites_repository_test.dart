import 'package:debrify/features/home/data/home_iptv_favorites_repository.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'preserves stored order, live-only mapping, exact strings and headers',
    () async {
      final headers = <Object, Object?>{
        'Referer': 'https://example.test/',
        'X-Number': 7,
        8: 'ignore',
        'null': null,
      };
      final saved = <String, Map<String, dynamic>>{
        'url:b': {
          'name': '',
          'logoUrl': '',
          'group': ' spaced ',
          'duration': 120,
          'contentType': 'vod',
          'channelNumber': 44,
          'httpHeaders': headers,
        },
        'url:a': {'logoUrl': 'logo', 'group': null},
      };
      var reads = 0;
      final repository = HomeIptvFavoritesRepository(
        favorites: () async {
          reads++;
          return saved;
        },
        headers: IptvFavoritesStorage.iptvFavoriteHeaders,
      );
      expect(reads, 0);
      final result = (await repository.read(isCurrent: () => true))!;
      expect(reads, 1);
      expect(result.map((c) => c.url), ['url:b', 'url:a']);
      expect(result.first.name, '');
      expect(result.first.logoUrl, '');
      expect(result.first.group, ' spaced ');
      expect(result.first.duration, -1);
      expect(result.first.contentType, isNull);
      expect(result.first.channelNumber, isNull);
      expect(result.first.isLive, isTrue);
      expect(result.first.attributes, isEmpty);
      expect(result.first.httpHeaders, {
        'Referer': 'https://example.test/',
        'X-Number': '7',
      });
      expect(result.last.name, 'Unknown Channel');
      expect(result.last.logoUrl, 'logo');
      expect(result.last.group, isNull);
      expect(result.last.httpHeaders, isEmpty);
      headers.clear();
      saved.clear();
      expect(result.first.httpHeaders.length, 2);
      expect(result.clear, throwsUnsupportedError);
      expect(result.first.httpHeaders.clear, throwsUnsupportedError);
      expect(result.first.attributes.clear, throwsUnsupportedError);
    },
  );

  test('empty storage remains empty and skips header mapping', () async {
    final repository = HomeIptvFavoritesRepository(
      favorites: () async => {},
      headers: (_) => throw StateError('unexpected'),
    );
    expect(await repository.read(isCurrent: () => true), isEmpty);
  });

  test(
    'malformed fields preserve failure instead of silently changing metadata',
    () async {
      final repository = HomeIptvFavoritesRepository(
        favorites: () async => {
          'url': {'name': 12},
        },
        headers: IptvFavoritesStorage.iptvFavoriteHeaders,
      );
      await expectLater(
        repository.read(isCurrent: () => true),
        throwsA(isA<TypeError>()),
      );
    },
  );

  for (final before in [true, false]) {
    test(
      'retirement ${before ? 'before' : 'after'} read prevents mapping',
      () async {
        var current = !before;
        var reads = 0;
        final repository = HomeIptvFavoritesRepository(
          favorites: () async {
            reads++;
            current = false;
            return {
              'url': {'name': 'One'},
            };
          },
          headers: (_) => throw StateError('retired mapping'),
        );
        expect(await repository.read(isCurrent: () => current), isNull);
        expect(reads, before ? 0 : 1);
      },
    );
  }
}

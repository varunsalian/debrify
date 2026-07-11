import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/stremio_addon.dart';

void main() {
  group('StremioMeta.trailerYtId parsing', () {
    test('prefers trailerStreams[].ytId', () {
      final meta = StremioMeta.fromJson({
        'id': 'tt1234567',
        'type': 'movie',
        'name': 'Example',
        'trailerStreams': [
          {'title': 'Trailer', 'ytId': 'ABC123'},
        ],
        'trailers': [
          {'source': 'SHOULD_NOT_WIN', 'type': 'Trailer'},
        ],
      });
      expect(meta.trailerYtId, 'ABC123');
    });

    test('falls back to trailers[].source, preferring type=="Trailer"', () {
      final meta = StremioMeta.fromJson({
        'id': 'tt1',
        'type': 'series',
        'name': 'Example',
        'trailers': [
          {'source': 'CLIP1', 'type': 'Clip'},
          {'source': 'TRAILER1', 'type': 'Trailer'},
        ],
      });
      expect(meta.trailerYtId, 'TRAILER1');
    });

    test('falls back to first source when no typed Trailer', () {
      final meta = StremioMeta.fromJson({
        'id': 'tt1',
        'type': 'movie',
        'name': 'Example',
        'trailers': [
          {'source': 'FIRST'},
          {'source': 'SECOND'},
        ],
      });
      expect(meta.trailerYtId, 'FIRST');
    });

    test('is null when no trailer fields', () {
      final meta = StremioMeta.fromJson({
        'id': 'tt1',
        'type': 'movie',
        'name': 'Example',
      });
      expect(meta.trailerYtId, isNull);
    });

    test('survives an empty ytId and skips to a valid one', () {
      final meta = StremioMeta.fromJson({
        'id': 'tt1',
        'type': 'movie',
        'name': 'Example',
        'trailerStreams': [
          {'title': 'a', 'ytId': ''},
          {'title': 'b', 'ytId': 'GOOD'},
        ],
      });
      expect(meta.trailerYtId, 'GOOD');
    });

    test('round-trips through toJson/fromJson', () {
      final meta = StremioMeta.fromJson({
        'id': 'tt1',
        'type': 'movie',
        'name': 'Example',
        'trailerStreams': [
          {'ytId': 'ROUNDTRIP'},
        ],
      });
      final restored = StremioMeta.fromJson(meta.toJson());
      expect(restored.trailerYtId, 'ROUNDTRIP');
    });
  });
}

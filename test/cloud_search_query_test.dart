import 'package:debrify/services/cloud/cloud_search_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (title, query, matches) in <(String?, String, bool)>[
    (null, '', true),
    (null, 'anything', true),
    ('', '', true),
    ('', 'anything', true),
    ('The Matrix', 'prematrixed', true),
    ('The Matrix', 'PREMATRIXED', true),
    ('THE MATRIX', 'matrix', true),
    ('The Matrix', 'unrelated', false),
    ('The Matrix', 'the', false),
    ('The Matrix', '', false),
    ('The Matrix', '   ', false),
    ('The Matrix Reloaded', 'reloaded', true),
    ('The Matrix Reloaded', 'matrix', true),
    ('the a an', 'theatre', true),
    ('the a an', 'banana', true),
    ('the a an', 'zzz', false),
    ('the a an', '', false),
    ('X', 'extra', true),
    ('X', 'other', false),
    ('X', '', false),
    ('X Matrix', 'extra', false),
    ('1917', 'film1917release', true),
    ('1917', '191', false),
    ('2', '2026', true),
    ('!!!', 'unrelated', true),
    ('!!!', '', true),
    ('東京', 'unrelated', true),
    ('東京', '', true),
    ('東京 Matrix', '東京', false),
    ('東京 Matrix', 'prematrixed', true),
    ('  ', '', true),
    ('Spider-Man', 'human', true),
  ]) {
    test('title=$title query="$query" matches=$matches', () {
      expect(queryMatchesInitialTitle(query, title), matches);
    });
  }
}

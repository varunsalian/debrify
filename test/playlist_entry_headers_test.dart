import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copied launch playlist retains effective headers for rollback', () {
    final launch =
        [
              const PlaylistEntry(
                url: 'https://original.test/a',
                title: 'Episode 1',
              ),
              const PlaylistEntry(
                url: 'https://original.test/b',
                title: 'Episode 2',
                httpHeaders: {'Authorization': 'episode-2'},
              ),
              const PlaylistEntry(
                url: 'https://public.test/c',
                title: 'Episode 3',
                httpHeaders: {},
              ),
            ]
            .map(
              (entry) => entry.withDefaultHttpHeaders({
                'Authorization': 'launch-secret',
              }),
            )
            .toList();
    final snapshot = List<PlaylistEntry>.of(launch);
    expect(identical(snapshot, launch), isFalse);
    expect(snapshot[0].httpHeaders, {'Authorization': 'launch-secret'});
    expect(snapshot[1].httpHeaders, {'Authorization': 'episode-2'});
    expect(snapshot[2].httpHeaders, isEmpty);
    expect(
      snapshot[0].copyWithTitle('Updated title').httpHeaders,
      snapshot[0].httpHeaders,
    );
    const replacement = PlaylistEntry(
      url: 'https://other.test/video',
      title: 'Other source',
    );
    expect(replacement.httpHeaders, isNull);
  });
}

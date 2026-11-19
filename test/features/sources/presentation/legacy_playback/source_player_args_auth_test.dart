import 'package:debrify/features/sources/presentation/legacy_playback/source_player_args.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a sign-in header keeps playback in Debrify', () {
    // External apps receive only the URL, so a WebDAV Basic sign-in would
    // fail there with 401; Debrify plays it (and explains why) instead.
    for (final header in ['Authorization', 'authorization']) {
      final args = SourcePlayerArgs.playerArgsForTesting(
        null,
        httpHeaders: {header: 'Basic Zm9vOmJhcg==', 'Accept': '*/*'},
      );
      expect(args.disableExternalPlayer, isTrue, reason: header);
    }
    final open = SourcePlayerArgs.playerArgsForTesting(
      null,
      httpHeaders: const {'Accept': '*/*', 'User-Agent': 'x'},
    );
    expect(open.disableExternalPlayer, isFalse);
  });
}

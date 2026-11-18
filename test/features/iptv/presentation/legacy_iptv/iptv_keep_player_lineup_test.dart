// A Sports match launches the player with its own channels. Both players ask
// for a page of the playing channel's category right after launch and adopt
// it; the wrapper declines exactly that request so the lineup stays, and
// passes every other browse request through untouched.
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final seen = <String?>[];
  Future<Map<String, dynamic>?> browse(Map<String, dynamic> request) async {
    seen.add(request['action'] as String?);
    return {'channels': const <Object>[], 'action': request['action']};
  }

  setUp(seen.clear);

  test('a category page is declined, so the launch list stays', () async {
    final keep = keepPlayerLineup(browse);
    expect(await keep({'action': 'zapPage', 'category': 'Sports'}), isNull);
    expect(seen, isEmpty);
  });

  test('browsing the guide and number jumps still reach the source', () async {
    final keep = keepPlayerLineup(browse);
    expect((await keep({'action': 'browse'}))?['action'], 'browse');
    expect(
      (await keep({'action': 'channelNumber', 'channelNumber': 7}))?['action'],
      'channelNumber',
    );
    expect(seen, ['browse', 'channelNumber']);
  });
}

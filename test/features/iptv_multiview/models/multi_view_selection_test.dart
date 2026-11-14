import 'package:debrify/features/iptv_multiview/models/multi_view_selection.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final a = IptvChannel(name: 'A', url: 'https://iptv.test/a');
  final b = IptvChannel(name: 'B', url: 'https://iptv.test/b');

  test('the channel with sound is the one the list returns to', () {
    expect(const MultiViewSelection().audioChannel, isNull);
    expect(MultiViewSelection(channels: [a, b]).audioChannel, same(a));
    expect(
      MultiViewSelection(channels: [a, b], audioIndex: 1).audioChannel,
      same(b),
    );
    // A tile removed after the sound moved must not point past the end.
    expect(
      MultiViewSelection(channels: [a], audioIndex: 1).audioChannel,
      same(a),
    );
  });
}

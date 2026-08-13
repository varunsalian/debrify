import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/screens/iptv/xtream_series_detail.dart';

void main() {
  test('parses a saved Xtream series identity', () {
    expect(parseXtreamSeriesMetaId('xtream-series:playlist:with:colons:77'), (
      playlistId: 'playlist:with:colons',
      seriesId: '77',
    ));
  });

  test('rejects incomplete and unrelated identities', () {
    expect(parseXtreamSeriesMetaId('movie:77'), isNull);
    expect(parseXtreamSeriesMetaId('xtream-series::77'), isNull);
    expect(parseXtreamSeriesMetaId('xtream-series:playlist:'), isNull);
  });
}

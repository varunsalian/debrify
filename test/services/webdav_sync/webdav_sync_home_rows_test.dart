import 'package:debrify/services/home_row_refresh.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_ui_refresh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('committed batches refresh affected Home rows once', () {
    final received = <Set<HomeRowRefresh>>[];
    HomeRowRefreshSignal.addListener(received.add);
    addTearDown(() => HomeRowRefreshSignal.removeListener(received.add));
    WebDavSyncUiRefresh.dispatch({
      'debrify_tv_favorite_channels_v1',
      'tv/ch',
      'playlist_poster_overrides_v1',
      'playback_state_v1',
      'stremio_tv_favorite_channels_v1',
      'stremio_tv_rotation_minutes',
      'stremio_tv_series_rotation_minutes',
      'my_watchlist_v1',
      'resume',
      'iptv/watch',
    });
    expect(received, [HomeRowRefresh.values.toSet()]);
  });

  test('unrelated changes do not reload Home data', () {
    final received = <Set<HomeRowRefresh>>[];
    HomeRowRefreshSignal.addListener(received.add);
    addTearDown(() => HomeRowRefreshSignal.removeListener(received.add));
    WebDavSyncUiRefresh.dispatch({'default_provider', 'home_row_order_v1'});
    expect(received, isEmpty);
  });

  test('listeners can detach and fail without losing other refreshes', () {
    var calls = 0;
    void failing(Set<HomeRowRefresh> rows) {
      HomeRowRefreshSignal.removeListener(failing);
      throw StateError('disposed view');
    }

    void healthy(Set<HomeRowRefresh> rows) {
      calls++;
      expect(rows, {HomeRowRefresh.watchlist});
      expect(() => rows.clear(), throwsUnsupportedError);
    }

    HomeRowRefreshSignal.addListener(failing);
    HomeRowRefreshSignal.addListener(healthy);
    addTearDown(() => HomeRowRefreshSignal.removeListener(failing));
    addTearDown(() => HomeRowRefreshSignal.removeListener(healthy));
    WebDavSyncUiRefresh.dispatch({'my_watchlist_v1'});
    WebDavSyncUiRefresh.dispatch({'my_watchlist_v1'});
    expect(calls, 2);
    HomeRowRefreshSignal.removeListener(healthy);
    WebDavSyncUiRefresh.dispatch({'my_watchlist_v1'});
    expect(calls, 2);
  });
}

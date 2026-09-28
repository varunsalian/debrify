import 'package:debrify/features/home/application/home_refresh_queue.dart';
import 'package:debrify/features/home/models/home_row_refresh.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'coalesces without extending deadline and refreshes addons after rows',
    () {
      fakeAsync((async) {
        final calls = <String>[];
        var visible = true;
        var current = true;
        final queue = HomeRefreshQueue(
          isCurrent: () => current,
          isVisible: () => visible,
          refreshRow: (row) => calls.add(row.name),
          refreshAddons: () => calls.add('addons'),
        );
        queue.enqueue({HomeRowRefresh.watchlist, HomeRowRefresh.playback});
        async.elapse(const Duration(milliseconds: 50));
        queue.enqueue({HomeRowRefresh.watchlist, HomeRowRefresh.playlist});
        queue.addonsChanged();
        async.elapse(const Duration(milliseconds: 49));
        expect(calls, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(calls, [
          'watchlist',
          'playlist',
          'stremioTvFavorites',
          'addons',
        ]);
        calls.clear();
        visible = false;
        queue.enqueue({HomeRowRefresh.playback});
        async.elapse(const Duration(milliseconds: 100));
        expect(calls, ['playback']);
        calls.clear();
        queue.enqueue({HomeRowRefresh.watchlist});
        current = false;
        async.elapse(const Duration(milliseconds: 100));
        expect(calls, isEmpty);
        queue.dispose();
      });
    },
  );
  test('dispose cancels the pending batch', () {
    fakeAsync((async) {
      final queue = HomeRefreshQueue(
        isCurrent: () => true,
        isVisible: () => false,
        refreshRow: (_) => fail('disposed'),
        refreshAddons: () => fail('disposed'),
      );
      queue.addonsChanged();
      queue.dispose();
      async.elapse(const Duration(seconds: 1));
    });
  });
}

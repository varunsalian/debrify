import 'package:debrify/utils/iptv_player_paging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iptvPlayerZapPageOffset', () {
    test('centers a searched channel when there is room on both sides', () {
      expect(
        iptvPlayerZapPageOffset(total: 1000, limit: 200, anchorIndex: 500),
        400,
      );
    });

    test('clamps anchored pages at both catalog edges', () {
      expect(
        iptvPlayerZapPageOffset(total: 1000, limit: 200, anchorIndex: 4),
        0,
      );
      expect(
        iptvPlayerZapPageOffset(total: 1000, limit: 200, anchorIndex: 999),
        800,
      );
    });

    test('uses a full final page for reverse category transitions', () {
      expect(
        iptvPlayerZapPageOffset(total: 425, limit: 200, fromEnd: true),
        225,
      );
      expect(iptvPlayerZapPageOffset(total: 80, limit: 200, fromEnd: true), 0);
    });

    test('clamps explicit page requests and handles an empty catalog', () {
      expect(
        iptvPlayerZapPageOffset(total: 425, limit: 200, requestedOffset: 600),
        424,
      );
      expect(
        iptvPlayerZapPageOffset(total: 0, limit: 200, requestedOffset: 200),
        0,
      );
    });
  });

  group('iptvAdjacentZapCategory', () {
    const categories = ['News', 'Sports', 'Movies', 'Kids'];

    String? next(String? current, int delta, {int attempt = 1}) =>
        iptvAdjacentZapCategory(
          categories: categories,
          current: current,
          delta: delta,
          attempt: attempt,
        );

    test('steps to the neighbouring category in either direction', () {
      expect(next('Sports', 1), 'Movies');
      expect(next('Sports', -1), 'News');
    });

    test('wraps around both ends', () {
      expect(next('Kids', 1), 'News');
      expect(next('News', -1), 'Kids');
    });

    test('skips further ahead on later attempts, still wrapping', () {
      expect(next('Movies', 1, attempt: 2), 'News');
      expect(next('News', -1, attempt: 2), 'Movies');
    });

    test('gives up once every category has been tried', () {
      expect(next('News', 1, attempt: 4), 'News');
      expect(next('News', 1, attempt: 5), isNull);
      expect(next('News', 1, attempt: 0), isNull);
    });

    test('has nowhere to go without a current category', () {
      expect(next(null, 1), isNull);
      expect(
        iptvAdjacentZapCategory(
          categories: const [],
          current: 'News',
          delta: 1,
        ),
        isNull,
      );
    });

    test('ignores duplicates and blanks when counting neighbours', () {
      expect(
        iptvAdjacentZapCategory(
          categories: const ['News', '', 'Sports', 'News'],
          current: 'Sports',
          delta: 1,
        ),
        'News',
      );
    });

    test('treats an unknown category as sitting at the front', () {
      expect(next('Deleted Group', 1), 'Sports');
    });
  });

  group('iptvMergeZapWindow', () {
    test('appends a page that continues the window', () {
      final merged = iptvMergeZapWindow(
        window: const ['a', 'b'],
        windowOffset: 10,
        page: const ['c', 'd'],
        pageOffset: 12,
      );
      expect(merged!.offset, 10);
      expect(merged.channels, ['a', 'b', 'c', 'd']);
    });

    test('prepends a page that runs up to the window', () {
      final merged = iptvMergeZapWindow(
        window: const ['c', 'd'],
        windowOffset: 12,
        page: const ['a', 'b'],
        pageOffset: 10,
      );
      expect(merged!.offset, 10);
      expect(merged.channels, ['a', 'b', 'c', 'd']);
    });

    test('lets the fresher page win where the two overlap', () {
      final merged = iptvMergeZapWindow(
        window: const ['a', 'b', 'c'],
        windowOffset: 0,
        page: const ['B', 'C', 'd'],
        pageOffset: 1,
      );
      expect(merged!.offset, 0);
      expect(merged.channels, ['a', 'B', 'C', 'd']);
    });

    test('rejects a page separated from the window by a gap', () {
      expect(
        iptvMergeZapWindow(
          window: const ['a', 'b'],
          windowOffset: 0,
          page: const ['x'],
          pageOffset: 3,
        ),
        isNull,
      );
      expect(
        iptvMergeZapWindow(
          window: const ['a', 'b'],
          windowOffset: 10,
          page: const ['x'],
          pageOffset: 8,
        ),
        isNull,
      );
    });

    test('keeps a page that lands entirely inside the window', () {
      final merged = iptvMergeZapWindow(
        window: const ['a', 'b', 'c', 'd'],
        windowOffset: 0,
        page: const ['B'],
        pageOffset: 1,
      );
      expect(merged!.offset, 0);
      expect(merged.channels, ['a', 'B', 'c', 'd']);
    });

    test(
      'adopts the page when there is no window yet, and rejects nothing',
      () {
        final merged = iptvMergeZapWindow(
          window: const <String>[],
          windowOffset: 0,
          page: const ['a'],
          pageOffset: 7,
        );
        expect(merged!.offset, 7);
        expect(merged.channels, ['a']);
        expect(
          iptvMergeZapWindow(
            window: const ['a'],
            windowOffset: 0,
            page: const <String>[],
            pageOffset: 0,
          ),
          isNull,
        );
      },
    );
  });
}

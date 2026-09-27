import 'package:debrify/features/home/presentation/home_progress_publication.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HomeProgressPublication publication;
  late List<HomeProgressUpdate> published;
  late List<String> events;
  var visible = true;
  var generation = 1;
  Object? scope;

  HomeProgressUpdate update({bool first = false, int? owner}) => (
    rows: <CatalogSection>[],
    first: first,
    generation: owner ?? generation,
    scope: scope,
  );

  void resume() => publication.resume(
    isVisible: () => visible,
    isCurrent: (pending) =>
        pending.generation == generation && pending.scope == scope,
    publish: (pending) {
      expect(publication.hasPending, isFalse);
      expect(publication.isScheduled, isFalse);
      published.add(pending);
      events.add('publish');
    },
    onResumed: () {
      events.add('resume');
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => events.add('measure'),
      );
    },
  );

  Future<void> frame(WidgetTester tester) {
    // addPostFrameCallback deliberately does not request a frame. In the app,
    // route/layout changes supply it; this fixture supplies the same boundary.
    tester.binding.scheduleFrame();
    return tester.pump();
  }

  setUp(() {
    publication = HomeProgressPublication();
    published = [];
    events = [];
    visible = true;
    generation = 1;
    scope = Object();
  });
  tearDown(() => publication.dispose());

  for (final first in [true, false]) {
    testWidgets('coalesces frames and preserves initial first=$first', (
      tester,
    ) async {
      publication.defer(update(first: first));
      final latest = update(first: !first);
      publication.defer(latest);
      resume();
      resume();
      expect(publication.isScheduled, isTrue);
      expect(published, isEmpty);
      await frame(tester);
      expect(published.single.rows, same(latest.rows));
      expect(published.single.first, first);
      expect(events, ['publish', 'resume']);
      await frame(tester);
      expect(events, ['publish', 'resume', 'measure']);
    });
  }

  testWidgets('covered callback retains rows until a later visible frame', (
    tester,
  ) async {
    final pending = update(first: true);
    publication.defer(pending);
    resume();
    visible = false;
    await frame(tester);
    expect(publication.hasPending, isTrue);
    expect(publication.isScheduled, isFalse);
    expect(events, isEmpty);
    visible = true;
    resume();
    await frame(tester);
    expect(published.single, pending);
    expect(events, ['publish', 'resume']);
    await frame(tester);
  });

  for (final retirement in ['generation', 'scope']) {
    testWidgets('$retirement change discards pending rows and skips autofill', (
      tester,
    ) async {
      publication.defer(update());
      resume();
      if (retirement == 'generation') {
        generation++;
      } else {
        scope = Object();
      }
      await frame(tester);
      expect(publication.hasPending, isFalse);
      expect(publication.isScheduled, isFalse);
      expect(events, isEmpty);
      // Once the stale update is consumed, a normal return can measure again.
      resume();
      await frame(tester);
      expect(events, ['resume']);
      await frame(tester);
    });
  }

  testWidgets('clear preserves scheduled return and measures with no rows', (
    tester,
  ) async {
    publication.defer(update());
    resume();
    publication.clear();
    expect(publication.isScheduled, isTrue);
    expect(publication.hasPending, isFalse);
    await frame(tester);
    expect(published, isEmpty);
    expect(events, ['resume']);
    await frame(tester);
    expect(events, ['resume', 'measure']);
  });

  testWidgets(
    'timeout retirement retains accepted rows for the new generation',
    (tester) async {
      final pending = update(first: true);
      publication.defer(pending);
      publication.retireGeneration(99, 100);
      publication.retireGeneration(1, 2);
      generation = 2;
      resume();
      await frame(tester);
      expect(published.single.rows, same(pending.rows));
      expect(published.single.first, isTrue);
      expect(published.single.scope, same(pending.scope));
      expect(published.single.generation, 2);
      await frame(tester);
    },
  );

  testWidgets('new load can replace queued data before the scheduled frame', (
    tester,
  ) async {
    publication.defer(update());
    resume();
    generation++;
    publication.clear();
    final next = update(first: true);
    publication.defer(next);
    await frame(tester);
    expect(published, [next]);
    await frame(tester);
  });

  testWidgets('disposal cancels pending callbacks without reading view state', (
    tester,
  ) async {
    publication.defer(update());
    publication.resume(
      isVisible: () => throw StateError('disposed view'),
      isCurrent: (_) => throw StateError('disposed provider'),
      publish: (_) => fail('disposed publication'),
      onResumed: () => fail('disposed autofill'),
    );
    publication.dispose();
    publication.defer(update());
    resume();
    await frame(tester);
    expect(publication.hasPending, isFalse);
    expect(publication.isScheduled, isFalse);
    expect(events, isEmpty);
  });
}

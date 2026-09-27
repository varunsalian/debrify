import 'dart:async';
import 'package:debrify/features/home/application/home_layout_preference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HomeLayoutPreference operation;
  var active = true;
  var owner = true;
  var style = 'classic';
  late List<String> transitions;
  void mount(Future<String> Function() read) {
    operation = HomeLayoutPreference(
      initialStyle: 'classic',
      readSaved: read,
      isOwnerCurrent: () => owner,
    );
  }

  Future<void> load() => operation.load(
    isCurrent: () => active,
    currentStyle: () => style,
    transition: (value) {
      transitions.add(value);
      style = value;
    },
  );
  setUp(() {
    active = true;
    owner = true;
    style = 'classic';
    transitions = [];
  });

  test(
    'construction retains cached style without reading; equal styles do not transition',
    () async {
      var reads = 0;
      mount(() async {
        reads++;
        return 'classic';
      });
      expect(operation.initialStyle, 'classic');
      expect(reads, 0);
      await load();
      await load();
      expect(reads, 2);
      expect(transitions, isEmpty);
    },
  );
  test('compare against the live layout after the read completes', () async {
    final response = Completer<String>();
    mount(() => response.future);
    final pending = load();
    style = 'spotlight';
    response.complete('spotlight');
    await pending;
    expect(transitions, isEmpty);
  });
  test(
    'new refresh transitions once and late startup cannot undo it',
    () async {
      final startup = Completer<String>();
      var reads = 0;
      mount(() => ++reads == 1 ? startup.future : Future.value('spotlight'));
      final old = load();
      await load();
      startup.complete('mosaic');
      await old;
      expect(transitions, ['spotlight']);
      expect(style, 'spotlight');
    },
  );
  for (final reason in ['profile', 'view', 'dispose']) {
    test('$reason rejects a pending transition and subsequent reads', () async {
      final response = Completer<String>();
      var reads = 0;
      mount(() {
        reads++;
        return response.future;
      });
      final pending = load();
      switch (reason) {
        case 'profile':
          owner = false;
        case 'view':
          active = false;
        case 'dispose':
          operation.dispose();
      }
      response.complete('spotlight');
      await pending;
      await load();
      expect(reads, 1);
      expect(transitions, isEmpty);
    });
  }
  test('a rejected call does not cancel an already accepted read', () async {
    final response = Completer<String>();
    mount(() => response.future);
    final pending = load();
    active = false;
    await load();
    active = true;
    response.complete('spotlight');
    await pending;
    expect(transitions, ['spotlight']);
  });
  test(
    'storage errors propagate without changing the layout or retrying',
    () async {
      var reads = 0;
      mount(() async {
        reads++;
        throw StateError('storage');
      });
      await expectLater(load(), throwsStateError);
      expect(style, 'classic');
      expect(transitions, isEmpty);
      expect(reads, 1);
    },
  );
}

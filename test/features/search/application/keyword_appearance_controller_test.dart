import 'dart:async';
import 'package:debrify/features/search/application/keyword_appearance_controller.dart';
import 'package:debrify/features/search/application/keyword_appearance_dependencies.dart';
import 'package:debrify/features/search/models/search_session.dart';
import 'package:debrify/models/source_appearance.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late SearchSession key;
  late KeywordAppearanceController controller;
  late ProviderSubscription<SourceAppearance> values;
  void mount(SourceAppearanceReader read) {
    key = SearchSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container = ProviderContainer.test(
      overrides: [
        keywordAppearanceReaderProvider.overrideWith((ref, session) => read),
      ],
    );
    values = container.listen(keywordAppearanceProvider(key), (_, _) {});
    controller = container.read(keywordAppearanceProvider(key).notifier);
  }

  Future<void> load({bool Function()? current, void Function()? accepted}) =>
      controller.load(
        isCurrent: current ?? () => true,
        onAccepted: accepted ?? () {},
      );

  test(
    'explicit reads publish complete values before repaint; failures retain accepted state',
    () async {
      var reads = 0;
      var failure = false;
      mount(() async {
        reads++;
        if (failure) throw StateError('storage');
        return (text: true, logos: false);
      });
      expect(reads, 0);
      expect(values.read(), initialSourceAppearance);
      var repaints = 0;
      for (var i = 0; i < 2; i++) {
        await load(
          accepted: () {
            expect(values.read(), (text: true, logos: false));
            repaints++;
          },
        );
      }
      expect(repaints, 2);
      failure = true;
      await expectLater(load(), throwsStateError);
      expect(values.read(), (text: true, logos: false));
      expect(reads, 3);
    },
  );

  test('new refresh wins over late startup', () async {
    final startup = Completer<SourceAppearance>();
    var reads = 0;
    mount(
      () => ++reads == 1
          ? startup.future
          : Future.value((text: false, logos: true)),
    );
    final first = load(accepted: () => fail('stale repaint'));
    await load();
    startup.complete((text: true, logos: false));
    await first;
    expect(values.read(), (text: false, logos: true));
  });

  for (final reason in ['profile', 'view', 'dispose', 'recompute']) {
    test('$reason retires pending appearance without repaint', () async {
      final response = Completer<SourceAppearance>();
      mount(() => response.future);
      var active = true;
      final pending = load(
        current: () => active,
        accepted: () => fail('retired repaint'),
      );
      switch (reason) {
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'view':
          active = false;
        case 'dispose':
          container.dispose();
        case 'recompute':
          container.invalidate(keywordAppearanceProvider(key));
          container.read(keywordAppearanceProvider(key));
      }
      response.complete((text: true, logos: true));
      await pending;
      if (reason != 'dispose') expect(values.read(), initialSourceAppearance);
    });
  }

  test('retired request does not start another storage read', () async {
    var reads = 0;
    mount(() async {
      reads++;
      return (text: true, logos: true);
    });
    await load(current: () => false);
    ProfileSessionMemory.clearAll();
    await load();
    expect(reads, 0);
  });

  test('profile retirement during publication prevents repaint', () async {
    mount(() async => (text: true, logos: true));
    container.listen(
      keywordAppearanceProvider(key),
      (_, _) => ProfileSessionMemory.clearAll(),
    );
    await load(accepted: () => fail('retired repaint'));
  });
}

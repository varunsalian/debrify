import 'dart:async';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/merged_detail_fixture.dart';

void main() {
  testWidgets('in-flight engine target stays stashed until loader settles', (
    t,
  ) async {
    await mergedDetailCase(t, (f) async {
      f.heldResume = Completer<MergedResume>();
      await f.mount(t);
      expect(f.model.primaryLabel, 'Resume');
      expect(f.model.primaryBusy, true);
      f.next((season: 2, episode: 8, started: true));
      expect(f.model.primaryLabel, 'Resume');
      expect(f.model.primaryBusy, true);
      f.heldResume!.complete((started: false, season: null, episode: null));
      await f.until(t, () => !f.model.primaryBusy);
      expect(f.model.primaryLabel, 'Resume · S2E8');
      f.model.onPrimary();
      await f.until(t, () => f.calls.contains('resumePlay'));
      expect(f.promises, [(started: true, season: 2, episode: 8)]);
    });
  });
  testWidgets(
    'started loader discards a stashed and later non-mutation engine target',
    (t) async {
      await mergedDetailCase(t, (f) async {
        f.heldResume = Completer<MergedResume>();
        await f.mount(t);
        f.next((season: 2, episode: 8, started: true));
        f.heldResume!.complete((started: true, season: 1, episode: 7));
        await f.until(t, () => !f.model.primaryBusy);
        expect(f.model.primaryLabel, 'Resume · S1E7');
        f.next((season: 3, episode: 9, started: true));
        expect(f.model.primaryLabel, 'Resume · S1E7');
        f.model.onPrimary();
        await f.until(t, () => f.calls.contains('resumePlay'));
        expect(f.promises, [null]);
      });
    },
  );
  testWidgets(
    'mutation writes through in-flight loader and protects the merged promise',
    (t) async {
      await mergedDetailCase(t, (f) async {
        f.heldResume = Completer<MergedResume>();
        await f.mount(t);
        f.next((season: 4, episode: 5, started: true), mutation: true);
        expect(f.model.primaryLabel, 'Resume · S4E5');
        f.heldResume!.complete((started: true, season: 1, episode: 2));
        await f.until(t, () => !f.model.primaryBusy);
        expect(f.model.primaryLabel, 'Resume · S4E5');
        f.model.onPrimary();
        await f.until(t, () => f.calls.contains('resumePlay'));
        expect(f.promises, [(started: true, season: 4, episode: 5)]);
      });
    },
  );
  testWidgets('failed loader applies its last stashed target and clears busy', (
    t,
  ) async {
    await mergedDetailCase(t, (f) async {
      f.heldResume = Completer<MergedResume>();
      await f.mount(t);
      f.next((season: 2, episode: 6, started: true));
      f.heldResume!.completeError(StateError('fixture failure'));
      await f.until(t, () => !f.model.primaryBusy);
      expect(f.model.primaryLabel, 'Resume · S2E6');
    });
  });
  testWidgets('12-second timeout settles a stash with fake time', (t) async {
    await mergedDetailCase(t, (f) async {
      f.heldResume = Completer<MergedResume>();
      await f.mount(t);
      f.next((season: 5, episode: 3, started: true));
      await t.pump(const Duration(seconds: 10));
      expect(f.model.primaryBusy, true);
      await t.pump(const Duration(seconds: 2));
      await t.pump();
      expect(f.model.primaryBusy, false);
      expect(f.model.primaryLabel, 'Resume · S5E3');
      f.heldResume!.complete((started: true, season: 1, episode: 1));
      await t.pump();
      expect(f.model.primaryLabel, 'Resume · S5E3');
    });
  });
  testWidgets(
    'unstarted coordinate is Start Watching and never a merged promise',
    (t) async {
      await mergedDetailCase(t, (f) async {
        await f.mount(t);
        f.next((season: 1, episode: 1, started: false), mutation: true);
        expect(f.model.primaryLabel, 'Start Watching');
        f.model.onPrimary();
        await f.until(t, () => f.calls.contains('resumePlay'));
        expect(f.promises, [null]);
      });
    },
  );
  testWidgets('started engine upgrades an unstarted settled loader', (t) async {
    await mergedDetailCase(t, (f) async {
      await f.mount(t);
      expect(f.model.primaryLabel, 'Start Watching');
      f.next((season: 2, episode: 3, started: true));
      expect(f.model.primaryLabel, 'Resume · S2E3');
      f.next((season: 2, episode: 4, started: true), mutation: true);
      expect(f.model.primaryLabel, 'Resume · S2E4');
    });
  });
  testWidgets(
    'movie ignores episode engine emissions and forwards a null promise',
    (t) async {
      await mergedDetailCase(t, (f) async {
        f.item = const StremioMeta(
          id: 'merged-movie',
          type: 'movie',
          name: 'Original Movie',
        );
        await f.mount(t);
        f.next((season: 3, episode: 4, started: true), mutation: true);
        expect(f.model.primaryLabel, 'Play');
        f.model.onPrimary();
        await f.until(t, () => f.calls.contains('resumePlay'));
        expect(f.promises, [null]);
      });
    },
  );
}

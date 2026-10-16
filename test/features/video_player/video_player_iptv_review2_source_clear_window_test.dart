import 'dart:async';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';
import 'support/vp_fixture_actions.dart';

/// Hold the screen's pause await after the delegated player emitted playing.
/// Internal fake-player awaits do not represent this capture boundary.
class SwitchPauseDelivery {
  bool armed = true;
  int skip = 1;
  final pending = <void Function()>[];
  Result run<Result>(Result Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      registerUnaryCallback:
          <R, T>(self, parent, zone, R Function(T) callback) {
            final stack = StackTrace.current.toString();
            final first = stack
                .split('\n')
                .where((s) => s.contains('package:debrify/'))
                .firstOrNull;
            final selected =
                (first?.contains('switchToIptvChannel') ?? false) &&
                !stack.contains('FakePlayer.operation') &&
                !stack.contains('FakePlayer.pause');
            return parent.registerUnaryCallback(zone, (T value) {
              if (armed && selected && value == null) {
                if (skip > 0) {
                  skip--;
                } else {
                  armed = false;
                  pending.add(
                    VpFixtureActions.heldCallback(
                      'screen pause delivery',
                      () => zone.runUnary(callback, value),
                    ),
                  );
                  return null as R;
                }
              }
              return callback(value);
            });
          },
    ),
  );
  void release() {
    armed = false;
    final callbacks = List<void Function()>.of(pending);
    pending.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}

void main() {
  testWidgets(
    'P15 review2 clearing absent sources does not publish an extra pre-open frame',
    (t) async {
      final d = IptvWorkflowDriver(t, native: true);
      await d.initialize();
      final live = await d.installAddon('source-clear-frame');
      final addon = d.response!;
      final plain = iptvChannel(1);
      final incoming = iptvChannel(
        2,
        url: 'https://p15-clear-panel.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      final channels = [live, plain, incoming];
      final stop = DateTime.now().add(const Duration(seconds: 7));
      d.response = (r) => r.url.host == 'p15-clear-panel.test'
          ? iptvPanelReply(r, stop: stop)
          : addon(r);
      final pause = SwitchPauseDelivery();
      final epg = IptvAwaitDelivery(
        'loadIptvZapBannerEpg',
        (v) => v is EpgNowNext,
      );
      final setup = Completer<void>();
      var entered = false;
      try {
        await d.mount(channels, initialUrl: 'https://probe.test/first.ts');
        await d.f.until(
          t,
          () => playerControls(t).onShowStremioSources != null,
        );
        expect(playerControls(t).onShowStremioSources, isNotNull);
        await d.pick(channels, 1);
        expect(playerControls(t).onShowStremioSources, isNull);
        await d.f.finish(
          t,
          IptvEpgService.instance.nowNextWithCatchupMetadata(incoming.url),
        );
        await d.observe(() => t.tapAt(const Offset(600, 300)));
        await d.advance(const Duration(milliseconds: 400));
        await pause.run(() => epg.run(() => d.zap(1)));
        await d.f.until(t, () => pause.pending.isNotEmpty);
        await d.f.until(t, () => epg.pending.isNotEmpty);
        await d.settle();
        expect(playerControls(t).onLiveEdgeAction, isNotNull);
        final wait =
            stop.difference(DateTime.now()) + const Duration(milliseconds: 100);
        if (wait.isNegative) {
          throw StateError('Original source-clear window already expired');
        }
        await t.runAsync(() => Future<void>.delayed(wait));
        final native = d.player.platform as FakeNativePlayer;
        bool hold(String name, Object? value) =>
            name == 'setProperty' &&
            value is (String, String) &&
            value.$1 == 'sub-visibility' &&
            !entered;
        native.heldOperation = hold;
        native.beforeOperation = (name, value) async {
          if (hold(name, value)) {
            entered = true;
            await setup.future;
          }
        };
        pause.release();
        await d.f.until(t, () => entered);
        await t.pump();
        // The held metadata result and completed pause cannot publish again.
        // A no-op source clear must not independently rebuild the time-sensitive
        // live-edge input before the new media's first event.
        expect(playerControls(t).onLiveEdgeAction, isNotNull);
        setup.complete();
        epg.release();
        await d.f.until(t, () => d.opened.length == 3);
        await d.settle();
        expect(d.playingUrl, incoming.url);
        expect(d.errors, isEmpty);
      } finally {
        pause.release();
        epg.release();
        if (!setup.isCompleted) setup.complete();
        await d.close();
      }
    },
  );
}

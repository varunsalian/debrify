import 'dart:async';
import 'dart:io' as io;
import 'support/iptv_workflow_driver.dart';

/// Preserve the actual predicate and captured argument, while modelling a UI
/// thread suspension before its caller performs the next wall-clock read.
class ProgrammeReadPause extends EpgProgramme {
  ProgrammeReadPause(this.value, {required this.armed, required this.onPause})
    : super(
        title: value.title,
        description: value.description,
        start: value.start,
        stop: value.stop,
        hasArchive: value.hasArchive,
        rawStart: value.rawStart,
        replayStart: value.replayStart,
      );
  final EpgProgramme value;
  final VoidCallback onPause;
  bool armed;
  @override
  bool airsAt(DateTime time) {
    final result = value.airsAt(time);
    if (armed) {
      armed = false;
      final remaining = stop.difference(DateTime.now());
      if (!result || remaining.isNegative) {
        throw StateError(
          'Original clock-case admission missed its real window',
        );
      }
      onPause();
      io.sleep(remaining + const Duration(milliseconds: 100));
    }
    return result;
  }
}

void main() {
  for (final mode in ['getter', 'action', 'active']) {
    final action = mode == 'action';
    final active = mode == 'active';
    testWidgets(
      'P15 review2 programme expiry between availability reads mode=$mode',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = iptvChannel(
          0,
          url: 'https://p15-expiry-reads-$mode.test/live/u/p/123.ts',
          attributes: {'tv_archive': '1'},
        );
        final stop = DateTime.now().add(const Duration(seconds: 4));
        Response? listing;
        d.response = (r) {
          if (r.url.path == '/player_api.php') {
            return listing ??= iptvPanelReply(r, stop: stop);
          }
          return iptvPanelReply(r, stop: stop);
        };
        ProgrammeReadPause? programme;
        final firstFrameActions = <bool>[];
        final boundary = ZoneSpecification(
          registerUnaryCallback:
              <R, T>(self, parent, zone, R Function(T) callback) {
                final frame = StackTrace.current
                    .toString()
                    .split('\n')
                    .where((line) => line.contains('package:debrify/'))
                    .firstOrNull;
                final selected =
                    frame?.contains('loadIptvZapBannerEpg') ?? false;
                return parent.registerUnaryCallback(zone, (T value) {
                  if (selected &&
                      value is EpgNowNext &&
                      value.now != null &&
                      programme == null) {
                    programme = ProgrammeReadPause(
                      value.now!,
                      armed: !action && !active,
                      onPause: () {
                        if (!action && !active) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            firstFrameActions.add(
                              playerControls(t).onLiveEdgeAction != null,
                            );
                          });
                        }
                      },
                    );
                    return callback(
                      EpgNowNext(now: programme, next: value.next) as T,
                    );
                  }
                  return callback(value);
                });
              },
        );
        try {
          await runZoned(() => d.mount([live]), zoneSpecification: boundary);
          expect(programme, isNotNull);
          if (active) {
            final start = playerControls(t).onLiveEdgeAction;
            expect(start, isNotNull);
            d.observe(start!);
            await d.f.until(t, () => playerControls(t).liveEdgeActionActive);
            live.attributes['tv_archive'] = '0';
            d.player.emit('duration', const Duration(minutes: 21));
            await d.settle();
            final backToLive = playerControls(t).onLiveEdgeAction;
            expect(backToLive, isNotNull);
            d.observe(backToLive!);
            await d.f.until(t, () => d.playingUrl == live.url);
            expect(playerControls(t).liveEdgeActionActive, false);
          } else if (action) {
            final callback = playerControls(t).onLiveEdgeAction;
            expect(callback, isNotNull);
            programme!.armed = true;
            d.observe(callback!);
            await d.settle();
            expect(programme!.armed, false);
            expect(d.opened, [live.url]);
            expect(playerControls(t).liveEdgeActionLoading, false);
            expect(playerControls(t).liveEdgeActionActive, false);
          } else {
            expect(firstFrameActions, [false]);
            expect(playerControls(t).onLiveEdgeAction, isNull);
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}

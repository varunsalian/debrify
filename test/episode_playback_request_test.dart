import 'dart:async';

import 'package:debrify/utils/episode_playback_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pause arriving during last timeout interval prevents fallback',
    () async {
      var paused = false;
      var waits = 0;
      expect(
        await waitForEpisodePlayback(
          isCurrent: () => true,
          isReady: () => waits == 2,
          isPaused: () => paused,
          attempts: 1,
          wait: () async {
            waits++;
            paused = true;
          },
        ),
        isTrue,
      );
      expect(waits, 2);
    },
  );

  test('intentional pause does not exhaust readiness timeout', () async {
    var paused = true;
    var waits = 0;
    final ready = await waitForEpisodePlayback(
      isCurrent: () => true,
      isReady: () => waits >= 5,
      isPaused: () => paused,
      attempts: 2,
      wait: () async {
        waits++;
        if (waits == 4) paused = false;
      },
    );
    expect(ready, isTrue);
    expect(waits, 5);
  });

  test('cancelled paused readiness does not keep waiting', () async {
    var current = true;
    expect(
      await waitForEpisodePlayback(
        isCurrent: () => current,
        isReady: () => false,
        isPaused: () => true,
        wait: () async {
          current = false;
        },
      ),
      isFalse,
    );
  });

  test(
    'readiness timeout fails instead of committing an unplayable URL',
    () async {
      var waits = 0;
      expect(
        await waitForEpisodePlayback(
          isCurrent: () => true,
          isReady: () => false,
          attempts: 3,
          wait: () async {
            waits++;
          },
        ),
        isFalse,
      );
      expect(waits, 3);
    },
  );

  test('readiness requires current request and playback evidence', () async {
    var ready = false;
    expect(
      await waitForEpisodePlayback(
        isCurrent: () => true,
        isReady: () => ready,
        wait: () async {
          ready = true;
        },
      ),
      isTrue,
    );
    expect(
      await waitForEpisodePlayback(isCurrent: () => false, isReady: () => true),
      isFalse,
    );
  });

  test(
    'cancellation during tracking preparation restores same-pack identity',
    () async {
      var index = 0;
      var trackingIndex = 0;
      var active = true;
      final request = EpisodePlaybackRequest(
        currentIdentity: () => 1,
        isActive: () => active,
      );
      final tracking = Completer<void>();
      final pending = request.attempt(() async {
        var loaded = false;
        try {
          index = 7;
          trackingIndex = index;
          await tracking.future;
          if (!request.isCurrent) return false;
          loaded = await request.commit(() async {});
          return loaded;
        } finally {
          if (!loaded &&
              request.restorePlaylist(() {
                index = 0;
              })) {
            trackingIndex = index;
          }
        }
      });
      active = false;
      tracking.complete();
      expect(await pending, EpisodePlaybackOutcome.cancelled);
      expect(index, 0);
      expect(trackingIndex, 0);
    },
  );

  test(
    'cancellation while waiting for readiness retains opened media identity',
    () async {
      var identity = 1;
      var active = true;
      var playlist = 'outgoing';
      var media = 'outgoing';
      final ready = Completer<void>();
      final opened = Completer<void>();
      final request = EpisodePlaybackRequest(
        currentIdentity: () => identity,
        isActive: () => active,
      );
      final pending = request.attempt(() async {
        request.replacePlaylist(() {
          playlist = 'incoming';
          identity++;
        });
        await request.commit(() async {
          media = 'incoming';
        });
        opened.complete();
        await ready.future;
        if (!request.isCurrent) {
          request.restorePlaylist(() {
            playlist = 'outgoing';
            identity++;
          });
          return false;
        }
        return true;
      });
      await opened.future;
      active = false;
      ready.complete();
      expect(await pending, EpisodePlaybackOutcome.cancelled);
      expect(playlist, media);
      expect(playlist, 'incoming');
      expect(identity, 2);
    },
  );

  test('failed native open cannot authorize metadata-only rollback', () async {
    var identity = 1;
    var playlist = 'outgoing';
    var media = 'outgoing';
    final request = EpisodePlaybackRequest(
      currentIdentity: () => identity,
      isActive: () => true,
    );
    final outcome = await request.attempt(() async {
      request.replacePlaylist(() {
        playlist = 'incoming';
        identity++;
      });
      return request.commit(() async {
        media = 'incoming';
        throw StateError('native open failed after replacing media');
      });
    });
    expect(outcome, EpisodePlaybackOutcome.unavailable);
    expect(
      request.restorePlaylist(() {
        playlist = 'outgoing';
        identity++;
      }),
      isFalse,
    );
    expect(playlist, media);

    // A later candidate can still roll back its own preparation before open.
    request.replacePlaylist(() {
      playlist = 'next candidate';
      identity++;
    });
    expect(
      request.restorePlaylist(() {
        playlist = 'incoming';
        identity++;
      }),
      isTrue,
    );
    expect(playlist, media);
  });

  test(
    'same-pack navigation cancels pending shuffle and its rollback',
    () async {
      var navigation = 0;
      var opens = 0;
      var restores = 0;
      final request = EpisodePlaybackRequest(
        currentIdentity: () => 1,
        currentNavigation: () => navigation,
        isActive: () => true,
      );
      final lookup = Completer<void>();
      final pending = request.attempt(() async {
        await lookup.future;
        return request.commit(() async {
          opens++;
        });
      });
      navigation++; // Manual selection, without replacing the playlist.
      lookup.complete();
      expect(await pending, EpisodePlaybackOutcome.cancelled);
      expect(
        request.restorePlaylist(() {
          restores++;
        }),
        isFalse,
      );
      expect(opens, 0);
      expect(restores, 0);
    },
  );

  test(
    'request-owned pack switches preserve the navigation generation',
    () async {
      var identity = 1;
      final request = EpisodePlaybackRequest(
        currentIdentity: () => identity,
        currentNavigation: () => 7,
        isActive: () => true,
      );
      expect(
        await request.attempt(() async {
          request.replacePlaylist(() => identity++);
          await Future<void>.value();
          return request.commit(() async {});
        }),
        EpisodePlaybackOutcome.committed,
      );
    },
  );

  test(
    'failed source replacement remains retryable and next source commits',
    () async {
      var identity = 1;
      var playlist = 'original';
      var opens = 0;
      final request = EpisodePlaybackRequest(
        currentIdentity: () => identity,
        isActive: () => true,
      );
      final failedUrl = Completer<bool>();
      final first = request.attempt(() async {
        request.replacePlaylist(() {
          playlist = 'broken';
          identity++;
        });
        final loaded = await failedUrl.future;
        if (!loaded) {
          request.restorePlaylist(() {
            playlist = 'original';
            identity++;
          });
        }
        return loaded;
      });
      failedUrl.complete(false);
      expect(await first, EpisodePlaybackOutcome.unavailable);
      expect(playlist, 'original');
      expect(request.isCurrent, isTrue);
      expect(identity, 3);

      final second = await request.attempt(() async {
        request.replacePlaylist(() {
          playlist = 'working';
          identity++;
        });
        return request.commit(() async {
          opens++;
        });
      });
      expect(second, EpisodePlaybackOutcome.committed);
      expect(playlist, 'working');
      expect(opens, 1);
    },
  );

  test('disabling shuffle during URL resolution prevents media open', () async {
    var generation = 1;
    var opens = 0;
    final request = EpisodePlaybackRequest(
      currentIdentity: () => 1,
      isActive: () => generation == 1,
    );
    final url = Completer<String>();
    final pending = request.attempt(() async {
      await url.future;
      return request.commit(() async {
        opens++;
      });
    });
    generation++;
    url.complete('https://example.invalid/episode');
    expect(await pending, EpisodePlaybackOutcome.cancelled);
    expect(opens, 0);
  });

  test(
    'cancellation during native preparation is checked again at open',
    () async {
      var active = true;
      var opens = 0;
      final request = EpisodePlaybackRequest(
        currentIdentity: () => 1,
        isActive: () => active,
      );
      final tuning = Completer<void>();
      final pending = request.attempt(() async {
        expect(request.isCurrent, isTrue);
        await tuning.future;
        return request.commit(() async {
          opens++;
        });
      });
      active = false;
      tuning.complete();
      expect(await pending, EpisodePlaybackOutcome.cancelled);
      expect(opens, 0);
    },
  );

  test(
    'external playlist replacement cancels load and prevents stale rollback',
    () async {
      var identity = 1;
      var opens = 0;
      var restored = false;
      final request = EpisodePlaybackRequest(
        currentIdentity: () => identity,
        isActive: () => true,
      );
      final url = Completer<void>();
      final pending = request.attempt(() async {
        request.replacePlaylist(() => identity++);
        await url.future;
        final committed = await request.commit(() async {
          opens++;
        });
        if (!committed) {
          request.restorePlaylist(() {
            restored = true;
            identity++;
          });
        }
        return committed;
      });
      identity++; // Another request owns this playlist now.
      url.complete();
      expect(await pending, EpisodePlaybackOutcome.cancelled);
      expect(opens, 0);
      expect(restored, isFalse);
      expect(identity, 3);
    },
  );

  test(
    'cancelled request can restore its own uncommitted replacement',
    () async {
      var identity = 1;
      var active = true;
      final request = EpisodePlaybackRequest(
        currentIdentity: () => identity,
        isActive: () => active,
      );
      request.replacePlaylist(() => identity++);
      active = false;
      expect(request.restorePlaylist(() => identity++), isTrue);
      expect(request.isCurrent, isFalse);
      expect(request.replacePlaylist(() => identity++), isFalse);
      expect(identity, 3);
    },
  );

  test(
    'load exception is unavailable, not committed by identity mutation',
    () async {
      var identity = 1;
      final request = EpisodePlaybackRequest(
        currentIdentity: () => identity,
        isActive: () => true,
      );
      expect(
        await request.attempt(() async {
          request.replacePlaylist(() => identity++);
          throw StateError('URL resolution failed');
        }),
        EpisodePlaybackOutcome.unavailable,
      );
      expect(request.isCurrent, isTrue);
    },
  );

  test('sleep stop during preparation cancels automatic playback', () async {
    var sleeping = false;
    var opens = 0;
    final request = EpisodePlaybackRequest(
      currentIdentity: () => 1,
      isActive: () => !sleeping,
    );
    final url = Completer<void>();
    final pending = request.attempt(() async {
      await url.future;
      return request.commit(() async {
        opens++;
      });
    });
    sleeping = true;
    url.complete();
    expect(await pending, EpisodePlaybackOutcome.cancelled);
    expect(opens, 0);
  });
}

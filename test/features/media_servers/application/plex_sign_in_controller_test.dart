import 'package:debrify/features/media_servers/application/plex_sign_in_controller.dart';
import 'package:debrify/features/media_servers/application/plex_sign_in_providers.dart';
import 'package:debrify/features/media_servers/data/plex/plex_account_link.dart';
import 'package:debrify/features/media_servers/models/media_server_errors.dart';
import 'package:debrify/models/media_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_plex_sign_in.dart';

void main() {
  late FakePlexSignIn gateway;
  late ProviderContainer container;
  Object scope = 'profile-a';

  setUp(() {
    gateway = FakePlexSignIn();
    scope = 'profile-a';
    container = ProviderContainer(
      overrides: [
        plexSignInGatewayProvider.overrideWithValue(gateway),
        plexSignInClockProvider.overrideWithValue(() => gateway.now),
        plexSignInDelayProvider.overrideWithValue(
          (_) => Future<void>.delayed(Duration.zero),
        ),
        plexSignInScopeProvider.overrideWithValue(() => scope),
      ],
    );
  });

  tearDown(() => container.dispose());

  PlexSignInController controller() =>
      container.read(plexSignInControllerProvider.notifier);
  PlexSignInState state() => container.read(plexSignInControllerProvider);

  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  // Keep the auto-dispose provider alive like the panel does.
  void keepAlive() => container.listen(plexSignInControllerProvider, (_, _) {});

  test('code, then a server choice, then a saved connection', () async {
    keepAlive();
    await controller().start(replaceId: 'old', label: 'Den');
    expect(state(), isA<PlexSignInWaiting>());
    expect((state() as PlexSignInWaiting).code, 'AB1Z');

    await settle();
    final choosing = state() as PlexSignInChoosing;
    expect(choosing.servers, [plexHome, plexFriend]);
    expect(choosing.message, isNull);

    await controller().choose('friend', allowInsecureLocal: true);
    expect(state(), isA<PlexSignInDone>());
    expect(gateway.connects, [('friend', true, 'Den')]);
    expect(gateway.replaceIds, ['old']);
    expect(gateway.attempts.single.closed, isTrue);
  });

  test('a single server with a secure address is connected directly', () async {
    keepAlive();
    gateway.servers = const [plexHome];
    await controller().start();
    await settle();
    expect(state(), isA<PlexSignInDone>());
    expect(gateway.connects, [('home', false, '')]);
  });

  test(
    'if that server cannot be reached, the choice and opt-in appear',
    () async {
      keepAlive();
      gateway
        ..servers = const [plexHome]
        ..reachable = false;
      await controller().start();
      await settle();
      final choosing = state() as PlexSignInChoosing;
      expect(choosing.servers, [plexHome]);
      expect(choosing.message, plexUnreachableMessage);
    },
  );

  test('an expired code can be renewed in the same attempt', () async {
    keepAlive();
    gateway.expireOnPoll = true;
    await controller().start();
    await settle();
    expect(state(), isA<PlexSignInExpired>());

    gateway.expireOnPoll = false;
    await controller().renewCode();
    expect((state() as PlexSignInWaiting).code, 'AB2Z');
    expect(gateway.attempts, hasLength(1));
  });

  test('waiting past the expiry time also expires the code', () async {
    keepAlive();
    gateway
      ..ttl = Duration.zero
      ..signInAfterPolls = 99;
    await controller().start();
    await settle();
    expect(state(), isA<PlexSignInExpired>());
    expect(gateway.polls, 0);
  });

  test('cancelling stops polling and ignores a late answer', () async {
    keepAlive();
    gateway.signInAfterPolls = 3;
    await controller().start();
    controller().cancel();
    await settle();
    expect(state(), isA<PlexSignInIdle>());
    expect(gateway.attempts.single.closed, isTrue);
    expect(gateway.connects, isEmpty);
  });

  test('a profile switch abandons the sign-in without saving', () async {
    keepAlive();
    gateway.servers = const [plexHome];
    await controller().start();
    scope = 'profile-b';
    await settle();
    expect(state(), isA<PlexSignInFailed>());
    expect(gateway.connects, isEmpty);
  });

  test('only one check with plex.tv runs at a time', () async {
    keepAlive();
    gateway.signInAfterPolls = 6;
    await controller().start();
    await settle();
    expect(gateway.polls, greaterThanOrEqualTo(6));
    expect(gateway.maxActivePolls, 1);
  });

  test('a failed save shows its message and can be retried', () async {
    keepAlive();
    gateway.connectError = const MediaServerException(
      'The active profile changed. Sign in again from this profile.',
    );
    await controller().start();
    await settle();
    await controller().choose('home', allowInsecureLocal: false);
    expect(
      (state() as PlexSignInFailed).message,
      'The active profile changed. Sign in again from this profile.',
    );
  });

  test('a refused plex.tv token fails once and is not retried', () async {
    keepAlive();
    gateway
      ..signInAfterPolls = 1
      ..pollErrors.add(const MediaServerAuthError('unauthorized', status: 401));
    await controller().start();
    await settle();
    expect(
      (state() as PlexSignInFailed).message,
      'Plex refused this sign-in. Sign in again with a new code.',
    );
    expect(gateway.polls, 1);
  });

  test('a malformed plex.tv answer is shown, not retried', () async {
    keepAlive();
    gateway.pollErrors.add(TypeError());
    await controller().start();
    await settle();
    expect(state(), isA<PlexSignInFailed>());
    expect(gateway.polls, 1);
  });

  test('a busy or unreachable plex.tv is waited out', () async {
    keepAlive();
    gateway
      ..signInAfterPolls = 3
      ..pollErrors.addAll([
        const MediaServerUnreachable('down'),
        const MediaServerHttpError('busy', status: 503),
      ]);
    await controller().start();
    await settle();
    expect(state(), isA<PlexSignInChoosing>());
  });

  test('a profile error while starting is shown instead of a spinner', () async {
    keepAlive();
    gateway.startError = StateError('Profile session is locked');
    await controller().start();
    expect(
      (state() as PlexSignInFailed).message,
      'This profile is locked, changed or unavailable. Sign in again from this profile.',
    );
  });

  test('a profile switch while waiting ends the sign-in visibly', () async {
    keepAlive();
    gateway.signInAfterPolls = 99;
    await controller().start();
    scope = 'profile-b';
    await settle();
    expect(
      (state() as PlexSignInFailed).message,
      'The active profile changed. Sign in again from this profile.',
    );
    expect(gateway.attempts.single.closed, isTrue);
  });

  test('leaving the page closes the attempt', () async {
    final sub = container.listen(plexSignInControllerProvider, (_, _) {});
    gateway.signInAfterPolls = 99;
    await controller().start();
    sub.close();
    await settle();
    expect(gateway.attempts.single.closed, isTrue);
  });
}

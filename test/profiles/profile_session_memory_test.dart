import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProfileScope profileA;
  late ProfileScope profileB;

  setUp(() {
    profileA = ProfileScope(
      profileId: 'profile-a',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    profileB = ProfileScope(
      profileId: 'profile-b',
      dataGeneration: 1,
      sessionEpoch: 2,
    );
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(profileA);
    ProfileSessionMemory.debugReset();
  });

  tearDown(() {
    ProfileSessionMemory.debugReset();
    ProfileRuntime.debugReset();
  });

  test('same profile session can consume its preserved screen state', () {
    final memory = ProfileSessionMemory<String>();
    final owner = ProfileSessionMemory.captureOwner();

    memory.store(owner, 'profile A query and results');

    expect(
      memory.take(ProfileSessionMemory.captureOwner()),
      'profile A query and results',
    );
    expect(memory.take(owner), isNull, reason: 'restores are one-shot');
  });

  test('another profile cannot consume preserved screen state', () {
    final memory = ProfileSessionMemory<String>();
    final profileAOwner = ProfileSessionMemory.captureOwner();
    memory.store(profileAOwner, 'profile A query and results');

    ProfileRuntime.publish(profileB);
    final profileBOwner = ProfileSessionMemory.captureOwner();

    expect(memory.take(profileBOwner), isNull);
    expect(
      memory.take(profileAOwner),
      isNull,
      reason: 'a mismatched read also purges the stale profile value',
    );
  });

  test('late outgoing dispose cannot repopulate an incoming session', () {
    final memory = ProfileSessionMemory<String>();
    final outgoingOwner = ProfileSessionMemory.captureOwner();
    memory.store(outgoingOwner, 'first outgoing snapshot');

    ProfileSessionMemory.clearAll();
    ProfileRuntime.publish(profileB);
    final incomingOwner = ProfileSessionMemory.captureOwner();

    // A widget mounted under A can dispose after the lifecycle clear. It must
    // keep its mount-time owner instead of being relabelled as profile B.
    memory.store(outgoingOwner, 'late outgoing snapshot');

    expect(memory.take(incomingOwner), isNull);
  });

  test('lifecycle clear purges stores with different value types', () {
    final textMemory = ProfileSessionMemory<String>();
    final numberMemory = ProfileSessionMemory<int>();
    final owner = ProfileSessionMemory.captureOwner();
    textMemory.store(owner, 'query');
    numberMemory.store(owner, 42);

    ProfileSessionMemory.clearAll();

    expect(textMemory.take(owner), isNull);
    expect(numberMemory.take(owner), isNull);
  });

  test('nonmatching surface leaves same-session state for its owner', () {
    final memory = ProfileSessionMemory<String>();
    final owner = ProfileSessionMemory.captureOwner();
    memory.store(owner, 'search-tab');

    expect(memory.take(owner, where: (value) => value == 'home-board'), isNull);
    expect(
      memory.take(owner, where: (value) => value == 'search-tab'),
      'search-tab',
    );
  });
}

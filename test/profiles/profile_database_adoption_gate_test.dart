import 'package:debrify/services/profiles/profile_database_adoption_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    ProfileDatabaseAdoptionGate.debugReset();
  });

  tearDown(ProfileDatabaseAdoptionGate.debugReset);

  test('database opens wait until the adoption gate is released', () async {
    await ProfileDatabaseAdoptionGate.hold();
    var passed = false;
    final waiting = ProfileDatabaseAdoptionGate.waitUntilReleased().then((_) {
      passed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(passed, isFalse);

    await ProfileDatabaseAdoptionGate.release();
    await waiting;
    expect(passed, isTrue);
  });

  test('persisted gate is reconstructed after a process restart', () async {
    await ProfileDatabaseAdoptionGate.hold();
    ProfileDatabaseAdoptionGate.debugReset();
    await ProfileDatabaseAdoptionGate.restorePersisted();
    var passed = false;
    final waiting = ProfileDatabaseAdoptionGate.waitUntilReleased().then((_) {
      passed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(passed, isFalse);

    await ProfileDatabaseAdoptionGate.release();
    await waiting;
    expect(passed, isTrue);
  });
}

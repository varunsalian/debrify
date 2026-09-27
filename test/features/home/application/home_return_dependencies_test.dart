import 'package:debrify/features/home/application/home_return_dependencies.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../data/home_return_repository_test.dart' show returnSnapshot;

void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
  });
  tearDown(() {
    ProfileSessionMemory.clearAll();
    ProfileRuntime.debugReset();
  });
  test(
    'provider disposal leaves the borrowed adapter usable for outgoing view disposal',
    () {
      final owner = ProfileSessionMemory.captureOwner();
      final container = ProviderContainer.test();
      final repository = container.read(homeReturnRepositoryProvider(owner));
      final saved = returnSnapshot();
      container.dispose();
      repository.store(saved, revision: repository.revision);
      final next = ProviderContainer.test();
      expect(next.read(homeReturnRepositoryProvider(owner)).take(), saved);
      expect(repository.take(), isNull);
    },
  );
  test(
    'provider construction and recomputation do not consume a saved board',
    () {
      final owner = ProfileSessionMemory.captureOwner();
      final container = ProviderContainer.test();
      final repository = container.read(homeReturnRepositoryProvider(owner));
      final saved = returnSnapshot();
      repository.store(saved, revision: repository.revision);
      container.invalidate(homeReturnRepositoryProvider(owner));
      final replacement = container.read(homeReturnRepositoryProvider(owner));
      expect(replacement, isNot(same(repository)));
      expect(replacement.take(), saved);
    },
  );
}

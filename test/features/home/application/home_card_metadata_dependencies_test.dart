import 'dart:convert';
import 'package:debrify/features/home/application/home_card_metadata_dependencies.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../fixtures/card_metadata_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);

  test(
    'default adapter reads the captured profile policy and delegates current-provider presentation',
    () async {
      final scope = ProfileScope(
        profileId: 'one',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      SharedPreferences.setMockInitialValues({
        MetadataPreferencesService.key: jsonEncode(
          MetadataPreferences(language: 'fr-FR').toJson(),
        ),
        scope.preferenceKey(MetadataPreferencesService.key): jsonEncode(
          MetadataPreferences(language: 'hi-IN').toJson(),
        ),
      });
      ProfileRuntime.promoteLegacyToCommitted(scope);
      final container = ProviderContainer.test();
      final epoch = container.read(homeCardMetadataEpochProvider);
      final repository = container.read(
        homeCardMetadataRepositoryProvider(epoch),
      );
      expect((await repository.readPreferences()).language, 'hi-IN');
      final current = MetadataPreferences(
        providers: {
          for (final category in MetadataCategory.values)
            category: MetadataPreferences.current,
        },
        features: {},
      );
      final result = await repository.present(cardSource, current, () => true);
      expect(result.item, same(cardSource));
    },
  );

  for (final reason in ['profile', 'policy']) {
    test(
      '$reason retirement rejects reads and presentation before service entry',
      () async {
        final container = ProviderContainer.test();
        final epoch = container.read(homeCardMetadataEpochProvider);
        final repository = container.read(
          homeCardMetadataRepositoryProvider(epoch),
        );
        if (reason == 'profile') {
          ProfileRuntime.promoteLegacyToCommitted(
            ProfileScope(
              profileId: 'incoming',
              dataGeneration: 1,
              sessionEpoch: 1,
            ),
          );
        } else {
          MetadataPreferencesService.revision.value++;
        }
        expect(repository.isCurrent(), isFalse);
        await expectLater(repository.readPreferences(), throwsStateError);
        await expectLater(
          repository.present(cardSource, MetadataPreferences(), () => true),
          throwsStateError,
        );
      },
    );
  }

  testWidgets(
    'epoch adapter observes policy/profile changes and removes listeners on disposal',
    (tester) async {
      final container = ProviderContainer();
      var closed = false;
      addTearDown(() {
        if (!closed) container.dispose();
      });
      final subscription = container.listen(
        homeCardMetadataEpochProvider,
        (_, _) {},
      );
      final original = subscription.read();
      MetadataPreferencesService.revision.value++;
      container.read(homeCardMetadataEpochProvider);
      await tester.pump();
      expect(subscription.read().revision, original.revision + 1);
      expect(subscription.read().owner, original.owner);
      ProfileRuntime.promoteLegacyToCommitted(
        ProfileScope(profileId: 'incoming', dataGeneration: 1, sessionEpoch: 1),
      );
      container.read(homeCardMetadataEpochProvider);
      await tester.pump();
      expect(subscription.read().owner, isNot(original.owner));
      subscription.close();
      container.dispose();
      closed = true;
      MetadataPreferencesService.revision.value++;
      ProfileRuntime.publish(
        ProfileScope(profileId: 'later', dataGeneration: 1, sessionEpoch: 2),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

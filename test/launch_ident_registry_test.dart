import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/services/storage_service.dart';
import 'package:debrify/widgets/launch/launch_ident.dart';

/// The ident registry and StorageService's accepted-values set are two lists
/// that must agree. When they drift, nothing errors — the pref is silently
/// normalized back to 'horizon' and the picker just appears not to save.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every registered ident id round-trips through the pref', () async {
    for (final ident in kLaunchIdents) {
      await StorageService.setLaunchAnimation(ident.id);
      expect(
        StorageService.launchAnimationCached,
        ident.id,
        reason: '"${ident.id}" (${ident.label}) is missing from '
            'StorageService._launchAnimationValues',
      );
      expect(await StorageService.getLaunchAnimation(), ident.id);
    }
  });

  test('an unknown id falls back to the default ident', () async {
    await StorageService.setLaunchAnimation('not-an-ident');
    expect(StorageService.launchAnimationCached, kLaunchIdents.first.id);
    expect(launchIdentFor('not-an-ident').id, kLaunchIdents.first.id);
  });

  test('ids are unique and stable-looking', () {
    final ids = kLaunchIdents.map((i) => i.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate ident id');
    expect(kLaunchIdents.first.id, 'horizon',
        reason: 'the first entry is the default; changing it moves every '
            'unset/unknown pref onto a different splash');
  });

  test('registry and storage agree in both directions', () {
    expect(
      StorageService.launchAnimationValues,
      kLaunchIdents.map((i) => i.id).toSet(),
      reason: 'an id accepted by storage but absent from the registry is dead '
          'config; an id in the registry but not accepted by storage cannot '
          'be saved',
    );
  });

  test('shipped ids never change', () {
    // These are written into user prefs on real installs. Renaming one — even
    // consistently in both lists — silently moves that user back to Horizon,
    // which no other assertion here would catch. Add to this list when you
    // add an ident; only edit an existing entry with a migration.
    expect(kLaunchIdents.map((i) => i.id).toList(), [
      'horizon',
      'drop',
      'marquee',
      'prism',
      'neon',
      'chrome',
      'monogram',
      'aperture',
      'blueprint',
      'ripple',
      'ember',
      'swiss',
      'origami',
      'anamorphic',
      'constellation',
      'silk',
      'rackfocus',
    ]);
  });
}

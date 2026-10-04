import 'dart:async';

import 'package:debrify/screens/addons/addon_hub_screen.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../support/addon_hub_fixture.dart';
import '../../../../support/addon_hub_profiles.dart';

void main() {
  testWidgets(
    'older held installed load cannot publish metadata or clear newer state',
    (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        final store = (await t.runAsync(AddonHubHeldPreferences.install))!;
        final release = Completer<void>();
        store.read = release;
        SharedPreferences.resetStatic();
        final load = f.member('loadInstalled') as Future<void> Function();
        final older = load();
        await f.until(t, () => store.reads.length == 1);
        store.read = null;
        await t.runAsync(
          () => store.setValue(
            'String',
            'flutter.stremio_metadata_provider_v1',
            'automatic',
          ),
        );
        SharedPreferences.resetStatic();
        final newer = load();
        await f.until(t, () => f.member('installedLoading') == false);
        await newer;
        expect(f.member('metadataProviderPreference'), 'automatic');
        final revision = f.member('installedLoadRevision');
        release.complete();
        await f.until(t, () => f.member('installedLoadRevision') == revision);
        await older;
        expect(f.member('metadataProviderPreference'), 'automatic');
        expect(f.member('installedLoading'), isFalse);
        expect(f.ids('installed'), ['z9', 'com.linvo.cinemeta', 'a2']);
        expect(f.requests, isEmpty);
      });
    },
  );
  testWidgets(
    'both original listener receivers unregister before subsequent notifications',
    (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        final state = f.key.currentState!;
        final before = addonHubTestAccess(state);
        await t.pumpWidget(const SizedBox.shrink());
        StremioService.instance.refreshAfterExternalChange();
        LocalEngineStorage.changes.value++;
        await t.pump();
        final after = addonHubTestAccess(state);
        expect(after['installedLoadRevision'], before['installedLoadRevision']);
        expect(after['engineLoadRevision'], before['engineLoadRevision']);
        expect(f.requests, isEmpty);
        expect(f.clients.last.closed, isTrue);
      });
    },
  );
}

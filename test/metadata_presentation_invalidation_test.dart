import 'dart:convert';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/metadata_presentation_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => ProbeState();
}

class ProbeState extends State<Probe> with MetadataPresentationMixin<Probe> {
  int resets = 0;
  int presentations = 0;
  @override
  StremioMeta get originalMetadata =>
      const StremioMeta(id: 'custom', type: 'movie', name: 'A');
  @override
  void onMetadataPolicyChanged() => resets++;
  @override
  void onMetadataPresentationChanged() => presentations++;
  @override
  Widget build(BuildContext context) => Text(presentedMetadata!.name);
}

void main() {
  testWidgets(
    'Home changes preserve metadata; actual provider changes refresh it',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final key = GlobalKey<ProbeState>();
      await tester.pumpWidget(MaterialApp(home: Probe(key: key)));
      await tester.pumpAndSettle();
      final initial = key.currentState!.presentations;
      for (var i = 0; i < 5; i++) {
        MainPageBridge.notifyHomeSettingsChanged();
      }
      await tester.pumpAndSettle();
      expect(key.currentState!.resets, 0);
      expect(key.currentState!.presentations, initial);
      await MetadataPreferencesService.save(
        MetadataPreferences(language: 'fr-FR'),
      );
      await tester.pumpAndSettle();
      expect(key.currentState!.resets, 1);
      await StremioService.instance.setMetadataProviderPreference('automatic');
      await tester.pumpAndSettle();
      expect(key.currentState!.resets, 2);
      await StremioService.instance.setMetadataProviderPreference('automatic');
      await tester.pumpAndSettle();
      expect(key.currentState!.resets, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'decoding memo reuses unchanged JSON and observes external writes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await ProfilePreferences.instance();
      await prefs.setString(
        MetadataPreferencesService.key,
        jsonEncode(MetadataPreferences(language: 'fr-FR').toJson()),
      );
      final first = await MetadataPreferencesService.load();
      expect(identical(first, await MetadataPreferencesService.load()), true);
      await prefs.setString(
        MetadataPreferencesService.key,
        jsonEncode(MetadataPreferences(language: 'hi-IN').toJson()),
      );
      expect((await MetadataPreferencesService.load()).language, 'hi-IN');
      await prefs.setString(MetadataPreferencesService.key, 'broken-json');
      expect((await MetadataPreferencesService.load()).language, 'en-US');
      await prefs.remove(MetadataPreferencesService.key);
      expect((await MetadataPreferencesService.load()).isCurrent, true);
    },
  );
}

import 'package:debrify/services/engine/remote_engine_manager.dart';
import 'package:debrify/widgets/onboarding/onboarding_theme.dart';
import 'package:flutter/material.dart';

class FakeRemoteEngineManager extends RemoteEngineManager {
  FakeRemoteEngineManager(this.engines);

  final List<RemoteEngineInfo> engines;

  @override
  Future<List<RemoteEngineInfo>> fetchAvailableEngines() async => engines;

  @override
  Future<String?> downloadEngineYaml(String fileName) async =>
      'id: ${fileName.replaceAll('.yaml', '')}\ndisplay_name: Test\nsearch:\n  url: https://example.com\n';

  @override
  void dispose() {}
}

Widget onboardingApp(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: OnboardingTheme.scope(Scaffold(body: child)),
);

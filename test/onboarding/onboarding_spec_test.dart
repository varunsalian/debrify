import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the approved 1920x1080 mock and its logical-pixel implementation
/// tied together without pretending browser and Flutter text rasterize alike.
void main() {
  final mock = File('design/mockups/onboarding_mockup/index.html');
  final stage = File('lib/widgets/onboarding/onboarding_stage.dart');
  final keyStep = File('lib/widgets/onboarding/steps/key_step.dart');
  final models = File('lib/widgets/onboarding/onboarding_models.dart');
  final flow = File('lib/widgets/onboarding/onboarding_flow.dart');

  test('the onboarding mock and production sources are present', () {
    expect(mock.existsSync(), isTrue);
    expect(stage.existsSync(), isTrue);
    expect(keyStep.existsSync(), isTrue);
    expect(models.existsSync(), isTrue);
    expect(flow.existsSync(), isTrue);
  });

  test('stage geometry is the mock at half scale', () {
    final html = mock.readAsStringSync();
    final dart = stage.readAsStringSync();
    expect(html, contains('width:1920px; height:1080px'));
    expect(html, contains('left:84px; top:96px; width:600px'));
    expect(html, contains('height:72px; border-radius:36px'));
    expect(dart, contains('keyStep ? 63.0 : 300.0'));
    expect(dart, contains('EdgeInsets.fromLTRB(42, 48, 42'));
    expect(dart, contains('widget.compact ? 42.0 : 33.0'));
    expect(dart, contains('height: 36'));
  });

  test('keyboard and responsive invariants cannot silently drift', () {
    final html = mock.readAsStringSync();
    final keyDart = keyStep.readAsStringSync();
    final modelDart = models.readAsStringSync();
    final flowDart = flow.readAsStringSync();
    expect(html, contains('The field sits in its own band.'));
    expect(html, contains('CTA that is <b>sticky above the keyboard</b>'));
    expect(keyDart, contains('BoxConstraints(minHeight: 275)'));
    expect(modelDart, contains('if (isTelevision)'));
    expect(modelDart, contains('size.width < 600'));
    expect(modelDart, contains('size.width <= 1000'));
    expect(flowDart, contains('Duration(milliseconds: 220)'));
    expect(flowDart, contains('rootNavigator: true'));
  });
}

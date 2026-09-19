import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:debrify/utils/app_version_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const packageInfoChannel = MethodChannel(
    'dev.fluttercommunity.plus/package_info',
  );

  test(
    'accepts and caches the tvOS Bundle.main package-info contract',
    () async {
      AppVersionInfo.debugReset();
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(packageInfoChannel, (call) async {
            calls++;
            expect(call.method, 'getAll');
            return <String, Object>{
              'appName': 'Debrify',
              'packageName': 'com.varunsalian.debrifytv',
              'version': '0.8.15-alpha.1',
              'buildNumber': '43',
              'buildSignature': '',
            };
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(packageInfoChannel, null);
        AppVersionInfo.debugReset();
      });

      final first = await AppVersionInfo.get();
      final second = await AppVersionInfo.get();

      expect(first.appName, 'Debrify');
      expect(first.packageName, 'com.varunsalian.debrifytv');
      expect(first.version, '0.8.15-alpha.1');
      expect(first.buildNumber, '43');
      expect(identical(first, second), isTrue);
      expect(AppVersionInfo.isUnavailable, isFalse);
      expect(calls, 1);
    },
  );

  test('restores the bundled prerelease label from an Apple version', () async {
    AppVersionInfo.debugReset();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final bundled = RegExp(
      r'^version:\s*([^\s#+]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    final appleVersion = bundled
        .replaceAll(RegExp(r'[^\d\.]'), '')
        .split('.')
        .where((segment) => segment.isNotEmpty)
        .join('.');
    PackageInfo.setMockInitialValues(
      appName: 'Debrify',
      packageName: 'com.varunsalian.debrify',
      version: appleVersion,
      buildNumber: '48',
      buildSignature: '',
    );
    addTearDown(AppVersionInfo.debugReset);

    final info = await AppVersionInfo.get();

    expect(info.version, bundled);
  });

  test('does not replace an explicit build-name override', () {
    expect(
      AppVersionInfo.restoreSanitizedAppleVersion(
        reportedVersion: '1.2.3',
        bundledVersion: '0.9.4-alpha.1',
      ),
      '1.2.3',
    );
  });
}

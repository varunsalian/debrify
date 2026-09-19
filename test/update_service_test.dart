import 'dart:convert';
import 'dart:io';

import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _release(
  String tag, {
  bool draft = false,
  bool prerelease = false,
}) => <String, Object?>{
  'tag_name': tag,
  'name': tag,
  'body': '',
  'html_url': 'https://github.com/varunsalian/debrify/releases/tag/$tag',
  'published_at': '2026-09-19T00:00:00Z',
  'draft': draft,
  'prerelease': prerelease,
  'assets': <Object?>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppVersion', () {
    test(
      'orders alpha, beta, and final releases using semantic precedence',
      () {
        final alpha1 = AppVersion.tryParse('v0.9.5-alpha.1')!;
        final alpha2 = AppVersion.tryParse('0.9.5-alpha.2+49')!;
        final beta1 = AppVersion.tryParse('0.9.5-beta.1')!;
        final finalRelease = AppVersion.tryParse('0.9.5')!;

        expect(alpha1.compareTo(alpha2), isNegative);
        expect(alpha2.compareTo(beta1), isNegative);
        expect(beta1.compareTo(finalRelease), isNegative);
      },
    );

    test('newer core alpha beats an older beta', () {
      final alpha = AppVersion.tryParse('0.9.5-alpha.1')!;
      final beta = AppVersion.tryParse('0.9.4-beta.3')!;

      expect(alpha.compareTo(beta), isPositive);
    });

    test('ignores build metadata and rejects non-version labels', () {
      final withBuild = AppVersion.tryParse('0.9.5-beta.1+52')!;
      final withoutBuild = AppVersion.tryParse('v0.9.5-beta.1')!;

      expect(withBuild.compareTo(withoutBuild), 0);
      expect(AppVersion.tryParse('latest-alpha'), isNull);
    });
  });

  group('UpdateService', () {
    test('recognizes same-base Apple prerelease increments', () {
      expect(
        UpdateService.isReleaseNewer(
          releaseVersion: 'v0.9.4-alpha.2',
          currentVersion: '0.9.4.1',
        ),
        isTrue,
      );
      expect(
        UpdateService.isReleaseNewer(
          releaseVersion: 'v0.9.4-beta.2',
          currentVersion: '0.9.4.1',
        ),
        isTrue,
      );
      expect(
        UpdateService.isReleaseNewer(
          releaseVersion: 'v0.9.4-alpha.1',
          currentVersion: '0.9.4.1',
        ),
        isFalse,
      );
    });

    test('preserved channel metadata recognizes alpha to beta promotion', () {
      expect(
        UpdateService.isReleaseNewer(
          releaseVersion: 'v0.9.4-beta.1',
          currentVersion: '0.9.4-alpha.1',
        ),
        isTrue,
      );
    });

    test('keeps the normal channel on the latest-release endpoint', () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/releases/latest'));
        expect(request.url.query, isEmpty);
        return http.Response(jsonEncode(_release('v0.9.4-beta.1')), 200);
      });

      final release = await UpdateService.fetchLatestRelease(
        forceRefresh: true,
        client: client,
      );

      expect(release.versionLabel, 'v0.9.4-beta.1');
    });

    test('alpha opt-in selects the highest non-draft release', () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/releases'));
        expect(request.url.queryParameters['per_page'], '30');
        return http.Response(
          jsonEncode(<Object?>[
            _release('v0.9.4-beta.1'),
            _release('v0.9.5-alpha.1', prerelease: true),
            _release('v0.9.6-alpha.1', draft: true, prerelease: true),
          ]),
          200,
        );
      });

      final release = await UpdateService.fetchLatestRelease(
        forceRefresh: true,
        includePrereleases: true,
        client: client,
      );

      expect(release.versionLabel, 'v0.9.5-alpha.1');
      expect(release.prerelease, isTrue);
    });
  });

  group('alpha update preference', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults off and persists an opt-in', () async {
      expect(await StorageService.getUpdateIncludeAlphaEnabled(), isFalse);

      await StorageService.setUpdateIncludeAlphaEnabled(true);

      expect(await StorageService.getUpdateIncludeAlphaEnabled(), isTrue);
    });
  });

  test('settings update actions enforce the app-update permission', () {
    final source = File('lib/screens/settings_screen.dart').readAsStringSync();
    for (final method in <String>[
      '_checkForAppUpdates',
      '_toggleAutoUpdateChecks',
      '_toggleIncludeAlphaUpdates',
    ]) {
      expect(
        source,
        matches(
          RegExp(
            'Future<void> $method\\([^)]*\\) async \\{\\s*'
            'if \\(!await _ensureProfileFeature\\('
            'ProfileFeature\\.appUpdates\\)\\) return;',
          ),
        ),
        reason: '$method must fail closed for restricted profiles',
      );
    }
  });
}

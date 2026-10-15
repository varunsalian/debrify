import 'dart:convert';

import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_driver.dart';

void main() {
  for (final origin in ['fresh', 'launch']) {
    for (final missing in ['id', 'empty-id', 'revision']) {
      testWidgets(
        'p13 recording resource edge $origin missing=$missing preserves validation and fallback',
        (t) async {
          final d = RecordingDriver(t, committed: false);
          await d.setup();
          SecretVault.debugReset(deviceIdOverride: 'vplayer-recording-edges');
          try {
            SharedPreferences.setMockInitialValues({
              if (origin == 'fresh')
                'iptv_playlists': [
                  jsonEncode({
                    'id': 'p13-edge',
                    'name': 'Resource edge',
                    'url': '',
                    'addedAt': '2024-01-01T00:00:00.000',
                    if (missing != 'id')
                      '_connectionResourceId': missing == 'empty-id'
                          ? ''
                          : 'fresh',
                    if (missing != 'revision') '_connectionResourceRevision': 8,
                  }),
                ],
            });
            final url = await d.loopback();
            await d.mountRecording(
              url: url,
              tee: false,
              sourceId: 'p13-edge',
              sources: [
                {
                  'id': 'p13-edge',
                  if (origin == 'fresh' || missing != 'id')
                    'connectionResourceId':
                        origin == 'launch' && missing == 'empty-id'
                        ? ''
                        : 'launch',
                  if (origin == 'fresh' || missing != 'revision')
                    'connectionResourceRevision': 3,
                },
              ],
            );
            d.native.properties['file-format'] = 'mpegts';
            d.desktopRecord();
            final capture = await d.captured(url);
            expect(
              capture.connectionResourceId,
              origin == 'fresh' ? 'launch' : null,
            );
            expect(
              capture.resourceAuthorizationRevision,
              origin == 'fresh' ? 3 : null,
            );
            expect(d.errors, isEmpty);
          } finally {
            await d.close();
            SecretVault.debugReset();
          }
        },
      );
    }
  }
}

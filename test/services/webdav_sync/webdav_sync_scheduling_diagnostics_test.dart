import 'dart:convert';
import 'dart:io';

import 'package:debrify/services/diagnostic_log.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export retains deferral reasons and scheduling state', () async {
    final directory = await Directory.systemTemp.createTemp('sync-diagnostics-');
    final log = DiagnosticLog.instance;
    await log.initialize(directoryOverride: directory);
    try {
      recordWebDavSyncLocalChangeDeferred('cycle did not start', 3,
          const Duration(seconds: 8));
      recordWebDavSyncScheduling('scheduler_state', 'cycle_return_inactive', {
        'pendingSequence': 12,
        'tvPlayback': false,
        'foreground': true,
      });
      final text = utf8.decode((await log.exportLastWindow()).bytes);
      final rows = text.trim().split('\n').map((line) => jsonDecode(line) as Map);
      final deferred = rows.firstWhere((r) => r['event'] == 'local_change_deferred');
      expect(deferred['fields']['reason'], 'cycle_did_not_start');
      expect(deferred['fields']['delayMs'], 8000);
      final state = rows.firstWhere((r) => r['event'] == 'scheduler_state');
      expect(state['fields']['reason'], 'cycle_return_inactive');
      expect(state['fields']['pendingSequence'], 12);
      expect(state['fields']['tvPlayback'], false);
    } finally {
      await log.dispose();
      await directory.delete(recursive: true);
    }
  });
}

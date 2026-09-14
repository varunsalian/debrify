import 'dart:io';

import 'package:debrify/services/android_native_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

/// Only Android registers the downloader event channel. Every other platform
/// used to subscribe anyway and throw a MissingPluginException on each
/// profile-scope remount (three listeners re-subscribe), which surfaced as
/// repeated framework errors on macOS. Off Android the stream must simply be
/// empty — no channel, no throw.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('events is an empty stream off Android', () async {
    if (Platform.isAndroid) return;
    final events = await AndroidNativeDownloader.events.toList();
    expect(events, isEmpty);
  });
}

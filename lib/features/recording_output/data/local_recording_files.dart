// The local recordings library as the SMB upload sees it: Android's native
// recording store (content:// or file:// uris) and the desktop recordings
// folder (plain paths).

import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:saf_stream/saf_stream.dart';

import '../models/smb_upload_models.dart';

/// Recording exists on Android and on desktops with the capture engine;
/// never on iOS/tvOS, where dart_smb2's library is not bundled.
bool get smbUploadSupported =>
    Platform.isAndroid || DesktopRecordingService.instance.isSupported;

/// Finished recordings visible to the active profile.
Future<List<SmbLocalRecording>> listLocalRecordings() async {
  final entries = Platform.isAndroid
      ? await LiveRecordingService.queryLibrary()
      : await DesktopRecordingService.listLibrary();
  return [
    for (final e in entries)
      SmbLocalRecording(
        uri: e.uri,
        name: e.name,
        bytes: e.bytes,
        recordedAtMs: e.recordedAtMs,
      ),
  ];
}

/// Files still being written; they are never uploaded.
Future<Set<String>> activeRecordingUris() async {
  if (Platform.isAndroid) {
    final live = await LiveRecordingService.query();
    return {
      for (final r in live)
        if (r.isRecording && (r.uri ?? '').isNotEmpty) r.uri!,
    };
  }
  return {for (final c in DesktopRecordingService.instance.captures) c.path};
}

Future<bool> deleteLocalRecording(String uri) => Platform.isAndroid
    ? LiveRecordingService.deleteRecordingFile(uri)
    : DesktopRecordingService.deleteRecordingFile(uri);

/// Streams a library entry's bytes.
Stream<Uint8List> readLocalRecording(String uri) async* {
  if (uri.startsWith('content://')) {
    yield* await SafStream().readFileStream(uri, bufferSize: 1024 * 1024);
    return;
  }
  final file = uri.startsWith('file://')
      ? File.fromUri(Uri.parse(uri))
      : File(uri);
  await for (final chunk in file.openRead()) {
    yield chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
  }
}

/// Identity of the active profile, so a pass started under one profile
/// stops (and never deletes local files) once another takes over.
String currentRecordingScope() =>
    ProfileRuntime.isProfileCommitted ? ProfileRuntime.capture().profileId : '';

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
/// never on iOS (libsmb2 is bundled there but never loaded) or tvOS (not
/// bundled at all).
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
    // failClosed: an unreadable engine state skips the pass instead of
    // treating every file as finished.
    final live = await LiveRecordingService.query(failClosed: true);
    return {
      for (final r in live)
        if (r.isRecording && (r.uri ?? '').isNotEmpty) r.uri!,
    };
  }
  return DesktopRecordingService.instance.activePaths;
}

Future<bool> deleteLocalRecording(String uri) => Platform.isAndroid
    ? LiveRecordingService.deleteRecordingFile(uri)
    : DesktopRecordingService.deleteRecordingFile(uri);

/// Streams a library entry's bytes.
Stream<Uint8List> readLocalRecording(String uri) async* {
  if (uri.startsWith('content://')) {
    // Pull one chunk per request: readFileStream pushes the whole file over
    // an EventChannel with no backpressure, and a multi-GB recording read
    // faster than the share accepts it would pile up in memory.
    final saf = SafStream();
    final session = await saf.startReadCustomFileStream(
      uri,
      bufferSize: 1024 * 1024,
    );
    try {
      while (true) {
        final chunk = await saf.readCustomFileStreamChunk(session);
        if (chunk == null || chunk.isEmpty) break;
        yield chunk;
      }
    } finally {
      await saf.endReadCustomFileStream(session);
    }
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

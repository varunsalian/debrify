import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/alldebrid_files_source.dart';

// This source-only boundary supplements behavioural HTTP/widget tests. It
// freezes the native handoff, dormant branches and lifecycle without adding an
// injectable player, download or private-action seam to production.
String lines(String text) =>
    text.split('\n').map((line) => line.trim()).join('\n').trim();
void main() {
  final frozen =
      jsonDecode(
            File(
              'dev/tool/alldebrid_files_original_bodies.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  const cases = <String, List<String>>{
    "verbatim State startup and ten ordered disposals": [
      "initState",
      "dispose",
    ],
    "token-exact file launcher arguments and mounted handoff": ["_playFile"],
    "token-exact series playlist sorting fallback clamp and launcher arguments":
        ["_playVideos", "_findFirstEpisodeIndex"],
    "token-exact saved-link launcher arguments and notify order": ["_playLink"],
    "file enqueue credentials context size and failure contracts": [
      "_downloadFile",
    ],
    "saved-link enqueue credentials context and failure contracts": [
      "_downloadLink",
    ],
    "selected-files sequential enqueue and three result branches": [
      "_downloadSelectedFiles",
    ],
    "download dialog maps retain full paths sizes indices and unawaited callback":
        ["_downloadMagnet"],
    "playlist persistence single and collection maps retain all arguments": [
      "_addMagnetToPlaylist",
    ],
    "shared loading flag guard clear-before-pop and non-dismissible barrier": [
      "_showLoading",
      "_dismissLoading",
    ],
    "dormant non-ready snacks and badges remain unreachable and verbatim": [
      "_openMagnet",
      "_buildMagnetCard",
    ],
    "navigate-up attached-scroll reset and focus protocol remain verbatim": [
      "_navigateUp",
    ],
    "clipboard auto-paste and original input link-save contract remain verbatim":
        ["_showAddLinkDialog", "_copyLink"],
  };
  for (final entry in cases.entries) {
    test(entry.key, () {
      for (final method in entry.value) {
        final identity = '_AllDebridFilesScreenState.$method';
        expect(
          lines(allDebridOriginalMember(identity)),
          lines(frozen[identity] as String),
          reason: 'Frozen ORIGINAL $identity changed',
        );
      }
    });
  }
}

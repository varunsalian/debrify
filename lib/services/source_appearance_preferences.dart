import 'package:debrify/services/storage/torrent_search_storage.dart';
import '../models/source_appearance.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_session_memory.dart';

/// Shared by keyword results and the Sources settings repository.
Future<SourceAppearance> readSourceAppearance(ProfileSessionOwner owner) async {
  bool current() => owner == ProfileSessionMemory.captureOwner();
  if (!current()) return initialSourceAppearance;
  Future<SourceAppearance> read() async {
    final text = await TorrentSearchStorage.getUseAddonTextFormatting();
    if (!current()) return initialSourceAppearance;
    final logos = await TorrentSearchStorage.getShowAddonLogos();
    return current() ? (text: text, logos: logos) : initialSourceAppearance;
  }

  final scope = owner.scope;
  return scope == null ? read() : ProfileRuntime.withCapturedScope(scope, read);
}

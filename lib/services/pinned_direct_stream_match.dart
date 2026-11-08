import '../models/torrent.dart';

/// Match candidates already scoped to the saved addon's configuration.
/// An explicit group must survive; otherwise profile identity is required,
/// with response position used only to disambiguate matching profiles.
Torrent? matchPinnedDirectStream(
  List<Torrent> direct, {
  required String streamKey,
  required int streamIndex,
  String? bingeGroup,
}) {
  if (bingeGroup != null && bingeGroup.isNotEmpty) {
    final matches = direct
        .where((t) => t.stremioBingeGroup == bingeGroup)
        .toList();
    // An explicit group disappearing is a miss, not permission to change groups.
    if (matches.isEmpty) return null;
    return matches.firstWhere(
      (t) => t.stremioStreamKey == streamKey,
      orElse: () => matches.first,
    );
  }
  final profileMatches = direct
      .where((torrent) => torrent.stremioStreamKey == streamKey)
      .toList(growable: false);
  if (profileMatches.length == 1) return profileMatches.single;
  if (profileMatches.isNotEmpty) {
    for (final torrent in profileMatches) {
      if (torrent.stremioStreamIndex == streamIndex) return torrent;
    }
    return profileMatches.first;
  }
  return null;
}

/// Why [matchPinnedDirectStream] found nothing, as a fixed diagnostic label.
/// A saved group naming a torrent hash is a season pack, which should offer
/// every episode, so its miss is worth a look; a quality/release group
/// usually belongs to a single-episode release whose next episode comes from
/// another release.
String pinnedDirectMissReason(List<Torrent> direct, String? bingeGroup) {
  if (direct.isEmpty) return 'no_direct_streams';
  if (bingeGroup == null || bingeGroup.isEmpty) return 'profile_missing';
  return RegExp(r'[0-9a-fA-F]{40}').hasMatch(bingeGroup)
      ? 'pack_group_missing'
      : 'binge_group_missing';
}

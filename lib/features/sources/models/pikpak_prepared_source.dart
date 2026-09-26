/// Files prepared for playback; streaming URLs are resolved by the caller.
class PikPakPreparedSource {
  final String fileId;
  final List<PikPakSourceVideo> videos;

  PikPakPreparedSource({
    required this.fileId,
    required Iterable<PikPakSourceVideo> videos,
  }) : videos = List.unmodifiable(videos);
}

class PikPakSourceVideo {
  final String? id;
  final String? name;
  final String? relativePath;
  final int? sizeBytes;

  const PikPakSourceVideo({
    this.id,
    this.name,
    this.relativePath,
    this.sizeBytes,
  });
}

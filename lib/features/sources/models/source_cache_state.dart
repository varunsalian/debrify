import '../../../models/torrent.dart';

class SourceCacheState {
  final bool torboxEnabled;
  final bool premiumizeEnabled;
  final Map<String, bool> torbox;
  final Map<String, bool> premiumize;
  // Legacy map updates became readable immediately, but explicitly repainted
  // the screen only after both sequential provider attempts finished.
  final int repaintRevision;

  const SourceCacheState.empty({
    this.repaintRevision = 0,
    this.torboxEnabled = false,
    this.premiumizeEnabled = false,
  }) : torbox = const {},
       premiumize = const {};

  SourceCacheState._(
    this.torboxEnabled,
    this.premiumizeEnabled,
    this.torbox,
    this.premiumize,
    this.repaintRevision,
  );

  SourceCacheState copyWith({
    bool? torboxEnabled,
    bool? premiumizeEnabled,
    Map<String, bool>? torbox,
    Map<String, bool>? premiumize,
    int? repaintRevision,
  }) => SourceCacheState._(
    torboxEnabled ?? this.torboxEnabled,
    premiumizeEnabled ?? this.premiumizeEnabled,
    torbox == null ? this.torbox : Map.unmodifiable(torbox),
    premiumize == null ? this.premiumize : Map.unmodifiable(premiumize),
    repaintRevision ?? this.repaintRevision,
  );

  String? label(Torrent torrent) {
    if (!torrent.hasRealInfoHash) return null;
    final hash = torrent.infohash.trim().toLowerCase();
    if (hash.isEmpty) return null;
    final labels = [
      if (torboxEnabled && (torbox[hash] ?? false)) 'TB',
      if (premiumizeEnabled && (premiumize[hash] ?? false)) 'PM',
    ];
    return labels.isEmpty ? null : labels.join(' | ');
  }
}

import '../../../models/torrent_filter_state.dart';

abstract interface class KeywordDefaultsRepository {
  bool get isCurrent;
  Future<TorrentFilterState> load();
}

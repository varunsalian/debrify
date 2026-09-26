import 'dart:async';

import 'package:debrify/features/search/data/keyword_defaults_repository.dart';
import 'package:debrify/models/torrent_filter_state.dart';

class FakeKeywordDefaultsRepository implements KeywordDefaultsRepository {
  @override
  bool isCurrent = true;
  bool delayed = true;
  final reads = <Completer<TorrentFilterState>>[];

  @override
  Future<TorrentFilterState> load() {
    final read = Completer<TorrentFilterState>();
    reads.add(read);
    if (!delayed) read.complete(const TorrentFilterState.empty());
    return read.future;
  }
}

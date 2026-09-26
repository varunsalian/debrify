import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/system_clipboard.dart';
import '../../../services/iptv_source_search.dart';
import '../data/source_link_copier.dart';

/// App-scoped immutable dependencies only. Each copy gets its view/session guard.
final sourceLinkCopierProvider = Provider<SourceLinkCopier>(
  (ref) => SourceLinkCopier(
    isDeferredEpisode: IptvSourceSearch.isDeferredXtreamSeries,
    resolveEpisode: IptvSourceSearch.resolveXtreamSeriesEpisode,
    writeText: writeSystemClipboardText,
  ),
);

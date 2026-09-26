import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/iptv_source_search.dart';
import '../../../services/media_server_service.dart';
import '../data/source_binding_matcher.dart';

/// App-scoped stateless adapter. Identity lookups occur on demand, never cached.
final sourceBindingMatcherProvider = Provider<SourceBindingMatcher>(
  (ref) => SourceBindingMatcher(
    mediaServerKeyFor: (torrent) =>
        MediaServerService.bindingFor(torrent)?.bindingKey,
    isIptv: IptvSourceSearch.owns,
  ),
  dependencies: const [],
);

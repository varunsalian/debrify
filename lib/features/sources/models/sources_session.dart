import '../../../models/advanced_search_selection.dart';
import '../../../models/stremio_addon.dart';
import '../../../services/profiles/profile_session_memory.dart';

class SourcesSession {
  final ProfileSessionOwner owner;
  final Object viewIdentity;
  final AdvancedSearchSelection selection;
  final StremioMeta? catalogItem;
  final String? metadataAddonId;
  final bool keywordMode;

  const SourcesSession({
    required this.owner,
    required this.viewIdentity,
    required this.selection,
    this.catalogItem,
    this.metadataAddonId,
    this.keywordMode = false,
  });

  bool get hasSeasonScope =>
      !keywordMode && selection.isSeries && selection.episode == null;

  @override
  bool operator ==(Object other) =>
      other is SourcesSession &&
      other.owner == owner &&
      identical(other.viewIdentity, viewIdentity);
  @override
  int get hashCode => Object.hash(owner, identityHashCode(viewIdentity));
}

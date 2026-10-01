import 'package:debrify/features/home/data/home_iptv_lists_repository.dart';
import 'package:debrify/features/home/models/home_iptv_list.dart';
import 'package:debrify/models/home_preferences.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';

typedef SavedChannels = Map<String, Map<String, dynamic>>;
SavedChannels saved(String name) => {
  'url:$name': {'name': name},
};
HomeIptvListMeta meta(String id, {String? title}) =>
    (id: id, title: title ?? id, isFavorites: false);
HomeIptvListsRepository repository({
  Future<List<HomeExtraRow>> Function()? extras,
  Future<List<HomeIptvListMeta>> Function()? lists,
  required Future<SavedChannels> Function(String) channels,
}) => HomeIptvListsRepository(
  extras: extras ?? () async => [(id: 'iptvlist:a', title: 'opt-in label')],
  lists: lists ?? () async => [meta('a')],
  channels: channels,
  headers: IptvFavoritesStorage.iptvFavoriteHeaders,
  favoritesListId: 'favorites',
);

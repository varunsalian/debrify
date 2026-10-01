import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/profile_policy_storage.dart';

final class LemmyStorage {
  const LemmyStorage._();
  // Lemmy settings
  static const String _lemmyInstanceKey = 'lemmy_instance';
  static const String _lemmyAllowNsfwKey = 'lemmy_allow_nsfw';
  static const String _lemmyFavoriteCommunitiesKey =
      'lemmy_favorite_communities';
  static const String _lemmyDefaultCommunityKey = 'lemmy_default_community';

  // Lemmy Settings
  static Future<String> getLemmyInstance() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_lemmyInstanceKey);
    return (value != null && value.isNotEmpty) ? value : 'https://lemmy.world';
  }

  static Future<void> setLemmyInstance(String instance) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_lemmyInstanceKey, instance);
  }

  static Future<bool> getLemmyAllowNsfw() async {
    if (!await ProfilePolicyStorage.profileAllowsAdultContent()) return false;
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_lemmyAllowNsfwKey) ?? false;
  }

  static Future<void> setLemmyAllowNsfw(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(
      _lemmyAllowNsfwKey,
      await ProfilePolicyStorage.profileAllowsAdultContent() && value,
    );
  }

  static Future<List<String>> getLemmyFavoriteCommunities() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getStringList(_lemmyFavoriteCommunitiesKey) ?? [];
  }

  static Future<void> setLemmyFavoriteCommunities(
    List<String> communities,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_lemmyFavoriteCommunitiesKey, communities);
  }

  static Future<String?> getLemmyDefaultCommunity() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_lemmyDefaultCommunityKey);
  }

  static Future<void> setLemmyDefaultCommunity(String? community) async {
    final prefs = await ProfilePreferences.instance();
    if (community == null || community.isEmpty) {
      await prefs.remove(_lemmyDefaultCommunityKey);
    } else {
      await prefs.setString(_lemmyDefaultCommunityKey, community);
    }
  }
}

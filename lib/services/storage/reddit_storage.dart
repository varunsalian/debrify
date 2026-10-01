import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/profile_policy_storage.dart';

final class RedditStorage {
  const RedditStorage._();

  // Reddit settings
  static const String _redditAccessTokenKey = 'reddit_access_token';
  static const String _redditRefreshTokenKey = 'reddit_refresh_token';
  static const String _redditUsernameKey = 'reddit_username';
  static const String _redditEnabledKey = 'reddit_enabled';
  static const String _redditHiddenFromNavKey = 'reddit_hidden_from_nav';
  static const String _redditLastSubredditKey = 'reddit_last_subreddit';
  static const String _redditRecentSubredditsKey = 'reddit_recent_subreddits';
  static const String _redditAllowNsfwKey = 'reddit_allow_nsfw';
  static const String _redditFavoriteSubredditsKey = 'reddit_favorite_subreddits';
  static const String _redditDefaultSubredditKey = 'reddit_default_subreddit';

  // Reddit Settings
  static Future<String?> getRedditAccessToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _redditAccessTokenKey);
  }

  static Future<void> setRedditAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _redditAccessTokenKey, token);
  }

  static Future<String?> getRedditRefreshToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _redditRefreshTokenKey);
  }

  static Future<void> setRedditRefreshToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _redditRefreshTokenKey, token);
  }

  static Future<String?> getRedditUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_redditUsernameKey);
  }

  static Future<void> setRedditUsername(String username) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_redditUsernameKey, username);
  }

  static Future<bool> getRedditEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_redditEnabledKey) ?? true; // Default enabled
  }

  static Future<void> setRedditEnabled(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_redditEnabledKey, value);
  }

  static Future<bool> getRedditHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_redditHiddenFromNavKey) ?? false;
  }

  static Future<void> setRedditHiddenFromNav(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_redditHiddenFromNavKey, value);
  }

  static Future<String?> getRedditLastSubreddit() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_redditLastSubredditKey);
  }

  static Future<void> setRedditLastSubreddit(String subreddit) async {
    final prefs = await ProfilePreferences.instance();
    if (prefs.getString(_redditLastSubredditKey) == subreddit) return;
    await prefs.setString(_redditLastSubredditKey, subreddit);
  }

  static Future<void> clearRedditAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_redditAccessTokenKey)) {
      await prefs.remove(_redditAccessTokenKey);
      await prefs.remove(_redditRefreshTokenKey);
    }
    await prefs.remove(_redditUsernameKey);
  }

  static Future<List<String>> getRedditRecentSubreddits() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getStringList(_redditRecentSubredditsKey) ?? [];
  }

  static Future<void> setRedditRecentSubreddits(List<String> subreddits) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_redditRecentSubredditsKey, subreddits);
  }

  static Future<bool> getRedditAllowNsfw() async {
    if (!await ProfilePolicyStorage.profileAllowsAdultContent()) return false;
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_redditAllowNsfwKey) ?? false;
  }

  static Future<void> setRedditAllowNsfw(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(
      _redditAllowNsfwKey,
      await ProfilePolicyStorage.profileAllowsAdultContent() && value,
    );
  }

  static Future<List<String>> getRedditFavoriteSubreddits() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getStringList(_redditFavoriteSubredditsKey) ?? [];
  }

  static Future<void> setRedditFavoriteSubreddits(
    List<String> subreddits,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_redditFavoriteSubredditsKey, subreddits);
  }

  static Future<String?> getRedditDefaultSubreddit() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_redditDefaultSubredditKey);
  }

  static Future<void> setRedditDefaultSubreddit(String? subreddit) async {
    final prefs = await ProfilePreferences.instance();
    if (subreddit == null || subreddit.isEmpty) {
      await prefs.remove(_redditDefaultSubredditKey);
    } else {
      await prefs.setString(_redditDefaultSubredditKey, subreddit);
    }
  }
}

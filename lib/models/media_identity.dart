/// Validated provider identities. Native IDs are never sent as IMDb IDs.
class MediaIdentity {
  MediaIdentity._();
  static bool isImdb(String? id) =>
      id != null && RegExp(r'^tt[0-9]+$').hasMatch(id);
  static bool isNative(String? id) =>
      id != null &&
      RegExp(r'^(?:tmdb:(?:movie:)?|simkl:)[1-9][0-9]*$').hasMatch(id);

  /// TMDB movie and TV numbers are separate namespaces. Keep the existing
  /// TV key, and qualify movie progress keys without changing catalog IDs.
  static String progressId(String id, String contentType) {
    final normalized = id.trim().toLowerCase();
    return contentType.trim().toLowerCase() == 'movie' &&
            RegExp(r'^tmdb:[1-9][0-9]*$').hasMatch(normalized)
        ? normalized.replaceFirst('tmdb:', 'tmdb:movie:')
        : id;
  }

  /// Provider requests still use the ordinary TMDB identifier.
  static String providerId(String id) =>
      RegExp(r'^tmdb:movie:[1-9][0-9]*$').hasMatch(id)
      ? id.replaceFirst('tmdb:movie:', 'tmdb:')
      : id;

  static int? positiveInt(Object? value) {
    final text = value?.toString() ?? '';
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(text)) return null;
    return int.tryParse(text);
  }

  static Set<String> aliases(dynamic ids) {
    if (ids is! Map) return {};
    final imdb = ids['imdb'] is String
        ? (ids['imdb'] as String).trim().toLowerCase()
        : null;
    return {
      if (isImdb(imdb)) imdb!,
      for (final provider in ['tmdb', 'simkl'])
        if (positiveInt(ids[provider]) case final int id) '$provider:$id',
    };
  }

  static String? preferred(dynamic ids) => aliases(ids).firstOrNull;
  static bool matches(dynamic ids, String id) =>
      aliases(ids).contains(providerId(id));
  static Map<String, dynamic> apiIds(String id) {
    if (isImdb(id)) return {'imdb': id};
    if (isNative(id)) {
      final parts = id.split(':');
      return {parts.first: int.parse(parts.last)};
    }
    throw ArgumentError.value(id, 'id', 'Unsupported media identity');
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/stream_badge_rules.dart';
import 'profiles/profile_preferences.dart';
import 'stream_badge_matcher.dart';

/// One imported badges file: where it came from and its cached content, so
/// the rules keep working offline and a URL source can be refreshed.
class StreamBadgeSource {
  final String id;
  final String name;

  /// Set for URL imports; null for pasted or file imports.
  final String? url;

  /// The badges.json text as last fetched/pasted.
  final String json;
  final bool enabled;
  final int? fetchedAtMs;

  const StreamBadgeSource({
    required this.id,
    required this.name,
    required this.json,
    this.url,
    this.enabled = true,
    this.fetchedAtMs,
  });

  StreamBadgeSource copyWith({
    String? name,
    String? json,
    bool? enabled,
    int? fetchedAtMs,
  }) => StreamBadgeSource(
    id: id,
    name: name ?? this.name,
    url: url,
    json: json ?? this.json,
    enabled: enabled ?? this.enabled,
    fetchedAtMs: fetchedAtMs ?? this.fetchedAtMs,
  );

  static StreamBadgeSource? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final json = raw['json'];
    if (id is! String || id.isEmpty || json is! String) return null;
    final fetched = raw['fetchedAt'];
    return StreamBadgeSource(
      id: id,
      name: raw['name'] is String ? raw['name'] as String : id,
      url: raw['url'] is String ? raw['url'] as String : null,
      json: json,
      enabled: raw['enabled'] != false,
      fetchedAtMs: fetched is num ? fetched.toInt() : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (url != null) 'url': url,
    'json': json,
    'enabled': enabled,
    if (fetchedAtMs != null) 'fetchedAt': fetchedAtMs,
  };
}

/// Result of an import, for the settings page's dialog.
class StreamBadgeImportResult {
  final StreamBadgeSource source;
  final StreamBadgeRuleset ruleset;
  final bool replaced;

  const StreamBadgeImportResult({
    required this.source,
    required this.ruleset,
    required this.replaced,
  });
}

/// Profile-scoped store of imported badge rulesets plus the live matcher the
/// source lists read synchronously.
///
/// Sources live under `stream_badge_sources_v1` as one JSON string in
/// [ProfilePreferences]. [matcher] is rebuilt whenever the sources change and
/// warmed once at startup, because the rows that draw badges cannot await
/// storage.
class StreamBadgesService {
  StreamBadgesService({http.Client Function()? httpClientFactory})
    : _httpClientFactory = httpClientFactory ?? http.Client.new;

  static final StreamBadgesService instance = StreamBadgesService();

  static const String sourcesKey = 'stream_badge_sources_v1';
  static const String enabledKey = 'stream_badges_enabled';
  static const int maxImportBytes = 4 * 1024 * 1024;
  static const Duration _fetchTimeout = Duration(seconds: 20);

  final http.Client Function() _httpClientFactory;

  /// The rules currently in force; [StreamBadgeMatcher.empty] when the
  /// feature is off or nothing is imported.
  final ValueNotifier<StreamBadgeMatcher> matcher = ValueNotifier(
    StreamBadgeMatcher.empty,
  );

  bool _enabled = true;
  bool _warmed = false;

  /// The master switch (Settings › Play Loader › Stream badges). On by
  /// default: importing a file is the opt-in.
  bool get enabled => _enabled;

  Future<void> warmUp() async {
    if (_warmed) return;
    _warmed = true;
    try {
      final prefs = await ProfilePreferences.instance();
      _enabled = prefs.getBool(enabledKey) ?? true;
    } catch (_) {
      _enabled = true;
    }
    await _rebuild(await getSources());
  }

  void resetProfileScope() {
    _warmed = false;
    _enabled = true;
    matcher.value = StreamBadgeMatcher.empty;
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(enabledKey, value);
    await _rebuild(await getSources());
  }

  // ── Sources ────────────────────────────────────────────────────────────

  Future<List<StreamBadgeSource>> getSources() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(sourcesKey);
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      final seen = <String>{};
      return [
        for (final raw in decoded)
          if (StreamBadgeSource.fromJson(raw) case final s?)
            if (seen.add(s.id)) s,
      ];
    } catch (e) {
      debugPrint('StreamBadgesService: error reading sources: $e');
      return const [];
    }
  }

  Future<void> _save(List<StreamBadgeSource> sources) async {
    final prefs = await ProfilePreferences.instance();
    if (sources.isEmpty) {
      await prefs.remove(sourcesKey);
    } else {
      await prefs.setString(
        sourcesKey,
        jsonEncode([for (final s in sources) s.toJson()]),
      );
    }
    await _rebuild(sources);
  }

  Future<void> _rebuild(List<StreamBadgeSource> sources) async {
    if (!_enabled) {
      matcher.value = StreamBadgeMatcher.empty;
      return;
    }
    // A source that no longer parses contributes nothing.
    matcher.value = StreamBadgeMatcher([
      for (final s in sources)
        if (s.enabled)
          if (StreamBadgeRuleset.tryParse(s.json) case final set?) set,
    ]);
  }

  /// Parse and store pasted/file text. Same [id] (derived from the URL, or
  /// the given name) replaces in place.
  Future<StreamBadgeImportResult> importJson(
    String jsonText, {
    required String name,
    String? url,
  }) async {
    if (jsonText.length > maxImportBytes) {
      throw const FormatException(
        'That file is too large to be a badges file.',
      );
    }
    final ruleset = StreamBadgeRuleset.parse(jsonText);
    final id = url != null ? _idFor(url) : _idFor(name);
    final current = List<StreamBadgeSource>.of(await getSources());
    final index = current.indexWhere((s) => s.id == id);
    final source = StreamBadgeSource(
      id: id,
      name: name,
      url: url,
      json: jsonText,
      enabled: index >= 0 ? current[index].enabled : true,
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (index >= 0) {
      current[index] = source;
    } else {
      current.add(source);
    }
    await _save(current);
    return StreamBadgeImportResult(
      source: source,
      ruleset: ruleset,
      replaced: index >= 0,
    );
  }

  /// Download and store a badges file. Throws [FormatException] for a bad
  /// link, response or document.
  Future<StreamBadgeImportResult> importFromUrl(String url) async {
    final text = await _fetch(url);
    final name = _nameFor(url);
    return importJson(text, name: name, url: url.trim());
  }

  /// Re-download a URL source. Pasted sources are left as they are.
  Future<StreamBadgeImportResult?> refresh(String id) async {
    final sources = await getSources();
    final source = sources.cast<StreamBadgeSource?>().firstWhere(
      (s) => s!.id == id,
      orElse: () => null,
    );
    if (source == null || source.url == null) return null;
    final text = await _fetch(source.url!);
    return importJson(text, name: source.name, url: source.url);
  }

  Future<void> remove(String id) async {
    await _save([
      for (final s in await getSources())
        if (s.id != id) s,
    ]);
  }

  Future<void> setSourceEnabled(String id, bool enabled) async {
    await _save([
      for (final s in await getSources())
        if (s.id == id) s.copyWith(enabled: enabled) else s,
    ]);
  }

  Future<void> clear() => _save(const []);

  // ── Backup ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> exportJson() async => [
    for (final s in await getSources()) s.toJson(),
  ];

  /// Restore from a backup list, merging by id.
  Future<({int imported, int alreadyPresent, int failed})> applyBackup(
    List<dynamic> list,
  ) async {
    final current = List<StreamBadgeSource>.of(await getSources());
    var imported = 0, present = 0, failed = 0;
    for (final raw in list) {
      final s = StreamBadgeSource.fromJson(raw);
      if (s == null) {
        failed++;
        continue;
      }
      final i = current.indexWhere((e) => e.id == s.id);
      if (i >= 0) {
        current[i] = s;
        present++;
      } else {
        current.add(s);
        imported++;
      }
    }
    if (imported > 0 || present > 0) await _save(current);
    return (imported: imported, alreadyPresent: present, failed: failed);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Future<String> _fetch(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const FormatException('Enter an http(s) link to a badges JSON.');
    }
    final client = _httpClientFactory();
    try {
      final response = await client.get(uri).timeout(_fetchTimeout);
      if (response.statusCode != 200) {
        throw FormatException(
          'The server answered ${response.statusCode} for that link.',
        );
      }
      if (response.bodyBytes.length > maxImportBytes) {
        throw const FormatException(
          'That file is too large to be a badges file.',
        );
      }
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Could not download that link: $e');
    } finally {
      client.close();
    }
  }

  static String _idFor(String seed) =>
      seed.trim().toLowerCase().hashCode.toRadixString(16);

  static String _nameFor(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return 'Badges';
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // github.com/<owner>/<repo>/... → "owner/repo"; otherwise the host.
    if (uri.host.contains('github') && segments.length >= 2) {
      return '${segments[0]}/${segments[1]}';
    }
    return uri.host;
  }
}

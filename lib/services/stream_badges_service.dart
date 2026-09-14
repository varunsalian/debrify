import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:synchronized/synchronized.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_scope.dart';

import '../models/stream_badge_rules.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/portable_profile_package.dart';
import 'stream_badge_matcher.dart';
import 'remote_control/remote_constants.dart';

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
/// source lists observe for asynchronous matching.
///
/// Sources live under `stream_badge_sources_v1` as one JSON string in
/// [ProfilePreferences]. [matcher] is rebuilt whenever the sources change and
/// warmed once at startup so source rows never need to read storage.
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

  static final Lock _mutations = Lock(reentrant: true);
  bool _enabled = true;
  bool _warmed = false;
  String? _publishedConfiguration;
  int _generation = 0;
  bool get enabled => _enabled;

  _BadgeContext _capture() => (
    scope: ProfileRuntime.isProfileCommitted ? ProfileRuntime.capture() : null,
    active: ProfileRuntime.scope.value,
    generation: _generation,
  );

  void _check(_BadgeContext context) {
    if (context != _capture()) {
      throw StateError('The profile changed. Import the badges again.');
    }
  }

  Future<ProfilePreferences> _preferences(_BadgeContext context) async {
    _check(context);
    final prefs = await ProfilePreferences.instance();
    _check(context);
    return prefs;
  }

  void _publish(ProfilePreferences prefs, _BadgeContext context) {
    _check(context);
    // Restore can write an invisible generation or an inactive profile.
    // Its data must never replace the active profile's process-wide matcher.
    if (context.scope != context.active) return;
    final enabled = prefs.getBool(enabledKey) ?? true;
    final sources = _decode(prefs.getString(sourcesKey));
    final configuration = jsonEncode([
      enabled,
      if (enabled)
        for (final source in sources)
          if (source.enabled) source.json,
    ]);
    if (_warmed &&
        configuration == _publishedConfiguration &&
        !matcher.value.failed) {
      return;
    }
    _publishedConfiguration = configuration;
    final next = enabled
        ? StreamBadgeMatcher([
            for (final s in sources)
              if (s.enabled)
                if (StreamBadgeRuleset.tryParse(s.json) case final rules?)
                  rules,
          ])
        : StreamBadgeMatcher.empty;
    _enabled = enabled;
    _warmed = true;
    final old = matcher.value;
    matcher.value = next;
    if (!identical(old, StreamBadgeMatcher.empty)) old.dispose();
  }

  Future<void> warmUp() async {
    if (_warmed) return;
    await refreshFromPreferences();
  }

  /// Read-only: safe inside WebDAV's preference barrier. Never wait on a
  /// badge writer here; that writer may itself be waiting on the barrier.
  Future<void> refreshFromPreferences() async {
    final context = _capture();
    final prefs = await _preferences(context);
    try {
      _publish(prefs, context);
    } on FormatException {
      // Corrupt optional decoration data must not prevent application startup.
      // Keep it on disk so settings can offer an explicit reset.
      _check(context);
      if (context.scope == context.active) {
        _enabled = prefs.getBool(enabledKey) ?? true;
        _warmed = true;
        _publishedConfiguration = null;
        final old = matcher.value;
        matcher.value = StreamBadgeMatcher.empty;
        if (!identical(old, StreamBadgeMatcher.empty)) old.dispose();
      }
    }
  }

  void resetProfileScope() {
    _generation++;
    _warmed = false;
    _publishedConfiguration = null;
    _enabled = true;
    final old = matcher.value;
    matcher.value = StreamBadgeMatcher.empty;
    if (!identical(old, StreamBadgeMatcher.empty)) old.dispose();
  }

  Future<void> setEnabled(bool value) {
    final context = _capture();
    return _mutations.synchronized(() async {
      final prefs = await _preferences(context);
      if (!await prefs.setBool(enabledKey, value)) {
        throw StateError('Could not save the stream badge setting.');
      }
      _publish(prefs, context);
    });
  }

  static List<StreamBadgeSource> _decode(String? source) {
    if (source == null || source.isEmpty) return [];
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Invalid badge inventory');
    }
    final out = <StreamBadgeSource>[];
    final seen = <String>{};
    for (final raw in decoded) {
      final item = StreamBadgeSource.fromJson(raw);
      if (item == null) throw const FormatException('Invalid badge source');
      if (seen.add(item.id)) out.add(item);
    }
    return out;
  }

  Future<List<StreamBadgeSource>> getSources() async {
    final context = _capture();
    final prefs = await _preferences(context);
    return _decode(prefs.getString(sourcesKey));
  }

  static int _activeRuleCount(List<StreamBadgeSource> sources) =>
      sources.fold<int>(
        0,
        (count, source) =>
            count +
            (source.enabled
                ? (StreamBadgeRuleset.tryParse(source.json)?.rules
                          .where((rule) => rule.enabled && rule.regex != null)
                          .length ??
                      0)
                : 0),
      );

  Future<T> _mutate<T>(
    _BadgeContext context,
    (List<StreamBadgeSource>, T) Function(List<StreamBadgeSource>) update, {
    bool replaceAll = false,
  }) => _mutations.synchronized(() async {
    final prefs = await _preferences(context);
    late T result;
    final success = await prefs.mutateStringAtomically(sourcesKey, (old) {
      _check(context);
      final previous = replaceAll ? <StreamBadgeSource>[] : _decode(old);
      final previousCount = _activeRuleCount(previous);
      final (sources, value) = update(previous);
      final ruleCount = _activeRuleCount(sources);
      // Older/synced inventories can already exceed the cap. Allow users to
      // disable or remove presets in stages while refusing further growth.
      if (ruleCount > StreamBadgeMatcher.maxRules &&
          ruleCount > previousCount) {
        throw const FormatException(
          'Badge presets can have up to 512 active rules per profile.',
        );
      }
      final encoded = jsonEncode([for (final s in sources) s.toJson()]);
      // Backups carry this inventory as a single preference string. Use the
      // same UTF-8 bound as their validator, including JSON escaping/metadata.
      final storedBytes = utf8.encode(encoded).length;
      if (storedBytes > PortableProfilePackage.maxStringBytes &&
          storedBytes >= utf8.encode(old ?? '').length) {
        throw const FormatException(
          'Badge presets exceed the profile backup size limit (4 MiB). '
          'Remove a preset or import a smaller file.',
        );
      }
      result = value;
      return encoded;
    });
    if (!success) {
      throw StateError(
        'Could not save badge presets: device storage limit reached.',
      );
    }
    _publish(prefs, context);
    return result;
  });

  Future<StreamBadgeImportResult> importJson(
    String jsonText, {
    required String name,
    String? url,
  }) => _import(_capture(), jsonText, name: name, url: url);

  Future<StreamBadgeImportResult> _import(
    _BadgeContext context,
    String jsonText, {
    required String name,
    String? url,
    StreamBadgeSource? expectedSource,
  }) {
    _check(context);
    if (utf8.encode(jsonText).length > maxImportBytes) {
      throw const FormatException(
        'That file is too large to be a badges file.',
      );
    }
    final ruleset = StreamBadgeRuleset.parse(jsonText);
    final id = url != null ? _idFor(url) : _idFor(name);
    return _mutate(context, (current) {
      final index = current.indexWhere((s) => s.id == id);
      if (expectedSource != null &&
          (index < 0 ||
              jsonEncode(current[index].toJson()) !=
                  jsonEncode(expectedSource.toJson()))) {
        throw StateError('This preset changed while refreshing. Try again.');
      }
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
      return (
        current,
        StreamBadgeImportResult(
          source: source,
          ruleset: ruleset,
          replaced: index >= 0,
        ),
      );
    });
  }

  Future<StreamBadgeImportResult> importFromUrl(String url) async {
    final context = _capture();
    final text = await _fetch(url);
    return _import(context, text, name: _nameFor(url), url: url.trim());
  }

  Future<StreamBadgeImportResult?> refresh(String id) async {
    final context = _capture();
    final prefs = await _preferences(context);
    final sources = _decode(prefs.getString(sourcesKey));
    final source = sources.where((s) => s.id == id).firstOrNull;
    if (source == null || source.url == null) return null;
    final text = await _fetch(source.url!);
    return _import(
      context,
      text,
      name: source.name,
      url: source.url,
      expectedSource: source,
    );
  }

  Future<void> remove(String id) => _mutate<void>(
    _capture(),
    (sources) => (sources.where((s) => s.id != id).toList(), null),
  );
  Future<void> setSourceEnabled(String id, bool enabled) => _mutate<void>(
    _capture(),
    (sources) => (
      [for (final s in sources) s.id == id ? s.copyWith(enabled: enabled) : s],
      null,
    ),
  );
  Future<void> clear() => _mutate<void>(
    _capture(),
    (_) => (<StreamBadgeSource>[], null),
    replaceAll: true,
  );

  Future<List<Map<String, dynamic>>> exportJson() async => [
    for (final s in await getSources()) s.toJson(),
  ];

  /// Use the authenticated peer capability, never an app-version guess.
  /// Older receivers accept only source arrays and retain their master switch.
  Future<List<Map<String, dynamic>>> exportTransferJson({
    required int peerProtocolVersion,
  }) {
    final context = _capture();
    return _mutations.synchronized(() async {
      final prefs = await _preferences(context);
      final sources = [
        for (final source in _decode(prefs.getString(sourcesKey)))
          source.toJson(),
      ];
      if (peerProtocolVersion < kStreamBadgeEnvelopeProtocolVersion) {
        return sources;
      }
      return [
        {
          'badgeTransferVersion': 1,
          'enabled': prefs.getBool(enabledKey) ?? true,
          'sources': sources,
        },
      ];
    });
  }

  Future<({int imported, int alreadyPresent, int failed})> applyBackup(
    List<dynamic> list,
  ) {
    final context = _capture();
    return _mutations.synchronized(() => _applyBackup(context, list));
  }

  Future<({int imported, int alreadyPresent, int failed})> _applyBackup(
    _BadgeContext context,
    List<dynamic> list,
  ) async {
    _check(context);
    bool? enabled;
    if (list.length == 1 &&
        list.first is Map &&
        (list.first as Map).containsKey('badgeTransferVersion')) {
      final envelope = list.first as Map;
      if (envelope['badgeTransferVersion'] != 1 ||
          envelope['enabled'] is! bool ||
          envelope['sources'] is! List) {
        throw const FormatException('Unsupported badge transfer');
      }
      enabled = envelope['enabled'] as bool;
      list = envelope['sources'] as List;
    }
    final incoming = <StreamBadgeSource>[];
    var failed = 0;
    for (final raw in list) {
      final s = StreamBadgeSource.fromJson(raw);
      if (s == null ||
          utf8.encode(s.json).length > maxImportBytes ||
          StreamBadgeRuleset.tryParse(s.json) == null) {
        failed++;
        continue;
      }
      incoming.add(s);
    }
    final counts = await _mutate(context, (current) {
      var imported = 0, present = 0;
      for (final s in incoming) {
        final i = current.indexWhere((e) => e.id == s.id);
        if (i >= 0) {
          current[i] = s;
          present++;
        } else {
          current.add(s);
          imported++;
        }
      }
      return (
        current,
        (imported: imported, alreadyPresent: present, failed: failed),
      );
    });
    if (enabled != null) {
      _check(context);
      await setEnabled(enabled);
    }
    return counts;
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Future<String> _fetch(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const FormatException('Enter an http(s) link to a badges JSON.');
    }
    final client = _httpClientFactory();
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(_fetchTimeout);
      if (response.statusCode != 200) {
        throw FormatException(
          'The server answered ${response.statusCode} for that link.',
        );
      }
      final bytes = await (() async {
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > maxImportBytes) {
            throw const FormatException(
              'That file is too large to be a badges file.',
            );
          }
          bytes.addAll(chunk);
        }
        return bytes;
      })().timeout(_fetchTimeout);
      return utf8.decode(bytes);
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

typedef _BadgeContext = ({
  ProfileScope? scope,
  ProfileScope? active,
  int generation,
});

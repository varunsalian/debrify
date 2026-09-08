import 'package:flutter/material.dart';

import '../../models/metadata_preferences.dart';
import '../../models/stremio_addon.dart';
import '../../services/metadata_preferences_service.dart';
import '../../services/stremio_service.dart';
import '../../services/tmdb_metadata_repository.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/metadata_details_service.dart';
import '../../widgets/collections/tmdb_attribution.dart';

class MetadataSettingsPage extends StatefulWidget {
  const MetadataSettingsPage({super.key, this.repository});
  final TmdbMetadataRepository? repository;
  @override
  State<MetadataSettingsPage> createState() => _MetadataSettingsPageState();
}

class _MetadataSettingsPageState extends State<MetadataSettingsPage> {
  TmdbMetadataRepository get _repository =>
      widget.repository ?? TmdbMetadataRepository.instance;
  MetadataPreferences? _preferences;
  List<StremioAddon> _addons = [];
  bool _saving = false;
  String? _error;
  Object? _loadedScope;
  int _loadGeneration = 0;
  int? _loadedRevision;
  Map<String, String> _languageOptions = {..._languages};
  Map<String, String>? _regionOptions;

  @override
  void initState() {
    super.initState();
    ProfileRuntime.scope.addListener(_load);
    MetadataPreferencesService.revision.addListener(_load);
    _load();
    _loadConfiguration();
  }

  @override
  void dispose() {
    ProfileRuntime.scope.removeListener(_load);
    MetadataPreferencesService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _loadConfiguration() async {
    if (!_repository.configured) return;
    try {
      final data = await Future.wait([
        _repository.get('configuration/languages'),
        _repository.get('configuration/countries'),
      ]);
      if (!mounted) return;
      final languages = <String, String>{..._languages};
      for (final row in MetadataDetailsService.maps(data[0]['results'])) {
        final code = MetadataDetailsService.text(row['iso_639_1']);
        final name = MetadataDetailsService.text(row['english_name']);
        if (code != null && name != null) languages[code] = name;
      }
      final regions = <String, String>{};
      for (final row in MetadataDetailsService.maps(data[1]['results'])) {
        final code = MetadataDetailsService.text(row['iso_3166_1']);
        final name = MetadataDetailsService.text(row['english_name']);
        if (code != null && name != null) regions[code] = name;
      }
      setState(() {
        _languageOptions = languages;
        if (regions.isNotEmpty) _regionOptions = regions;
      });
    } catch (_) {
      // Offline settings retain the built-in choices.
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final scope = ProfileRuntime.scope.value;
    final revision = MetadataPreferencesService.revision.value;
    try {
      final prefs = await MetadataPreferencesService.load();
      final addons = await StremioService.instance.getEnabledAddons();
      if (!mounted ||
          generation != _loadGeneration ||
          scope != ProfileRuntime.scope.value) {
        return;
      }
      setState(() {
        _loadedScope = scope;
        _loadedRevision = revision;
        _preferences = prefs;
        _addons = addons.where((a) => a.resources.contains('meta')).toList();
        _error = null;
      });
    } catch (_) {
      if (mounted &&
          generation == _loadGeneration &&
          scope == ProfileRuntime.scope.value) {
        setState(() => _error = 'Could not load metadata settings.');
      }
    }
  }

  Future<void> _save(MetadataPreferences next) async {
    if (_saving || _loadedScope != ProfileRuntime.scope.value ||
        _loadedRevision != MetadataPreferencesService.revision.value) {
      return;
    }
    final scope = _loadedScope;
    setState(() => _saving = true);
    try {
      await MetadataPreferencesService.save(next);
      if (mounted && scope == ProfileRuntime.scope.value) {
        setState(() {
          _preferences = next;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && scope == ProfileRuntime.scope.value) {
        setState(() => _error = 'Could not save metadata settings. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, String> _providers(MetadataCategory category) => {
    MetadataPreferences.current: 'Current behaviour',
    if (_repository.configured) MetadataPreferences.tmdb: 'TMDB',
    if (category == MetadataCategory.credits) MetadataPreferences.imdb: 'IMDb',
    if (category == MetadataCategory.episodeArtwork)
      MetadataPreferences.tvmaze: 'TVMaze',
    if (category != MetadataCategory.credits &&
        category != MetadataCategory.recommendations)
      for (final addon in _addons)
        if ((category != MetadataCategory.episodeInformation &&
                category != MetadataCategory.episodeArtwork) ||
            addon.types.contains('series'))
          '${MetadataPreferences.addonPrefix}${StremioService.metadataProviderValue(addon)}':
              addon.name,
  };

  Future<String?> _choose(
    String title,
    String value,
    Map<String, String> options,
  ) => showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final entry in options.entries)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, entry.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    entry.key == value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(entry.value)),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _selection(
    String title,
    String value,
    Map<String, String> options,
    MetadataPreferences Function(String) update, {
    bool enabled = true,
    String? disabledReason,
  }) => ListTile(
    title: Text(title),
    subtitle: Text([
      options[value] ?? 'Selected provider unavailable',
      if (!enabled && disabledReason != null) disabledReason,
    ].join('\n')),
    trailing: const Icon(Icons.chevron_right),
    enabled: enabled && !_saving && _loadedRevision == MetadataPreferencesService.revision.value,
    onTap: !enabled ? null : () async {
      if (_loadedRevision != MetadataPreferencesService.revision.value) return;
      final scope = ProfileRuntime.scope.value;
      final generation = _loadGeneration;
      final selected = await _choose(title, value, options);
      if (!mounted ||
          selected == null ||
          generation != _loadGeneration ||
          scope != ProfileRuntime.scope.value) {
        return;
      }
      await _save(update(selected));
    },
  );

  static const _languages = {
    'en-US': 'English',
    'hi-IN': 'Hindi',
    'kn-IN': 'Kannada',
    'ta-IN': 'Tamil',
    'te-IN': 'Telugu',
    'ml-IN': 'Malayalam',
    'bn-IN': 'Bengali',
    'mr-IN': 'Marathi',
    'es-ES': 'Spanish',
    'fr-FR': 'French',
    'de-DE': 'German',
    'it-IT': 'Italian',
    'pt-BR': 'Portuguese (Brazil)',
    'ja-JP': 'Japanese',
    'ko-KR': 'Korean',
    'zh-CN': 'Chinese',
    'ar-SA': 'Arabic',
    'ru-RU': 'Russian',
  };

  @override
  Widget build(BuildContext context) {
    final prefs = _preferences;
    bool tmdb(MetadataCategory category) =>
        _repository.configured && prefs?.provider(category) == MetadataPreferences.tmdb;
    final artwork = tmdb(MetadataCategory.posters) || tmdb(MetadataCategory.backgrounds);
    final trailers = tmdb(MetadataCategory.trailers);
    final language = _repository.configured && prefs != null && (
        tmdb(MetadataCategory.information) || tmdb(MetadataCategory.episodeInformation) ||
        tmdb(MetadataCategory.credits) || tmdb(MetadataCategory.recommendations) ||
        prefs.features.any((f) => f != MetadataFeature.availability) ||
        (artwork && prefs.artworkLanguage == 'same') ||
        (trailers && prefs.trailerLanguage == 'same'));
    final region = _repository.configured && prefs != null &&
        (prefs.features.contains(MetadataFeature.availability) ||
         prefs.features.contains(MetadataFeature.discovery));
    return Scaffold(
      appBar: AppBar(title: const Text('Metadata')),
      body: prefs == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : TextButton(onPressed: _load, child: Text('$_error Retry')),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Choose who supplies each part of a title. Current behaviour keeps your existing setup. '
                    'These choices do not change playback or watched progress.',
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!),
                  ),
                for (final category in MetadataCategory.values)
                  _selection(
                    category.label,
                    prefs.provider(category),
                    _providers(category),
                    (value) => prefs.copyWith(
                      providers: {...prefs.providers, category: value},
                    ),
                  ),
                SwitchListTile(
                  title: const Text('Use other sources when unavailable'),
                  subtitle: const Text(
                    'Allow fallback when your selected provider has no information.',
                  ),
                  value: prefs.fallback,
                  onChanged: _saving
                      ? null
                      : (value) => _save(prefs.copyWith(fallback: value)),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('TMDB language and region'),
                ),
                _selection(
                  'Metadata language',
                  prefs.language,
                  _languageOptions,
                  (v) => prefs.copyWith(language: v),
                  enabled: language,
                  disabledReason: 'Enable a TMDB feature that uses metadata language.',
                ),
                _selection(
                  'Artwork language',
                  prefs.artworkLanguage,
                  {
                    'same': 'Same as metadata',
                    'original': 'Original language',
                    ..._languageOptions,
                  },
                  (v) => prefs.copyWith(artworkLanguage: v),
                  enabled: artwork,
                  disabledReason: 'Select TMDB for posters or backdrops to change this.',
                ),
                _selection(
                  'Trailer language',
                  prefs.trailerLanguage,
                  {
                    'same': 'Same as metadata',
                    'original': 'Original language',
                    ..._languageOptions,
                  },
                  (v) => prefs.copyWith(trailerLanguage: v),
                  enabled: trailers,
                  disabledReason: 'Select TMDB for trailers to change this.',
                ),
                _selection(
                  'Country / region',
                  prefs.region,
                  _regionOptions ??
                      const {
                        'IN': 'India',
                        'US': 'United States',
                        'GB': 'United Kingdom',
                        'CA': 'Canada',
                        'AU': 'Australia',
                        'DE': 'Germany',
                        'FR': 'France',
                        'ES': 'Spain',
                        'BR': 'Brazil',
                        'JP': 'Japan',
                        'KR': 'South Korea',
                      },
                  (v) => prefs.copyWith(region: v),
                  enabled: region,
                  disabledReason: 'Enable Where to watch or TMDB discovery to change this.',
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Optional features'),
                ),
                for (final feature in MetadataFeature.values)
                  SwitchListTile(
                    title: Text(feature.label),
                    value: prefs.features.contains(feature),
                    onChanged: _saving || !_repository.configured
                        ? null
                        : (value) {
                            final features = {...prefs.features};
                            if (value) {
                              features.add(feature);
                            } else {
                              features.remove(feature);
                            }
                            _save(prefs.copyWith(features: features));
                          },
                  ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => _save(MetadataPreferences()),
                  child: const Text('Restore defaults'),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: TmdbAttribution(),
                ),
              ],
            ),
    );
  }
}

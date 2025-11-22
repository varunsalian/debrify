import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

import '../../models/engine_config/engine_config.dart';
import '../../models/engine_config/default_config.dart';
import 'local_engine_storage.dart';

/// Service for loading and managing YAML engine configuration files.
///
/// This service handles:
/// - Loading _defaults.yaml with fallback to hardcoded defaults
/// - Loading all engine YAML files from local storage (imported from GitLab)
/// - Merging engine configs with defaults
/// - Caching loaded configurations
/// - Graceful error handling for invalid/missing files
class ConfigLoader {
  // Singleton pattern
  static final ConfigLoader _instance = ConfigLoader._internal();
  factory ConfigLoader() => _instance;
  ConfigLoader._internal();

  /// Asset path for default configuration file
  static const String _configBasePath = 'assets/config/engines';

  // Cached configs
  DefaultConfig? _defaultConfig;
  List<EngineConfig>? _engineConfigs;

  /// Hardcoded fallback defaults used when _defaults.yaml is missing or invalid
  static const Map<String, dynamic> _hardcodedDefaults = {
    'version': '1.0',
    'request': {
      'timeout_seconds': 30,
      'user_agent': 'Debrify/1.0',
      'retry_attempts': 3,
      'retry_delay_ms': 1000,
    },
    'tv_mode': {
      'keyword_threshold': 3,
      'channel_batch_size': 5,
      'min_torrents_per_keyword': 1,
      'avoid_nsfw': true,
      'nsfw_category_patterns': ['xxx', 'porn', 'adult', 'nsfw'],
    },
  };

  /// Load defaults from _defaults.yaml (or use hardcoded fallback)
  ///
  /// Returns [DefaultConfig] parsed from _defaults.yaml if available,
  /// otherwise returns hardcoded fallback defaults.
  Future<DefaultConfig> loadDefaults() async {
    try {
      final yamlString = await rootBundle.loadString(
        '$_configBasePath/_defaults.yaml',
      );

      final yamlMap = loadYaml(yamlString);
      if (yamlMap == null) {
        debugPrint(
          'ConfigLoader: _defaults.yaml is empty, using hardcoded defaults',
        );
        return DefaultConfig.fromMap(_hardcodedDefaults);
      }

      final map = _convertYamlToMap(yamlMap);
      debugPrint('ConfigLoader: Loaded defaults from _defaults.yaml');
      return DefaultConfig.fromMap(map);
    } on FlutterError catch (e) {
      // Asset not found
      debugPrint(
        'ConfigLoader: _defaults.yaml not found, using hardcoded defaults: $e',
      );
      return DefaultConfig.fromMap(_hardcodedDefaults);
    } catch (e) {
      debugPrint(
        'ConfigLoader: Error loading _defaults.yaml, using hardcoded defaults: $e',
      );
      return DefaultConfig.fromMap(_hardcodedDefaults);
    }
  }

  /// Load all engine configs from local storage (imported engines)
  ///
  /// Returns a list of [EngineConfig] objects for all valid engine YAML files.
  /// Invalid or missing files are skipped with a warning logged.
  /// Returns an empty list if no valid engine configs are found.
  Future<List<EngineConfig>> loadEngineConfigs() async {
    final configs = <EngineConfig>[];
    final defaults = await getDefaults();
    final localStorage = LocalEngineStorage.instance;

    // Get all imported engine file paths from local storage
    final filePaths = await localStorage.getAllEngineFilePaths();

    if (filePaths.isEmpty) {
      debugPrint('ConfigLoader: No imported engines found in local storage');
      return configs;
    }

    for (final filePath in filePaths) {
      final config = await loadEngineConfigFromFile(filePath);

      if (config != null) {
        // Merge with defaults
        final mergedConfig = mergeWithDefaults(config, defaults);
        configs.add(mergedConfig);
        debugPrint('ConfigLoader: Loaded engine config: ${config.metadata.id}');
      }
    }

    if (configs.isEmpty) {
      debugPrint('ConfigLoader: No valid engine configs found');
    } else {
      debugPrint('ConfigLoader: Loaded ${configs.length} engine configs from local storage');
    }

    return configs;
  }

  /// Load a single engine config from a file path (local storage)
  ///
  /// Returns [EngineConfig] if the file is valid, null otherwise.
  Future<EngineConfig?> loadEngineConfigFromFile(String filePath) async {
    try {
      debugPrint('ConfigLoader: Loading from file: $filePath');
      final file = File(filePath);

      if (!await file.exists()) {
        debugPrint('ConfigLoader: File not found: $filePath');
        return null;
      }

      final yamlString = await file.readAsString();
      debugPrint('ConfigLoader: YAML string length: ${yamlString.length}');

      final yamlMap = loadYaml(yamlString);
      if (yamlMap == null) {
        debugPrint('ConfigLoader: $filePath is empty, skipping');
        return null;
      }

      final map = _convertYamlToMap(yamlMap);
      debugPrint('ConfigLoader: Converted YAML to map with ${map.length} keys');

      // Transform the flat YAML structure to the expected nested structure
      final transformedMap = _transformYamlToEngineConfig(map);
      debugPrint('ConfigLoader: Transformed map has ${transformedMap.length} sections');

      final config = EngineConfig.fromMap(transformedMap);
      debugPrint('ConfigLoader: Successfully created EngineConfig for ${config.metadata.id}');
      return config;
    } on YamlException catch (e) {
      debugPrint('ConfigLoader: Invalid YAML in $filePath - $e');
      return null;
    } on TypeError catch (e, stackTrace) {
      debugPrint('ConfigLoader: Type error loading $filePath - $e');
      debugPrint('ConfigLoader: Stack trace: $stackTrace');
      return null;
    } catch (e, stackTrace) {
      debugPrint('ConfigLoader: Error loading $filePath - $e');
      debugPrint('ConfigLoader: Stack trace: $stackTrace');
      return null;
    }
  }

  /// Load a single engine config file
  ///
  /// Returns [EngineConfig] if the file is valid, null otherwise.
  /// Errors are logged but not thrown.
  Future<EngineConfig?> loadEngineConfig(String assetPath) async {
    try {
      debugPrint('ConfigLoader: Loading $assetPath...');
      final yamlString = await rootBundle.loadString(assetPath);
      debugPrint('ConfigLoader: YAML string length: ${yamlString.length}');

      final yamlMap = loadYaml(yamlString);
      if (yamlMap == null) {
        debugPrint('ConfigLoader: $assetPath is empty, skipping');
        return null;
      }

      final map = _convertYamlToMap(yamlMap);
      debugPrint('ConfigLoader: Converted YAML to map with ${map.length} keys');

      // Transform the flat YAML structure to the expected nested structure
      final transformedMap = _transformYamlToEngineConfig(map);
      debugPrint('ConfigLoader: Transformed map has ${transformedMap.length} sections');

      final config = EngineConfig.fromMap(transformedMap);
      debugPrint('ConfigLoader: Successfully created EngineConfig for ${config.metadata.id}');
      return config;
    } on FlutterError catch (e) {
      debugPrint('ConfigLoader: Asset not found: $assetPath - $e');
      return null;
    } on YamlException catch (e) {
      debugPrint('ConfigLoader: Invalid YAML in $assetPath - $e');
      return null;
    } on TypeError catch (e, stackTrace) {
      debugPrint('ConfigLoader: Type error loading $assetPath - $e');
      debugPrint('ConfigLoader: This usually means a YAML field has an unexpected type (e.g., Map where String expected)');
      debugPrint('ConfigLoader: Stack trace: $stackTrace');
      return null;
    } catch (e, stackTrace) {
      debugPrint('ConfigLoader: Error loading $assetPath - $e');
      debugPrint('ConfigLoader: Stack trace: $stackTrace');
      return null;
    }
  }

  /// Merge engine config with defaults
  ///
  /// Applies default values from [defaults] to [engine] config where
  /// the engine config doesn't specify a value.
  EngineConfig mergeWithDefaults(EngineConfig engine, DefaultConfig defaults) {
    // Apply timeout from defaults if not specified in engine
    final mergedRequest = RequestConfig(
      baseUrl: engine.request.baseUrl,
      method: engine.request.method,
      timeoutSeconds:
          engine.request.timeoutSeconds ?? defaults.request.timeoutSeconds,
      urlBuilder: engine.request.urlBuilder,
      urls: engine.request.urls,
      params: engine.request.params,
      seriesConfig: engine.request.seriesConfig,
    );

    // Apply TV mode defaults if engine doesn't have TV mode config
    final mergedTvMode = engine.tvMode ??
        TvModeConfig(
          enabledDefault: false,
          smallChannel: TvModeLimit(
            maxResults: defaults.tvMode.minTorrentsPerKeyword * 10,
          ),
          largeChannel: TvModeLimit(
            maxResults: defaults.tvMode.minTorrentsPerKeyword * 20,
          ),
          quickPlay: TvModeLimit(
            maxResults: defaults.tvMode.minTorrentsPerKeyword * 5,
          ),
        );

    return EngineConfig(
      metadata: engine.metadata,
      request: mergedRequest,
      pagination: engine.pagination,
      response: engine.response,
      settings: engine.settings,
      tvMode: mergedTvMode,
    );
  }

  /// Get cached defaults (load if not cached)
  Future<DefaultConfig> getDefaults() async {
    _defaultConfig ??= await loadDefaults();
    return _defaultConfig!;
  }

  /// Get cached engine configs (load if not cached)
  Future<List<EngineConfig>> getEngines() async {
    _engineConfigs ??= await loadEngineConfigs();
    return _engineConfigs!;
  }

  /// Get a specific engine config by ID
  ///
  /// Returns null if the engine is not found.
  Future<EngineConfig?> getEngineById(String id) async {
    final engines = await getEngines();
    try {
      return engines.firstWhere((e) => e.metadata.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Force reload all configurations
  Future<void> reload() async {
    clearCache();
    _defaultConfig = await loadDefaults();
    _engineConfigs = await loadEngineConfigs();
  }

  /// Clear cached configurations
  void clearCache() {
    _defaultConfig = null;
    _engineConfigs = null;
    debugPrint('ConfigLoader: Cache cleared');
  }

  /// Transform flat YAML structure to nested EngineConfig structure
  ///
  /// The YAML files use a flatter structure for readability,
  /// this transforms it to match the EngineConfig model structure.
  Map<String, dynamic> _transformYamlToEngineConfig(Map<String, dynamic> yaml) {
    final result = <String, dynamic>{};
    final engineId = yaml['id'] ?? 'unknown';

    debugPrint('ConfigLoader: Transforming YAML for engine: $engineId');

    // Build metadata section
    result['metadata'] = {
      'id': yaml['id'],
      'display_name': yaml['display_name'],
      'description': yaml['description'],
      'icon': yaml['icon'],
      'categories': yaml['categories'] ?? [],
      'capabilities': yaml['capabilities'] ?? {},
    };

    // Build request section from api, query_params, and path_params
    final api = yaml['api'] as Map<String, dynamic>? ?? {};
    final queryParams = yaml['query_params'] as Map<String, dynamic>?;
    final pathParams = yaml['path_params'] as Map<String, dynamic>?;

    // Determine URL builder type - path_params takes precedence if present
    String urlBuilderType = 'query_params';
    if (pathParams != null) {
      urlBuilderType = pathParams['type'] as String? ?? 'path_params';
    } else if (queryParams != null) {
      urlBuilderType = queryParams['type'] as String? ?? 'query_params';
    }

    // Handle param_name which can be String or Map
    final paramName = queryParams?['param_name'];
    String? queryParamString;
    Map<String, String>? queryParamMap;

    if (paramName is String) {
      queryParamString = paramName;
    } else if (paramName is Map) {
      queryParamMap = paramName.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
      debugPrint('ConfigLoader: [$engineId] param_name is a Map with ${queryParamMap.length} entries');
    }

    result['request'] = {
      'base_url': api['base_url'],
      'method': api['method'] ?? 'GET',
      'timeout_seconds': api['timeout_seconds'],
      'urls': api['urls'],
      'url_builder': {
        'type': urlBuilderType,
        'query_param': queryParamString,
        'query_param_map': queryParamMap,
        'encode': queryParams?['encode'] ?? true,
      },
      'params': api['params'] ?? [],
      'series_config': yaml['series_config'] ?? api['series_config'],
    };

    // Pagination section - transform flat YAML to nested model structure
    final paginationYaml = yaml['pagination'] as Map<String, dynamic>? ?? {'type': 'none'};
    final paginationType = paginationYaml['type'] as String? ?? 'none';

    final transformedPagination = <String, dynamic>{
      'type': paginationType,
      if (paginationYaml['results_per_page'] != null)
        'results_per_page': paginationYaml['results_per_page'],
      if (paginationYaml['page_size'] != null)
        'results_per_page': paginationYaml['page_size'],  // Alias
      if (paginationYaml['max_pages'] != null)
        'max_pages': paginationYaml['max_pages'],
      if (paginationYaml['fixed_results'] != null)
        'fixed_results': paginationYaml['fixed_results'],
    };

    // Build nested cursor config if cursor-based pagination
    if (paginationType == 'cursor') {
      transformedPagination['cursor'] = {
        'response_field': paginationYaml['cursor_field'] ?? paginationYaml['response_field'] ?? '',
        'param_name': paginationYaml['cursor_param'] ?? paginationYaml['param_name'] ?? 'cursor',
      };
    }

    // Build nested page config if page-based pagination
    if (paginationType == 'page') {
      transformedPagination['page'] = {
        'param_name': paginationYaml['page_param'] ?? paginationYaml['param_name'] ?? 'page',
        'start_page': paginationYaml['start_page'] ?? 1,
        'has_more_field': paginationYaml['has_more_field'],
      };
    }

    result['pagination'] = transformedPagination;

    // Build response section
    final responseFormat =
        yaml['response_format'] as Map<String, dynamic>? ?? {};
    final emptyCheck = yaml['empty_check'] as Map<String, dynamic>?;
    final fieldMappings =
        yaml['field_mappings'] as Map<String, dynamic>? ?? {};

    // Convert field_mappings to field_mapping format expected by ResponseConfig
    final fieldMapping = <String, String>{};
    final typeConversions = <String, String>{};
    final complexConversions = <String, Map<String, dynamic>>{};
    final specialParsers = <String, dynamic>{};

    fieldMappings.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        final source = value['source'] as String?;
        if (source != null) {
          fieldMapping[key] = source;
        }

        // Handle conversion which can be String or Map
        final conversion = value['conversion'];
        if (conversion is String) {
          typeConversions[key] = conversion;
        } else if (conversion is Map) {
          // Complex conversion like {type: replace, find: "\n", replace: " "}
          complexConversions[key] = Map<String, dynamic>.from(conversion);
          debugPrint('ConfigLoader: [$engineId] Field "$key" has complex conversion: ${conversion['type']}');
        }

        // Handle special parsing configurations
        if (value['type'] == 'regex' || value['pattern'] != null) {
          specialParsers[key] = {
            'source_field': source ?? key,
            'pattern': value['pattern'] ?? '',
            'capture_group': value['capture_group'],
            'type': value['output_type'] ?? 'string',
            'default_value': value['default_value'],
          };
        }
      } else if (value is String) {
        fieldMapping[key] = value;
      }
    });

    // Also read top-level special_parsers section (in addition to inline ones from field_mappings)
    final topLevelSpecialParsers = yaml['special_parsers'] as Map<String, dynamic>?;
    if (topLevelSpecialParsers != null) {
      topLevelSpecialParsers.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          // Determine output type from various possible keys
          String outputType = 'string';
          if (value['parser_type'] != null) {
            outputType = value['parser_type'] as String;
          } else if (value['output_type'] != null) {
            outputType = value['output_type'] as String;
          } else if (value['conversion'] == 'string_to_int') {
            outputType = 'int';
          }

          specialParsers[key] = {
            'source_field': value['source'] ?? key,
            'pattern': value['pattern'] ?? '',
            'capture_group': value['capture_group'],
            'type': outputType,
            'default_value': value['default_value'],
          };
          debugPrint('ConfigLoader: [$engineId] Added top-level special parser "$key" from source "${value['source']}"');
        }
      });
    }

    // Handle results_path which can be String or Map
    final resultsPath = responseFormat['results_path'];
    if (resultsPath is Map) {
      debugPrint('ConfigLoader: [$engineId] results_path is a Map with keys: ${resultsPath.keys.toList()}');
    }

    // Get pre_checks from either response_format section or top-level
    final preChecks = responseFormat['pre_checks'] ?? yaml['pre_checks'];

    // Get nested_results from either response_format section or top-level
    final nestedResults = responseFormat['nested_results'] ?? yaml['nested_results'];

    result['response'] = {
      'format': responseFormat['type'] ?? 'json',
      'results_path': resultsPath, // Keep as-is, model handles both String and Map
      'jina_unwrap': responseFormat['jina_unwrap'],
      'pre_checks': preChecks,
      'empty_check': emptyCheck,
      'nested_results': nestedResults,
      'field_mapping': fieldMapping,
      'type_conversions': typeConversions.isNotEmpty ? typeConversions : null,
      'complex_conversions':
          complexConversions.isNotEmpty ? complexConversions : null,
      'transforms': yaml['transforms'],
      'special_parsers': specialParsers.isNotEmpty ? specialParsers : null,
    };

    debugPrint('ConfigLoader: [$engineId] Response config - format: ${responseFormat['type']}, '
        'field_mappings: ${fieldMapping.length}, type_conversions: ${typeConversions.length}, '
        'complex_conversions: ${complexConversions.length}');

    // Build settings section
    final settingsList = yaml['settings'] as List<dynamic>? ?? [];
    final settingsMap = <String, dynamic>{};

    for (final setting in settingsList) {
      if (setting is Map<String, dynamic>) {
        final id = setting['id'] as String?;
        if (id != null) {
          settingsMap[id] = {
            'type': setting['type'] ?? 'toggle',
            'label': setting['label'] ?? id,
            'default_value': setting['default'],
            'options': setting['options'],
            'min': setting['min'],
            'max': setting['max'],
          };
        }
      }
    }

    result['settings'] = settingsMap;

    // Build TV mode section
    final tvMode = yaml['tv_mode'] as Map<String, dynamic>?;
    if (tvMode != null) {
      final limits = tvMode['limits'] as Map<String, dynamic>? ?? {};
      result['tv_mode'] = {
        'enabled_default': tvMode['enabled_default'] ?? false,
        'small_channel': {
          'max_results': limits['small'] ?? 10,
        },
        'large_channel': {
          'max_results': limits['large'] ?? 20,
        },
        'quick_play': {
          'max_results': limits['quick_play'] ?? 5,
        },
      };
    }

    return result;
  }

  /// Convert YamlMap to a standard Dart Map.
  ///
  /// YAML library returns YamlMap which doesn't work well with
  /// type casting, so we need to convert it to a regular Map.
  Map<String, dynamic> _convertYamlToMap(dynamic yaml) {
    if (yaml is YamlMap) {
      final map = <String, dynamic>{};
      yaml.forEach((key, value) {
        map[key.toString()] = _convertYamlValue(value);
      });
      return map;
    } else if (yaml is Map) {
      final map = <String, dynamic>{};
      yaml.forEach((key, value) {
        map[key.toString()] = _convertYamlValue(value);
      });
      return map;
    }
    return {};
  }

  /// Recursively convert YAML values to Dart types
  dynamic _convertYamlValue(dynamic value) {
    if (value is YamlMap) {
      return _convertYamlToMap(value);
    } else if (value is YamlList) {
      return value.map((e) => _convertYamlValue(e)).toList();
    } else if (value is Map) {
      return _convertYamlToMap(value);
    } else if (value is List) {
      return value.map((e) => _convertYamlValue(e)).toList();
    }
    return value;
  }
}

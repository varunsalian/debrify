/// Main configuration class that holds all sections of an engine config
class EngineConfig {
  final EngineMetadata metadata;
  final RequestConfig request;
  final PaginationConfig pagination;
  final ResponseConfig response;
  final SettingsConfig settings;
  final TvModeConfig? tvMode;

  const EngineConfig({
    required this.metadata,
    required this.request,
    required this.pagination,
    required this.response,
    required this.settings,
    this.tvMode,
  });

  /// Factory constructor to create an EngineConfig from a YAML map
  factory EngineConfig.fromMap(Map<String, dynamic> map) {
    return EngineConfig(
      metadata: EngineMetadata.fromMap(
        map['metadata'] as Map<String, dynamic>? ?? {},
      ),
      request: RequestConfig.fromMap(
        map['request'] as Map<String, dynamic>? ?? {},
      ),
      pagination: PaginationConfig.fromMap(
        map['pagination'] as Map<String, dynamic>? ?? {},
      ),
      response: ResponseConfig.fromMap(
        map['response'] as Map<String, dynamic>? ?? {},
      ),
      settings: SettingsConfig.fromMap(
        map['settings'] as Map<String, dynamic>? ?? {},
      ),
      tvMode: map['tv_mode'] != null
          ? TvModeConfig.fromMap(map['tv_mode'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Convert the config back to a map for debugging
  Map<String, dynamic> toMap() {
    return {
      'metadata': metadata.toMap(),
      'request': request.toMap(),
      'pagination': pagination.toMap(),
      'response': response.toMap(),
      'settings': settings.toMap(),
      if (tvMode != null) 'tv_mode': tvMode!.toMap(),
    };
  }
}

// Import statements for related models
class EngineMetadata {
  final String id;
  final String displayName;
  final String? description;
  final String icon;
  final List<String> categories;
  final EngineCapabilities capabilities;

  const EngineMetadata({
    required this.id,
    required this.displayName,
    this.description,
    required this.icon,
    required this.categories,
    required this.capabilities,
  });

  factory EngineMetadata.fromMap(Map<String, dynamic> map) {
    return EngineMetadata(
      id: map['id'] as String? ?? '',
      displayName: map['display_name'] as String? ?? '',
      description: map['description'] as String?,
      icon: map['icon'] as String? ?? '',
      categories: (map['categories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      capabilities: EngineCapabilities.fromMap(
        map['capabilities'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'display_name': displayName,
      if (description != null) 'description': description,
      'icon': icon,
      'categories': categories,
      'capabilities': capabilities.toMap(),
    };
  }
}

class EngineCapabilities {
  final bool keywordSearch;
  final bool imdbSearch;
  final bool seriesSupport;

  const EngineCapabilities({
    required this.keywordSearch,
    required this.imdbSearch,
    required this.seriesSupport,
  });

  factory EngineCapabilities.fromMap(Map<String, dynamic> map) {
    return EngineCapabilities(
      keywordSearch: map['keyword_search'] as bool? ?? false,
      imdbSearch: map['imdb_search'] as bool? ?? false,
      seriesSupport: map['series_support'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'keyword_search': keywordSearch,
      'imdb_search': imdbSearch,
      'series_support': seriesSupport,
    };
  }
}

class RequestConfig {
  final String? baseUrl;
  final String method;
  final int? timeoutSeconds;
  final UrlBuilder urlBuilder;
  final Map<String, String>? urls;
  final List<RequestParam> params;
  final SeriesConfig? seriesConfig;

  const RequestConfig({
    this.baseUrl,
    required this.method,
    this.timeoutSeconds,
    required this.urlBuilder,
    this.urls,
    required this.params,
    this.seriesConfig,
  });

  factory RequestConfig.fromMap(Map<String, dynamic> map) {
    return RequestConfig(
      baseUrl: map['base_url'] as String?,
      method: map['method'] as String? ?? 'GET',
      timeoutSeconds: map['timeout_seconds'] as int?,
      urlBuilder: UrlBuilder.fromMap(
        map['url_builder'] as Map<String, dynamic>? ?? {},
      ),
      urls: (map['urls'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      params: (map['params'] as List<dynamic>?)
              ?.map((e) => RequestParam.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      seriesConfig: map['series_config'] != null
          ? SeriesConfig.fromMap(map['series_config'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (baseUrl != null) 'base_url': baseUrl,
      'method': method,
      if (timeoutSeconds != null) 'timeout_seconds': timeoutSeconds,
      'url_builder': urlBuilder.toMap(),
      if (urls != null) 'urls': urls,
      'params': params.map((e) => e.toMap()).toList(),
      if (seriesConfig != null) 'series_config': seriesConfig!.toMap(),
    };
  }
}

class UrlBuilder {
  final String type;
  final String? queryParam; // Single param name for all search types
  final Map<String, String>? queryParamMap; // Per-type param names {keyword: "q", imdb: "imdb_id"}
  final bool encode;

  const UrlBuilder({
    required this.type,
    this.queryParam,
    this.queryParamMap,
    required this.encode,
  });

  /// Get the query parameter name for a specific search type.
  /// Returns the type-specific param if queryParamMap contains the search type,
  /// otherwise falls back to the generic queryParam.
  String? getQueryParamForType(String searchType) {
    if (queryParamMap != null && queryParamMap!.containsKey(searchType)) {
      return queryParamMap![searchType];
    }
    return queryParam;
  }

  factory UrlBuilder.fromMap(Map<String, dynamic> map) {
    // Handle query_param which can be String or Map
    final queryParamValue = map['query_param'];
    String? queryParamString;
    Map<String, String>? queryParamMapValue;

    if (queryParamValue is String) {
      queryParamString = queryParamValue;
    } else if (queryParamValue is Map) {
      queryParamMapValue = queryParamValue.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }

    // Also check for explicit query_param_map field
    final explicitMap = map['query_param_map'];
    if (explicitMap is Map) {
      queryParamMapValue = explicitMap.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }

    return UrlBuilder(
      type: map['type'] as String? ?? 'query_params',
      queryParam: queryParamString,
      queryParamMap: queryParamMapValue,
      encode: map['encode'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      if (queryParam != null) 'query_param': queryParam,
      if (queryParamMap != null) 'query_param_map': queryParamMap,
      'encode': encode,
    };
  }
}

class RequestParam {
  final String name;
  final String? value;
  final String? source;
  final bool required;
  final String? appliesTo;

  const RequestParam({
    required this.name,
    this.value,
    this.source,
    required this.required,
    this.appliesTo,
  });

  factory RequestParam.fromMap(Map<String, dynamic> map) {
    return RequestParam(
      name: map['name'] as String? ?? '',
      value: map['value'] as String?,
      source: map['source'] as String?,
      required: map['required'] as bool? ?? false,
      appliesTo: map['applies_to'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      if (value != null) 'value': value,
      if (source != null) 'source': source,
      'required': required,
      if (appliesTo != null) 'applies_to': appliesTo,
    };
  }
}

class SeriesConfig {
  final int maxSeasonProbes;
  final int defaultEpisode;

  const SeriesConfig({
    required this.maxSeasonProbes,
    required this.defaultEpisode,
  });

  factory SeriesConfig.fromMap(Map<String, dynamic> map) {
    return SeriesConfig(
      maxSeasonProbes: map['max_season_probes'] as int? ?? 5,
      defaultEpisode: map['default_episode'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'max_season_probes': maxSeasonProbes,
      'default_episode': defaultEpisode,
    };
  }
}

class PaginationConfig {
  final String type;
  final int? resultsPerPage;
  final int? maxPages;
  final int? fixedResults;
  final CursorConfig? cursor;
  final PageConfig? page;

  const PaginationConfig({
    required this.type,
    this.resultsPerPage,
    this.maxPages,
    this.fixedResults,
    this.cursor,
    this.page,
  });

  factory PaginationConfig.fromMap(Map<String, dynamic> map) {
    return PaginationConfig(
      type: map['type'] as String? ?? 'none',
      resultsPerPage: map['results_per_page'] as int?,
      maxPages: map['max_pages'] as int?,
      fixedResults: map['fixed_results'] as int?,
      cursor: map['cursor'] != null
          ? CursorConfig.fromMap(map['cursor'] as Map<String, dynamic>)
          : null,
      page: map['page'] != null
          ? PageConfig.fromMap(map['page'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      if (resultsPerPage != null) 'results_per_page': resultsPerPage,
      if (maxPages != null) 'max_pages': maxPages,
      if (fixedResults != null) 'fixed_results': fixedResults,
      if (cursor != null) 'cursor': cursor!.toMap(),
      if (page != null) 'page': page!.toMap(),
    };
  }
}

class CursorConfig {
  final String responseField;
  final String paramName;

  const CursorConfig({
    required this.responseField,
    required this.paramName,
  });

  factory CursorConfig.fromMap(Map<String, dynamic> map) {
    return CursorConfig(
      responseField: map['response_field'] as String? ?? '',
      paramName: map['param_name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'response_field': responseField,
      'param_name': paramName,
    };
  }
}

class PageConfig {
  final String paramName;
  final int startPage;
  final String? hasMoreField;

  const PageConfig({
    required this.paramName,
    required this.startPage,
    this.hasMoreField,
  });

  factory PageConfig.fromMap(Map<String, dynamic> map) {
    return PageConfig(
      paramName: map['param_name'] as String? ?? 'page',
      startPage: map['start_page'] as int? ?? 1,
      hasMoreField: map['has_more_field'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'param_name': paramName,
      'start_page': startPage,
      if (hasMoreField != null) 'has_more_field': hasMoreField,
    };
  }
}

class ResponseConfig {
  final String format;
  final JinaUnwrapConfig? jinaUnwrap;
  final dynamic resultsPath;
  final List<PreCheck>? preChecks;
  final EmptyCheckConfig? emptyCheck;
  final NestedResultsConfig? nestedResults;
  final Map<String, String> fieldMapping;
  final Map<String, String>? typeConversions;
  final Map<String, Map<String, dynamic>>?
      complexConversions; // For complex conversions like {type: replace, find: "\n", replace: " "}
  final Map<String, dynamic>? transforms;
  final Map<String, SpecialParserConfig>? specialParsers;

  const ResponseConfig({
    required this.format,
    this.jinaUnwrap,
    required this.resultsPath,
    this.preChecks,
    this.emptyCheck,
    this.nestedResults,
    required this.fieldMapping,
    this.typeConversions,
    this.complexConversions,
    this.transforms,
    this.specialParsers,
  });

  factory ResponseConfig.fromMap(Map<String, dynamic> map) {
    return ResponseConfig(
      format: map['format'] as String? ?? 'json',
      jinaUnwrap: map['jina_unwrap'] != null
          ? JinaUnwrapConfig.fromMap(
              map['jina_unwrap'] as Map<String, dynamic>)
          : null,
      resultsPath: map['results_path'],
      preChecks: (map['pre_checks'] as List<dynamic>?)
          ?.map((e) => PreCheck.fromMap(e as Map<String, dynamic>))
          .toList(),
      emptyCheck: map['empty_check'] != null
          ? EmptyCheckConfig.fromMap(
              map['empty_check'] as Map<String, dynamic>)
          : null,
      nestedResults: map['nested_results'] != null
          ? NestedResultsConfig.fromMap(
              map['nested_results'] as Map<String, dynamic>)
          : null,
      fieldMapping: (map['field_mapping'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, value.toString()),
          ) ??
          {},
      typeConversions:
          (map['type_conversions'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      complexConversions:
          (map['complex_conversions'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
      ),
      transforms: map['transforms'] as Map<String, dynamic>?,
      specialParsers:
          (map['special_parsers'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(
          key,
          SpecialParserConfig.fromMap(value as Map<String, dynamic>),
        ),
      ),
    );
  }

  /// Get results path for a specific search type (keyword, imdb, series)
  /// If resultsPath is a map with type-specific paths, returns the appropriate one.
  /// Otherwise returns the default resultsPath as a string.
  String getResultsPathForType(String searchType) {
    if (resultsPath is Map) {
      final pathMap = resultsPath as Map;
      // Try type-specific path first
      if (pathMap.containsKey(searchType)) {
        return pathMap[searchType]?.toString() ?? '';
      }
      // Fall back to 'default' key
      if (pathMap.containsKey('default')) {
        return pathMap['default']?.toString() ?? '';
      }
      // Return first value if no match
      return pathMap.values.first?.toString() ?? '';
    }
    return resultsPath?.toString() ?? '';
  }

  Map<String, dynamic> toMap() {
    return {
      'format': format,
      if (jinaUnwrap != null) 'jina_unwrap': jinaUnwrap!.toMap(),
      'results_path': resultsPath,
      if (preChecks != null)
        'pre_checks': preChecks!.map((e) => e.toMap()).toList(),
      if (emptyCheck != null) 'empty_check': emptyCheck!.toMap(),
      if (nestedResults != null) 'nested_results': nestedResults!.toMap(),
      'field_mapping': fieldMapping,
      if (typeConversions != null) 'type_conversions': typeConversions,
      if (complexConversions != null) 'complex_conversions': complexConversions,
      if (transforms != null) 'transforms': transforms,
      if (specialParsers != null)
        'special_parsers':
            specialParsers!.map((key, value) => MapEntry(key, value.toMap())),
    };
  }
}

class JinaUnwrapConfig {
  final String method;
  final String? jsonStart;
  final String? jsonEnd;

  const JinaUnwrapConfig({
    required this.method,
    this.jsonStart,
    this.jsonEnd,
  });

  factory JinaUnwrapConfig.fromMap(Map<String, dynamic> map) {
    return JinaUnwrapConfig(
      method: map['method'] as String? ?? 'json_extraction',
      jsonStart: map['json_start'] as String?,
      jsonEnd: map['json_end'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'method': method,
      if (jsonStart != null) 'json_start': jsonStart,
      if (jsonEnd != null) 'json_end': jsonEnd,
    };
  }
}

class PreCheck {
  final String field;
  final dynamic equals;
  final String? errorMessage;

  const PreCheck({
    required this.field,
    required this.equals,
    this.errorMessage,
  });

  factory PreCheck.fromMap(Map<String, dynamic> map) {
    return PreCheck(
      field: map['field'] as String? ?? '',
      equals: map['equals'],
      errorMessage: map['error_message'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'field': field,
      'equals': equals,
      if (errorMessage != null) 'error_message': errorMessage,
    };
  }
}

class EmptyCheckConfig {
  final String type;
  final String? field;
  final String? equals;

  const EmptyCheckConfig({
    required this.type,
    this.field,
    this.equals,
  });

  factory EmptyCheckConfig.fromMap(Map<String, dynamic> map) {
    return EmptyCheckConfig(
      type: map['type'] as String? ?? 'array_empty',
      field: map['field'] as String?,
      equals: map['equals'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      if (field != null) 'field': field,
      if (equals != null) 'equals': equals,
    };
  }
}

class NestedResultsConfig {
  final bool enabled;
  final String itemsField;
  final List<ParentField> parentFields;

  const NestedResultsConfig({
    required this.enabled,
    required this.itemsField,
    required this.parentFields,
  });

  factory NestedResultsConfig.fromMap(Map<String, dynamic> map) {
    return NestedResultsConfig(
      enabled: map['enabled'] as bool? ?? false,
      itemsField: map['items_field'] as String? ?? '',
      parentFields: (map['parent_fields'] as List<dynamic>?)
              ?.map((e) => ParentField.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'items_field': itemsField,
      'parent_fields': parentFields.map((e) => e.toMap()).toList(),
    };
  }
}

class ParentField {
  final String source;
  final String? fallback;
  final String target;
  final String? transform;

  const ParentField({
    required this.source,
    this.fallback,
    required this.target,
    this.transform,
  });

  factory ParentField.fromMap(Map<String, dynamic> map) {
    return ParentField(
      source: map['source'] as String? ?? '',
      fallback: map['fallback'] as String?,
      target: map['target'] as String? ?? '',
      transform: map['transform'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'source': source,
      if (fallback != null) 'fallback': fallback,
      'target': target,
      if (transform != null) 'transform': transform,
    };
  }
}

class SpecialParserConfig {
  final String sourceField;
  final String pattern;
  final int? captureGroup;
  final String type;
  final dynamic defaultValue;

  const SpecialParserConfig({
    required this.sourceField,
    required this.pattern,
    this.captureGroup,
    required this.type,
    this.defaultValue,
  });

  factory SpecialParserConfig.fromMap(Map<String, dynamic> map) {
    return SpecialParserConfig(
      sourceField: map['source_field'] as String? ?? '',
      pattern: map['pattern'] as String? ?? '',
      captureGroup: map['capture_group'] as int?,
      type: map['type'] as String? ?? 'int',
      defaultValue: map['default_value'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'source_field': sourceField,
      'pattern': pattern,
      if (captureGroup != null) 'capture_group': captureGroup,
      'type': type,
      if (defaultValue != null) 'default_value': defaultValue,
    };
  }
}

class SettingsConfig {
  final Map<String, SettingConfig> settings;

  const SettingsConfig({
    required this.settings,
  });

  /// Convenience getter for the 'enabled' setting
  SettingConfig? get enabled => settings['enabled'];

  /// Convenience getter for the 'maxResults' setting
  SettingConfig? get maxResults => settings['max_results'];

  /// Get all setting keys
  Iterable<String> get keys => settings.keys;

  /// Get a setting by key
  SettingConfig? getSetting(String key) => settings[key];

  factory SettingsConfig.fromMap(Map<String, dynamic> map) {
    final settings = <String, SettingConfig>{};
    map.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        settings[key] = SettingConfig.fromMap(value);
      }
    });
    return SettingsConfig(settings: settings);
  }

  Map<String, dynamic> toMap() {
    return settings.map((key, value) => MapEntry(key, value.toMap()));
  }
}

class SettingConfig {
  final String type;
  final String label;
  final dynamic defaultValue;
  final List<int>? options;
  final int? min;
  final int? max;

  const SettingConfig({
    required this.type,
    required this.label,
    required this.defaultValue,
    this.options,
    this.min,
    this.max,
  });

  /// Type-safe getter for boolean default value
  bool get defaultBool => defaultValue is bool ? defaultValue as bool : false;

  /// Type-safe getter for integer default value
  int get defaultInt => defaultValue is int ? defaultValue as int : 0;

  /// Check if this is a toggle (boolean) setting
  bool get isToggle => type == 'toggle';

  /// Check if this is a dropdown setting
  bool get isDropdown => type == 'dropdown';

  /// Check if this is a slider setting
  bool get isSlider => type == 'slider';

  factory SettingConfig.fromMap(Map<String, dynamic> map) {
    return SettingConfig(
      type: map['type'] as String? ?? 'toggle',
      label: map['label'] as String? ?? '',
      defaultValue: map['default_value'],
      options: (map['options'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList(),
      min: map['min'] as int?,
      max: map['max'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'label': label,
      'default_value': defaultValue,
      if (options != null) 'options': options,
      if (min != null) 'min': min,
      if (max != null) 'max': max,
    };
  }
}

class TvModeConfig {
  final bool enabledDefault;
  final TvModeLimit smallChannel;
  final TvModeLimit largeChannel;
  final TvModeLimit quickPlay;

  const TvModeConfig({
    required this.enabledDefault,
    required this.smallChannel,
    required this.largeChannel,
    required this.quickPlay,
  });

  factory TvModeConfig.fromMap(Map<String, dynamic> map) {
    return TvModeConfig(
      enabledDefault: map['enabled_default'] as bool? ?? false,
      smallChannel: TvModeLimit.fromMap(
        map['small_channel'] as Map<String, dynamic>? ?? {},
      ),
      largeChannel: TvModeLimit.fromMap(
        map['large_channel'] as Map<String, dynamic>? ?? {},
      ),
      quickPlay: TvModeLimit.fromMap(
        map['quick_play'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled_default': enabledDefault,
      'small_channel': smallChannel.toMap(),
      'large_channel': largeChannel.toMap(),
      'quick_play': quickPlay.toMap(),
    };
  }
}

class TvModeLimit {
  final int maxResults;

  const TvModeLimit({
    required this.maxResults,
  });

  factory TvModeLimit.fromMap(Map<String, dynamic> map) {
    return TvModeLimit(
      maxResults: map['max_results'] as int? ?? 10,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'max_results': maxResults,
    };
  }
}
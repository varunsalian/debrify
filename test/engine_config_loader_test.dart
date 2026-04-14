import 'dart:io';

import 'package:debrify/models/engine_config/engine_config.dart';
import 'package:debrify/services/engine/config_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Engine guide compatibility', () {
    late Directory tempDir;
    late String yamlPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('guide_engine');
      yamlPath = '${tempDir.path}/guide_engine.yaml';
      await File(yamlPath).writeAsString(_sampleEngineYaml);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('ConfigLoader parses guide-compliant YAML', () async {
      final loader = ConfigLoader();
      final EngineConfig? config = await loader.loadEngineConfigFromFile(yamlPath);
      expect(config, isNotNull, reason: 'Guide sample should produce a valid EngineConfig');

      final metadata = config!.metadata;
      expect(metadata.id, 'guide_example');
      expect(metadata.displayName, 'Guide Example Engine');
      expect(metadata.capabilities.keywordSearch, isTrue);
      expect(metadata.capabilities.imdbSearch, isFalse);

      final request = config.request;
      expect(request.method, 'GET');
      expect(request.baseUrl, 'https://example.com/api/search');
      expect(request.params.length, 1);
      expect(request.params.first.name, 'limit');
      expect(request.params.first.value, '50');

      final urlBuilder = request.urlBuilder;
      expect(urlBuilder.type, 'query_params');
      expect(urlBuilder.queryParamMap?['keyword'], 'q');
      expect(urlBuilder.queryParamMap?['imdb'], 'q');

      final pagination = config.pagination;
      expect(pagination.type, 'page');
      expect(pagination.page?.paramName, 'page');
      expect(pagination.page?.startPage, 1);
      expect(pagination.resultsPerPage, 50);

      final response = config.response;
      expect(response.format, 'direct_json');
      expect(response.resultsPath, 'results');
      expect(response.fieldMapping['infohash'], 'hash');
      expect(response.fieldMapping['name'], 'title');
      expect(response.fieldMapping['seeders'], 'stats.seeders');
      expect(response.typeConversions?['size_bytes'], 'string_to_int');
      expect(response.specialParsers?['leechers']?.pattern, 'Leechers:(\\d+)');

      final settings = config.settings;
      expect(settings.getSetting('enabled')?.defaultBool, isTrue);
      expect(settings.getSetting('max_results')?.isDropdown, isTrue);
      expect(settings.getSetting('max_results')?.defaultInt, 50);
      expect(settings.getSetting('max_results')?.options, containsAll([25, 50, 75]));

      final tvMode = config.tvMode;
      expect(tvMode, isNotNull);
      expect(tvMode!.enabledDefault, isFalse);
      expect(tvMode.smallChannel.maxResults, 10);
      expect(tvMode.largeChannel.maxResults, 20);
      expect(tvMode.quickPlay.maxResults, 15);
    });
  });
}

const String _sampleEngineYaml = '''
# Minimal keyword-centric engine that mirrors the documentation guide
id: guide_example
display_name: "Guide Example Engine"
description: "Sample engine built exactly like the docs"
icon: travel_explore
categories: [general, movies]
capabilities:
  keyword_search: true
  imdb_search: false
  series_support: false

api:
  urls:
    keyword: "https://example.com/api/search"
    imdb: "https://example.com/api/search"
  base_url: "https://example.com/api/search"
  method: GET
  timeout_seconds: 15
  params:
    - name: limit
      value: "50"
      location: query

query_params:
  type: query_params
  param_name:
    keyword: q
    imdb: q
  encode: true

series_config:
  max_season_probes: 2
  default_episode: 1

pagination:
  type: page
  page_size: 50
  max_pages: 2
  start_page: 1
  page_param: "page"

response_format:
  type: direct_json
  results_path: results
  pre_checks:
    - field: ok
      equals: true

empty_check:
  type: field_value
  field: message
  equals: "No results"

field_mappings:
  infohash:
    source: hash
  name:
    source: title
    conversion:
      type: replace
      find: "\\n"
      replace: " "
  size_bytes:
    source: size
    conversion: string_to_int
  seeders:
    source: stats.seeders
    conversion: string_to_int

special_parsers:
  leechers:
    source: stats_text
    type: regex
    pattern: "Leechers:(\\\\d+)"
    capture_group: 1
    conversion: string_to_int

settings:
  - id: enabled
    type: toggle
    label: "Enable guide example"
    default: true
  - id: max_results
    type: dropdown
    label: "Max results"
    default: 50
    options: [25, 50, 75]

tv_mode:
  enabled_default: false
  limits:
    small: 10
    large: 20
    quick_play: 15
''';

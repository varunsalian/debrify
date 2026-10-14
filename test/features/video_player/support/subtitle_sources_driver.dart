import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/subtitle_source_priority.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'subtitle_apply_driver.dart';
import 'trakt_transport.dart';

/// Real addon registration and service-owned requests; never injects State slots.
class SubtitleSourcesDriver extends SubtitleApplyDriver {
  SubtitleSourcesDriver(super.t, {super.configurePlayer, super.committed});
  final addons = <StremioAddon>[];
  Future<void> setup() async {
    await initialize();
    TraktTestTransport.instance.attach(f);
  }

  String endpoint(
    String name, {
    String identity = 'tt1100001',
    String type = 'movie',
  }) => 'https://$name.subtitle.test/subtitles/$type/$identity.json';
  String caption(String name) => 'https://$name.subtitle.test/$name.srt';
  http.Response slots(String name, {String language = 'eng'}) => http.Response(
    jsonEncode({
      'subtitles': [
        {'id': name, 'url': caption(name), 'lang': language},
      ],
    }),
    200,
  );
  Future<void> register(String name) async {
    final manifest = 'https://$name.subtitle.test/manifest.json';
    f.network.replies[manifest] = http.Response(
      jsonEncode({
        'id': 'p11-$name',
        'name': name,
        'version': '1.0.0',
        'types': ['movie', 'series'],
        'resources': ['subtitles'],
        'catalogs': [],
      }),
      200,
    );
    addons.add(await f.finish(t, StremioService.instance.addAddon(manifest)));
    f.network.replies[endpoint(name)] = slots(name);
    f.network.replies[caption(name)] = http.Response(
      '1\n00:00:01,000 --> 00:00:02,000\n$name\n',
      200,
    );
  }

  Future<void> order({String? language, bool embeddedFirst = false}) async {
    await f.finish(
      t,
      SubtitleSettingsStorage.setDefaultSubtitleLanguage(language),
    );
    await f.finish(
      t,
      SubtitleSettingsStorage.setSubtitleSourcePriority([
        if (embeddedFirst) SubtitleSourcePriority.embedded,
        ...addons.map(
          (a) => SubtitleSourcePriority.addon(a.portableConfigurationKey),
        ),
        if (!embeddedFirst) SubtitleSourcePriority.embedded,
      ]),
    );
  }

  int requests(String url) =>
      f.network.requests.where((r) => r.url.toString() == url).length;
}

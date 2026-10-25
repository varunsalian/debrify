"""Phase-13 real four-file draft: routed Hosts, lexical context and S2d."""
import copy
from test_dart_identify_moves import snippet_tokens
from dart_move_fixture import materialize
from dart_move_history import load_manifest, git_text, check_earlier, earlier_sources, applied_sources
import check_dart_moves as d
import re


def run(package):
    print('Phase-13 current draft: 29 methods/getters + inert refresh-ticket field; four destinations', flush=True)
    spec = load_manifest('dev/tool/dart_moves/vplayer_p13.json')
    original = git_text(spec['base'], spec['source'])
    sources = materialize(spec, original, package)
    assert not d.check(spec, original, sources, package)
    assert not check_earlier(spec, package, current=applied_sources(spec))
    assert len(earlier_sources(spec)) == 25
    assert len([r for r in spec['declarations'] if r['fate'] == 'moved']) == 30
    assert sum(e['count'] for r in spec['declarations'] if r['fate'] == 'retained'
               for e in r.get('substitutions', [])) == 25
    facade = spec['source']
    ui, menu, recording, resources = spec['destinations']
    assert spec['patched_class_projection'] == [
        '_VpDisplayModeHostAdapter', '_VpSleepTimerHostAdapter']
    for key in spec['patched_class_projection']:
        row = next(r for r in spec['declarations'] if r['original'] == key)
        assert row['fate'] == 'patched' and len(row['patches']) == 1
        assert row['patches'][0]['count'] == 1

    def replace(path, before, after):
        pattern = r'\s*'.join(re.escape(t) for t in snippet_tokens(before))
        start = sources[path].index('class _VpIptvRecordingHostAdapter') if before == 'bool get isIOS => VpS2Hooks.isIOS;' else 0
        matches = list(re.finditer(pattern, sources[path][start:]))
        assert matches, (path, before)
        found = matches[0]
        begin, end = start + found.start(), start + found.end()
        return dict(sources, **{path: sources[path][:begin] + after +
                               sources[path][end:]})

    cases = [
        ('refresh ticket initializer changed', recording, 'int engineRefreshTicket = 0;', 'int engineRefreshTicket = 1;'),
        ('refresh ticket captured by local', recording, 'final ticket = ++engineRefreshTicket;', 'int engineRefreshTicket = 0; final ticket = ++engineRefreshTicket;'),
        ('inert constructor reads Host', recording, 'VpIptvRecording(this._host);',
         'VpIptvRecording(this._host) { _host.player; }'),
        ('resource eager selector', resources, 'VpIptvRecordingResources(this._host);',
         'VpIptvRecordingResources(this._host) { _host.iptvSources; }'),
        ('assignment missing', facade,
         '_recordingResources = VpIptvRecordingResources(_VpIptvRecordingResourcesHostAdapter(this));', ''),
        ('wrong menu sibling routing', facade, '_s._menu.openPlayerMenuAt', '_s._menuUi.openPlayerMenuAt'),
        ('wrong resource routing', facade, '_s._recordingResources.recordingTargetPath', '_s._recording.recordingTargetPath'),
        ('cached player', facade, 'mk.Player get player => _s._player;', 'late final mk.Player player = _s._player;'),
        ('cached launch selector', facade, 'get iptvSources => _s.widget.iptvSources;', 'get iptvSources => null;'),
        ('wrong State setter', facade, 'set engineTaskId(String? v) => _s._engineTaskId = v;',
         'set engineTaskId(String? v) => _s._recordingTempPath = v;'),
        ('S2d bypass', recording, '!_host.isIOS && _host.recordingSupported', '_host.recordingSupported'),
        ('S2d support order', recording, 'DesktopRecordingService.instance.isSupported && !_host.isIOS',
         '!_host.isIOS && DesktopRecordingService.instance.isSupported'),
        ('S2d wrong live projection', facade, 'bool get isIOS => VpS2Hooks.isIOS;', 'bool get isIOS => Platform.isIOS;'),
        ('parameter context changed', ui, 'if (!context.mounted) return;', 'if (!_host.mounted) return;'),
        ('quick metadata fetch', menu, 'seriesPlaylist.getImdbIdForIndex(_host.currentIndex)',
         'seriesPlaylist.fetchMovieMetadataForIndex(_host.currentIndex)'),
        ('live metadata skipped', ui, 'await seriesPlaylist.fetchMovieMetadataForIndex',
         'seriesPlaylist.getImdbIdForIndex'),
        ('cache identity live', ui, 'final cacheKey = _host.menuCacheKey;', 'final cacheKey = _host.cachedSubtitleKey;'),
        ('manual revision increment lost', menu, 'final revision = ++_host.subtitleAudioRevision;',
         'final revision = _host.subtitleAudioRevision;'),
        ('generation captured late', recording, 'final gen = ++_host.recordingStartGen;', 'final gen = 0;'),
        ('stop generation lost', recording, '_host.recordingStartGen++;', ''),
        ('stop default changed', recording, 'stopRecording({bool userInitiated = true})',
         'stopRecording({bool userInitiated = false})'),
        ('target extension changed', resources, "String extension = 'mkv'", "String extension = 'ts'"),
        ('resource record type changed', resources, 'Future<({String id, int revision})?> currentRecordingResource()',
         'Future<({String id, int revision})> currentRecordingResource()'),
        ('captured platform becomes live', recording, "await platform.setProperty('stream-record', path)",
         "await _host.player.platform!.setProperty('stream-record', path)"),
        ('dispose inline protocol replaced', facade, '_recordingStartGen++; if (_isRecording)',
         '_recording.stopRecording(); if (_isRecording)'),
        ('facade import', menu, "import 'dart:async';", "import 'package:debrify/screens/video_player_screen.dart';"),
        ('sibling import', recording, "import 'dart:async';", "import 'vp_iptv_recording_resources.dart';"),
    ]
    for label, path, before, after in cases:
        assert d.check(spec, original, replace(path, before, after), package), label
        print('Phase-13 ' + label + ': rejected')
    # A declared edit cannot authorize replacing the lexical parameter guard.
    changed = copy.deepcopy(spec)
    row = next(r for r in changed['declarations'] if r['original'].endswith('._showTracksSheet'))
    row.setdefault('substitutions', []).append(dict(
        before=snippet_tokens('if (!context.mounted) return;'),
        after=snippet_tokens('if (!_host.mounted) return;'), count=1))
    errors = d.check(changed, original,
                     replace(ui, 'if (!context.mounted) return;', 'if (!_host.mounted) return;'), package)
    assert errors and not any('tokens changed' in e for e in errors), errors
    assert any('context' in e or 'Occurrence' in e for e in errors), errors
    print('Phase-13 declared lexical context mutation: independently rejected')
    for chain in spec['guards']['registered_occurrence_substitutions']:
        changed = copy.deepcopy(spec)
        changed['guards']['registered_occurrence_substitutions'].remove(chain)
        assert d.check(changed, original, sources, package), chain
        print('Phase-13 unregistered ' + '.'.join(chain['before']) + ': rejected')
    print('Phase-13 PASS: four complete files, 30 moves, 25 retained + two adapter rewrites, 25 earlier destinations')

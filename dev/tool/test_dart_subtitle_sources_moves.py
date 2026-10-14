"""Phase-11 real-config ownership, live selectors, chains and ordering proofs."""
import copy
import re
from check_settings_moves import tokens
from dart_move_history import load_manifest, git_text, check_earlier, earlier_sources
from dart_move_fixture import materialize
import check_dart_moves as d


def run(package):
    spec = load_manifest('dev/tool/dart_moves/vplayer_p11.json')
    original = git_text(spec['base'], spec['source'])
    sources = materialize(spec, original, package)
    assert not d.check(spec, original, sources, package)
    assert not check_earlier(spec, package)
    assert len(earlier_sources(spec)) == 20
    moves = [r for r in spec['declarations'] if r['fate'] == 'moved']
    assert len(moves) == 15
    assert sum(e['count'] for r in spec['declarations'] if r['fate'] == 'retained'
               for e in r.get('substitutions', [])) == 21
    patch = next(r for r in spec['declarations'] if r['original'] == '_VpSubtitleApplyHostAdapter')
    assert sum(e['count'] for e in patch['patches']) == 1
    fields = spec['guards']['occurrence_field_bindings']['owner_scoped_bare_fields']
    assert set(fields) == {'_VideoPlayerScreenState._tempSubtitleFiles',
                           '_VideoPlayerScreenState._subtitlePrioritySelectionQueue'}
    facade = spec['source']
    destinations = list(spec['destinations'])
    language, preferences, addon = destinations
    cases = [
        ('constructor order', facade,
         '_trackPreferences = VpTrackPreferences ( _VpTrackPreferencesHostAdapter ( this ) ) ;', ''),
        ('eager Host read', language, 'VpSubtitleLanguagePolicy ( this . _host ) ;',
         'VpSubtitleLanguagePolicy(this._host) { _host.player; }'),
        ('cached player', facade, 'mk . Player get player => _s . _player ;',
         'late final mk.Player player = _s._player;'),
        ('cached title selector', facade, 'String get title => _s . widget . title ;',
         "String get title => '';"),
        ('wrong episode selector', facade, 'get contentEpisode => _s . widget . contentEpisode ;',
         'get contentEpisode => _s.widget.contentSeason;'),
        ('nullable callback removed', addon, 'bool Function ( ) ? isCurrent', 'bool Function() isCurrent'),
        ('default argument changed', language, 'bool ignoreSourcePriority = false',
         'bool ignoreSourcePriority = true'),
        ('captured track list changed', language, 'final tracks = _host . player . state . tracks ;',
         'final tracks = _host.player.state.tracks; await Future<void>.value();'),
        ('captured playlist changed', preferences, 'final seriesPlaylist = _host . seriesPlaylist ;',
         'final seriesPlaylist = null;'),
        ('content token changed', preferences, 'final restoreToken = _host . addonSubtitleFetchToken ;',
         'final restoreToken = 0;'),
        ('audio revision changed', addon, 'final audioRevision = _host . subtitleAudioRevision ;',
         'final audioRevision = 0;'),
        ('field ownership wrong', addon, 'tempSubtitleFiles . add', '_host.tempSubtitleFiles.add'),
        ('queue ownership wrong', addon, 'subtitlePrioritySelectionQueue.submit',
         '_host.subtitlePrioritySelectionQueue.submit'),
        ('queue initializer changed', addon, 'SubtitlePrioritySelectionQueue ( )',
         'SubtitlePrioritySelectionQueue()..toString()'),
        ('temp initializer changed', addon, 'tempSubtitleFiles = { } ;', "tempSubtitleFiles = {'cached'};"),
        ('reset moved cleanup position', facade, '_addonSubtitles . cleanupTempSubtitleFilesSync ( ) ;', ''),
        ('selected audio reset removed', facade, '_subtitleSelectedAudio = null ;', ''),
        ('live setter changed', facade, 'set subtitleSelectedAudio ( String ? v ) => _s . _subtitleSelectedAudio = v ;',
         'set subtitleSelectedAudio(String? v) {}'),
        ('wrong persistence projection', facade, '_s . _trackPreferences . persistTrackChoice',
         '_s._addonSubtitles.persistTrackChoice'),
        ('unrelated patched adapter change', facade, 'bool get isAndroid => VpS2Hooks . isAndroid ;',
         'bool get isAndroid => false;'),
        ('frozen wait signature changed', preferences, 'waitForSubtitleTracks ( token : restoreToken )',
         'waitForSubtitleTracks(token: 0)'),
        ('frozen external path chain wrong', addon, '_host . setActiveExternalSubtitlePath',
         '_host.resetSubtitleSyncOffset'),
        ('native removal reordered', addon, 'await platform . command ( [ \'sub-remove\' , id ] ) ;', ''),
        ('facade import', addon, "import 'dart:async' ;", "import 'package:debrify/screens/video_player_screen.dart';"),
        ('sibling import', language, "import 'package:flutter/foundation.dart' ;",
         "import 'vp_addon_subtitles.dart';"),
    ]
    for label, path, before, after in cases:
        pattern = r'\s*'.join(re.escape(t) for t in re.findall(r"'[^']*'|[A-Za-z_$][A-Za-z0-9_$]*|[0-9]+|=>|\+\+|--|\S", before))
        found = re.search(pattern, sources[path])
        assert found, (label, before)
        text = sources[path][:found.start()] + after + sources[path][found.end():]
        changed = dict(sources, **{path: text})
        assert d.check(spec, original, changed, package), label
        print('Phase-11 ' + label + ': rejected')
    for chain in spec['guards']['registered_occurrence_substitutions']:
        changed = copy.deepcopy(spec)
        changed['guards']['registered_occurrence_substitutions'].remove(chain)
        assert d.check(changed, original, sources, package), chain
        print('Phase-11 unregistered ' + '.'.join(chain['before']) + ': rejected')
    assert sum(len(g['before']) == 3 and g['before'][0] != 'widget'
               for g in spec['guards']['registered_occurrence_substitutions']) == 3
    print('Phase-11 PASS: 15 moves, 28 references, three chains, 20 protected destinations')

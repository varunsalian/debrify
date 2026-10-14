"""Phase-12 real-manifest routing, lexical setters/contexts and live Hosts."""
import copy
import re

import check_dart_moves as d
from dart_move_fixture import materialize
from dart_move_history import load_manifest, git_text, check_earlier, earlier_sources


def snippet_tokens(text):
    return re.findall(r"'[^']*'|[A-Za-z_$][A-Za-z0-9_$]*|[0-9]+|=>|\+\+|--|\S", text)


def run(package):
    spec = load_manifest('dev/tool/dart_moves/vplayer_p12.json')
    original = git_text(spec['base'], spec['source'])
    sources = materialize(spec, original, package)
    assert not d.check(spec, original, sources, package)
    assert not check_earlier(spec, package)
    assert len(earlier_sources(spec)) == 23
    assert len([r for r in spec['declarations'] if r['fate'] == 'moved']) == 8
    assert sum(e['count'] for r in spec['declarations'] if r['fate'] == 'retained'
               for e in r.get('substitutions', [])) == 7
    facade = spec['source']
    identify, ui = spec['destinations']

    def replace(path, before, after):
        pattern = r'\s*'.join(re.escape(t) for t in snippet_tokens(before))
        matches = list(re.finditer(pattern, sources[path]))
        assert matches, (path, before)
        found = matches[0]
        return dict(sources, **{path: sources[path][:found.start()] + after +
                               sources[path][found.end():]})

    cases = [
        ('UI assignment missing', facade,
         '_identifyUi = VpIdentifyTitleUi(_VpIdentifyTitleUiHostAdapter(this));', ''),
        ('constructor Host read', identify, 'VpIdentifyTitle(this._host);',
         'VpIdentifyTitle(this._host) { _host.title; }'),
        ('UI eager context', ui, 'VpIdentifyTitleUi(this._host);',
         'VpIdentifyTitleUi(this._host) { _host.context; }'),
        ('wrong sheet facade routing', facade, '_s._identifyUi.showIdentifyTitleSearchSheet',
         '_s._identify.showIdentifyTitleSearchSheet'),
        ('wrong dialog facade routing', facade, '_s._identifyUi.requestSeasonEpisodeForIdentity',
         '_s._identify.requestSeasonEpisodeForIdentity'),
        ('wrong P11 forwarding', facade, '_s._addonSubtitles.fetchAndMaybeAutoSelectAddonSubtitle',
         '_s._identify.fetchAndMaybeAutoSelectAddonSubtitle'),
        ('cached State context', facade, 'BuildContext get context => _s.context;',
         'late final BuildContext context = _s.context;'),
        ('cached title', facade, 'String get title => _s.widget.title;',
         "String get title => '';"),
        ('wrong widget coordinate', facade, 'get contentSeason => _s.widget.contentSeason;',
         'get contentSeason => _s.widget.contentEpisode;'),
        ('manual field assigned incorrectly', facade,
         'set manualContentEpisode(int? v) => _s._manualContentEpisode = v;',
         'set manualContentEpisode(int? v) => _s._manualContentSeason = v;'),
        ('captured title becomes live', identify, 'SeriesParser.parseFilename(rawTitle)',
         'SeriesParser.parseFilename(_host.title)'),
        ('captured playlist removed', identify, 'final seriesPlaylist = _host.seriesPlaylist;',
         'final seriesPlaylist = null;'),
        ('identify token captured late', identify, 'final identifyToken = _host.addonSubtitleFetchToken;',
         'final identifyToken = 0;'),
        ('deferred search becomes immediate', ui, 'Future(() => runSearch(initialQuery, setSheetState));',
         'runSearch(initialQuery, setSheetState);'),
        ('search token changed', ui, 'final token = ++searchToken;', 'final token = searchToken;'),
        ('tile uses missing lexical context', ui, 'Navigator.of(_host.context).pop(meta)',
         'Navigator.of(sheetContext).pop(meta)'),
        ('initial search flag moved', ui, 'var initialSearchStarted = false;',
         'var initialSearchStarted = true;'),
        ('resource disposal removed', ui, 'firstResultFocusNode.dispose();', ''),
        ('sheet setter uses State', ui, 'setSheetState(() { isSearching = true;',
         '_host.setState(() { isSearching = true;'),
        ('dialog setter uses State', ui, 'setDialogState(() {', '_host.setState(() {'),
        ('sheet close uses State context', ui, 'Navigator.of(sheetContext).pop()',
         'Navigator.of(_host.context).pop()'),
        ('dialog close uses State context', ui, 'Navigator.of(dialogContext).pop()',
         'Navigator.of(_host.context).pop()'),
        ('sheet layout uses State context', ui, 'MediaQuery.of(sheetContext).size',
         'MediaQuery.of(_host.context).size'),
        ('facade import', identify, "import 'package:flutter/material.dart';",
         "import 'package:debrify/screens/video_player_screen.dart';"),
        ('sibling import', identify, "import 'package:flutter/material.dart';",
         "import 'vp_identify_title_ui.dart';"),
    ]
    for label, path, before, after in cases:
        errors = d.check(spec, original, replace(path, before, after), package)
        assert errors, label
        print('Phase-12 ' + label + ': rejected')

    # Declare the exact corrupt token edits: independent binding guards must
    # still reject lexical setters/contexts. Token comparison alone cannot do so.
    for member, before, after, required_error in [
        ('_showIdentifyTitleSearchSheet', 'setSheetState(() { isSearching = true;',
         '_host.setState(() { isSearching = true;', 'Lexical State setter changed'),
        ('_requestSeasonEpisodeForIdentity', 'setDialogState(() {',
         '_host.setState(() {', 'Lexical State setter changed'),
        ('_showIdentifyTitleSearchSheet', 'Navigator.of(sheetContext).pop()',
         'Navigator.of(_host.context).pop()', None),
        ('_requestSeasonEpisodeForIdentity', 'Navigator.of(dialogContext).pop()',
         'Navigator.of(_host.context).pop()', None),
        ('_showIdentifyTitleSearchSheet', 'MediaQuery.of(sheetContext).size',
         'MediaQuery.of(_host.context).size', None),
    ]:
        changed = copy.deepcopy(spec)
        row = next(r for r in changed['declarations']
                   if r['original'] == '_VideoPlayerScreenState.' + member)
        row.setdefault('substitutions', []).append(
            dict(before=snippet_tokens(before), after=snippet_tokens(after), count=1))
        errors = d.check(changed, original, replace(ui, before, after), package)
        assert errors and not any('tokens changed' in e for e in errors), (member, errors)
        if required_error:
            assert any(required_error in e for e in errors), (member, errors)
        else:
            assert any('Occurrence' in e or 'context' in e for e in errors), (member, errors)
        print('Phase-12 binding-only ' + member + '/' + before + ': rejected')

    for chain in spec['guards']['registered_occurrence_substitutions']:
        changed = copy.deepcopy(spec)
        changed['guards']['registered_occurrence_substitutions'].remove(chain)
        assert d.check(changed, original, sources, package), chain
        print('Phase-12 unregistered ' + '.'.join(chain['before']) + ': rejected')
    assert spec['guards']['lexical_state_setters'] == {
        '_VideoPlayerScreenState._showIdentifyTitleSearchSheet': ['setSheetState'],
        '_VideoPlayerScreenState._requestSeasonEpisodeForIdentity': ['setDialogState'],
    }
    print('Phase-12 PASS: eight moves, seven retained references, lexical builders, '
          'live State tile context, two facade-routed Hosts, 23 earlier destinations')

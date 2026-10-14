"""PROVISIONAL P14 real-manifest tests; deliberately makes no history claim."""
import argparse
import json
from pathlib import Path

import check_dart_moves as d
from dart_move_fixture import materialize
from dart_move_history import git_text
from test_dart_identify_moves import snippet_tokens
import re


def run(package):
    spec = json.loads((d.ROOT / 'dev/tool/dart_moves/vplayer_p14.json').read_text())
    assert spec['status'] == 'PROVISIONAL'
    original = git_text(spec['base'], spec['source'])
    sources = materialize(spec, original, package)
    assert not d.check(spec, original, sources, package)
    assert sum(r['fate'] == 'moved' for r in spec['declarations']) == 13
    assert sum(e['count'] for r in spec['declarations'] if r['fate'] == 'retained'
               for e in r.get('substitutions', [])) == 25
    assert len(spec['patched_class_projection']) == 3
    for adapter in spec['patched_class_projection']:
        row = next(r for r in spec['declarations'] if r['original'] == adapter)
        assert row['fate'] == 'patched' and len(row['patches']) == 1
        assert row['patches'][0]['count'] == 1
    facade = spec['source']
    keys, restore, save = spec['destinations']
    forward = ('Future<Map<String, dynamic>?> readLocalResume({required String? contentId, '
               'required String resumeKey, required Future<Map<String, dynamic>?> Function() enhanced}) '
               '=> VideoPlayerScreen.readLocalResume(contentId: contentId, resumeKey: resumeKey, enhanced: enhanced);')
    scaffold = spec['scaffolding'][facade]['_VpResumeRestoreHostAdapter']
    assert scaffold and re.search(r"\s*".join(re.escape(t) for t in snippet_tokens(forward)), sources[facade])

    cases = [
        ('static forwarder eager enhanced', facade, forward, forward.replace('enhanced: enhanced', 'enhanced: () async => await enhanced()')),
        ('static forwarder copied map', facade, forward, forward.replace('=> VideoPlayerScreen', 'async => Map<String, dynamic>.from((await VideoPlayerScreen').replace('enhanced: enhanced);', 'enhanced: enhanced))!);')),
        ('static forwarder guard', facade, forward, forward.replace('=> VideoPlayerScreen', '=> contentId == null ? Future.value(null) : VideoPlayerScreen')),
        ('static forwarder argument swap', facade, forward, forward.replace('contentId: contentId, resumeKey: resumeKey', 'contentId: resumeKey, resumeKey: contentId!')),
        ('static forwarder extra await', facade, forward, forward.replace('=> VideoPlayerScreen', 'async => await VideoPlayerScreen')),
        ('static forwarder wrong owner', facade, forward, forward.replace('=> VideoPlayerScreen', '=> _s.VideoPlayerScreen')),
        ('constructor Host read', restore, 'VpResumeRestore(this._host);', 'VpResumeRestore(this._host) { _host.duration; }'),
        ('saved row captured early', save, 'var pos = positionOverride ?? _host.position;', 'var pos = Duration.zero;'),
        ('wrong live speed getter', facade, 'double get playbackSpeed => _s._display.playbackSpeed;', 'double get playbackSpeed => 1.0;'),
        ('restore effectful speed setter', facade, 'set playbackSpeed(double v) => _s._display.playbackSpeed = v;', 'set playbackSpeed(double v) => _s._display.setPlaybackSpeed(v);'),
        ('wrong sibling key forwarder', facade, 'String get resumeKey => _s._resumeKeys.resumeKey;', 'String get resumeKey => _s.widget.videoUrl;'),
        ('guard cloned', facade, 'ResumeWriteGuard get resumeWriteGuard => _s._resumeWriteGuard;', 'ResumeWriteGuard get resumeWriteGuard => ResumeWriteGuard();'),
        ('destination facade import', restore, "import 'dart:async';", "import 'package:debrify/screens/video_player_screen.dart';"),
        ('destination sibling import', restore, "import 'dart:async';", "import 'vp_resume_save.dart';"),
    ]
    for label, path, before, after in cases:
        pattern = r'\s*'.join(re.escape(t) for t in snippet_tokens(before))
        matches = list(re.finditer(pattern, sources[path]))
        assert matches, (label, before)
        found = matches[0]
        changed = dict(sources, **{path: sources[path][:found.start()] + after + sources[path][found.end():]})
        errors = d.check(spec, original, changed, package)
        assert errors, label
        print('P14 ' + label + ': rejected')
    print('PASS PROVISIONAL: 13 moves, 28 reference rewrites incl. three adapters; history BLOCKED')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--parser-package', type=Path, required=True)
    run(p.parse_args().parser_package)

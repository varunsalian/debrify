"""Whole-checker wiring negatives against reviewed exact cached bindings."""
import copy
import json
import tempfile
from pathlib import Path

from check_settings_moves import ROOT, all_nodes, check, tokens
from check_verbatim_moves import parse


def self_test(original, sources, rows, source, config, package):
    before = all_nodes(parse(sources, package))
    probe = dict(sources)
    # Both factories run inside the owning State; no protected external call.
    for owner, text in [
        ('_CardState', 'Object get setterProbe => SpotlightBoardSetterBinding(this, setState);'),
        ('SpotlightBoardState', '''Object? sectionCache;
          List<StremioMeta>? heroCache;
          Object get sectionProbe => sectionCache ??= SpotlightBoardSectionBinding();
          List<StremioMeta> get heroProbe => widget.hero;
          Color Function(AppTheme) get groundProbe => SpotlightBoard.groundOf;'''),
    ]:
        declared = before[(source, '', owner)]
        brace = probe[source].find('{', declared['start'])
        # Apply in descending original-offset order in the caller loop.
        probe[source] = probe[source][:brace+1] + '\n' + text + '\n' + probe[source][brace+1:]
    probe[source] += '''
class SpotlightBoardSetterBinding {
  final Object state;
  final void Function(VoidCallback) setState;
  SpotlightBoardSetterBinding(this.state, this.setState);
}
class SpotlightBoardSectionBinding {}
'''
    # The Board insertion is above the Card insertion; refresh AST locations.
    nodes = all_nodes(parse(probe, package))
    scaffolds = [dict(file=k[0], owner=k[1], name=k[2], tokens=tokens(n))
                 for k,n in nodes.items() if k not in before]
    with tempfile.TemporaryDirectory(dir=ROOT / '.dart_tool/spotlight_board') as directory:
        sidecar = Path(directory) / 'bindings.json'
        sidecar.write_text(json.dumps({'scaffolds':scaffolds}))
        configured = copy.deepcopy(config)
        configured['sidecars']['scaffolding'] = str(sidecar)
        assert not check(original, probe, rows, source, package, context_guard=True, config=configured)
        for label, owner, name, old, new in [
            ('board setter tear-off','_CardState','setterProbe','this, setState','this, SpotlightBoardState().setState'),
            ('setter wrapper','_CardState','setterProbe','this, setState','this, (callback) => setState(callback)'),
            ('section built per access','SpotlightBoardState','sectionProbe','sectionCache ??= SpotlightBoardSectionBinding()','SpotlightBoardSectionBinding()'),
            ('cached view snapshot','SpotlightBoardState','heroProbe','widget.hero','heroCache ??= widget.hero'),
            ('view static wrapper','SpotlightBoardState','groundProbe','SpotlightBoard.groundOf','(app) => SpotlightBoard.groundOf(app)'),
        ]:
            node = nodes[(source, owner, name)]
            assert old in node['text']
            changed = dict(probe)
            changed[source] = changed[source][:node['start']] + node['text'].replace(old,new,1) + changed[source][node['end']:]
            failures = check(original, changed, rows, source, package, context_guard=True, config=configured)
            assert any('scaffold' in failure.lower() for failure in failures),(label,failures)
            print('Spotlight real binding '+label+': rejected')
        node = nodes[(source, 'SpotlightBoardState', 'build')]
        start = node['bodyOffset'] - node['start']
        prefix, body = node['text'][:start], node['text'][start:]
        statement = 'sectionCache = SpotlightBoardSectionBinding();'
        if body.startswith('{'):
            body = '{ ' + statement + body[1:]
        else:
            assert body.startswith('=>')
            body = '{ ' + statement + ' return ' + body[2:] + ' }'
        changed = dict(probe)
        changed[source] = (changed[source][:node['start']] + prefix + body
                           + changed[source][node['end']:])
        failures = check(original, changed, rows, source, package,
                         context_guard=True, config=configured)
        assert any('Non-verbatim' in failure or 'Forwarder' in failure
                   for failure in failures), failures
        print('Spotlight real binding section built on every build: rejected')

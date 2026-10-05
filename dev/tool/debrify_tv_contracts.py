"""Debrify TV-only argument pairs and callback expressions before moves normalize."""
import json


def check_contracts(lookup, rows, source, config):
    from check_settings_moves import ROOT, normalize, tokens
    from torbox_callback_identity import arguments, callback_argument
    errors = []
    def code(values):
        return [v for v in values if not v.startswith(('//', '/*'))]
    by_original = {row['original_name']: row for row in rows}

    def located(identity):
        row = by_original[identity]
        owner, _, name = identity.rpartition('.')
        return lookup.get((row['destination_file'], row['destination_class'], row['new_name'])) or lookup[(source, owner, name or identity)]

    def call_name(name):
        forwarder = next((f['call'] for f in config.get('constructor_forwarders', []) if f['original_name']==name), None)
        if forwarder:
            return forwarder
        alias = next((a['alias'] for a in config.get('type_aliases', []) if a['original_name']==name), None)
        if alias:
            return alias
        row = by_original.get('_DebrifyTVScreenState.' + name)
        return located(row['original_name'])['name'] if row else name

    for spec in json.loads((ROOT/config['sidecars']['handoff']).read_text())['sites']:
        try:
            node = located(spec['original_member'])
            row = by_original[spec['original_member']]
            call = arguments(code(tokens(node)), call_name(spec['call']))[spec['occurrence']]
            actual = [(arg[0], normalize(arg[2:], rows, row)) for arg in call if arg[1:2] == [':']]
            expected = [(a['name'], normalize(a['tokens'], rows, row)) for a in spec['arguments']]
            if len(actual) != len(call) or actual != expected:
                errors.append('Debrify TV handoff argument name/value pairs changed: '+spec['site'])
        except (KeyError, IndexError, ValueError):
            errors.append('Missing Debrify TV handoff: '+spec['site'])
    for ordinal, spec in enumerate(json.loads((ROOT/config['sidecars']['callbacks']).read_text())['sites']):
        try:
            node = located(spec['member'])
            row = by_original[spec['member']]
            calls = arguments(code(tokens(node)), call_name(spec['call']))
            actual = callback_argument(calls[spec['occurrence']], spec)
            if len(calls) != spec['count'] or normalize(actual, rows, row) != normalize(code(spec['expression']), rows, row):
                errors.append('Debrify TV original callback expression changed: '+str(ordinal)+' '+spec['member']+' '+spec['named_argument'])
        except (KeyError, IndexError, ValueError):
            errors.append('Missing Debrify TV callback site: '+str(ordinal))
    return errors

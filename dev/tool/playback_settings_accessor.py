"""Exact opt-in relocation of the frozen playback accessor over composition."""

def check_accessor(lookup, source, spec, expected, rows, normalize_accessor, tokens):
    relocation = spec['composition']
    accessor = lookup.get((source, '', spec['name']))
    bridge = lookup.get((relocation['file'], '', relocation['name']))
    if accessor is None or bridge is None:
        return ['Missing playback composition accessor/forwarder']
    forward = ['@', 'visibleForTesting', 'Map', '<', 'String', ',', 'Object', '?', '>',
               spec['name'], '(', 'State', '<', 'ExternalPlayerSettingsPage', '>', 'state', ')', '=>', relocation['name'],
               '(', '(', 'state', 'as', relocation['state'], ')', '.', '_sections', ')', ';']
    if tokens(accessor) != forward or len(accessor['text'].splitlines()) > 5:
        return ['Playback accessor State cast/forwarder changed']
    header = ['Map', '<', 'String', ',', 'Object', '?', '>', relocation['name'],
              '(', relocation['type'], 's', ')', '{']
    current = tokens(bridge)
    if current[:len(header)] != header:
        return ['Playback composition accessor header changed']
    original_header = ['@', 'visibleForTesting', 'Map', '<', 'String', ',', 'Object', '?', '>',
                       spec['name'], '(', 'State', '<', 'ExternalPlayerSettingsPage', '>', 'state', ')', '{',
                       'final', 's', '=', 'state', 'as', relocation['state'], ';']
    if expected[:len(original_header)] != original_header:
        return ['Frozen playback accessor header is not the original State seam']
    before = expected[len(original_header):]
    after = current[len(header):]
    if normalize_accessor(after, spec, rows) != normalize_accessor(before, spec, rows):
        return ['Playback composition accessor changed outside receiver edits']
    return []

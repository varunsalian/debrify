"""Kotlin capture roles and the exact loader → Host → volatile-storage chain."""
from pathlib import Path
import re
import subprocess

import check_kotlin_moves as k

ACTIVITY = 'com.debrify.app.tv.AndroidTvTorrentPlayerActivity'
PIPELINE = 'com.debrify.app.tv.TvMediaPipelineController'
HOST = PIPELINE + '$Host'
HOST_IMPL = ACTIVITY + '$mediaPipelineController$1'
FACTORY = 'Landroidx/media3/extractor/DefaultExtractorsFactory;'


def reviewed_chains():
    data_spec = '(Landroidx/media3/datasource/DataSpec;)Landroidx/media3/datasource/DataSpec;'
    return [dict(field=field, descriptor=descriptor, method=method, signature=signature, role=role)
            for field, descriptor, method, signature, role in [
                ('activeVodHeaders', 'Lkotlin/Pair;', 'resolveDataSpec', data_spec, 'vod_resolver'),
                ('currentIptvHttpHeaders', 'Ljava/util/Map;', 'resolveDataSpec', data_spec, 'iptv_resolver'),
                ('iptvStrictTsActive', 'Z', 'createExtractors', '()[Landroidx/media3/extractor/Extractor;', 'extractors_no_args'),
                ('iptvStrictTsActive', 'Z', 'createExtractors', '(Landroid/net/Uri;Ljava/util/Map;)[Landroidx/media3/extractor/Extractor;', 'extractors_with_uri')]]


def declarations(folder):
    """Include Kotlin's package-private final captures, not only Java public fields."""
    paths = sorted(Path(folder).glob('*.class'))
    if not paths:
        raise ValueError('volatile-chain compiled classes missing')
    raw = subprocess.check_output([str(k.JBR / 'bin/javap'), '-p', '-s', *map(str, paths)], text=True)
    fields, methods, owner, member = {}, {}, None, None
    for line in raw.splitlines():
        if re.match(r'^\S.*\b(class|interface)\b', line):
            owner = re.search(r'\b(?:class|interface) (\S+)', line).group(1)
            member = None
        elif member and line.strip().startswith('descriptor:'):
            descriptor = line.split(':', 1)[1].strip()
            if '(' in member:
                methods[owner, member] = descriptor
            else:
                parts = member.removesuffix(';').split()
                fields[owner, parts[-1]] = dict(descriptor=descriptor,
                    final='final' in parts, volatile='volatile' in parts)
            member = None
        elif line.startswith('  ') and line.strip().endswith(';'):
            member = line.strip()
        else:
            member = None
    return fields, methods


def binary(name):
    return name.replace('.', '/')


def require_field(fields, owner, name, descriptor, *, final=False, volatile=False):
    if fields.get((owner, name)) != dict(descriptor=descriptor, final=final, volatile=volatile):
        raise ValueError('volatile-chain field descriptor/final/volatile flags differ: ' + owner + '.' + name)


def one_call(scope, opcode, target):
    matches = [i for i in scope if i['opcode'] == opcode and i['operand'].endswith(target)]
    if len(matches) != 1:
        raise ValueError('volatile-chain requires exactly one getter invocation per read site: ' + target)
    return matches[0]


def method_scope(instructions, owner, name, descriptor, methods):
    keys = [key for key, value in methods.items() if key[0] == owner and value == descriptor
            and re.search(r'\b' + re.escape(name) + r'\(', key[1])]
    if len(keys) != 1:
        raise ValueError('volatile-chain method owner/descriptor differs: ' + owner + '.' + name)
    return [i for i in instructions if (i['owner'], i['method']) == keys[0]]


def field_reads(scope):
    return [i for i in scope if i['opcode'] in ('getfield', 'getstatic')]


def exact_read(scope, name, descriptor):
    reads = field_reads(scope)
    if len(reads) != 1 or not reads[0]['operand'].endswith(' ' + name + ':' + descriptor):
        raise ValueError('volatile-chain accessor must reach exact single field: ' + name)


def audit_read_chains(pins, folder, instructions, relocated):
    if pins != reviewed_chains():
        raise ValueError('volatile read-chain descriptor/role coverage differs')
    fields, methods = declarations(folder)
    root = PIPELINE if relocated else ACTIVITY
    suffixes = dict(vod_resolver='$setupPlayer$dataSourceFactory$1$1',
                    iptv_resolver='$setupPlayer$finalDataSourceFactory$1',
                    extractors_no_args='$setupPlayer$mediaSourceFactory$iptvExtractors$1',
                    extractors_with_uri='$setupPlayer$mediaSourceFactory$iptvExtractors$1')
    results = []
    for pin in pins:
        field, descriptor = pin['field'], pin['descriptor']
        require_field(fields, ACTIVITY, field, descriptor, volatile=True)
        if any(name == field and owner != ACTIVITY for owner, name in fields):
            raise ValueError('volatile-chain storage must remain a single Activity field')
        owner = root + suffixes[pin['role']]
        captures = {name: info for (cls, name), info in fields.items() if cls == owner}
        owner_capture = '$this_run' if pin['role'] == 'vod_resolver' else 'this$0'
        permitted = {owner_capture: dict(descriptor='L' + binary(root) + ';', final=True, volatile=False)}
        if pin['role'].startswith('extractors'):
            permitted.update({name: dict(descriptor=FACTORY, final=True, volatile=False)
                              for name in ('$strictTs', '$aggressiveTs')})
        if captures != permitted:
            raise ValueError('Kotlin loader capture descriptor/role differs; snapshot capture forbidden: ' + owner)
        scope = method_scope(instructions, owner, pin['method'], pin['signature'], methods)
        reads = field_reads(scope)
        # DataSpec.uri is an immutable argument field used by the VOD origin
        # check; it is not a retained/captured header value.
        argument_read = 'Field androidx/media3/datasource/DataSpec.uri:Landroid/net/Uri;'
        if any(not (pin['role'] == 'vod_resolver' and i['operand'] == argument_read)
               and not any(i['operand'].endswith(' ' + name + ':' + info['descriptor'])
                           for name, info in permitted.items()) for i in reads):
            raise ValueError('Kotlin loader read escapes reviewed final capture roles')
        if sum(i['operand'].endswith(' ' + owner_capture + ':L' + binary(root) + ';') for i in reads) != 1:
            raise ValueError('volatile-chain must read exactly one final owner capture')
        getter = 'get' + field[0].upper() + field[1:]
        accessor = binary(ACTIVITY) + '.access$' + getter + '$p:(L' + binary(ACTIVITY) + ';)' + descriptor
        if relocated:
            # The generated owner accessor reads one final Host field; each
            # interface invocation then reaches the original Activity accessor.
            host_access = binary(PIPELINE) + '.access$getHost$p:(L' + binary(PIPELINE) + ';)L' + binary(HOST) + ';'
            one_call(scope, 'invokestatic', host_access)
            one_call(scope, 'invokeinterface', binary(HOST) + '.' + getter + ':()' + descriptor)
            require_field(fields, PIPELINE, 'host', 'L' + binary(HOST) + ';', final=True)
            access_scope = method_scope(instructions, PIPELINE, 'access$getHost$p',
                '(L' + binary(PIPELINE) + ';)L' + binary(HOST) + ';', methods)
            exact_read(access_scope, 'host', 'L' + binary(HOST) + ';')
            require_field(fields, HOST_IMPL, 'this$0', 'L' + binary(ACTIVITY) + ';', final=True)
            if {name for cls, name in fields if cls == HOST_IMPL} != {'this$0'}:
                raise ValueError('computed Host cannot retain a snapshot/backing field')
            host_scope = method_scope(instructions, HOST_IMPL, getter, '()' + descriptor, methods)
            exact_read(host_scope, 'this$0', 'L' + binary(ACTIVITY) + ';')
            one_call(host_scope, 'invokestatic', accessor)
        else:
            one_call(scope, 'invokestatic', accessor)
        storage = method_scope(instructions, ACTIVITY, 'access$' + getter + '$p',
                               '(L' + binary(ACTIVITY) + ';)' + descriptor, methods)
        exact_read(storage, field, descriptor)
        results.append(dict(site=pin, captures=captures, loader=scope, storage=storage, relocated=relocated))
    return results

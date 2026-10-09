"""Offline compiled super-constructor, ListView and preserved receiver audit."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import unittest

import check_kotlin_moves as k
from check_kotlin_overloads import audit, bytecode, resolve, resolve_inherited


class Phase14OverloadsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase14-overloads')
        cls.original = (k.ROOT / 'dev/tool/fixtures/kotlin_overloads/phase14.kt').read_text()
        unit = k.parse({'base': cls.original})['base']
        cls.node = next(n for n in k.walk(unit['declarations']) if n['selector'] == 'fun exhaust()')
        body = cls.original[cls.node['start']:cls.node['end']]
        for site in sorted(unit['all_this_sites'], key=lambda s: s['start'], reverse=True):
            if cls.node['start'] <= site['start'] < cls.node['end'] and 'lambda_receiver' not in site:
                a, b = site['start'] - cls.node['start'], site['end'] - cls.node['start']
                body = body[:a] + 'activity' + body[b:]
        body = body.replace('runOnUiThread {', 'activity.runOnUiThread {')
        cls.current = {'Controller.kt': 'package com.debrify.app.tv\nimport android.widget.ArrayAdapter\nimport android.widget.ListView\nimport android.widget.TextView\nclass FixtureController(private val activity: androidx.appcompat.app.AppCompatActivity) {\n' + body + '\n}\n'}
        row = dict(original=cls.node['id'], fate='moved', destination='Controller.kt', target='class FixtureController/fun exhaust()')
        cls.manifest = dict(phase=14, declarations=[row], overload_audit=[], runnable_receivers=[], context_aliases=[],
            receiver_lambda_exclusions=[], receiver_lambda_transformations=[], listener_receivers=[], function_references=[], preserved_receivers=[])
        cls.before = cls.compile('original', None)
        cls.after = cls.compile('activity', cls.current['Controller.kt'])
        for site in unit['all_this_sites'] + unit['implicit_inherited_sites']:
            if not cls.node['start'] <= site['start'] < cls.node['end'] or 'lambda_receiver' in site:
                continue
            line = cls.original.count('\n', 0, site['start']) + 1
            first, last = [cls.original.count('\n', 0, site[key]) + 1 for key in ('call_start', 'call_end')]
            entry = dict(original=row['original'], line=line, context=cls.original.splitlines()[line - 1].strip(),
                callee=site['callee'], call_start_line=first, call_end_line=last, destination=row['destination'], target=row['target'])
            if site['receiver'] == 'implicit-inherited':
                pin, _ = resolve_inherited(cls.before, site, first, last)
                entry.update(receiver='implicit-inherited', expected_before=pin,
                    expected_after=dict(pin, owner='androidx/appcompat/app/AppCompatActivity'))
            else:
                target, evidence = resolve(cls.before, site, first, last)
                target, descriptor = target.split(':', 1)
                pin = dict(owner=target.rsplit('.', 1)[0], descriptor=descriptor, opcode=evidence[0]['opcode'])
                entry.update(expected_before=pin, expected_after=pin)
                if 'call_kind' in site:
                    entry['call_kind'] = site['call_kind']
            cls.manifest['overload_audit'].append(entry)
        exclusion = next(s for s in unit['all_this_sites'] if 'lambda_receiver' in s)
        line = cls.original.count('\n', 0, exclusion['start']) + 1
        cls.manifest['receiver_lambda_exclusions'] = [dict(original=row['original'], line=line,
            context=cls.original.splitlines()[line - 1].strip(), text='this', receiver='receiver-lambda',
            lambda_callee='apply', lambda_receiver='ListView(this)', reason='ListView remains its own apply receiver.')]
        cls.manifest['receiver_lambda_transformations'] = [dict(original=row['original'], line=line,
            constructor_line=line - 1, context=cls.original.splitlines()[line - 2].strip(),
            before='ListView(this)', after='ListView(activity)', callee='ListView', reason='Only the Activity context argument changes.')]
        for site in unit['preserved_receiver_sites']:
            if not cls.node['start'] <= site['start'] < cls.node['end']:
                continue
            line = cls.original.count('\n', 0, site['start']) + 1
            entry = dict(original=row['original'], line=line, context=cls.original.splitlines()[line - 1].strip(),
                text=site['text'], binding=site['binding'], callee=site.get('callee'), reason='View/adapter binding or named constructor argument preserved.')
            if site.get('callee'):
                pin, _ = resolve_inherited(cls.before, site, line, line)
                entry.update(expected_before=pin, expected_after=dict(pin,
                    owner=pin['owner'].replace('AndroidTvTorrentPlayerActivity', 'FixtureController')))
            cls.manifest['preserved_receivers'].append(entry)
        cls.wrong = dict(cls.current)
        cls.wrong['Controller.kt'] = cls.wrong['Controller.kt'].replace('ArrayAdapter<String>(activity, 0,', 'ArrayAdapter<String>(activity, 0L,')
        cls.changed = cls.compile('wrong-super-constructor', cls.wrong['Controller.kt'])
        (cls.folder / 'manifest.json').write_text(json.dumps(cls.manifest, indent=2) + '\n')

    @classmethod
    def compile(cls, label, controller):
        folder = cls.folder / label
        folder.mkdir(parents=True, exist_ok=True)
        original = cls.original if controller is None else cls.original[:cls.node['start']] + cls.original[cls.node['end']:]
        sources = {
            'Original.kt': original,
            'Context.kt': 'package android.content\nopen class Context\n',
            'Activity.kt': 'package android.app\nopen class Activity: android.content.Context() { fun runOnUiThread(r: Runnable) { r.run() } }\n',
            'Compat.kt': 'package androidx.appcompat.app\nopen class AppCompatActivity: android.app.Activity()\n',
            'Widgets.kt': 'package android.widget\nopen class TextView(val context: android.content.Context) { var text: String? = null }\nclass ListView(val context: android.content.Context) { var adapter: Any? = null }\nopen class ArrayAdapter<T>(val context: android.content.Context, count: Int, val rows: List<T>) { constructor(context: android.content.Context, count: Long, rows: List<T>): this(context, count.toInt(), rows) { error("super-constructor changed") }; fun getItem(position: Int): T = rows[position]; open fun getView(position: Int): TextView = TextView(context) }\n',
            'Addon.kt': 'package com.debrify.app.tv\ndata class Addon(val resources: List<String>)\nobject Probe { val contexts = mutableListOf<android.content.Context>() }\n',
            'Runner.kt': 'package com.debrify.app.tv\nobject Runner { @JvmStatic fun main(args: Array<String>) { val a=AndroidTvTorrentPlayerActivity(); ' +
                ('a.exhaust()' if controller is None else 'FixtureController(a).exhaust()') + '; check(Probe.contexts.size == 3); check(Probe.contexts.all { it === a }); println("constructor context and inner receivers preserved") } }\n',
        }
        if controller:
            sources['Controller.kt'] = controller
        paths = []
        for name, text in sources.items():
            p = folder / name
            p.write_text(text)
            paths.append(str(p))
        cache = Path.home() / '.gradle/caches/modules-2/files-2.1'
        jars = [next((cache / g / a / v).glob('*/*.jar')) for g, a, v in [
            ('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.2.20'), ('org.jetbrains.kotlin', 'kotlin-stdlib', '2.2.20'),
            ('org.jetbrains.kotlin', 'kotlin-reflect', '2.2.0'), ('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.8.0'), ('org.jetbrains', 'annotations', '13.0')]]
        target = folder / 'classes'
        result = subprocess.run([str(k.JBR / 'bin/java'), '-cp', ':'.join(map(str, jars)),
            'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib', '-no-reflect', '-classpath', ':'.join(map(str, jars)),
            '-d', str(target), *paths], capture_output=True, text=True)
        (folder / 'compile.log').write_text(result.stdout + result.stderr)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        flat = folder / 'audit-classes'
        flat.mkdir(exist_ok=True)
        for p in (target / 'com/debrify/app/tv').glob('*.class'):
            if p.name.startswith(('AndroidTvTorrentPlayerActivity', 'FixtureController')):
                shutil.copy2(p, flat / p.name)
        result = subprocess.run([str(k.JBR / 'bin/java'), '-cp', str(target) + ':' + str(jars[1]),
            'com.debrify.app.tv.Runner'], capture_output=True, text=True)
        (folder / 'runtime.log').write_text(result.stdout + result.stderr)
        if label == 'wrong-super-constructor':
            if result.returncode == 0 or 'super-constructor changed' not in result.stderr:
                raise AssertionError('constructor negative did not fail its intended runtime assertion')
        elif result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        return bytecode(flat)

    def test_compiled_positive(self):
        result = audit(self.manifest, self.original, self.current, self.before, self.after)
        self.assertEqual(3, len(result))
        self.assertEqual(4, len(self.manifest['preserved_receivers']))
        (self.folder / 'audit.json').write_text(json.dumps(result, indent=2) + '\n')

    def test_compiled_super_constructor_descriptor_change(self):
        with self.assertRaisesRegex(ValueError, 'argument receiver dispatch changed'):
            audit(self.manifest, self.original, self.wrong, self.before, self.changed)

    def test_super_constructor_opcode_pin(self):
        m = copy.deepcopy(self.manifest)
        next(s for s in m['overload_audit'] if s['callee'] == 'ArrayAdapter')['expected_after']['opcode'] = 'invokevirtual'
        with self.assertRaisesRegex(ValueError, 'argument receiver dispatch changed'):
            audit(m, self.original, self.current, self.before, self.after)

    def test_super_constructor_misclassification(self):
        m = copy.deepcopy(self.manifest)
        next(s for s in m['overload_audit'] if s['callee'] == 'ArrayAdapter')['call_kind'] = 'KtCallExpression'
        with self.assertRaisesRegex(ValueError, 'super-constructor audit call kind differs'):
            audit(m, self.original, self.current, self.before, self.after)

    def test_inner_this_substitution(self):
        current = {p: s.replace('this.adapter', 'activity.adapter') for p, s in self.current.items()}
        with self.assertRaisesRegex(ValueError, 'receiver-lambda expression substituted or binding changed'):
            audit(self.manifest, self.original, current, self.before, self.after)

    def test_preserved_adapter_dispatch_pin(self):
        m = copy.deepcopy(self.manifest)
        next(s for s in m['preserved_receivers'] if s['callee'] == 'getItem')['expected_after']['owner'] = 'host/OtherAdapter'
        with self.assertRaisesRegex(ValueError, 'preserved receiver compiled dispatch changed'):
            audit(m, self.original, self.current, self.before, self.after)

    def test_named_argument_is_not_an_inherited_getter(self):
        m = copy.deepcopy(self.manifest)
        next(s for s in m['preserved_receivers'] if s['text'] == 'resources')['binding'] = 'receiver-getter'
        with self.assertRaisesRegex(ValueError, 'preserved receiver coverage/binding differs'):
            audit(m, self.original, self.current, self.before, self.after)

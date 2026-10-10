"""Offline compiled phase-4 receiver fixture and independent negative controls."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_toolchain import kotlin_jars
from check_kotlin_overloads import audit, bytecode


class Phase4OverloadsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase4-overloads')
        cls.original = (k.ROOT / 'dev/tool/fixtures/kotlin_overloads/phase4.kt').read_text()
        unit = k.parse({'base': cls.original})['base']
        nodes = list(k.walk(unit['declarations']))
        function = next(n for n in nodes if n['id'].endswith('/fun render()'))
        field = next(n for n in nodes if n['id'].endswith('/property tick'))
        cls.current = {'Controller.kt': 'package com.debrify.app.tv\n\nimport androidx.appcompat.app.AppCompatActivity\n\n'
            'class FixtureController(private val activity: AppCompatActivity) {\n'
            + cls.original[field['start']:field['end']] + '\n'
            + cls.original[function['start']:function['end']].replace('val ctx = this', 'val ctx = activity')
                .replace('(this)', '(activity)') + '\n}\n'}
        # The Runnable invocation deliberately remains this, never activity.
        cls.current['Controller.kt'] = cls.current['Controller.kt'].replace('Accept.post(activity)', 'Accept.post(this)')
        row = dict(original=function['id'], fate='moved', destination='Controller.kt', target='class FixtureController/fun render()')
        cls.manifest = dict(phase=4, declarations=[row], overload_audit=[], runnable_receivers=[], context_aliases=[])
        for site in unit['all_this_sites']:
            line = cls.original.count('\n', 0, site['start']) + 1
            base = dict(original=function['id'], line=line, context=cls.original.splitlines()[line - 1].strip())
            if site['receiver'] == 'Runnable':
                cls.manifest['runnable_receivers'].append(dict(**base, reason='Fixture Runnable self identity and repost.'))
                continue
            alias = next((a for a in unit['context_aliases'] if a['start'] == site['start']), None)
            if alias:
                cls.manifest['context_aliases'].append(dict(**base, name=alias['name'], uses=[dict(
                    line=cls.original.count('\n', 0, x['start']) + 1, callee=x['callee'],
                    context=cls.original.splitlines()[cls.original.count('\n', 0, x['start'])].strip()) for x in alias['uses']]))
            for call in alias['uses'] if alias else [site]:
                call_line = cls.original.count('\n', 0, call['start']) + 1
                cls.manifest['overload_audit'].append(dict(original=function['id'], line=call_line,
                    context=cls.original.splitlines()[call_line - 1].strip(), callee=call['callee'],
                    call_start_line=cls.original.count('\n', 0, call['call_start']) + 1,
                    call_end_line=cls.original.count('\n', 0, call['call_end']) + 1,
                    destination='Controller.kt', target=row['target'], **({'alias': alias['name']} if alias else {})))
        cls.before = cls.compile('original', cls.original)
        cls.after = cls.compile('moved', cls.current['Controller.kt'])
        # Context is deliberately wider: the ring selects a different constructor.
        cls.bad_current = {'Controller.kt': cls.current['Controller.kt'].replace('activity: AppCompatActivity', 'activity: android.content.Context')}
        # Other constructor constraints remain compilable, so only ring changes.
        bad_calls = (k.ROOT / 'dev/tool/fixtures/kotlin_overloads/phase4_calls.kt').read_text().replace(
            'class SubtitleLinePickerController(activity: FragmentActivity)', 'class SubtitleLinePickerController(activity: Context)').replace(
            'class SubtitleSyncOverlayController(activity: FragmentActivity)', 'class SubtitleSyncOverlayController(activity: Context)')
        cls.bad = cls.compile('wrong-constructor', cls.bad_current['Controller.kt'], bad_calls)
        (cls.folder / 'manifest.json').write_text(json.dumps(cls.manifest, indent=2) + '\n')

    @classmethod
    def compile(cls, label, source, calls=None):
        folder = cls.folder / label
        folder.mkdir(parents=True, exist_ok=True)
        sources = {'Fixture.kt': source,
            'Context.kt': 'package android.content\nopen class Context\n',
            'FragmentActivity.kt': 'package androidx.fragment.app\nopen class FragmentActivity : android.content.Context()\n',
            'AppCompatActivity.kt': 'package androidx.appcompat.app\nopen class AppCompatActivity : androidx.fragment.app.FragmentActivity()\n',
            'Calls.kt': calls or (k.ROOT / 'dev/tool/fixtures/kotlin_overloads/phase4_calls.kt').read_text()}
        paths = []
        for name, text in sources.items():
            path = folder / name; path.write_text(text); paths.append(str(path))
        jars = kotlin_jars()
        target = folder / 'classes'
        result = subprocess.run([str(k.JBR / 'bin/java'), '-cp', ':'.join(map(str, jars)),
            'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib', '-no-reflect', '-classpath', ':'.join(map(str, jars)),
            '-d', str(target), *paths], capture_output=True, text=True)
        (folder / 'compile.log').write_text(result.stdout + result.stderr)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        flat = folder / 'audit-classes'; flat.mkdir(exist_ok=True)
        import shutil
        for path in (target / 'com/debrify/app/tv').glob('*.class'):
            if path.name.startswith(('AndroidTvTorrentPlayerActivity', 'FixtureController')):
                shutil.copy2(path, flat / path.name)
        return bytecode(flat)

    def test_complete_phase4_compiled_audit(self):
        results = audit(self.manifest, self.original, self.current, self.before, self.after)
        self.assertEqual(8, len(results))
        self.assertEqual(7, sum('.<init>:' in x['resolved_before'] for x in results))
        (self.folder / 'audit.json').write_text(json.dumps(results, indent=2) + '\n')

    def test_wrong_receiver_classification(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['runnable_receivers'].pop()
        with self.assertRaisesRegex(ValueError, 'wrong receiver classification'):
            audit(manifest, self.original, self.current, self.before, self.after)

    def test_unlisted_alias(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['context_aliases'].clear()
        with self.assertRaisesRegex(ValueError, 'unlisted alias'):
            audit(manifest, self.original, self.current, self.before, self.after)

    def test_constructor_resolved_to_different_overload(self):
        with self.assertRaisesRegex(ValueError, 'overload changed.*AutoSyncRingView'):
            audit(self.manifest, self.original, self.bad_current, self.before, self.bad)

    def test_alias_use_cannot_be_omitted(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['overload_audit'] = [x for x in manifest['overload_audit'] if not x.get('alias')]
        with self.assertRaisesRegex(ValueError, 'audit coverage differs'):
            audit(manifest, self.original, self.current, self.before, self.after)

    def test_non_call_this_is_collected(self):
        unit = k.parse({'test': self.original})['test']
        self.assertEqual(2, sum(x['receiver'] == 'Runnable' for x in unit['all_this_sites']))
        self.assertTrue(any('callee' not in x and x['text'] == 'this' for x in unit['all_this_sites']))

"""Offline bytecode controls for constructor provenance and virtual finish."""
from pathlib import Path
import shutil
import subprocess
import unittest

import check_kotlin_moves as k
from check_kotlin_overloads import bytecode, typed_bytecode, resolve_inherited
from kotlin_overloads_phase18 import audit_shuffle_constructor


class Phase18OverloadsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/overload-selftests-phase18')
        cls.source = (k.ROOT / 'dev/tool/fixtures/kotlin_overloads/phase18.kt').read_text()
        cls.compile('original', cls.source)
        cls.pin = dict(constructor=dict(owner='com/debrify/app/tv/ShowShuffle',
            descriptor='(Lkotlin/random/Random;ILkotlin/jvm/internal/DefaultConstructorMarker;)V',
            opcode='invokespecial'))

    @classmethod
    def compile(cls, label, source):
        folder = cls.folder / label
        folder.mkdir(parents=True, exist_ok=True)
        sources = {'Fixture.kt': source,
            'Activity.kt': 'package android.app\nopen class Activity { open fun finish() {} }\n',
            'Compat.kt': 'package androidx.appcompat.app\nopen class AppCompatActivity : android.app.Activity() { override fun finish() { super.finish() } }\n'}
        paths = []
        for name, text in sources.items():
            p = folder / name
            p.write_text(text)
            paths.append(str(p))
        cache = Path.home() / '.gradle/caches/modules-2/files-2.1'
        jars = [next((cache / g / a / v).glob('*/*.jar')) for g, a, v in [
            ('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.2.20'),
            ('org.jetbrains.kotlin', 'kotlin-stdlib', '2.2.20'),
            ('org.jetbrains.kotlin', 'kotlin-reflect', '2.2.0'),
            ('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.8.0'),
            ('org.jetbrains', 'annotations', '13.0')]]
        result = subprocess.run([str(k.JBR / 'bin/java'), '-cp', ':'.join(map(str, jars)),
            'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib', '-no-reflect',
            '-classpath', ':'.join(map(str, jars)), '-d', str(folder / 'classes'), *paths],
            capture_output=True, text=True)
        (folder / 'compile.log').write_text(result.stdout + result.stderr)
        assert result.returncode == 0, result.stdout + result.stderr
        flat = folder / 'audit-classes'
        flat.mkdir(exist_ok=True)
        for p in (folder / 'classes/com/debrify/app/tv').glob('*.class'):
            shutil.copy2(p, flat / p.name)
        return typed_bytecode(flat)

    def constructor(self, label, source=None):
        source = source or self.source
        line = next(i + 1 for i, text in enumerate(source.splitlines())
                    if 'private val showShuffle' in text)
        calls = typed_bytecode(self.folder / label / 'audit-classes')
        owner = 'com.debrify.app.tv.AndroidTvTorrentPlayerActivity'
        return audit_shuffle_constructor(self.pin, calls, owner, line)

    def test_compiled_resolved_default_constructor(self):
        instructions = typed_bytecode(self.folder / 'original/audit-classes')
        lines = [i + 1 for i, text in enumerate(self.source.splitlines()) if 'private val showShuffle' in text]
        for owner, line in zip(('AndroidTvTorrentPlayerActivity', 'TvPlaybackNavigator'), lines):
            audit_shuffle_constructor(self.pin, instructions, 'com.debrify.app.tv.' + owner, line)

    def test_compiled_explicit_random_changes_constructor(self):
        changed = self.source.replace('= ShowShuffle()', '= ShowShuffle(Random(1))')
        self.compile('explicit-random', changed)
        with self.assertRaisesRegex(ValueError, 'resolved constructor/default dispatch changed'):
            self.constructor('explicit-random', changed)

    def test_compiled_factory_does_not_satisfy_constructor_pin(self):
        changed = self.source.replace('= ShowShuffle()', '= shuffleFactory()') + '\nfun shuffleFactory() = ShowShuffle()\n'
        self.compile('factory', changed)
        with self.assertRaisesRegex(ValueError, 'resolved constructor/default dispatch changed'):
            self.constructor('factory', changed)

    def test_compiled_wrong_constructor_descriptor_or_opcode_rejected(self):
        lines = [i + 1 for i, text in enumerate(self.source.splitlines()) if 'private val showShuffle' in text]
        instructions = typed_bytecode(self.folder / 'original/audit-classes')
        for key, value in [('opcode', 'invokestatic'), ('descriptor', '()V'), ('owner', 'Other')]:
            pin = dict(constructor={**self.pin['constructor'], key: value})
            with self.assertRaisesRegex(ValueError, 'resolved constructor/default dispatch changed'):
                audit_shuffle_constructor(pin, instructions, 'com.debrify.app.tv.AndroidTvTorrentPlayerActivity', lines[0])

    def finish(self, label, source, expected='androidx/appcompat/app/AppCompatActivity'):
        line = next(i + 1 for i, text in enumerate(source.splitlines()) if 'fun handBack() { activity.finish() }' in text
                    or 'fun handBack() { super.finish() }' in text or 'fun handBack() { StaticFinish.finish(activity) }' in text)
        calls = bytecode(self.folder / label / 'audit-classes')
        resolved, _ = resolve_inherited([c for c in calls if c['owner'] == 'com.debrify.app.tv.TvPlaybackNavigator'],
                                       dict(callee='finish'), line, line)
        self.assertEqual(dict(owner=expected, descriptor='()V', opcode='invokevirtual'), resolved)

    def test_compiled_finish_preserves_virtual_override_dispatch(self):
        self.finish('original', self.source)

    def test_compiled_super_finish_rejected(self):
        changed = self.source.replace('fun handBack() { activity.finish() }', 'fun handBack() { super.finish() }')
        self.compile('super', changed)
        with self.assertRaises(AssertionError):
            self.finish('super', changed)

    def test_compiled_static_finish_rejected(self):
        changed = self.source.replace('fun handBack() { activity.finish() }', 'fun handBack() { StaticFinish.finish(activity) }')
        self.compile('static', changed)
        with self.assertRaises(AssertionError):
            self.finish('static', changed)

    def test_compiled_widened_activity_type_rejected(self):
        changed = self.source.replace('private val activity: AppCompatActivity', 'private val activity: android.app.Activity')
        self.compile('wide', changed)
        with self.assertRaises(AssertionError):
            self.finish('wide', changed)

"""Real offline Kotlin controls: value captures, computed Hosts and writer owners."""
from pathlib import Path
import shutil
import subprocess
import unittest

import check_kotlin_moves as k
from check_kotlin_overloads import typed_bytecode, resolve
from kotlin_volatile_chains import reviewed_chains, audit_read_chains, declarations
from kotlin_overloads_phase16 import audit_identity, field_declarations
from kotlin_overloads_phase19 import writer_owners, constant_pins, audit_constants


class Phase19OverloadsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/overload-selftests-phase19')
        cls.source = (k.ROOT / 'dev/tool/fixtures/kotlin_overloads/phase19.kt').read_text()
        cls.compile('positive', cls.source)

    @classmethod
    def compile(cls, label, source):
        folder = cls.folder / label
        folder.mkdir(parents=True, exist_ok=True)
        sources = {'Fixture.kt': source,
            'Uri.kt': 'package android.net\nclass Uri\n',
            'Data.kt': '''package androidx.media3.datasource
class DataSpec { fun withHeaders(headers: Map<String, String>) = this }
class ResolvingDataSource {
    interface Resolver { fun resolveDataSpec(spec: DataSpec): DataSpec }
    class Factory(val resolver: Resolver)
}
''', 'Extract.kt': '''package androidx.media3.extractor
import android.net.Uri
interface Extractor
interface ExtractorsFactory {
    fun createExtractors(): Array<Extractor>
    fun createExtractors(uri: Uri, headers: Map<String, List<String>>): Array<Extractor>
}
class DefaultExtractorsFactory : ExtractorsFactory {
    override fun createExtractors(): Array<Extractor> = emptyArray()
    override fun createExtractors(uri: Uri, headers: Map<String, List<String>>): Array<Extractor> = emptyArray()
}
'''}
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
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        flat = folder / 'audit-classes'
        flat.mkdir(exist_ok=True)
        for p in (folder / 'classes/com/debrify/app/tv').glob('*.class'):
            shutil.copy2(p, flat / p.name)
        return flat, typed_bytecode(flat)

    def check(self, label, source, reason):
        folder, instructions = self.compile(label, source)
        with self.assertRaisesRegex(ValueError, reason):
            audit_read_chains(reviewed_chains(), folder, instructions, True)
        print('EXPECTED COMPILED PHASE-19 FAILURE:', label, reason)
        return declarations(folder)[0]

    def test_original_and_relocated_real_kotlin_read_chains(self):
        folder = self.folder / 'positive/audit-classes'
        for relocated in (False, True):
            result = audit_read_chains(reviewed_chains(), folder, typed_bytecode(folder), relocated)
            self.assertEqual(4, len(result))
            self.assertEqual('Landroidx/media3/extractor/DefaultExtractorsFactory;',
                             result[2]['captures']['$strictTs']['descriptor'])

    def test_real_kotlin_hoisted_map_snapshot(self):
        source = self.source
        # Change only the relocated body; the original retains its own receiver.
        start = source.index('class TvMediaPipelineController')
        source = source[:start] + source[start:].replace('val finalDataSourceFactory = ResolvingDataSource.Factory(',
            'val headers = host.currentIptvHttpHeaders\n        val finalDataSourceFactory = ResolvingDataSource.Factory(', 1).replace('                val headers = host.currentIptvHttpHeaders\n', '', 1)
        fields = self.check('map-snapshot', source, 'snapshot capture forbidden')
        self.assertTrue(any(name == '$headers' and f['descriptor'] == 'Ljava/util/Map;'
                            for (_, name), f in fields.items()))

    def test_real_kotlin_hoisted_pair_snapshot(self):
        start = self.source.index('class TvMediaPipelineController')
        source = self.source[:start] + self.source[start:].replace('val dataSourceFactory = run {\n',
            'val dataSourceFactory = run {\n            val headers = host.activeVodHeaders\n', 1).replace('                    val headers = host.activeVodHeaders\n', '', 1)
        fields = self.check('pair-snapshot', source, 'snapshot capture forbidden')
        self.assertTrue(any(name == '$headers' and f['descriptor'] == 'Lkotlin/Pair;'
                            for (_, name), f in fields.items()))

    def test_real_kotlin_boolean_strictTs_capture_not_factory(self):
        start = self.source.index('class TvMediaPipelineController')
        tail = self.source[start:].replace('val strictTs = DefaultExtractorsFactory()',
            'val strictFactory = DefaultExtractorsFactory()\n            val strictTs = host.iptvStrictTsActive')
        tail = tail.replace('(if (host.iptvStrictTsActive) strictTs else aggressiveTs)',
                            '(if (strictTs) strictFactory else aggressiveTs)')
        fields = self.check('boolean-snapshot', self.source[:start] + tail, 'snapshot capture forbidden')
        self.assertTrue(any(name == '$strictTs' and f['descriptor'] == 'Z' for (_, name), f in fields.items()))

    def test_initialized_host_val_is_backing_snapshot(self):
        source = self.source.replace('override val currentIptvHttpHeaders: Map<String, String> get() =',
                                    'override val currentIptvHttpHeaders: Map<String, String> =')
        self.check('host-val-snapshot', source, 'cannot retain a snapshot/backing field')

    def test_host_var_backing_snapshot(self):
        source = self.source.replace('override val currentIptvHttpHeaders: Map<String, String> get() =',
                                    'override var currentIptvHttpHeaders: Map<String, String> =')
        self.check('host-var-snapshot', source, 'cannot retain a snapshot/backing field')

    def test_removed_volatile_flag(self):
        self.check('no-volatile', self.source.replace('@Volatile private var activeVodHeaders',
                                                    'private var activeVodHeaders'), 'descriptor/final/volatile flags differ')

    def test_different_controller_host_chain(self):
        source = self.source.replace('class TvMediaPipelineController(private val host: Host)',
            'class TvMediaPipelineController(private val otherHost: Host)')
        source = source.replace('host.activeVodHeaders', 'otherHost.activeVodHeaders').replace('host.currentIptvHttpHeaders',
            'otherHost.currentIptvHttpHeaders').replace('host.iptvStrictTsActive', 'otherHost.iptvStrictTsActive')
        self.check('other-host', source, 'exactly one getter invocation')

    def test_different_controller_host_descriptor(self):
        source = self.source.replace('class TvMediaPipelineController(private val host: Host)',
                                    'class TvMediaPipelineController(private val host: OtherController.Host)')
        start = source.index('class TvMediaPipelineController')
        tail = source[start:].replace('interface Host {', 'interface Host : OtherController.Host {', 1)
        for name in ('activeVodHeaders', 'currentIptvHttpHeaders', 'iptvStrictTsActive'):
            tail = tail.replace('        val ' + name + ':', '        override val ' + name + ':', 1)
        source = source[:start] + tail + '''
class OtherController {
    interface Host {
        val activeVodHeaders: Pair<Set<String>, Map<String, String>>
        val currentIptvHttpHeaders: Map<String, String>
        val iptvStrictTsActive: Boolean
    }
}
'''
        self.check('other-controller-host', source, 'exactly one getter invocation')

    def test_duplicate_getter_invocation_not_accepted(self):
        source = self.source.replace('val headers = host.currentIptvHttpHeaders',
                                    'host.currentIptvHttpHeaders\n                val headers = host.currentIptvHttpHeaders')
        self.check('two-reads', source, 'exactly one final owner capture')

    def test_read_chain_pin_descriptor_role_and_coverage(self):
        folder = self.folder / 'positive/audit-classes'
        for key, value in [('descriptor', 'Z'), ('role', 'other'), ('signature', '()V')]:
            pins = reviewed_chains()
            pins[0][key] = value
            with self.assertRaisesRegex(ValueError, 'coverage differs'):
                audit_read_chains(pins, folder, typed_bytecode(folder), True)

    def test_before_and_after_writer_relocations(self):
        folder = self.folder / 'positive/audit-classes'
        pin = dict(descriptor='Ljava/lang/String;', writers=['handleMetadataUpdate', 'replacePayloadWithStremioTvItem'], reader='playlistController')
        fields = field_declarations(folder)
        calls = typed_bytecode(folder)
        for owners in writer_owners().values():
            audit_identity(pin, fields, fields, calls,
                before_owner='com.debrify.app.tv.TvDockIdentityPresenter', writer_owners=owners)

    def test_compiled_missing_relocated_metadata_writer(self):
        source = self.source.replace('class TvEpisodeMetadataReceiver(private val identity: TvDockIdentityPresenter) {\n    private fun handleMetadataUpdate(name: String) { identity.ottShowName = name }',
                                    'class TvEpisodeMetadataReceiver(private val identity: TvDockIdentityPresenter) {\n    private fun handleMetadataUpdate(name: String) { }')
        folder, calls = self.compile('writer-missing', source)
        pin = dict(descriptor='Ljava/lang/String;', writers=['handleMetadataUpdate', 'replacePayloadWithStremioTvItem'], reader='playlistController')
        with self.assertRaisesRegex(ValueError, 'writer dispatch differs: handleMetadataUpdate'):
            audit_identity(pin, field_declarations(folder), field_declarations(folder), calls,
                before_owner='com.debrify.app.tv.TvDockIdentityPresenter', writer_owners=writer_owners()['after'])

    def test_compiled_replacement_cannot_return_to_activity_owner(self):
        folder = self.folder / 'positive/audit-classes'
        pin = dict(descriptor='Ljava/lang/String;', writers=['handleMetadataUpdate', 'replacePayloadWithStremioTvItem'], reader='playlistController')
        for direction in ('before', 'after'):
            owners = {**writer_owners()[direction], 'replacePayloadWithStremioTvItem': 'com.debrify.app.tv.AndroidTvTorrentPlayerActivity'}
            with self.assertRaisesRegex(ValueError, 'writer dispatch differs: replacePayloadWithStremioTvItem'):
                audit_identity(pin, field_declarations(folder), field_declarations(folder), typed_bytecode(folder),
                    before_owner='com.debrify.app.tv.TvDockIdentityPresenter', writer_owners=owners)

    def test_compiled_metadata_writer_moved_before_approved_boundary(self):
        source = self.source.replace('private fun handleMetadataUpdate(name: String) { identity.ottShowName = name }',
                                    'private fun other(name: String) { identity.ottShowName = name }', 1)
        folder, calls = self.compile('writer-too-early', source)
        pin = dict(descriptor='Ljava/lang/String;', writers=['handleMetadataUpdate', 'replacePayloadWithStremioTvItem'], reader='playlistController')
        with self.assertRaisesRegex(ValueError, 'writer dispatch differs: handleMetadataUpdate'):
            audit_identity(pin, field_declarations(folder), field_declarations(folder), calls,
                before_owner='com.debrify.app.tv.TvDockIdentityPresenter', writer_owners=writer_owners()['before'])

    def test_compiled_context_constant_values_and_counts(self):
        folder = self.folder / 'positive/audit-classes'
        instructions = typed_bytecode(folder)
        for name in ('AndroidTvTorrentPlayerActivity', 'TvMediaPipelineController'):
            audit_constants(constant_pins(), instructions, 'com.debrify.app.tv.' + name)
        for label, source in [('wrong-constant', self.source.replace('consume("activity")', 'consume("other")')),
                              ('duplicate-constant', self.source.replace('consume("connectivity")', 'consume("connectivity"); consume("connectivity")'))]:
            _, instructions = self.compile(label, source)
            with self.assertRaisesRegex(ValueError, 'inlined String value/count'):
                audit_constants(constant_pins(), instructions, 'com.debrify.app.tv.TvMediaPipelineController')

    def test_identity_object_argument_is_narrowly_reviewed(self):
        site = dict(callee='setActiveSubtitleIdentityProvider')
        target = 'com/debrify/app/util/SubtitleSettings.setActiveSubtitleIdentityProvider'
        call = dict(line=1, call=target + ':(Ljava/lang/Object;Lkotlin/jvm/functions/Function0;)V')
        self.assertEqual(call['call'], resolve([call], site, 1, 1)[0])
        for changed in [target + ':(Ljava/lang/Object;)V', 'Other.setActiveSubtitleIdentityProvider:(Ljava/lang/Object;Lkotlin/jvm/functions/Function0;)V']:
            with self.assertRaisesRegex(ValueError, 'resolve uniquely'):
                resolve([{**call, 'call': changed}], site, 1, 1)

"""Production phase-5 extraction, original slots and initializer/Host negatives."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, check_earlier, initializer_kind

MANIFEST = None


class Phase5MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
            cls.manifest['base'] + ':' + cls.manifest['source']], text=True)
        cls.current = extraction(cls.manifest, cls.original)

    def path(self, stem):
        return next(p for p in self.manifest['destinations'] if Path(p).stem == stem)

    def verify(self, current, reason=None, manifest=None, original=None):
        errors, count = k.check(manifest or self.manifest, original or self.original, current)
        self.assertEqual(2548, count)
        if reason:
            self.assertTrue(any(reason in e for e in errors), '\n'.join(errors))
            print('EXPECTED PHASE-5 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason):
        current = dict(self.current)
        self.assertEqual(1, current[path].count(before))
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def test_complete_production_extraction_all_16_proofs(self):
        self.verify(self.current)
        self.assertEqual(42, sum(r['fate'] == 'moved' for r in self.manifest['declarations']))
        self.assertEqual(16, len(self.manifest['initializer_timing']))
        self.assertEqual(3, len(self.manifest['added']))
        self.assertEqual(7, len(self.manifest['overload_audit']))
        folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/production')
        for path, text in self.current.items():
            target = folder / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)

    def test_typed_empty_factories_and_numeric_literals(self):
        for form in ('mutableSetOf<String>()', 'mutableListOf<Pair<String, Int?>>()',
                     'mutableMapOf<String, Long>()', 'emptySet<String>()', 'listOf<String>()'):
            self.assertEqual('allocation', initializer_kind(form))
        for form in ('1_000L', '10_000', '2u', '2UL', '0L'):
            self.assertEqual('constant', initializer_kind(form))

    def reject_initializer(self, expression):
        manifest = copy.deepcopy(self.manifest)
        proof = next(r for r in manifest['initializer_timing'] if r['original'].endswith('property lastLiveChannelSettleMs'))
        before = proof['text']
        proof['text'] = before.replace('1_000L', expression)
        proof['kind'] = 'allocation'
        original = self.original.replace(before, proof['text'])
        current = extraction(manifest, original)
        self.verify(current, 'initializer timing not proven inert: ' + proof['original'], manifest, original)

    def test_initializer_state_read_rejected_even_with_matching_proof(self):
        self.reject_initializer('currentIptvIndex')

    def test_initializer_effectful_factory_rejected_even_with_matching_proof(self):
        self.reject_initializer('readRememberedSettleMs()')

    def test_initializer_collection_argument_rejected(self):
        self.reject_initializer('mutableSetOf<String>(readState())')

    def test_initializer_numeric_expression_rejected(self):
        self.reject_initializer('1_000L + currentIptvIndex')

    def test_typed_factory_cannot_hide_call_in_type_syntax(self):
        self.assertIsNone(initializer_kind('mutableSetOf<readState()>()'))
        self.assertIsNone(initializer_kind('mutableSetOf<String>().also { host.player.play() }'))

    def test_initializer_proof_coverage_exhaustive(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['initializer_timing'].pop()
        self.verify(self.current, 'initializer timing coverage differs', manifest)

    def test_sleep_forwarder_is_only_patched_activity_property(self):
        row = next(r for r in self.manifest['declarations'] if r['original'].endswith('property sleepTimerController'))
        self.assertEqual('patched', row['fate'])
        self.assertEqual(1, len(row['patches']))
        self.assertEqual(1, row['patches'][0]['count'])
        self.assertIn('fireCancelsThenLatchesReportsBeforePause', row['test'])
        self.assertEqual([], self.manifest['earlier_destinations']['whitelist'])

    def test_sleep_forwarder_extra_edit_rejected(self):
        self.edit(self.manifest['source'],
            'this@AndroidTvTorrentPlayerActivity.progressReporter.sendProgress(completed)',
            'this@AndroidTvTorrentPlayerActivity.progressReporter.sendProgress(!completed)',
            'token mismatch: class AndroidTvTorrentPlayerActivity/property sleepTimerController')

    def test_cross_feature_forwarder_targets_channel_start_owner(self):
        self.edit(self.manifest['source'],
            'this@AndroidTvTorrentPlayerActivity.iptvChannelStartController.beginIptvPlayback(entry)',
            'this@AndroidTvTorrentPlayerActivity.beginIptvPlayback(entry)',
            'added declaration: class AndroidTvTorrentPlayerActivity/property iptvStartOverController')

    def test_borrowed_handler_forwarder_is_computed(self):
        self.edit(self.manifest['source'],
            'override val iptvBrowseHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.iptvBrowseHandler',
            'override val iptvBrowseHandler: Handler = this@AndroidTvTorrentPlayerActivity.iptvBrowseHandler',
            'added declaration: class AndroidTvTorrentPlayerActivity/property iptvChannelStartController')

    def test_default_activity_read_remains_at_invocation(self):
        self.edit(self.path('TvIptvStartOverController'),
            'fun updateIptvStartOverButton(entry: IptvChannelEntry? =\n        host.iptvChannels.getOrNull(host.currentIptvIndex)',
            'fun updateIptvStartOverButton(entry: IptvChannelEntry? =\n        host.iptvChannels.getOrNull(0)',
            'token mismatch: class AndroidTvTorrentPlayerActivity/fun updateIptvStartOverButton(IptvChannelEntry?)')

    def test_host_default_argument_pinned(self):
        self.edit(self.path('TvIptvStartOverController'), 'checkpointOutgoing: Boolean = true',
            'checkpointOutgoing: Boolean = false', 'pinned destination:')

    def test_unbraced_progress_template_rejected(self):
        self.edit(self.manifest['source'], 'sent=${progressReporter.progressSentCount}',
            'sent=$progressReporter.progressSentCount',
            'token mismatch: class AndroidTvTorrentPlayerActivity/fun recordPlaybackLifecycle(String,String)')

    def test_extra_activity_this_rewrite_rejected(self):
        self.edit(self.path('TvProgressReporter'), 'val channel = MainActivity.getAndroidTvPlayerChannel()',
            'val channel = activity.getAndroidTvPlayerChannel()',
            'token mismatch: class AndroidTvTorrentPlayerActivity/fun deliverProgress(HashMap<String, Any?>)')

    def test_shadowed_window_not_substituted(self):
        self.edit(self.manifest['source'], 'val window = boundedHiddenIptvZapWindow(merged)',
            'val window = host.window', 'token mismatch:')

    def test_shadowed_current_index_not_substituted(self):
        self.edit(self.manifest['source'], 'val currentIndex = categories.indexOf(currentCategory).let {',
            'val currentIndex = host.currentIndex.let {', 'token mismatch:')

    def test_this_index_receiver_not_rewritten(self):
        self.edit(self.manifest['source'], '?.mapIndexed { index, item -> item.apply { this.index = index } }',
            '?.mapIndexed { index, item -> item.apply { activity.index = index } }', 'token mismatch:')

    def test_controller_constructor_cannot_read_host(self):
        self.edit(self.path('TvIptvChannelStartController'), '    interface Host {',
            '    init { host.progressHandler.post {} }\n    interface Host {', 'unexpected new declaration:')

    def test_controller_property_cannot_move_from_first_owned_slot(self):
        current = dict(self.current)
        row = next(r for r in self.manifest['added'] if r['target'].endswith('property progressReporter'))
        path = self.manifest['source']
        current[path] = current[path].replace(row['text'], '')
        marker = '    private var finalProgressSnapshot = false'
        current[path] = current[path].replace(marker, marker + row['text'])
        self.verify(current, 'retained declaration order changed:')

    def test_teardown_statement_order_pinned(self):
        self.edit(self.manifest['source'],
            'finalProgressSnapshot = true\n        progressReporter.sendProgress(completed = false)\n        finalProgressSnapshot = false',
            'finalProgressSnapshot = true\n        finalProgressSnapshot = false\n        progressReporter.sendProgress(completed = false)',
            'token mismatch: class AndroidTvTorrentPlayerActivity/fun onStop()')

    def test_all_28_earlier_destinations_frozen(self):
        current = {p: (k.ROOT / p).read_text() for p in self.manifest['earlier_destinations']['paths']}
        self.assertEqual(28, len(current))
        self.assertEqual([], check_earlier(self.manifest, k.ROOT, current))
        for stem in ('TvSleepTimerController', 'TvAutoSyncController', 'TvSubtitleController'):
            changed = dict(current)
            path = next(p for p in current if Path(p).stem == stem)
            changed[path] += '\nfun unreviewed() = 1\n'
            self.assertIn('earlier destination changed beyond reviewed whitelist: ' + path,
                          check_earlier(self.manifest, k.ROOT, changed))

    def test_historical_phase4_manifest(self):
        result = subprocess.run(['python3', str(k.ROOT / 'dev/tool/check_kotlin_moves.py'),
            '--manifest', str(k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p4.json'), '--at', '1a33c42cb'],
            capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

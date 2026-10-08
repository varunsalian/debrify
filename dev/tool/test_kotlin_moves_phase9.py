"""Phase-9 exhaustive gate fixture, timing proofs and retained lifecycle wiring."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, check_earlier

MANIFEST = None


class Phase9MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
            cls.manifest['base'] + ':' + cls.manifest['source']], text=True)
        cls.current = extraction(cls.manifest, cls.original)
        cls.count = len(list(k.walk(k.parse({'base': cls.original})['base']['declarations'])))
        cls.path = next(iter(cls.manifest['destinations']))
        cls.source = cls.manifest['source']

    def verify(self, current, reason=None, manifest=None):
        errors, count = k.check(manifest or self.manifest, self.original, current)
        self.assertEqual(self.count, count)
        if reason:
            self.assertTrue(any(reason in e for e in errors), '\n'.join(errors))
            print('EXPECTED PHASE-9 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason, count=1):
        current = dict(self.current)
        self.assertEqual(count, current[path].count(before), before)
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def host_edit(self, before, after):
        current = dict(self.current); row = self.manifest['added'][0]
        self.assertEqual(1, row['text'].count(before))
        current[self.source] = current[self.source].replace(row['text'], row['text'].replace(before, after))
        self.verify(current, 'added declaration:')

    def test_complete_production_extraction_all_29_proofs(self):
        self.verify(self.current)
        self.assertEqual(51, sum(r['fate'] == 'moved' for r in self.manifest['declarations']))
        self.assertEqual(29, len(self.manifest['initializer_timing']))
        self.assertEqual(5, len(self.manifest['overload_audit']))
        self.assertEqual(4, sum(s.get('receiver') == 'implicit-inherited' for s in self.manifest['overload_audit']))
        self.assertEqual(2, len(self.manifest['runnable_receivers']))
        for name, edits in [('progressReporter', 4), ('sourceSwitchController', 14)]:
            row = next(r for r in self.manifest['declarations'] if r['original'].endswith('/property ' + name))
            self.assertEqual('patched', row['fate']); self.assertEqual(edits, sum(e['count'] for e in row['patches']))
        folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase9')
        for path, text in self.current.items():
            target = folder / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(text)

    def test_moved_host_template_must_be_braced(self):
        self.edit(self.path, '${host.currentStremioSourceIndex}', '$host.currentStremioSourceIndex', 'token mismatch:', 3)

    def test_retained_gate_template_must_be_braced(self):
        self.edit(self.source, '${startupGateController.startupFailoverGeneration}',
                  '$startupGateController.startupFailoverGeneration', 'token mismatch:', 2)

    def test_finish_must_not_route_through_host(self):
        current = dict(self.current)
        current[self.path] = current[self.path].replace('    interface Host {', '    interface Host {\n        fun finish() {}')
        current[self.path] = current[self.path].replace('activity.finish()', 'host.finish()')
        self.verify(current, 'token mismatch:'); self.verify(current, 'pinned destination:')

    def test_finish_super_dispatch_is_rejected(self):
        self.edit(self.path, 'activity.finish()', 'super.finish()', 'token mismatch:')

    def test_finish_static_dispatch_is_rejected(self):
        self.edit(self.path, 'activity.finish()', 'StaticFinish.finish(activity)', 'token mismatch:')

    def test_retry_id_forwarder_cannot_snapshot(self):
        self.host_edit('override val pikPakRetryId: Int get() =', 'override val pikPakRetryId: Int =')

    def test_player_forwarder_cannot_snapshot(self):
        self.host_edit('override val player: ExoPlayer? get() =', 'override val player: ExoPlayer? =')

    def test_switcher_qualification_cannot_be_missed(self):
        self.edit(self.path, 'host.sourceSwitchController.', 'sourceSwitchController.', 'token mismatch:', 7)

    def test_same_name_host_cannot_capture_switcher_call(self):
        current = dict(self.current)
        current[self.path] = current[self.path].replace('    interface Host {', '    interface Host {\n        fun cancelSourceSwitchWait() {}')
        current[self.path] = current[self.path].replace('host.sourceSwitchController.cancelSourceSwitchWait()', 'host.cancelSourceSwitchWait()')
        self.verify(current, 'token mismatch:'); self.verify(current, 'pinned destination:')

    def test_same_name_host_cannot_capture_gate_call(self):
        current = dict(self.current)
        current[self.path] = current[self.path].replace('    interface Host {', '    interface Host {\n        fun failStartupCandidate(reason: String) {}')
        current[self.path] = current[self.path].replace('failStartupCandidate("missing-source")', 'host.failStartupCandidate("missing-source")')
        self.verify(current, 'token mismatch:'); self.verify(current, 'pinned destination:')

    def test_on_destroy_statements_cannot_be_reordered(self):
        before = 'startupGateController.startupFailoverTimeout?.let { progressHandler.removeCallbacks(it) }\n        startupGateController.startupFailoverTimeout = null'
        after = 'startupGateController.startupFailoverTimeout = null\n        startupGateController.startupFailoverTimeout?.let { progressHandler.removeCallbacks(it) }'
        self.edit(self.source, before, after, 'token mismatch:')

    def test_on_destroy_15_statements_cannot_be_folded(self):
        current = dict(self.current); start = current[self.source].index('        startupGateController.startupFailoverTimeout?.let')
        end = current[self.source].index('\n        if (::startupGateView.isInitialized)', start)
        self.assertEqual(15, len(current[self.source][start:end].splitlines()))
        current[self.source] = current[self.source][:start] + '        startupGateController.destroyGate()' + current[self.source][end:]
        self.verify(current, 'token mismatch:')

    def test_progress_repoint_cannot_be_missed(self):
        self.edit(self.source, 'override val startupSourcesExhausted: Boolean get() = this@AndroidTvTorrentPlayerActivity.startupGateController.startupSourcesExhausted',
                  'override val startupSourcesExhausted: Boolean get() = this@AndroidTvTorrentPlayerActivity.startupSourcesExhausted', 'token mismatch:')

    def test_switcher_repoint_cannot_be_missed(self):
        self.edit(self.source, 'override fun armStartupCandidate(sourceIndex: Int): Unit = this@AndroidTvTorrentPlayerActivity.startupGateController.armStartupCandidate(sourceIndex)',
                  'override fun armStartupCandidate(sourceIndex: Int): Unit = this@AndroidTvTorrentPlayerActivity.armStartupCandidate(sourceIndex)', 'token mismatch:')

    def property_extra_edit(self, name, before, after):
        current = dict(self.current)
        unit = k.parse({'source': current[self.source]})['source']
        node = next(n for n in k.walk(unit['declarations']) if n['id'] == 'class AndroidTvTorrentPlayerActivity/property ' + name)
        text = current[self.source][node['start']:node['end']]; self.assertEqual(1, text.count(before))
        current[self.source] = current[self.source][:node['start']] + text.replace(before, after) + current[self.source][node['end']:]
        self.verify(current, 'token mismatch:')

    def test_progress_whole_property_cannot_hide_extra_edit(self):
        self.property_extra_edit('progressReporter', 'get() = this@AndroidTvTorrentPlayerActivity.currentIndex', 'get() = 0')

    def test_switcher_whole_property_cannot_hide_extra_edit(self):
        self.property_extra_edit('sourceSwitchController', '.playItem(index, suppressTrakt, suppressResume, shuffleAttempt)', '.playItem(index, false, suppressResume, shuffleAttempt)')

    def test_block_two_proof_cannot_be_omitted(self):
        m = copy.deepcopy(self.manifest)
        m['initializer_timing'] = [r for r in m['initializer_timing'] if not r['original'].endswith('/property manualSourceCandidateUrl')]
        self.verify(self.current, 'initializer timing coverage differs', m)

    def test_runnable_self_must_not_be_activity(self):
        self.edit(self.path, 'host.progressHandler.postDelayed(this, STARTUP_WATCHDOG_RECHECK_MS)',
                  'host.progressHandler.postDelayed(activity, STARTUP_WATCHDOG_RECHECK_MS)', 'token mismatch:', 2)

    def test_host_must_not_read_later_controller_at_construction(self):
        self.host_edit('override val sourceSwitchController: TvSourceSwitchController get() =',
                       'override val sourceSwitchController: TvSourceSwitchController =')

    def test_all_36_earlier_destinations_frozen(self):
        current = {p: (k.ROOT / p).read_text() for p in self.manifest['earlier_destinations']['paths']}
        self.assertEqual(36, len(current)); self.assertEqual([], check_earlier(self.manifest, k.ROOT, current))
        for path in [p for p in current if Path(p).stem in {'TvSourceSwitchController', 'TvSourceSwitchApplier'}]:
            changed = dict(current); changed[path] += '\nfun unreviewed() = 1\n'
            self.assertIn('earlier destination changed beyond reviewed whitelist: ' + path,
                          check_earlier(self.manifest, k.ROOT, changed))

    def test_historical_phase8_manifest(self):
        result = subprocess.run(['python3', str(k.ROOT / 'dev/tool/check_kotlin_moves.py'),
            '--manifest', str(k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p8.json'), '--at', 'c4906cd2f'], capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

"""Production phase-4 partition and its state/Host/default/local negative controls."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, check_earlier

MANIFEST = None


class Phase4MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
            cls.manifest['base'] + ':' + cls.manifest['source']], text=True)
        cls.current = extraction(cls.manifest, cls.original)

    def path(self, stem):
        return next(p for p in self.manifest['destinations'] if Path(p).stem == stem)

    def verify(self, current, reason=None, manifest=None):
        errors, count = k.check(manifest or self.manifest, self.original, current)
        self.assertEqual(2629, count)
        if reason:
            self.assertTrue(any(reason in error for error in errors), '\n'.join(errors))
            print('EXPECTED PHASE-4 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason):
        current = dict(self.current)
        self.assertEqual(1, current[path].count(before))
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def test_complete_production_extraction(self):
        self.verify(self.current)
        self.assertEqual(66, sum(r['fate'] == 'moved' for r in self.manifest['declarations']))
        self.assertEqual(28, len(self.manifest['initializer_timing']))
        folder = k.evidence_root(k.ROOT) / 'p4/fixtures/production'
        for path, text in self.current.items():
            target = folder / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)

    def test_multi_block_late_field_cannot_stay_in_activity(self):
        source = self.manifest['source']
        self.edit(source, '    private var statusPill: TextView? = null',
            '    private var autoSyncPillWindowActive = false\n    private var statusPill: TextView? = null',
            'unexpected new declaration: ' + source + ':class AndroidTvTorrentPlayerActivity/property autoSyncPillWindowActive')

    def test_cross_controller_read_must_target_owner(self):
        self.edit(self.manifest['source'],
            'this@AndroidTvTorrentPlayerActivity.subtitleController.externalSubtitleActive',
            'this@AndroidTvTorrentPlayerActivity.externalSubtitleActive',
            'added declaration: class AndroidTvTorrentPlayerActivity/property autoSyncController')

    def test_cross_controller_write_must_target_owner(self):
        self.edit(self.manifest['source'],
            'set(value) { this@AndroidTvTorrentPlayerActivity.autoSyncController.autoSyncAppliedOffsetMs = value }',
            'set(value) { this@AndroidTvTorrentPlayerActivity.autoSyncAppliedOffsetMs = value }',
            'added declaration: class AndroidTvTorrentPlayerActivity/property subtitleController')

    def test_host_default_argument_is_pinned(self):
        path = self.path('TvSubtitleController')
        self.edit(path, 'fun runSubtitleAutoSync(auto: Boolean = false)',
            'fun runSubtitleAutoSync(auto: Boolean = true)', 'pinned destination: ' + path + ':class TvSubtitleController/class Host')

    def test_host_named_and_nullable_default_are_pinned(self):
        path = self.path('TvSubtitleController')
        self.edit(path, 'hint: String? = null, autoHideMs: Long?, uppercase: Boolean = true',
            'hint: String? = "", autoHideMs: Long?, uppercase: Boolean = true',
            'pinned destination: ' + path + ':class TvSubtitleController/class Host')

    def test_shadowed_local_is_not_rewritten(self):
        self.edit(self.path('TvSubtitleController'),
            'val subtitleTracks = mutableListOf<Pair<String, TrackSelectionOverride?>>()',
            'val subtitleTracks = host.subtitleTracks',
            'token mismatch: class AndroidTvTorrentPlayerActivity/fun showSubtitleTrackDialog()')

    def test_late_initializer_proof_is_exhaustive(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['initializer_timing'].pop()
        self.verify(self.current, 'initializer timing coverage differs', manifest)

    def test_initializer_proof_cannot_change_kind(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['initializer_timing'][0]['kind'] = 'effectful'
        self.verify(self.current, 'initializer timing not proven inert', manifest)

    def test_owned_seek_handler_cannot_clear_shared_handler(self):
        self.edit(self.path('TvSubtitleController'),
            'subtitleSeekHandler.removeCallbacks(subtitleSeekRunnable)',
            'host.externalSubtitleHandler.removeCallbacksAndMessages(null)',
            'token mismatch: class AndroidTvTorrentPlayerActivity/fun applySubtitleSettings()')

    def test_reviewed_runnable_this_cannot_be_rewritten(self):
        self.edit(self.path('TvAutoSyncController'), 'if (autoSyncVerifyTick === this)',
            'if (autoSyncVerifyTick === activity)',
            'token mismatch: class AndroidTvTorrentPlayerActivity/fun scheduleAutoSyncVerify()')

    def test_teardown_borrowed_scope_order_is_pinned(self):
        self.edit(self.manifest['source'],
            'subtitleController.subtitleSeekHandler.removeCallbacks(subtitleController.subtitleSeekRunnable)\n        externalSubtitleHandler.removeCallbacksAndMessages(null)',
            'externalSubtitleHandler.removeCallbacksAndMessages(null)\n        subtitleController.subtitleSeekHandler.removeCallbacks(subtitleController.subtitleSeekRunnable)',
            'token mismatch: class AndroidTvTorrentPlayerActivity/fun onDestroy()')

    def test_earlier_controller_destinations_are_frozen(self):
        current = {p: (k.ROOT / p).read_text() for p in self.manifest['earlier_destinations']['paths']}
        self.assertEqual([], check_earlier(self.manifest, k.ROOT, current))
        for stem in ('TvSleepTimerController', 'TvSkipSegmentController', 'TvUpNextController', 'TvIptvRecordingActionsController'):
            changed = dict(current)
            path = next(p for p in current if Path(p).stem == stem)
            changed[path] = current[path] + '\nfun unreviewed() = 1\n'
            self.assertIn('earlier destination changed beyond reviewed whitelist: ' + path,
                          check_earlier(self.manifest, k.ROOT, changed))

    def test_historical_phase3_manifest(self):
        result = subprocess.run(['python3', str(k.ROOT / 'dev/tool/check_kotlin_moves.py'),
            '--manifest', str(k.ROOT / 'dev/tool/kotlin_moves/tvplayer_p3.json'), '--at', 'eee52b084'],
            capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

"""Complete stateful extraction and exact scaffold/slot negative controls."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from test_kotlin_moves import extraction
from kotlin_move_partition import check_earlier

MANIFEST = None


class Phase3MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output([
            'git', '-C', str(k.ROOT), 'show', cls.manifest['base'] + ':' + cls.manifest['source'],
        ]).decode()
        cls.current = extraction(cls.manifest, cls.original)

    def path(self, stem):
        return next(p for p in self.manifest['destinations'] if Path(p).stem == stem)

    def verify(self, current, reason=None, manifest=None):
        errors, count = k.check(manifest or self.manifest, self.original, current)
        self.assertEqual(2671, count)
        if reason is None:
            self.assertEqual([], errors)
        else:
            self.assertTrue(any(reason in error for error in errors), '\n'.join(errors))
            print('EXPECTED PHASE-3 FAILURE:', reason)

    def edit(self, path, before, after, reason):
        current = dict(self.current)
        self.assertEqual(1, current[path].count(before))
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def test_complete_phase3_extraction(self):
        self.verify(self.current)
        self.assertEqual(4, len(self.manifest['destinations']))
        self.assertEqual(6, len(self.manifest['added']))
        folder = k.evidence_root(k.ROOT) / 'p3/fixtures/phase3'
        for path, text in self.current.items():
            folder.mkdir(parents=True, exist_ok=True)
            (folder / Path(path).name).write_text(text)

    def test_undeclared_this_rewrite(self):
        self.edit(self.path('TvUpNextController'), 'postDelayed(this, UP_NEXT_TICK_MS)',
                  'postDelayed(activity, UP_NEXT_TICK_MS)', 'token mismatch: class AndroidTvTorrentPlayerActivity/property upNextTicker')

    def test_host_forwarder_logic(self):
        self.edit(self.manifest['source'],
                  'override var sleepStopLatched: Boolean\n                get() = this@AndroidTvTorrentPlayerActivity.sleepStopLatched',
                  'override var sleepStopLatched: Boolean\n                get() = !this@AndroidTvTorrentPlayerActivity.sleepStopLatched',
                  'added declaration: class AndroidTvTorrentPlayerActivity/property sleepTimerController')

    def test_moved_field_order(self):
        self.edit(self.path('TvSleepTimerController'),
                  'private var sleepTimerDeadlineElapsedMs = 0L\n    private val sleepTimerHandler = Handler(Looper.getMainLooper())',
                  'private val sleepTimerHandler = Handler(Looper.getMainLooper())\n    private var sleepTimerDeadlineElapsedMs = 0L',
                  'destination declaration order changed:')

    def test_added_text_change(self):
        self.edit(self.manifest['source'], 'Boolean get() = ::skipSegmentButton.isInitialized',
                  'Boolean get() = true', 'added declaration: class AndroidTvTorrentPlayerActivity/property skipSegmentButtonReady')

    def test_teardown_statement_order(self):
        self.edit(self.manifest['source'],
                  'skipSegmentController.skipSegmentFetchGeneration++\n        skipSegmentController.skipSegmentFetchJob?.cancel()',
                  'skipSegmentController.skipSegmentFetchJob?.cancel()\n        skipSegmentController.skipSegmentFetchGeneration++',
                  'token mismatch: class AndroidTvTorrentPlayerActivity/fun onDestroy()')

    def test_constructor_side_effect(self):
        path = self.path('TvSleepTimerController')
        self.edit(path, 'private val activity: AppCompatActivity,',
                  'private val activity: AppCompatActivity = error("constructor side effect"),',
                  'pinned destination: ' + path + ':class TvSleepTimerController:header')

    def test_unexpected_init(self):
        path = self.path('TvSleepTimerController')
        self.edit(path, '    interface Host {', '    init { activity.finish() }\n    interface Host {',
                  'unexpected new declaration: ' + path + ':class TvSleepTimerController/init#1')

    def test_changed_host_declaration(self):
        path = self.path('TvUpNextController')
        self.edit(path, 'val currentIndex: Int', 'val currentIndex: Long',
                  'pinned destination: ' + path + ':class TvUpNextController/class Host')

    def test_relocated_controller_property(self):
        current = dict(self.current)
        row = next(r for r in self.manifest['added'] if r['target'].endswith('property sleepTimerController'))
        source = self.manifest['source']
        self.assertEqual(1, current[source].count(row['text']))
        current[source] = current[source].replace(row['text'], '')
        marker = '    private var sleepStopLatched = false'
        current[source] = current[source].replace(marker, marker + row['text'])
        self.verify(current, 'retained declaration order changed: class AndroidTvTorrentPlayerActivity')

    def test_unbraced_host_template(self):
        self.edit(self.path('TvSkipSegmentController'), '${host.skipSegmentProviderId}:$imdbId',
                  '$host.skipSegmentProviderId:$imdbId',
                  'token mismatch: class AndroidTvTorrentPlayerActivity/fun currentSkipSegmentRequest(Long)')

    def test_snapshot_forwarder(self):
        self.edit(self.manifest['source'],
                  'override val upNextVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.upNextController.upNextVisible',
                  'override val upNextVisible: Boolean = this@AndroidTvTorrentPlayerActivity.upNextController.upNextVisible',
                  'added declaration: class AndroidTvTorrentPlayerActivity/property skipSegmentController')

    def test_missing_destination_structural_pin(self):
        manifest = copy.deepcopy(self.manifest)
        path = self.path('TvUpNextController')
        del manifest['destinations'][path]['pinned_spans']['class TvUpNextController:header']
        self.verify(self.current, 'missing pinned structural span:', manifest)

    def test_added_slot_must_be_first_removed_field(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['added'][0]['slot'] = 'class AndroidTvTorrentPlayerActivity/property sleepTimerDeadlineElapsedMs'
        self.verify(self.current, 'added slot must be the first removed field:', manifest)

    def test_earlier_destinations_and_unreviewed_change(self):
        spec = self.manifest['earlier_destinations']
        current = {p: (k.ROOT / p).read_text() for p in spec['paths']}
        self.assertEqual([], check_earlier(self.manifest, k.ROOT, current))
        path = next(p for p in current if p.endswith('IptvRecordingUrlRules.kt'))
        current[path] = current[path].replace('contains(\'?\')', 'contains(\'&\')')
        self.assertTrue(any('beyond reviewed whitelist' in e for e in check_earlier(self.manifest, k.ROOT, current)))

    def test_earlier_coverage_cannot_be_reduced(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['earlier_destinations']['paths'].pop()
        self.assertEqual(['earlier destination coverage differs from historical manifests'], check_earlier(manifest, k.ROOT))

    def test_historical_phase_manifests(self):
        for phase, revision in ((1, 'dcbd9aafe'), (2, 'ec365eb80')):
            result = subprocess.run(['python3', str(k.ROOT / 'dev/tool/check_kotlin_moves.py'),
                                     '--manifest', str(k.ROOT / f'dev/tool/kotlin_moves/tvplayer_p{phase}.json'),
                                     '--at', revision], capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIn('0 differences', result.stdout)

"""Complete playback-start/navigator extraction and exact boundary negatives."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from kotlin_move_partition import extraction, initializer_kind, check_earlier
from kotlin_overloads_phase18 import validate_source_bound, historical_receivers

MANIFEST = None


class Phase18MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output(['git', '-C', str(k.ROOT), 'show',
            MANIFEST['base'] + ':' + MANIFEST['source']], text=True)
        cls.current = extraction(MANIFEST, cls.original)
        cls.inventory = {n['id']: n for n in k.walk(k.parse({'original': cls.original})['original']['declarations'])}
        cls.source = MANIFEST['source']

    def path(self, name):
        return next(p for p in self.manifest['destinations'] if Path(p).stem == name)

    def verify(self, current=None, reason=None, manifest=None, bound_sources=None):
        errors, count = k.check(manifest or self.manifest, self.original,
                                current or self.current, bound_sources=bound_sources)
        self.assertEqual(1642, count)
        if reason:
            self.assertTrue(any(reason in e for e in errors), '\n'.join(errors))
            print('EXPECTED PHASE-18 FAILURE:', reason)
        else:
            self.assertEqual([], errors)

    def edit(self, path, before, after, reason, count=1):
        current = dict(self.current)
        self.assertEqual(count, current[path].count(before), before)
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def test_complete_production_extraction(self):
        self.verify()
        self.assertEqual(37, sum(r['fate'] == 'moved' for r in self.manifest['declarations']))
        self.assertEqual(8, len(self.manifest['initializer_timing']))
        self.assertEqual(20, len(self.manifest['overload_audit']))
        self.assertEqual(59, len(self.manifest['earlier_destinations']['paths']))
        self.assertEqual([], self.manifest['receiver_lambda_exclusions'])
        folder = k.evidence_root(k.ROOT) / (k.EVIDENCE_PHASE + '/fixtures/phase18')
        for path, text in self.current.items():
            target = folder / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)

    def test_reviewed_shuffle_initializer_and_source(self):
        self.assertEqual('allocation', initializer_kind('ShowShuffle()'))
        validate_source_bound(self.manifest, self.inventory)
        for text in ('ShowShuffle(Random(1))', 'OtherProjectClass()', 'ShowShuffle(random = Random.Default)', 'ShowShuffle(host.random)'):
            self.assertIsNone(initializer_kind(text))

    def test_shuffle_constructor_argument_changed(self):
        self.edit(self.path('TvPlaybackNavigator'), 'val showShuffle = ShowShuffle()', 'val showShuffle = ShowShuffle(Random(1))', 'token mismatch:')

    def test_original_shuffle_initializer_must_be_exact(self):
        nodes = copy.deepcopy(self.inventory)
        nodes['class AndroidTvTorrentPlayerActivity/property showShuffle']['initializer_text'] = 'ShowShuffle(Random(1))'
        with self.assertRaisesRegex(ValueError, 'exact reviewed zero-argument'):
            validate_source_bound(self.manifest, nodes)

    def test_changed_shuffle_default_with_call_unchanged(self):
        path = self.manifest['source_bound_initializers'][0]['source']
        text = (k.ROOT / path).read_text()
        self.assertEqual(1, text.count('Random.Default'))
        self.verify(reason='ShowShuffle source changed', bound_sources={path: text.replace('Random.Default', 'Random(1)')})

    def test_effectful_shuffle_init_with_call_unchanged(self):
        path = self.manifest['source_bound_initializers'][0]['source']
        text = (k.ROOT / path).read_text()
        self.verify(reason='ShowShuffle source changed', bound_sources={path: text.replace('    private val visited', '    init { System.setProperty("effect", "true") }\n    private val visited', 1)})

    def test_unreviewed_shuffle_source_or_constructor_proof(self):
        for key, value in [('revision', 'HEAD'), ('source', 'Other.kt'), ('sha256', '0' * 64),
                           ('constructor', dict(owner='Other', descriptor='()V', opcode='invokespecial'))]:
            m = copy.deepcopy(self.manifest)
            m['source_bound_initializers'][0][key] = value
            self.verify(manifest=m, reason='source-bound constructor proof coverage differs')

    def test_missing_source_bound_proof(self):
        m = copy.deepcopy(self.manifest)
        m['source_bound_initializers'] = []
        self.verify(manifest=m, reason='source-bound constructor proof coverage differs')

    def test_every_initializer_proof_required(self):
        for row in self.manifest['initializer_timing']:
            with self.subTest(field=row['original']):
                m = copy.deepcopy(self.manifest)
                m['initializer_timing'].remove(row)
                self.verify(manifest=m, reason='initializer timing coverage differs')

    def test_eager_navigator_and_exact_position(self):
        p = self.path('TvPlaybackStartController')
        self.edit(p, 'internal val navigator = TvPlaybackNavigator(activity, host, this)',
            'internal val navigator by lazy { TvPlaybackNavigator(activity, host, this) }', 'pinned destination:')
        m = copy.deepcopy(self.manifest)
        order = m['destinations'][p]['order']['class TvPlaybackStartController']
        item = 'class TvPlaybackStartController/property navigator'
        order.remove(item)
        order.insert(1, item)
        self.verify(manifest=m, reason='destination declaration order changed')

    def test_nested_effective_slot_required(self):
        m = copy.deepcopy(self.manifest)
        m['nested_construction'] = []
        self.verify(manifest=m, reason='destination lacks effective construction slot')

    def test_scope_remains_first_and_property_slot_is_pinned(self):
        p = self.path('TvPlaybackStartController')
        m = copy.deepcopy(self.manifest)
        order = m['destinations'][p]['order']['class TvPlaybackStartController']
        field = 'class TvPlaybackStartController/property mediaPreparationScope'
        order.remove(field)
        order.append(field)
        self.verify(manifest=m, reason='destination declaration order changed')
        m = copy.deepcopy(self.manifest)
        m['added'][0]['slot'] = 'class AndroidTvTorrentPlayerActivity/property mediaPreparationGeneration'
        self.verify(manifest=m, reason='added slot must be the first removed field')

    def test_construction_time_host_or_owner_reads_rejected(self):
        for stem, read in [('TvPlaybackStartController', 'host.player'), ('TvPlaybackNavigator', 'playbackStart.pendingShufflePlayback')]:
            p = self.path(stem)
            header = self.manifest['destinations'][p]['pinned_spans']['class ' + stem + ':header']
            self.edit(p, header, header + '\n    init { ' + read + ' }', 'unexpected new declaration:')

    def test_missed_owner_and_navigator_qualification(self):
        for stem, before in [('TvPlaybackStartController', 'navigator.shuffleAttemptCurrent'),
                              ('TvPlaybackNavigator', 'playbackStart.mediaPreparationGeneration')]:
            p = self.path(stem)
            self.edit(p, before, before.split('.', 1)[1], 'token mismatch:', self.current[p].count(before))

    def test_same_name_host_cannot_capture_owned_read(self):
        owner, child = self.path('TvPlaybackStartController'), self.path('TvPlaybackNavigator')
        current = dict(self.current)
        current[owner] = current[owner].replace('    interface Host {', '    interface Host {\n        val mediaPreparationGeneration: Int', 1)
        current[child] = current[child].replace('playbackStart.mediaPreparationGeneration', 'host.mediaPreparationGeneration')
        self.verify(current, 'pinned destination:')

    def test_deliberately_absent_host_names(self):
        p = self.path('TvPlaybackStartController')
        for name in ('playItem', 'updateCatalogEpisodeControls', 'pendingShufflePlayback', 'mediaPreparationGeneration',
                     'mediaPreparationScope', 'shuffleAttemptCurrent', 'watchShufflePlayback',
                     'restoreShufflePreparation', 'failShufflePlayback', 'shuffleBag'):
            self.edit(p, '    interface Host {', '    interface Host {\n        val ' + name + ': Any', 'pinned destination:')

    def test_navigation_name_collision_and_local_qualification(self):
        p = self.path('TvPlaybackStartController')
        self.edit(p, 'navigator.shuffleAttemptCurrent', 'navigation.shuffleAttemptCurrent', 'token mismatch:', self.current[p].count('navigator.shuffleAttemptCurrent'))
        p = self.path('TvPlaybackNavigator')
        self.edit(p, 'val navigation = playbackStart.mediaPreparationGeneration', 'val navigator = playbackStart.mediaPreparationGeneration', 'token mismatch:')

    def test_local_functions_are_body_content(self):
        p = self.path('TvPlaybackNavigator')
        self.assertTrue(all(self.current[p].count('fun ' + name + '(') == 1 for name in ('retryWhenIdle', 'fetchTarget', 'openPrepared')))
        self.assertFalse(any('/fun retryWhenIdle' in r['original'] or '/fun fetchTarget' in r['original'] or '/fun openPrepared' in r['original'] for r in self.manifest['declarations']))
        self.edit(p, 'playShowShuffle(attempted, autoAdvance)', 'playShowShuffle(emptySet(), autoAdvance)', 'token mismatch:')

    def test_exoplayer_inner_members_never_host_qualified(self):
        p = self.path('TvPlaybackStartController')
        for before, after in [('            prepare()', '            host.player?.prepare()'),
                              ('            playWhenReady = true', '            host.player?.playWhenReady = true'),
                              ('pendingShufflePlayback?.mediaStarted = true', 'host.pendingShufflePlayback?.mediaStarted = true')]:
            self.edit(p, before, after, 'token mismatch:', self.current[p].count(before))

    def test_receiver_blocks_cannot_be_swapped(self):
        p = self.path('TvPlaybackStartController')
        self.edit(p, 'host.player?.apply {', 'host.player?.let {', 'receiver binding changed', 3)
        m = copy.deepcopy(self.manifest)
        m['preserved_receiver_blocks'] = []
        self.verify(manifest=m, reason='receiver-block coverage differs')

    def test_labels_unchanged(self):
        p = self.path('TvPlaybackNavigator')
        self.edit(p, 'return@requestStreamFromFlutter', 'return@playShowShuffle', 'token mismatch:')
        p = self.path('TvPlaybackStartController')
        self.edit(p, 'return@discoverProtectedMime', 'return@startPlayback', 'token mismatch:')

    def test_braced_manual_token_template(self):
        p = self.path('TvPlaybackStartController')
        self.edit(p, '${host.stremioResolutionToken}', '$host.stremioResolutionToken', 'token mismatch:')

    def test_protected_client_computed_off_main_read_not_snapshot(self):
        before = 'override val protectedStreamClient: okhttp3.OkHttpClient get() = this@AndroidTvTorrentPlayerActivity.protectedStreamClient'
        self.edit(self.source, before, before.replace(' get()', ''), 'added declaration:')

    def test_borrowed_volatile_storage_and_nested_binary_owner(self):
        self.edit(self.source, '@Volatile private var activeVodHeaders', 'private var activeVodHeaders', 'retain @Volatile')
        m = copy.deepcopy(self.manifest)
        row = next(r for r in m['declarations'] if r['original'].endswith('/class ShufflePlaybackAttempt'))
        row['fate'] = 'patched'
        row.update(patches=[dict(before='internal class', after='public class', count=1)], reason='invalid', test='invalid')
        self.verify(manifest=m, reason='binary owner must remain Activity')

    def test_default_arguments_and_public_dispatch_pins(self):
        p = self.path('TvPlaybackStartController')
        self.edit(p, 'suppressTrakt: Boolean = false', 'suppressTrakt: Boolean = true', 'token mismatch:')
        self.edit(p, '    fun playItem(', '    internal fun playItem(', 'token mismatch:')
        self.edit(p, '    private fun replacePayloadWithStremioTvItem(', '    fun replacePayloadWithStremioTvItem(', 'token mismatch:')
        p = self.path('TvPlaybackNavigator')
        self.edit(p, 'autoAdvance: Boolean = false', 'autoAdvance: Boolean = true', 'token mismatch:')

    def test_guide_adjacent_shape_no_interface_default(self):
        p = self.path('TvPlaybackStartController')
        before = 'fun guideAdjacent(model: PlaybackPayload, currentItem: PlaybackItem?, direction: Int): SeasonEpisode?'
        self.edit(p, before, before.replace('direction: Int', 'direction: Int = 1'), 'pinned destination:')

    def test_whole_property_repoint_extra_edit(self):
        self.edit(self.source, 'this@AndroidTvTorrentPlayerActivity.playbackStartController.navigator.playNext()',
            'this@AndroidTvTorrentPlayerActivity.playbackStartController.navigator.playPrevious()', 'token mismatch:', 2)

    def test_teardown_order_unchanged(self):
        a = '        playbackStartController.mediaPreparationScope.cancel()\n        playbackStartController.mediaPreparationGeneration++'
        self.edit(self.source, a, '\n'.join(reversed(a.splitlines())), 'token mismatch:')

    def test_every_current_and_historical_receiver_pin_required(self):
        for group in ('overload_audit', 'retained_receiver_sites'):
            m = copy.deepcopy(self.manifest)
            m[group].pop()
            self.verify(manifest=m, reason='coverage differs')
        historical_receivers(self.manifest)

    def test_frozen_destinations_and_shuffle_source(self):
        self.assertEqual([], check_earlier(self.manifest, k.ROOT))
        m = copy.deepcopy(self.manifest)
        m['earlier_destinations']['paths'].pop()
        self.assertIn('earlier destination coverage differs', '\n'.join(check_earlier(m, k.ROOT)))

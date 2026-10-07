"""Real phase-2 fixture: companion partition, policy edits and caller patch."""
import copy
from pathlib import Path
import subprocess
import unittest

import check_kotlin_moves as k
from test_kotlin_moves import extraction

MANIFEST = None


class Phase2MovesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = MANIFEST
        cls.original = subprocess.check_output([
            'git', '-C', str(k.ROOT), 'show',
            cls.manifest['base'] + ':' + cls.manifest['source'],
        ]).decode()
        cls.current = extraction(cls.manifest, cls.original)

    def verify(self, current, reason=None, manifest=None):
        errors, count = k.check(manifest or self.manifest, self.original, current)
        self.assertEqual(2839, count)
        if reason is None:
            self.assertEqual([], errors)
        else:
            self.assertTrue(any(reason in error for error in errors), '\n'.join(errors))
            print('EXPECTED PHASE-2 FAILURE:', reason)

    def edit(self, path, before, after, reason):
        current = dict(self.current)
        self.assertEqual(1, current[path].count(before))
        current[path] = current[path].replace(before, after)
        self.verify(current, reason)

    def destination(self, name):
        return next(path for path in self.manifest['destinations'] if Path(path).name == name)

    def test_complete_phase2_extraction(self):
        self.verify(self.current)
        self.assertEqual(54, sum(row['fate'] == 'moved' for row in self.manifest['declarations']))
        self.assertEqual(1, sum(row['fate'] == 'patched' for row in self.manifest['declarations']))
        source = self.current[self.manifest['source']]
        policy = self.current[self.destination('IptvLoadErrorPolicy.kt')]
        self.assertNotIn('@OptIn(UnstableApi::class)\n    internal fun classifyIptvError', policy)
        self.assertEqual(3, sum(text.count('@OptIn(UnstableApi::class)') for path, text in self.current.items() if path != self.manifest['source']))
        self.assertIn('IptvLiveLoadErrorPolicy { iptvChannels.getOrNull(currentIptvIndex)?.isLive == true }', source)
        for name in ('SEARCH_SUBTITLE_LABEL', 'STARTUP_FAILOVER_LOG_TAG', 'EXTERNAL_SUBTITLE_PREFIX', 'PROVIDER_PIKPAK'):
            self.assertNotIn('const val ' + name, source)
        folder = k.evidence_root(k.ROOT) / k.EVIDENCE_PHASE / 'fixtures/phase2'
        for path, text in self.current.items():
            destination = folder / Path(path).name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(text)

    def test_policy_extra_edit_beyond_substitutions(self):
        self.edit(self.destination('IptvLoadErrorPolicy.kt'),
                  'if (loadErrorInfo.errorCount > 15) C.TIME_UNSET else 1_000L',
                  'if (loadErrorInfo.errorCount > 14) C.TIME_UNSET else 1_000L',
                  'token mismatch: class AndroidTvTorrentPlayerActivity/class IptvLiveLoadErrorPolicy')

    def test_setup_player_extra_edit_beyond_patch(self):
        self.edit(self.manifest['source'],
                  '.setLoadErrorHandlingPolicy(IptvLiveLoadErrorPolicy { iptvChannels.getOrNull(currentIptvIndex)?.isLive == true })',
                  '.setLoadErrorHandlingPolicy(IptvLiveLoadErrorPolicy { iptvChannels.getOrNull(currentIptvIndex)?.isLive != true })',
                  'token mismatch: class AndroidTvTorrentPlayerActivity/fun setupPlayer()')

    def test_companion_constant_left_behind(self):
        source = self.manifest['source']
        current = dict(self.current)
        current[source] = current[source].replace('companion object {', 'companion object {\n        private const val EXTERNAL_SUBTITLE_PREFIX = "⬇"', 1)
        self.verify(current, 'surviving-after-move: class AndroidTvTorrentPlayerActivity/companion Companion/property EXTERNAL_SUBTITLE_PREFIX')

    def test_companion_constant_literal_change(self):
        self.edit(self.destination('TvStartupDiagnostics.kt'),
                  'internal const val PROVIDER_PIKPAK = "pikpak"',
                  'internal const val PROVIDER_PIKPAK = "other"',
                  'token mismatch: class AndroidTvTorrentPlayerActivity/companion Companion/property PROVIDER_PIKPAK')

    def test_required_opt_in_removed(self):
        self.edit(self.destination('TvTrackLabels.kt'),
                  '@OptIn(UnstableApi::class)\n    internal fun buildAudioTrackLabel',
                  'internal fun buildAudioTrackLabel',
                  'token mismatch: class AndroidTvTorrentPlayerActivity/fun buildAudioTrackLabel(Format)')

    def test_patch_metadata_is_required(self):
        manifest = copy.deepcopy(self.manifest)
        row = next(row for row in manifest['declarations'] if row['fate'] == 'patched')
        del row['reason']
        self.verify(self.current, 'patched requires exact patches, reason and named test', manifest)

    def test_wrong_policy_substitution_count(self):
        manifest = copy.deepcopy(self.manifest)
        row = next(row for row in manifest['declarations'] if row['original'].endswith('/class IptvLiveLoadErrorPolicy'))
        row['substitutions'][1]['count'] = 2
        with self.assertRaisesRegex(ValueError, 'substitution occurrence count'):
            self.verify(self.current, manifest=manifest)

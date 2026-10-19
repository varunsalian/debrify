#!/usr/bin/env python3
"""Exercise the real PROVISIONAL P18 manifest; no production writes/history claims."""
import argparse
import copy
import json
from pathlib import Path
from check_verbatim_moves import ensure_parser_package
from check_dart_moves import check, retained_manifest
from draft_vplayer_navigation_moves import SOURCE, FEATURE, BASE
from check_verbatim_moves import ROOT
from dart_move_history import git_text


def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parser-package',required=True,type=Path);p.add_argument('--evidence',required=True,type=Path);a=p.parse_args()
 ensure_parser_package(a.parser_package.parent.parent,a.parser_package)
 original=git_text(BASE,SOURCE)
 spec=json.loads((ROOT/'dev/tool/dart_moves/vplayer_p18.json').read_text())
 sources={p:(a.evidence.parent/p).read_text() for p in [SOURCE,*spec['destinations']]}
 sites=json.loads((a.evidence.parent/'retained-sites.json').read_text())
 assert not check(spec,original,sources,a.parser_package)
 retained=retained_manifest(SOURCE,FEATURE,original,BASE,a.parser_package)
 assert not check(retained,original,{SOURCE:original},a.parser_package)
 cases=[
  # Relocated shuffle fields stay inert.
  ('bag-inert-field','vp_shuffle.dart','final List<int> shuffleBag = [];','final List<int> shuffleBag = [0];'),
  ('flag-inert-field','vp_shuffle.dart','bool showShuffleInProgress = false;','bool showShuffleInProgress = true;'),
  ('constructor-host','vp_shuffle.dart','VpShuffle(this._host);','VpShuffle(this._host) { _host.mounted; }'),
  # Set-and-pop: the latch re-check cannot be dropped or reordered.
  ('latch-recheck','vp_episode_next.dart','if (!_host.mounted || _host.seriesNextDispatched) return true;','if (!_host.mounted) return true;'),
  ('latch-set','vp_episode_next.dart','    _host.seriesNextDispatched = true;','    _host.seriesNextDispatched = false;'),
  # Shadowed dialog context: the builder's own context must stay lexical.
  ('dialog-builder-context','vp_shuffle.dart',"onTap: () => Navigator.of(context).pop('once'),","onTap: () => Navigator.of(_host.context).pop('once'),"),
  ('dialog-state-context','vp_shuffle.dart','      context: _host.context,\n      builder: (context) {','      context: context,\n      builder: (context) {'),
  # Formatter-only named-record comma: the value stays pinned.
  ('record-value','vp_episode_title_info.dart','        fetched: false,\n      );','        fetched: true,\n      );'),
  # Interpolated live Host read: a changed expression is rejected.
  ('interpolation','vp_pikpak_retry.dart','index ${_host.currentIndex}, isPikPak','index ${_host.currentIndex + 1}, isPikPak'),
  # Retained adapters reach moved members exactly.
  # (anchored inside the RETAINED P16/P17 adapters, not the new P18 scaffolding)
  ('adapter-receiver','lib/screens/video_player_screen.dart@class _VpDebrifyTvChannelsHostAdapter ','Future<void> waitForVideoReady() => _s._mediaWaits.waitForVideoReady();','Future<void> waitForVideoReady() => _s._mediaWaits.waitForDuration();'),
  ('adapter-collaborator','lib/screens/video_player_screen.dart@class _VpSourcePlaylistSwitchHostAdapter ','}) => _s._playlistLoad.loadPlaylistIndex(','}) => _s._shuffle.loadPlaylistIndex('),
  ('adapter-member','lib/screens/video_player_screen.dart@class _VpPlayerMenuUiHostAdapter ','      _s._shuffle.toggleContinuousShuffle();','      _s._shuffle.playRandomOnce();'),
  # Retained call sites: receiver only, at the same position.
  ('timer-live-setter','vp_playlist_load.dart','_host.manualSelectionResetTimer?.cancel();','_host.manualSelectionResetTimer?.isActive;'),
  ('retained-any-next','lib/screens/video_player_screen.dart','_episodeAdjacent.hasNextEpisode() ||','_episodeAdjacent.hasPreviousEpisode() ||'),
  # Live state: generation bump and token increment keep their direction.
  ('navigation-bump','vp_playlist_load.dart','if (request == null) _host.episodeNavigationGeneration++;','if (request == null) _host.episodeNavigationGeneration--;'),
  ('pikpak-token','vp_pikpak_retry.dart','    _host.pikPakRetryId++;\n    final myRetryId = _host.pikPakRetryId;','    final myRetryId = _host.pikPakRetryId;'),
  ('live-player','vp_episode_next.dart','await _host.player.pause();','await _host.player.play();'),
 ]
 results=[]
 for label,suffix,before,after in cases:
  suffix,_,within=suffix.partition('@')
  path=next(k for k in sources if k.endswith(suffix));text=sources[path]
  start=text.index(within) if within else 0;at=text.index(before,start)
  assert not within or text.find('\nclass ',start+1)>at,(label,'anchor outside class')
  changed=dict(sources);changed[path]=text[:at]+after+text[at+len(before):]
  errors=check(spec,original,changed,a.parser_package);assert errors,label
  results.append(dict(label=label,result='rejected',errors=errors[:3]))
 changed=copy.deepcopy(spec)
 changed['declarations'].append(copy.deepcopy(next(r for r in spec['declarations'] if r['fate']=='moved')))
 assert check(changed,original,sources,a.parser_package)
 a.evidence.parent.mkdir(parents=True,exist_ok=True);a.evidence.write_text(json.dumps(dict(label='PROVISIONAL',original_self_compare='PASS',positive='PASS',negatives=results,duplicate_move='rejected',retained_references=len(sites)),indent=2)+'\n')
 print(f'PASS P18 original self-comparison, materialization, {len(results)+1} independent negatives')


if __name__=='__main__':main()

#!/usr/bin/env python3
"""Exercise the real PROVISIONAL P17 manifest; no production writes/history claims."""
import argparse
import copy
import json
from pathlib import Path
from check_verbatim_moves import ensure_parser_package
from check_dart_moves import check, retained_manifest
from draft_vplayer_tv_episode_moves import SOURCE, FEATURE, BASE
from check_verbatim_moves import ROOT
from dart_move_history import git_text


def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parser-package',required=True,type=Path);p.add_argument('--evidence',required=True,type=Path);a=p.parse_args()
 ensure_parser_package(a.parser_package.parent.parent,a.parser_package)
 original=git_text(BASE,SOURCE)
 spec=json.loads((ROOT/'dev/tool/dart_moves/vplayer_p17.json').read_text())
 sources={p:(a.evidence.parent/p).read_text() for p in [SOURCE,*spec['destinations']]}
 sites=json.loads((a.evidence.parent/'retained-sites.json').read_text())
 assert not check(spec,original,sources,a.parser_package)
 retained=retained_manifest(SOURCE,FEATURE,original,BASE,a.parser_package)
 assert not check(retained,original,{SOURCE:original},a.parser_package)
 cases=[
  ('generation-setter','lib/screens/video_player_screen.dart','_s._episodeNavigationGeneration = v','_s._playlistIdentityToken = v'),
  ('increment','vp_episode_fetch.dart','_host.episodeNavigationGeneration++','_host.episodeNavigationGeneration--'),
  ('clock-capture','vp_debrify_tv_banner.dart','if (resolving || _host.isTransitioning)','if (_host.isTransitioning || _host.isTransitioning)'),
  ('guide-context','vp_episode_guide.dart','      context,','      _host.context,'),
  ('constructor-host','vp_debrify_tv_banner.dart','VpDebrifyTvBanner(this._host);','VpDebrifyTvBanner(this._host) { _host.mounted; }'),
  ('map-identity','vp_stremio_tv_channels.dart','Map<String, dynamic>.from(entry)','entry'),
  ('live-player','vp_stremio_tv_channels.dart','_host.player.seek(seekTo)','_host.player.pause()'),
  ('retained-banner-dispose','lib/screens/video_player_screen.dart','_debrifyBanner.debrifyBannerTimer?.cancel()','_debrifyBanner.debrifyBannerTimer?.isActive'),
  ('guide-compound','vp_episode_guide.dart','_host.episodeMetadataReady ??=','_host.episodeMetadataReady ='),
  ('retain-guard','vp_episode_fetch.dart','        _host.mounted &&','        true &&'),
  ('request-current','vp_episode_fetch.dart','currentNavigation: () => _host.episodeNavigationGeneration','currentNavigation: () => _host.playlistIdentityToken'),
 ]
 results=[]
 for label,suffix,before,after in cases:
  path=next(k for k in sources if k.endswith(suffix));assert before in sources[path],(label,before)
  changed=dict(sources);changed[path]=changed[path].replace(before,after,1)
  errors=check(spec,original,changed,a.parser_package);assert errors,label
  results.append(dict(label=label,result='rejected',errors=errors))
 changed=copy.deepcopy(spec)
 changed['declarations'].append(copy.deepcopy(next(r for r in spec['declarations'] if r['fate']=='moved')))
 assert check(changed,original,sources,a.parser_package)
 a.evidence.parent.mkdir(parents=True,exist_ok=True);a.evidence.write_text(json.dumps(dict(label='PROVISIONAL',original_self_compare='PASS',positive='PASS',negatives=results,duplicate_move='rejected',retained_references=len(sites)),indent=2)+'\n')
 print('PASS P17 original self-comparison, materialization, 12 independent negatives')


if __name__=='__main__':main()

#!/usr/bin/env python3
"""Exercise the real P19 manifest on its probe; no production writes/history claims."""
import argparse
import copy
import json
from pathlib import Path
from check_verbatim_moves import ensure_parser_package
from check_dart_moves import check, retained_manifest
from draft_vplayer_engine_moves import SOURCE, FEATURE, BASE
from check_verbatim_moves import ROOT
from dart_move_history import git_text


def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parser-package',required=True,type=Path);p.add_argument('--evidence',required=True,type=Path);a=p.parse_args()
 ensure_parser_package(a.parser_package.parent.parent,a.parser_package)
 original=git_text(BASE,SOURCE)
 spec=json.loads((ROOT/'dev/tool/dart_moves/vplayer_p19.json').read_text())
 sources={p:(a.evidence.parent/p).read_text() for p in [SOURCE,*spec['destinations']]}
 sites=json.loads((a.evidence.parent/'retained-sites.json').read_text())
 assert not check(spec,original,sources,a.parser_package)
 retained=retained_manifest(SOURCE,FEATURE,original,BASE,a.parser_package)
 assert not check(retained,original,{SOURCE:original},a.parser_package)
 F='lib/screens/video_player_screen.dart'
 cases=[
  # Relocated fields stay inert; the timeout stays a lazily sampled static final.
  ('lease-static-final','vp_video_output_lease.dart','static final Duration outputLeaseTimeout =','late final Duration outputLeaseTimeout ='),
  ('flip-chain-inert','vp_audio_output.dart','Future<void> passthroughFlipChain = Future<void>.value();','Future<void> passthroughFlipChain = Future<void>.delayed(Duration.zero);'),
  ('frame-generation-inert','vp_decoder_probe.dart','int mediaServerFrameGeneration = -1;','int mediaServerFrameGeneration = 0;'),
  ('diagnostic-channel-name','vp_decoder_probe.dart',"'debrify/player_diagnostics',","'debrify/player_diagnostic',"),
  ('constructor-host','vp_renderer_fallback.dart','VpRendererFallback(this._host);','VpRendererFallback(this._host) { _host.mounted; }'),
  # The flip chain is stored synchronously in the caller's turn.
  ('flip-chain-store','vp_audio_output.dart','passthroughFlipChain = flip.catchError((_) {});','passthroughFlipChain = flip;'),
  # S2b/S2f live projections: each site keeps its own predicate.
  ('s2b-moved-predicate','vp_renderer_fallback.dart','isAndroid: _host.isAndroid,','isAndroid: _host.isAndroidRendererValidation,'),
  ('s2f-schedule-predicate','vp_renderer_fallback.dart','isAndroid: _host.isAndroidRendererValidation,','isAndroid: _host.isAndroid,'),
  ('s2f-observer-predicate','vp_decoder_probe.dart','if (!_host.isAndroidRendererValidation) return;','if (_host.isAndroidRendererValidation) return;'),
  ('s2b-projection',F+'@class _VpRendererFallbackHostAdapter ','bool get isAndroid => VpS2Hooks.isAndroid;','bool get isAndroid => VpS2Hooks.isAndroidRendererValidation;'),
  ('s2f-projection',F+'@class _VpDecoderProbeHostAdapter ','VpS2Hooks.isAndroidRendererValidation;','VpS2Hooks.isAndroid;'),
  ('static-host-channel',F+'@class _VpDecoderProbeHostAdapter ','_VideoPlayerScreenState._tvReleaseLogChannel;',"const MethodChannel('debrify/tvlog');"),
  # Fallback synchronous prefix and generation direction.
  ('fallback-in-progress','vp_renderer_fallback.dart','    _host.rendererFallbackInProgress = true;','    _host.rendererFallbackInProgress = false;'),
  ('fallback-generation','vp_renderer_fallback.dart','    _host.playerInstanceGeneration++;','    _host.playerInstanceGeneration--;'),
  # The remedy callback reaches the probe live, guarded by mounted.
  ('remedy-callback','vp_tvos_video.dart','if (_host.mounted) _host.scheduleDecoderProbe();','_host.scheduleDecoderProbe();'),
  # Retained adapters reach moved members exactly (P16/P17 scaffolding).
  ('adapter-external-audio',F+'@class _VpSourceSwitchHostAdapter ','_s._audioOutput.setExternalAudioTrack(url);','_s._audioOutput.setExternalAudioTrack(url.trim());'),
  ('adapter-fallback-owner',F+'@class _VpStartupGateHostAdapter ','}) => _s._rendererFallback.canFallbackExplicitRenderer(','}) => _s._decoderProbe.canFallbackExplicitRenderer('),
  ('adapter-passthrough',F+'@class _VpPlayerMenuUiHostAdapter ','_s._audioOutput.setAudioPassthroughLive(enabled);','_s._audioOutput.setAudioPassthroughLive(!enabled);'),
  # Retained call sites: receiver only; the dispose tear-off stays a tear-off.
  ('dispose-tear-off',F,'}().whenComplete(_videoOutputLease.releaseVideoOutput);','}().whenComplete(() => _videoOutputLease.releaseVideoOutput());'),
  ('retained-claim',F,'    await _videoOutputLease.claimVideoOutput();','    unawaited(_videoOutputLease.claimVideoOutput());'),
  ('retained-boundary',F,'    _tvosVideo.resetTvosDisplayMatchForMediaBoundary();','    _tvosVideo.scheduleTvosDisplayMatch(params);'),
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
 a.evidence.parent.mkdir(parents=True,exist_ok=True);a.evidence.write_text(json.dumps(dict(label='FINAL',original_self_compare='PASS',positive='PASS',negatives=results,duplicate_move='rejected',retained_references=len(sites)),indent=2)+'\n')
 print(f'PASS P19 original self-comparison, materialization, {len(results)+1} independent negatives')


if __name__=='__main__':main()

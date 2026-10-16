"""FINAL P15 real-configuration ownership, forwarding and history negatives."""
import copy,re,json,sys
from pathlib import Path
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'dev/tool'))
from check_dart_moves import check,retained_manifest
from dart_move_history import git_text,earlier_sources
from dart_move_fixture import materialize
from check_verbatim_moves import parse
from draft_vplayer_iptv_moves import GROUPS,STATE
from dart_move_partition import partition
def run(package):
    package=Path(package);spec=json.loads((R/'dev/tool/dart_moves/vplayer_p15.json').read_text());original=git_text(spec['base'],spec['source']);sources=materialize(spec,original,package)
    assert not check(spec,original,sources,package)
    retained=retained_manifest(spec['source'],spec['feature'],original,spec['base'],package)
    assert not check(retained,original,{spec['source']:original},package)
    earlier=earlier_sources(spec)
    assert len(earlier)==32 and spec['base']=='be4cd78aa', (spec['base'],len(earlier))
    print('PASS FINAL all-retained/virtual comparison; all 32 history-derived earlier destinations',flush=True)
    def mutate(path,before,after):
     ts=re.findall(r"'[^']*'|[A-Za-z_$][A-Za-z0-9_$]*|[0-9]+|=>|\+\+|--|\S",before)
     pattern=r'\s*'.join(re.escape(t) for t in ts);matches=list(re.finditer(pattern,sources[path]));assert matches,(path,before)
     found=matches[0];return dict(sources,**{path:sources[path][:found.start()]+after+sources[path][found.end():]})
    D={g['name']:'lib/features/video_player/presentation/legacy_video_player/'+g['file'] for g in GROUPS}
    cases=[
     ('eager Host read',D['VpIptvChannelSwitch'],'VpIptvChannelSwitch(this._host);','VpIptvChannelSwitch(this._host) { _host.mounted; }'),
     ('switch ticket setter',spec['source'],'set iptvSwitchTicket(int v) => _s._iptvSwitchTicket = v;','set iptvSwitchTicket(int v) => _s._currentIptvIndex = v;'),
     ('cached player',spec['source'],'mk.Player get player => _s._player;','late final mk.Player player = _s._player;'),
     ('stale snapshot made live',D['VpIptvWatchMemory'],'final tracks = _host.player.state.tracks;','final tracks = _host.player.state.tracks; _host.player.state.tracks;'),
     ('ticket before await',D['VpIptvChannelSwitch'],'final ticket = ++_host.iptvSwitchTicket;','final ticket = _host.iptvSwitchTicket;'),
     ('timer duration',D['VpIptvZapBanner'],'const Duration(milliseconds: 4500)','const Duration(milliseconds: 4501)'),
     ('header dropped',D['VpIptvLiveSources'],'mk.Media(url, httpHeaders: httpHeaders)','mk.Media(url)'),
     ('lexical context target',D['VpIptvGuideCatchup'],'iptvGuideContextOverride = context','iptvGuideContextOverride = _host.context'),
     ('sleep chain',D['VpIptvChannelSwitch'],'_host.sleepTimerMode','_sleep.sleepTimerMode'),
     ('recording order',D['VpIptvLiveSources'],'await _host.stopRecording(userInitiated: false);',''),
     ('probe pre-ack',D['VpIptvLiveSources'],'var openDone = false;','var openDone = true;'),
     ('owned field wrong Host',D['VpIptvZapLadder'],'iptvZapCachedPage = null;','_host.iptvZapCachedPage = null;'),
    ]
    for name,path,before,after in cases:
     assert check(spec,original,mutate(path,before,after),package),name
     print('PASS rejects '+name,flush=True)
    # Independently corrupt each regenerated adapter, preserving every other
    # class, so one correct forwarder cannot mask a stale sibling.
    adapters={
     '_VpPipLifecycleHostAdapter':('_s._iptvGuide.cancelPendingIptvCatchup','_s._cancelPendingIptvCatchup'),
     '_VpTrackPreferencesHostAdapter':('_s._iptvMemory.applyIptvAudioPreference','_s._applyIptvAudioPreference'),
     '_VpPlayerMenuUiHostAdapter':('_s._iptvMemory.captureIptvAudioLanguage','_s._captureIptvAudioLanguage'),
     '_VpPlayerMenuHostAdapter':('_s._iptvBanner.hideIptvZapBanner','_s._hideIptvZapBanner'),
    }
    for adapter,(before,after) in adapters.items():
     facade=spec['source'];start=sources[facade].index('class '+adapter);end=sources[facade].index('\n}',start)+2
     segment=sources[facade][start:end]
     pattern=r'\s*'.join(map(re.escape,re.findall(r'[A-Za-z_]\w*|\S',before)))
     changed,n=re.subn(pattern,after,segment);assert n==1,(adapter,n)
     current=dict(sources,**{facade:sources[facade][:start]+changed+sources[facade][end:]})
     assert check(spec,original,current,package),adapter
     print('PASS rejects stale '+adapter,flush=True)
    # The context parameter is a guide model, not Flutter's live context.
    altered=copy.deepcopy(spec)
    row=next(r for r in altered['declarations'] if r['original']==STATE+'._persistIptvGuideContext')
    row.setdefault('substitutions',[]).append(dict(before=['=','context',';'],after=['=','_host','.','context',';'],count=1))
    current=mutate(D['VpIptvGuideCatchup'],'iptvGuideContextOverride = context','iptvGuideContextOverride = _host.context')
    assert check(altered,original,current,package), 'lexical context falsely authorized as live State context'
    print('PASS rejects declared lexical guide-context substitution',flush=True)
    print('PASS 17 FINAL negatives; no history waiver',flush=True)

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parser-package', type=Path, required=True)
    args = parser.parse_args()
    assert args.parser_package.resolve().is_relative_to(R / '.dart_tool/vplayer_parser')
    run(args.parser_package)

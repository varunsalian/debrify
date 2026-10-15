"""P15 virtual comparison only; the historical check must reject this base."""
import re,json,sys
from pathlib import Path
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'dev/tool'))
from check_dart_moves import check,retained_manifest
from dart_move_history import git_text,earlier_sources
from dart_move_fixture import materialize
from check_verbatim_moves import parse
from draft_vplayer_iptv_moves import GROUPS,STATE
from dart_move_partition import partition
def run(package):
    package=Path(package);spec=json.loads((R/'dev/tool/dart_moves/vplayer_p15_provisional.json').read_text());original=git_text(spec['base'],spec['source']);sources=materialize(spec,original,package)
    assert not check(spec,original,sources,package)
    retained=retained_manifest(spec['source'],spec['feature'],original,spec['base'],package)
    assert not check(retained,original,{spec['source']:original},package)
    try:earlier_sources(spec)
    except ValueError as e:assert str(e)=='missing historical phase manifests'
    else:raise AssertionError('PROVISIONAL history incorrectly passed')
    print('PASS all-retained original and virtual comparison; historical rejection intact',flush=True)
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
    print('PASS 12 prototype negatives; no history waiver',flush=True)

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parser-package', type=Path, required=True)
    args = parser.parse_args()
    assert args.parser_package.resolve().is_relative_to(R / '.dart_tool/vplayer_parser')
    run(args.parser_package)

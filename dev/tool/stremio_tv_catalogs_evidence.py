"""Worktree-local, serialized suite_evidence entry point for this Step 0."""
import argparse
import fcntl
import sys
from pathlib import Path
import suite_evidence

ROOT=Path(__file__).resolve().parents[2]
EVIDENCE=ROOT/'refactor-evidence'


def run(name, paths, root=ROOT):
    root=Path(root).resolve()
    assert root==ROOT or root.is_relative_to(ROOT/'.dart_tool'),root
    assert name.startswith('stremio_tv_catalogs/') and '..' not in name.split('/')
    lock=ROOT/'.dart_tool/stremio_tv_catalogs_suite.lock';lock.parent.mkdir(exist_ok=True)
    with lock.open('w') as handle:
        fcntl.flock(handle,fcntl.LOCK_EX)
        previous=suite_evidence.ROOT;suite_evidence.ROOT=root
        suite_evidence.evidence_dir=lambda:EVIDENCE
        try: return suite_evidence.cmd_run(name,paths)
        finally: suite_evidence.ROOT=previous

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=ROOT);p.add_argument('name');p.add_argument('paths',nargs=argparse.REMAINDER);a=p.parse_args()
    sys.exit(run(a.name,a.paths,a.root))

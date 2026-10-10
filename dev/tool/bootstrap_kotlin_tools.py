#!/usr/bin/env python3
"""Provision the five checksum-pinned Kotlin tools into GRADLE_USER_HOME."""
import hashlib
from pathlib import Path
import urllib.request

from kotlin_toolchain import ARTIFACTS, artifact_matches, gradle_cache, kotlin_jars, verify_artifact


def main():
    for row in ARTIFACTS:
        matches = artifact_matches(row)
        if len(matches) > 1:
            raise ValueError('ambiguous pinned artifact cache: ' + row['artifact'])
        if matches:
            verify_artifact(matches[0], row)
            print('VERIFIED ' + str(matches[0]), flush=True)
            continue
        filename = row['artifact'] + '-' + row['version'] + '.jar'
        url = 'https://repo.maven.apache.org/maven2/' + '/'.join(
            [row['group'].replace('.', '/'), row['artifact'], row['version'], filename])
        target = gradle_cache() / row['group'] / row['artifact'] / row['version'] / row['sha1'] / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        partial = target.with_suffix('.part')
        try:
            with urllib.request.urlopen(url, timeout=60) as response, partial.open('wb') as out:
                while block := response.read(1024 * 1024):
                    out.write(block)
            verify_artifact(partial, row)
            if hashlib.sha1(partial.read_bytes()).hexdigest() != row['sha1']:
                raise ValueError('pinned artifact directory hash mismatch')
            partial.replace(target)
        finally:
            partial.unlink(missing_ok=True)
        print('DOWNLOADED ' + str(target), flush=True)
    print(f'PASS: all {len(kotlin_jars())} pinned artifacts available offline')


if __name__ == '__main__':
    main()

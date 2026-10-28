#!/usr/bin/env python3
"""Refresh the DMG presentation while preserving an already notarized app."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from installer import build_installer
from release_signing import identity_team, notarize, run, sha256, staple, verify_app

ROOT = Path(__file__).resolve().parents[2]
os.environ.setdefault('DEVELOPER_DIR', '/Library/Developer/CommandLineTools')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--from-version', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--notary-profile', required=True)
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    import re
    for version in (args.version, args.from_version):
        if not re.fullmatch(r'\d+\.\d+\.\d+-preview\.\d+', version):
            parser.error('Expected a preview version')
    if args.version == args.from_version:
        parser.error('Use a new release version')
    team = identity_team(args.identity)
    source_dir = ROOT / 'release' / args.from_version
    source_info = source_dir / 'build-info.json'
    source_zip = source_dir / f'Derivative-{args.from_version}-macos-arm64.zip'
    expected = {line.split('  ', 1)[1]: line.split('  ', 1)[0] for line in (source_dir / 'SHA256SUMS').read_text().splitlines()}
    for path in (source_info, source_zip):
        if sha256(path) != expected[path.name]:
            raise RuntimeError(f'Source artifact checksum mismatch: {path.name}')
    info = json.loads(source_info.read_text())
    if not info['notarized'] or info['teamID'] != team:
        raise RuntimeError('Source must already be notarized by this Developer ID team')
    output = ROOT / 'release' / args.version
    work = output / '.work'
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    config = {'sourceZip': sha256(source_zip), 'packagingCommit': commit, 'identity': args.identity, 'profile': args.notary_profile}
    prepared = work / 'prepared.json'
    if args.resume:
        if json.loads(prepared.read_text()) != config:
            raise RuntimeError('Resume requires the same source, commit, identity and profile')
        app = Path((work / 'app-path.txt').read_text().strip())
    else:
        if output.exists():
            raise RuntimeError('Output exists; use --resume or a new version')
        work.mkdir(parents=True)
        stage = Path(tempfile.mkdtemp(prefix='derivative-repackage-'))
        run('ditto', '-x', '-k', source_zip, stage)
        app = stage / 'Derivative.app'
        verify_app(app, team)
        run('xcrun', 'stapler', 'validate', app)
        run('spctl', '--assess', '--type', 'execute', '--verbose=2', app)
        (work / 'app-path.txt').write_text(str(app) + '\n')
        prepared.write_text(json.dumps(config) + '\n')
    name = f'Derivative-{args.version}-macos-arm64'
    archive, dmg = output / f'{name}.zip', output / f'{name}.dmg'
    if not archive.exists():
        shutil.copyfile(source_zip, archive)  # Byte-for-byte unchanged notarized app.
    if not dmg.exists():
        partial = work / 'installer.dmg'
        partial.unlink(missing_ok=True)
        build_installer(app, partial, args.version)
        run('codesign', '--force', '--sign', args.identity, '--timestamp', partial)
        partial.replace(dmg)
    accepted = work / 'accepted.json'
    if not accepted.exists():
        submission = notarize(dmg, args.notary_profile, output / '.notary')
        staple(dmg)
        accepted.write_text(json.dumps({'dmg': submission}) + '\n')
    run('xcrun', 'stapler', 'validate', dmg)
    run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg)
    info.update(version=args.version, installerSourceCommit=commit, appRelease=args.from_version)
    info['notarizationSubmissions']['dmg'] = json.loads(accepted.read_text())['dmg']
    manifest = output / 'build-info.json'
    manifest.write_text(json.dumps(info, indent=2) + '\n')
    (output / 'SHA256SUMS').write_text(''.join(f'{sha256(path)}  {path.name}\n' for path in (dmg, archive, manifest)))
    run('hdiutil', 'verify', dmg)
    print(f'Installer ready: {dmg}')


if __name__ == '__main__':
    main()

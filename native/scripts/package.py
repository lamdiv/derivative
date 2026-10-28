#!/usr/bin/env python3
"""Build macOS previews, optionally Developer ID signed and notarized."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

from release_signing import identity_team, notarize, sign_app, staple, verify_app
from installer import build_installer

ROOT = Path(__file__).resolve().parents[2]
os.environ.setdefault('DEVELOPER_DIR', '/Library/Developer/CommandLineTools')


def run(*args):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', default='0.1.0-preview.1')
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--identity', help='Developer ID Application name or SHA-1 fingerprint')
    parser.add_argument('--notary-profile', help='Existing notarytool Keychain profile; never a password')
    parser.add_argument('--resume', action='store_true', help='Resume preserved signing/notarization staging')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+-preview\.\d+', args.version):
        parser.error('Use a preview version such as 0.1.0-preview.1')
    signed = bool(args.identity)
    if signed != bool(args.notary_profile):
        parser.error('--identity and --notary-profile must be supplied together')
    team = identity_team(args.identity) if signed else None
    if signed:
        changed = subprocess.check_output([
            'git', 'status', '--porcelain', '--untracked-files=normal', '--',
            'native/Sources', 'native/scripts', 'native/cef.lock.json', 'assets/icon.icns',
        ], cwd=ROOT, text=True)
        if changed.strip():
            raise RuntimeError('Commit release input changes before signing so the source manifest identifies the exact build.')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    output = ROOT / 'release' / args.version
    output.mkdir(parents=True, exist_ok=True)
    work = output / '.work'
    prepared = work / 'prepared.json'
    configuration = {'version': args.version, 'sourceCommit': commit,
                     'identity': args.identity, 'notaryProfile': args.notary_profile}
    name = f'Derivative-{args.version}-macos-arm64'
    dmg, archive = output / f'{name}.dmg', output / f'{name}.zip'
    if args.resume:
        if not prepared.exists() or json.loads(prepared.read_text()) != configuration:
            raise RuntimeError('Resume requires the same prepared source commit, version, identity and Keychain profile')
        stage = Path((work / 'stage-path.txt').read_text().strip())
        if not stage.is_dir():
            raise RuntimeError('Temporary signing stage is missing; build a new release version')
    else:
        if work.exists() or dmg.exists() or archive.exists():
            raise RuntimeError(f'Staging or installer already exists in {output}; use --resume or a new version')
        if signed:
            # Authenticate before building; credentials stay in Keychain.
            subprocess.run(['xcrun', 'notarytool', 'history', '--keychain-profile', args.notary_profile,
                            '--output-format', 'json'], check=True, stdout=subprocess.DEVNULL)
        if not args.skip_build:
            run('python3', 'native/scripts/build.py')
        app = (ROOT / 'native/build/Derivative.app').resolve(strict=True)
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        if info['CFBundleShortVersionString'] != args.version.split('-')[0]:
            raise RuntimeError('Release version does not match app version')
        for bundle_info in app.rglob('Info.plist'):
            if 'LSEnvironment' in plistlib.loads(bundle_info.read_bytes()):
                raise RuntimeError(f'Development environment embedded in {bundle_info}')
        run('codesign', '--verify', '--deep', '--strict', app)
        # Desktop File Provider can add FinderInfo after copying/signing. Keep
        # the persistent signing stage outside the checkout, as build.py does.
        work.mkdir(parents=True)
        stage = Path(tempfile.mkdtemp(prefix='derivative-release-')) / 'image'
        stage.mkdir()
        (work / 'stage-path.txt').write_text(str(stage) + '\n')
        staged_app = stage / 'Derivative.app'
        run('ditto', '--norsrc', '--noextattr', app, staged_app)
        if signed:
            sign_app(staged_app, args.identity)
            # Exercise the hardened runtime before submitting anything to Apple.
            env = {**os.environ, 'DERIVATIVE_NATIVE_APP': str(staged_app)}
            subprocess.run(['node', 'native/scripts/verify.mjs'], cwd=ROOT, env=env, check=True)
            subprocess.run(['node', 'native/scripts/keychain-browser.mjs'], cwd=ROOT, env=env, check=True)
        run('codesign', '--verify', '--deep', '--strict', staged_app)
        (stage / 'Applications').symlink_to('/Applications')
        prepared.write_text(json.dumps(configuration, indent=2) + '\n')
    staged_app = stage / 'Derivative.app'
    info = plistlib.loads((staged_app / 'Contents/Info.plist').read_bytes())
    submissions = {}
    if signed:
        verify_app(staged_app, team)
        app_receipt = work / 'app-accepted.json'
        if not app_receipt.exists():
            upload = work / 'notarization.zip'
            if not upload.exists():
                run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', staged_app, upload)
            submission = notarize(upload, args.notary_profile, output / '.notary')
            staple(staged_app)
            app_receipt.write_text(json.dumps({'app': submission}) + '\n')
        submissions.update(json.loads(app_receipt.read_text()))
        run('xcrun', 'stapler', 'validate', staged_app)
        run('spctl', '--assess', '--type', 'execute', '--verbose=2', staged_app)
    if not archive.exists():
        partial = work / 'distribution.zip'
        partial.unlink(missing_ok=True)
        run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', staged_app, partial)
        partial.replace(archive)
    if not dmg.exists():
        # HFS+ invents Finder metadata for text licenses, breaking strict signing.
        partial = work / 'distribution.dmg'
        partial.unlink(missing_ok=True)
        build_installer(staged_app, partial, args.version)
        if signed:
            run('codesign', '--force', '--sign', args.identity, '--timestamp', partial)
        partial.replace(dmg)
    if signed:
        dmg_receipt = work / 'dmg-accepted.json'
        if not dmg_receipt.exists():
            submission = notarize(dmg, args.notary_profile, output / '.notary')
            staple(dmg)
            dmg_receipt.write_text(json.dumps({'dmg': submission}) + '\n')
        submissions.update(json.loads(dmg_receipt.read_text()))
        run('xcrun', 'stapler', 'validate', dmg)
        run('codesign', '--verify', '--strict', dmg)
        run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg)
    provenance = {
        'version': args.version,
        'sourceCommit': commit,
        'bundleVersion': info['CFBundleVersion'],
        'architecture': 'arm64', 'minimumMacOS': info['LSMinimumSystemVersion'],
        'signing': 'Developer ID' if signed else 'ad-hoc', 'notarized': signed,
        'teamID': team, 'notarizationSubmissions': submissions,
        'engine': json.loads((staged_app / 'Contents/Resources/ThirdParty/CEF-BUILD.json').read_text()),
    }
    manifest = output / 'build-info.json'
    manifest.write_text(json.dumps(provenance, indent=2) + '\n')
    checksums = []
    for artifact in (dmg, archive, manifest):
        with artifact.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        checksums.append(f'{digest}  {artifact.name}\n')
    (output / 'SHA256SUMS').write_text(''.join(checksums))
    run('hdiutil', 'verify', dmg)
    print(f'Preview installers: {output}')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Build a relocatable, ad-hoc signed macOS preview installer."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
os.environ.setdefault('DEVELOPER_DIR', '/Library/Developer/CommandLineTools')


def run(*args):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', default='0.1.0-preview.1')
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+-preview\.\d+', args.version):
        parser.error('Use a preview version such as 0.1.0-preview.1')
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
    output = ROOT / 'release' / args.version
    output.mkdir(parents=True, exist_ok=True)
    name = f'Derivative-{args.version}-macos-arm64'
    dmg, archive = output / f'{name}.dmg', output / f'{name}.zip'
    if dmg.exists() or archive.exists():
        raise RuntimeError(f'Installer already exists in {output}; use a new version or remove it explicitly')
    with tempfile.TemporaryDirectory(prefix='derivative-package-') as work:
        stage = Path(work) / 'image'
        stage.mkdir()
        run('ditto', '--norsrc', '--noextattr', app, stage / 'Derivative.app')
        run('codesign', '--verify', '--deep', '--strict', stage / 'Derivative.app')
        (stage / 'Applications').symlink_to('/Applications')
        (stage / 'Read Me.txt').write_text(
            'Derivative — macOS preview\n\nApple Silicon · macOS 14 or later\n\n'
            'Drag Derivative.app to Applications, then open it from Applications.\n'
            'This preview is ad-hoc signed and is NOT notarized by Apple.\n'
            'macOS may block it. Only open a download you trust; Apple explains\n'
            'the Privacy & Security > Open Anyway option here:\n'
            'https://support.apple.com/102445\n\n'
            'Early development: no automatic updates, password manager, extensions,\n'
            'sync, private browsing, or DRM. H.264/AAC and MP4 streaming are not enabled.\n'
            'Get updates and report issues: https://github.com/lamdiv/derivative\n')
        run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', stage / 'Derivative.app', archive)
        # HFS+ invents Finder type metadata for bundled text licenses, invalidating
        # strict signature verification. APFS preserves the clean staged bundle.
        run('hdiutil', 'create', '-volname', f'Derivative {args.version}', '-fs', 'APFS',
            '-srcfolder', stage, '-format', 'UDZO', '-imagekey', 'zlib-level=9', dmg)
    provenance = {
        'version': args.version,
        'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'bundleVersion': info['CFBundleVersion'],
        'architecture': 'arm64', 'minimumMacOS': info['LSMinimumSystemVersion'],
        'signing': 'ad-hoc', 'notarized': False,
        'engine': json.loads((app / 'Contents/Resources/ThirdParty/CEF-BUILD.json').read_text()),
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

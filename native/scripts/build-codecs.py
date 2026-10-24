#!/usr/bin/env python3
"""Build pinned CEF with H.264/AAC, test a candidate app, then select the engine."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
LOCK = json.loads((ROOT / 'cef.lock.json').read_text())
CODECS = json.loads((ROOT / 'cef-codecs.lock.json').read_text())

def run(*args, **kwargs):
    print('+', ' '.join(str(arg) for arg in args), flush=True)
    subprocess.run([str(arg) for arg in args], check=True, cwd=REPO, **kwargs)

def preflight(work):
    errors = []
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        errors.append('An Apple Silicon Mac is required.')
    try:
        xcode = subprocess.check_output(['xcodebuild', '-version'], text=True, stderr=subprocess.STDOUT)
        if not xcode.startswith('Xcode '): errors.append('Full Xcode is required.')
    except (OSError, subprocess.CalledProcessError):
        errors.append('Full Xcode is missing or not selected. Install it, finish its first launch, and select its Developer directory.')
    if any(char.isspace() for char in str(work)):
        errors.append('CEF source build paths must not contain whitespace.')
    existing = work
    while not existing.exists(): existing = existing.parent
    free = shutil.disk_usage(existing).free / 1024**3
    if free < 200 and not (work / 'chromium/src/out').exists():
        errors.append(f'Allow at least 200 GiB free for the initial checkout/build; available: {free:.1f} GiB.')
    if not shutil.which('node'): errors.append('Node.js is required for playback verification.')
    if not (REPO / 'node_modules/playwright').exists(): errors.append('Install project test dependencies with npm ci.')
    if LOCK['version'].split('+g')[1].split('+')[0] != CODECS['cefCommit'][:7]:
        errors.append('CEF and codec source locks do not match.')
    return errors

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path, default=ROOT / '.cache/codec-source')
    parser.add_argument('--check', action='store_true', help='Check prerequisites without downloading or building')
    parser.add_argument('--plan', action='store_true', help='Print pinned configuration without running it')
    args = parser.parse_args()
    work = args.work_dir.resolve()
    command = [sys.executable, work / 'automate-git.py', f'--download-dir={work}',
               f'--branch={CODECS["cefBranch"]}', f'--checkout={CODECS["cefCommit"]}', f'--chromium-checkout={CODECS["chromiumCheckout"]}',
               '--arm64-build', '--no-debug-build', '--no-chromium-history', '--force-build',
               '--minimal-distrib-only', '--no-distrib-symbols', '--no-distrib-docs', '--no-distrib-archive']
    if args.plan:
        print(json.dumps({'source': CODECS, 'command': list(map(str, command)), 'workDirectory': str(work)}, indent=2))
        return
    errors = preflight(work)
    if errors: raise SystemExit('\n'.join(errors))
    if args.check:
        print('PASS: codec build prerequisites are available.')
        return
    work.mkdir(parents=True, exist_ok=True)
    url = f'https://raw.githubusercontent.com/chromiumembedded/cef/{CODECS["cefCommit"]}/tools/automate/automate-git.py'
    data = urllib.request.urlopen(url, timeout=60).read()
    if hashlib.sha256(data).hexdigest() != CODECS['automateSha256']:
        raise SystemExit('Pinned CEF automation script checksum mismatch.')
    (work / 'automate-git.py').write_bytes(data)
    env = {**os.environ, 'GN_DEFINES': CODECS['gnDefines'], 'CEF_USE_GN': '1', 'DEPOT_TOOLS_UPDATE': '0'}
    # All engine work stays separate from the working browser bundle.
    run(*command, env=env)
    cef = work / 'chromium/src/cef/binary_distrib' / ('cef_binary_' + LOCK['version'] + '_macosarm64_minimal')
    if not cef.is_dir(): raise SystemExit(f'Expected pinned binary distribution was not produced: {cef}')
    binary = cef / 'Release/Chromium Embedded Framework.framework/Chromium Embedded Framework'
    with binary.open('rb') as stream: identity = hashlib.file_digest(stream, 'sha256').hexdigest()
    depot = work / 'depot_tools'
    provenance = {**CODECS, 'depotToolsCommit': subprocess.check_output(['git', '-C', str(depot), 'rev-parse', 'HEAD'], text=True).strip()}
    (cef / 'derivative-build.json').write_text(json.dumps(provenance, indent=2)+'\n')
    candidate = ROOT / 'build/codec-candidate'
    run(sys.executable, ROOT / 'scripts/build.py', '--cef-dir', cef, '--build-dir', candidate)
    app = candidate / 'Derivative.app'
    run('node', ROOT / 'scripts/media.mjs', '--app', app, '--require-proprietary')
    run('node', ROOT / 'scripts/verify.mjs', env={**os.environ, 'DERIVATIVE_NATIVE_APP': str(app)})
    # Persist selection only after real decoding and browser smoke tests pass.
    selected = ROOT / '.cache/selected-cef.json'
    temporary = selected.with_suffix('.tmp')
    temporary.write_text(json.dumps({'version': LOCK['version'], 'directory': str(cef), 'frameworkSha256': identity}, indent=2)+'\n')
    temporary.replace(selected)
    run(sys.executable, ROOT / 'scripts/build.py')
    print('PASS: verified H.264/AAC engine selected and Derivative rebuilt. Restart the app to use it.')

if __name__ == '__main__':
    main()

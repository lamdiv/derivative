"""Developer ID signing and resumable notarization for the packaged app.

No credentials are accepted here: codesign uses Keychain and notarytool uses a
named Keychain profile. Developer signing never uses codesign --deep.
"""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ENTITLEMENTS = {
    'app': {
        'com.apple.security.device.audio-input': True,
        'com.apple.security.device.bluetooth': True,
        'com.apple.security.device.camera': True,
        'com.apple.security.device.print': True,
        'com.apple.security.personal-information.location': True,
    },
    'jit': {'com.apple.security.cs.allow-jit': True},
    'helper': {},
}
HELPER_ROLES = ('', ' (Alerts)', ' (GPU)', ' (Plugin)', ' (Renderer)')
MACHO_MAGIC = {bytes.fromhex(value) for value in (
    'feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca',
    'cafebabf', 'bfbafeca')}


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def identity_team(identity):
    output = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    for fingerprint, name in re.findall(r'\b([0-9A-F]{40}) "([^"]+)"', output):
        if identity in (fingerprint, name) and name.startswith('Developer ID Application: '):
            match = re.search(r'\(([A-Z0-9]{10})\)$', name)
            if match:
                return match.group(1)
    raise RuntimeError('A valid Developer ID Application identity and private key are required in Keychain.')


def signing_plan(app):
    app = Path(app).resolve()
    frameworks = app / 'Contents/Frameworks'
    framework = frameworks / 'Chromium Embedded Framework.framework'
    libraries = framework / 'Libraries'
    plan = []
    for path in sorted(libraries.rglob('*')):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                if stream.read(4) in MACHO_MAGIC:
                    plan.append((path, None))
    if not (framework / 'Chromium Embedded Framework').is_file():
        raise RuntimeError('CEF framework is missing')
    plan.append((framework, None))
    for role in HELPER_ROLES:
        helper = frameworks / f'Derivative Helper{role}.app'
        executable = helper / 'Contents/MacOS' / f'Derivative Helper{role}'
        if not executable.is_file():
            raise RuntimeError(f'Missing helper: {helper.name}')
        plan.append((helper, 'jit' if role in (' (GPU)', ' (Renderer)') else 'helper'))
    plan.append((app, 'app'))
    # Refuse to silently leave a newly introduced native component unsigned.
    covered = {path.resolve() for path, kind in plan if kind is None and path != framework}
    covered.add((framework / 'Chromium Embedded Framework').resolve())
    for bundle, kind in plan:
        if kind:
            info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
            covered.add((bundle / 'Contents/MacOS' / info['CFBundleExecutable']).resolve())
    for path in app.rglob('*'):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                if stream.read(4) in MACHO_MAGIC and path.resolve() not in covered:
                    raise RuntimeError(f'Native code missing from signing inventory: {path}')
    return plan


def verify_app(app, team):
    run('codesign', '--verify', '--deep', '--strict', app)
    for path, kind in signing_plan(app):
        run('codesign', '--verify', '--strict', path)
        result = run('codesign', '--display', '--verbose=4', path, capture_output=True, text=True)
        details = result.stderr
        if f'TeamIdentifier={team}' not in details or 'Timestamp=' not in details:
            raise RuntimeError(f'Missing Team ID or secure timestamp: {path}')
        if kind:
            if 'runtime' not in details:
                raise RuntimeError(f'Hardened runtime is missing: {path}')
            result = run('codesign', '--display', '--entitlements', '-', '--xml', path, capture_output=True)
            actual = plistlib.loads(result.stdout)
            if actual != ENTITLEMENTS[kind]:
                raise RuntimeError(f'Unexpected entitlements on {path}')


def sign_app(app, identity):
    team = identity_team(identity)
    plan = signing_plan(app)
    for attribute in ('com.apple.ResourceFork', 'com.apple.FinderInfo'):
        subprocess.run(['xattr', '-dr', attribute, str(app)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with tempfile.TemporaryDirectory(prefix='derivative-entitlements-') as directory:
        files = {}
        for kind, entitlements in ENTITLEMENTS.items():
            path = Path(directory) / f'{kind}.plist'
            path.write_bytes(plistlib.dumps(entitlements))
            files[kind] = path
        for path, kind in plan:
            command = ['codesign', '--force', '--sign', identity, '--timestamp']
            if kind:
                command += ['--options', 'runtime', '--entitlements', files[kind]]
            run(*command, path)
    verify_app(app, team)
    return team


def notarize(path, profile, receipts):
    """Reuse a submission for identical bytes; a wait timeout never resubmits."""
    receipts = Path(receipts)
    receipts.mkdir(parents=True, exist_ok=True)
    digest = sha256(path)
    receipt = receipts / f'{digest}.json'
    if receipt.exists():
        submission = json.loads(receipt.read_text())
    else:
        result = run('xcrun', 'notarytool', 'submit', path, '--keychain-profile', profile,
                     '--output-format', 'json', capture_output=True, text=True)
        submission = json.loads(result.stdout)
        receipt.write_text(json.dumps(submission, indent=2) + '\n')
    submission_id = submission['id']
    print(f'Apple notarization submission: {submission_id}', flush=True)
    # A first submission can take longer. Preserve staging and the submission ID
    # on timeout; --resume checks this same request instead of making another.
    subprocess.run(['xcrun', 'notarytool', 'wait', submission_id, '--keychain-profile', profile,
                    '--timeout', '10m', '--output-format', 'json'], check=False)
    result = run('xcrun', 'notarytool', 'info', submission_id, '--keychain-profile', profile,
                 '--output-format', 'json', capture_output=True, text=True)
    status = json.loads(result.stdout)
    receipt.write_text(json.dumps(status, indent=2) + '\n')
    if status.get('status') != 'Accepted':
        if status.get('status') in ('Invalid', 'Rejected'):
            run('xcrun', 'notarytool', 'log', submission_id, '--keychain-profile', profile,
                receipts / f'{submission_id}-log.json')
        raise RuntimeError(f'Notarization status is {status.get("status")}. Staging is preserved; inspect the receipt and use --resume when ready.')
    return submission_id


def staple(path):
    run('xcrun', 'stapler', 'staple', path)
    run('xcrun', 'stapler', 'validate', path)

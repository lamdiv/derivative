#!/usr/bin/env python3
"""Build Derivative with SwiftUI, AppKit, and sandboxed Chromium on Apple Silicon."""
import hashlib
import argparse
import json
import os
import platform
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
CACHE = ROOT / '.cache'
BUILD = ROOT / 'build'
LOCK = json.loads((ROOT / 'cef.lock.json').read_text())

def write_app_info(path, identifier, executable, extra=None):
    data = {'CFBundleIdentifier': identifier, 'CFBundleExecutable': executable,
            'CFBundleName': executable, 'CFBundleDisplayName': executable,
            'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1',
            'CFBundleShortVersionString': '0.1.0', 'LSMinimumSystemVersion': '14.0',
            'NSHighResolutionCapable': True,
            'NSBluetoothAlwaysUsageDescription': 'Derivative uses Bluetooth to let you sign in to websites with a passkey on a nearby device or a Bluetooth security key.'}
    data.update(extra or {})
    path.write_bytes(plistlib.dumps(data))

def file_hash(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def validate_cef(cef):
    header = (cef / 'include/cef_version.h').read_text()
    if f'#define CEF_VERSION "{LOCK["version"]}"' not in header:
        raise SystemExit('Custom CEF version must match native/cef.lock.json.')
    binary = cef / 'Release/Chromium Embedded Framework.framework/Chromium Embedded Framework'
    if not binary.is_file():
        raise SystemExit('CEF distribution is missing its Release framework.')
    return file_hash(binary)

def run(*args):
    subprocess.run([str(arg) for arg in args], check=True, cwd=ROOT)

def sign(bundle):
    # Finder/File Provider can attach metadata to app bundles on the Desktop.
    for attribute in ['com.apple.ResourceFork', 'com.apple.FinderInfo']:
        subprocess.run(['xattr', '-dr', attribute, str(bundle)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['xattr', '-d', 'com.apple.FinderInfo', str(bundle)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run('codesign', '--force', '--deep', '--sign', '-', bundle)

def main():
    global BUILD
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cef-dir', type=Path, help='Use a matching local CEF binary distribution')
    parser.add_argument('--build-dir', type=Path, default=BUILD, help='Separate output directory for candidate builds')
    args = parser.parse_args()
    BUILD = args.build_dir.resolve()
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        raise SystemExit('Derivative currently targets Apple Silicon macOS only.')
    CACHE.mkdir(exist_ok=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    selection = CACHE / 'selected-cef.json'
    custom = args.cef_dir
    if custom is None and selection.exists():
        selected = json.loads(selection.read_text())
        if selected['version'] != LOCK['version']:
            raise SystemExit('Selected codec engine is outdated; rebuild it for the current CEF lock.')
        custom = Path(selected['directory'])
        if validate_cef(custom) != selected['frameworkSha256']:
            raise SystemExit('Selected CEF framework checksum changed; rebuild and verify it again.')
    archive = CACHE / LOCK['archive']
    cef = custom.resolve() if custom else CACHE / LOCK['archive'].removesuffix('.tar.bz2')
    if not custom and not cef.exists():
        if not archive.exists():
            print('Downloading official CEF binary (about 135 MB)…', flush=True)
            temporary = archive.with_suffix('.download')
            with urllib.request.urlopen('https://cef-builds.spotifycdn.com/' + LOCK['archive']) as source, temporary.open('wb') as out:
                shutil.copyfileobj(source, out)
            temporary.replace(archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != LOCK['sha256']:
            raise SystemExit('CEF checksum mismatch; remove the cached archive before retrying.')
        with tarfile.open(archive) as bundle:
            bundle.extractall(CACHE, filter='data')
    identity = validate_cef(cef)
    tools = CACHE / 'tools'
    if not (tools / 'bin/cmake').exists() or not (tools / 'bin/ninja').exists():
        run(sys.executable, '-m', 'venv', tools)
        run(tools / 'bin/python', '-m', 'pip', 'install', 'cmake==3.31.6', 'ninja==1.11.1.4')
    cmake = tools / 'bin/cmake'
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
    wrapper_key = hashlib.sha256((str(cef) + identity).encode()).hexdigest()[:16]
    wrapper_build = BUILD / ('cef-' + wrapper_key)
    run(cmake, '-S', cef, '-B', wrapper_build, '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release', '-DPROJECT_ARCH=arm64',
        f'-DCMAKE_MAKE_PROGRAM={tools / "bin/ninja"}', f'-DCMAKE_OSX_SYSROOT={sdk}')
    run(cmake, '--build', wrapper_build, '--target', 'libcef_dll_wrapper', '--parallel', '6')
    wrapper = wrapper_build / 'libcef_dll_wrapper/libcef_dll_wrapper.a'
    sources = ROOT / 'Sources'
    target = 'arm64-apple-macos14.0'
    run('xcrun', 'swiftc', '-swift-version', '5', '-O', '-target', target, '-module-cache-path', CACHE / 'swift-modules',
        '-parse-as-library', '-whole-module-optimization', '-emit-object', '-import-objc-header', sources / 'Bridge.h',
        *sorted(sources.glob('*.swift')), '-o', BUILD / 'BrowserUI.o')
    common = ['-std=c++20', '-O2', '-target', target, '-isysroot', sdk, '-I', cef]
    run('xcrun', 'clang++', *common, '-fobjc-arc', '-c', sources / 'Browser.mm', '-o', BUILD / 'Browser.o')
    # Sign outside File Provider folders, which can re-add FinderInfo during signing.
    bundle_root = Path(tempfile.gettempdir()) / 'derivative-native-builds' / hashlib.sha256(str(BUILD).encode()).hexdigest()[:12]
    app = bundle_root / 'Derivative.app'
    contents = app / 'Contents'
    for directory in ['MacOS', 'Frameworks', 'Resources/ThirdParty']:
        (contents / directory).mkdir(parents=True, exist_ok=True)
    run('xcrun', 'swiftc', '-target', target, BUILD / 'Browser.o', BUILD / 'BrowserUI.o', wrapper,
        '-framework', 'AppKit', '-framework', 'SwiftUI', '-framework', 'IOSurface', '-lc++',
        '-Xlinker', '-ObjC', '-o', contents / 'MacOS/Derivative')
    run('xcrun', 'clang++', *common, sources / 'Helper.cc', wrapper, '-framework', 'AppKit', '-framework', 'IOSurface', '-o', BUILD / 'Helper')
    framework = 'Chromium Embedded Framework.framework'
    destination = contents / 'Frameworks' / framework
    marker = BUILD / '.cef-version'
    if not destination.exists() or not marker.exists() or marker.read_text() != identity:
        if destination.exists(): shutil.rmtree(destination)
        run('ditto', cef / 'Release' / framework, destination)
        marker.write_text(identity)
    write_app_info(contents / 'Info.plist', 'app.derivative.browser.native', 'Derivative',
         {'UTExportedTypeDeclarations': [{'UTTypeIdentifier': 'app.derivative.browser.item', 'UTTypeConformsTo': ['public.data'], 'UTTypeDescription': 'Derivative sidebar item'}], 'NSPrincipalClass': 'DerivativeApplication', 'CFBundleIconFile': 'Derivative.icns', 'NSCameraUsageDescription': 'Allow websites you approve to use your camera.', 'NSMicrophoneUsageDescription': 'Allow websites you approve to use your microphone.', 'NSLocationWhenInUseUsageDescription': 'Allow websites you approve to use your location.'})
    for suffix, identifier in [('', ''), (' (Alerts)', '.alerts'), (' (GPU)', '.gpu'), (' (Plugin)', '.plugin'), (' (Renderer)', '.renderer')]:
        name = 'Derivative Helper' + suffix
        helper = contents / 'Frameworks' / (name + '.app') / 'Contents'
        (helper / 'MacOS').mkdir(parents=True, exist_ok=True)
        shutil.copy2(BUILD / 'Helper', helper / 'MacOS' / name)
        write_app_info(helper / 'Info.plist', 'app.derivative.browser.native.helper' + identifier, name, {'LSUIElement': True})
        sign(helper.parent)
    shutil.copy2(REPO / 'assets/icon.icns', contents / 'Resources/Derivative.icns')
    shutil.copy2(cef / 'LICENSE.txt', contents / 'Resources/ThirdParty/CEF-LICENSE.txt')
    shutil.copy2(cef / 'CREDITS.html', contents / 'Resources/ThirdParty/Chromium-CREDITS.html')
    provenance = {'version': LOCK['version'], 'frameworkSha256': identity, 'source': 'custom' if custom else 'official'}
    manifest = cef / 'derivative-build.json'
    if manifest.exists(): provenance['build'] = json.loads(manifest.read_text())
    (contents / 'Resources/ThirdParty/CEF-BUILD.json').write_text(json.dumps(provenance, indent=2)+'\n')
    sign(app)
    legacy = BUILD / 'Derivative Native.app'
    if legacy.is_symlink(): legacy.unlink()
    output = BUILD / 'Derivative.app'
    if output.is_symlink(): output.unlink()
    elif output.exists(): shutil.rmtree(output)
    output.symlink_to(app, target_is_directory=True)
    print(f'Built {output} → {app}', flush=True)

if __name__ == '__main__':
    main()

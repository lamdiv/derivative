#!/usr/bin/env python3
"""Build an isolated SwiftUI/AppKit + sandboxed CEF prototype on Apple Silicon."""
import hashlib
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

def run(*args):
    subprocess.run([str(arg) for arg in args], check=True, cwd=ROOT)

def sign(bundle):
    # Finder/File Provider can attach metadata to app bundles on the Desktop.
    for attribute in ['com.apple.ResourceFork', 'com.apple.FinderInfo']:
        subprocess.run(['xattr', '-dr', attribute, str(bundle)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['xattr', '-d', 'com.apple.FinderInfo', str(bundle)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run('codesign', '--force', '--deep', '--sign', '-', bundle)

def main():
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        raise SystemExit('This prototype currently targets Apple Silicon macOS only.')
    CACHE.mkdir(exist_ok=True)
    BUILD.mkdir(exist_ok=True)
    archive = CACHE / LOCK['archive']
    cef = CACHE / LOCK['archive'].removesuffix('.tar.bz2')
    if not cef.exists():
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
    tools = CACHE / 'tools'
    if not (tools / 'bin/cmake').exists() or not (tools / 'bin/ninja').exists():
        run(sys.executable, '-m', 'venv', tools)
        run(tools / 'bin/python', '-m', 'pip', 'install', 'cmake==3.31.6', 'ninja==1.11.1.4')
    cmake = tools / 'bin/cmake'
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
    run(cmake, '-S', cef, '-B', BUILD / 'cef', '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release', '-DPROJECT_ARCH=arm64',
        f'-DCMAKE_MAKE_PROGRAM={tools / "bin/ninja"}', f'-DCMAKE_OSX_SYSROOT={sdk}')
    run(cmake, '--build', BUILD / 'cef', '--target', 'libcef_dll_wrapper', '--parallel', '6')
    wrapper = BUILD / 'cef/libcef_dll_wrapper/libcef_dll_wrapper.a'
    sources = ROOT / 'Sources'
    target = 'arm64-apple-macos14.0'
    run('xcrun', 'swiftc', '-swift-version', '5', '-O', '-target', target, '-module-cache-path', CACHE / 'swift-modules',
        '-parse-as-library', '-emit-object', '-import-objc-header', sources / 'Bridge.h',
        sources / 'BrowserUI.swift', '-o', BUILD / 'BrowserUI.o')
    common = ['-std=c++20', '-O2', '-target', target, '-isysroot', sdk, '-I', cef]
    run('xcrun', 'clang++', *common, '-fobjc-arc', '-c', sources / 'Browser.mm', '-o', BUILD / 'Browser.o')
    # Sign outside File Provider folders, which can re-add FinderInfo during signing.
    bundle_root = Path(tempfile.gettempdir()) / 'derivative-native-builds' / hashlib.sha256(str(ROOT).encode()).hexdigest()[:12]
    app = bundle_root / 'Derivative Native.app'
    contents = app / 'Contents'
    for directory in ['MacOS', 'Frameworks', 'Resources/ThirdParty']:
        (contents / directory).mkdir(parents=True, exist_ok=True)
    run('xcrun', 'swiftc', '-target', target, BUILD / 'Browser.o', BUILD / 'BrowserUI.o', wrapper,
        '-framework', 'AppKit', '-framework', 'SwiftUI', '-framework', 'IOSurface', '-lc++',
        '-Xlinker', '-ObjC', '-o', contents / 'MacOS/Derivative Native')
    run('xcrun', 'clang++', *common, sources / 'Helper.cc', wrapper, '-framework', 'AppKit', '-framework', 'IOSurface', '-o', BUILD / 'Helper')
    framework = 'Chromium Embedded Framework.framework'
    destination = contents / 'Frameworks' / framework
    marker = BUILD / '.cef-version'
    if not destination.exists() or not marker.exists() or marker.read_text() != LOCK['version']:
        if destination.exists(): shutil.rmtree(destination)
        run('ditto', cef / 'Release' / framework, destination)
        marker.write_text(LOCK['version'])
    def info(path, identifier, executable, extra=None):
        data = {'CFBundleIdentifier': identifier, 'CFBundleExecutable': executable,
                'CFBundleName': executable, 'CFBundleDisplayName': executable,
                'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1',
                'CFBundleShortVersionString': '0.1.0', 'LSMinimumSystemVersion': '14.0',
                'NSHighResolutionCapable': True}
        data.update(extra or {})
        path.write_bytes(plistlib.dumps(data))
    info(contents / 'Info.plist', 'app.derivative.native.prototype', 'Derivative Native',
         {'NSPrincipalClass': 'DerivativeApplication', 'CFBundleIconFile': 'Derivative.icns'})
    for suffix, identifier in [('', ''), (' (Alerts)', '.alerts'), (' (GPU)', '.gpu'), (' (Plugin)', '.plugin'), (' (Renderer)', '.renderer')]:
        name = 'Derivative Native Helper' + suffix
        helper = contents / 'Frameworks' / (name + '.app') / 'Contents'
        (helper / 'MacOS').mkdir(parents=True, exist_ok=True)
        shutil.copy2(BUILD / 'Helper', helper / 'MacOS' / name)
        info(helper / 'Info.plist', 'app.derivative.native.prototype.helper' + identifier, name, {'LSUIElement': True})
        sign(helper.parent)
    shutil.copy2(REPO / 'assets/icon.icns', contents / 'Resources/Derivative.icns')
    shutil.copy2(cef / 'LICENSE.txt', contents / 'Resources/ThirdParty/CEF-LICENSE.txt')
    shutil.copy2(cef / 'CREDITS.html', contents / 'Resources/ThirdParty/Chromium-CREDITS.html')
    sign(app)
    output = BUILD / 'Derivative Native.app'
    if output.is_symlink(): output.unlink()
    elif output.exists(): shutil.rmtree(output)
    output.symlink_to(app, target_is_directory=True)
    print(f'Built {output} → {app}', flush=True)

if __name__ == '__main__':
    main()

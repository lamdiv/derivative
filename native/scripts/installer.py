"""Create the actual Finder drag-to-install layout without AppleScript."""
from pathlib import Path
import subprocess
import sys
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def build_installer(app, destination, version):
    tools = ROOT / 'native/.cache/dmg-tools'
    python = tools / 'bin/python'
    if not python.exists():
        subprocess.run([sys.executable, '-m', 'venv', str(tools)], check=True)
    subprocess.run([str(python), '-m', 'pip', 'install', '--disable-pip-version-check',
                    'dmgbuild==1.6.7', 'ds_store==1.3.3', 'mac_alias==2.2.3'], check=True)
    generator = tools / 'installer-background'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(ROOT / 'native/.cache/swift-modules'),
                    str(ROOT / 'native/scripts/installer-background.swift'), '-o', str(generator)], check=True)
    background = tools / 'installer-background.png'
    subprocess.run([str(generator), str(background)], check=True)
    subprocess.run([str(generator), str(tools / 'installer-background@2x.png'), '2'], check=True)
    settings = {
        'format': 'UDZO', 'filesystem': 'APFS', 'files': [str(Path(app).resolve())],
        'symlinks': {'Applications': '/Applications'},
        'icon': str(ROOT / 'assets/icon.icns'),
        'background': str(background), 'window_rect': ((180, 180), (640, 420)),
        'default_view': 'icon-view', 'show_icon_preview': True,
        'show_toolbar': False, 'show_status_bar': False, 'show_sidebar': False,
        'show_pathbar': False, 'show_tab_view': False, 'include_icon_view_settings': True,
        'icon_size': 96, 'text_size': 13, 'grid_spacing': 90,
        'icon_locations': {'Derivative.app': (180, 210), 'Applications': (460, 210)},
    }
    import json
    # dmgbuild creates its writable image beside the output. File Provider can
    # lock that image in a synced Desktop checkout, so construct it outside the
    # checkout and copy back only the finished compressed image.
    with tempfile.TemporaryDirectory(prefix='derivative-installer-') as directory:
        image = Path(directory) / 'installer.dmg'
        subprocess.run([str(python), '-c',
                        'import dmgbuild,json,sys; dmgbuild.build_dmg(sys.argv[1],sys.argv[2],settings=json.loads(sys.argv[3]))',
                        str(image), f'Derivative {version}', json.dumps(settings)], check=True)
        shutil.copyfile(image, destination)

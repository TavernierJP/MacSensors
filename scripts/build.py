#!/usr/bin/env python3
"""Build a native, dependency-free Apple Silicon menu-bar app."""
from pathlib import Path
import os
import plistlib
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build'
APP = BUILD / 'MacSensors.app'
BUILD.mkdir(exist_ok=True)
(APP / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
(APP / 'Contents/Resources').mkdir(parents=True, exist_ok=True)
CACHE = BUILD / 'ModuleCache'
ENV = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(CACHE), SWIFT_MODULECACHE_PATH=str(CACHE))

def run(args):
    subprocess.run([str(x) for x in args], check=True, env=ENV)

info = {
    'CFBundleName': 'MacSensors',
    'CFBundleDisplayName': 'MacSensors',
    'CFBundleIdentifier': 'local.tavernierjp.macsensors',
    'CFBundleExecutable': 'MacSensors',
    'CFBundlePackageType': 'APPL',
    'CFBundleInfoDictionaryVersion': '6.0',
    'CFBundleShortVersionString': '1.2',
    'CFBundleVersion': '3',
    'CFBundleIconFile': 'AppIcon',
    'CFBundleSupportedPlatforms': ['MacOSX'],
    'CFBundleDevelopmentRegion': 'fr',
    'LSMinimumSystemVersion': '13.0',
    'LSUIElement': True,
    'LSApplicationCategoryType': 'public.app-category.utilities',
    'NSPrincipalClass': 'NSApplication',
    'NSHighResolutionCapable': True,
    'NSHumanReadableCopyright': 'designed by TavernierJP',
}
with (APP / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump(info, f)

sources = sorted((ROOT / 'Sources').glob('*.swift'))
bridge = ROOT / 'Sources/SensorsBridge.h'
run(['/usr/bin/xcrun', 'clang', '-O2', '-arch', 'arm64', '-mmacosx-version-min=13.0', '-c', ROOT / 'Sources/SensorsBridge.c', '-o', BUILD / 'SensorsBridge.o'])
run(['/usr/bin/xcrun', 'swiftc', '-swift-version', '5', '-O',
     '-target', 'arm64-apple-macosx13.0', '-module-cache-path', CACHE,
     '-framework', 'Cocoa', '-framework', 'ServiceManagement', '-framework', 'IOKit',
     '-import-objc-header', bridge, BUILD / 'SensorsBridge.o',
     *sources, '-o', APP / 'Contents/MacOS/MacSensors'])

run(['/usr/bin/xcrun', 'swiftc', '-O', '-module-cache-path', CACHE,
     ROOT / 'scripts/Icon.swift', '-o', BUILD / 'make-icon'])
iconset = BUILD / 'AppIcon.iconset'
iconset.mkdir(exist_ok=True)
run([BUILD / 'make-icon', iconset])
# PNG-backed ICNS chunks; this also works without iconutil's GUI services.
chunks = []
for kind, name in [('icp4', 'icon_16x16.png'), ('icp5', 'icon_32x32.png'),
                   ('icp6', 'icon_32x32@2x.png'), ('ic07', 'icon_128x128.png'),
                   ('ic08', 'icon_256x256.png'), ('ic09', 'icon_512x512.png'),
                   ('ic10', 'icon_512x512@2x.png'), ('ic11', 'icon_16x16@2x.png'),
                   ('ic12', 'icon_32x32@2x.png'), ('ic13', 'icon_128x128@2x.png'),
                   ('ic14', 'icon_256x256@2x.png')]:
    data = (iconset / name).read_bytes()
    chunks.append(kind.encode('ascii') + struct.pack('>I', len(data) + 8) + data)
payload = b''.join(chunks)
(APP / 'Contents/Resources/AppIcon.icns').write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
shutil.copy2(iconset / 'icon_256x256.png', APP / 'Contents/Resources/AboutIcon.png')
run(['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', APP])
run(['/usr/bin/codesign', '--verify', '--strict', APP])
print(APP)

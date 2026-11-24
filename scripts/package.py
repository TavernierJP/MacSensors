#!/usr/bin/env python3
"""Package the app, license, documentation and complete repository source."""
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
import hashlib

ROOT = Path(__file__).resolve().parents[1]
arguments = [arg for arg in sys.argv[1:] if arg != '--dmg']
OUTPUT = Path(arguments[0]).resolve() if arguments else ROOT / 'dist'
STAGE = ROOT / '.build/MacSensors-1.2'
OUTPUT.mkdir(parents=True, exist_ok=True)
if STAGE.exists():
    shutil.rmtree(STAGE)
STAGE.mkdir()
shutil.copytree(ROOT / '.build/MacSensors.app', STAGE / 'MacSensors.app')
(STAGE / 'Applications').symlink_to('/Applications', target_is_directory=True)
for name in ['README.md', 'README.fr.md', 'LICENSE', 'VALIDATION.md', 'CHANGELOG.md',
             'REFERENCES.md', 'CONTRIBUTING.md']:
    shutil.copy2(ROOT / name, STAGE / name)
shutil.copy2(ROOT / 'README.fr.md', STAGE / 'LIRE-MOI.md')
shutil.copytree(ROOT / 'docs', STAGE / 'docs')
for name in ['preview-light.png', 'preview-dark.png', 'about-light.png', 'about-dark.png']:
    if (ROOT / '.build' / name).exists():
        shutil.copy2(ROOT / '.build' / name, STAGE / name)
with zipfile.ZipFile(STAGE / 'MacSensors-Sources-1.2.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for directory in ['Sources', 'Tests', 'scripts', 'docs', '.github']:
        for path in sorted((ROOT / directory).rglob('*')):
            if path.is_file() and '__pycache__' not in path.parts:
                archive.write(path, Path('MacSensors') / path.relative_to(ROOT))
    for name in ['README.md', 'README.fr.md', 'LICENSE', 'VALIDATION.md', 'REFERENCES.md',
                 'CONTRIBUTING.md', 'CHANGELOG.md', '.gitignore', '.gitattributes']:
        archive.write(ROOT / name, Path('MacSensors') / name)
archive = OUTPUT / 'MacSensors-1.2-AppleSilicon.zip'
subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(STAGE), str(archive)], check=True)
print(archive)
source_archive = OUTPUT / 'MacSensors-Sources-1.2.zip'
shutil.copy2(STAGE / source_archive.name, source_archive)
checksum = OUTPUT / 'SHA256SUMS.txt'
checksum.write_text(''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n'
                            for path in [archive, source_archive]), encoding='utf-8')
print(source_archive)
print(checksum)
# Optional DMG generation uses the host disk-image service; ZIP is always available.
if '--dmg' in sys.argv:
    image = OUTPUT / 'MacSensors-1.2-AppleSilicon.dmg'
    subprocess.run(['/usr/bin/hdiutil', 'create', '-volname', 'MacSensors', '-srcfolder', str(STAGE),
                    '-ov', '-format', 'UDZO', '-fs', 'HFS+', str(image)], check=True)

#!/usr/bin/env python3
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
build = root / '.build'
build.mkdir(exist_ok=True)
subprocess.run(['/usr/bin/xcrun', 'swiftc', '-swift-version', '5', '-O', '-module-cache-path', str(build / 'ModuleCache'),
                '-framework', 'IOKit', '-import-objc-header', str(root / 'Sources/SensorsBridge.h'), str(build / 'SensorsBridge.o'),
                str(root / 'Sources/Metrics.swift'), str(root / 'Sources/Temperatures.swift'), str(root / 'Tests/main.swift'), '-o', str(build / 'metrics-tests')], check=True)
subprocess.run([str(build / 'metrics-tests')], check=True)

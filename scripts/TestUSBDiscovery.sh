#!/bin/bash
# Standalone production-utility checks; never launch macUSB or invoke diskutil.
set -euo pipefail
cd "$(dirname "$0")/.."
test_root=$(mktemp -d "${TMPDIR:-/tmp/}macusb-discovery.XXXXXX")
trap 'rm -rf "$test_root"' EXIT
xcrun swiftc -swift-version 5 -module-cache-path "$test_root/ModuleCache" \
    macUSB/Shared/Services/USBDiscoveryProcessRunner.swift \
    macUSB/Shared/Services/USBDriveRefreshPolicy.swift \
    macUSB/Shared/Services/USBRegistryTraversal.swift \
    tests/USBDiscoveryRegressionTests.swift -o "$test_root/USBDiscoveryTests"
"$test_root/USBDiscoveryTests"

#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

mkdir -p build/tests build/.modcache
sed '/^enum WindowList {/,$d' Sources/TopPin/WindowList.swift > build/tests/WindowInfo.swift
swiftc -swift-version 5 -module-cache-path build/.modcache -module-name PinManagerRegression \
    -framework AppKit -framework ScreenCaptureKit \
    Sources/TopPin/PinManager.swift Sources/TopPin/Settings.swift \
    build/tests/WindowInfo.swift Tests/PinManagerRegression/Fixtures.swift \
    Tests/PinManagerRegression/main.swift -o build/tests/PinManagerRegression
build/tests/PinManagerRegression

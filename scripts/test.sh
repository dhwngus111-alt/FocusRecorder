#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
mkdir -p .build/clang-cache .build/swift-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFT_MODULE_CACHE_PATH="$PWD/.build/swift-cache"
sdk_path="${FOCUS_SDK_PATH:-$(xcrun --show-sdk-path)}"
sdk_path="$(realpath "$sdk_path")"
if [[ "$sdk_path" == *MacOSX27.0.sdk && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
swiftc -sdk "$sdk_path" \
  Sources/FocusCore.swift Tests/CoreTests.swift -o .build/core-tests
.build/core-tests

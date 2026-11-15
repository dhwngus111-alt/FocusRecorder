#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
mkdir -p .build dist/FocusRecorder.app/Contents/MacOS
mkdir -p .build/clang-cache .build/swift-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFT_MODULE_CACHE_PATH="$PWD/.build/swift-cache"
sdk_path="${FOCUS_SDK_PATH:-$(xcrun --show-sdk-path)}"
sdk_path="$(realpath "$sdk_path")"
# Some Command Line Tools 27.0 installations pair a newer compiler with an older SDK build.
if [[ "$sdk_path" == *MacOSX27.0.sdk && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi

swiftc -O -sdk "$sdk_path" \
  -framework AppKit -framework SwiftUI -framework Combine \
  Sources/FocusCore.swift Sources/FocusStore.swift Sources/Views.swift Sources/FocusRecorderApp.swift \
  -o dist/FocusRecorder.app/Contents/MacOS/FocusRecorder

cp Info.plist dist/FocusRecorder.app/Contents/Info.plist
codesign --force --deep --sign - dist/FocusRecorder.app
print "Built dist/FocusRecorder.app"

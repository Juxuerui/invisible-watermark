#!/bin/bash
# Compile and run the algorithm/self-test suite with plain swiftc.
# Works with Command Line Tools (no Xcode) and on CI runners where the
# installed macOS SDK version differs.
set -euo pipefail
cd "$(dirname "$0")"

pick_sdk() {
  if [ -n "${SDK:-}" ] && [ -d "$SDK" ]; then
    echo "$SDK"
    return
  fi
  # Prefer the SDK reported by the active toolchain.
  local detected
  detected="$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || true)"
  if [ -n "$detected" ] && [ -d "$detected" ]; then
    echo "$detected"
    return
  fi
  # Fall back to the newest MacOSX*.sdk available.
  local candidate
  candidate="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -V | tail -1 || true)"
  if [ -n "$candidate" ] && [ -d "$candidate" ]; then
    echo "$candidate"
    return
  fi
  return 1
}

SDK_PATH="$(pick_sdk)" || {
  echo "找不到 macOS SDK，请安装 Xcode 或 Command Line Tools。" >&2
  exit 1
}

# The bundled Swift compiler may be older than the newest installed SDK.
# In that case try older SDKs until one compiles.
try_build() {
  local sdk="$1"
  swiftc -sdk "$sdk" -O -parse-as-library \
    Tests/CoreTests.swift Core/*.swift \
    -o .build/manual/coretests 2>/dev/null
}

mkdir -p .build/manual
echo "Using SDK: $SDK_PATH"
if ! try_build "$SDK_PATH"; then
  echo "当前 SDK 与 Swift 编译器不匹配，尝试较旧的 SDK..."
  for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -rV); do
    if [ "$sdk" = "$SDK_PATH" ]; then continue; fi
    echo "  尝试 $sdk"
    if try_build "$sdk"; then
      SDK_PATH="$sdk"
      break
    fi
  done
fi

if [ ! -x .build/manual/coretests ]; then
  echo "编译失败，请安装 Xcode 后重试（xcode-select -p 应指向 Xcode.app）。" >&2
  exit 1
fi

./.build/manual/coretests

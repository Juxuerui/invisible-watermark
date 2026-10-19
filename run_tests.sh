#!/bin/bash
# Compile and run the algorithm/self-test suite with plain swiftc.
# Works with Command Line Tools (no Xcode), on CI runners, and with Xcode
# toolchains whose SDK version differs from the host macOS version.
set -euo pipefail
cd "$(dirname "$0")"

# Derive the deployment target from the SDK name so the standard library that
# ships inside that SDK is the one actually linked. Without this, swiftc targets
# the host macOS version (e.g. 26.0) and an older SDK (e.g. 15.5) cannot supply
# a matching stdlib.
target_for_sdk() {
  local sdk="$1"
  local version
  version="$(basename "$sdk" | sed -n 's/^MacOSX\([0-9][0-9.]*\)\.sdk$/\1/p')"
  if [ -z "$version" ]; then
    echo ""
    return
  fi
  # Trim trailing ".0" components: 15.5 -> 15.5, 15 -> 15
  echo "arm64-apple-macosx${version}"
}

candidate_sdks() {
  local seen=""
  for sdk in \
    "${SDK:-}" \
    "$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || true)" \
    $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -rV) \
    $(ls -d /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk 2>/dev/null | sort -rV)
  do
    [ -n "$sdk" ] || continue
    [ -d "$sdk" ] || continue
    case " $seen " in *" $sdk "*) continue;; esac
    seen="$seen $sdk"
    echo "$sdk"
  done
}

try_build() {
  local sdk="$1"
  local target
  target="$(target_for_sdk "$sdk")"
  local args=(-sdk "$sdk" -O -parse-as-library)
  if [ -n "$target" ]; then
    args+=(-target "$target")
  fi
  swiftc "${args[@]}" Tests/CoreTests.swift Core/*.swift \
    -o .build/manual/coretests 2>/tmp/swiftc_err.txt
}

mkdir -p .build/manual
rm -f .build/manual/coretests

built=0
for sdk in $(candidate_sdks); do
  target="$(target_for_sdk "$sdk")"
  echo "尝试 SDK: $sdk${target:+  (target: $target)}"
  if try_build "$sdk"; then
    echo "编译成功"
    built=1
    break
  fi
  echo "  失败，首个错误："
  grep -m3 -E "error:" /tmp/swiftc_err.txt | sed 's/^/    /' || head -3 /tmp/swiftc_err.txt | sed 's/^/    /'
done

if [ "$built" -ne 1 ]; then
  echo "" >&2
  echo "全部 SDK 编译失败。请确认已安装 Xcode 或 Command Line Tools。" >&2
  echo "xcode-select -p 当前为: $(xcode-select -p 2>/dev/null || echo 未设置)" >&2
  exit 1
fi

./.build/manual/coretests

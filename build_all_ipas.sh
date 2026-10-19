#!/bin/bash
# Produce both unsigned IPA variants in one go:
#
#   build/InvisibleWatermark.ipa        完整功能（激活页 + 打标 + 查标 + 邮件）
#   build/ActivationTool.ipa            授权工具（只生成/校验设备码与授权码）
#
# Neither IPA is signed. Install via Sideloadly / AltStore / Xcode with a
# development certificate, or re-sign with your own provisioning profile.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-Release}"
OUT="build"

if ! xcodebuild -version >/dev/null 2>&1; then
  cat >&2 <<'EOF'
未找到 xcodebuild。请先安装 Xcode：

  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept

若 App Store 拒绝你的 Apple ID，请改用：
  https://developer.apple.com/download/all/?q=xcode   （免费账号即可）
EOF
  exit 1
fi

build_variant() {
  local name="$1"
  local scheme="$2"
  local bundle_id="$3"
  local extra_swift="$4"

  echo ""
  echo "=== 构建 $name ($bundle_id) ==="
  xcodebuild \
    -project InvisibleWatermark.xcodeproj \
    -scheme "$scheme" \
    -configuration "$CONFIG" \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$OUT/$name-DD" \
    PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS="$extra_swift" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build

  local app="$OUT/$name-DD/Build/Products/$CONFIG-iphoneos/InvisibleWatermark.app"
  if [ ! -d "$app" ]; then
    echo "构建产物缺失: $app" >&2
    exit 1
  fi

  rm -rf "$OUT/$name-Payload" "$OUT/$name.ipa"
  mkdir -p "$OUT/$name-Payload"
  cp -R "$app" "$OUT/$name-Payload/InvisibleWatermark.app"
  (cd "$OUT" && zip -qry "$name.ipa" "$name-Payload")
  echo "→ $OUT/$name.ipa"
}

# 1. 完整应用
build_variant "InvisibleWatermark" "InvisibleWatermark" "com.watermark.app" ""

# 2. 授权工具：仅保留激活界面与授权库，供发码方使用
build_variant "ActivationTool" "InvisibleWatermark" "com.watermark.activationtool" "ACTIVATION_TOOL"

echo ""
echo "完成："
ls -lh "$OUT"/*.ipa
echo ""
echo "两个包都未签名，无法直接装到普通 iPhone。重签示例："
echo "  sideloadly -u <UDID> --ipa build/InvisibleWatermark.ipa"

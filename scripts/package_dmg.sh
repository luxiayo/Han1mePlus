#!/usr/bin/env bash
# 打包仅 ARM64 的 macOS DMG：构建后裁掉 x86_64、重做 ad-hoc 签名、压缩为 DMG。
# 产物：build/Han1mePlus-v<版本>-macos-arm64-<日期>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

base_version=$(grep '^version:' pubspec.yaml | cut -d' ' -f2 | cut -d'+' -f1)
date_tag=$(date +%Y%m%d)
app="build/macos/Build/Products/Release/Han1me+.app"
out="build/Han1mePlus-v${base_version}-macos-arm64-${date_tag}.dmg"

flutter build macos --release

echo "裁剪 x86_64（仅保留 arm64）..."
find "$app" -type f -print0 | while IFS= read -r -d '' file; do
  if lipo -info "$file" 2>/dev/null | grep -q 'x86_64'; then
    lipo "$file" -remove x86_64 -output "$file" 2>/dev/null || true
  fi
done

# 裁剪后原签名失效，重做 ad-hoc 签名
codesign --force --deep --sign - "$app"

hdiutil create -volname Han1mePlus -srcfolder "$app" -ov -format UDZO "$out" | tail -1
echo "已生成 $(pwd)/$out"

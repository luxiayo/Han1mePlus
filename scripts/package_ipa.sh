#!/usr/bin/env bash
# 打包免签名 IPA：flutter 构建后按 Payload 结构压缩。
# 产物：build/Han1mePlus-v<版本>-ios-unsigned-<日期>.ipa
# 侧载安装（AltStore/Sideloadly 等）或自有证书重签后使用。
set -euo pipefail
cd "$(dirname "$0")/.."

base_version=$(grep '^version:' pubspec.yaml | cut -d' ' -f2 | cut -d'+' -f1)
date_tag=$(date +%Y%m%d)
out="build/Han1mePlus-v${base_version}-ios-unsigned-${date_tag}.ipa"

flutter build ios --release --no-codesign

rm -rf build/ipa
mkdir -p build/ipa/Payload
cp -R build/ios/iphoneos/Runner.app build/ipa/Payload/
(
  cd build/ipa
  zip -qry "../$(basename "$out")" Payload
)
rm -rf build/ipa

echo "已生成 $(pwd)/$out"

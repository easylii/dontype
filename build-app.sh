#!/bin/bash
# 编译并打包成 SiYu.app（菜单栏应用）。
# 打成 .app bundle 是为了能正确弹出麦克风/语音/辅助功能的授权对话框。
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ 编译 (release)…"
swift build -c release

APP="Dontype.app"
BIN=".build/release/SiYu"

echo "▸ 组装 $APP…"
rm -rf "$APP" SiYu.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dontype"   # bundle 可执行名 = Dontype（TCC/访达里显示 Dontype）
cp Info.plist "$APP/Contents/Info.plist"

# 本地化的显示名/权限文案：中文系统显示「丝语」，英文系统显示「Dontype」
if [[ -d Resources ]]; then
  for lproj in Resources/*.lproj; do
    [[ -d "$lproj" ]] && cp -R "$lproj" "$APP/Contents/Resources/"
  done
fi

# App 图标：用 make-icon.swift 渲染 1024 PNG → 各尺寸 .iconset → AppIcon.icns
echo "▸ 生成 App 图标…"
PNG="$(mktemp -t siyu-icon).png"
swift make-icon.swift "$PNG" >/dev/null
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz        "$PNG" --out "$ICONSET/icon_${sz}x${sz}.png"      >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$PNG" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$PNG" "$ICONSET"

# 内置 whisper 二进制（共 ~7MB；1.6GB 模型不打包，App 首次启动自动下载）
if [[ -x whisper/whisper-cli && -x whisper/whisper-server ]]; then
  mkdir -p "$APP/Contents/Resources/whisper"
  cp whisper/whisper-cli whisper/whisper-server "$APP/Contents/Resources/whisper/"
fi

# 用固定的自签名证书「SiYu Dev」签名：哈希在变但签名身份稳定，
# 所以 TCC（辅助功能等）授权一次后跨重新编译永久有效，不必每次重授权。
# 证书不在钥匙串时（如换台电脑），自动从 .cert/ 导入。
SIGN_ID="SiYu Dev"
# 必须检查「身份」(证书+私钥)而非只有证书 —— 否则私钥丢了仍跳过导入、签成 adhoc，会把 TCC 授权打掉。
# 自签名不受信任，find-identity 仍会列出它(带 NOT_TRUSTED)，用它判断身份是否齐全。
if ! security find-identity ~/Library/Keychains/login.keychain-db 2>/dev/null | grep -q "$SIGN_ID"; then
  echo "▸ 钥匙串无可用身份「$SIGN_ID」，从 .cert/ 导入…"
  security import .cert/siyu-dev.p12 -k ~/Library/Keychains/login.keychain-db \
    -P siyu -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1 || true
fi
echo "▸ 用固定证书「$SIGN_ID」签名（授权跨重编不失效）…"
# 注意：不要用 --deep —— 单可执行包用 --deep 会签成 adhoc，破坏稳定身份、打掉 TCC 授权。
codesign --force --sign "$SIGN_ID" "$APP"

echo "✓ 完成：$(pwd)/$APP"
echo "  首次运行：open $APP  然后按提示授予 麦克风 / 语音识别 / 辅助功能 权限并重开。"

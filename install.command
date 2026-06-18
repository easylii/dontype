#!/bin/bash
# Dontype（丝语）一键安装：拷到 /Applications、去隔离（免右键打开）、写默认配置、启动。
#
# 首次从 DMG 运行本脚本：右键点它 →「打开」（仅这一次；之后 App 直接双击即可）。
# 之所以还需要这一下：App 是个人自签名、未做 Apple 公证，Gatekeeper 会拦第一次打开。
# 本脚本运行后会替 App 去掉隔离标记，App 本身就能直接双击打开了。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="SiYu.app"
SRC="$DIR/$APP"
DST="/Applications/$APP"

echo "▸ 安装 Dontype…"
[ -d "$SRC" ] || { echo "✗ 找不到 $SRC（请把本脚本和 SiYu.app 放在同一文件夹）"; exit 1; }

# 关掉正在运行的旧实例，避免覆盖时占用
osascript -e 'quit app "SiYu"' >/dev/null 2>&1 || true
pkill -x SiYu >/dev/null 2>&1 || true
sleep 1

echo "▸ 拷贝到 /Applications…"
rm -rf "$DST"
cp -R "$SRC" "$DST"

echo "▸ 去除隔离标记（免去右键打开）…"
xattr -dr com.apple.quarantine "$DST" 2>/dev/null || true

# 预置默认配置（已存在则保留用户的，不覆盖）
CFG_DIR="$HOME/.config/siyu"
CFG="$CFG_DIR/config.json"
mkdir -p "$CFG_DIR"
if [ ! -f "$CFG" ]; then
  cat > "$CFG" <<'JSON'
{
  "apiKey": "",
  "autoPaste": true,
  "cleanup": true,
  "locale": "zh-CN",
  "micDeviceUID": "",
  "model": "claude-haiku-4-5-20251001",
  "recognitionLang": "zh",
  "uiLang": "auto",
  "whisperModel": "large-v3-turbo"
}
JSON
  echo "▸ 已写入默认配置：$CFG"
fi

echo "▸ 启动 Dontype…"
open "$DST"

cat <<'EOF'

✓ 安装完成！Dontype 已在菜单栏（气泡 logo）。

首次打开会先弹「隐私政策」，点「我已阅读，同意」后进入设置向导。

接下来按「设置向导」逐项点一下即可：
  ① 麦克风、② 语音识别，点「请求」允许
  ③ 辅助功能，点「打开设置」，在列表里勾选「Dontype」（中文系统显示为「丝语」；勾上即生效，无需重启）
  ④ 识别模型，点「下载」（约 1.5GB，一次性；下载时先用系统识别顶着）
  ⑤ AI 整理，装了 Claude Code 或 Codex 会自动启用，可点「测试」

用法：双击 Control 开始说话，单击 Control 结束并粘贴到光标；Esc 结束但不粘贴。

完整隐私政策见同文件夹内 PRIVACY.md。可关掉此窗口。
EOF

#!/bin/bash
# 打分发用 DMG：SiYu.app（内置 whisper 二进制）+ 拖入 Applications 的快捷方式 + 安装说明。
# 1.6GB 模型不进 DMG —— App 首次启动自动下载到 ~/Library/Application Support/SiYu/。
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh

DIST="dist-dmg"
DMG="Dontype.dmg"
rm -rf "$DIST" "$DMG"
mkdir "$DIST"
cp -R SiYu.app "$DIST/"
cp install.command "$DIST/"
chmod +x "$DIST/install.command"
[ -f PRIVACY.md ] && cp PRIVACY.md "$DIST/"
ln -s /Applications "$DIST/Applications"

cat > "$DIST/安装说明.txt" <<'EOF'
Dontype（丝语）安装说明
======================

【推荐 · 一键安装】
  右键点击「install.command」，选「打开」，再点「打开」。
  脚本会自动：拷到 Applications、去隔离（之后 App 直接双击即可）、
  写默认配置、启动 Dontype，并弹出「隐私政策」与「设置向导」。
  （只有这第一次需要右键打开脚本，个人自签名应用，Gatekeeper 会拦首次运行。）

【或 · 手动安装】
  1. 把 SiYu.app 拖进 Applications 文件夹。
  2. 首次打开：右键点击 SiYu.app，选「打开」，再点「打开」。

首次启动：
  · 先弹「隐私政策」，点「我已阅读，同意」后继续。
  · 「设置向导」一屏搞定：
  ① 麦克风、② 语音识别，点「请求」允许
  ③ 辅助功能，点「打开设置」，勾选「Dontype」（中文系统显示为「丝语」；勾上即生效，无需重启）
  ④ 识别模型，点「下载」（约 1.5GB，一次性；下载时先用系统识别顶着）
  ⑤ AI 整理（可选），装了 Claude Code 或 Codex 任一（已登录）会自动启用，
     也可在 ~/.config/siyu/config.json 填 Anthropic API key（最快）。可点「测试」。

菜单栏图标常驻，随时可重开「设置向导」。

使用：双击 Control 开始说话，单击 Control 结束并粘贴到光标处；
      Esc 结束但不粘贴（悬浮窗里可点复制）。

完整隐私政策见本文件夹内 PRIVACY.md，或联系 support@easylii.com。
EOF

echo "▸ 生成 $DMG…"
hdiutil create -volname "Dontype 丝语" -srcfolder "$DIST" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DIST"

echo "✓ 完成：$(pwd)/$DMG（$(du -h "$DMG" | cut -f1 | xargs)）"

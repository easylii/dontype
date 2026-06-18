# Dontype（丝语）

Privacy-first 的 Mac 语音输入 + 朗读工具，by **Easylii**。
西文品牌 **Dontype**（Don't type — 说就行），中文 **丝语**。双击 **Control** 开始说话，单击结束 —— 本地转写、AI 整理、自动粘贴到光标处。全程在本机，声音不出这台 Mac。

## 工作流程

```
双击 Control 开始录音（单击结束 / Esc 结束但不粘贴）
  → whisper.cpp 本地识别（中英混说，离线；缺模型时回退 Apple 识别）
  → AI 整理（Claude API / Claude Code / Codex 自动降级；理解后改写成通顺整句）
  → 悬浮窗显示结果 + 复制按钮
  → 自动粘贴到刚才的输入框
```

## Demo

**交互式安装流程演示** —— 在浏览器打开 [`design/dontype-install-flow.html`](design/dontype-install-flow.html),点一遍完整首启体验(Welcome → 隐私同意 → 权限 → 模型 → 热键 → 朗读 → AI → 完成,共 8 屏,含朗读动画演示)。
> 公开后可用 GitHub Pages 托管成一个在线链接;也可在此放真实使用的 GIF（听写 / 朗读 / 剪贴历史）。录制：`Cmd+Shift+5` 录屏,再用 Gifski / Kap 转 GIF。

## 支持的识别语言

> **关键:不需要"多语言识别包"。** 一个 whisper 模型就覆盖约 99 种语言 —— 设定语言或开自动检测即可,不存在按语言下载多个识别模型。

| 档位 | 语言 | 说明 |
|------|------|------|
| **强**（可主推） | English · 中文(普通话) · 日本語 · 한국어 · Spanish · French · German · Italian · Portuguese | turbo ≈ 完整 large-v3 |
| **可用(有保留)** | 粤语 Cantonese · Thai · Vietnamese · Hindi · Russian … | **turbo 在粤语/泰语上明显掉点 → 换 `large-v3`** |
| **弱**（不建议宣传） | 低资源语言 | 错误率高、易幻觉 |

- **turbo vs large-v3**:默认 `large-v3-turbo` 快、对高资源语言≈满血;但**低资源语言(尤其粤语、泰语)会掉**。要更好的多语言精度,把 `whisperModel` 换成 `large-v3`。
- **自动检测**:设 `recognitionLang: "auto"`,whisper 自动判断你说的语言 —— 做多语言时推荐。
- **界面语言**(菜单/向导)和识别语言是两回事:目前中/英,其它语言回退英文。日本语日本語 / 韩语等 UI 需要时再加翻译,渐进即可。

## 安装

**分发安装（推荐）**：`./make-dmg.sh` 打出 `Dontype.dmg`（内含 `install.command` / `PRIVACY.md` / 安装说明）。装机时右键点 DMG 里的 **install.command** →「打开」，脚本自动拷到 `/Applications`、去隔离（之后直接双击）、写默认配置并启动。

**首次启动 = 分页设置向导**：Welcome → **隐私政策（必须同意才能继续）** → 权限 → 模型 → 热键 → 朗读 → AI → 完成。之后菜单栏「设置」会打开**单窗口设置面板**（不再走分页流程）。

**本地开发**：

```bash
cd ~/Documents/SiYu
./build-app.sh          # 编译 + 打包 + 签名 → SiYu.app
open SiYu.app
```

> 注：app bundle 内部仍叫 `SiYu.app`，但 Finder / 权限 / 菜单显示的品牌名是 **Dontype**（英文系统）/ **丝语**（中文系统），靠 `Info.plist` + `Resources/*.lproj` 本地化。
> 签名证书在 `.cert/`（**不在仓库里**，需单独备份）—— 固定证书保证「辅助功能」等授权跨重编不失效。

启动后菜单栏出现**气泡 logo**，录音时变实心红、整理时变实心橙。

## 剪贴历史（最多 5 条）

菜单栏「语音输入」区有一个**剪贴历史**，最多 5 条、点一下复制回剪贴板：
- 两种来源，带图标区分：🌊 本 app 转写结果 / 📋 你手动复制的文字。
- **自动去重**：同样内容只留一条并置顶。
- **纯内存、不落盘、退出即清**；密码管理器标记的敏感剪贴**不收**。

## 朗读选中文字（反向）

在**任何 app**里选中（或把光标放到起点）→ **双击右 ⌘** → 用 Premium 嗓音**从这里往下念到当前文本块结尾**（离线、免费）。念的时候**单击右 ⌘**暂停/继续，**Esc** 停。
- 往下读：优先用辅助功能拿「焦点文本框全文 + 选区位置」，从选区起点读到该文本块结尾；拿不到（部分网页/终端/Electron）就退回**只念选中那段**。
- 选区抓取兜底：辅助功能拿不到时，模拟 Cmd+C 读剪贴板并**还原**。
- 设置：在设置面板「⑧ 朗读选中文字 → 设置」里搞定语音 / 语速 / 触发键 / 试听；没有 Premium 嗓音时有入口去系统设置下载。

## 隐私

声音永不离开本机、零收集、零追踪、无账号、无埋点。可选的 AI 整理只发**文字**（非音频）到你**自己配置**的 Claude/Codex 账号。完整政策见 [`PRIVACY.md`](PRIVACY.md)（双语，GDPR / CCPA 级）。首次启动有隐私同意关卡。

## 配置

AI 清洗后端按优先级自动选：`Claude API（最快）→ Claude Code → Codex → 原文直出`，任一档失败自动降级。想用最快的 API：环境变量 `ANTHROPIC_API_KEY`，或在 `~/.config/siyu/config.json` 填 `apiKey`。没有 key 也能用：有 Claude Code / Codex 就走订阅，都没有则输出识别原文。

`~/.config/siyu/config.json` 字段：

| 字段 | 说明 | 默认 |
|------|------|------|
| `apiKey` | Anthropic API key | 空（回退到环境变量） |
| `model` | API 清洗用的模型 | `claude-haiku-4-5-20251001` |
| `cleanup` | 是否开启 AI 清洗（自动判断口水词才整理） | `true` |
| `autoPaste` | 出结果后自动粘贴到光标 | `true` |
| `locale` | Apple 备用后端的识别 locale | `zh-CN` |
| `whisperModel` | whisper 模型 id（`large-v3-turbo` / `large-v3` / `medium` / `small`） | `large-v3-turbo` |
| `recognitionLang` | whisper 识别语言（`zh` / `en` / `ja` / `ko` / `yue` / `auto`） | `zh` |
| `uiLang` | 界面语言（`auto` / `zh` / `en`） | `auto` |
| `readKey` | 朗读触发键（`control`/`fn`/`rightCommand`/`rightOption`/`option`） | `rightCommand` |
| `readVoice` | 朗读嗓音 id（空=按文字语言自动挑 Premium） | 空 |
| `readRate` | 朗读语速 0…1 | `0.5` |

## 结构

| 文件 | 职责 |
|------|------|
| `AppDelegate.swift` | 菜单栏、流程编排、剪贴历史、权限 |
| `HotkeyMonitor.swift` | 全局双击修饰键检测（CGEventTap） |
| `Dictation.swift` | 录音 + 识别（whisper 首选，Apple 备用） |
| `Whisper.swift` | whisper.cpp 后端：模型目录、识别语言、常驻 server |
| `Cleaner.swift` | AI 整理（API / Claude Code / Codex 降级链，理解后改写成整句） |
| `ModelDownloader.swift` | whisper 模型下载（进度回调给向导） |
| `TextGrabber.swift` | 取选中文字（辅助功能直读 + Cmd+C 兜底还原剪贴板） |
| `Speaker.swift` | 朗读引擎（AVSpeechSynthesizer + Premium 嗓音，按语言自动挑） |
| `HotkeySetup.swift` / `ReadSetup.swift` | 开始/结束热键、朗读设置（双击测试确认才生效） |
| `Onboarding.swift` | 首装**分页向导**（含隐私同意）+ 菜单**设置面板**（同类两模式） |
| `RecallStore.swift` | 剪贴历史（最多 5 条、去重、纯内存、跳过敏感剪贴） |
| `IconRenderer.swift` | 菜单栏图标 + 麦克风来源图标（SVG 路径实时绘制） |
| `HUD.swift` | 悬浮结果窗 / 可拖动药丸 / 朗读声波 |
| `Paster.swift` | 剪贴板 + 合成 Cmd+V |
| `L.swift` | 界面多语言（中/英） · `Config.swift` 运行配置 |

`design/dontype-install-flow.html` 是完整安装体验的交互原型（演示用）。

## 后续可升级

- **流式识别**：边说边出字（whisper-server 已常驻，可做分段流式）。
- **CoreML 加速**：为 whisper encoder 开 CoreML。
- **Developer ID 公证**：换签名 + notarize，去掉首次「右键打开」。

# 丝语 SiYu

自用的 Mac 中文语音输入。双击 **Control** 开始说话，单击结束 —— 自动转写、AI 整理、复制并粘贴到光标处。类似 Typeless，但本地、免费、为自己定制。

## 工作流程

```
双击 Control 开始录音（单击结束 / Esc 结束但不粘贴）
  → whisper.cpp 本地识别（中英混说，离线；缺模型时回退 Apple 识别）
  → AI 整理（Claude API / Claude Code / Codex 自动降级，去口水词 / 顺语序）
  → 悬浮窗显示结果 + 复制按钮
  → 自动粘贴到刚才的输入框
```

## 安装

**分发安装（推荐）**：`./make-dmg.sh` 打出 `SiYu.dmg`。装机时右键点 DMG 里的 **install.command** →「打开」，脚本会自动拷到 `/Applications`、去隔离（之后 App 直接双击）、写默认配置并启动，随后弹出**设置向导**带你走完权限与模型下载。

**本地开发**：

```bash
cd ~/Documents/SiYu
./build-app.sh          # 编译 + 打包 + 签名 → SiYu.app
open SiYu.app
```

首次启动弹出**设置向导**（也可从菜单「设置向导…」随时重开），一屏完成：
1. **麦克风** —— 点「请求」录音权限
2. **语音识别** —— 点「请求」（仅备用后端用）
3. **辅助功能** —— 点「打开设置」勾选 丝语（监听热键 + 自动粘贴；**勾上即生效，无需重启**）
4. **识别模型** —— 点「下载」（whisper 模型 ~1.5GB，一次性；下载期间走系统识别顶着）
5. **AI 整理** —— 装了 Claude Code 或 Codex 自动启用，可点「测试」

启动后菜单栏出现「丝」字图标，录音时变「● 丝」。

## 朗读选中文字（反向）

在**任何 app**里选中（或把光标放到起点）→ **双击右 ⌘** → 用 Premium 嗓音**从这里往下念到当前文本块结尾**（离线、免费）。念的时候**单击右 ⌘**暂停/继续，**Esc** 停；菜单栏旁的药丸会显示声波。
- 往下读：优先用辅助功能拿「焦点文本框的全文 + 选区位置」，从选区起点读到该文本块结尾（不跳到别的区块）；拿不到（部分网页/终端/Electron）就退回**只念选中的那段**。
- 选区抓取兜底：辅助功能拿不到选中文字时，模拟 Cmd+C 读剪贴板并**还原** —— 终端里的 Claude Code、VS Code、网页都覆盖。
- 设置：在「设置向导 ▸ ⑦ 朗读选中文字 → 设置」里一处搞定 —— 语音（Premium/自动按语言挑）、语速、触发键（默认双击右 ⌘，和说话的 `triggerKey` 分开）、试听。没有 Premium 嗓音时有入口去系统设置下载。

## 配置

菜单栏图标点开可切换：**AI 整理** 开关、**自动粘贴**、**麦克风**、**识别模型**、**识别语言**、**界面语言**，以及重开**设置向导**。

AI 清洗的后端按优先级自动选择：`Claude API（最快）→ Claude Code → Codex → 原文直出`，任一档失败自动降级。想用最快的 API：
- 环境变量 `ANTHROPIC_API_KEY`，或
- 在 `~/.config/siyu/config.json` 填 `apiKey`

没有 key 也能用：有 Claude Code / Codex 就走订阅，都没有则直接输出识别原文。

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
| `HotkeyMonitor.swift` | 全局双击修饰键检测（CGEventTap） |
| `Dictation.swift` | 录音 + 识别（whisper 首选，Apple 备用） |
| `Whisper.swift` | whisper.cpp 后端：模型目录、识别语言、常驻 server |
| `TextGrabber.swift` | 取选中文字（辅助功能直读 + Cmd+C 兜底还原剪贴板） |
| `Speaker.swift` | 朗读引擎（AVSpeechSynthesizer + Premium 嗓音、按语言自动挑） |
| `HotkeySetup.swift` | 开始/结束热键设置（双击测试确认才生效） |
| `ReadSetup.swift` | 朗读设置（语音/语速/触发键/试听，从设置向导进入） |
| `Cleaner.swift` | AI 整理（API / Claude Code / Codex 降级链，按语言选 prompt） |
| `ModelDownloader.swift` | whisper 模型下载（进度回调给设置向导） |
| `Onboarding.swift` | 设置向导：权限清单 / 模型下载 / 后端检查 一屏完成 |
| `L.swift` | 界面多语言（中/英） |
| `HUD.swift` | 悬浮结果窗 + 复制/粘贴 |
| `Paster.swift` | 剪贴板 + 合成 Cmd+V |
| `AppDelegate.swift` | 菜单栏、流程编排、权限 |

## 后续可升级

- **流式识别**：边说边出字，进一步降延迟（whisper-server 已常驻，可做分段流式）。
- **CoreML 加速**：为 whisper encoder 开 CoreML，Apple Silicon 上识别更快。
- **自定义手势**：触发键在「设置向导 ▸ ⑥ 开始/结束热键」里选并确认生效（Typeless 式：双击测试通过才启用）；目前手势固定为双击开始/单击结束，未来可让「开始/结束分别用单击或双击」也可配。

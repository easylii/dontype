# Dontype（丝语）

[English](README.md) · **中文** · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md)

**Vibe Coding 的 Mac 终极语音搭子**，by **Easylii**。西文品牌 **Dontype**（Don't type — 说就行），中文 **丝语**。

Vibe coding 是**对着 AI 说**、而不是把一切都打出来。Dontype 让你的 Mac 听你说：把提示词**直接说进 Claude Code、Cursor、任何输入框** —— 双击 **Control** 开口说，它本地转写、去口水词、粘到光标处，一个键**发送**；整套流程还能**拿 Apple TV 遥控器隔空操作**，回复也能**念给你听**。全程在本机，声音不出这台 Mac。

## 核心亮点

- **为 vibe coding 而生。** 把提示词直接说进 Claude Code、Cursor、ChatGPT 或任何输入框 —— 说完它去掉"嗯/那个"、顺好句子、粘到光标,一个键**发送**(回车)。往后一靠,整套流程用 Apple TV 遥控器搞定。
- **三合一。** 语音 → 文字（听写）、文字 → 语音（朗读选中文字）、再加 5 条剪贴历史 —— 一个菜单栏 app 里三件套。多数听写工具只做一件。
- **不花额外的钱、不走计费 API。** 识别**全本地**（免费、离线、不耗流量）；AI 整理直接用你**已有的 Claude Code / Codex 订阅**（走它们的 CLI）—— 不需要单独的 Anthropic API key，也不按 token 计费。没有额外开销；两个都没有时,直接输出原始转写（照样免费）。
- **5 条剪贴历史。** 每条转写结果、每次手动复制都进一个 5 条的历史（去重、标来源）—— 点一下复制回去。纯内存、敏感剪贴不收。
- **支持 Apple TV 遥控器（第 2 / 3 代）。** 拿着 Siri Remote 隔着房间也能听写：按 **TV** 开始说话、再按 **TV** 完成、**OK** 发送、**返回 ‹ / Esc** 取消、滑**触摸板**移动光标、**方向键**当 Tab 在控件间跳。在设置向导的「遥控器」页里配置（有动画演示逐步说明）。
- **语音对话 Claude Code**（实验）。一个可选的语音助手,用对讲机方式跟 Claude Code 语音聊天 —— 按遥控器**侧键**说话、再按一下、它把回答念给你。在线 + 只读、单独 opt-in,和本地内核分开。
- **用摄像头隔空操控。** 从菜单打开**摄像头**,实时追踪你的**脸 / 手 / 身体**,全程**本地**（Apple Vision —— 画面不出这台 Mac）。把手当鼠标 —— 指着移动光标、**捏合点击/拖拽** —— 或**训练你自己的手势**,映射到点击 / 滚动 / Esc / 空格。
- **让 Mac 保持唤醒 —— 合盖、用电池也不断网。** 菜单栏一个类 Amphetamine 的开关,阻止系统休眠、让 Wi-Fi / 手机热点在你走开时也保持连接:选 **30 分钟 / 1 小时 / 2 小时**,或**一直开到电池剩 15%**,菜单栏图标旁走实时倒计时。

## 工作流程

```
双击 Control 开始录音（单击结束 / Esc 结束但不粘贴）
  → whisper.cpp 本地识别（中英混说，离线；缺模型时回退 Apple 识别）
  → AI 整理（Claude API / Claude Code / Codex 自动降级；理解后改写成通顺整句）
  → 悬浮窗显示结果 + 复制按钮
  → 自动粘贴到刚才的输入框
```

## Demo

**语音 → 文字** —— 双击 Control,说话,文字直接落到光标处:

![语音转文字 demo](design/demo-stt.svg)

**文字 → 语音** —— 选中文字,双击 右⌘,用嗓音念出来:

![文字转语音 demo](design/demo-tts.svg)

**剪贴历史** —— 最近 5 条(转写 + 手动复制),点一条复制回去:

![剪贴历史 demo](design/demo-clipboard.svg)

**Apple TV 遥控器(第 2 / 3 代)** —— 按 **TV** 说话、再按 **TV** 把文字打到光标处、**返回 ‹ / Esc** 取消、滑**触摸板**移动鼠标:

![Apple TV 遥控器 demo](design/demo-remote.svg)

**交互式安装流程演示** —— 在浏览器打开 [`design/dontype-install-flow.html`](design/dontype-install-flow.html),点一遍完整首启体验（8 屏:Welcome → 隐私同意 → 权限 → 模型 → 热键 → 朗读 → AI → 完成）。

> 上面两个是**动画 SVG**(README 里会动)。要真机效果就用 `Cmd+Shift+5` 录屏 → Gifski / Kap 转 GIF;公开后还能用 GitHub Pages 把 HTML 那个挂上线。

## 支持的识别语言

> **关键：不需要"多语言识别包"。** 一个 whisper 模型就覆盖约 99 种语言 —— 设定语言或开自动检测即可，不存在按语言下载多个识别模型。

**默认自动检测**（`recognitionLang: auto`）—— 说什么自动认，无需手动选。识别语言下拉只列**主推语言**做手动锁定：

| 档位 | 语言 | 说明 |
|------|------|------|
| **主推**（下拉可选、官方支持） | English · 中文(普通话) · 日本語 · 한국어 · Spanish · French | turbo ≈ 完整 large-v3，可放心宣传 |
| 可用但掉点 | 粤语 · 泰语 · 越南语等 | turbo 在粤语/泰语明显变差 → 想要就把 `whisperModel` 换 `large-v3`；不在主推下拉里，靠 auto 也能认 |
| 弱（不宣传） | 低资源语言 | 错误率高、易幻觉 |

- **turbo vs large-v3**：默认 `large-v3-turbo` 快、对高资源语言 ≈ 满血；低资源语言（尤其粤语、泰语）会掉，需要就换 `large-v3`。
- **界面语言**（菜单/向导）和识别语言是两回事：目前中/英，其它语言回退英文。日/韩等 UI 需要时再加翻译，渐进即可。

## 安装

**分发安装（推荐）**：`./make-dmg.sh` 打出 `Dontype.dmg`（内含 `install.command` / `PRIVACY.md` / 安装说明）。装机时右键点 DMG 里的 **install.command** →「打开」，脚本自动拷到 `/Applications`、去隔离（之后直接双击）、写默认配置并启动。

**首次启动 = 分页设置向导**：Welcome → **隐私政策（必须同意才能继续）** → 权限 → 模型 → 热键 → 朗读 → AI → 完成。之后菜单栏「设置」打开**单窗口设置面板**（不再走分页流程）。

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

## Apple TV 遥控器（第 2 / 3 代）

拿着 **Siri Remote（第 2 或第 3 代）**隔着房间也能用 Dontype —— 不用额外硬件，像普通 Mac 输入设备一样走蓝牙配对。在设置向导的 **⑧ 遥控器** 页里开启（带上面那个动画演示）；一次性的**输入监视**权限让 app 能读到遥控器按键。

| 遥控器 | 作用 |
|--------|------|
| **TV** | 开始说话 —— **再按一次**完成，文字打到光标处 |
| **中间（OK）** | **发送** —— 刚听写完按它就发**回车**（把提示词发出去）；其它情况激活聚焦的控件 / 在光标处点击 |
| **返回 ‹ / Esc** | 取消 —— 立刻停止听写/朗读，不转写、不粘贴 |
| **↑ / ↓** | 在列表、菜单、侧栏里上下移动 |
| **← / →** | Tab / Shift+Tab 在控件（链接、按钮、输入框）间跳 |
| **侧键** | 开关**语音助手**（对讲机式语音聊 Claude Code） |
| **触摸板** | 滑动移动鼠标光标；中间键点击 |

音量、静音、播放/暂停保留系统原功能。开启遥控器时还会自动打开 macOS 的**键盘导航**（全键盘访问），让 Tab 能落到按钮、而不只是文本框。

> 遥控器的三路输入各用一套 macOS API（媒体键走 CGEvent tap、特殊键走 IOHIDManager、触摸面走私有的 MultitouchSupport 框架）。最后这条意味着 app 无法上架沙盒化的 App Store —— 它是个进阶功能，在遥控器页里开关。

## 摄像头追踪 & 手势控制

从菜单打开**摄像头**,实时追踪你的**脸 / 手 / 身体** —— 全程**本地** Apple Vision,画面不出这台 Mac（有镜像实时预览;脸/手/身体可分别开关）。在此之上有两种隔空操控:

- **手当鼠标** —— 食指指向移动光标、**捏合**点击和拖拽（绝对映射 + 平滑,横跨你所有显示器）。一块摄像头空中触控板,不用碰触摸板。
- **训练自己的手势** —— 打开训练器,给手势起名、选动作（**左/右键单击、向上/向下滚动、Esc、空格**），对着摄像头保持约 1 秒（多录几次更准）。本地少样本学习（Vision 手部关键点 + 最近邻）,一认出手势就触发你设的动作。

全程本地运行;摄像头在菜单里按需开启,需一次性摄像头权限。

## 保持唤醒（合盖也不断网）

菜单栏一个类 Amphetamine 的**保持唤醒**开关,阻止 Mac 休眠 —— 让 Wi-Fi 或手机热点在你走开、合上盖子时也保持连接。可选 **30 分钟 / 1 小时 / 2 小时**,或**一直开到电池 ≤ 15%**;菜单栏图标旁有实时**倒计时**,随时能关。定时到点、电池降到 15%（用电池时）、或退出 App,都会自动关闭。

Apple Silicon 上,**电池 + 合盖**还保持唤醒是 IOKit 电源断言和 `caffeinate -s` 都做不到的（固件强制休眠）。保持唤醒用 root 级的 `pmset disablesleep`,首次开启时经一次系统授权装一条**极窄的 sudoers 白名单**（只允许 `pmset disablesleep 0|1`,安装前用 `visudo` 校验），之后全部静默切换 —— 因为定时/低电自动关可能在合着盖时触发,那时根本看不到密码框。

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
| `whisperModel` | whisper 模型 id（`large-v3-turbo` / `large-v3` / `medium` / `small`） | `large-v3-turbo` |
| `recognitionLang` | 识别语言（`auto` / `en` / `zh` / `ja` / `ko` / `es` / `fr`） | `auto` |
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
| `RemoteHID.swift` | Apple TV 遥控器特殊键（IOHIDManager，HID 报文 id=251）→ 动作 |
| `Multitouch.swift` | 遥控器触摸面 → 鼠标光标（私有 MultitouchSupport，family 0x91） |
| `Camera.swift` | 摄像头 + 本地 Vision 追踪（脸 / 手 / 身体）、镜像预览、手当鼠标（捏合点击/拖拽） |
| `Gestures.swift` | 自定义手势训练（少样本：Vision 手部关键点 + k-NN）→ 动作（点击 / 滚动 / Esc / 空格） |
| `KeepAwake.swift` | 保持唤醒：阻止休眠（含电池合盖，`pmset disablesleep`，一次性 sudoers 授权）、定时/电池自动关、菜单栏倒计时 |
| `RemoteSetup.swift` | 遥控器设置 / 演示页（识别连接状态，动画 SVG 演示） |
| `GameControllerInput.swift` | 蓝牙手柄输入（听写 / 光标 / 方向键） |
| `Assistant.swift` · `VoiceLoop.swift` · `VoiceOrb.swift` | 语音助手：Claude Code 流式会话、对讲机式轮流循环、状态球 |
| `AudioDevices.swift` | 麦克风来源选择 |
| `L.swift` | 界面多语言（中/英） · `Config.swift` 运行配置 |

`design/dontype-install-flow.html` 是交互式安装流程原型（演示用）。

## 后续可升级

- **流式识别**：边说边出字（whisper-server 已常驻，可做分段流式）。
- **CoreML 加速**：为 whisper encoder 开 CoreML。
- **Developer ID 公证**：换签名 + notarize，去掉首次「右键打开」。

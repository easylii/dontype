# Dontype Privacy Policy

**Publisher:** Easylii
**Apps covered:** Dontype (also distributed as 丝语 / SiYu)
**Effective date:** June 17, 2026

---

## The short version

Dontype is built to be private by default. **Your voice never leaves your Mac.** Speech is transcribed on-device. We do not run any servers that receive your audio or text, we do not have user accounts, and we do not use analytics, telemetry, tracking, advertising, or third-party data-collection SDKs. We do not collect, store, sell, or share your personal data — because the app is designed so that we never receive it in the first place.

---

## 1. What the app does with your data

**Voice capture and transcription (on-device).**
When you trigger dictation, Dontype records audio from your microphone and converts it to text **locally on your Mac**, using a local speech model (whisper.cpp running on your machine) or Apple's on-device speech recognition. The audio is held only in memory for the moment it takes to transcribe and is then discarded. Audio is never uploaded to us or to anyone else.

**Optional AI cleanup (uses your own account).**
If you enable AI cleanup, the **transcribed text** (not audio) is sent to the AI provider you have configured — Anthropic (Claude API or Claude Code) or OpenAI (Codex) — using **your own API key or subscription**. That text is handled under your account and is governed by that provider's privacy policy, not ours. Dontype does not receive, log, or store this text on any server we control. If you do not configure an AI provider, no text is sent anywhere; the raw transcription is used as-is. You can turn AI cleanup off at any time.

**Read-aloud (on-device).**
The read-aloud feature uses Apple's on-device speech synthesis to speak selected text. The text and audio stay on your Mac.

**Local files on your Mac.**
Dontype stores your settings in `~/.config/siyu/config.json` and a local diagnostic log in `~/.config/siyu/status.log`. The "recall last result" feature keeps your most recent transcription on your device so you can copy it again. All of this lives only on your Mac. None of it is transmitted to us. You can delete it at any time by removing those files or uninstalling the app.

---

## 2. macOS permissions we request, and why

- **Microphone** — to capture your voice for dictation.
- **Speech Recognition** — for Apple's on-device transcription, used as a fallback.
- **Accessibility** — to detect your start/stop hotkey and to paste the result at your cursor.

These permissions are used only for the functions described above. macOS asks for each one separately, and you can revoke any of them in System Settings at any time.

---

## 3. What we do **not** do

- We do **not** collect or store your audio or transcribed text on our servers.
- We do **not** use analytics, telemetry, crash reporting, or tracking of any kind.
- We do **not** have user accounts, logins, or profiles.
- We do **not** show ads or use advertising identifiers.
- We do **not** sell, rent, or share your data with third parties.
- We do **not** embed third-party SDKs that collect personal data.

---

## 4. Third-party services

The only third party that may receive data is the **AI provider you choose** for optional cleanup (Anthropic or OpenAI), and only because you connected it with your own credentials. Please review their policies:

- Anthropic: https://www.anthropic.com/legal/privacy
- OpenAI: https://openai.com/policies/privacy-policy

Software downloads (the app's local speech model and binaries) are fetched over the internet on first run; these are standard file downloads and do not transmit your personal data.

---

## 5. Your rights (GDPR, UK GDPR, CCPA/CPRA, and similar)

Because we do not collect or hold any personal data about you, there is nothing on our side to access, correct, export, or delete — you are already in full control of all data, which lives on your own device. You may exercise complete control at any time by deleting the local files listed above or uninstalling the app.

- We do not "sell" or "share" personal information as those terms are defined under California law (CCPA/CPRA). There is therefore nothing to opt out of.
- For data processed by your chosen AI provider, please direct any access/deletion requests to that provider, since they act as the controller of that data under your account.

If you believe you have a privacy concern about Dontype, contact us (Section 8) and we will respond.

---

## 6. Children

Dontype is not directed to children, and we do not knowingly collect any data from anyone, including children.

## 7. International users

Because nothing you say or type is transmitted to us, there is no cross-border transfer of your personal data by Dontype. One policy applies worldwide. (Any transfer that occurs when you use an AI provider is governed by that provider and your account with them.)

## 8. Changes & contact

We may update this policy as the app evolves; we will revise the "Effective date" above and, for material changes, note them in the app or release notes.

Questions or requests: **support@easylii.com**

---
---

# Dontype 隐私政策（中文）

**发行方：** Easylii
**适用应用：** Dontype（中国市场亦以「丝语 / SiYu」发行）
**生效日期：** 2026 年 6 月 17 日

---

## 一句话版本

Dontype 默认就保护隐私。**你的声音永不离开这台 Mac。** 语音在本机转写。我们没有任何会接收你音频或文字的服务器,没有用户账号,也不使用任何分析、埋点、追踪、广告或第三方数据收集 SDK。我们不收集、不存储、不出售、不共享你的个人数据——因为这个 App 从设计上就让我们根本接触不到它。

---

## 1. App 如何处理你的数据

**语音采集与转写（本机完成）。**
当你触发听写时,Dontype 从麦克风录音,并**在你的 Mac 本地**把它转成文字——使用运行在你机器上的本地语音模型(whisper.cpp)或苹果的本机语音识别。音频只在转写的那一瞬间留在内存里,随后即被丢弃。音频绝不上传给我们或任何人。

**可选的 AI 整理（用你自己的账号）。**
如果你开启 AI 整理,**转写后的文字**(不是音频)会被发送到你所配置的 AI 服务商——Anthropic(Claude API 或 Claude Code)或 OpenAI(Codex)——使用**你自己的 API key 或订阅**。这些文字在你的账号下处理,受该服务商的隐私政策约束,而非我们的。Dontype 不会在任何我们控制的服务器上接收、记录或存储这些文字。如果你没有配置 AI 服务商,则不会有任何文字被发送,直接使用原始转写。你可以随时关闭 AI 整理。

**朗读(本机完成)。**
朗读功能使用苹果本机语音合成来朗读选中的文字。文字与音频都留在你的 Mac 上。

**本机文件。**
Dontype 把你的设置存在 `~/.config/siyu/config.json`,本地诊断日志存在 `~/.config/siyu/status.log`。「调出上一次结果」功能会把你最近一次的转写留在本机,方便你再次复制。以上全部只存在于你的 Mac,不会传给我们。你可随时删除这些文件或卸载 App 来清除。

---

## 2. 我们申请的 macOS 权限及用途

- **麦克风** —— 采集你的语音用于听写。
- **语音识别** —— 用于苹果本机转写(作为兜底)。
- **辅助功能** —— 监听你的开始/结束热键,并把结果粘贴到光标处。

这些权限仅用于上述功能。macOS 会逐项询问,你可随时在「系统设置」中撤销任意一项。

---

## 3. 我们**不会**做的事

- **不**在我们的服务器上收集或存储你的音频或转写文字。
- **不**使用任何分析、埋点、崩溃上报或追踪。
- **不**设用户账号、登录或画像。
- **不**展示广告,**不**使用广告标识符。
- **不**向第三方出售、出租或共享你的数据。
- **不**嵌入收集个人数据的第三方 SDK。

---

## 4. 第三方服务

唯一可能接收数据的第三方,是你为可选整理所选择的 **AI 服务商**(Anthropic 或 OpenAI),且仅因为是你用自己的凭据连接了它。请查阅其政策:

- Anthropic：https://www.anthropic.com/legal/privacy
- OpenAI：https://openai.com/policies/privacy-policy

App 首次运行会从网络下载本地语音模型与二进制文件;这些是普通文件下载,不会传输你的个人数据。

---

## 5. 你的权利（GDPR、英国 GDPR、CCPA/CPRA 等）

由于我们不收集、不持有你的任何个人数据,我们这边没有任何东西可供你访问、更正、导出或删除——你本就完全掌控所有数据,它们都在你自己的设备上。你可随时删除上文所列本机文件或卸载 App,实现完全控制。

- 按加州法律(CCPA/CPRA)定义,我们不「出售」也不「共享」个人信息,因此没有需要你选择退出的项目。
- 对于你所选 AI 服务商处理的数据,相关访问/删除请求请直接向该服务商提出,因为在你的账号下它是该数据的控制者。

如你对 Dontype 有任何隐私方面的疑虑,请联系我们(第 8 条),我们会回复。

---

## 6. 儿童

Dontype 并非面向儿童;我们不会在知情情况下收集任何人(包括儿童)的数据。

## 7. 国际用户

由于你所说或所打的内容不会传输给我们,Dontype 不存在跨境传输你个人数据的情形。一份政策全球适用。(你使用 AI 服务商时若发生任何传输,由该服务商及你与其的账号关系约束。)

## 8. 变更与联系方式

随着 App 演进,我们可能更新本政策;届时会修改上方「生效日期」,重大变更会在 App 内或发行说明中标注。

疑问或请求:**support@easylii.com**

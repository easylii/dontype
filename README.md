# Dontype (丝语)

**English** · [中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md)

**The ultimate voice companion for vibe coding on Mac**, by **Easylii**. Western brand **Dontype** (don't type — just talk), Chinese **丝语**.

Vibe coding is *talking* to your AI, not typing it all out. Dontype makes your Mac listen: dictate prompts straight into **Claude Code, Cursor, or any field** — double-tap **Control**, talk, and it transcribes locally, strips the fillers, and pastes at your cursor; one button **sends** it. Run the whole loop **hands-free from an Apple TV remote**, and have replies **read back** to you. Everything runs on-device; your voice never leaves your Mac.

## Highlights

- **Made for vibe coding.** Talk your prompts straight into Claude Code, Cursor, ChatGPT or any text field — dictate, it removes the "um"s and fixes the grammar, pastes at the cursor, and one button **sends** it (Return). Lean back and run the whole loop from an Apple TV remote.
- **3-in-1.** Speech → text (dictation), text → speech (read any selected text aloud), and a 5-slot clipboard history — three tools in one tiny menu-bar app. Most dictation tools do just one.
- **No metered API, no extra subscription.** Recognition runs fully **local** (free, offline, no bandwidth). AI cleanup runs on the **Claude Code / Codex you already have**, via their CLI — no separate Anthropic API key and no per-token API billing. Nothing extra to pay; without either, it just outputs the raw transcription (still free).
- **5-slot clipboard history.** Every dictation result and every manual copy flows into a 5-item history (deduplicated, source-tagged) — click any to copy it back. In-memory only, sensitive clips skipped.
- **Works with the Apple TV Remote (gen 2 or 3).** Dictate hands-free from across the room with a Siri Remote: press **TV** to start talking, **TV** again to finish, **OK** to send, **Back ‹ / Esc** to cancel, swipe the **touchpad** to move the cursor, and the **arrows** act like Tab between controls. Set it up in the setup wizard's Remote page (an animated demo shows every step).
- **Talk to Claude Code, out loud** *(experimental)*. An optional voice assistant holds a walkie-talkie-style spoken conversation with Claude Code — press the remote's **side button**, talk, press again, and it reads the answer back. Online + read-only, opt-in, kept separate from the on-device core.

## How it works

```
Double-tap Control to record (tap to stop / Esc = stop without paste)
  → whisper.cpp local recognition (offline; falls back to Apple speech if no model)
  → AI cleanup (Claude API / Claude Code / Codex, auto-fallback; rewrites into fluent sentences)
  → floating result window + copy button
  → auto-paste into the field you were in
```

## Demo

**Speech → text** — double-tap Control, talk, text is pasted at your cursor:

![Speech to text demo](design/demo-stt.svg)

**Text → speech** — select text, double-tap right ⌘, a voice reads it aloud:

![Text to speech demo](design/demo-tts.svg)

**Clipboard history** — your last 5 clips (dictations + manual copies), click one to copy it back:

![Clipboard history demo](design/demo-clipboard.svg)

**Apple TV Remote (gen 2 / 3)** — press **TV** to talk, press **TV** again to type your words in at the cursor, **Back ‹ / Esc** to cancel, swipe the **touchpad** to move the mouse:

![Apple TV Remote demo](design/demo-remote.svg)

**Interactive install walkthrough** — open [`design/dontype-install-flow.html`](design/dontype-install-flow.html) in a browser for the full first-run experience (8 screens: Welcome → privacy consent → permissions → model → hotkey → read-aloud → AI → done).

> The two demos above are animated SVGs (they play in the README). For the real thing, record short GIFs of the app with `Cmd+Shift+5` → Gifski / Kap; once the repo is public you can also host the HTML walkthrough via GitHub Pages.

## Supported recognition languages

> **Key point: there are no "per-language recognition packs".** One whisper model covers ~99 languages — just set the language or use auto-detect. You never download multiple models per language.

**Auto-detect by default** (`recognitionLang: auto`) — it figures out what you're speaking, no manual choice needed. The recognition-language dropdown only lists the **featured** languages for manual locking:

| Tier | Languages | Notes |
|------|-----------|-------|
| **Featured** (in dropdown, officially supported) | English · Chinese (Mandarin) · 日本語 · 한국어 · Spanish · French | turbo ≈ full large-v3; safe to advertise |
| Works, with caveats | Cantonese · Thai · Vietnamese, etc. | turbo degrades noticeably on Cantonese/Thai → switch `whisperModel` to `large-v3`; not in the dropdown, but auto-detect still recognizes them |
| Weak (not advertised) | low-resource languages | higher error rate, hallucination-prone |

- **turbo vs large-v3**: the default `large-v3-turbo` is fast and ≈ full quality for high-resource languages; it drops on low-resource ones (notably Cantonese, Thai). Switch `whisperModel` to `large-v3` for better multilingual accuracy.
- **Interface language** (menus / wizard) is separate from recognition — currently Chinese / English, falling back to English elsewhere. Japanese / Korean UI etc. can be added gradually when a market justifies the translation work.

## Install

**Distributed install (recommended)**: `./make-dmg.sh` builds `Dontype.dmg` (bundling `install.command` / `PRIVACY.md` / install notes). To install, right-click **install.command** inside the DMG → "Open"; the script copies to `/Applications`, strips quarantine (double-click works afterward), writes a default config, and launches.

**First launch = paginated setup wizard**: Welcome → **Privacy policy (must agree to continue)** → Permissions → Model → Hotkey → Read-aloud → AI → Done. Afterward, "Settings" in the menu bar opens a **single-window settings panel** (no longer the paginated flow).

**Local development**:

```bash
cd ~/Documents/SiYu
./build-app.sh          # build + bundle + sign → SiYu.app
open SiYu.app
```

> Note: the app bundle is still named `SiYu.app` internally, but Finder / permissions / menus show the brand **Dontype** (English systems) / **丝语** (Chinese systems), via `Info.plist` + `Resources/*.lproj` localization.
> The signing certificate lives in `.cert/` (**not in the repo** — back it up separately). A fixed cert keeps Accessibility and other TCC grants valid across rebuilds.

After launch a **bubble logo** appears in the menu bar; it turns solid red while recording, solid orange while cleaning up.

## Clipboard history (up to 5)

The menu bar's "Voice input" section has a **clipboard history** — up to 5 entries, click to copy back to the clipboard:
- Two sources, marked by icon: 🌊 this app's transcriptions / 📋 things you copied manually.
- **Auto-dedup**: identical content is kept once and moved to top.
- **In-memory only, never written to disk, cleared on quit**; sensitive clipboard items flagged by password managers are **skipped**.

## Read selected text aloud (reverse)

In **any app**, select text (or place the cursor at the start) → **double-tap right ⌘** → a Premium voice reads **from there down to the end of the current text block** (offline, free). While reading: **tap right ⌘** to pause/resume, **Esc** to stop.
- Reading downward: it first tries Accessibility to get "the focused field's full text + selection position", reading from the selection start to the end of that text block; if it can't (some web pages / terminals / Electron) it falls back to **reading only the selected span**.
- Selection fallback: when Accessibility can't get the selection, it synthesizes Cmd+C, reads the clipboard, and **restores** it.
- Settings: configure voice / rate / trigger key / preview under the settings panel "⑧ Read selection aloud → Configure"; if you have no Premium voice there's an entry point to download one in System Settings.

## Apple TV Remote (gen 2 / 3)

Drive Dontype hands-free from across the room with a **Siri Remote (2nd or 3rd generation)** — no extra hardware; it pairs over Bluetooth like any Mac input device. Turn it on in the setup wizard's **⑧ Remote** page (with the animated walkthrough above); a one-time **Input Monitoring** permission lets the app read the remote's keys.

| Remote | What it does |
|--------|--------------|
| **TV** | Start talking — **press again** to finish and type the text in at your cursor |
| **Center (OK)** | **Send** — right after a dictation it presses **Return** (fires off your prompt); elsewhere activates the focused control / clicks at the cursor |
| **Back ‹ / Esc** | Cancel — stops dictation/read-aloud instantly, nothing transcribed, nothing pasted |
| **↑ / ↓** | Move up & down lists, menus and sidebars |
| **← / →** | Tab / Shift-Tab between controls (links, buttons, fields) |
| **Side button** | Toggle the **voice assistant** (walkie-talkie talk to Claude Code) |
| **Touchpad** | Glide the mouse cursor; click with the center button |

Volume, mute and play/pause keep their normal system function. Enabling the remote also switches on macOS **keyboard navigation** (Full Keyboard Access) so Tab can reach buttons, not just text fields.

> The remote's three input channels each use a different macOS API (media keys via a CGEvent tap, the special keys via IOHIDManager, the touch surface via the private MultitouchSupport framework). That last one means the app isn't App-Store-sandboxable — it's a power-user feature you toggle on the Remote page.

## Privacy

Your voice never leaves the device — zero collection, zero tracking, no accounts, no telemetry. Optional AI cleanup sends only **text** (not audio) to the Claude/Codex account **you configure yourself**. Full policy in [`PRIVACY.md`](PRIVACY.md) (bilingual, GDPR / CCPA grade). First launch has a privacy-consent gate.

## Configuration

The AI cleanup backend is auto-selected by priority: `Claude API (fastest) → Claude Code → Codex → raw passthrough`, with automatic fallback on failure. For the fastest API: set `ANTHROPIC_API_KEY`, or put `apiKey` in `~/.config/siyu/config.json`. It works without a key too: with Claude Code / Codex it uses your subscription; with none it outputs the raw transcription.

`~/.config/siyu/config.json` fields:

| Field | Meaning | Default |
|-------|---------|---------|
| `apiKey` | Anthropic API key | empty (falls back to env var) |
| `model` | model for API cleanup | `claude-haiku-4-5-20251001` |
| `cleanup` | enable AI cleanup (auto-triggers only when fillers detected) | `true` |
| `autoPaste` | auto-paste at cursor after a result | `true` |
| `whisperModel` | whisper model id (`large-v3-turbo` / `large-v3` / `medium` / `small`) | `large-v3-turbo` |
| `recognitionLang` | recognition language (`auto` / `en` / `zh` / `ja` / `ko` / `es` / `fr`) | `auto` |
| `uiLang` | interface language (`auto` / `zh` / `en`) | `auto` |
| `readKey` | read-aloud trigger key (`control`/`fn`/`rightCommand`/`rightOption`/`option`) | `rightCommand` |
| `readVoice` | read-aloud voice id (empty = auto-pick Premium by text language) | empty |
| `readRate` | read-aloud rate 0…1 | `0.5` |

## Structure

| File | Responsibility |
|------|----------------|
| `AppDelegate.swift` | menu bar, flow orchestration, clipboard history, permissions |
| `HotkeyMonitor.swift` | global double-tap modifier-key detection (CGEventTap) |
| `Dictation.swift` | recording + recognition (whisper first, Apple fallback) |
| `Whisper.swift` | whisper.cpp backend: model dir, recognition language, resident server |
| `Cleaner.swift` | AI cleanup (API / Claude Code / Codex fallback chain; rewrites into sentences) |
| `ModelDownloader.swift` | whisper model download (progress callbacks to the wizard) |
| `TextGrabber.swift` | grab selected text (Accessibility direct + Cmd+C fallback restoring clipboard) |
| `Speaker.swift` | read-aloud engine (AVSpeechSynthesizer + Premium voices, auto-pick by language) |
| `HotkeySetup.swift` / `ReadSetup.swift` | start/stop hotkey, read-aloud setup (double-tap test to confirm) |
| `Onboarding.swift` | first-run **paginated wizard** (with privacy consent) + menu **settings panel** (two modes, one class) |
| `RecallStore.swift` | clipboard history (up to 5, dedup, in-memory, skips sensitive clips) |
| `IconRenderer.swift` | menu-bar icon + mic-source icons (SVG paths drawn at runtime) |
| `HUD.swift` | floating result window / draggable pill / read-aloud waveform |
| `Paster.swift` | clipboard + synthetic Cmd+V |
| `RemoteHID.swift` | Apple TV Remote special keys (IOHIDManager, HID report id=251) → actions |
| `Multitouch.swift` | remote touch surface → mouse cursor (private MultitouchSupport, family 0x91) |
| `RemoteSetup.swift` | Remote setup / demo page (connection-aware, animated SVG walkthrough) |
| `GameControllerInput.swift` | Bluetooth gamepad input (dictation / cursor / arrows) |
| `Assistant.swift` · `VoiceLoop.swift` · `VoiceOrb.swift` | voice assistant: Claude Code stream session, walkie-talkie turn loop, status orb |
| `AudioDevices.swift` | microphone source selection |
| `L.swift` | UI localization (zh/en) · `Config.swift` runtime config |

`design/dontype-install-flow.html` is the interactive install-flow prototype (for demo).

## Roadmap

- **Streaming recognition**: text as you speak (whisper-server is already resident; can do chunked streaming).
- **CoreML acceleration**: enable CoreML for the whisper encoder.
- **Developer ID notarization**: switch signing + notarize to drop the first-run "right-click → Open".

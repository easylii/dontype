import Foundation

/// 运行配置，来自 ~/.config/siyu/config.json（可选）。
/// 没有配置文件也能跑：默认开启清洗、模式 tidy、自动粘贴、zh-CN。
/// apiKey 缺省时回退到环境变量 ANTHROPIC_API_KEY；都没有则跳过清洗、只出原始转写。
struct Config {
    var apiKey: String?
    var model: String
    var cleanup: Bool
    var cleanupBackend: String   // AI 整理后端：auto（按可用优先）/ api / claudeCode / codex
    var autoPaste: Bool
    var locale: String       // Apple 备用后端的识别 locale（如 zh-CN / en-US），仅 whisper 缺失时用
    var triggerKey: String   // 双击触发键：control / fn / rightCommand / rightOption / option
    var remoteKey: String    // 遥控器（媒体键）触发听写：off / playpause / mute / next / prev，默认 off（不抢键盘媒体键）
    var remoteMap: [String: String] // 遥控器 id=251 特殊键 → 动作：位码("d0.3")→action("dictation"/"up"…)，空=用内置默认
    var remoteEnabled: Bool  // 遥控器/手柄总开关：开=按键固定映射生效 + 触摸板移光标；关=遥控器啥也不做，默认 true
    var remoteTrackpad: Bool // 把遥控器触摸面当触控板移动鼠标（私有 MultitouchSupport，实验），默认 false
    var diagnostic: Bool     // 诊断模式：把每个键写进日志、不触发不吞（摸清遥控器各键发什么），默认 false
    var micDeviceUID: String // 手动指定麦克风 UID；空串 = 自动智能选择（盖开内置/合盖iPhone/兜底默认）
    var uiLang: String       // 界面语言：auto（跟随系统）/ zh / en
    var whisperModel: String // 识别模型 id（见 Whisper.models），默认 large-v3-turbo
    var recognitionLang: String // whisper 识别语言码：zh / en / ja / ko / auto …
    var readKey: String      // 朗读选中文字的触发键，默认 rightCommand（和说话的 control 分开）
    var assistantKey: String // 语音助手触发键（双击 = 对讲机：开/说/停发送），默认 rightOption
    var readLang: String     // 朗读主语言偏好：auto/zh/en/ja/ko/es/fr；非 auto 时该语言在文中占比够就整篇用它读
    var readVoice: String    // AVSpeechSynthesisVoice.identifier；空 = 按文字语言自动挑
    var readRate: Double     // 朗读语速 0…1，默认 0.5（AVSpeechUtteranceDefaultSpeechRate）
    var pillOffsetX: Double  // 药丸相对「屏顶中点」的水平偏移（拖动后记住）
    var pillOffsetY: Double  // 药丸相对「屏顶中点」的垂直偏移

    static let dir = (("~/.config/siyu") as NSString).expandingTildeInPath
    static let path = dir + "/config.json"

    static func load() -> Config {
        var c = Config(
            apiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
            model: "claude-haiku-4-5-20251001",
            cleanup: true,
            cleanupBackend: "auto",
            autoPaste: true,
            locale: "zh-CN",
            triggerKey: "control",
            remoteKey: "off",
            remoteMap: [:],
            remoteEnabled: true,
            remoteTrackpad: false,
            diagnostic: false,
            micDeviceUID: "",
            uiLang: "auto",
            whisperModel: "large-v3-turbo",
            recognitionLang: "auto",   // 自动检测：对所有主推语言开箱即用
            readKey: "rightCommand",
            assistantKey: "leftCommand",
            readLang: "auto",
            readVoice: "",
            readRate: 0.5,
            pillOffsetX: 0,
            pillOffsetY: 0
        )
        if let data = FileManager.default.contents(atPath: path),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let v = json["apiKey"] as? String, !v.isEmpty { c.apiKey = v }
            if let v = json["model"] as? String, !v.isEmpty { c.model = v }
            if let v = json["cleanup"] as? Bool { c.cleanup = v }
            if let v = json["cleanupBackend"] as? String, !v.isEmpty { c.cleanupBackend = v }
            if let v = json["autoPaste"] as? Bool { c.autoPaste = v }
            if let v = json["locale"] as? String, !v.isEmpty { c.locale = v }
            if let v = json["triggerKey"] as? String, !v.isEmpty { c.triggerKey = v }
            if let v = json["remoteKey"] as? String, !v.isEmpty { c.remoteKey = v }
            if let v = json["remoteMap"] as? [String: String] { c.remoteMap = v }
            if let v = json["remoteEnabled"] as? Bool { c.remoteEnabled = v }
            if let v = json["remoteTrackpad"] as? Bool { c.remoteTrackpad = v }
            if let v = json["diagnostic"] as? Bool { c.diagnostic = v }
            if let v = json["micDeviceUID"] as? String { c.micDeviceUID = v }
            if let v = json["uiLang"] as? String, !v.isEmpty { c.uiLang = v }
            if let v = json["whisperModel"] as? String, !v.isEmpty { c.whisperModel = v }
            if let v = json["recognitionLang"] as? String, !v.isEmpty { c.recognitionLang = v }
            if let v = json["readKey"] as? String, !v.isEmpty { c.readKey = v }
            if let v = json["assistantKey"] as? String, !v.isEmpty { c.assistantKey = v }
            if let v = json["readLang"] as? String, !v.isEmpty { c.readLang = v }
            if let v = json["readVoice"] as? String { c.readVoice = v }
            if let v = json["readRate"] as? Double { c.readRate = v }
            if let v = json["pillOffsetX"] as? Double { c.pillOffsetX = v }
            if let v = json["pillOffsetY"] as? Double { c.pillOffsetY = v }
        }
        return c
    }

}

import Foundation

/// 运行配置，来自 ~/.config/siyu/config.json（可选）。
/// 没有配置文件也能跑：默认开启清洗、模式 tidy、自动粘贴、zh-CN。
/// apiKey 缺省时回退到环境变量 ANTHROPIC_API_KEY；都没有则跳过清洗、只出原始转写。
struct Config {
    var apiKey: String?
    var model: String
    var cleanup: Bool
    var autoPaste: Bool
    var locale: String       // Apple 备用后端的识别 locale（如 zh-CN / en-US），仅 whisper 缺失时用
    var triggerKey: String   // 双击触发键：control / fn / rightCommand / rightOption / option
    var micDeviceUID: String // 手动指定麦克风 UID；空串 = 自动智能选择（盖开内置/合盖iPhone/兜底默认）
    var uiLang: String       // 界面语言：auto（跟随系统）/ zh / en
    var whisperModel: String // 识别模型 id（见 Whisper.models），默认 large-v3-turbo
    var recognitionLang: String // whisper 识别语言码：zh / en / ja / ko / auto …
    var readKey: String      // 朗读选中文字的触发键，默认 rightCommand（和说话的 control 分开）
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
            autoPaste: true,
            locale: "zh-CN",
            triggerKey: "control",
            micDeviceUID: "",
            uiLang: "auto",
            whisperModel: "large-v3-turbo",
            recognitionLang: "zh",
            readKey: "rightCommand",
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
            if let v = json["autoPaste"] as? Bool { c.autoPaste = v }
            if let v = json["locale"] as? String, !v.isEmpty { c.locale = v }
            if let v = json["triggerKey"] as? String, !v.isEmpty { c.triggerKey = v }
            if let v = json["micDeviceUID"] as? String { c.micDeviceUID = v }
            if let v = json["uiLang"] as? String, !v.isEmpty { c.uiLang = v }
            if let v = json["whisperModel"] as? String, !v.isEmpty { c.whisperModel = v }
            if let v = json["recognitionLang"] as? String, !v.isEmpty { c.recognitionLang = v }
            if let v = json["readKey"] as? String, !v.isEmpty { c.readKey = v }
            if let v = json["readVoice"] as? String { c.readVoice = v }
            if let v = json["readRate"] as? Double { c.readRate = v }
            if let v = json["pillOffsetX"] as? Double { c.pillOffsetX = v }
            if let v = json["pillOffsetY"] as? Double { c.pillOffsetY = v }
        }
        return c
    }

}

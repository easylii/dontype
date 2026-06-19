import AVFoundation
import NaturalLanguage

/// 朗读引擎：AVSpeechSynthesizer + 系统下载的 Premium/Enhanced 嗓音（离线、免费）。
/// 嗓音选择：先对整篇文字做一次评估，按「全篇字数占比」选出主语言，
/// 然后整篇都用这一个嗓音从头读到尾 —— 不中途切换、不以开头为准，避免穿插多国嗓音。
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()

    /// 朗读自然结束或被取消后回调（主线程）—— AppDelegate 用来收起 HUD、复位图标。
    var onFinish: (() -> Void)?

    var isSpeaking: Bool { synth.isSpeaking }
    var isPaused: Bool { synth.isPaused }

    private var pending = 0
    private var finished = true

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, voiceID: String, rate: Double) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.rate = Float(max(0, min(1, rate)))
        u.voice = Speaker.dominantVoice(text: text, preferredID: voiceID)
        finished = false
        pending = 1
        synth.speak(u)
    }

    /// 暂停 ⇄ 继续；返回切换后的「是否暂停」
    @discardableResult
    func pauseOrResume() -> Bool {
        if synth.isPaused { synth.continueSpeaking(); return false }
        if synth.isSpeaking { synth.pauseSpeaking(at: .word); return true }
        return false
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        fireFinish()
    }

    private func fireFinish() {
        guard !finished else { return }
        finished = true
        DispatchQueue.main.async { self.onFinish?() }
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        pending -= 1
        if pending <= 0 { fireFinish() }
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        fireFinish()
    }

    // MARK: 嗓音选择（整篇评估主语言）

    /// 用户指定了嗓音就用它；否则按全篇主语言挑一个最高质量的嗓音。
    static func dominantVoice(text: String, preferredID: String) -> AVSpeechSynthesisVoice? {
        if !preferredID.isEmpty, let v = AVSpeechSynthesisVoice(identifier: preferredID) { return v }
        let prefix = dominantLangPrefix(text)
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        return bestQuality(candidates) ?? AVSpeechSynthesisVoice(language: voiceLocale(for: prefix))
    }

    /// 评估整篇：按字数统计谁为主。CJK 多 → 细分中/日/韩；拉丁多 → NL 识别具体语言。
    static func dominantLangPrefix(_ text: String) -> String {
        var cjk = 0, latin = 0, han = 0, kana = 0, hangul = 0
        for u in text.unicodeScalars {
            let v = u.value
            if (0xAC00...0xD7A3).contains(v) || (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v) {
                cjk += 1; hangul += 1
            } else if (0x3040...0x30FF).contains(v) {
                cjk += 1; kana += 1
            } else if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) {
                cjk += 1; han += 1
            } else if (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0xC0...0x24F).contains(v) {
                latin += 1
            }
        }
        if cjk == 0 && latin == 0 { return "en" }

        if cjk >= latin {
            // CJK 为主，细分语种
            if hangul > han && hangul > kana { return "ko" }   // 谚文占多 → 韩
            if kana > 0 { return "ja" }                         // 出现假名 → 日（汉字不影响）
            return "zh"                                         // 否则按中文
        }
        // 拉丁为主 → 用 NL 识别 en/es/fr…（排除被误判成 CJK 的情况）
        let r = NLLanguageRecognizer()
        r.processString(text)
        if let lang = r.dominantLanguage?.rawValue,
           !lang.hasPrefix("zh"), !lang.hasPrefix("ja"), !lang.hasPrefix("ko") {
            return String(lang.prefix(2))
        }
        return "en"
    }

    /// 菜单用：可选的高质量嗓音（Premium/Enhanced），按质量、语言排序。
    static func premiumVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.quality == .premium || $0.quality == .enhanced }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue { return $0.quality.rawValue > $1.quality.rawValue }
                return $0.language < $1.language
            }
    }

    /// 菜单显示名：名字（质量）· 语言
    static func display(_ v: AVSpeechSynthesisVoice) -> String {
        let q = v.quality == .premium ? "Premium" : (v.quality == .enhanced ? "Enhanced" : "Default")
        return "\(v.name)（\(q)）· \(v.language)"
    }

    private static func bestQuality(_ voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        voices.max { $0.quality.rawValue < $1.quality.rawValue }
    }

    private static func voiceLocale(for prefix: String) -> String {
        switch prefix {
        case "zh": return "zh-CN"
        case "en": return "en-US"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        default:   return prefix
        }
    }
}

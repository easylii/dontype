import AVFoundation
import NaturalLanguage

/// 朗读引擎：AVSpeechSynthesizer + 系统下载的 Premium/Enhanced 嗓音（离线、免费）。
/// 支持暂停/继续/停止、语速；未指定嗓音时按文字语言自动挑一个尽量高质量的。
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()

    /// 朗读自然结束或被取消后回调（主线程）—— AppDelegate 用来收起 HUD、复位图标。
    var onFinish: (() -> Void)?

    var isSpeaking: Bool { synth.isSpeaking }
    var isPaused: Bool { synth.isPaused }

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, voiceID: String, rate: Double) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.rate = Float(max(0, min(1, rate)))
        u.voice = Speaker.resolveVoice(id: voiceID, text: text)
        synth.speak(u)
    }

    /// 暂停 ⇄ 继续；返回切换后的「是否暂停」
    @discardableResult
    func pauseOrResume() -> Bool {
        if synth.isPaused { synth.continueSpeaking(); return false }
        if synth.isSpeaking { synth.pauseSpeaking(at: .word); return true }
        return false
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish?() }
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish?() }
    }

    // MARK: 嗓音

    /// 指定了 id 就用它；否则按文字语言挑一个最高质量的。
    static func resolveVoice(id: String, text: String) -> AVSpeechSynthesisVoice? {
        if !id.isEmpty, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        let langPrefix = detectLangPrefix(text)
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(langPrefix) }
        return bestQuality(candidates) ?? AVSpeechSynthesisVoice(language: voiceLocale(for: langPrefix))
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

    /// 粗判文字主语言 → 嗓音 language 前缀（zh / en / ja / ko …）
    private static func detectLangPrefix(_ text: String) -> String {
        let r = NLLanguageRecognizer()
        r.processString(text)
        guard let lang = r.dominantLanguage?.rawValue else { return "en" }
        if lang.hasPrefix("zh") { return "zh" }
        return String(lang.prefix(2))
    }

    private static func voiceLocale(for prefix: String) -> String {
        switch prefix {
        case "zh": return "zh-CN"
        case "en": return "en-US"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        default: return prefix
        }
    }
}

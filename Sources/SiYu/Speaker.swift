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

    func speak(_ text: String, voiceID: String, lang: String, rate: Double) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.rate = Float(max(0, min(1, rate)))
        u.voice = Speaker.pickVoice(text: text, preferredID: voiceID, preferredLang: lang)
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

    // MARK: 嗓音选择（整篇评估 + 主语言偏好）

    private struct Counts { var han = 0, kana = 0, hangul = 0, latin = 0
        var cjk: Int { han + kana + hangul }
        var total: Int { cjk + latin } }

    /// 选嗓音优先级：① 用户指定的具体嗓音 → 永远用它；② 设了「主语言」且它在文中占比够 → 整篇用它；
    /// ③ 否则按全篇字数多数自动判。母语场景：设主语言=中文后，哪怕英文字更多，只要中文占到一定比例就整篇中文读。
    static func pickVoice(text: String, preferredID: String, preferredLang: String) -> AVSpeechSynthesisVoice? {
        if !preferredID.isEmpty, let v = AVSpeechSynthesisVoice(identifier: preferredID) { return v }
        let c = counts(text)
        if preferredLang != "auto", langShare(preferredLang, c) >= 0.10 {
            return voice(for: preferredLang)
        }
        return voice(for: dominantPrefix(c, text: text))
    }

    private static func counts(_ text: String) -> Counts {
        var c = Counts()
        for u in text.unicodeScalars {
            let v = u.value
            if (0xAC00...0xD7A3).contains(v) || (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v) { c.hangul += 1 }
            else if (0x3040...0x30FF).contains(v) { c.kana += 1 }
            else if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) { c.han += 1 }
            else if (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0xC0...0x24F).contains(v) { c.latin += 1 }
        }
        return c
    }

    /// 某语言在全文「实义字符」里的占比（0…1）。
    private static func langShare(_ prefix: String, _ c: Counts) -> Double {
        guard c.total > 0 else { return 0 }
        let n: Int
        switch prefix {
        case "zh": n = c.han
        case "ja": n = c.kana + c.han
        case "ko": n = c.hangul
        default:   n = c.latin            // en / es / fr …共用拉丁
        }
        return Double(n) / Double(c.total)
    }

    /// 没有主语言偏好时：按全篇字数多数判主语言。CJK 多 → 细分中/日/韩；拉丁多 → NL 识别。
    private static func dominantPrefix(_ c: Counts, text: String) -> String {
        if c.cjk == 0 && c.latin == 0 { return "en" }
        if c.cjk >= c.latin {
            if c.hangul > c.han && c.hangul > c.kana { return "ko" }
            if c.kana > 0 { return "ja" }
            return "zh"
        }
        let r = NLLanguageRecognizer()
        r.processString(text)
        if let lang = r.dominantLanguage?.rawValue,
           !lang.hasPrefix("zh"), !lang.hasPrefix("ja"), !lang.hasPrefix("ko") {
            return String(lang.prefix(2))
        }
        return "en"
    }

    private static func voice(for prefix: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        return bestQuality(candidates) ?? AVSpeechSynthesisVoice(language: voiceLocale(for: prefix))
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

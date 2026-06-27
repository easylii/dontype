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
    private var streamOpen = false                 // 流式：还可能有后续句子，别提前 onFinish
    private var streamVoice: AVSpeechSynthesisVoice? // 整段流用同一个嗓音，避免逐句切换

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, voiceID: String, lang: String, rate: Double) {
        synth.stopSpeaking(at: .immediate)
        let clean = Speaker.cleanForSpeech(text)
        let u = AVSpeechUtterance(string: clean)
        u.rate = Float(max(0, min(1, rate)))
        u.voice = Speaker.pickVoice(text: clean, preferredID: voiceID, preferredLang: lang)
        finished = false
        streamOpen = false
        pending = 1
        synth.speak(u)
    }

    // MARK: 流式朗读（边生成边念）—— 开一段 → 逐句 enqueue → endStream 后全部念完才 onFinish

    func beginStream() {
        synth.stopSpeaking(at: .immediate)
        finished = false; pending = 0; streamOpen = true; streamVoice = nil
    }

    func enqueue(_ text: String, voiceID: String, lang: String, rate: Double) {
        let clean = Speaker.cleanForSpeech(text)
        guard !clean.isEmpty else { return }
        if streamVoice == nil { streamVoice = Speaker.pickVoice(text: clean, preferredID: voiceID, preferredLang: lang) }
        let u = AVSpeechUtterance(string: clean)
        u.rate = Float(max(0, min(1, rate)))
        u.voice = streamVoice
        pending += 1
        synth.speak(u)
    }

    func endStream() {
        streamOpen = false
        if pending <= 0 { fireFinish() }            // 没有待念的（空回复）→ 直接结束
    }

    /// 朗读前清掉会让合成器「乱读」或啰嗦的 Markdown 标记，只留可读文字。
    /// 实测 `#` 会把 AVSpeech 读飞；反引号/星号/波浪号是噪音；链接只留文字。
    static func cleanForSpeech(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression) // [文字](url)→文字
        s = s.replacingOccurrences(of: "(?m)^[ \\t]*[#>]+[ \\t]*", with: "", options: .regularExpression)      // 行首 # 标题 / > 引用
        s = s.replacingOccurrences(of: "(?m)^[ \\t]*[-*+][ \\t]+", with: "", options: .regularExpression)       // 行首列表符
        s = s.replacingOccurrences(of: "[#*`~]", with: "", options: .regularExpression)                         // 行内 # * ` ~
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 暂停 ⇄ 继续；返回切换后的「是否暂停」
    @discardableResult
    func pauseOrResume() -> Bool {
        if synth.isPaused { synth.continueSpeaking(); return false }
        if synth.isSpeaking { synth.pauseSpeaking(at: .word); return true }
        return false
    }

    func stop() {
        streamOpen = false
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
        if pending <= 0 && !streamOpen { fireFinish() }   // 流式期间等 endStream 才收尾
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

    /// 没有主语言偏好时判主语言。按「内容量」比：CJK 每字≈一个词，拉丁按词（连续字母段）计，
    /// 比 CJK 字数 vs 拉丁词数 —— 这样「中文夹几个英文术语」不会因英文词字母多被误判成英文。
    private static func dominantPrefix(_ c: Counts, text: String) -> String {
        let latinWords = latinWordCount(text)
        if c.cjk == 0 && latinWords == 0 { return "en" }
        if c.cjk >= latinWords {
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

    /// 拉丁词数：连续字母段算一个词；撇号/连字符不断词（Let's、e-mail 各算一个）。
    private static func latinWordCount(_ text: String) -> Int {
        var words = 0, inWord = false
        for u in text.unicodeScalars {
            let v = u.value
            let isLatin = (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0xC0...0x24F).contains(v)
            if isLatin {
                if !inWord { words += 1; inWord = true }
            } else if v == 0x27 || v == 0x2019 || v == 0x2D {
                // 撇号/连字符：保持在词内，不断词
            } else {
                inWord = false
            }
        }
        return words
    }

    private static func voice(for prefix: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        return bestQuality(candidates) ?? AVSpeechSynthesisVoice(language: voiceLocale(for: prefix))
    }

    /// 朗读设置「主要语言」用：已装嗓音覆盖的语言前缀（常用的排前，其余按字母）。
    static func installedLanguagePrefixes() -> [String] {
        let installed = Set(AVSpeechSynthesisVoice.speechVoices().map { String($0.language.prefix(2)) })
        let preferred = ["zh", "en", "ja", "ko", "es", "fr"]
        return preferred.filter(installed.contains) + installed.subtracting(preferred).sorted()
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

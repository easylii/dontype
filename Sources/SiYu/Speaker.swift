import AVFoundation
import NaturalLanguage

/// 朗读引擎：AVSpeechSynthesizer + 系统下载的 Premium/Enhanced 嗓音（离线、免费）。
/// 关键：中英（中日韩）混排时按语言把文字切成多段，每段用对应语言的嗓音排队朗读，
/// 避免「英文嗓音遇到中文直接跳过」。支持暂停/继续/停止、语速。
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()

    /// 朗读自然结束或被取消后回调（主线程）—— AppDelegate 用来收起 HUD、复位图标。
    var onFinish: (() -> Void)?

    var isSpeaking: Bool { synth.isSpeaking }
    var isPaused: Bool { synth.isPaused }

    // 一次朗读可能排队多段；读完最后一段（或被停止）才回调 onFinish 一次。
    private var pending = 0
    private var finished = true

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, voiceID: String, rate: Double) {
        synth.stopSpeaking(at: .immediate)   // 调用方保证此时不在朗读，故不会有残留段
        let r = Float(max(0, min(1, rate)))
        let segs = Speaker.segments(text)
        finished = false
        pending = 0
        for seg in segs {
            let u = AVSpeechUtterance(string: seg.text)
            u.rate = r
            u.preUtteranceDelay = 0
            u.postUtteranceDelay = 0
            u.voice = Speaker.voiceFor(langPrefix: seg.langPrefix, preferredID: voiceID)
            synth.speak(u)
            pending += 1
        }
        if pending == 0 { fireFinish() }     // 没有可读内容
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
        guard !finished else { return }      // 一次朗读只回调一次
        finished = true
        DispatchQueue.main.async { self.onFinish?() }
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        pending -= 1
        if pending <= 0 { fireFinish() }     // 最后一段读完 → 结束
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        fireFinish()                          // 被停止 → 结束（finished 标志防重复）
    }

    // MARK: 按语言切段

    private enum Script { case cjk, latin, neutral }

    /// 把文字切成「同语言的连续片段」：CJK ↔ 拉丁切换处断开；数字/标点/空格归到当前段。
    /// 每段判定一个语言前缀（zh/ja/ko/en/es/fr…）。
    static func segments(_ text: String) -> [(text: String, langPrefix: String)] {
        var runs: [(String, Script)] = []
        var cur = ""
        var curScript: Script = .neutral
        for ch in text {
            let cls = script(of: ch)
            if cls == .neutral { cur.append(ch); continue }   // 标点/空格/数字跟随当前段
            if curScript == .neutral { curScript = cls }
            if cls == curScript {
                cur.append(ch)
            } else {
                if !cur.isEmpty { runs.append((cur, curScript)) }
                cur = String(ch); curScript = cls
            }
        }
        if !cur.isEmpty { runs.append((cur, curScript)) }

        return runs.compactMap { (s, sc) in
            guard !s.isEmpty else { return nil }
            let prefix: String
            switch sc {
            case .cjk:     prefix = cjkLang(s)
            case .latin:   prefix = latinLang(s)
            case .neutral: prefix = "en"      // 整段都是标点/数字：随便给个嗓音读
            }
            return (s, prefix)
        }
    }

    private static func script(of ch: Character) -> Script {
        for u in ch.unicodeScalars {
            let v = u.value
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) ||  // CJK 汉字
               (0xF900...0xFAFF).contains(v) ||                                    // 兼容汉字
               (0x3040...0x30FF).contains(v) ||                                    // 平假名/片假名
               (0xAC00...0xD7A3).contains(v) ||                                    // 谚文音节
               (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v)      // 谚文字母
            { return .cjk }
            if (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) ||           // 基本拉丁
               (0xC0...0x24F).contains(v)                                          // 带音符的拉丁
            { return .latin }
        }
        return .neutral
    }

    /// CJK 段细分：有谚文 → 韩；有假名 → 日；否则按中文。
    private static func cjkLang(_ t: String) -> String {
        for u in t.unicodeScalars {
            let v = u.value
            if (0xAC00...0xD7A3).contains(v) || (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v) { return "ko" }
            if (0x3040...0x30FF).contains(v) { return "ja" }
        }
        return "zh"
    }

    /// 拉丁段语言判定：太短不可靠就当英文；否则用 NL 识别（覆盖 en/es/fr…）。
    private static func latinLang(_ t: String) -> String {
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return "en" }
        let r = NLLanguageRecognizer()
        r.processString(trimmed)
        guard let lang = r.dominantLanguage?.rawValue else { return "en" }
        return String(lang.prefix(2))
    }

    // MARK: 嗓音

    /// 给某语言前缀挑嗓音：用户指定的嗓音若语言匹配就用它，否则挑该语言最高质量的。
    static func voiceFor(langPrefix: String, preferredID: String) -> AVSpeechSynthesisVoice? {
        if !preferredID.isEmpty, let v = AVSpeechSynthesisVoice(identifier: preferredID),
           v.language.hasPrefix(langPrefix) { return v }
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

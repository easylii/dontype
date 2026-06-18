import Foundation

/// 轻量界面多语言：调用点直接给中/英两版文案，无需维护 key 表（App 体量小，这样最不易漏译）。
/// 当前语言来自 config.uiLang（auto 跟随系统）。FileLog 等内部诊断保持中文，不走这里。
enum L {
    enum Lang { case zh, en }

    /// 当前界面语言；启动时 AppDelegate 会按 config 设定，菜单切换后也会更新。
    static var lang: Lang = .zh

    /// "auto" / "zh" / "en" → 实际语言；auto 时看系统首选语言是否中文。
    static func resolve(_ pref: String) -> Lang {
        switch pref {
        case "zh": return .zh
        case "en": return .en
        default:
            let code = (Locale.preferredLanguages.first ?? "en").lowercased()
            return code.hasPrefix("zh") ? .zh : .en
        }
    }

    static func set(_ pref: String) { lang = resolve(pref) }

    static func t(zh: String, en: String) -> String { lang == .zh ? zh : en }

    /// 界面语言菜单项：id → 显示名（随当前界面语言变化）
    static func uiLangs() -> [(id: String, label: String)] {
        [("auto", t(zh: "自动（跟随系统）", en: "Auto (system)")),
         ("zh", "中文"),
         ("en", "English")]
    }
}

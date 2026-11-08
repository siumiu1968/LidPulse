import Foundation

enum Language: String, CaseIterable, Identifiable {
    case cantonese, english
    var id: Self { self }
    var label: String { self == .english ? "English" : "繁體中文" }
    var locale: Locale { Locale(identifier: self == .english ? "en" : "zh_HK") }
    func text(_ chinese: String, _ english: String) -> String {
        self == .english ? english : chinese
    }
}

struct LocalizedNotice {
    let zh: String
    let en: String
    init(_ zh: String, _ en: String) { self.zh = zh; self.en = en }
    func text(_ language: Language) -> String { language.text(zh, en) }
}

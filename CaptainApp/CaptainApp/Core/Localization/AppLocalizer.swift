import Foundation

enum L10n {
    static func t(_ key: String) -> String {
        AppLocalizer.shared.localized(key)
    }
}

final class AppLocalizer {
    static let shared = AppLocalizer()

    private let store: [String: [String: String]]

    private init() {
        guard
            let url = Bundle.main.url(forResource: "localization", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]]
        else {
            store = [:]
            return
        }
        store = json
    }

    func localized(_ key: String) -> String {
        let languageCode = UserDefaults.standard.string(forKey: "app.language.code") ?? "ar"
        if let value = store[languageCode]?[key] {
            return value
        }
        if let fallbackArabic = store["ar"]?[key] {
            return fallbackArabic
        }
        return key
    }
}

import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable {
    case arabic = "ar"
    case english = "en"
}

@MainActor
final class AppLanguageSettings: ObservableObject {
    private static let languageKey = "app.language.code"

    @Published private(set) var language: AppLanguage

    init() {
        let savedCode = UserDefaults.standard.string(forKey: Self.languageKey)
        language = AppLanguage(rawValue: savedCode ?? "") ?? .arabic
        if savedCode == nil {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
        }
    }

    var locale: Locale {
        Locale(identifier: language.rawValue)
    }

    var layoutDirection: LayoutDirection {
        language == .arabic ? .rightToLeft : .leftToRight
    }

    func setLanguage(_ newLanguage: AppLanguage) {
        guard language != newLanguage else { return }
        language = newLanguage
        UserDefaults.standard.set(newLanguage.rawValue, forKey: Self.languageKey)
    }
}

import Foundation

/// Subset of DeepL target languages exposed in the UI. The raw value is the
/// exact code DeepL expects in the `target_lang` form field; some entries use
/// regional variants (`EN-US`, `PT-BR`) because DeepL requires them.
///
/// Display strings follow the same shape as the system's
/// `Locale.localizedString(forLanguageCode:)` output but stay hard-coded so
/// users see consistent names regardless of the host system language.
enum Language: String, CaseIterable, Identifiable, Codable {
    case englishUS = "EN-US"
    case englishUK = "EN-GB"
    case german = "DE"
    case spanish = "ES"
    case french = "FR"
    case italian = "IT"
    case dutch = "NL"
    case polish = "PL"
    case portugueseBR = "PT-BR"
    case portuguesePT = "PT-PT"
    case russian = "RU"
    case ukrainian = "UK"
    case japanese = "JA"
    case korean = "KO"
    case chineseSimplified = "ZH"
    case turkish = "TR"
    case czech = "CS"
    case danish = "DA"
    case finnish = "FI"
    case greek = "EL"
    case hungarian = "HU"
    case norwegian = "NB"
    case romanian = "RO"
    case slovak = "SK"
    case swedish = "SV"
    case bulgarian = "BG"
    case indonesian = "ID"
    case lithuanian = "LT"
    case latvian = "LV"

    var id: String { rawValue }

    /// Code expected by DeepL's `target_lang` field. Same as `rawValue` but
    /// exposed under a name that explains intent at call sites.
    var deepLCode: String { rawValue }

    /// "English (US) — EN-US" style label for the picker.
    var displayName: String {
        switch self {
        case .englishUS:         return "English (US)"
        case .englishUK:         return "English (UK)"
        case .german:            return "German"
        case .spanish:           return "Spanish"
        case .french:            return "French"
        case .italian:           return "Italian"
        case .dutch:             return "Dutch"
        case .polish:            return "Polish"
        case .portugueseBR:      return "Portuguese (Brazil)"
        case .portuguesePT:      return "Portuguese (Portugal)"
        case .russian:           return "Russian"
        case .ukrainian:         return "Ukrainian"
        case .japanese:          return "Japanese"
        case .korean:            return "Korean"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .turkish:           return "Turkish"
        case .czech:             return "Czech"
        case .danish:            return "Danish"
        case .finnish:           return "Finnish"
        case .greek:             return "Greek"
        case .hungarian:         return "Hungarian"
        case .norwegian:         return "Norwegian"
        case .romanian:          return "Romanian"
        case .slovak:            return "Slovak"
        case .swedish:           return "Swedish"
        case .bulgarian:         return "Bulgarian"
        case .indonesian:        return "Indonesian"
        case .lithuanian:        return "Lithuanian"
        case .latvian:           return "Latvian"
        }
    }

    /// Decode permissively so older shorthand codes (e.g. `EN` from a future
    /// schema or a different tool) don't crash the app on launch.
    static func from(rawCode: String) -> Language? {
        let upper = rawCode.uppercased()
        if let direct = Language(rawValue: upper) { return direct }
        // DeepL's source language detection returns plain `EN` / `PT` codes,
        // which the target enum doesn't have. Map them to the conventional
        // regional default when the user-facing UI happens to display a
        // detected-source label.
        switch upper {
        case "EN": return .englishUS
        case "PT": return .portuguesePT
        default: return nil
        }
    }
}

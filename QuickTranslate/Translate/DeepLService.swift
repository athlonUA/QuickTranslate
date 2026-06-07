import Foundation

/// Outcome of a successful DeepL call.
struct Translation: Equatable {
    /// Source text the user asked us to translate. Kept so the UI can show
    /// the original alongside the result without re-reading the clipboard.
    let source: String
    /// Translated text from DeepL.
    let translated: String
    /// Two-letter language code DeepL reports it detected. Optional because
    /// DeepL has historically returned an empty field for very short inputs.
    let detectedSourceCode: String?
    /// Target language used for the request (matches the user picker).
    let target: Language
}

/// Errors surfaced from `DeepLService.translate`. The `errorDescription`
/// strings are shown verbatim in the popover's error banner, so they're
/// phrased for end users rather than developers.
enum DeepLError: LocalizedError, Equatable {
    case missingAPIKey
    case emptyInput
    case http(status: Int, body: String?)
    case invalidResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your DeepL API key in the Settings section."
        case .emptyInput:
            return "Nothing to translate — copy text or select it on screen first."
        case .http(let status, let body):
            switch status {
            case 401, 403:
                return "DeepL rejected the API key (HTTP \(status)). Check the key in Settings."
            case 429:
                return "DeepL rate limit hit. Try again in a moment."
            case 456:
                return "DeepL quota exceeded for this billing period."
            case 500...599:
                return "DeepL is currently unavailable (HTTP \(status)). Try again shortly."
            default:
                if let body, !body.isEmpty {
                    return "DeepL returned HTTP \(status): \(body)"
                }
                return "DeepL returned HTTP \(status)."
            }
        case .invalidResponse:
            return "Unexpected response from DeepL."
        case .transport(let message):
            return "Network error: \(message)"
        }
    }
}

/// Thin async wrapper around DeepL's `/v2/translate` endpoint.
///
/// **Endpoint selection.** Free-tier API keys end with `:fx`; routing solely
/// off that suffix avoids a separate "Free vs Pro" toggle in the UI.
///
/// **Source language.** Always omitted. DeepL's auto-detection is good enough
/// for the quick-look UX and avoids forcing the user to pick a source.
///
/// The `URLSession` dependency is injectable so tests can substitute a
/// `URLProtocol`-mocked session without going to the network.
struct DeepLService {
    static let freeEndpoint = URL(string: "https://api-free.deepl.com/v2/translate")!
    static let proEndpoint = URL(string: "https://api.deepl.com/v2/translate")!

    var session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Picks the free endpoint for `:fx`-suffixed keys, otherwise pro. Marked
    /// `static` so callers (and tests) can verify routing without constructing
    /// the service.
    static func endpoint(for apiKey: String) -> URL {
        apiKey.hasSuffix(":fx") ? freeEndpoint : proEndpoint
    }

    /// Builds the request the service would send. Exposed (rather than
    /// inlined inside `translate`) so unit tests can assert on the URL,
    /// headers, and body without hitting the network.
    static func buildRequest(text: String, target: Language, apiKey: String) -> URLRequest {
        var req = URLRequest(url: endpoint(for: apiKey))
        req.httpMethod = "POST"
        req.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        // URLComponents handles percent-encoding for us, including the
        // characters DeepL is strict about (newlines, plus signs, etc.).
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "target_lang", value: target.deepLCode),
        ]
        req.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return req
    }

    /// Executes the request and parses the first translation entry. Errors map
    /// to `DeepLError` cases; the original `URLError`/`DecodingError` is not
    /// exposed because none of them are actionable to the end user.
    func translate(text: String, target: Language, apiKey: String) async throws -> Translation {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw DeepLError.missingAPIKey }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { throw DeepLError.emptyInput }

        let request = Self.buildRequest(text: trimmedText, target: target, apiKey: trimmedKey)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DeepLError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DeepLError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw DeepLError.http(status: http.statusCode, body: body)
        }

        return try Self.parse(responseData: data, source: trimmedText, target: target)
    }

    /// Static so tests can exercise the parser with a hand-built payload.
    static func parse(responseData: Data, source: String, target: Language) throws -> Translation {
        let payload: DeepLResponse
        do {
            payload = try JSONDecoder().decode(DeepLResponse.self, from: responseData)
        } catch {
            throw DeepLError.invalidResponse
        }
        guard let first = payload.translations.first else {
            throw DeepLError.invalidResponse
        }
        return Translation(
            source: source,
            translated: first.text,
            detectedSourceCode: first.detected_source_language,
            target: target
        )
    }

    // DeepL response shape; intentionally permissive — `detected_source_language`
    // can be missing for very short inputs.
    private struct DeepLResponse: Decodable {
        let translations: [Entry]
        struct Entry: Decodable {
            let detected_source_language: String?
            let text: String
        }
    }
}

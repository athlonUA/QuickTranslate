import XCTest
@testable import QuickTranslate

final class DeepLServiceTests: XCTestCase {

    // MARK: - Endpoint routing

    func test_endpoint_routesFreeKeysToFreeHost() {
        let url = DeepLService.endpoint(for: "abc123:fx")
        XCTAssertEqual(url.host, "api-free.deepl.com")
    }

    func test_endpoint_routesProKeysToProHost() {
        let url = DeepLService.endpoint(for: "abc123")
        XCTAssertEqual(url.host, "api.deepl.com")
    }

    // MARK: - Request construction

    func test_buildRequest_setsAuthorizationHeader() {
        let req = DeepLService.buildRequest(text: "hi", target: .russian, apiKey: "secret:fx")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "DeepL-Auth-Key secret:fx")
    }

    func test_buildRequest_isPOSTWithFormBody() {
        let req = DeepLService.buildRequest(text: "hi", target: .russian, apiKey: "k:fx")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func test_buildRequest_bodyIncludesTextAndTargetLang() throws {
        let req = DeepLService.buildRequest(
            text: "Hello, world!",
            target: .germanRoundTrip,
            apiKey: "k:fx"
        )
        let body = try XCTUnwrap(req.httpBody).asPercentDecodedFormDict()
        XCTAssertEqual(body["text"], "Hello, world!")
        XCTAssertEqual(body["target_lang"], "DE")
    }

    func test_buildRequest_percentEncodesSpecialCharacters() throws {
        // `+` and `&` are the two characters that break naive form encoders;
        // verify the URLComponents path handles both.
        let req = DeepLService.buildRequest(
            text: "C++ & Rust",
            target: .englishUS,
            apiKey: "k:fx"
        )
        let body = try XCTUnwrap(req.httpBody).asPercentDecodedFormDict()
        XCTAssertEqual(body["text"], "C++ & Rust")
        XCTAssertEqual(body["target_lang"], "EN-US")
    }

    func test_buildRequest_omitsSourceLangSoDeepLAutoDetects() throws {
        let req = DeepLService.buildRequest(text: "x", target: .russian, apiKey: "k:fx")
        let body = try XCTUnwrap(req.httpBody).asPercentDecodedFormDict()
        XCTAssertNil(body["source_lang"], "source language must be omitted for auto-detection")
    }

    // MARK: - Response parsing

    func test_parse_singleTranslation() throws {
        let json = """
        {"translations":[{"detected_source_language":"EN","text":"Привет"}]}
        """.data(using: .utf8)!

        let result = try DeepLService.parse(responseData: json, source: "Hello", target: .russian)
        XCTAssertEqual(result.translated, "Привет")
        XCTAssertEqual(result.detectedSourceCode, "EN")
        XCTAssertEqual(result.target, .russian)
        XCTAssertEqual(result.source, "Hello")
    }

    func test_parse_missingDetectedSource_keepsNil() throws {
        // Real-world short inputs cause DeepL to drop the detected language
        // entirely. The decoder must tolerate that without throwing.
        let json = """
        {"translations":[{"text":"a"}]}
        """.data(using: .utf8)!
        let result = try DeepLService.parse(responseData: json, source: "a", target: .englishUS)
        XCTAssertNil(result.detectedSourceCode)
        XCTAssertEqual(result.translated, "a")
    }

    func test_parse_emptyTranslationsArray_throwsInvalidResponse() {
        let json = #"{"translations":[]}"#.data(using: .utf8)!
        XCTAssertThrowsError(
            try DeepLService.parse(responseData: json, source: "x", target: .russian)
        ) { error in
            XCTAssertEqual(error as? DeepLError, .invalidResponse)
        }
    }

    func test_parse_malformedJSON_throwsInvalidResponse() {
        let bytes = Data("not json".utf8)
        XCTAssertThrowsError(
            try DeepLService.parse(responseData: bytes, source: "x", target: .russian)
        ) { error in
            XCTAssertEqual(error as? DeepLError, .invalidResponse)
        }
    }

    // MARK: - End-to-end via URLProtocol mock

    func test_translate_happyPath_returnsParsedTranslation() async throws {
        StubURLProtocol.next = .success(
            statusCode: 200,
            body: Data(#"{"translations":[{"detected_source_language":"EN","text":"привет"}]}"#.utf8)
        )

        let result = try await stubbedService().translate(
            text: "hello",
            target: .russian,
            apiKey: "k:fx"
        )
        XCTAssertEqual(result.translated, "привет")
        XCTAssertEqual(result.detectedSourceCode, "EN")
    }

    func test_translate_emptyText_throwsEmptyInput() async {
        do {
            _ = try await stubbedService().translate(
                text: "   \n  ",
                target: .russian,
                apiKey: "k:fx"
            )
            XCTFail("expected DeepLError.emptyInput")
        } catch {
            XCTAssertEqual(error as? DeepLError, .emptyInput)
        }
    }

    func test_translate_missingKey_throwsMissingAPIKey() async {
        do {
            _ = try await stubbedService().translate(
                text: "hello",
                target: .russian,
                apiKey: "   "
            )
            XCTFail("expected DeepLError.missingAPIKey")
        } catch {
            XCTAssertEqual(error as? DeepLError, .missingAPIKey)
        }
    }

    func test_translate_authError_throwsHTTP403() async {
        StubURLProtocol.next = .success(statusCode: 403, body: Data("forbidden".utf8))
        do {
            _ = try await stubbedService().translate(
                text: "hello",
                target: .russian,
                apiKey: "wrong:fx"
            )
            XCTFail("expected DeepLError.http")
        } catch let error as DeepLError {
            if case .http(let status, _) = error {
                XCTAssertEqual(status, 403)
            } else {
                XCTFail("unexpected error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_translate_transportError_throwsTransport() async {
        StubURLProtocol.next = .failure(URLError(.notConnectedToInternet))
        do {
            _ = try await stubbedService().translate(
                text: "hello",
                target: .russian,
                apiKey: "k:fx"
            )
            XCTFail("expected DeepLError.transport")
        } catch let error as DeepLError {
            if case .transport = error {
                // ok
            } else {
                XCTFail("unexpected error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func stubbedService() -> DeepLService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self] + (config.protocolClasses ?? [])
        return DeepLService(session: URLSession(configuration: config))
    }
}

// MARK: - URLProtocol stub

private final class StubURLProtocol: URLProtocol {
    enum Outcome {
        case success(statusCode: Int, body: Data)
        case failure(Error)
    }

    /// Nonisolated mutable state is fine here — tests run serially per case.
    nonisolated(unsafe) static var next: Outcome?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let outcome = StubURLProtocol.next else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        StubURLProtocol.next = nil

        switch outcome {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .success(let status, let body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

// MARK: - Convenience

private extension Data {
    /// Parses `application/x-www-form-urlencoded` bodies into `[key: value]`.
    /// Built on URLComponents so it inherits proper percent-decoding for
    /// non-ASCII characters and `+` literals.
    func asPercentDecodedFormDict() -> [String: String] {
        guard let raw = String(data: self, encoding: .utf8) else { return [:] }
        var components = URLComponents()
        components.percentEncodedQuery = raw
        var out: [String: String] = [:]
        for item in components.queryItems ?? [] {
            out[item.name] = item.value
        }
        return out
    }
}

// MARK: - Test fixtures

private extension Language {
    /// Tiny alias so the German case in tests reads more deliberate than `.german`.
    /// Picked to ensure the test still passes if `displayName` changes; we only
    /// care about the DeepL code in this branch.
    static let germanRoundTrip: Language = .german
}

import Foundation
import os

private let googleLog = Logger(subsystem: "app.ciji.mac", category: "GoogleTranslate")

struct DictionaryLookupResult: Equatable, Sendable {
    /// Always the lemma / dictionary headword stored in the DB.
    var english: String
    var phonetic: String
    var chinese: String
    var source: String
    /// Original user input when it differs from the lemma (for UI hint).
    var inputForm: String? = nil

    var wasLemmatized: Bool {
        guard let inputForm else { return false }
        return inputForm.lowercased() != english.lowercased()
    }
}

enum DictionaryServiceError: LocalizedError, Sendable {
    case emptyQuery
    case invalidURL
    case httpStatus(Int)
    case apiError(String)
    case decoding(String)
    case timeout
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .emptyQuery: return "请输入英文单词"
        case .invalidURL: return "无法创建请求地址"
        case .httpStatus(let code): return "网络错误（HTTP \(code)）"
        case .apiError(let message): return message
        case .decoding(let detail): return "解析翻译结果失败：\(detail)"
        case .timeout: return "查询超时，请检查网络后重试"
        case .emptyResult: return "未获得有效翻译结果"
        }
    }
}

/// Google Translate free endpoints + English lemmatization + phonetic enrichment.
final class GoogleTranslateService: @unchecked Sendable {
    private let allowMockFallback: Bool
    private let session: URLSession
    private let requestTimeout: TimeInterval

    init(
        allowMockFallback: Bool = true,
        session: URLSession? = nil,
        requestTimeout: TimeInterval = 12
    ) {
        self.allowMockFallback = allowMockFallback
        self.requestTimeout = requestTimeout

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = requestTimeout
            config.timeoutIntervalForResource = requestTimeout + 5
            config.waitsForConnectivity = false
            config.httpAdditionalHeaders = [
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                "Accept": "application/json,*/*",
            ]
            self.session = URLSession(configuration: config)
        }
    }

    func lookup(word: String) async throws -> DictionaryLookupResult {
        let raw = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw DictionaryServiceError.emptyQuery }

        let input = raw.lowercased()
        let lemma = EnglishLemmatizer.lemma(for: input)

        do {
            async let chineseTask = fetchChinese(for: lemma)
            async let phoneticTask = fetchPhonetic(for: lemma)
            let chinese = try await chineseTask
            let phonetic = (try? await phoneticTask) ?? ""

            guard !chinese.isEmpty else { throw DictionaryServiceError.emptyResult }

            googleLog.info(
                "Lookup ok input=\(input, privacy: .public) lemma=\(lemma, privacy: .public) phonetic=\(phonetic, privacy: .public) chinese=\(chinese, privacy: .public)"
            )

            return DictionaryLookupResult(
                english: lemma,
                phonetic: phonetic,
                chinese: chinese,
                source: "google",
                inputForm: input == lemma ? nil : input
            )
        } catch {
            if allowMockFallback, !(error is CancellationError) {
                googleLog.error(
                    "Lookup failed for \(input, privacy: .public): \(error.localizedDescription, privacy: .public) — using mock"
                )
                var mock = Self.mockResult(for: lemma)
                mock.inputForm = input == lemma ? nil : input
                return mock
            }
            throw error
        }
    }

    // MARK: - Chinese (en → zh)

    private func fetchChinese(for lemma: String) async throws -> String {
        let primary = try await fetchTranslate(
            client: "dict-chrome-ex",
            sourceLang: "en",
            targetLang: "zh-CN",
            query: lemma,
            includeDictionary: true
        )
        if !primary.chinese.isEmpty { return primary.chinese }

        let simple = try await fetchSimpleTranslation(query: lemma)
        return simple
    }

    // MARK: - Phonetic (en → en + dt=rm)

    private func fetchPhonetic(for lemma: String) async throws -> String {
        var components = URLComponents(string: "https://clients5.google.com/translate_a/single")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "dict-chrome-ex"),
            URLQueryItem(name: "sl", value: "en"),
            URLQueryItem(name: "tl", value: "en"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "dt", value: "rm"),
            URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "oe", value: "UTF-8"),
            URLQueryItem(name: "q", value: lemma),
        ]
        guard let url = components?.url else { return "" }
        let data = try await perform(url: url, query: lemma)
        return Self.extractPhonetic(from: data, query: lemma)
    }

    static func extractPhonetic(from data: Data, query: String) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let root = json as? [Any],
              let sentences = root[safe: 0] as? [Any] else { return "" }

        let phoneticChars = CharacterSet(charactersIn: "ˈˌəɪæɑɒɔʊʌɛθðŋʃʒːāēīōūǎǐǒǔɡ()")
        var found: String?

        for item in sentences {
            guard let row = item as? [Any] else { continue }
            for value in row {
                guard let text = value as? String else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if trimmed.lowercased() == query.lowercased() { continue }
                // Prefer strings that look like pronunciation / IPA-ish readings.
                if trimmed.unicodeScalars.contains(where: { phoneticChars.contains($0) })
                    || trimmed.contains("'")
                    || trimmed.contains("ˈ") {
                    found = trimmed
                    break
                }
            }
            if found != nil { break }
        }

        guard let raw = found else { return "" }
        let bare = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "/\(bare)/"
    }

    // MARK: - Network helpers

    private func fetchTranslate(
        client: String,
        sourceLang: String,
        targetLang: String,
        query: String,
        includeDictionary: Bool
    ) async throws -> GoogleTranslateParseResult {
        var components = URLComponents(string: "https://clients5.google.com/translate_a/single")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "client", value: client),
            URLQueryItem(name: "sl", value: sourceLang),
            URLQueryItem(name: "tl", value: targetLang),
            URLQueryItem(name: "hl", value: "zh-CN"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "oe", value: "UTF-8"),
            URLQueryItem(name: "q", value: query),
        ]
        if includeDictionary {
            items.append(URLQueryItem(name: "dt", value: "bd"))
            items.append(URLQueryItem(name: "dt", value: "md"))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw DictionaryServiceError.invalidURL }
        let data = try await perform(url: url, query: query)
        return try Self.parseResponse(data: data, query: query)
    }

    private func fetchSimpleTranslation(query: String) async throws -> String {
        var components = URLComponents(string: "https://clients5.google.com/translate_a/t")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "dict-chrome-ex"),
            URLQueryItem(name: "sl", value: "en"),
            URLQueryItem(name: "tl", value: "zh-CN"),
            URLQueryItem(name: "q", value: query),
        ]
        guard let url = components?.url else { throw DictionaryServiceError.invalidURL }
        let data = try await perform(url: url, query: query)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        if let arr = json as? [String] { return arr.joined() }
        if let arr = json as? [Any] { return arr.compactMap { $0 as? String }.joined() }
        return ""
    }

    private func perform(url: URL, query: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout

        googleLog.debug("GET \(url.absoluteString, privacy: .public)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw DictionaryServiceError.timeout
        } catch is CancellationError {
            throw CancellationError()
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DictionaryServiceError.httpStatus(http.statusCode)
        }

        if let raw = String(data: data, encoding: .utf8),
           raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("<!doctype")
            || raw.contains("We're sorry") {
            throw DictionaryServiceError.apiError("Google 接口暂时不可用或被限流，请稍后再试")
        }

        return data
    }

    // MARK: - Chinese parse

    struct GoogleTranslateParseResult: Equatable {
        var chinese: String
        var phonetic: String
    }

    static func parseResponse(data: Data, query: String) throws -> GoogleTranslateParseResult {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = json as? [Any] else {
            throw DictionaryServiceError.decoding("根节点不是数组")
        }

        let translation = pickTranslation(from: root)
        let dictionary = pickDictionary(from: root)

        let chinese: String
        if !dictionary.isEmpty, !translation.isEmpty, !dictionary.contains(translation) {
            chinese = "\(translation)；\(dictionary)"
        } else if !dictionary.isEmpty {
            chinese = dictionary
        } else {
            chinese = translation
        }

        return GoogleTranslateParseResult(chinese: chinese, phonetic: "")
    }

    static func pickTranslation(from root: [Any]) -> String {
        guard let sentences = root[safe: 0] as? [Any] else { return "" }
        var parts: [String] = []
        for item in sentences {
            guard let row = item as? [Any], let text = row[safe: 0] as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        return parts.joined()
    }

    static func pickDictionary(from root: [Any]) -> String {
        guard root.count > 1, let blocks = root[1] as? [Any] else { return "" }
        var lines: [String] = []
        for block in blocks {
            guard let row = block as? [Any] else { continue }
            let pos = (row[safe: 0] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let meanings = (row[safe: 1] as? [Any])?
                .compactMap { $0 as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []
            guard !meanings.isEmpty else { continue }
            let useful = meanings.filter { $0.count > 1 || meanings.count == 1 }
            guard !useful.isEmpty else { continue }
            let joined = useful.prefix(6).joined(separator: "、")
            lines.append(pos.isEmpty ? joined : "\(pos). \(joined)")
        }
        return lines.joined(separator: "；")
    }

    // MARK: - Mock

    static func mockResult(for query: String) -> DictionaryLookupResult {
        let key = EnglishLemmatizer.lemma(for: query)
        if let known = mockLexicon[key] {
            return DictionaryLookupResult(
                english: key,
                phonetic: known.0,
                chinese: known.1,
                source: "mock"
            )
        }
        return DictionaryLookupResult(
            english: key,
            phonetic: "",
            chinese: "（示例）\(key) — 网络查询失败时的本地占位释义",
            source: "mock"
        )
    }

    private static let mockLexicon: [String: (String, String)] = [
        "apple": ("/ˈæpl/", "n. 苹果"),
        "banana": ("/bəˈnɑːnə/", "n. 香蕉"),
        "cat": ("/kæt/", "n. 猫"),
        "dog": ("/dɒɡ/", "n. 狗"),
        "elegant": ("/ˈelɪɡənt/", "adj. 优雅的；高雅的"),
        "focus": ("/ˈfəʊkəs/", "n. 焦点；v. 集中"),
        "grateful": ("/ˈɡreɪtfl/", "adj. 感激的；感谢的"),
        "habit": ("/ˈhæbɪt/", "n. 习惯"),
        "improve": ("/ɪmˈpruːv/", "v. 改进；提高"),
        "journey": ("/ˈdʒɜːni/", "n. 旅行；历程"),
        "knowledge": ("/ˈnɒlɪdʒ/", "n. 知识；学问"),
        "memory": ("/ˈmeməri/", "n. 记忆；回忆"),
        "notion": ("/ˈnəʊʃn/", "n. 概念；看法"),
        "optimize": ("/ˈɒptɪmaɪz/", "v. 优化"),
        "practice": ("/ˈpræktɪs/", "n. 练习；实践 v. 练习"),
        "quiet": ("/ˈkwaɪət/", "adj. 安静的"),
        "resilient": ("/rɪˈzɪliənt/", "adj. 有弹性的；能复原的"),
        "run": ("/rʌn/", "v. 跑；运行"),
        "go": ("/ɡəʊ/", "v. 去"),
        "good": ("/ɡʊd/", "adj. 好的"),
        "study": ("/ˈstʌdi/", "v./n. 学习；研究"),
        "serene": ("/səˈriːn/", "adj. 平静的；安详的"),
        "thrive": ("/θraɪv/", "v. 繁荣；茁壮成长"),
        "vocabulary": ("/vəˈkæbjələri/", "n. 词汇；词汇量"),
    ]
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

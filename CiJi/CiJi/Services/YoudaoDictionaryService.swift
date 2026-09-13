import Foundation
import os

private let youdaoLog = Logger(subsystem: "app.ciji.mac", category: "Youdao")

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
        case .emptyQuery: return "请输入英文单词或短语"
        case .invalidURL: return "无法创建请求地址"
        case .httpStatus(let code): return "网络错误（HTTP \(code)）"
        case .apiError(let message): return message
        case .decoding(let detail): return "解析词典结果失败：\(detail)"
        case .timeout: return "查询超时，请检查网络后重试"
        case .emptyResult: return "未获得有效翻译结果"
        }
    }
}

/// Free Youdao Dictionary web API (same style as Gloss / many Mac dict tools).
/// Uses `dict.youdao.com/jsonapi` — no AppKey, no end-user cost.
final class YoudaoDictionaryService: @unchecked Sendable {
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
                "Referer": "https://www.youdao.com/",
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
            async let youdaoTask = fetchJSONAPI(for: lemma)
            async let phoneticTask = IPAPhoneticService.fetchIPA(
                for: lemma,
                session: session,
                timeout: requestTimeout
            )
            let youdao = try await youdaoTask
            let enrichedPhonetic = await phoneticTask

            let phonetic: String
            if IPAPhoneticService.isPlausibleIPA(enrichedPhonetic) {
                phonetic = enrichedPhonetic
            } else if !youdao.phonetic.isEmpty {
                phonetic = youdao.phonetic.hasPrefix("/") ? youdao.phonetic : "/\(youdao.phonetic)/"
            } else {
                phonetic = ""
            }

            guard !youdao.chinese.isEmpty else { throw DictionaryServiceError.emptyResult }

            youdaoLog.info(
                "Lookup ok input=\(input, privacy: .public) lemma=\(lemma, privacy: .public) phonetic=\(phonetic, privacy: .public) chinese=\(youdao.chinese, privacy: .public)"
            )

            return DictionaryLookupResult(
                english: lemma,
                phonetic: phonetic,
                chinese: youdao.chinese,
                source: "youdao",
                inputForm: input == lemma ? nil : input
            )
        } catch {
            if allowMockFallback, !(error is CancellationError) {
                youdaoLog.error(
                    "Lookup failed for \(input, privacy: .public): \(error.localizedDescription, privacy: .public) — using mock"
                )
                var mock = Self.mockResult(for: lemma)
                mock.inputForm = input == lemma ? nil : input
                return mock
            }
            throw error
        }
    }

    // MARK: - Network

    struct YoudaoParseResult: Equatable {
        var chinese: String
        var phonetic: String
    }

    private func fetchJSONAPI(for lemma: String) async throws -> YoudaoParseResult {
        // Prefer compact ec+fanyi payload (used widely by free Youdao clients).
        if let primary = try? await requestJSONAPI(lemma: lemma, includeAllDicts: false),
           !primary.chinese.isEmpty {
            return primary
        }
        // Broader payload as fallback.
        if let full = try? await requestJSONAPI(lemma: lemma, includeAllDicts: true),
           !full.chinese.isEmpty {
            return full
        }
        // Lightweight suggest endpoint.
        return try await requestSuggest(lemma: lemma)
    }

    private func requestJSONAPI(lemma: String, includeAllDicts: Bool) async throws -> YoudaoParseResult {
        var components = URLComponents(string: "https://dict.youdao.com/jsonapi")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: lemma),
            URLQueryItem(name: "le", value: "en"),
            URLQueryItem(name: "client", value: "macOS"),
            URLQueryItem(name: "keyfrom", value: "macdict.ciji"),
        ]
        if !includeAllDicts {
            // Request English-Chinese + machine translation blocks only.
            let dicts = #"{"count":2,"dicts":[["ec"],["fanyi"]]}"#
            items.append(URLQueryItem(name: "dicts", value: dicts))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw DictionaryServiceError.invalidURL }

        let data = try await fetchData(from: url)
        return try Self.parseJSONAPI(data: data)
    }

    private func requestSuggest(lemma: String) async throws -> YoudaoParseResult {
        var components = URLComponents(string: "https://dict.youdao.com/suggest")
        components?.queryItems = [
            URLQueryItem(name: "q", value: lemma),
            URLQueryItem(name: "num", value: "1"),
            URLQueryItem(name: "doctype", value: "json"),
        ]
        guard let url = components?.url else { throw DictionaryServiceError.invalidURL }
        let data = try await fetchData(from: url)
        return try Self.parseSuggest(data: data)
    }

    private func fetchData(from url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw DictionaryServiceError.httpStatus(http.statusCode)
            }
            return data
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw DictionaryServiceError.timeout
        }
    }

    // MARK: - Parse

    static func parseJSONAPI(data: Data) throws -> YoudaoParseResult {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = json as? [String: Any] else {
            throw DictionaryServiceError.decoding("根节点不是对象")
        }

        let chinese = pickChinese(from: root)
        let phonetic = pickPhonetic(from: root)
        if chinese.isEmpty {
            throw DictionaryServiceError.emptyResult
        }
        return YoudaoParseResult(chinese: chinese, phonetic: phonetic)
    }

    static func parseSuggest(data: Data) throws -> YoudaoParseResult {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = json as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let entries = dataObj["entries"] as? [[String: Any]],
              let first = entries.first,
              let explain = first["explain"] as? String
        else {
            throw DictionaryServiceError.emptyResult
        }
        let chinese = explain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chinese.isEmpty else { throw DictionaryServiceError.emptyResult }
        return YoudaoParseResult(chinese: chinese, phonetic: "")
    }

    static func pickChinese(from root: [String: Any]) -> String {
        // 1) English-Chinese dictionary explains
        if let ec = root["ec"] as? [String: Any],
           let words = ec["word"] as? [[String: Any]] {
            var lines: [String] = []
            for word in words {
                guard let trs = word["trs"] as? [[String: Any]] else { continue }
                for trBlock in trs {
                    if let trList = trBlock["tr"] as? [[String: Any]] {
                        for tr in trList {
                            if let text = flattenI(tr["l"]) {
                                lines.append(text)
                            }
                        }
                    }
                    // Some payloads put explains directly under trs[].tran
                    if let tran = trBlock["tran"] as? String {
                        let trimmed = tran.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { lines.append(trimmed) }
                    }
                }
            }
            let joined = uniqueJoined(lines)
            if !joined.isEmpty { return joined }
        }

        // 2) Machine translation block
        if let fanyi = root["fanyi"] as? [String: Any],
           let tran = fanyi["tran"] as? String {
            let trimmed = tran.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        // 3) Web translation first hit
        if let web = root["web_trans"] as? [String: Any],
           let list = web["web-translation"] as? [[String: Any]],
           let first = list.first,
           let trans = first["trans"] as? [[String: Any]],
           let value = trans.first?["value"] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        return ""
    }

    static func pickPhonetic(from root: [String: Any]) -> String {
        if let ec = root["ec"] as? [String: Any],
           let words = ec["word"] as? [[String: Any]],
           let first = words.first {
            for key in ["usphone", "ukphone", "phone"] {
                if let value = first[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        if let simple = root["simple"] as? [String: Any],
           let words = simple["word"] as? [[String: Any]],
           let first = words.first {
            for key in ["usphone", "ukphone"] {
                if let value = first[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        return ""
    }

    /// Flatten Youdao `l.i` which may be String or [String].
    private static func flattenI(_ value: Any?) -> String? {
        guard let l = value as? [String: Any] else { return nil }
        if let i = l["i"] as? String {
            let trimmed = i.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let arr = l["i"] as? [Any] {
            let parts = arr.compactMap { $0 as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: "；")
        }
        return nil
    }

    private static func uniqueJoined(_ lines: [String]) -> String {
        var seen = Set<String>()
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result.joined(separator: "；")
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

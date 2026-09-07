import Foundation
import CryptoKit
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
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .emptyQuery: return "请输入英文单词"
        case .invalidURL: return "无法创建请求地址"
        case .httpStatus(let code): return "网络错误（HTTP \(code)）"
        case .apiError(let message): return message
        case .decoding(let detail): return "解析翻译结果失败：\(detail)"
        case .timeout: return "查询超时，请检查网络后重试"
        case .emptyResult: return "未获得有效翻译结果"
        case .missingCredentials: return "请在设置中填写有道智云 AppKey 与应用密钥"
        }
    }
}

/// 有道智云文本翻译 API（官方）：https://openapi.youdao.com/api
final class YoudaoDictionaryService: @unchecked Sendable {
    private let appKey: String
    private let appSecret: String
    private let allowMockFallback: Bool
    private let session: URLSession
    private let requestTimeout: TimeInterval

    init(
        appKey: String,
        appSecret: String,
        allowMockFallback: Bool = true,
        session: URLSession? = nil,
        requestTimeout: TimeInterval = 12
    ) {
        self.appKey = appKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appSecret = appSecret.trimmingCharacters(in: .whitespacesAndNewlines)
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
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json",
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
            guard !appKey.isEmpty, !appSecret.isEmpty else {
                throw DictionaryServiceError.missingCredentials
            }

            async let youdaoTask = fetchYoudao(for: lemma)
            async let phoneticTask = IPAPhoneticService.fetchIPA(
                for: lemma,
                session: session,
                timeout: requestTimeout
            )
            let youdao = try await youdaoTask
            let enrichedPhonetic = (try? await phoneticTask) ?? ""

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

    private func fetchYoudao(for lemma: String) async throws -> YoudaoParseResult {
        let salt = UUID().uuidString
        let curtime = String(Int(Date().timeIntervalSince1970))
        let sign = Self.sign(
            appKey: appKey,
            query: lemma,
            salt: salt,
            curtime: curtime,
            appSecret: appSecret
        )

        guard let url = URL(string: "https://openapi.youdao.com/api") else {
            throw DictionaryServiceError.invalidURL
        }

        let formItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: lemma),
            URLQueryItem(name: "from", value: "en"),
            URLQueryItem(name: "to", value: "zh-CHS"),
            URLQueryItem(name: "appKey", value: appKey),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign),
            URLQueryItem(name: "signType", value: "v3"),
            URLQueryItem(name: "curtime", value: curtime),
        ]
        var form = URLComponents()
        form.queryItems = formItems
        guard let body = form.percentEncodedQuery?.data(using: .utf8) else {
            throw DictionaryServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw DictionaryServiceError.timeout
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DictionaryServiceError.httpStatus(http.statusCode)
        }

        return try Self.parseResponse(data: data)
    }

    // MARK: - Sign / Parse

    static func truncateInput(_ q: String) -> String {
        let chars = Array(q)
        if chars.count <= 20 { return q }
        let head = String(chars.prefix(10))
        let tail = String(chars.suffix(10))
        return "\(head)\(chars.count)\(tail)"
    }

    static func sign(appKey: String, query: String, salt: String, curtime: String, appSecret: String) -> String {
        let input = truncateInput(query)
        let raw = appKey + input + salt + curtime + appSecret
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func parseResponse(data: Data) throws -> YoudaoParseResult {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = json as? [String: Any] else {
            throw DictionaryServiceError.decoding("根节点不是对象")
        }

        let errorCode = String(describing: root["errorCode"] ?? "")
        guard errorCode == "0" else {
            throw DictionaryServiceError.apiError(Self.friendlyError(code: errorCode))
        }

        let chinese = pickChinese(from: root)
        let phonetic = pickPhonetic(from: root)
        if chinese.isEmpty {
            throw DictionaryServiceError.emptyResult
        }
        return YoudaoParseResult(chinese: chinese, phonetic: phonetic)
    }

    static func pickChinese(from root: [String: Any]) -> String {
        if let basic = root["basic"] as? [String: Any],
           let explains = basic["explains"] as? [String] {
            let lines = explains
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty {
                return lines.joined(separator: "；")
            }
        }

        if let translation = root["translation"] as? [String] {
            let joined = translation
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "；")
            if !joined.isEmpty { return joined }
        }
        return ""
    }

    static func pickPhonetic(from root: [String: Any]) -> String {
        guard let basic = root["basic"] as? [String: Any] else { return "" }
        let candidates = ["us-phonetic", "uk-phonetic", "phonetic"]
        for key in candidates {
            if let value = basic[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return ""
    }

    static func friendlyError(code: String) -> String {
        switch code {
        case "101": return "有道：缺少必填参数"
        case "102": return "有道：不支持的语言类型"
        case "103": return "有道：翻译文本过长"
        case "108": return "有道：应用ID无效，请检查 AppKey"
        case "110": return "有道：无相关服务的有效实例"
        case "111": return "有道：开发者账号无效"
        case "112": return "有道：请求服务无效"
        case "113": return "有道：查询为空"
        case "202": return "有道：签名校验失败，请检查 AppKey / 密钥"
        case "401": return "有道：账户已经欠费"
        case "411": return "有道：访问频率受限"
        default: return "有道接口错误（code \(code)）"
        }
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

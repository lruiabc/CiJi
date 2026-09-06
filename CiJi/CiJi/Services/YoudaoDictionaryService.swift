import Foundation
import CryptoKit
import os

private let youdaoLog = Logger(subsystem: "app.ciji.mac", category: "Youdao")

struct DictionaryLookupResult: Equatable, Sendable {
    var english: String
    var phonetic: String
    var chinese: String
    var source: String
}

enum DictionaryServiceError: LocalizedError, Sendable {
    case emptyQuery
    case invalidURL
    case httpStatus(Int)
    case apiError(String)
    case decoding(String)
    case missingCredentials
    case timeout

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "请输入英文单词"
        case .invalidURL:
            return "无法创建请求地址"
        case .httpStatus(let code):
            return "网络错误（HTTP \(code)）"
        case .apiError(let message):
            return message
        case .decoding(let detail):
            return "解析词典结果失败：\(detail)"
        case .missingCredentials:
            return "尚未配置有道 API Key。可在设置中填写密钥，或开启本地示例释义。"
        case .timeout:
            return "查询超时，请检查网络后重试"
        }
    }
}

/// 有道智云文本翻译/词典 API（https://openapi.youdao.com/api）
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
            self.session = URLSession(configuration: config)
        }
    }

    func lookup(word: String) async throws -> DictionaryLookupResult {
        let query = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw DictionaryServiceError.emptyQuery }

        if appKey.isEmpty || appSecret.isEmpty {
            if allowMockFallback {
                youdaoLog.info("No API key — mock result for \(query, privacy: .public)")
                return Self.mockResult(for: query)
            }
            throw DictionaryServiceError.missingCredentials
        }

        return try await lookupFromYoudao(query: query)
    }

    private func lookupFromYoudao(query: String) async throws -> DictionaryLookupResult {
        let salt = UUID().uuidString
        let curtime = String(Int(Date().timeIntervalSince1970))
        let sign = Self.sign(appKey: appKey, query: query, salt: salt, curtime: curtime, appSecret: appSecret)

        var components = URLComponents(string: "https://openapi.youdao.com/api")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "from", value: "en"),
            URLQueryItem(name: "to", value: "zh-CHS"),
            URLQueryItem(name: "appKey", value: appKey),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign),
            URLQueryItem(name: "signType", value: "v3"),
            URLQueryItem(name: "curtime", value: curtime),
        ]

        guard let url = components?.url else { throw DictionaryServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        youdaoLog.debug("Lookup start: \(query, privacy: .public)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            youdaoLog.error("Lookup timeout: \(query, privacy: .public)")
            throw DictionaryServiceError.timeout
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            youdaoLog.error("Lookup network error: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            youdaoLog.error("HTTP \(http.statusCode) for \(query, privacy: .public)")
            throw DictionaryServiceError.httpStatus(http.statusCode)
        }

        if let raw = String(data: data, encoding: .utf8) {
            let preview = raw.count > 500 ? String(raw.prefix(500)) + "…" : raw
            youdaoLog.debug("Raw response: \(preview, privacy: .public)")
        }

        let decoded: YoudaoAPIResponse
        do {
            decoded = try JSONDecoder().decode(YoudaoAPIResponse.self, from: data)
        } catch {
            youdaoLog.error("Decode failed: \(error.localizedDescription, privacy: .public)")
            throw DictionaryServiceError.decoding(error.localizedDescription)
        }

        guard decoded.errorCode == "0" else {
            let message = Self.message(forErrorCode: decoded.errorCode)
            youdaoLog.error("API errorCode=\(decoded.errorCode, privacy: .public) \(message, privacy: .public)")
            throw DictionaryServiceError.apiError(message)
        }

        // 字段优先级：词典释义 basic.explains > 翻译 translation > 网络释义 web
        let phonetic = Self.pickPhonetic(from: decoded.basic)
        let chinese = Self.pickChinese(from: decoded)

        youdaoLog.info(
            "Lookup ok \(query, privacy: .public): phonetic=\(phonetic, privacy: .public) chinese=\(chinese, privacy: .public)"
        )

        return DictionaryLookupResult(
            english: query.lowercased(),
            phonetic: phonetic,
            chinese: chinese,
            source: "youdao"
        )
    }

    /// 音标：phonetic → us-phonetic → uk-phonetic
    static func pickPhonetic(from basic: YoudaoBasic?) -> String {
        guard let basic else { return "" }
        let raw = basic.phonetic ?? basic.usPhonetic ?? basic.ukPhonetic ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let bare = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "/\(bare)/"
    }

    /// 中文：explains（词典）→ translation（翻译）→ web（网络释义）
    static func pickChinese(from response: YoudaoAPIResponse) -> String {
        if let explains = response.basic?.explains?
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty }),
           !explains.isEmpty {
            return explains.joined(separator: "；")
        }

        if let translation = response.translation?
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty }),
           !translation.isEmpty {
            return translation.joined(separator: "；")
        }

        if let web = response.web, !web.isEmpty {
            let parts = web.prefix(3).compactMap { item -> String? in
                let values = item.value
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !values.isEmpty else { return nil }
                let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
                if key.isEmpty { return values.joined(separator: "、") }
                return "\(key)：\(values.joined(separator: "、"))"
            }
            if !parts.isEmpty {
                return parts.joined(separator: "；")
            }
        }

        return ""
    }

    // MARK: - Signing (Youdao v3)

    /// q 长度 ≤20 用原文；>20 用 前10 + 长度 + 后10
    static func inputForSign(_ query: String) -> String {
        let chars = Array(query)
        if chars.count <= 20 { return query }
        return "\(String(chars.prefix(10)))\(chars.count)\(String(chars.suffix(10)))"
    }

    static func sign(appKey: String, query: String, salt: String, curtime: String, appSecret: String) -> String {
        let input = inputForSign(query)
        let raw = appKey + input + salt + curtime + appSecret
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func message(forErrorCode code: String) -> String {
        switch code {
        case "101": return "有道：缺少必填参数，请检查 API 配置"
        case "102": return "有道：不支持的语言类型"
        case "103": return "有道：翻译文本过长"
        case "108": return "有道：应用 ID 无效"
        case "110": return "有道：无相关服务的有效实例"
        case "111": return "有道：开发者账号无效"
        case "112": return "有道：请求服务无效"
        case "113": return "有道：查询为空"
        case "202": return "有道：签名校验失败，请核对 AppSecret"
        case "401": return "有道：账户已经欠费"
        case "411": return "有道：访问频率受限"
        default: return "有道接口错误（code \(code)）"
        }
    }

    // MARK: - Mock

    static func mockResult(for query: String) -> DictionaryLookupResult {
        let key = query.lowercased()
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
            phonetic: "/ˈsæmpəl/",
            chinese: "（示例）\(key) 的中文释义 — 请在设置中配置有道 API 以获取真实结果",
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
        "serene": ("/səˈriːn/", "adj. 平静的；安详的"),
        "thrive": ("/θraɪv/", "v. 繁荣；茁壮成长"),
        "vocabulary": ("/vəˈkæbjələri/", "n. 词汇；词汇量"),
    ]
}

// MARK: - API DTOs

struct YoudaoAPIResponse: Decodable, Sendable {
    let errorCode: String
    let translation: [String]?
    let basic: YoudaoBasic?
    let query: String?
    let web: [YoudaoWebItem]?

    enum CodingKeys: String, CodingKey {
        case errorCode
        case translation
        case basic
        case query
        case web
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // errorCode 可能是 "0" 或 0
        if let stringCode = try? container.decode(String.self, forKey: .errorCode) {
            errorCode = stringCode
        } else if let intCode = try? container.decode(Int.self, forKey: .errorCode) {
            errorCode = String(intCode)
        } else {
            errorCode = "-1"
        }

        translation = try container.decodeIfPresent([String].self, forKey: .translation)
        basic = try container.decodeIfPresent(YoudaoBasic.self, forKey: .basic)
        query = try container.decodeIfPresent(String.self, forKey: .query)
        web = try container.decodeIfPresent([YoudaoWebItem].self, forKey: .web)
    }

    /// 测试/预览用
    init(
        errorCode: String,
        translation: [String]? = nil,
        basic: YoudaoBasic? = nil,
        query: String? = nil,
        web: [YoudaoWebItem]? = nil
    ) {
        self.errorCode = errorCode
        self.translation = translation
        self.basic = basic
        self.query = query
        self.web = web
    }
}

struct YoudaoBasic: Decodable, Sendable {
    let phonetic: String?
    let ukPhonetic: String?
    let usPhonetic: String?
    let explains: [String]?

    enum CodingKeys: String, CodingKey {
        case phonetic
        case ukPhonetic = "uk-phonetic"
        case usPhonetic = "us-phonetic"
        case explains
    }

    init(
        phonetic: String? = nil,
        ukPhonetic: String? = nil,
        usPhonetic: String? = nil,
        explains: [String]? = nil
    ) {
        self.phonetic = phonetic
        self.ukPhonetic = ukPhonetic
        self.usPhonetic = usPhonetic
        self.explains = explains
    }
}

struct YoudaoWebItem: Decodable, Sendable {
    let key: String
    let value: [String]

    enum CodingKeys: String, CodingKey {
        case key, value
    }
}

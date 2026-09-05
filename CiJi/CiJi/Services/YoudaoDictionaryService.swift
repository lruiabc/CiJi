import Foundation
import CryptoKit

struct DictionaryLookupResult: Equatable {
    var english: String
    var phonetic: String
    var chinese: String
    var source: String
}

enum DictionaryServiceError: LocalizedError {
    case emptyQuery
    case invalidURL
    case httpStatus(Int)
    case apiError(String)
    case decoding
    case missingCredentials
    case cancelled

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
        case .decoding:
            return "解析词典结果失败"
        case .missingCredentials:
            return "尚未配置有道 API Key，已使用本地示例释义。可在设置中填写真实密钥。"
        case .cancelled:
            return "已取消"
        }
    }
}

protocol DictionaryLooking {
    func lookup(word: String) async throws -> DictionaryLookupResult
}

/// 有道智云翻译/词典 API + 无 Key 时的本地 mock。
final class YoudaoDictionaryService: DictionaryLooking, @unchecked Sendable {
    private let appKey: String
    private let appSecret: String
    private let allowMockFallback: Bool
    private let session: URLSession

    init(
        appKey: String,
        appSecret: String,
        allowMockFallback: Bool = true,
        session: URLSession = .shared
    ) {
        self.appKey = appKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appSecret = appSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        self.allowMockFallback = allowMockFallback
        self.session = session
    }

    func lookup(word: String) async throws -> DictionaryLookupResult {
        let query = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw DictionaryServiceError.emptyQuery }

        if appKey.isEmpty || appSecret.isEmpty {
            if allowMockFallback {
                return Self.mockResult(for: query)
            }
            throw DictionaryServiceError.missingCredentials
        }

        do {
            return try await lookupFromYoudao(query: query)
        } catch {
            if allowMockFallback, error is DictionaryServiceError {
                // Keep real errors when credentials exist; only mock on network/API failure if desired.
                // Prefer surfacing API errors so the user can fix keys.
                throw error
            }
            throw error
        }
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
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DictionaryServiceError.httpStatus(http.statusCode)
        }

        let decoded: YoudaoAPIResponse
        do {
            decoded = try JSONDecoder().decode(YoudaoAPIResponse.self, from: data)
        } catch {
            throw DictionaryServiceError.decoding
        }

        guard decoded.errorCode == "0" else {
            throw DictionaryServiceError.apiError(Self.message(forErrorCode: decoded.errorCode))
        }

        let phonetic = decoded.basic?.phonetic
            ?? decoded.basic?.usPhonetic
            ?? decoded.basic?.ukPhonetic
            ?? ""

        let chinese: String
        if let explains = decoded.basic?.explains, !explains.isEmpty {
            chinese = explains.joined(separator: "；")
        } else if let translation = decoded.translation, !translation.isEmpty {
            chinese = translation.joined(separator: "；")
        } else {
            chinese = ""
        }

        return DictionaryLookupResult(
            english: query.lowercased(),
            phonetic: phonetic.isEmpty ? "" : "/\(phonetic.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/",
            chinese: chinese,
            source: "youdao"
        )
    }

    // MARK: - Signing (Youdao v3)

    /// input truncation rules from Youdao docs:
    /// if q length > 20: first10 + length + last10; else q itself.
    static func inputForSign(_ query: String) -> String {
        let chars = Array(query)
        if chars.count <= 20 { return query }
        let head = String(chars.prefix(10))
        let tail = String(chars.suffix(10))
        return "\(head)\(chars.count)\(tail)"
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

private struct YoudaoAPIResponse: Decodable {
    let errorCode: String
    let translation: [String]?
    let basic: YoudaoBasic?
    let query: String?
}

private struct YoudaoBasic: Decodable {
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
}

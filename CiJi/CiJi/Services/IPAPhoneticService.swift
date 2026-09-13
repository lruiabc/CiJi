import Foundation
import os

private let ipaLog = Logger(subsystem: "app.ciji.mac", category: "IPA")

/// Fetches IPA / DJ-style phonetics (not Google romanization).
/// Primary: Free Dictionary API · Fallback: Datamuse CMU → DJ IPA.
enum IPAPhoneticService {
    /// Returns a slash-wrapped IPA string such as `/ɪnˈtenʃənəl/`, or `""`.
    static func fetchIPA(for lemma: String, session: URLSession, timeout: TimeInterval) async -> String {
        let phrase = lemma.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !phrase.isEmpty else { return "" }

        // Prefer a single lookup first (works for words and some fixed phrases).
        if let whole = await lookupSingleTokenIPA(phrase, session: session, timeout: timeout), !whole.isEmpty {
            return whole
        }

        // For multi-word phrases, fall back to per-word IPA joined with spaces.
        let tokens = phrase.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init).filter { !$0.isEmpty }
        if tokens.count > 1 {
            var parts: [String] = []
            for token in tokens {
                if let part = await lookupSingleTokenIPA(token, session: session, timeout: timeout), !part.isEmpty {
                    let bare = part.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    parts.append(bare)
                }
            }
            if !parts.isEmpty {
                return "/" + parts.joined(separator: " ") + "/"
            }
        }

        ipaLog.error("IPA unavailable for \(phrase, privacy: .public)")
        return ""
    }

    private static func lookupSingleTokenIPA(_ word: String, session: URLSession, timeout: TimeInterval) async -> String? {
        if let fromDict = try? await fetchFromFreeDictionary(word: word, session: session, timeout: min(timeout, 8)),
           !fromDict.isEmpty {
            ipaLog.info("IPA FreeDict \(word, privacy: .public)=\(fromDict, privacy: .public)")
            return fromDict
        }
        if let fromDatamuse = try? await fetchFromDatamuse(word: word, session: session, timeout: min(timeout, 8)),
           !fromDatamuse.isEmpty {
            ipaLog.info("IPA Datamuse \(word, privacy: .public)=\(fromDatamuse, privacy: .public)")
            return fromDatamuse
        }
        return nil
    }

    // MARK: - Free Dictionary (IPA text)

    static func extractFreeDictionaryIPA(from data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return ""
        }

        var candidates: [String] = []
        for entry in root {
            if let top = entry["phonetic"] as? String {
                candidates.append(top)
            }
            if let phonetics = entry["phonetics"] as? [[String: Any]] {
                for item in phonetics {
                    if let text = item["text"] as? String {
                        candidates.append(text)
                    }
                }
            }
        }

        for raw in candidates {
            let normalized = normalizeIPA(raw)
            if isPlausibleIPA(normalized) {
                return normalized
            }
        }
        return ""
    }

    private static func fetchFromFreeDictionary(word: String, session: URLSession, timeout: TimeInterval) async throws -> String {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        guard let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else {
            return ""
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return ""
        }
        return extractFreeDictionaryIPA(from: data)
    }

    // MARK: - Datamuse (CMU ARPABET → DJ IPA)

    static func extractDatamuseARPABET(from data: Data, word: String) -> String {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return ""
        }
        let target = word.lowercased()
        let row = rows.first { ($0["word"] as? String)?.lowercased() == target } ?? rows.first
        guard let tags = row?["tags"] as? [String] else { return "" }
        guard let pronTag = tags.first(where: { $0.hasPrefix("pron:") }) else { return "" }
        let arpa = String(pronTag.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        return arpabetToDJIPA(arpa)
    }

    private static func fetchFromDatamuse(word: String, session: URLSession, timeout: TimeInterval) async throws -> String {
        var components = URLComponents(string: "https://api.datamuse.com/words")
        components?.queryItems = [
            URLQueryItem(name: "sp", value: word),
            URLQueryItem(name: "md", value: "r"),
            URLQueryItem(name: "max", value: "5"),
        ]
        guard let url = components?.url else { return "" }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return ""
        }
        return extractDatamuseARPABET(from: data, word: word)
    }

    // MARK: - ARPABET → DJ IPA

    private static let vowels: Set<String> = [
        "AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY", "IH", "IY", "OW", "OY", "UH", "UW",
    ]

    /// CMU phones → DJ-style IPA (common in Chinese learner dictionaries).
    private static let phoneMap: [String: String] = [
        "AA": "ɑː", "AE": "æ", "AH": "ʌ", "AO": "ɔː", "AW": "aʊ", "AY": "aɪ",
        "B": "b", "CH": "tʃ", "D": "d", "DH": "ð", "EH": "e", "ER": "ɜː", "EY": "eɪ",
        "F": "f", "G": "ɡ", "HH": "h", "IH": "ɪ", "IY": "iː", "JH": "dʒ",
        "K": "k", "L": "l", "M": "m", "N": "n", "NG": "ŋ",
        "OW": "əʊ", "OY": "ɔɪ", "P": "p", "R": "r", "S": "s", "SH": "ʃ",
        "T": "t", "TH": "θ", "UH": "ʊ", "UW": "uː", "V": "v", "W": "w",
        "Y": "j", "Z": "z", "ZH": "ʒ",
    ]

    static func arpabetToDJIPA(_ arpa: String) -> String {
        let tokens = arpa
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return "" }

        struct Phone {
            let base: String
            let stress: Int? // 0/1/2 for vowels; nil for consonants
            let ipa: String
        }

        var phones: [Phone] = []
        phones.reserveCapacity(tokens.count)

        for token in tokens {
            var base = token.uppercased()
            var stress: Int?
            if let last = base.last, last.isNumber {
                stress = Int(String(last))
                base = String(base.dropLast())
            }

            guard var ipa = phoneMap[base] else { continue }

            if base == "AH", stress == 0 { ipa = "ə" }
            if base == "ER", stress == 0 { ipa = "ə" }
            if !vowels.contains(base) { stress = nil }

            phones.append(Phone(base: base, stress: stress, ipa: ipa))
        }

        guard !phones.isEmpty else { return "" }

        // Place ˈ / ˌ at the start of the stressed syllable onset.
        var markAt = Array(repeating: Optional<Character>.none, count: phones.count)
        for (i, phone) in phones.enumerated() {
            guard let stress = phone.stress, stress == 1 || stress == 2 else { continue }
            let mark: Character = stress == 1 ? "ˈ" : "ˌ"

            var prevVowel = i - 1
            while prevVowel >= 0, phones[prevVowel].stress == nil {
                prevVowel -= 1
            }

            let consonantCount = i - prevVowel - 1
            let onsetStart: Int
            if prevVowel < 0 {
                onsetStart = 0
            } else if consonantCount >= 2 {
                // Keep earlier consonants as coda; last consonant as onset → /ɪnˈten…/
                onsetStart = i - 1
            } else if consonantCount == 1 {
                onsetStart = i - 1
            } else {
                onsetStart = i
            }
            if markAt[onsetStart] == nil {
                markAt[onsetStart] = mark
            }
        }

        var out = ""
        for (i, phone) in phones.enumerated() {
            if let mark = markAt[i] {
                out.append(mark)
            }
            out.append(phone.ipa)
        }
        return normalizeIPA(out)
    }

    // MARK: - Normalize / validate

    static func normalizeIPA(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        // Strip wrapping brackets/slashes then re-wrap with /
        if s.hasPrefix("["), s.hasSuffix("]"), s.count >= 2 {
            s = String(s.dropFirst().dropLast())
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        return "/\(s)/"
    }

    /// Reject Google-style spell-pronunciations like `ten(t)SH(ə)nəl`.
    static func isPlausibleIPA(_ value: String) -> Bool {
        let bare = value.trimmingCharacters(in: CharacterSet(charactersIn: "/[]"))
        guard bare.count >= 1 else { return false }

        // Google romanization often mixes Latin digraphs in UPPER case (SH, TH, NG).
        if bare.range(of: #"[A-Z]{2,}"#, options: .regularExpression) != nil {
            return false
        }

        let ipaHints = CharacterSet(charactersIn: "ˈˌːɪæɑɒɔʊʌɛəθðŋʃʒɡjʔ")
        let hasIPA = bare.unicodeScalars.contains { ipaHints.contains($0) }
        let mostlyLatin = bare.unicodeScalars.filter { $0.isASCII && CharacterSet.letters.contains($0) }.count
        // Accept if it has IPA symbols, or short pure-ASCII like /run/ is rare — require IPA hints.
        if hasIPA { return true }
        // Allow simple cases like /kæt/ with æ already covered; without hints reject long ASCII.
        return mostlyLatin <= 3 && bare.count <= 6
    }
}

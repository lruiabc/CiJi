import Foundation

/// Flexible Chinese-answer checking for vocabulary drills.
enum QuizAnswerMatcher {
    struct Judgment: Equatable {
        var isCorrect: Bool
        var matchedSense: String?
    }

    static func isCorrect(answer: String, expected: String) -> Bool {
        judge(answer: answer, expected: expected).isCorrect
    }

    static func judge(answer: String, expected: String) -> Judgment {
        let user = normalize(answer)
        guard !user.isEmpty else {
            return Judgment(isCorrect: false, matchedSense: nil)
        }

        let senseList = senses(from: expected)
        for sense in senseList {
            if user == sense {
                return Judgment(isCorrect: true, matchedSense: sense)
            }
            if sense.count >= 2, user.count >= 2, sense.contains(user) || user.contains(sense) {
                return Judgment(isCorrect: true, matchedSense: sense)
            }
        }

        let whole = normalize(expected)
        if !whole.isEmpty {
            if user == whole || (whole.count >= 2 && (whole.contains(user) || user.contains(whole))) {
                return Judgment(isCorrect: true, matchedSense: whole)
            }
        }
        return Judgment(isCorrect: false, matchedSense: nil)
    }

    static func senses(from expected: String) -> [String] {
        let stripped = stripPartOfSpeech(expected)
        let parts = stripped
            .components(separatedBy: CharacterSet(charactersIn: "；;、，,/|"))
            .map { normalize($0) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var result: [String] = []
        for part in parts where seen.insert(part).inserted {
            result.append(part)
        }
        return result
    }

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = stripPartOfSpeech(s)
        let removal = CharacterSet(charactersIn: " \t\n\r　·•．.。!！?？\"“”'‘’（）()【】[]《》<>~～-—_/\\")
        s = String(s.unicodeScalars.filter { !removal.contains($0) }.map(Character.init))
        return s.lowercased()
    }

    static func stripPartOfSpeech(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^(?i)(n|v|vt|vi|adj|adv|prep|conj|pron|num|art|int|aux|modal|phr|pl)\.?\s+"#,
            #"^(名词|动词|形容词|副词|介词|连词|代词|数词|感叹词|助动词)[.:：、\s]*"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

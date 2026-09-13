import Foundation

/// Lightweight English lemmatizer for vocabulary learning (not full NLP).
/// Converts common inflected forms to a dictionary headword / lemma.
enum EnglishLemmatizer {
    static func lemma(for raw: String) -> String {
        let word = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !word.isEmpty else { return word }

        // Keep hyphenated / multi-token phrases as-is (e.g. "ice cream")
        if word.contains(" ") || word.contains("-") {
            return word
        }

        if let irregular = irregulars[word] {
            return irregular
        }

        // Try suffix reductions and pick the first plausible candidate.
        for candidate in candidates(from: word) where candidate != word {
            if candidate.count >= 2 {
                return candidate
            }
        }
        return word
    }

    /// Ordered unique candidates: original first, then stemmed forms.
    static func candidates(from raw: String) -> [String] {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !word.isEmpty else { return [] }

        var list: [String] = []
        func push(_ s: String) {
            guard s.count >= 2, !list.contains(s) else { return }
            list.append(s)
        }

        push(word)
        if let irregular = irregulars[word] {
            push(irregular)
        }

        // nouns / verbs ending in -ies → -y
        if word.hasSuffix("ies"), word.count > 4 {
            push(String(word.dropLast(3)) + "y")
        }
        // -ves → -f / -fe
        if word.hasSuffix("ves"), word.count > 4 {
            let stem = String(word.dropLast(3))
            push(stem + "f")
            push(stem + "fe")
        }
        // -ses/-xes/-zes/-ches/-shes → drop es
        for suf in ["ses", "xes", "zes", "ches", "shes"] {
            if word.hasSuffix(suf), word.count > suf.count + 1 {
                push(String(word.dropLast(2))) // drop "es"
            }
        }
        // regular plural -s
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 3 {
            push(String(word.dropLast()))
        }
        // -ied → -y
        if word.hasSuffix("ied"), word.count > 4 {
            push(String(word.dropLast(3)) + "y")
        }
        // -ed
        if word.hasSuffix("ed"), word.count > 4 {
            let noEd = String(word.dropLast(2))
            push(noEd)
            push(noEd + "e")
            // stopped → stop
            if noEd.count >= 2, noEd.last == noEd.dropLast().last, "bcdfghjklmnpqrstvwxz".contains(noEd.last!) {
                push(String(noEd.dropLast()))
            }
        }
        // -ing
        if word.hasSuffix("ing"), word.count > 5 {
            let noIng = String(word.dropLast(3))
            push(noIng)
            push(noIng + "e")
            if noIng.count >= 2, noIng.last == noIng.dropLast().last, "bcdfghjklmnpqrstvwxz".contains(noIng.last!) {
                push(String(noIng.dropLast()))
            }
        }
        // comparative / superlative
        if word.hasSuffix("est"), word.count > 4 {
            let stem = String(word.dropLast(3))
            push(stem)
            push(stem + "e")
        }
        if word.hasSuffix("er"), word.count > 4, !["her", "over", "under", "after", "other", "water"].contains(word) {
            let stem = String(word.dropLast(2))
            push(stem)
            push(stem + "e")
        }
        // -ly adverb → adjective (ordered from specific → general)
        // Never do a bare drop of "ly" alone for "-bly" (humbly → humb is wrong; need humble).
        if word.hasSuffix("ly"), word.count > 4, !lyHeadwords.contains(word) {
            if word.hasSuffix("ily"), word.count > 5 {
                // happily → happy, easily → easy
                push(String(word.dropLast(3)) + "y")
            } else if word.hasSuffix("bly"), word.count > 5 {
                // humbly → humble, possibly → possible, terribly → terrible
                push(String(word.dropLast(1)) + "e")
            } else if word.hasSuffix("mply"), word.count > 5 {
                // simply → simple (supply/apply are in lyHeadwords)
                push(String(word.dropLast(1)) + "e")
            } else if word.hasSuffix("uly"), word.count > 5 {
                // truly → true, duly → due
                push(String(word.dropLast(2)) + "e")
            } else {
                // quickly → quick, slowly → slow, nicely → nice
                let stem = String(word.dropLast(2))
                push(stem)
                if stem.count >= 3, !stem.hasSuffix("e") {
                    push(stem + "e")
                }
            }
        }

        return list
    }

    /// Words that end in "ly" but are already dictionary headwords (not adverb inflections).
    private static let lyHeadwords: Set<String> = [
        "family", "assembly", "supply", "apply", "reply", "imply", "comply", "multiply",
        "only", "early", "weekly", "monthly", "yearly", "daily", "hourly",
        "lovely", "lonely", "likely", "ugly", "silly", "holy", "jolly", "deadly", "lively",
        "friendly", "costly", "elderly", "scholarly",
        "italy", "lily", "jelly", "belly", "alley", "valley", "volley", "trolley", "pulley",
        "butterfly", "dragonfly", "firefly", "melancholy", "anomaly",
    ]

    /// Common irregular verbs / plurals for vocabulary apps.
    /// Built from pairs (last write wins) so a duplicate key never crashes at launch.
    private static let irregulars: [String: String] = makeIrregulars()

    private static func makeIrregulars() -> [String: String] {
        let pairs: [(String, String)] = [
            // be
            ("am", "be"), ("is", "be"), ("are", "be"), ("was", "be"), ("were", "be"), ("been", "be"), ("being", "be"),
            // have / do / go
            ("has", "have"), ("had", "have"), ("having", "have"),
            ("does", "do"), ("did", "do"), ("done", "do"), ("doing", "do"),
            ("goes", "go"), ("went", "go"), ("gone", "go"), ("going", "go"),
            // common verbs
            ("ran", "run"), ("runs", "run"), ("running", "run"),
            ("ate", "eat"), ("eats", "eat"), ("eaten", "eat"), ("eating", "eat"),
            ("took", "take"), ("takes", "take"), ("taken", "take"), ("taking", "take"),
            ("came", "come"), ("comes", "come"), ("coming", "come"),
            ("saw", "see"), ("sees", "see"), ("seen", "see"), ("seeing", "see"),
            ("made", "make"), ("makes", "make"), ("making", "make"),
            ("got", "get"), ("gets", "get"), ("getting", "get"), ("gotten", "get"),
            ("gave", "give"), ("gives", "give"), ("given", "give"), ("giving", "give"),
            ("knew", "know"), ("knows", "know"), ("known", "know"), ("knowing", "know"),
            ("thought", "think"), ("thinks", "think"), ("thinking", "think"),
            ("said", "say"), ("says", "say"), ("saying", "say"),
            ("told", "tell"), ("tells", "tell"), ("telling", "tell"),
            ("became", "become"), ("becomes", "become"), ("becoming", "become"),
            ("began", "begin"), ("begins", "begin"), ("begun", "begin"), ("beginning", "begin"),
            ("broke", "break"), ("breaks", "break"), ("broken", "break"), ("breaking", "break"),
            ("brought", "bring"), ("brings", "bring"), ("bringing", "bring"),
            ("built", "build"), ("builds", "build"), ("building", "build"),
            ("bought", "buy"), ("buys", "buy"), ("buying", "buy"),
            ("caught", "catch"), ("catches", "catch"), ("catching", "catch"),
            ("chose", "choose"), ("chooses", "choose"), ("chosen", "choose"), ("choosing", "choose"),
            ("drew", "draw"), ("draws", "draw"), ("drawn", "draw"), ("drawing", "draw"),
            ("drank", "drink"), ("drinks", "drink"), ("drunk", "drink"), ("drinking", "drink"),
            ("drove", "drive"), ("drives", "drive"), ("driven", "drive"), ("driving", "drive"),
            ("fell", "fall"), ("falls", "fall"), ("fallen", "fall"), ("falling", "fall"),
            ("felt", "feel"), ("feels", "feel"), ("feeling", "feel"),
            ("found", "find"), ("finds", "find"), ("finding", "find"),
            ("flew", "fly"), ("flies", "fly"), ("flown", "fly"), ("flying", "fly"),
            ("forgot", "forget"), ("forgets", "forget"), ("forgotten", "forget"), ("forgetting", "forget"),
            ("froze", "freeze"), ("freezes", "freeze"), ("frozen", "freeze"), ("freezing", "freeze"),
            ("grew", "grow"), ("grows", "grow"), ("grown", "grow"), ("growing", "grow"),
            ("hid", "hide"), ("hides", "hide"), ("hidden", "hide"), ("hiding", "hide"),
            ("hit", "hit"), ("hits", "hit"), ("hitting", "hit"),
            ("kept", "keep"), ("keeps", "keep"), ("keeping", "keep"),
            // "leaves" → "leaf" (irregular plural); verb leave uses "left" / "leaving"
            ("left", "leave"), ("leaving", "leave"),
            ("lent", "lend"), ("lends", "lend"), ("lending", "lend"),
            ("lost", "lose"), ("loses", "lose"), ("losing", "lose"),
            ("meant", "mean"), ("means", "mean"), ("meaning", "mean"),
            ("met", "meet"), ("meets", "meet"), ("meeting", "meet"),
            ("paid", "pay"), ("pays", "pay"), ("paying", "pay"),
            ("put", "put"), ("puts", "put"), ("putting", "put"),
            ("read", "read"), ("reads", "read"), ("reading", "read"),
            ("rode", "ride"), ("rides", "ride"), ("ridden", "ride"), ("riding", "ride"),
            ("rang", "ring"), ("rings", "ring"), ("rung", "ring"), ("ringing", "ring"),
            ("rose", "rise"), ("rises", "rise"), ("risen", "rise"), ("rising", "rise"),
            ("sang", "sing"), ("sings", "sing"), ("sung", "sing"), ("singing", "sing"),
            ("sank", "sink"), ("sinks", "sink"), ("sunk", "sink"), ("sinking", "sink"),
            ("sat", "sit"), ("sits", "sit"), ("sitting", "sit"),
            ("slept", "sleep"), ("sleeps", "sleep"), ("sleeping", "sleep"),
            ("spoke", "speak"), ("speaks", "speak"), ("spoken", "speak"), ("speaking", "speak"),
            ("spent", "spend"), ("spends", "spend"), ("spending", "spend"),
            ("stood", "stand"), ("stands", "stand"), ("standing", "stand"),
            ("stole", "steal"), ("steals", "steal"), ("stolen", "steal"), ("stealing", "steal"),
            ("swam", "swim"), ("swims", "swim"), ("swum", "swim"), ("swimming", "swim"),
            ("taught", "teach"), ("teaches", "teach"), ("teaching", "teach"),
            ("threw", "throw"), ("throws", "throw"), ("thrown", "throw"), ("throwing", "throw"),
            ("understood", "understand"), ("understands", "understand"), ("understanding", "understand"),
            ("woke", "wake"), ("wakes", "wake"), ("woken", "wake"), ("waking", "wake"),
            ("wore", "wear"), ("wears", "wear"), ("worn", "wear"), ("wearing", "wear"),
            ("won", "win"), ("wins", "win"), ("winning", "win"),
            ("wrote", "write"), ("writes", "write"), ("written", "write"), ("writing", "write"),
            // -ly adverbs that need a vowel restored (not a bare strip of "ly")
            ("humbly", "humble"), ("simply", "simple"), ("gently", "gentle"),
            ("subtly", "subtle"), ("nobly", "noble"), ("idly", "idle"),
            ("truly", "true"), ("duly", "due"), ("wholly", "whole"),
            ("possibly", "possible"), ("probably", "probable"), ("terribly", "terrible"),
            // adjectives
            ("better", "good"), ("best", "good"),
            ("worse", "bad"), ("worst", "bad"),
            ("more", "much"), ("most", "much"),
            ("less", "little"), ("least", "little"),
            // nouns
            ("men", "man"), ("women", "woman"), ("children", "child"), ("people", "person"),
            ("teeth", "tooth"), ("feet", "foot"), ("mice", "mouse"), ("geese", "goose"),
            ("leaves", "leaf"), ("knives", "knife"), ("wives", "wife"), ("lives", "life"),
            ("potatoes", "potato"), ("tomatoes", "tomato"),
        ]

        var dict: [String: String] = [:]
        dict.reserveCapacity(pairs.count)
        for (form, lemma) in pairs {
            dict[form] = lemma
        }
        return dict
    }
}

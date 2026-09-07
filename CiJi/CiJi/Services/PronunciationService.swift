import Foundation
import AVFoundation
import Combine
import os

private let speechLog = Logger(subsystem: "app.ciji.mac", category: "Pronunciation")

enum PronunciationAccent: String, CaseIterable, Identifiable {
    case us
    case uk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .us: return "美音"
        case .uk: return "英音"
        }
    }

    var googleTL: String {
        switch self {
        case .us: return "en"
        case .uk: return "en-GB"
        }
    }

    var avLanguage: String {
        switch self {
        case .us: return "en-US"
        case .uk: return "en-GB"
        }
    }
}

@MainActor
final class PronunciationService: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var playingWord: String?
    @Published var lastError: String?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private let synthesizer = AVSpeechSynthesizer()
    private var speechDelegate: SpeechDelegate?

    func play(word: String, preferUS: Bool) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        play(word: trimmed, accent: preferUS ? .us : .uk)
    }

    func play(word: String, accent: PronunciationAccent) {
        lastError = nil
        stop()

        // Prefer Youdao dictvoice (same free web source as lookup); fall back to system speech.
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word
        let type = accent == .us ? "2" : "1"
        let urlString = "https://dict.youdao.com/dictvoice?audio=\(encoded)&type=\(type)"
        guard let url = URL(string: urlString) else {
            speakLocally(word: word, accent: accent)
            return
        }

        speechLog.debug("Play Youdao voice \(word, privacy: .public)")

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        playingWord = word.lowercased()
        isPlaying = true

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.playingWord = nil
            }
        }

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                if item.status == .failed {
                    speechLog.error("Youdao voice failed — falling back to AVSpeech")
                    self?.stopPlayerOnly()
                    self?.speakLocally(word: word, accent: accent)
                }
            }
        }

        newPlayer.play()
    }

    func toggle(word: String, preferUS: Bool) {
        if isPlaying, playingWord == word.lowercased() {
            stop()
        } else {
            play(word: word, preferUS: preferUS)
        }
    }

    func stop() {
        stopPlayerOnly()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speechDelegate = nil
        isPlaying = false
        playingWord = nil
    }

    func isPlaying(_ word: String) -> Bool {
        isPlaying && playingWord == word.lowercased()
    }

    private func stopPlayerOnly() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        player = nil
    }

    private func speakLocally(word: String, accent: PronunciationAccent) {
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: accent.avLanguage)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        let delegate = SpeechDelegate { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
                self?.playingWord = nil
                self?.speechDelegate = nil
            }
        }
        speechDelegate = delegate
        synthesizer.delegate = delegate

        playingWord = word.lowercased()
        isPlaying = true
        synthesizer.speak(utterance)
    }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
}

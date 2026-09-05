import Foundation
import AVFoundation
import Combine

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

    /// 有道 dictvoice：1=美音，2=英音
    var youdaoType: String {
        switch self {
        case .us: return "1"
        case .uk: return "2"
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

    func play(word: String, preferUS: Bool) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let accent: PronunciationAccent = preferUS ? .us : .uk
        play(word: trimmed, accent: accent)
    }

    func play(word: String, accent: PronunciationAccent) {
        lastError = nil
        stop()

        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word
        guard let url = URL(string: "https://dict.youdao.com/dictvoice?audio=\(encoded)&type=\(accent.youdaoType)") else {
            lastError = "无法创建发音地址"
            return
        }

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
                    self?.lastError = item.error?.localizedDescription ?? "发音加载失败"
                    self?.isPlaying = false
                    self?.playingWord = nil
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
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        player = nil
        isPlaying = false
        playingWord = nil
    }

    func isPlaying(_ word: String) -> Bool {
        isPlaying && playingWord == word.lowercased()
    }
}

import SwiftUI

/// 可点击的发音按钮：播放有道词典真人发音（美音/英音由设置决定）。
struct SpeakButton: View {
    let word: String
    var size: CGFloat = 14
    var helpText: String = "播放发音"

    @EnvironmentObject private var pronunciation: PronunciationService
    @EnvironmentObject private var settings: SettingsStore

    private var active: Bool {
        pronunciation.isPlaying(word)
    }

    var body: some View {
        Button {
            pronunciation.toggle(word: word, preferUS: settings.preferUSAccent)
        } label: {
            Image(systemName: active ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .frame(width: size + 10, height: size + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
        .disabled(word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

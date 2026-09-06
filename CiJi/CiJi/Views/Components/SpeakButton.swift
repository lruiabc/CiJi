import SwiftUI

/// Clickable pronunciation button. Prefer passing services explicitly so sheets
/// on macOS cannot crash from a missing `environmentObject`.
struct SpeakButton: View {
    let word: String
    var size: CGFloat = 14
    var helpText: String = "播放发音"

    @ObservedObject var pronunciation: PronunciationService
    @ObservedObject var settings: SettingsStore

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

/// Convenience for views that already hold both services in the environment.
struct SpeakButtonEnv: View {
    let word: String
    var size: CGFloat = 14
    var helpText: String = "播放发音"

    @EnvironmentObject private var pronunciation: PronunciationService
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        SpeakButton(
            word: word,
            size: size,
            helpText: helpText,
            pronunciation: pronunciation,
            settings: settings
        )
    }
}

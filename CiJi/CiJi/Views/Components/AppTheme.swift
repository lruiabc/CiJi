import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Visual language for 词笺 — bright paper + soft jade (light-first).
enum AppTheme {
    static let brandName = "词笺"
    static let brandSubtitle = "英语词库 · 听写练习"

    /// Soft ink for primary text
    static let ink = Color(red: 0.20, green: 0.33, blue: 0.36)
    /// Fresh jade accent
    static let jade = Color(red: 0.22, green: 0.62, blue: 0.54)
    /// Bright paper / mist fills
    static let mist = Color(red: 0.97, green: 0.98, blue: 0.97)
    /// Soft coral for wrong/error emphasis (not loud red)
    static let coral = Color(red: 0.82, green: 0.38, blue: 0.34)
    /// Pure panel surface
    static let paper = Color(red: 1.0, green: 1.0, blue: 0.995)
    /// Subtle wash behind the window
    static let canvas = Color(red: 0.94, green: 0.97, blue: 0.96)

    static var brandTitleFont: Font {
        .system(.title2, design: .serif).weight(.semibold)
    }

    static var brandHeroFont: Font {
        .system(.largeTitle, design: .serif).weight(.bold)
    }

    static var sectionFont: Font {
        .system(.headline, design: .default).weight(.semibold)
    }

    static var wordFont: Font {
        .system(.body, design: .rounded).weight(.semibold)
    }

    static var phoneticFont: Font {
        .system(.callout, design: .monospaced)
    }
}

/// Soft atmospheric background used behind main panels.
struct AppAtmosphereBackground: View {
    var body: some View {
        ZStack {
            AppTheme.canvas
            LinearGradient(
                colors: [
                    Color.white.opacity(0.85),
                    AppTheme.mist.opacity(0.35),
                    AppTheme.jade.opacity(0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

}

struct BrandMark: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.jade.opacity(0.92), AppTheme.jade.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: compact ? 26 : 32, height: compact ? 26 : 32)
                Image(systemName: "bookmark.fill")
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(AppTheme.brandName)
                    .font(compact ? .headline.weight(.semibold) : AppTheme.brandTitleFont)
                    .foregroundStyle(AppTheme.ink)
                if !compact {
                    Text(AppTheme.brandSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppTheme.brandName)
    }
}

struct SoftPanelStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .font(AppTheme.sectionFont)
                .foregroundStyle(AppTheme.ink)
            configuration.content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.paper.opacity(0.94))
                .shadow(color: AppTheme.ink.opacity(0.05), radius: 10, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppTheme.jade.opacity(0.16), lineWidth: 1)
        )
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.jade.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

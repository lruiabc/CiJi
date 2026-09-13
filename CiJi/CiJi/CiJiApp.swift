import SwiftUI
import SwiftData
import AppKit

/// Single-window Mac behavior for App Review Guideline 4:
/// quit when the last window closes; Dock reopen is handled by the system / Window scene.
final class CiJiAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct CiJiApp: App {
    @NSApplicationDelegateAdaptor(CiJiAppDelegate.self) private var appDelegate
    @StateObject private var settings = SettingsStore()
    @StateObject private var pronunciation = PronunciationService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Word.self,
            WordGroup.self,
            PracticeRecord.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Early-dev schema changes (e.g. Word.group → Word.groups) may invalidate the store.
            // Recreate once so the app can launch; local data from the old schema is cleared.
            let url = configuration.url
            try? FileManager.default.removeItem(at: url)
            let storeDir = url.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: storeDir.appendingPathComponent(url.lastPathComponent + "-shm"))
            try? FileManager.default.removeItem(at: storeDir.appendingPathComponent(url.lastPathComponent + "-wal"))
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        // Unique single window: macOS lists it under Window so it can be reopened after close.
        Window("词笺", id: "main") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(pronunciation)
                .preferredColorScheme(.light)
                .frame(minWidth: 960, minHeight: 620)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            OpenMainWindowCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(pronunciation)
                .preferredColorScheme(.light)
                .frame(width: 440, height: 320)
        }
    }
}

/// Explicit Window-menu action so the main UI can be restored after the user closes it.
private struct OpenMainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("词笺") {
                openWindow(id: "main")
            }
            .keyboardShortcut("0", modifiers: [.command])
        }
    }
}

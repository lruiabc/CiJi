import SwiftUI
import SwiftData

@main
struct CiJiApp: App {
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
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(pronunciation)
                .frame(minWidth: 960, minHeight: 620)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(pronunciation)
                .frame(width: 520, height: 380)
        }
    }
}

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
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
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
                .frame(width: 440, height: 320)
        }
    }
}

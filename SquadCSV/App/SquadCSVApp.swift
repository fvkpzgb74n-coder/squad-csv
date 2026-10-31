import SwiftUI

@main
struct SquadCSVApp: App {
    @State private var store = SquadStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}

struct ContentView: View {
    @Environment(SquadStore.self) private var store

    var body: some View {
        TabView {
            LineupListView()
                .tabItem { Label("Lineups", systemImage: "sportscourt") }
            SquadListView()
                .tabItem { Label("Squad", systemImage: "person.3") }
        }
        .tint(.green)
        .onChange(of: store.players) { store.save() }
        .onChange(of: store.lineups) { store.save() }
    }
}

#Preview {
    ContentView()
        .environment(SquadStore.preview())
}

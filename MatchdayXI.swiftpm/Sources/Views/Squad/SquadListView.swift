import SwiftUI
import UniformTypeIdentifiers

struct SquadListView: View {
    @Environment(SquadStore.self) private var store
    @Environment(ProStore.self) private var pro
    @State private var isShowingPaywall = false

    @State private var editingPlayer: Player?
    @State private var isAddingPlayer = false
    @State private var searchText = ""

    @State private var isImporting = false
    @State private var isExporting = false
    @State private var pendingImport: [Player]?
    @State private var isChoosingImportMode = false
    @State private var message: String?

    private var filteredPlayers: [Player] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let players = store.players.sorted { lhs, rhs in
            switch (lhs.number, rhs.number) {
            case let (l?, r?) where l != r: l < r
            case (.some, nil): true
            case (nil, .some): false
            default: lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
        guard !query.isEmpty else { return players }
        return players.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.positionsText.localizedCaseInsensitiveContains(query)
                || $0.number.map(String.init) == query
        }
    }

    private struct PlayerSection: Identifiable {
        let title: String
        let players: [Player]
        var id: String { title }
    }

    private var sections: [PlayerSection] {
        let players = filteredPlayers
        var result = PositionGroup.allCases.map { group in
            PlayerSection(title: group.title, players: players.filter { $0.primaryPosition?.group == group })
        }
        result.append(PlayerSection(title: "No Position", players: players.filter { $0.primaryPosition == nil }))
        return result.filter { !$0.players.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.players.isEmpty {
                    emptyState
                } else {
                    squadList
                }
            }
            .navigationTitle("Squad")
            .toolbar { toolbar }
            .sheet(isPresented: $isShowingPaywall) {
                ProPaywallView(reason: "The free version holds up to \(ProStore.freePlayerLimit) players. Upgrade for an unlimited squad.")
                    .environment(pro)
            }
            .sheet(isPresented: $isAddingPlayer) {
                PlayerEditView(player: nil)
                    .environment(store)
            }
            .sheet(item: $editingPlayer) { player in
                PlayerEditView(player: player)
                    .environment(store)
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text]
            ) { result in
                handleImport(result)
            }
            .fileExporter(
                isPresented: $isExporting,
                document: CSVDocument(text: SquadCSV.export(store.players)),
                contentType: .commaSeparatedText,
                defaultFilename: "squad"
            ) { result in
                if case .failure(let error) = result {
                    message = "Export failed: \(error.localizedDescription)"
                }
            }
            .confirmationDialog(
                "Import \(pendingImport?.count ?? 0) players",
                isPresented: $isChoosingImportMode,
                titleVisibility: .visible
            ) {
                Button("Merge with Current Squad") { finishImport(replace: false) }
                Button("Replace Current Squad", role: .destructive) { finishImport(replace: true) }
                Button("Cancel", role: .cancel) { pendingImport = nil }
            } message: {
                Text("Merging updates players with matching names and adds everyone else. Replacing removes current players from saved lineups.")
            }
            .alert(
                message ?? "",
                isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
            ) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var squadList: some View {
        List {
            Section {
                SquadSummary(players: store.players)
            }
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.players) { player in
                        Button {
                            editingPlayer = player
                        } label: {
                            PlayerRow(player: player)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                if let index = store.players.firstIndex(where: { $0.id == player.id }) {
                                    store.players[index].isAvailable.toggle()
                                }
                            } label: {
                                if player.isAvailable {
                                    Label("Unavailable", systemImage: "cross.case")
                                } else {
                                    Label("Available", systemImage: "checkmark.circle")
                                }
                            }
                            .tint(player.isAvailable ? .orange : .green)
                        }
                    }
                    .onDelete { offsets in
                        store.deletePlayers(Set(offsets.map { section.players[$0].id }))
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Name, number or position")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Players Yet", systemImage: "person.3")
        } description: {
            Text("Add players one by one, or import your squad from a CSV file with Name, Number and Positions columns.")
        } actions: {
            Button("Add Player") { isAddingPlayer = true }
                .buttonStyle(.borderedProminent)
            Button("Import CSV") { isImporting = true }
                .buttonStyle(.bordered)
            Button("Load Sample Squad") { loadSampleSquad() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if pro.canAddPlayer(currentCount: store.players.count) {
                    isAddingPlayer = true
                } else {
                    isShowingPaywall = true
                }
            } label: {
                Label("Add Player", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button("Import CSV…", systemImage: "square.and.arrow.down") { isImporting = true }
                Button("Export CSV…", systemImage: "square.and.arrow.up") { isExporting = true }
                    .disabled(store.players.isEmpty)
                Divider()
                Button("Load Sample Squad", systemImage: "person.3.sequence") { loadSampleSquad() }
                Divider()
                Button(pro.isPro ? "Pro (Unlocked)" : "Upgrade to Pro…", systemImage: "crown") {
                    isShowingPaywall = true
                }
            } label: {
                Label("CSV", systemImage: "tablecells")
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let text = try CSVDocument.readText(at: url)
            let players = try SquadCSV.importPlayers(from: text)
            if store.players.isEmpty {
                pendingImport = players
                finishImport(replace: true)
            } else {
                pendingImport = players
                isChoosingImportMode = true
            }
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }

    /// Squad size after an import, counting merged players with existing names only once.
    private func squadSize(afterImporting players: [Player], replace: Bool) -> Int {
        if replace { return players.count }
        let newPlayers = players.filter { player in
            !store.players.contains { $0.name.caseInsensitiveCompare(player.name) == .orderedSame }
        }
        return store.players.count + newPlayers.count
    }

    private func loadSampleSquad() {
        if pro.canHavePlayers(squadSize(afterImporting: Player.sampleSquad, replace: false)) {
            store.loadSampleSquad()
        } else {
            isShowingPaywall = true
        }
    }

    private func finishImport(replace: Bool) {
        guard let players = pendingImport else { return }
        pendingImport = nil
        guard pro.canHavePlayers(squadSize(afterImporting: players, replace: replace)) else {
            isShowingPaywall = true
            return
        }
        let result = store.importPlayers(players, replace: replace)
        if replace {
            message = "Imported \(result.added) players."
        } else {
            message = "Added \(result.added) and updated \(result.updated) players."
        }
    }
}

private struct SquadSummary: View {
    let players: [Player]

    var body: some View {
        HStack {
            stat("\(players.count)", "Players")
            Divider()
            stat("\(players.filter(\.isAvailable).count)", "Available")
            Divider()
            stat("\(players.filter { $0.primaryPosition == .gk }.count)", "Keepers")
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    SquadListView()
        .environment(SquadStore.preview())
        .environment(ProStore())
}

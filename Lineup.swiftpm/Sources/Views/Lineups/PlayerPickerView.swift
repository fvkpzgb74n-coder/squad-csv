import SwiftUI

/// Chooses a player for a pitch position, or toggles players on the bench.
struct PlayerPickerView: View {
    @Binding var lineup: Lineup
    let target: PickerTarget

    @Environment(SquadStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var slotIndex: Int? {
        if case .slot(let index) = target, lineup.slots.indices.contains(index) { return index }
        return nil
    }

    private var role: Position? {
        slotIndex.map { lineup.slots[$0].role }
    }

    private var currentPlayer: Player? {
        guard let slotIndex, let id = lineup.slots[slotIndex].playerID else { return nil }
        return store.playersByID[id]
    }

    private var candidates: [Player] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return store.players
            .filter { $0.id != currentPlayer?.id }
            .filter {
                query.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(query)
                    || $0.number.map(String.init) == query
            }
            .sorted(by: rank)
    }

    /// Available, unselected players first; then by shirt number.
    private func rank(_ lhs: Player, _ rhs: Player) -> Bool {
        func score(_ player: Player) -> Int {
            var score = 0
            if !player.isAvailable { score += 4 }
            if target != .bench, lineup.isSelected(player.id) { score += 2 }
            return score
        }
        let (l, r) = (score(lhs), score(rhs))
        if l != r { return l < r }
        return (lhs.number ?? .max, lhs.name) < (rhs.number ?? .max, rhs.name)
    }

    private var suggested: [Player] {
        guard let role else { return [] }
        return candidates.filter { $0.positions.contains(role) }
    }

    private var others: [Player] {
        guard let role else { return candidates }
        return candidates.filter { !$0.positions.contains(role) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let slotIndex, let currentPlayer {
                    Section {
                        PlayerRow(player: currentPlayer)
                        Button {
                            lineup.toggleCaptain(currentPlayer.id)
                        } label: {
                            Label(
                                lineup.captainID == currentPlayer.id ? "Remove Captaincy" : "Make Captain",
                                systemImage: "c.circle"
                            )
                        }
                        Button {
                            lineup.toggleBench(currentPlayer.id)
                            dismiss()
                        } label: {
                            Label("Move to Bench", systemImage: "arrow.down.circle")
                        }
                        Button(role: .destructive) {
                            lineup.clearSlot(slotIndex)
                            dismiss()
                        } label: {
                            Label("Remove from Lineup", systemImage: "person.badge.minus")
                        }
                    } header: {
                        Text("Currently Playing")
                    }
                }

                if store.players.isEmpty {
                    ContentUnavailableView(
                        "No Players",
                        systemImage: "person.3",
                        description: Text("Add players in the Squad tab first.")
                    )
                }

                if !suggested.isEmpty, let role {
                    Section("Plays \(role.name)") {
                        rows(suggested)
                    }
                }
                if !others.isEmpty {
                    Section(role == nil ? "Squad" : "Other Players") {
                        rows(others)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search squad")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var title: String {
        if let role { return role.name }
        return "Substitutes (\(lineup.bench.count))"
    }

    private func rows(_ players: [Player]) -> some View {
        ForEach(players) { player in
            Button {
                select(player)
            } label: {
                HStack {
                    PlayerRow(player: player, status: lineup.status(of: player.id))
                    if target == .bench {
                        Image(systemName: lineup.bench.contains(player.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(lineup.bench.contains(player.id) ? Color.green : Color.secondary)
                    }
                }
            }
        }
    }

    private func select(_ player: Player) {
        switch target {
        case .slot(let index):
            lineup.assign(player.id, toSlot: index)
            dismiss()
        case .bench:
            lineup.toggleBench(player.id)
        }
    }
}

struct LineupDetailsView: View {
    @Binding var lineup: Lineup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Match") {
                    TextField("Lineup name", text: $lineup.name)
                    TextField("Opponent", text: $lineup.opponent)
                    DatePicker("Date", selection: $lineup.date, displayedComponents: [.date, .hourAndMinute])
                }
                Section("Notes") {
                    TextField("Tactics, set pieces, reminders…", text: $lineup.notes, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .navigationTitle("Match Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

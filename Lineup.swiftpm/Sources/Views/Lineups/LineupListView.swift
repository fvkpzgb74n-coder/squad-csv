import SwiftUI

struct LineupListView: View {
    @Environment(SquadStore.self) private var store
    @Environment(ProStore.self) private var pro
    @State private var isCreating = false
    @State private var isShowingPaywall = false

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Group {
                if store.lineups.isEmpty {
                    ContentUnavailableView {
                        Label("No Lineups", systemImage: "sportscourt")
                    } description: {
                        Text(store.players.isEmpty
                             ? "Add your squad first, then build a lineup for your next match."
                             : "Create a lineup to pick your starting team and substitutes.")
                    } actions: {
                        Button("New Lineup") { newLineup() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach($store.lineups) { $lineup in
                            NavigationLink {
                                LineupEditorView(lineup: $lineup)
                            } label: {
                                LineupRow(lineup: lineup)
                            }
                            .contextMenu {
                                Button("Duplicate", systemImage: "plus.square.on.square") {
                                    if pro.canAddLineup(currentCount: store.lineups.count) {
                                        store.duplicateLineup(lineup)
                                    } else {
                                        isShowingPaywall = true
                                    }
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    store.lineups.removeAll { $0.id == lineup.id }
                                }
                            }
                        }
                        .onDelete { store.lineups.remove(atOffsets: $0) }
                        .onMove { store.lineups.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
            }
            .navigationTitle("Lineups")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newLineup()
                    } label: {
                        Label("New Lineup", systemImage: "plus")
                    }
                }
                ToolbarItemGroup(placement: .topBarLeading) {
                    if !store.lineups.isEmpty {
                        EditButton()
                    }
                    Button {
                        isShowingPaywall = true
                    } label: {
                        Label("Lineup Pro", systemImage: pro.isPro ? "crown.fill" : "crown")
                    }
                    .tint(.yellow)
                }
            }
            .sheet(isPresented: $isCreating) {
                NewLineupView()
            }
            .sheet(isPresented: $isShowingPaywall) {
                ProPaywallView(reason: pro.isPro ? nil : "The free version holds up to \(ProStore.freeLineupLimit) lineups. Upgrade for unlimited lineups and Match Day mode.")
            }
        }
    }

    private func newLineup() {
        if pro.canAddLineup(currentCount: store.lineups.count) {
            isCreating = true
        } else {
            isShowingPaywall = true
        }
    }
}

private struct LineupRow: View {
    let lineup: Lineup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lineup.name)
                .font(.headline)
            HStack(spacing: 6) {
                Text(lineup.formationName)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2), in: Capsule())
                if !lineup.opponent.isEmpty {
                    Text("vs \(lineup.opponent)")
                }
                Text(lineup.date, format: .dateTime.day().month(.abbreviated))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            let total = lineup.slots.count
            HStack(spacing: 8) {
                ProgressView(value: Double(lineup.filledCount), total: Double(max(total, 1)))
                    .tint(lineup.filledCount == total ? .green : .orange)
                Text("\(lineup.filledCount)/\(total) · \(lineup.bench.count) subs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

struct NewLineupView: View {
    @Environment(SquadStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var opponent = ""
    @State private var date = Date()
    @State private var formationID = Formation.default.id
    @State private var autoFill = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Match") {
                    TextField("Lineup name", text: $name, prompt: Text("e.g. Saturday League"))
                    TextField("Opponent", text: $opponent)
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
                Section("Formation") {
                    Picker("Formation", selection: $formationID) {
                        ForEach(Formation.groupedBySize) { group in
                            Section(group.title) {
                                ForEach(group.formations) { formation in
                                    Text(formation.name).tag(formation.id)
                                }
                            }
                        }
                    }
                    if let formation = Formation.with(id: formationID) {
                        FormationPreview(formation: formation)
                            .frame(maxWidth: 180)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                }
                if !store.players.isEmpty {
                    Section {
                        Toggle("Auto-pick from squad", isOn: $autoFill)
                    } footer: {
                        Text("Fills each position with an available player who plays there. You can change anyone afterwards.")
                    }
                }
            }
            .navigationTitle("New Lineup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                }
            }
        }
    }

    private func create() {
        let formation = Formation.with(id: formationID) ?? .default
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let opponentName = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = opponentName.isEmpty ? "Lineup \(store.lineups.count + 1)" : "vs \(opponentName)"
        var lineup = Lineup(
            name: trimmed.isEmpty ? fallbackName : trimmed,
            opponent: opponentName,
            date: date,
            formation: formation
        )
        if autoFill && !store.players.isEmpty {
            lineup.autoFill(with: store.players)
            lineup.fillBench(with: store.players)
        }
        store.lineups.insert(lineup, at: 0)
        dismiss()
    }
}

/// A small, non-interactive diagram of a formation.
struct FormationPreview: View {
    let formation: Formation

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PitchBackground()
                ForEach(Array(formation.slots.enumerated()), id: \.offset) { _, slot in
                    Circle()
                        .fill(slot.role.group.color)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .frame(width: 14, height: 14)
                        .position(x: slot.x * geometry.size.width, y: slot.y * geometry.size.height)
                }
            }
        }
        .aspectRatio(PitchView.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("\(formation.name) formation")
    }
}

#Preview {
    LineupListView()
        .environment(SquadStore.preview())
        .environment(ProStore())
}

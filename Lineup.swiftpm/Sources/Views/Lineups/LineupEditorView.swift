import SwiftUI

enum PickerTarget: Identifiable, Hashable {
    case slot(Int)
    case bench

    var id: String {
        switch self {
        case .slot(let index): "slot-\(index)"
        case .bench: "bench"
        }
    }
}

struct LineupEditorView: View {
    @Binding var lineup: Lineup
    @Environment(SquadStore.self) private var store

    @State private var pickerTarget: PickerTarget?
    @State private var isEditingDetails = false
    @State private var shareImage: Image?

    private struct ShareKey: Equatable {
        let lineup: Lineup
        let players: [Player]
    }

    var body: some View {
        let playersByID = store.playersByID

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                PitchView(lineup: $lineup, playersByID: playersByID) { index in
                    pickerTarget = .slot(index)
                }
                // Keep the pitch a sensible size on iPad.
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)

                Text("Tap a position to choose a player. Drag players to fine-tune where they stand.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                benchSection(playersByID)

                notSelectedSection

                if !lineup.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.headline)
                        Text(lineup.notes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding()
        }
        .navigationTitle(lineup.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $pickerTarget) { target in
            PlayerPickerView(lineup: $lineup, target: target)
        }
        .sheet(isPresented: $isEditingDetails) {
            LineupDetailsView(lineup: $lineup)
        }
        .task(id: ShareKey(lineup: lineup, players: store.players)) {
            shareImage = renderShareImage()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Menu {
                ForEach(Formation.groupedBySize) { group in
                    Section(group.title) {
                        ForEach(group.formations) { formation in
                            Button {
                                withAnimation { lineup.apply(formation) }
                            } label: {
                                if formation.id == lineup.formationID {
                                    Label(formation.name, systemImage: "checkmark")
                                } else {
                                    Text(formation.name)
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(lineup.formationName)
                        .font(.title3.weight(.bold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.green.opacity(0.15), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 2) {
                if !lineup.opponent.isEmpty {
                    Text("vs \(lineup.opponent)").font(.subheadline.weight(.semibold))
                }
                Text(lineup.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(lineup.filledCount)/\(lineup.slots.count)")
                    .font(.headline.monospacedDigit())
                Text("starting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func benchSection(_ playersByID: [UUID: Player]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Substitutes")
                    .font(.headline)
                Text("\(lineup.bench.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    pickerTarget = .bench
                } label: {
                    Label("Edit Bench", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if lineup.bench.isEmpty {
                Text("No substitutes picked yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(lineup.bench, id: \.self) { id in
                            if let player = playersByID[id] {
                                BenchChip(player: player)
                                    .contextMenu { benchMenu(for: player) }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func benchMenu(for player: Player) -> some View {
        Menu("Bring On For…") {
            ForEach(Array(lineup.slots.enumerated()), id: \.element.id) { index, slot in
                let current = slot.playerID.flatMap { store.playersByID[$0] }
                Button("\(slot.role.rawValue) – \(current?.name ?? "Empty")") {
                    withAnimation { lineup.assign(player.id, toSlot: index) }
                }
            }
        }
        Button("Remove from Bench", systemImage: "minus.circle", role: .destructive) {
            withAnimation { lineup.remove(player.id) }
        }
    }

    @ViewBuilder
    private var notSelectedSection: some View {
        let unselected = store.players.filter { !lineup.isSelected($0.id) }
        if !unselected.isEmpty {
            DisclosureGroup {
                VStack(spacing: 0) {
                    ForEach(unselected) { player in
                        HStack {
                            PlayerRow(player: player)
                            Button {
                                withAnimation { lineup.toggleBench(player.id) }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                            }
                            .accessibilityLabel("Add \(player.name) to bench")
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("Not Selected (\(unselected.count))")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    subject: Text(lineup.name),
                    message: Text(LineupText.make(lineup, playersByID: store.playersByID)),
                    preview: SharePreview(lineup.name, image: shareImage)
                )
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Auto-Fill Empty Positions", systemImage: "wand.and.stars") {
                    withAnimation { lineup.autoFill(with: store.players) }
                }
                Button("Add Remaining Players to Bench", systemImage: "person.3.sequence") {
                    withAnimation { lineup.fillBench(with: store.players) }
                }
                Button("Reset Positions", systemImage: "arrow.counterclockwise") {
                    withAnimation { lineup.resetPositions() }
                }
                Button("Copy as Text", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = LineupText.make(lineup, playersByID: store.playersByID)
                }
                Button("Edit Match Details", systemImage: "pencil") {
                    isEditingDetails = true
                }
                Divider()
                Button("Clear Lineup", systemImage: "trash", role: .destructive) {
                    withAnimation { lineup.clearAll() }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Sharing

    @MainActor
    private func renderShareImage() -> Image? {
        let card = LineupShareCard(lineup: lineup, playersByID: store.playersByID)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}

private struct BenchChip: View {
    let player: Player

    var body: some View {
        VStack(spacing: 4) {
            PlayerBadge(player: player, size: 40)
            Text(player.shortName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Text(player.primaryPosition?.rawValue ?? "–")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 72)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Plain-text team sheet, used when sharing or copying a lineup.
enum LineupText {
    static func make(_ lineup: Lineup, playersByID: [UUID: Player]) -> String {
        func describe(_ id: UUID) -> String {
            guard let player = playersByID[id] else { return "?" }
            let number = player.number.map { "\($0). " } ?? ""
            let captain = id == lineup.captainID ? " (C)" : ""
            return "\(number)\(player.name)\(captain)"
        }

        var lines = [lineup.name]
        if !lineup.opponent.isEmpty { lines.append("vs \(lineup.opponent)") }
        lines.append(lineup.date.formatted(date: .abbreviated, time: .shortened))
        lines.append("")
        lines.append("Formation: \(lineup.formationName)")
        // List from the goalkeeper upwards, left to right.
        let ordered = lineup.slots.sorted { $0.y != $1.y ? $0.y > $1.y : $0.x < $1.x }
        for slot in ordered {
            lines.append("\(slot.role.rawValue)  \(slot.playerID.map(describe) ?? "—")")
        }
        if !lineup.bench.isEmpty {
            lines.append("")
            lines.append("Subs: " + lineup.bench.map(describe).joined(separator: ", "))
        }
        if !lineup.notes.isEmpty {
            lines.append("")
            lines.append(lineup.notes)
        }
        return lines.joined(separator: "\n")
    }
}

/// A self-contained graphic of the lineup, rendered to an image for sharing.
struct LineupShareCard: View {
    let lineup: Lineup
    let playersByID: [UUID: Player]

    private let width: CGFloat = 390

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lineup.name)
                        .font(.title2.weight(.heavy))
                    if !lineup.opponent.isEmpty {
                        Text("vs \(lineup.opponent)")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(lineup.formationName)
                        .font(.headline.weight(.bold))
                    Text(lineup.date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            PitchView(lineup: .constant(lineup), playersByID: playersByID, isEditable: false)
                .frame(width: width - 32, height: (width - 32) / PitchView.aspectRatio)

            if !lineup.bench.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SUBSTITUTES")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(lineup.bench.compactMap { playersByID[$0] }.map { player in
                        player.number.map { "\($0) \(player.shortName)" } ?? player.shortName
                    }.joined(separator: " · "))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: width)
        .background(Color(red: 0.07, green: 0.16, blue: 0.1))
        .environment(\.colorScheme, .dark)
    }
}

#Preview {
    let store = SquadStore.preview()
    return NavigationStack {
        LineupEditorView(lineup: .constant(store.lineups[0]))
    }
    .environment(store)
}

import SwiftUI

struct PlayerEditView: View {
    @Environment(SquadStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let existing: Player?

    @State private var name: String
    @State private var numberText: String
    @State private var positions: [Position]
    @State private var isAvailable: Bool
    @State private var notes: String
    @State private var isConfirmingDelete = false

    init(player: Player?) {
        existing = player
        _name = State(initialValue: player?.name ?? "")
        _numberText = State(initialValue: player?.number.map(String.init) ?? "")
        _positions = State(initialValue: player?.positions ?? [])
        _isAvailable = State(initialValue: player?.isAvailable ?? true)
        _notes = State(initialValue: player?.notes ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Player") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    TextField("Shirt number", text: $numberText)
                        .keyboardType(.numberPad)
                        .onChange(of: numberText) {
                            let digits = String(numberText.filter(\.isNumber).prefix(3))
                            if digits != numberText { numberText = digits }
                        }
                    Toggle("Available for selection", isOn: $isAvailable)
                }

                Section {
                    ForEach(PositionGroup.allCases) { group in
                        positionGrid(for: group)
                    }
                } header: {
                    Text("Positions")
                } footer: {
                    Text("Tap positions in order of preference. The starred position is the player's main position.")
                }

                Section("Notes") {
                    TextField("Injuries, preferred foot, anything else…", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if existing != nil {
                    Section {
                        Button("Delete Player", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Player" : "Edit Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Delete \(trimmedName)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Player", role: .destructive) {
                    if let existing { store.deletePlayers([existing.id]) }
                    dismiss()
                }
            } message: {
                Text("They will also be removed from any saved lineups.")
            }
        }
    }

    private func positionGrid(for group: PositionGroup) -> some View {
        let groupPositions = Position.allCases.filter { $0.group == group }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 8)], spacing: 8) {
            ForEach(groupPositions) { position in
                let isSelected = positions.contains(position)
                Button {
                    toggle(position)
                } label: {
                    Text(position.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .background(
                            isSelected ? AnyShapeStyle(group.color) : AnyShapeStyle(Color(.tertiarySystemFill)),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(alignment: .topTrailing) {
                            if positions.first == position {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                                    .padding(3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(position.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ position: Position) {
        if let index = positions.firstIndex(of: position) {
            positions.remove(at: index)
        } else {
            positions.append(position)
        }
    }

    private func save() {
        var player = existing ?? Player(name: trimmedName)
        player.name = trimmedName
        player.number = Int(numberText)
        player.positions = positions
        player.isAvailable = isAvailable
        player.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        store.upsert(player)
        dismiss()
    }
}

#Preview {
    PlayerEditView(player: Player.sampleSquad[3])
        .environment(SquadStore.preview())
}

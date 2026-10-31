import SwiftUI

/// Pro: run a live match with a clock, score, substitutions and playing-time tracking.
struct MatchDayView: View {
    @Binding var lineup: Lineup
    @Environment(SquadStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var substitutionSlot: SlotRef?
    @State private var isConfirmingFullTime = false
    @State private var isConfirmingReset = false

    private struct TimeRow: Identifiable {
        let player: Player
        let time: TimeInterval
        var id: UUID { player.id }
    }

    struct SlotRef: Identifiable {
        let index: Int
        var id: Int { index }
    }

    var body: some View {
        let playersByID = store.playersByID

        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                let session = lineup.match ?? MatchSession()

                ScrollView {
                    VStack(spacing: 20) {
                        scoreboard(session, now: now)
                        controls(session, now: now)

                        PitchView(lineup: $lineup, playersByID: playersByID) { index in
                            if !session.isFinished {
                                substitutionSlot = SlotRef(index: index)
                            }
                        }
                        .frame(maxWidth: 520)

                        if !session.isFinished {
                            Text("Tap a player on the pitch to substitute them.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        playingTime(session, playersByID: playersByID, now: now)
                        timeline(session, playersByID: playersByID)
                    }
                    .padding()
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Match Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Start New Match", systemImage: "arrow.counterclockwise", role: .destructive) {
                            isConfirmingReset = true
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $substitutionSlot) { slot in
                SubstitutionSheet(lineup: $lineup, slotIndex: slot.index)
            }
            .confirmationDialog("End the match?", isPresented: $isConfirmingFullTime, titleVisibility: .visible) {
                Button("Full Time") { lineup.match?.finish() }
            } message: {
                Text("The clock stops and playing times are final.")
            }
            .confirmationDialog("Start a new match?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                Button("Reset Clock, Score and Times", role: .destructive) { lineup.startMatch() }
            } message: {
                Text("This clears the current match. Your lineup stays as it is.")
            }
            .onAppear {
                if lineup.match == nil {
                    lineup.startMatch()
                } else {
                    // Pick up any lineup changes made outside Match Day.
                    lineup.match?.sync(onPitch: Set(lineup.startingPlayerIDs))
                }
            }
        }
    }

    // MARK: - Scoreboard

    private func scoreboard(_ session: MatchSession, now: Date) -> some View {
        HStack(alignment: .center) {
            teamScore(name: "Us", score: session.ourScore, forUs: true, enabled: !session.isFinished)
            VStack(spacing: 4) {
                Text(session.elapsed(at: now).clockText)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    if session.isRunning {
                        Circle().fill(.red).frame(width: 8, height: 8)
                    }
                    Text(session.isFinished ? "Full Time" : session.periodName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            teamScore(
                name: lineup.opponent.isEmpty ? "Them" : lineup.opponent,
                score: session.theirScore,
                forUs: false,
                enabled: !session.isFinished
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func teamScore(name: String, score: Int, forUs: Bool, enabled: Bool) -> some View {
        VStack(spacing: 6) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(score)")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .contentTransition(.numericText())
            if enabled {
                HStack(spacing: 14) {
                    Button {
                        withAnimation { lineup.match?.removeGoal(forUs: forUs) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .accessibilityLabel("Remove goal for \(name)")
                    Button {
                        withAnimation { lineup.match?.addGoal(forUs: forUs) }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Goal for \(name)")
                }
                .font(.title2)
            }
        }
        .frame(width: 96)
    }

    // MARK: - Controls

    @ViewBuilder
    private func controls(_ session: MatchSession, now: Date) -> some View {
        if session.isFinished {
            Label("Match finished", systemImage: "flag.checkered")
                .font(.headline)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) {
                Button {
                    if session.isRunning {
                        lineup.match?.pause()
                    } else {
                        lineup.match?.start()
                    }
                } label: {
                    Label(
                        session.isRunning ? "Pause" : (session.elapsed(at: now) == 0 ? "Kick Off" : "Resume"),
                        systemImage: session.isRunning ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(session.isRunning ? .orange : .green)

                Button {
                    lineup.match?.endPeriod()
                } label: {
                    Text(session.period == 1 ? "Half Time" : "End Period")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(session.elapsed(at: now) == 0)

                Button {
                    isConfirmingFullTime = true
                } label: {
                    Text("Full Time")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(session.elapsed(at: now) == 0)
            }
            .controlSize(.large)
        }
    }

    // MARK: - Playing time

    private func playingTime(_ session: MatchSession, playersByID: [UUID: Player], now: Date) -> some View {
        let onPitch = Set(lineup.startingPlayerIDs)
        let ids = (lineup.startingPlayerIDs + lineup.bench + Array(session.playedTime.keys)).uniqued()
        let rows = ids
            .compactMap { playersByID[$0] }
            .map { TimeRow(player: $0, time: session.timePlayed(by: $0.id, at: now)) }
            .sorted { $0.time < $1.time }
        let total = max(session.elapsed(at: now), 1)
        let nextOn = rows.first { !onPitch.contains($0.player.id) }?.player.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Playing Time").font(.headline)
                Spacer()
                Text("Least time first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    let isOn = onPitch.contains(row.player.id)
                    HStack(spacing: 12) {
                        PlayerBadge(player: row.player, size: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(row.player.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                if row.player.id == nextOn && !session.isFinished {
                                    Text("DUE ON")
                                        .font(.caption2.weight(.heavy))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(.blue, in: Capsule())
                                }
                            }
                            ProgressView(value: min(row.time, total), total: total)
                                .tint(isOn ? .green : .gray)
                        }
                        Text(row.time.minutesPlayedText)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                        Image(systemName: isOn ? "figure.run" : "chair.fill")
                            .foregroundStyle(isOn ? .green : .secondary)
                            .frame(width: 20)
                            .accessibilityLabel(isOn ? "On the pitch" : "On the bench")
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private func timeline(_ session: MatchSession, playersByID: [UUID: Player]) -> some View {
        if !session.events.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Timeline").font(.headline)
                ForEach(session.events.reversed()) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(event.time.minuteText)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .leading)
                        Text(describe(event, playersByID: playersByID))
                            .font(.subheadline)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func describe(_ event: MatchEvent, playersByID: [UUID: Player]) -> String {
        func name(_ id: UUID?) -> String {
            id.flatMap { playersByID[$0]?.name } ?? "Unknown"
        }
        switch event.kind {
        case .substitution:
            if event.playerOff == nil {
                return "🔼 \(name(event.playerOn)) on"
            }
            return "🔁 \(name(event.playerOn)) on for \(name(event.playerOff))"
        case .goalFor:
            return "⚽️ Goal for us"
        case .goalAgainst:
            return "⚽️ Goal for \(lineup.opponent.isEmpty ? "them" : lineup.opponent)"
        case .periodEnd:
            return event.period == 1 ? "⏸ Half time" : "⏸ End of period \(event.period)"
        case .fullTime:
            return "🏁 Full time"
        }
    }
}

/// Picks who comes on for the player in a slot.
private struct SubstitutionSheet: View {
    @Binding var lineup: Lineup
    let slotIndex: Int

    @Environment(SquadStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let playersByID = store.playersByID
        let session = lineup.match
        let current = lineup.slots.indices.contains(slotIndex)
            ? lineup.slots[slotIndex].playerID.flatMap { playersByID[$0] }
            : nil
        let benchPlayers = lineup.bench
            .compactMap { playersByID[$0] }
            .sorted { (session?.timePlayed(by: $0.id) ?? 0) < (session?.timePlayed(by: $1.id) ?? 0) }
        let others = store.players.filter { !lineup.isSelected($0.id) && $0.isAvailable }

        NavigationStack {
            List {
                if let current {
                    Section("Coming Off") {
                        row(current, time: session?.timePlayed(by: current.id))
                    }
                }
                Section {
                    if benchPlayers.isEmpty {
                        Text("Nobody on the bench.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(benchPlayers) { player in
                        Button {
                            bringOn(player)
                        } label: {
                            row(player, time: session?.timePlayed(by: player.id))
                        }
                    }
                } header: {
                    Text("Coming On – Bench")
                } footer: {
                    Text("Players with the least time played are listed first.")
                }
                if !others.isEmpty {
                    Section("Coming On – Not in Squad Today") {
                        ForEach(others) { player in
                            Button {
                                bringOn(player)
                            } label: {
                                row(player, time: nil)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Substitution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ player: Player, time: TimeInterval?) -> some View {
        HStack {
            PlayerRow(player: player)
            if let time {
                Text(time.minutesPlayedText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bringOn(_ player: Player) {
        withAnimation {
            lineup.substitute(player.id, intoSlot: slotIndex)
        }
        dismiss()
    }
}

#Preview {
    let store = SquadStore.preview()
    return MatchDayView(lineup: .constant(store.lineups[0]))
        .environment(store)
}

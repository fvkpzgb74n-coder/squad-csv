import Foundation
import Observation

private struct SquadData: Codable {
    var players: [Player]
    var lineups: [Lineup]
}

/// Holds the squad and saved lineups, persisted as JSON in the app's Documents folder.
@MainActor
@Observable
final class SquadStore {
    var players: [Player] = []
    var lineups: [Lineup] = []

    private let fileURL: URL?

    init(fileURL: URL? = URL.documentsDirectory.appending(path: "squad.json")) {
        self.fileURL = fileURL
        load()
    }

    static func preview() -> SquadStore {
        let store = SquadStore(fileURL: nil)
        store.players = Player.sampleSquad
        var lineup = Lineup(name: "Saturday League", opponent: "Riverside FC", formation: Formation.all[1])
        lineup.autoFill(with: store.players)
        lineup.fillBench(with: store.players)
        store.lineups = [lineup]
        return store
    }

    var playersByID: [UUID: Player] {
        Dictionary(players.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Players

    func upsert(_ player: Player) {
        if let index = players.firstIndex(where: { $0.id == player.id }) {
            players[index] = player
        } else {
            players.append(player)
        }
    }

    func deletePlayers(_ ids: Set<UUID>) {
        players.removeAll { ids.contains($0.id) }
        pruneLineups()
    }

    func loadSampleSquad() {
        importPlayers(Player.sampleSquad, replace: false)
    }

    /// Merges players into the squad, matching existing players by name.
    @discardableResult
    func importPlayers(_ imported: [Player], replace: Bool) -> (added: Int, updated: Int) {
        if replace {
            players = imported
            pruneLineups()
            return (imported.count, 0)
        }

        var added = 0
        var updated = 0
        for player in imported {
            if let index = players.firstIndex(where: { $0.name.caseInsensitiveCompare(player.name) == .orderedSame }) {
                if let number = player.number { players[index].number = number }
                if !player.positions.isEmpty { players[index].positions = player.positions }
                if !player.notes.isEmpty { players[index].notes = player.notes }
                players[index].isAvailable = player.isAvailable
                updated += 1
            } else {
                players.append(player)
                added += 1
            }
        }
        return (added, updated)
    }

    private func pruneLineups() {
        let ids = Set(players.map(\.id))
        for index in lineups.indices {
            lineups[index].prune(keeping: ids)
        }
    }

    // MARK: - Lineups

    func duplicateLineup(_ lineup: Lineup) {
        let copy = lineup.duplicated()
        if let index = lineups.firstIndex(where: { $0.id == lineup.id }) {
            lineups.insert(copy, at: index + 1)
        } else {
            lineups.append(copy)
        }
    }

    // MARK: - Persistence

    func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoded = try JSONDecoder().decode(SquadData.self, from: data)
            players = decoded.players
            lineups = decoded.lineups
        } catch {
            print("Failed to load squad: \(error)")
        }
    }

    func save() {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(SquadData(players: players, lineups: lineups))
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Failed to save squad: \(error)")
        }
    }
}

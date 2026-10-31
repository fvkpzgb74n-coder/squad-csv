import Foundation

/// Converts a squad to and from CSV.
///
/// Columns (matched case-insensitively, in any order): `Name`, `Number`, `Positions`,
/// `Available`, `Notes`. `First Name` + `Last Name` columns are also accepted instead of `Name`.
/// Positions may be separated by `/`, `|`, spaces or commas (when quoted).
/// Files without a header row are read as `Name, Number, Positions`.
enum SquadCSV {
    static let header = ["Name", "Number", "Positions", "Available", "Notes"]

    enum ImportError: LocalizedError, Equatable {
        case empty
        case noPlayers

        var errorDescription: String? {
            switch self {
            case .empty: "The file is empty."
            case .noPlayers: "No players with a name were found in the file."
            }
        }
    }

    static func export(_ players: [Player]) -> String {
        let rows = players.map { player in
            [
                player.name,
                player.number.map(String.init) ?? "",
                player.positions.map(\.rawValue).joined(separator: "/"),
                player.isAvailable ? "Yes" : "No",
                player.notes,
            ]
        }
        return CSV.encode([header] + rows)
    }

    static func importPlayers(from text: String) throws -> [Player] {
        let rows = CSV.parse(text)
        guard let first = rows.first else { throw ImportError.empty }

        let columns = Columns(header: first)
        let dataRows = columns.hasHeader ? Array(rows.dropFirst()) : rows

        let players = dataRows.compactMap { columns.player(from: $0) }
        guard !players.isEmpty else { throw ImportError.noPlayers }
        return players
    }

    private struct Columns {
        var name: Int?
        var firstName: Int?
        var lastName: Int?
        var number: Int?
        var positions: Int?
        var available: Int?
        var notes: Int?
        var hasHeader = false

        private static let keys: [WritableKeyPath<Columns, Int?>: Set<String>] = [
            \.name: ["name", "player", "player name", "full name", "fullname"],
            \.firstName: ["first name", "firstname", "forename", "given name"],
            \.lastName: ["last name", "lastname", "surname", "family name"],
            \.number: ["number", "no", "no.", "num", "#", "shirt", "shirt number", "squad number", "kit number", "jersey", "jersey number"],
            \.positions: ["positions", "position", "pos", "role", "roles"],
            \.available: ["available", "availability", "fit", "status"],
            \.notes: ["notes", "note", "comments", "comment"],
        ]

        init(header: [String]) {
            var found = false
            for (index, raw) in header.enumerated() {
                let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                for (path, names) in Self.keys where names.contains(key) && self[keyPath: path] == nil {
                    self[keyPath: path] = index
                    found = true
                }
            }
            hasHeader = found
            if !found {
                name = 0
                number = 1
                positions = 2
            }
        }

        func player(from row: [String]) -> Player? {
            func value(_ index: Int?) -> String {
                guard let index, row.indices.contains(index) else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var name = value(self.name)
            if name.isEmpty {
                name = [value(firstName), value(lastName)]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            guard !name.isEmpty else { return nil }

            let numberText = value(number).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            let positions = value(self.positions)
                .components(separatedBy: CharacterSet(charactersIn: "/|,;+ "))
                .compactMap(Position.parse)

            return Player(
                name: name,
                number: Int(numberText),
                positions: positions.uniqued(),
                isAvailable: SquadCSV.parseAvailability(value(available)),
                notes: value(notes)
            )
        }
    }

    static func parseAvailability(_ text: String) -> Bool {
        let unavailable: Set<String> = ["no", "n", "false", "0", "injured", "unavailable", "suspended", "out"]
        return !unavailable.contains(text.lowercased())
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

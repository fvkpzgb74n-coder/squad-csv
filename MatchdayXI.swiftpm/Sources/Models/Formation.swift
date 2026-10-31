import Foundation

/// A position marker within a formation. Coordinates are normalised to the pitch:
/// `x` runs 0 (left touchline) to 1 (right), `y` runs 0 (opponent's goal) to 1 (own goal).
struct FormationSlot: Codable, Hashable {
    var role: Position
    var x: Double
    var y: Double
}

struct Formation: Identifiable, Hashable {
    let id: String
    let name: String
    let slots: [FormationSlot]

    var playerCount: Int { slots.count }

    init(_ name: String, lines: [(y: Double, roles: [Position])]) {
        self.name = name
        let outfield = lines.flatMap { line in Formation.spread(line.roles, at: line.y) }
        let slots = [FormationSlot(role: .gk, x: 0.5, y: 0.91)] + outfield
        self.slots = slots
        self.id = "\(slots.count)-\(name)"
    }

    /// Spreads a line of players evenly across the pitch width.
    private static func spread(_ roles: [Position], at y: Double) -> [FormationSlot] {
        let count = roles.count
        guard count > 1 else {
            return roles.map { FormationSlot(role: $0, x: 0.5, y: y) }
        }
        let margin: Double = switch count {
        case 2: 0.3
        case 3: 0.2
        case 4: 0.13
        default: 0.1
        }
        let step = (1 - 2 * margin) / Double(count - 1)
        return roles.enumerated().map { index, role in
            FormationSlot(role: role, x: margin + step * Double(index), y: y)
        }
    }
}

extension Formation {
    static let all: [Formation] = [
        // 11-a-side
        Formation("4-4-2", lines: [
            (0.72, [.lb, .cb, .cb, .rb]),
            (0.47, [.lm, .cm, .cm, .rm]),
            (0.2, [.st, .st]),
        ]),
        Formation("4-3-3", lines: [
            (0.72, [.lb, .cb, .cb, .rb]),
            (0.48, [.cm, .cdm, .cm]),
            (0.2, [.lw, .st, .rw]),
        ]),
        Formation("4-2-3-1", lines: [
            (0.73, [.lb, .cb, .cb, .rb]),
            (0.56, [.cdm, .cdm]),
            (0.36, [.lw, .cam, .rw]),
            (0.15, [.st]),
        ]),
        Formation("4-1-4-1", lines: [
            (0.74, [.lb, .cb, .cb, .rb]),
            (0.58, [.cdm]),
            (0.4, [.lm, .cm, .cm, .rm]),
            (0.16, [.st]),
        ]),
        Formation("4-4-1-1", lines: [
            (0.73, [.lb, .cb, .cb, .rb]),
            (0.5, [.lm, .cm, .cm, .rm]),
            (0.3, [.cf]),
            (0.15, [.st]),
        ]),
        Formation("3-5-2", lines: [
            (0.74, [.cb, .cb, .cb]),
            (0.5, [.lwb, .cm, .cdm, .cm, .rwb]),
            (0.2, [.st, .st]),
        ]),
        Formation("3-4-3", lines: [
            (0.74, [.cb, .cb, .cb]),
            (0.5, [.lm, .cm, .cm, .rm]),
            (0.2, [.lw, .st, .rw]),
        ]),
        Formation("5-3-2", lines: [
            (0.72, [.lwb, .cb, .cb, .cb, .rwb]),
            (0.47, [.cm, .cm, .cm]),
            (0.2, [.st, .st]),
        ]),
        Formation("5-4-1", lines: [
            (0.73, [.lwb, .cb, .cb, .cb, .rwb]),
            (0.48, [.lm, .cm, .cm, .rm]),
            (0.18, [.st]),
        ]),
        // 9-a-side
        Formation("3-3-2", lines: [
            (0.72, [.lb, .cb, .rb]),
            (0.47, [.lm, .cm, .rm]),
            (0.2, [.st, .st]),
        ]),
        Formation("3-2-3", lines: [
            (0.72, [.lb, .cb, .rb]),
            (0.5, [.cm, .cm]),
            (0.22, [.lw, .st, .rw]),
        ]),
        // 7-a-side
        Formation("2-3-1", lines: [
            (0.7, [.cb, .cb]),
            (0.45, [.lm, .cm, .rm]),
            (0.18, [.st]),
        ]),
        Formation("3-2-1", lines: [
            (0.7, [.lb, .cb, .rb]),
            (0.45, [.cm, .cm]),
            (0.18, [.st]),
        ]),
        // 5-a-side
        Formation("2-2", lines: [
            (0.65, [.cb, .cb]),
            (0.3, [.st, .st]),
        ]),
        Formation("1-2-1", lines: [
            (0.7, [.cb]),
            (0.47, [.lm, .rm]),
            (0.2, [.st]),
        ]),
    ]

    static let `default` = all[0]

    static func with(id: String) -> Formation? {
        all.first { $0.id == id }
    }

    struct SizeGroup: Identifiable {
        let playerCount: Int
        let formations: [Formation]
        var id: Int { playerCount }
        var title: String { "\(playerCount)-a-side" }
    }

    /// Formations grouped by team size, largest first.
    static let groupedBySize: [SizeGroup] = Dictionary(grouping: all, by: \.playerCount)
        .sorted { $0.key > $1.key }
        .map { SizeGroup(playerCount: $0.key, formations: $0.value) }
}

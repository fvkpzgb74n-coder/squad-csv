import SwiftUI

/// Broad area of the pitch a position belongs to. Used for colours and grouping.
enum PositionGroup: String, Codable, CaseIterable, Identifiable {
    case goalkeeper
    case defender
    case midfielder
    case forward

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goalkeeper: "Goalkeepers"
        case .defender: "Defenders"
        case .midfielder: "Midfielders"
        case .forward: "Forwards"
        }
    }

    var color: Color {
        switch self {
        case .goalkeeper: .orange
        case .defender: .blue
        case .midfielder: .green
        case .forward: .red
        }
    }
}

enum Position: String, Codable, CaseIterable, Identifiable {
    case gk = "GK"
    case lb = "LB"
    case cb = "CB"
    case rb = "RB"
    case lwb = "LWB"
    case rwb = "RWB"
    case cdm = "CDM"
    case cm = "CM"
    case cam = "CAM"
    case lm = "LM"
    case rm = "RM"
    case lw = "LW"
    case rw = "RW"
    case cf = "CF"
    case st = "ST"

    var id: String { rawValue }

    var group: PositionGroup {
        switch self {
        case .gk: .goalkeeper
        case .lb, .cb, .rb, .lwb, .rwb: .defender
        case .cdm, .cm, .cam, .lm, .rm: .midfielder
        case .lw, .rw, .cf, .st: .forward
        }
    }

    var name: String {
        switch self {
        case .gk: "Goalkeeper"
        case .lb: "Left Back"
        case .cb: "Centre Back"
        case .rb: "Right Back"
        case .lwb: "Left Wing Back"
        case .rwb: "Right Wing Back"
        case .cdm: "Defensive Midfielder"
        case .cm: "Central Midfielder"
        case .cam: "Attacking Midfielder"
        case .lm: "Left Midfielder"
        case .rm: "Right Midfielder"
        case .lw: "Left Winger"
        case .rw: "Right Winger"
        case .cf: "Centre Forward"
        case .st: "Striker"
        }
    }

    private static let aliases: [String: Position] = [
        "G": .gk, "GOALKEEPER": .gk, "KEEPER": .gk, "GOALIE": .gk,
        "D": .cb, "DEF": .cb, "DEFENDER": .cb, "CD": .cb,
        "DM": .cdm,
        "M": .cm, "MID": .cm, "MIDFIELDER": .cm, "MF": .cm,
        "AM": .cam,
        "LF": .lw, "RF": .rw,
        "F": .st, "FW": .st, "FWD": .st, "FORWARD": .st, "STRIKER": .st, "S": .st, "ATT": .st,
    ]

    /// Parses an abbreviation (e.g. "cb", "Striker", "DM") into a position.
    static func parse(_ text: String) -> Position? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { return nil }
        return Position(rawValue: key) ?? aliases[key]
    }
}

import Foundation

struct Player: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var number: Int?
    /// Positions the player can play, the first being their main position.
    var positions: [Position] = []
    var isAvailable = true
    var notes = ""

    var primaryPosition: Position? { positions.first }

    var positionsText: String {
        positions.map(\.rawValue).joined(separator: " / ")
    }

    var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    /// Surname where available, for compact labels on the pitch.
    var shortName: String {
        let parts = name.split(separator: " ")
        if parts.count > 1, let last = parts.last { return String(last) }
        return name
    }
}

extension Player {
    static let sampleSquad: [Player] = [
        Player(name: "Sam Okafor", number: 1, positions: [.gk]),
        Player(name: "Joe Sato", number: 13, positions: [.gk]),
        Player(name: "Leo Varga", number: 2, positions: [.rb, .rwb]),
        Player(name: "Jamie Hart", number: 3, positions: [.lb, .lwb]),
        Player(name: "Mateo Ruiz", number: 4, positions: [.cb]),
        Player(name: "Tom Ellis", number: 5, positions: [.cb, .cdm]),
        Player(name: "Danny Reeve", number: 15, positions: [.cb, .rb]),
        Player(name: "Kai Brennan", number: 6, positions: [.cdm, .cm]),
        Player(name: "Noah Fischer", number: 8, positions: [.cm, .cam]),
        Player(name: "Ollie Grant", number: 10, positions: [.cam, .cf]),
        Player(name: "Isaac Mensah", number: 16, positions: [.cm, .cdm]),
        Player(name: "Ben Adeyemi", number: 7, positions: [.rw, .rm]),
        Player(name: "Luca Moretti", number: 11, positions: [.lw, .lm]),
        Player(name: "Ryan Doyle", number: 9, positions: [.st, .cf]),
        Player(name: "Theo Laurent", number: 19, positions: [.st]),
        Player(name: "Max Kowalski", number: 17, positions: [.lm, .lw, .lb]),
        Player(name: "Finn Callaghan", number: 14, positions: [.rm, .rw]),
        Player(name: "Elliot Price", number: 20, positions: [.cm], isAvailable: false, notes: "Hamstring"),
    ]
}

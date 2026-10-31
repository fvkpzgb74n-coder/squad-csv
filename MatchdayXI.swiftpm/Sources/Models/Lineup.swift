import Foundation

struct LineupSlot: Identifiable, Codable, Hashable {
    var id = UUID()
    var role: Position
    var x: Double
    var y: Double
    var playerID: UUID?

    init(_ slot: FormationSlot) {
        role = slot.role
        x = slot.x
        y = slot.y
    }
}

enum SelectionStatus: Equatable {
    case starting(Position)
    case bench
    case notSelected
}

struct Lineup: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var opponent = ""
    var date = Date()
    var formationID: String
    var slots: [LineupSlot]
    var bench: [UUID] = []
    var captainID: UUID?
    var notes = ""
    /// Live match tracking (Pro). Nil until Match Day mode is first opened.
    var match: MatchSession?

    init(name: String, opponent: String = "", date: Date = Date(), formation: Formation = .default) {
        self.name = name
        self.opponent = opponent
        self.date = date
        self.formationID = formation.id
        self.slots = formation.slots.map(LineupSlot.init)
    }

    var formation: Formation? { Formation.with(id: formationID) }

    var formationName: String { formation?.name ?? formationID }

    var startingPlayerIDs: [UUID] { slots.compactMap(\.playerID) }

    var filledCount: Int { startingPlayerIDs.count }

    func status(of playerID: UUID) -> SelectionStatus {
        if let slot = slots.first(where: { $0.playerID == playerID }) {
            return .starting(slot.role)
        }
        return bench.contains(playerID) ? .bench : .notSelected
    }

    func isSelected(_ playerID: UUID) -> Bool {
        status(of: playerID) != .notSelected
    }

    // MARK: - Editing

    /// Puts a player into a slot. A player moved from another slot swaps places with
    /// the slot's current occupant; a player promoted from the bench swaps with them too.
    mutating func assign(_ playerID: UUID, toSlot index: Int) {
        guard slots.indices.contains(index) else { return }
        let displaced = slots[index].playerID
        guard displaced != playerID else { return }

        if let from = slots.firstIndex(where: { $0.playerID == playerID }) {
            slots[from].playerID = displaced
        } else if let benchIndex = bench.firstIndex(of: playerID) {
            bench.remove(at: benchIndex)
            if let displaced {
                bench.insert(displaced, at: benchIndex)
            }
        } else if displaced == captainID {
            captainID = nil
        }
        slots[index].playerID = playerID
    }

    mutating func clearSlot(_ index: Int) {
        guard slots.indices.contains(index) else { return }
        if slots[index].playerID == captainID { captainID = nil }
        slots[index].playerID = nil
    }

    /// Adds a player to the bench (taking them off the pitch if needed) or removes them from it.
    mutating func toggleBench(_ playerID: UUID) {
        if let index = bench.firstIndex(of: playerID) {
            bench.remove(at: index)
            return
        }
        for index in slots.indices where slots[index].playerID == playerID {
            slots[index].playerID = nil
        }
        if captainID == playerID { captainID = nil }
        bench.append(playerID)
    }

    mutating func remove(_ playerID: UUID) {
        for index in slots.indices where slots[index].playerID == playerID {
            slots[index].playerID = nil
        }
        bench.removeAll { $0 == playerID }
        if captainID == playerID { captainID = nil }
    }

    mutating func toggleCaptain(_ playerID: UUID) {
        captainID = captainID == playerID ? nil : playerID
    }

    mutating func clearAll() {
        for index in slots.indices { slots[index].playerID = nil }
        bench.removeAll()
        captainID = nil
    }

    /// Restores every marker to the formation's default spot.
    mutating func resetPositions() {
        guard let formation, formation.slots.count == slots.count else { return }
        for index in slots.indices {
            slots[index].x = formation.slots[index].x
            slots[index].y = formation.slots[index].y
        }
    }

    /// Switches formation, keeping players in matching roles where possible.
    /// Anyone who no longer fits is moved to the front of the bench.
    mutating func apply(_ formation: Formation) {
        var remaining: [(role: Position, playerID: UUID)] = slots.compactMap { slot in
            slot.playerID.map { (role: slot.role, playerID: $0) }
        }
        var newSlots = formation.slots.map(LineupSlot.init)

        let passes: [(Position, Position) -> Bool] = [
            { old, new in old == new },
            { old, new in old.group == new.group },
            { old, new in old != .gk && new != .gk },
        ]
        for matches in passes {
            for index in newSlots.indices where newSlots[index].playerID == nil {
                let role = newSlots[index].role
                if let match = remaining.firstIndex(where: { matches($0.role, role) }) {
                    newSlots[index].playerID = remaining.remove(at: match).playerID
                }
            }
        }

        bench.insert(contentsOf: remaining.map(\.playerID), at: 0)
        slots = newSlots
        formationID = formation.id
    }

    /// Fills empty slots with available, unselected players who best suit each role.
    mutating func autoFill(with players: [Player]) {
        var pool = players.filter { $0.isAvailable && !isSelected($0.id) }

        let passes: [(Player, Position) -> Bool] = [
            { player, role in player.primaryPosition == role },
            { player, role in player.positions.contains(role) },
            { player, role in player.primaryPosition?.group == role.group },
            { player, role in player.positions.contains { $0.group == role.group } },
            { player, role in role != .gk && player.primaryPosition != .gk },
        ]
        for matches in passes {
            for index in slots.indices where slots[index].playerID == nil {
                let role = slots[index].role
                if let match = pool.firstIndex(where: { matches($0, role) }) {
                    slots[index].playerID = pool.remove(at: match).id
                }
            }
        }
    }

    /// Puts every available player who isn't already selected on the bench.
    mutating func fillBench(with players: [Player]) {
        for player in players where player.isAvailable && !isSelected(player.id) {
            bench.append(player.id)
        }
    }

    /// Drops references to players who are no longer in the squad.
    mutating func prune(keeping playerIDs: Set<UUID>) {
        for index in slots.indices {
            if let id = slots[index].playerID, !playerIDs.contains(id) {
                slots[index].playerID = nil
            }
        }
        bench.removeAll { !playerIDs.contains($0) }
        if let captainID, !playerIDs.contains(captainID) { self.captainID = nil }
    }

    // MARK: - Match day

    mutating func startMatch() {
        var session = MatchSession()
        session.sync(onPitch: Set(startingPlayerIDs))
        match = session
    }

    /// Brings a player on in place of whoever is in the slot. The player coming off goes to the bench.
    mutating func substitute(_ playerID: UUID, intoSlot index: Int, at now: Date = Date()) {
        guard slots.indices.contains(index) else { return }
        let off = slots[index].playerID
        guard off != playerID else { return }
        assign(playerID, toSlot: index)
        if let off, !isSelected(off) {
            bench.append(off)
        }
        let onPitch = Set(startingPlayerIDs)
        match?.sync(onPitch: onPitch, at: now)
        match?.recordSubstitution(on: playerID, off: off, at: now)
    }

    func duplicated() -> Lineup {
        var copy = self
        copy.id = UUID()
        copy.name = "\(name) (copy)"
        copy.match = nil
        copy.slots = slots.map { slot in
            var slot = slot
            slot.id = UUID()
            return slot
        }
        return copy
    }
}

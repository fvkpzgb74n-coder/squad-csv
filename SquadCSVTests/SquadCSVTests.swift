import XCTest
@testable import SquadCSV

final class CSVParserTests: XCTestCase {
    func testParsesQuotedFieldsAndEscapedQuotes() {
        let rows = CSV.parse("Name,Notes\n\"Doe, John\",\"Says \"\"hi\"\"\"\n")
        XCTAssertEqual(rows, [["Name", "Notes"], ["Doe, John", "Says \"hi\""]])
    }

    func testHandlesCRLFBlankLinesAndBOM() {
        let rows = CSV.parse("\u{FEFF}a,b\r\n\r\nc,d\r\n")
        XCTAssertEqual(rows, [["a", "b"], ["c", "d"]])
    }

    func testDetectsSemicolonDelimiter() {
        XCTAssertEqual(CSV.parse("Name;Number\nAna;7"), [["Name", "Number"], ["Ana", "7"]])
    }

    func testMultilineQuotedField() {
        XCTAssertEqual(CSV.parse("a,\"line1\nline2\"\n"), [["a", "line1\nline2"]])
    }

    func testRoundTrip() {
        let rows = [["Name", "Notes"], ["O'Neil, Sean", "He said \"go\""]]
        XCTAssertEqual(CSV.parse(CSV.encode(rows)), rows)
    }
}

final class SquadCSVImportTests: XCTestCase {
    func testImportWithHeaderInAnyOrder() throws {
        let csv = """
        Pos,Player,#,Available
        GK,Sam Okafor,1,yes
        "CB/RB",Danny Reeve,#15,no
        striker,Ryan Doyle,9,
        """
        let players = try SquadCSV.importPlayers(from: csv)
        XCTAssertEqual(players.map(\.name), ["Sam Okafor", "Danny Reeve", "Ryan Doyle"])
        XCTAssertEqual(players.map(\.number), [1, 15, 9])
        XCTAssertEqual(players[1].positions, [.cb, .rb])
        XCTAssertEqual(players[2].positions, [.st])
        XCTAssertFalse(players[1].isAvailable)
        XCTAssertTrue(players[2].isAvailable)
    }

    func testImportWithoutHeader() throws {
        let players = try SquadCSV.importPlayers(from: "Leo Varga,2,RB\nKai Brennan,6,CDM CM\n")
        XCTAssertEqual(players.count, 2)
        XCTAssertEqual(players[1].positions, [.cdm, .cm])
    }

    func testFirstAndLastNameColumns() throws {
        let players = try SquadCSV.importPlayers(from: "First Name,Last Name,Number\nNoah,Fischer,8\n")
        XCTAssertEqual(players.first?.name, "Noah Fischer")
        XCTAssertEqual(players.first?.number, 8)
    }

    func testExportThenImportPreservesPlayers() throws {
        let original = Player.sampleSquad
        let imported = try SquadCSV.importPlayers(from: SquadCSV.export(original))
        XCTAssertEqual(imported.map(\.name), original.map(\.name))
        XCTAssertEqual(imported.map(\.number), original.map(\.number))
        XCTAssertEqual(imported.map(\.positions), original.map(\.positions))
        XCTAssertEqual(imported.map(\.isAvailable), original.map(\.isAvailable))
        XCTAssertEqual(imported.map(\.notes), original.map(\.notes))
    }

    func testEmptyFileThrows() {
        XCTAssertThrowsError(try SquadCSV.importPlayers(from: "")) { error in
            XCTAssertEqual(error as? SquadCSV.ImportError, .empty)
        }
    }
}

final class LineupTests: XCTestCase {
    private let squad = Player.sampleSquad

    func testFormationsHaveExpectedPlayerCounts() {
        for formation in Formation.all {
            let outfield = formation.name.split(separator: "-").compactMap { Int($0) }.reduce(0, +)
            XCTAssertEqual(formation.playerCount, outfield + 1, formation.name)
        }
        XCTAssertEqual(Set(Formation.all.map(\.id)).count, Formation.all.count)
    }

    func testAutoFillPutsKeeperInGoalAndSkipsUnavailable() {
        var lineup = Lineup(name: "Test", formation: Formation.default)
        lineup.autoFill(with: squad)
        XCTAssertEqual(lineup.filledCount, 11)
        let keeperID = lineup.slots.first { $0.role == .gk }?.playerID
        XCTAssertEqual(squad.first { $0.id == keeperID }?.primaryPosition, .gk)
        let unavailable = squad.filter { !$0.isAvailable }.map(\.id)
        XCTAssertTrue(unavailable.allSatisfy { !lineup.isSelected($0) })
    }

    func testAssigningSelectedPlayerSwapsSlots() {
        var lineup = Lineup(name: "Test")
        let a = squad[0].id, b = squad[1].id
        lineup.assign(a, toSlot: 0)
        lineup.assign(b, toSlot: 1)
        lineup.assign(a, toSlot: 1)
        XCTAssertEqual(lineup.slots[0].playerID, b)
        XCTAssertEqual(lineup.slots[1].playerID, a)
    }

    func testPromotingFromBenchSwapsWithStarter() {
        var lineup = Lineup(name: "Test")
        let starter = squad[0].id, sub = squad[1].id
        lineup.assign(starter, toSlot: 0)
        lineup.toggleBench(sub)
        lineup.assign(sub, toSlot: 0)
        XCTAssertEqual(lineup.slots[0].playerID, sub)
        XCTAssertEqual(lineup.bench, [starter])
    }

    func testChangingFormationKeepsPlayersAndBenchesExtras() {
        var lineup = Lineup(name: "Test", formation: Formation.default)
        lineup.autoFill(with: squad)
        let before = Set(lineup.startingPlayerIDs)
        let fiveASide = Formation.all.first { $0.playerCount == 5 }!
        lineup.apply(fiveASide)
        XCTAssertEqual(lineup.filledCount, 5)
        XCTAssertEqual(lineup.bench.count, 6)
        XCTAssertEqual(Set(lineup.startingPlayerIDs).union(lineup.bench), before)
    }

    func testPruneRemovesDeletedPlayers() {
        var lineup = Lineup(name: "Test")
        lineup.assign(squad[0].id, toSlot: 0)
        lineup.toggleBench(squad[1].id)
        lineup.captainID = squad[0].id
        lineup.prune(keeping: [])
        XCTAssertEqual(lineup.filledCount, 0)
        XCTAssertTrue(lineup.bench.isEmpty)
        XCTAssertNil(lineup.captainID)
    }
}

final class MatchSessionTests: XCTestCase {
    private let squad = Player.sampleSquad
    private let kickOff = Date(timeIntervalSinceReferenceDate: 0)

    func testClockOnlyCountsWhileRunning() {
        var session = MatchSession()
        session.start(at: kickOff)
        session.pause(at: kickOff.addingTimeInterval(600))
        XCTAssertEqual(session.elapsed(at: kickOff.addingTimeInterval(900)), 600)
        session.start(at: kickOff.addingTimeInterval(900))
        XCTAssertEqual(session.elapsed(at: kickOff.addingTimeInterval(960)), 660)
    }

    func testSubstitutionSplitsPlayingTime() {
        var lineup = Lineup(name: "Test")
        let starter = squad[0].id, sub = squad[1].id
        lineup.assign(starter, toSlot: 0)
        lineup.toggleBench(sub)
        lineup.startMatch()
        lineup.match?.start(at: kickOff)

        let twentyMinutes = kickOff.addingTimeInterval(1200)
        lineup.substitute(sub, intoSlot: 0, at: twentyMinutes)

        let end = kickOff.addingTimeInterval(1800)
        XCTAssertEqual(lineup.match?.timePlayed(by: starter, at: end), 1200)
        XCTAssertEqual(lineup.match?.timePlayed(by: sub, at: end), 600)
        XCTAssertEqual(lineup.bench, [starter])
        XCTAssertEqual(lineup.match?.events.last?.kind, .substitution)
    }

    func testFinishBanksTimeAndStopsClock() {
        var lineup = Lineup(name: "Test")
        lineup.assign(squad[0].id, toSlot: 0)
        lineup.startMatch()
        lineup.match?.start(at: kickOff)
        lineup.match?.finish(at: kickOff.addingTimeInterval(300))
        let later = kickOff.addingTimeInterval(5000)
        XCTAssertEqual(lineup.match?.timePlayed(by: squad[0].id, at: later), 300)
        XCTAssertEqual(lineup.match?.isFinished, true)
    }

    func testGoalsAndUndo() {
        var session = MatchSession()
        session.addGoal(forUs: true)
        session.addGoal(forUs: true)
        session.addGoal(forUs: false)
        session.removeGoal(forUs: true)
        XCTAssertEqual(session.ourScore, 1)
        XCTAssertEqual(session.theirScore, 1)
        XCTAssertEqual(session.events.map(\.kind), [.goalFor, .goalAgainst])
    }
}

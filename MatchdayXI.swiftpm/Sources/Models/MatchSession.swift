import Foundation

struct MatchEvent: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case substitution
        case goalFor
        case goalAgainst
        case periodEnd
        case fullTime
    }

    var id = UUID()
    var kind: Kind
    /// Match-clock time in seconds when the event happened.
    var time: TimeInterval
    var period: Int
    var playerOn: UUID?
    var playerOff: UUID?
}

/// A live match (Pro): the match clock, score, substitutions and each player's time on the pitch.
///
/// Playing time is measured against the match clock, so time while the clock is paused
/// (half time, stoppages) isn't counted.
struct MatchSession: Codable, Hashable {
    var period = 1
    /// Clock time banked before the current running stretch.
    var accumulated: TimeInterval = 0
    var runningSince: Date?
    var ourScore = 0
    var theirScore = 0
    /// Time banked by players who have since gone off.
    var playedTime: [UUID: TimeInterval] = [:]
    /// Match-clock time at which each player currently on the pitch came on.
    var onSince: [UUID: TimeInterval] = [:]
    var events: [MatchEvent] = []
    var isFinished = false

    var isRunning: Bool { runningSince != nil }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        accumulated + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    func timePlayed(by playerID: UUID, at now: Date = Date()) -> TimeInterval {
        let banked = playedTime[playerID] ?? 0
        guard let since = onSince[playerID] else { return banked }
        return banked + max(0, elapsed(at: now) - since)
    }

    var periodName: String {
        switch period {
        case 1: "1st Half"
        case 2: "2nd Half"
        default: "Period \(period)"
        }
    }

    // MARK: - Clock

    mutating func start(at now: Date = Date()) {
        guard !isRunning, !isFinished else { return }
        runningSince = now
    }

    mutating func pause(at now: Date = Date()) {
        guard let since = runningSince else { return }
        accumulated += max(0, now.timeIntervalSince(since))
        runningSince = nil
    }

    mutating func endPeriod(at now: Date = Date()) {
        guard !isFinished else { return }
        pause(at: now)
        events.append(MatchEvent(kind: .periodEnd, time: elapsed(at: now), period: period))
        period += 1
    }

    mutating func finish(at now: Date = Date()) {
        guard !isFinished else { return }
        pause(at: now)
        sync(onPitch: [], at: now)
        events.append(MatchEvent(kind: .fullTime, time: elapsed(at: now), period: period))
        isFinished = true
    }

    // MARK: - Players

    /// Updates who is on the pitch: players who left bank their time, new players start counting.
    mutating func sync(onPitch: Set<UUID>, at now: Date = Date()) {
        let time = elapsed(at: now)
        for (id, since) in onSince where !onPitch.contains(id) {
            playedTime[id, default: 0] += max(0, time - since)
            onSince[id] = nil
        }
        if isFinished { return }
        for id in onPitch where onSince[id] == nil {
            onSince[id] = time
        }
    }

    mutating func recordSubstitution(on: UUID, off: UUID?, at now: Date = Date()) {
        events.append(MatchEvent(kind: .substitution, time: elapsed(at: now), period: period, playerOn: on, playerOff: off))
    }

    // MARK: - Score

    mutating func addGoal(forUs: Bool, at now: Date = Date()) {
        if forUs { ourScore += 1 } else { theirScore += 1 }
        events.append(MatchEvent(kind: forUs ? .goalFor : .goalAgainst, time: elapsed(at: now), period: period))
    }

    mutating func removeGoal(forUs: Bool) {
        let kind: MatchEvent.Kind = forUs ? .goalFor : .goalAgainst
        guard (forUs ? ourScore : theirScore) > 0 else { return }
        if forUs { ourScore -= 1 } else { theirScore -= 1 }
        if let index = events.lastIndex(where: { $0.kind == kind }) {
            events.remove(at: index)
        }
    }
}

extension TimeInterval {
    /// "mm:ss" for the match clock.
    var clockText: String {
        let total = Int(self)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Football-style minute, e.g. "12'".
    var minuteText: String {
        "\(Int(self) / 60 + 1)'"
    }

    /// Compact minutes played, e.g. "34m".
    var minutesPlayedText: String {
        "\(Int(self) / 60)m"
    }
}

import Foundation
import GRDB

/// Which way a study session asks: the pinyin/hanzi side asking and the
/// meaning answering, or the other way around (D5, D6).
public enum StudyDirection: String, Sendable, Equatable {
    case receptive
    case reverse
}

/// The singleton `preference` row in full: the study direction, how many new
/// words a session draws (D9, D10), whether a card's meaning speaks itself
/// when it flips (D11), and which installed voice speaks it at what speed
/// (route line 13).
public struct Preferences: Sendable, Equatable {
    public let direction: StudyDirection
    public let newWordsPerDay: Int
    public let speakOnFlip: Bool

    /// `AVSpeechSynthesisVoice.identifier` of the chosen voice, or `nil` to
    /// let `SpeechSpeaker` pick the best Mandarin voice installed. Stored as
    /// a bare string because `LaoshuKit` cannot import AVFoundation.
    public let voiceIdentifier: String?

    /// `AVSpeechUtterance.rate`'s own 0.0-1.0 range, stored as a plain
    /// `Double` for the same reason.
    public let speechRate: Double

    public init(
        direction: StudyDirection,
        newWordsPerDay: Int,
        speakOnFlip: Bool,
        voiceIdentifier: String? = nil,
        speechRate: Double = 0.5
    ) {
        self.direction = direction
        self.newWordsPerDay = newWordsPerDay
        self.speakOnFlip = speakOnFlip
        self.voiceIdentifier = voiceIdentifier
        self.speechRate = speechRate
    }

    /// What a missing `preference` row reads as: receptive, eight new words
    /// a day, speaking on flip, the app's own choice of voice, default speed.
    static let defaults = Preferences(direction: .receptive, newWordsPerDay: 8, speakOnFlip: true)
}

/// Reads and writes the singleton `preference` row: the study direction
/// every new session draws with, and the two settings (D9-D11) it draws
/// alongside it.
public struct PreferenceStore: Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func direction() throws -> StudyDirection {
        try dbQueue.read { db in
            // No row at all should be unreachable, since the migration
            // writes one. Read as receptive rather than trapping, the way
            // `PlacementStore.status()` reads a missing row as not taken.
            guard let row = try Row.fetchOne(
                db, sql: "SELECT direction FROM preference WHERE id = 1;"
            ) else { return .receptive }
            let direction: String = row["direction"]
            return StudyDirection(rawValue: direction) ?? .receptive
        }
    }

    public func setDirection(_ direction: StudyDirection) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE preference SET direction = ? WHERE id = 1;",
                arguments: [direction.rawValue]
            )
        }
    }

    /// The whole row in one query. A missing row (unreachable in practice,
    /// since the migration writes one) reads as `Preferences.defaults`
    /// rather than trapping, the same way `direction()` does.
    public func preferences() throws -> Preferences {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT direction, new_words_per_day, speak_on_flip, voice_identifier, speech_rate FROM preference WHERE id = 1;"
            ) else { return .defaults }
            let direction: String = row["direction"]
            return Preferences(
                direction: StudyDirection(rawValue: direction) ?? .receptive,
                newWordsPerDay: row["new_words_per_day"],
                speakOnFlip: (row["speak_on_flip"] as Int) == 1,
                voiceIdentifier: row["voice_identifier"],
                speechRate: row["speech_rate"]
            )
        }
    }

    public func setNewWordsPerDay(_ newWordsPerDay: Int) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE preference SET new_words_per_day = ? WHERE id = 1;",
                arguments: [newWordsPerDay]
            )
        }
    }

    public func setSpeakOnFlip(_ speakOnFlip: Bool) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE preference SET speak_on_flip = ? WHERE id = 1;",
                arguments: [speakOnFlip ? 1 : 0]
            )
        }
    }

    /// `nil` clears the chosen voice, going back to "let the app pick."
    public func setVoiceIdentifier(_ voiceIdentifier: String?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE preference SET voice_identifier = ? WHERE id = 1;",
                arguments: [voiceIdentifier]
            )
        }
    }

    public func setSpeechRate(_ speechRate: Double) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE preference SET speech_rate = ? WHERE id = 1;",
                arguments: [speechRate]
            )
        }
    }
}

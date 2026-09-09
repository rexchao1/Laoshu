import Foundation
import GRDB

/// The user's answer to a placement test word: do they already know it?
public enum PlacementAnswer: Sendable, Equatable {
    case know
    case dontKnow
}

/// One placement test in progress: drives `PlacementTest`'s pure level walk
/// with real blocks of words, drawn from the database, and collects which
/// ones the user says they already know.
///
/// D10: a word answered "know it" is written as a retired batch only once
/// the whole walk finishes, one batch per level marked — never as each
/// answer comes in — so a test abandoned partway through leaves no trace,
/// the same way `Session` defers its first write to the first swipe.
public final class PlacementSession {
    private let dbQueue: DatabaseQueue
    private let batchStore: BatchStore
    private let today: TodayProvider
    private var rng: any RandomNumberGenerator

    private var walk = PlacementTest()
    private var knownWordIndicesByLevel: [Int: [Int]] = [:]
    private var knownCountInBlock = 0
    private var currentLevel = PlacementTest.startingLevel
    private var queue: [Word] = []

    /// Set once the walk stops (D5, D12).
    public private(set) var recommendedLevel: Int?

    /// How many words have been answered so far, against
    /// `PlacementTest.wordCeiling` — what the test screen's progress bar
    /// fills against, since a walk that stops early never reaches it.
    public private(set) var wordsAnswered = 0

    /// Every word answered "know it", in answer order — the end screen's
    /// list, by pinyin and meaning, of what the test marked as known (D17,
    /// D17a). Kept alongside `knownWordIndicesByLevel`, which groups the
    /// same words by level for the batches `finish` writes.
    public private(set) var knownWords: [Word] = []

    public var isFinished: Bool { recommendedLevel != nil }

    public var currentWord: Word? { queue.first }

    init(dbQueue: DatabaseQueue, batchStore: BatchStore, today: TodayProvider, rng: any RandomNumberGenerator) throws {
        self.dbQueue = dbQueue
        self.batchStore = batchStore
        self.today = today
        self.rng = rng
        try loadBlock(level: PlacementTest.startingLevel)
    }

    /// Records the user's answer to `currentWord` and, once the block is
    /// exhausted, scores it and advances the walk.
    public func answer(_ answer: PlacementAnswer) throws {
        guard !queue.isEmpty else { return }
        let word = queue.removeFirst()
        wordsAnswered += 1
        if answer == .know {
            knownCountInBlock += 1
            knownWordIndicesByLevel[currentLevel, default: []].append(word.wordIndex)
            knownWords.append(word)
        }

        guard queue.isEmpty else { return }
        try apply(walk.recordBlock(level: currentLevel, knownCount: knownCountInBlock))
    }

    private func apply(_ step: PlacementTest.Step) throws {
        switch step {
        case .testLevel(let level):
            try loadBlock(level: level)
        case .finished(let recommendedLevel):
            try finish(recommendedLevel: recommendedLevel)
        }
    }

    /// Draws a level's block from the same unseen pool a study session's
    /// new-word draw uses (D7c) — a word already sitting in another batch,
    /// including one this test itself already wrote, is unreachable here.
    /// A pool short of a full block is treated as known outright, with no
    /// block ever shown (D7e).
    private func loadBlock(level: Int) throws {
        currentLevel = level
        knownCountInBlock = 0
        let pool = try batchStore.unseenWordIndices(level: level)

        guard pool.count >= PlacementTest.blockSize else {
            try apply(walk.recordTooFewWords(level: level))
            return
        }

        let chosen = Array(pool.shuffled(using: &rng).prefix(PlacementTest.blockSize))
        queue = try Word.fetch(indices: chosen, dbQueue: dbQueue)
    }

    private func finish(recommendedLevel: Int) throws {
        try dbQueue.write { db in
            for (level, wordIndices) in self.knownWordIndicesByLevel where !wordIndices.isEmpty {
                try BatchStore.createRetiredBatch(db, level: level, wordIndices: wordIndices, today: self.today)
            }
            try PlacementStore.markTaken(db, recommendedLevel: recommendedLevel)
        }
        self.recommendedLevel = recommendedLevel
    }
}

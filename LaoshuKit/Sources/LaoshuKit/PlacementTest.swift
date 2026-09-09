import Foundation

/// The placement test's pure level walk (D1, D5): which level a block of
/// five words is drawn from next, and when the walk stops.
///
/// Nothing here draws a word, asks a question, or writes anything — a caller
/// scores each block and gets back the next step. That split is what makes
/// the walk provable without a database or a simulator.
public struct PlacementTest: Sendable, Equatable {
    /// What a caller does next: test another level's block, or stop with a
    /// recommendation.
    public enum Step: Sendable, Equatable {
        case testLevel(Int)
        case finished(recommendedLevel: Int)
    }

    public static let startingLevel = 2
    public static let minLevel = 1
    public static let maxLevel = 6
    public static let blockSize = 5
    public static let wordCeiling = 25

    private struct LevelResult: Sendable, Equatable {
        let level: Int
        let knownCount: Int
    }

    private var results: [LevelResult] = []
    private var testedLevels: Set<Int> = []
    private var wordsShown = 0

    public init() {}

    /// What a fresh walk does first — always the starting level's block.
    public static var initialStep: Step { .testLevel(startingLevel) }

    /// Scores a block of `PlacementTest.blockSize` words at `level`:
    /// `knownCount` of them answered "know it". Four or five known moves up
    /// a level; zero or one moves down; two or three stops the walk.
    public mutating func recordBlock(level: Int, knownCount: Int) -> Step {
        precondition((0...Self.blockSize).contains(knownCount), "knownCount must be within the block")
        testedLevels.insert(level)
        results.append(LevelResult(level: level, knownCount: knownCount))
        wordsShown += Self.blockSize

        switch knownCount {
        case (Self.blockSize - 1)...Self.blockSize:
            return move(from: level, delta: 1)
        case 0...1:
            return move(from: level, delta: -1)
        default:
            return finish()
        }
    }

    /// A level whose pool of unbatched words came up short of a full block
    /// (D7e): treated as known outright, with no block ever shown, and
    /// always calling a move up — stopping if that move is refused.
    public mutating func recordTooFewWords(level: Int) -> Step {
        testedLevels.insert(level)
        results.append(LevelResult(level: level, knownCount: Self.blockSize))
        return move(from: level, delta: 1)
    }

    private mutating func move(from level: Int, delta: Int) -> Step {
        let next = level + delta
        guard next >= Self.minLevel, next <= Self.maxLevel else { return finish() }
        guard !testedLevels.contains(next) else { return finish() }
        guard wordsShown < Self.wordCeiling else { return finish() }
        return .testLevel(next)
    }

    /// The lowest level tested whose block had three or fewer of five known,
    /// or the highest level reached when every level tested had four or more
    /// known (D12).
    private func finish() -> Step {
        let recommended = results.filter { $0.knownCount <= 3 }.map(\.level).min()
            ?? results.map(\.level).max()
            ?? Self.startingLevel
        return .finished(recommendedLevel: recommended)
    }
}

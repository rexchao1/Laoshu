import Testing
@testable import LaoshuKit

/// Proves the package builds and is importable.
///
/// This exists so `swift test` can never report zero tests. A run with no tests
/// exits zero, which would let the build gate pass on silence.
@Test func packageLoads() {
    #expect(LaoshuKit.catalogueSchemaVersion == 1)
}

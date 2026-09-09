import SwiftUI

/// Placeholder for the level's browse screen. The real rows and audio are
/// the next task; this just names the level so the destination has
/// somewhere to land.
struct LevelBrowseView: View {
    let level: Int

    var body: some View {
        Text("Browse level \(level)")
            .navigationTitle("Level \(level)")
    }
}

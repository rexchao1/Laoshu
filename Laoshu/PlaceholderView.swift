import SwiftUI
import LaoshuKit

/// What the app shows until the level list exists.
///
/// This is deliberately not a stub of the real first screen. An empty level
/// list would look like a finished app that found no words, which is the one
/// thing the launch failure mode says never to show.
struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Laoshu")
                .font(.largeTitle.weight(.semibold))
            Text("No screens yet. Catalogue schema v\(LaoshuKit.catalogueSchemaVersion).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    PlaceholderView()
}

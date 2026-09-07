import SwiftUI

/// Shown instead of an empty level list when the catalogue is missing or
/// unreadable. Names the file rather than failing silently into a list that
/// looks like a finished app with no words.
struct DatabaseErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Couldn't open the word list")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LaoshuTheme.background)
    }
}

#Preview {
    DatabaseErrorView(message: "no catalogue database at /path/to/laoshu.sqlite")
}

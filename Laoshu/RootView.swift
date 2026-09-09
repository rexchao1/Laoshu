import SwiftUI
import LaoshuKit

/// Opens the database once at launch and hands the resulting engine to the
/// level list, or shows the named-file error screen if it cannot be opened.
struct RootView: View {
    @State private var engine: SessionEngine?
    @State private var preferenceStore: PreferenceStore?
    @State private var streakReader: StreakReader?
    @State private var progressStore: ProgressStore?
    @State private var openError: String?

    var body: some View {
        Group {
            if let engine, let preferenceStore, let streakReader, let progressStore {
                LevelListView(
                    engine: engine,
                    preferenceStore: preferenceStore,
                    streakReader: streakReader,
                    progressStore: progressStore
                )
            } else if let openError {
                DatabaseErrorView(message: openError)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LaoshuTheme.background)
            }
        }
        .task {
            openDatabase()
        }
    }

    private func openDatabase() {
        guard engine == nil, openError == nil else { return }
        do {
            let catalogueURL = try LaoshuDatabase.defaultCatalogueURL()
            let reviewLogURL = try LaoshuDatabase.defaultReviewLogURL()
            let dbQueue = try LaoshuDatabase.open(catalogueURL: catalogueURL, reviewLogURL: reviewLogURL)
            engine = SessionEngine(dbQueue: dbQueue)
            preferenceStore = PreferenceStore(dbQueue: dbQueue)
            streakReader = StreakReader(dbQueue: dbQueue)
            progressStore = ProgressStore(dbQueue: dbQueue)
        } catch {
            openError = "\(error)"
        }
    }
}

/// The version of the vocabulary schema this build expects.
///
/// The catalogue ships as a prebuilt SQLite file rather than being parsed on
/// device, so the app and the file it opens have to agree. Bumping this is how
/// a future build says it needs a database the old one would not understand.
public enum LaoshuKit {
    public static let catalogueSchemaVersion = 1
}

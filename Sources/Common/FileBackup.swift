import Foundation

/// Keeps a copy of a file that wm cannot read, as `<name>.bak` next to it, before the next save replaces it. Returns the copy, or
/// `nil` when there is no file or the copy failed (a backup that cannot be made must not stop wm). An older `.bak` is replaced.
@discardableResult
public func setAsideUnreadableFile(at url: URL) -> URL? {
    let files = FileManager.default
    guard files.fileExists(atPath: url.path) else { return nil }
    let backup = url.appendingPathExtension("bak")
    try? files.removeItem(at: backup)
    do {
        try files.copyItem(at: url, to: backup)
        return backup
    } catch {
        return nil
    }
}

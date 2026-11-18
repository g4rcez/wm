import CoreServices
import Foundation

/// Calls `onChange` (debounced) when a file changes anywhere in the config folder, including its subfolders, so
/// edits to modules loaded with `require` reload the config too. FSEvents sees atomic saves (rename over the file).
final class ConfigWatcher: @unchecked Sendable {
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "wm.config-watch")
    private var stream: FSEventStreamRef?

    init(fileURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        let folder = fileURL.deletingLastPathComponent().resolvingSymlinksInPath().path
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            Unmanaged<ConfigWatcher>.fromOpaque(info!).takeUnretainedValue().onChange()
        }
        // The latency (seconds) merges a burst of saves into one callback.
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [folder] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.25,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

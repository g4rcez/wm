import Foundation

/// Calls `onChange` (debounced) when the config file or its folder changes. Editors save by replacing the
/// file, so the folder is watched too and the file watch is re-armed after each change.
final class ConfigWatcher: @unchecked Sendable {
    private let fileURL: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "wm.config-watch")
    private var sources: [any DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?

    init(fileURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
        queue.async { [self] in arm() }
    }

    private func arm() {
        sources.forEach { $0.cancel() }
        sources = [fileURL, fileURL.deletingLastPathComponent()].compactMap { url in
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: queue
            )
            source.setEventHandler { [weak self] in self?.changed() }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            return source
        }
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [self] in
            arm()
            onChange()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

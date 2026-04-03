import Foundation
import os

final class FileWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private let callback: (String) -> Void
    private let queue = DispatchQueue(label: "com.fasttalk.filewatcher", qos: .utility)
    private var debounceWorkItem: DispatchWorkItem?

    init(callback: @escaping (String) -> Void) {
        self.callback = callback
    }

    func watchDirectories(_ paths: [String]) {
        stopAll()
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            watchDirectory(path)
        }
    }

    private func watchDirectory(_ path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            AppLogger.fileIO.warning("Failed to watch: \(path)")
            return
        }
        fileDescriptors.append(fd)

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            AppLogger.fileIO.debug("File change detected: \(path)")
            self.debouncedCallback(path)
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sources.append(source)
    }

    private func debouncedCallback(_ path: String) {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            AppLogger.fileIO.notice("Triggering rescan after debounce")
            DispatchQueue.main.async {
                self?.callback(path)
            }
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func stopAll() {
        debounceWorkItem?.cancel()
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        fileDescriptors.removeAll()
    }

    deinit {
        stopAll()
    }
}

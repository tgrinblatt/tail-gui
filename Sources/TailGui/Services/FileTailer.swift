import Foundation

final class FileTailer {
    private let path: String
    private var fd: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var lastOffset: off_t = 0
    private let queue = DispatchQueue(label: "tailgui.filetailer", qos: .utility)
    private var stopped = false

    var onAppend: ((Data) -> Void)?
    var onReset: ((Data) -> Void)?

    init(path: String) {
        self.path = path
    }

    func start() {
        queue.async { [weak self] in
            self?.openAndWatch(seedFromStart: true)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.tearDown()
            self?.stopped = true
        }
    }

    private func openAndWatch(seedFromStart: Bool) {
        guard !stopped else { return }
        tearDown()

        let openFd = open(path, O_EVTONLY | O_NONBLOCK)
        guard openFd >= 0 else {
            scheduleReopen()
            return
        }
        self.fd = openFd

        var st = stat()
        if fstat(openFd, &st) == 0 {
            lastOffset = 0
            if seedFromStart {
                if let data = readRange(from: 0, to: st.st_size), !data.isEmpty {
                    onReset?(data)
                }
                lastOffset = st.st_size
            } else {
                lastOffset = st.st_size
            }
        }

        let mask: DispatchSource.FileSystemEvent = [.write, .extend, .delete, .rename, .link]
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: openFd,
            eventMask: mask,
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.handleEvent(events: src.data)
        }
        src.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fd >= 0 {
                close(self.fd)
                self.fd = -1
            }
        }
        src.resume()
        self.source = src
    }

    private func handleEvent(events: DispatchSource.FileSystemEvent) {
        guard !stopped else { return }
        if events.contains(.delete) || events.contains(.rename) {
            let snapshot = lastOffset
            tearDown()
            queue.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
                guard let self = self, !self.stopped else { return }
                self.lastOffset = snapshot
                self.openAndWatch(seedFromStart: false)
                self.checkForGrowth()
            }
            return
        }
        if events.contains(.write) || events.contains(.extend) || events.contains(.link) {
            checkForGrowth()
        }
    }

    private func checkForGrowth() {
        guard fd >= 0 else { return }
        var st = stat()
        guard fstat(fd, &st) == 0 else { return }
        let size = st.st_size

        if size < lastOffset {
            lastOffset = 0
            if let data = readRange(from: 0, to: size), !data.isEmpty {
                onReset?(data)
            }
            lastOffset = size
            return
        }
        if size > lastOffset {
            if let data = readRange(from: lastOffset, to: size), !data.isEmpty {
                onAppend?(data)
            }
            lastOffset = size
        }
    }

    private func readRange(from: off_t, to: off_t) -> Data? {
        let length = Int(to - from)
        guard length > 0 else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: length, alignment: 1)
        defer { buffer.deallocate() }
        let read = pread(fd, buffer, length, from)
        guard read > 0 else { return nil }
        return Data(bytes: buffer, count: read)
    }

    private func tearDown() {
        if let s = source {
            s.cancel()
            source = nil
        } else if fd >= 0 {
            close(fd)
            fd = -1
        }
    }

    private func scheduleReopen() {
        queue.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
            guard let self = self, !self.stopped else { return }
            self.openAndWatch(seedFromStart: true)
        }
    }

    deinit {
        if let s = source { s.cancel() }
        if fd >= 0 { close(fd) }
    }
}

import Foundation
import Darwin

struct RenderHealth: Equatable {
    var drawThingsAlive: Bool
    var grpcOpen: Bool
    var lastChecked: Date?

    var hasBeenChecked: Bool { lastChecked != nil }

    var isAlive: Bool {
        drawThingsAlive && grpcOpen
    }

    static let unknown = RenderHealth(
        drawThingsAlive: false,
        grpcOpen: false,
        lastChecked: nil
    )
}

@MainActor
final class RenderHealthChecker: ObservableObject {
    @Published private(set) var health: RenderHealth = .unknown

    private var timer: Timer?
    private let interval: TimeInterval = 10
    private let grpcHost: String = "127.0.0.1"
    private let grpcPort: Int32 = 7859

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recheck() }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
        Task { @MainActor in self.recheck() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func recheck() {
        let host = grpcHost
        let port = grpcPort
        Task.detached(priority: .utility) { [weak self] in
            let dt = Self.processMatches(pattern: "DrawThings|Draw Things\\.app")
            let portOpen = Self.canConnect(host: host, port: port, timeoutMs: 250)
            let new = RenderHealth(
                drawThingsAlive: dt,
                grpcOpen: portOpen,
                lastChecked: Date()
            )
            await self?.applyHealth(new)
        }
    }

    private func applyHealth(_ new: RenderHealth) {
        health = new
    }

    nonisolated private static func processMatches(pattern: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "command="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return false }
        return out.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated private static func canConnect(host: String, port: Int32, timeoutMs: Int) -> Bool {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let n = poll(&pfd, 1, Int32(timeoutMs))
        guard n > 0 else { return false }

        var error: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &len)
        return error == 0
    }
}

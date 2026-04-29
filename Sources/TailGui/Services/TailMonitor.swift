import Foundation
import Combine

@MainActor
final class TailMonitor: ObservableObject {
    @Published private(set) var sessions: [TailSession] = []

    private var timer: Timer?
    private let scanInterval: TimeInterval = 2.0
    private let staleGrace: TimeInterval = 5.0
    private var pendingRemoval: [String: Date] = [:]

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: scanInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Task { @MainActor in await tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for session in sessions {
            session.markTerminated()
        }
        sessions.removeAll()
        pendingRemoval.removeAll()
    }

    private func tick() async {
        let scanned = await ProcessScanner.scan()
        applyScan(scanned)
        for session in sessions {
            session.recomputeStatus()
        }
    }

    private func applyScan(_ scanned: [TailProcess]) {
        var byPath: [String: [TailProcess]] = [:]
        for p in scanned {
            byPath[p.filePath, default: []].append(p)
        }

        let now = Date()
        var existingByPath: [String: TailSession] = [:]
        for s in sessions {
            existingByPath[s.filePath] = s
        }

        for (path, procs) in byPath {
            let pids = Set(procs.map { $0.pid })
            if let session = existingByPath[path] {
                session.pids = pids
                pendingRemoval.removeValue(forKey: path)
                if session.verdict == .pending || session.verdict == .rejected {
                    let v = DrawThingsDetector.evaluate(path: path)
                    let mapped: TailSession.Verdict
                    switch v {
                    case .confirmed: mapped = .confirmed
                    case .pending: mapped = .pending
                    case .rejected: mapped = .rejected
                    }
                    session.verdict = mapped
                }
            } else {
                let v = DrawThingsDetector.evaluate(path: path)
                let mappedVerdict: TailSession.Verdict
                switch v {
                case .confirmed: mappedVerdict = .confirmed
                case .pending: mappedVerdict = .pending
                case .rejected: mappedVerdict = .rejected
                }
                guard mappedVerdict != .rejected else { continue }
                let firstPid = procs.first?.pid ?? 0
                let session = TailSession(filePath: path, pid: firstPid, discoveredAt: now)
                session.pids = pids
                session.verdict = mappedVerdict
                let tailer = FileTailer(path: path)
                tailer.onReset = { [weak session] data in
                    Task { @MainActor in session?.resetContent(data) }
                }
                tailer.onAppend = { [weak session] data in
                    Task { @MainActor in session?.appendChunk(data) }
                }
                session.attach(tailer)
                tailer.start()
                sessions.append(session)
            }
        }

        let scannedPaths = Set(byPath.keys)
        for session in sessions {
            if !scannedPaths.contains(session.filePath) {
                if pendingRemoval[session.filePath] == nil {
                    pendingRemoval[session.filePath] = now
                }
                session.status = .terminated
            }
        }

        let toRemove = pendingRemoval.compactMap { (path, since) -> String? in
            now.timeIntervalSince(since) >= staleGrace ? path : nil
        }
        if !toRemove.isEmpty {
            for path in toRemove {
                if let idx = sessions.firstIndex(where: { $0.filePath == path }) {
                    sessions[idx].markTerminated()
                    sessions.remove(at: idx)
                }
                pendingRemoval.removeValue(forKey: path)
            }
        }

        sessions.sort { $0.startedAt < $1.startedAt }
    }
}

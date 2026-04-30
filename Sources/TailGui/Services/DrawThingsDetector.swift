import Foundation

enum DrawThingsDetector {
    enum Verdict: Equatable {
        case confirmed
        case pending
        case rejected
    }

    private struct CacheKey: Hashable {
        let inode: UInt64
        let size: Int64
    }

    private static var cache: [String: (key: CacheKey, verdict: Verdict)] = [:]
    private static let cacheLock = NSLock()

    private static let claudeOutputRegex: NSRegularExpression = {
        let pattern = #"^/private/tmp/claude-\d+/.+/tasks/[A-Za-z0-9._-]+\.output$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let strongMarkers: [String] = [
        "DRAW THINGS",
        "/Renders/Batch_"
    ]

    private static let softMarkers: [String] = [
        "Pinging gRPC",
        "Variants",
        "[clip ",
        "Pass ",
        " step ",
        "sampling steps"
    ]

    static func evaluate(path: String) -> Verdict {
        let pathOK = isClaudeTaskOutput(path)

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            return pathOK ? .pending : .rejected
        }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let key = CacheKey(inode: inode, size: size)

        cacheLock.lock()
        if let cached = cache[path], cached.key == key {
            cacheLock.unlock()
            return cached.verdict
        }
        cacheLock.unlock()

        let verdict = computeVerdict(path: path, pathOK: pathOK, size: size)

        cacheLock.lock()
        cache[path] = (key, verdict)
        cacheLock.unlock()
        return verdict
    }

    private static func isClaudeTaskOutput(_ path: String) -> Bool {
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return claudeOutputRegex.firstMatch(in: path, range: range) != nil
    }

    private static func computeVerdict(path: String, pathOK: Bool, size: Int64) -> Verdict {
        if size == 0 {
            return pathOK ? .pending : .rejected
        }
        let readSize = min(Int(size), 16 * 1024)
        guard let head = readHead(path: path, length: readSize) else {
            return pathOK ? .pending : .rejected
        }

        let upper = head.uppercased()
        for marker in strongMarkers {
            if upper.contains(marker.uppercased()) {
                return .confirmed
            }
        }
        var softHits = 0
        for marker in softMarkers {
            if head.contains(marker) {
                softHits += 1
                if softHits >= 2 { return .confirmed }
            }
        }
        if softHits >= 1 && pathOK { return .pending }
        return .rejected
    }

    private static func readHead(path: String, length: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let data: Data
        do {
            try handle.seek(toOffset: 0)
            data = handle.readData(ofLength: length)
        } catch {
            return nil
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    static func clearCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }
}

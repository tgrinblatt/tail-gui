import Foundation

enum OutputFileScanner {
    static let activeWindow: TimeInterval = 5 * 60

    static func scan() async -> [TailProcess] {
        await withCheckedContinuation { (cont: CheckedContinuation<[TailProcess], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: scanSync())
            }
        }
    }

    private static func scanSync() -> [TailProcess] {
        let now = Date()
        let cutoff = now.addingTimeInterval(-activeWindow)
        let fm = FileManager.default
        let tmpRoot = "/private/tmp"
        guard let entries = try? fm.contentsOfDirectory(atPath: tmpRoot) else { return [] }

        var results: [TailProcess] = []
        for entry in entries where entry.hasPrefix("claude-") {
            let claudeDir = "\(tmpRoot)/\(entry)"
            results.append(contentsOf: scanClaudeDir(claudeDir, cutoff: cutoff, now: now))
        }
        return results
    }

    private static func scanClaudeDir(_ root: String, cutoff: Date, now: Date) -> [TailProcess] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        var results: [TailProcess] = []

        for project in projects {
            let projectPath = "\(root)/\(project)"
            guard let sessions = try? fm.contentsOfDirectory(atPath: projectPath) else { continue }
            for session in sessions {
                let tasksPath = "\(projectPath)/\(session)/tasks"
                guard let tasks = try? fm.contentsOfDirectory(atPath: tasksPath) else { continue }
                for task in tasks where task.hasSuffix(".output") {
                    let filePath = "\(tasksPath)/\(task)"
                    if let process = candidateForFile(filePath, cutoff: cutoff, now: now) {
                        results.append(process)
                    }
                }
            }
        }
        return results
    }

    private static func candidateForFile(_ path: String, cutoff: Date, now: Date) -> TailProcess? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        guard let mtime = attrs[.modificationDate] as? Date else { return nil }
        guard mtime >= cutoff else { return nil }
        guard let type = attrs[.type] as? FileAttributeType, type == .typeRegular else { return nil }
        return TailProcess(pid: pidFromPath(path), filePath: path, discoveredAt: now)
    }

    private static func pidFromPath(_ path: String) -> Int32 {
        var hasher = Hasher()
        hasher.combine(path)
        let h = hasher.finalize()
        let positive = Int32(truncatingIfNeeded: h & 0x7fffffff)
        return -max(1, positive)
    }
}

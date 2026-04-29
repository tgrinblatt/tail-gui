import Foundation

enum PathParsing {
    struct TaskHint {
        let sessionPrefix: String
        let projectSlug: String
    }

    static func parse(_ path: String) -> TaskHint? {
        let parts = (path as NSString).pathComponents
        guard let tasksIdx = parts.firstIndex(of: "tasks"),
              tasksIdx >= 2 else { return nil }
        let sessionUUID = parts[tasksIdx - 1]
        let rawSlug = parts[tasksIdx - 2]
        let prefix = String(sessionUUID.prefix(8))
        let project = humanizeSlug(rawSlug)
        return TaskHint(sessionPrefix: prefix, projectSlug: project)
    }

    private static func humanizeSlug(_ slug: String) -> String {
        var s = slug
        if s.hasPrefix("-") { s.removeFirst() }
        let normalized = s.replacingOccurrences(of: "-", with: "/")
        let segments = normalized.split(separator: "/").map(String.init)
        guard let last = segments.last, !last.isEmpty else { return slug }
        return last
    }
}

import Foundation

enum ProcessScanner {
    static func scan() async -> [TailProcess] {
        await withCheckedContinuation { (cont: CheckedContinuation<[TailProcess], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: scanSync())
            }
        }
    }

    private static func scanSync() -> [TailProcess] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "pid=,command="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        let now = Date()
        var results: [TailProcess] = []

        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard let space = line.firstIndex(of: " ") else { continue }
            let pidStr = line[line.startIndex..<space].trimmingCharacters(in: .whitespaces)
            let cmdStr = line[line.index(after: space)...].trimmingCharacters(in: .whitespaces)
            guard let pid = Int32(pidStr) else { continue }
            guard let path = parseTailFollowPath(from: cmdStr) else { continue }
            results.append(TailProcess(pid: pid, filePath: path, discoveredAt: now))
        }
        return results
    }

    static func parseTailFollowPath(from command: String) -> String? {
        let tokens = tokenize(command)
        guard tokens.count >= 3 else { return nil }
        let exe = (tokens[0] as NSString).lastPathComponent
        guard exe == "tail" else { return nil }
        var sawFollow = false
        var pathArg: String? = nil
        for token in tokens.dropFirst() {
            if token == "-f" || token == "-F" {
                sawFollow = true
                continue
            }
            if token.hasPrefix("-") {
                if token.contains("f") || token.contains("F") {
                    sawFollow = true
                }
                continue
            }
            pathArg = token
        }
        guard sawFollow, let p = pathArg, !p.isEmpty else { return nil }
        return p
    }

    private static func tokenize(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inSingle = false
        var inDouble = false
        var escape = false
        for ch in s {
            if escape {
                cur.append(ch)
                escape = false
                continue
            }
            if ch == "\\" && !inSingle {
                escape = true
                continue
            }
            if ch == "'" && !inDouble {
                inSingle.toggle()
                continue
            }
            if ch == "\"" && !inSingle {
                inDouble.toggle()
                continue
            }
            if ch.isWhitespace && !inSingle && !inDouble {
                if !cur.isEmpty {
                    out.append(cur)
                    cur = ""
                }
                continue
            }
            cur.append(ch)
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}

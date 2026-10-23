import Foundation

final class ArenaLogWatcher {
    private var current: URL?
    private var offset: UInt64 = 0
    private var partial = ""
    private let fm = FileManager.default

    struct Result {
        let path: URL?
        let lines: [String]
    }

    func poll() -> Result {
        guard let latest = locateLatest() else { return Result(path: nil, lines: []) }
        if current != latest {
            current = latest
            partial = ""
            // Ignore old log entries from completed drafts when a session is discovered.
            // From this point, only appended lines are processed.
            offset = (try? latest.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
            return Result(path: latest, lines: [])
        }
        guard let size = (try? latest.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) else {
            return Result(path: latest, lines: [])
        }
        if size < offset { offset = 0; partial = "" }
        if size == offset { return Result(path: latest, lines: []) }
        guard let handle = try? FileHandle(forReadingFrom: latest) else { return Result(path: latest, lines: []) }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            let chunk = try handle.read(upToCount: 256_000) ?? Data()
            offset += UInt64(chunk.count)
            guard !chunk.isEmpty else { return Result(path: latest, lines: []) }
            let text = partial + String(decoding: chunk, as: UTF8.self)
            var lines = text.components(separatedBy: "\n")
            partial = lines.removeLast()
            if partial.count > 4096 { partial = "" }
            return Result(path: latest, lines: lines)
        } catch { return Result(path: latest, lines: []) }
    }

    private func locateLatest() -> URL? {
        let home = fm.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications/Hearthstone/Logs"),
            home.appendingPathComponent("Applications/Hearthstone/Logs"),
            home.appendingPathComponent("Library/Logs/Blizzard/Hearthstone"),
            home.appendingPathComponent("Library/Application Support/Blizzard/Hearthstone/Logs"),
            URL(fileURLWithPath: "/Applications/Hearthstone/Hearthstone.app/Contents/Logs")
        ]
        var latest: (url: URL, date: Date)?
        for root in roots where fm.fileExists(atPath: root.path) {
            guard let files = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            var count = 0
            for case let file as URL in files {
                count += 1
                if count > 6000 { break }
                if file.lastPathComponent.caseInsensitiveCompare("Arena.log") != .orderedSame { continue }
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if latest == nil || latest!.date < date { latest = (file, date) }
            }
        }
        return latest?.url
    }

    static func configureArenaLog() throws {
        let fm = FileManager.default
        let folder = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/Blizzard/Hearthstone", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("log.config")
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let section = "[Arena]"
        if let start = text.range(of: #"(?m)^\s*\[Arena\]\s*$"#, options: .regularExpression) {
            let beginning = start.upperBound
            let remainder = text[beginning...]
            let end = remainder.range(of: #"(?m)^\s*\[[^]]+\]\s*$"#, options: .regularExpression)?.lowerBound ?? text.endIndex
            var body = String(text[beginning..<end])
            for (key, desired) in [("LogLevel", "1"), ("FilePrinting", "true")] {
                let pattern = "(?m)^\\s*" + key + "\\s*=.*$"
                if body.range(of: pattern, options: .regularExpression) != nil {
                    body = body.replacingOccurrences(of: pattern, with: "\(key)=\(desired)", options: .regularExpression)
                } else { body += "\n\(key)=\(desired)" }
            }
            text.replaceSubrange(beginning..<end, with: body + "\n")
        } else {
            text += "\n\(section)\nLogLevel=1\nFilePrinting=true\nConsolePrinting=false\nScreenPrinting=false\n"
        }
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}

import Foundation

enum Agent: String, CaseIterable, Identifiable {
    case claude, codex
    var id: Self { self }
    var title: String { self == .claude ? "Claude Code" : "Codex" }
    var filename: String { self == .claude ? "settings.json" : "hooks.json" }
    var folder: URL {
        let variable = self == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"
        if let path = ProcessInfo.processInfo.environment[variable], path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("." + rawValue, isDirectory: true)
    }
}

enum AgentPhase: String {
    case working, attention, idle
}

struct AgentEvent {
    let agent: Agent
    let phase: AgentPhase
    let session: String
    static let scheme = "lidpulse"
    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == Self.scheme, parts.host == "event",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let values = parts.queryItems, values.count == 1, values[0].name == "sid",
              let session = values[0].value, (1...80).contains(session.utf8.count),
              session.unicodeScalars.allSatisfy(Self.allowed.contains) else { return nil }
        let path = parts.path.split(separator: "/")
        guard path.count == 2, let agent = Agent(rawValue: String(path[0])),
              let phase = AgentPhase(rawValue: String(path[1])) else { return nil }
        self.agent = agent
        self.phase = phase
        self.session = session
    }
}

enum AgentHooks {
    struct ConfigError: LocalizedError {
        var errorDescription: String? { "設定檔格式唔符合要求。原有檔案未有修改。" }
    }

    private typealias Object = [String: Any]

    private static func events(_ agent: Agent) -> [(String, AgentPhase)] {
        let shared: [(String, AgentPhase)] = [
            ("UserPromptSubmit", .working), ("PermissionRequest", .attention),
            ("PostToolUse", .working), ("PostToolUseFailure", .working),
            ("Stop", .idle), ("SessionEnd", .idle)
        ]
        return agent == .codex ? shared.filter { $0.0 != "PostToolUseFailure" } + [("Interrupt", .idle)] : shared
    }

    static func command(_ agent: Agent, _ phase: AgentPhase) -> String {
        // Read only the session ID; no prompt, tool arguments or output leave the hook.
        """
        /usr/bin/pgrep -xq LidPulse || exit 0; sid=$(/usr/bin/plutil -extract session_id raw -expect string -o - - 2>/dev/null) || sid=default; case "$sid" in ''|*[!A-Za-z0-9_-]*) sid=default;; esac; [ "${#sid}" -le 80 ] || sid=default; /usr/bin/open -g -b local.lidpulse "lidpulse://event/\(agent.rawValue)/\(phase.rawValue)?sid=$sid" >/dev/null 2>&1; exit 0
        """
    }

    private static func read(_ file: URL) throws -> (Object, Data?) {
        guard FileManager.default.fileExists(atPath: file.path) else { return ([:], nil) }
        let bytes = try Data(contentsOf: file)
        guard let value = try JSONSerialization.jsonObject(with: bytes) as? Object else { throw ConfigError() }
        return (value, bytes)
    }

    private static func ours(_ hook: Object, agent: Agent) -> Bool {
        guard let value = hook["command"] as? String else { return false }
        return [AgentPhase.working, .attention, .idle].contains { command(agent, $0) == value }
    }

    static func connected(_ agent: Agent, at file: URL) -> Bool {
        guard let (document, _) = try? read(file), let hooks = document["hooks"] as? Object else { return false }
        return events(agent).allSatisfy { name, _ in
            (hooks[name] as? [Object])?.contains {
                ($0["hooks"] as? [Object])?.contains { ours($0, agent: agent) } == true
            } == true
        }
    }

    static func configure(_ agent: Agent, at file: URL, connect: Bool) throws {
        var (document, previous) = try read(file)
        if previous == nil && !connect { return }
        guard document["hooks"] == nil || document["hooks"] is Object else { throw ConfigError() }
        var hooks = document["hooks"] as? Object ?? [:]
        for (name, phase) in events(agent) {
            guard hooks[name] == nil || hooks[name] is [Object] else { throw ConfigError() }
            var cleaned: [Object] = []
            for group in hooks[name] as? [Object] ?? [] {
                guard let commands = group["hooks"] as? [Object] else { throw ConfigError() }
                let retained = commands.filter { !ours($0, agent: agent) }
                if retained.count == commands.count {
                    cleaned.append(group)
                } else if !retained.isEmpty {
                    var updated = group
                    updated["hooks"] = retained
                    cleaned.append(updated)
                }
            }
            if connect {
                cleaned.append(["hooks": [[
                    "type": "command", "command": command(agent, phase), "timeout": 2
                ]]])
            }
            hooks[name] = cleaned.isEmpty ? nil : cleaned
        }
        document["hooks"] = hooks.isEmpty ? nil : hooks
        let output = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data([10])
        let manager = FileManager.default
        let parent = file.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        if let previous {
            let attributes = try manager.attributesOfItem(atPath: file.path)
            // Never replace a link with a settings file. The caller resolves links first.
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw ConfigError() }
            let backup = parent.appendingPathComponent("." + file.lastPathComponent + ".lidpulse-backup")
            let backupAttributes = try? manager.attributesOfItem(atPath: backup.path)
            guard backupAttributes == nil || backupAttributes?[.type] as? FileAttributeType == .typeRegular else {
                throw ConfigError()
            }
            // Avoid backing up or replacing a settings file that changed during this operation.
            guard try Data(contentsOf: file) == previous else { throw ConfigError() }
            let fd = open(backup.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            if fd >= 0 {
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                try handle.write(contentsOf: previous)
                try handle.close()
            } else if errno != EEXIST {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        try output.write(to: file, options: .atomic)
        if previous == nil {
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }
}

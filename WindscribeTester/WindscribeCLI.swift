import Foundation

enum WindscribeCLI {
    static let defaultCandidates = [
        "/usr/local/bin/windscribe-cli",
        "/opt/homebrew/bin/windscribe-cli",
        "/Applications/Windscribe.app/Contents/MacOS/windscribe-cli",
        "/Applications/Windscribe.app/Contents/Resources/windscribe-cli",
    ]

    static func detectPath() -> String {
        for candidate in defaultCandidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return defaultCandidates[0]
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    static func status(cliPath: String) async -> VPNStatus {
        let output = (try? await ProcessRunner.run(
            executable: cliPath,
            arguments: ["status"],
            timeout: 8
        )) ?? ""
        return parseStatus(output)
    }

    static func disconnect(cliPath: String) async {
        _ = try? await ProcessRunner.run(
            executable: cliPath,
            arguments: ["disconnect"],
            timeout: 10
        )
    }

    static func connect(cliPath: String, nick: String, proto: VPNProtocolKind, wait: Bool) async {
        var args = ["connect"]
        if !wait { args.append("-n") }
        args.append(contentsOf: [nick, proto.rawValue])
        _ = try? await ProcessRunner.run(
            executable: cliPath,
            arguments: args,
            timeout: wait ? 45 : 12
        )
    }

    static func waitUntilConnected(
        cliPath: String,
        timeout: TimeInterval,
        isCancelled: @escaping @Sendable () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isCancelled() || Task.isCancelled { return false }
            let status = await status(cliPath: cliPath)
            if status.isConnected { return true }
            if status.connection.lowercased().contains("error") { return false }
            try? await Task.sleep(for: .milliseconds(700))
        }
        return false
    }

    static func parseStatus(_ text: String) -> VPNStatus {
        var status = VPNStatus(raw: text)
        for line in text.split(whereSeparator: \.isNewline) {
            let raw = String(line).trimmingCharacters(in: .whitespaces)
            guard let idx = raw.firstIndex(of: ":") else { continue }
            let key = raw[..<idx].trimmingCharacters(in: .whitespaces).lowercased()
            let value = raw[raw.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "login": status.login = value
            case "connection": status.connection = value
            case "protocol": status.protocolLine = value
            case "ip": status.ip = value
            case "firewall": status.firewall = value
            case "data usage": status.dataUsage = value
            case "internet": status.internet = value
            default: break
            }
        }
        return status
    }
}

import Foundation

enum InventoryError: LocalizedError {
    case plistMissing(String)
    case malformed
    case cliEmpty

    var errorDescription: String? {
        switch self {
        case .plistMissing(let path):
            "Could not read Windscribe datacenters from \(path)."
        case .malformed:
            "Windscribe settings did not contain a usable server list."
        case .cliEmpty:
            "windscribe-cli locations did not print any servers."
        }
    }
}

enum InventoryService {
    static let plistPath = NSHomeDirectory() + "/Library/Preferences/com.windscribe.Windscribe2.plist"

    static func load(cliPath: String) async throws -> (servers: [ServerTarget], source: String) {
        do {
            return (try loadFromPlist(), "Windscribe settings")
        } catch {
            let fallback = try await loadFromCLI(cliPath: cliPath)
            if fallback.isEmpty { throw error }
            return (fallback, "Windscribe CLI")
        }
    }

    static func loadFromPlist() throws -> [ServerTarget] {
        let url = URL(fileURLWithPath: plistPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw InventoryError.plistMissing(plistPath)
        }

        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw InventoryError.malformed
        }

        let raw: String
        if let text = plist["wsnetSettings"] as? String {
            raw = text
        } else if let bytes = plist["wsnetSettings"] as? Data {
            raw = String(data: bytes, encoding: .utf8) ?? ""
        } else {
            throw InventoryError.malformed
        }

        return try parseSettingsJSON(raw)
    }

    static func parseSettingsJSON(_ text: String) throws -> [ServerTarget] {
        guard
            let settings = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            let invText = settings["invLocations"] as? String,
            let inventory = try JSONSerialization.jsonObject(with: Data(invText.utf8)) as? [String: Any]
        else {
            throw InventoryError.malformed
        }

        let payload = (inventory["data"] as? [String: Any]) ?? inventory
        guard let locations = payload["locations"] as? [[String: Any]] else {
            throw InventoryError.malformed
        }

        var servers: [ServerTarget] = []
        var seen = Set<String>()

        for location in locations {
            let country = (location["country_code"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let region = (location["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let continent = (location["continent"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "Other"
            let datacenters = location["datacenters"] as? [[String: Any]] ?? []

            for dc in datacenters {
                guard intValue(dc["status"]) == 1 else { continue }
                let nick = (dc["nick"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !nick.isEmpty, seen.insert(nick.lowercased()).inserted else { continue }
                let city = (dc["city"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                servers.append(
                    ServerTarget(
                        city: city,
                        nick: nick,
                        countryCode: country,
                        regionName: region,
                        continent: continent.isEmpty ? "Other" : continent,
                        iata: (dc["iata"] as? String) ?? "",
                        premium: boolish(dc["premium"]),
                        p2p: boolish(dc["p2p"]),
                        linkSpeedMbps: intValue(dc["link_speed"]),
                        isCustom: false
                    )
                )
            }
        }

        servers.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return servers
    }

    static func parseCLILocations(_ text: String) -> [ServerTarget] {
        var servers: [ServerTarget] = []
        var seen = Set<String>()

        for line in text.split(whereSeparator: \.isNewline) {
            var raw = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty || raw.hasPrefix("{") || raw.lowercased().hasPrefix("windscribe") {
                continue
            }

            let premium = raw.contains("(Pro)")
            let gbps = raw.contains("(10 Gbps)")
            raw = raw.replacingOccurrences(of: "(Pro)", with: "")
            raw = raw.replacingOccurrences(of: "(Disabled)", with: "")
            raw = raw.replacingOccurrences(of: "(10 Gbps)", with: "")
            raw = raw.trimmingCharacters(in: .whitespaces)

            let parts = raw.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            let nick = parts[parts.count - 1]
            let city = parts[parts.count - 2]
            let region = parts.count >= 3 ? parts[0] : ""
            if nick.isEmpty { continue }
            let reserved = ["nickname", "location", "locations"]
            if reserved.contains(nick.lowercased()) { continue }
            guard seen.insert(nick.lowercased()).inserted else { continue }

            servers.append(
                ServerTarget(
                    city: city,
                    nick: nick,
                    countryCode: "",
                    regionName: region,
                    continent: "Locations",
                    iata: "",
                    premium: premium,
                    p2p: false,
                    linkSpeedMbps: gbps ? 10_000 : 0,
                    isCustom: false
                )
            )
        }

        servers.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return servers
    }

    private static func loadFromCLI(cliPath: String) async throws -> [ServerTarget] {
        let output = try await ProcessRunner.run(
            executable: cliPath,
            arguments: ["locations"],
            timeout: 20
        )
        let servers = parseCLILocations(output)
        if servers.isEmpty { throw InventoryError.cliEmpty }
        return servers
    }

    private static func boolish(_ value: Any?) -> Bool {
        switch value {
        case let number as Int: number != 0
        case let number as Double: number != 0
        case let flag as Bool: flag
        case let text as String: text == "1" || text.lowercased() == "true"
        default: false
        }
    }

    private static func intValue(_ value: Any?) -> Int {
        switch value {
        case let number as Int: number
        case let number as Double: Int(number)
        case let text as String: Int(text) ?? 0
        default: 0
        }
    }
}

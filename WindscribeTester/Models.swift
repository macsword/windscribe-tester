import Foundation
import SwiftUI

enum VPNProtocolKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case wireguard
    case ikev2
    case udp
    case tcp
    case stealth
    case wstunnel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wireguard: "WireGuard"
        case .ikev2: "IKEv2"
        case .udp: "UDP"
        case .tcp: "TCP"
        case .stealth: "Stealth"
        case .wstunnel: "WS Tunnel"
        }
    }

    var systemImage: String {
        switch self {
        case .wireguard: "shield.lefthalf.filled"
        case .ikev2: "lock.shield"
        case .udp: "wave.3.right"
        case .tcp: "point.3.connected.trianglepath.dotted"
        case .stealth: "eye.slash"
        case .wstunnel: "globe"
        }
    }

    static let defaultEnabled: Set<VPNProtocolKind> = [.wireguard, .ikev2, .udp]
}

struct ServerTarget: Identifiable, Hashable, Codable {
    var id: String { nick.lowercased() }
    var city: String
    var nick: String
    var countryCode: String
    var regionName: String
    var continent: String
    var iata: String
    var premium: Bool
    var p2p: Bool
    var linkSpeedMbps: Int
    var isCustom: Bool

    var is10Gbps: Bool { linkSpeedMbps >= 10_000 }
    var flag: String { Self.flagEmoji(for: countryCode) }
    var title: String {
        city.isEmpty ? nick : "\(city) · \(nick)"
    }
    var subtitle: String {
        [regionName, countryCode].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func flagEmoji(for countryCode: String) -> String {
        let code = countryCode.uppercased()
        guard code.count == 2, code.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.uppercaseLetters.contains($0) }) else {
            return "🌐"
        }
        let base: UInt32 = 127_397
        var out = ""
        for scalar in code.unicodeScalars {
            if let flag = UnicodeScalar(base + scalar.value) {
                out.unicodeScalars.append(flag)
            }
        }
        return out.isEmpty ? "🌐" : out
    }
}

struct ContinentGroup: Identifiable {
    var id: String { name }
    let name: String
    let regions: [RegionGroup]
}

struct RegionGroup: Identifiable {
    var id: String { "\(countryCode)-\(name)" }
    let name: String
    let countryCode: String
    let servers: [ServerTarget]
}

enum TestOutcome: String, Codable {
    case success
    case pingFailed
    case timeout
    case cancelled

    var label: String {
        switch self {
        case .success: "Connected"
        case .pingFailed: "Ping failed"
        case .timeout: "Timeout"
        case .cancelled: "Cancelled"
        }
    }
}

struct TestResult: Identifiable, Hashable {
    let id: UUID
    let serverLabel: String
    let nick: String
    let city: String
    let countryCode: String
    let proto: VPNProtocolKind
    let outcome: TestOutcome
    let pingMs: Double?
    let finishedAt: Date

    var pingText: String {
        if let pingMs {
            return String(format: "%.1f ms", pingMs)
        }
        return "—"
    }
}

struct VPNStatus: Equatable {
    var login = ""
    var connection = ""
    var protocolLine = ""
    var ip = ""
    var firewall = ""
    var dataUsage = ""
    var internet = ""
    var raw = ""

    var isLoggedIn: Bool {
        let value = login.lowercased()
        return value.contains("logged in") && !value.contains("logged out")
    }

    var isConnected: Bool {
        let value = connection.lowercased()
        return value.hasPrefix("connected to") || value.contains("connected to")
    }

    var isConnecting: Bool {
        connection.lowercased().contains("connecting")
    }

    var isDisconnected: Bool {
        connection.lowercased().contains("disconnected")
    }

    var locationName: String {
        let prefixes = ["Connected to ", "Connecting to ", "connected to ", "connecting to "]
        for prefix in prefixes where connection.hasPrefix(prefix) {
            var name = String(connection.dropFirst(prefix.count))
            if let paren = name.firstIndex(of: "(") {
                name = String(name[..<paren])
            }
            return name.trimmingCharacters(in: .whitespaces)
        }
        return connection
    }

    var shortSummary: String {
        if !isLoggedIn {
            if login.isEmpty { return "Checking Windscribe…" }
            return login.isEmpty ? "Not logged in" : login
        }
        if isConnected { return "Connected · \(locationName)" }
        if isConnecting { return "Connecting · \(locationName)" }
        if isDisconnected { return "Disconnected" }
        return connection.isEmpty ? "Logged in" : connection
    }
}

struct TestProgress: Equatable {
    var currentServer = ""
    var currentProtocol: VPNProtocolKind = .wireguard
    var step = 0
    var total = 0
    var successful = 0
    var failed = 0
    var bestPing: Double?
    var startedAt = Date()

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(step) / Double(total)
    }

    var etaText: String {
        guard step > 0, step < total else {
            return total == 0 ? "" : "\(total) tests queued"
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = elapsed / Double(step) * Double(total - step)
        if remaining < 60 { return "About \(Int(remaining.rounded()))s left" }
        let minutes = Int((remaining / 60).rounded(.up))
        return "About \(minutes)m left"
    }
}

enum ResultFilter: String, CaseIterable, Identifiable {
    case all
    case success
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .success: "Working"
        case .failed: "Failed"
        }
    }
}

enum Palette {
    static let accent = Color(red: 0.42, green: 0.95, blue: 0.28)
    static let success = Color(red: 0.34, green: 0.82, blue: 0.45)
    static let warning = Color(red: 0.98, green: 0.74, blue: 0.22)
    static let fail = Color(red: 0.96, green: 0.38, blue: 0.38)
    static let gold = Color(red: 0.95, green: 0.78, blue: 0.25)
    static let silver = Color(red: 0.75, green: 0.78, blue: 0.82)
    static let bronze = Color(red: 0.80, green: 0.55, blue: 0.32)

    static func pingColor(_ ms: Double) -> Color {
        switch ms {
        case ..<40: success
        case ..<80: accent
        case ..<120: warning
        case ..<180: Color.orange
        default: fail
        }
    }

    static func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: gold
        case 2: silver
        case 3: bronze
        default: Color.secondary
        }
    }
}

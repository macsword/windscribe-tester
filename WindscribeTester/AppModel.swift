import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    var servers: [ServerTarget] = []
    var inventorySource = ""
    var isLoadingServers = false
    var searchText = ""
    var filter10G = false
    var filterP2P = false
    var filterPro = false
    var queuedNicks: Set<String> = []
    var customNickDraft = ""
    var enabledProtocols: Set<VPNProtocolKind> = VPNProtocolKind.defaultEnabled
    var cliPath = WindscribeCLI.detectPath()
    var timeoutSeconds = 15
    var uiScale: Double = 1.0
    var pingTarget = "1.1.1.1"
    var stayConnectedToBest = false
    var vpnStatus = VPNStatus()
    var isTesting = false
    var isCancelling = false
    var progress = TestProgress()
    var results: [TestResult] = []
    var resultFilter: ResultFilter = .all
    var showAlert = false
    var alertMessage = ""
    var showSettings = false

    private var testTask: Task<Void, Never>?
    private var cancelled: Bool { isCancelling || Task.isCancelled }

    var cliAvailable: Bool { WindscribeCLI.exists(cliPath) }

    var visibleServers: [ServerTarget] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return servers.filter { server in
            if filter10G && !server.is10Gbps { return false }
            if filterP2P && !server.p2p { return false }
            if filterPro && !server.premium { return false }
            if query.isEmpty { return true }
            let haystack = [
                server.city, server.nick, server.regionName, server.countryCode, server.continent, server.iata,
            ]
            .joined(separator: " ")
            .lowercased()
            return haystack.contains(query)
        }
    }

    var groupedServers: [ContinentGroup] {
        let preferred = ["North America", "Europe", "South America", "Asia", "Africa", "Oceania", "Custom", "Locations", "Other"]
        let grouped = Dictionary(grouping: visibleServers, by: \.continent)
        return grouped.keys.sorted { a, b in
            let ia = preferred.firstIndex(of: a) ?? 99
            let ib = preferred.firstIndex(of: b) ?? 99
            if ia != ib { return ia < ib }
            return a < b
        }
        .compactMap { continent in
            let regionsMap = Dictionary(grouping: grouped[continent] ?? [], by: \.regionName)
            let regions = regionsMap.keys.sorted().map { name in
                let list = (regionsMap[name] ?? []).sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return RegionGroup(
                    name: name.isEmpty ? continent : name,
                    countryCode: list.first?.countryCode ?? "",
                    servers: list
                )
            }
            guard !regions.isEmpty else { return nil }
            return ContinentGroup(name: continent, regions: regions)
        }
    }

    var queuedServers: [ServerTarget] {
        let byNick = Dictionary(uniqueKeysWithValues: servers.map { ($0.nick.lowercased(), $0) })
        return queuedNicks.compactMap { byNick[$0.lowercased()] }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var selectedProtocols: [VPNProtocolKind] {
        VPNProtocolKind.allCases.filter { enabledProtocols.contains($0) }
    }

    var testCount: Int { queuedServers.count * selectedProtocols.count }

    var filteredResults: [TestResult] {
        switch resultFilter {
        case .all: results
        case .success: results.filter { $0.pingMs != nil }
        case .failed: results.filter { $0.pingMs == nil }
        }
    }

    var sortedResults: [TestResult] {
        filteredResults.sorted { a, b in
            switch (a.pingMs, b.pingMs) {
            case let (left?, right?): left < right
            case (_?, nil): true
            case (nil, _?): false
            default: a.serverLabel.localizedCaseInsensitiveCompare(b.serverLabel) == .orderedAscending
            }
        }
    }

    var ranks: [UUID: Int] {
        var map: [UUID: Int] = [:]
        var rank = 1
        for result in results.sorted(by: { ($0.pingMs ?? .greatestFiniteMagnitude) < ($1.pingMs ?? .greatestFiniteMagnitude) })
        where result.pingMs != nil {
            map[result.id] = rank
            rank += 1
        }
        return map
    }

    var bestResult: TestResult? {
        results.filter { $0.pingMs != nil }.min { ($0.pingMs ?? 0) < ($1.pingMs ?? 0) }
    }

    var successCount: Int { results.filter { $0.pingMs != nil }.count }

    func bootstrap() async {
        loadSettings()
        await reloadServers()
    }

    func reloadServers() async {
        isLoadingServers = true
        defer { isLoadingServers = false }
        do {
            let loaded = try await InventoryService.load(cliPath: cliPath)
            let custom = servers.filter(\.isCustom)
            var merged = loaded.servers
            for item in custom where !merged.contains(where: { $0.nick.lowercased() == item.nick.lowercased() }) {
                merged.insert(item, at: 0)
            }
            servers = merged
            inventorySource = loaded.source
            queuedNicks = Set(queuedNicks.filter { nick in
                servers.contains { $0.nick.lowercased() == nick.lowercased() }
            })
        } catch {
            present(error.localizedDescription)
        }
    }

    func refreshStatus() async {
        guard cliAvailable else { return }
        vpnStatus = await WindscribeCLI.status(cliPath: cliPath)
    }

    func isQueued(_ server: ServerTarget) -> Bool {
        queuedNicks.contains(server.nick)
    }

    func toggleQueued(_ server: ServerTarget) {
        if queuedNicks.contains(server.nick) {
            queuedNicks.remove(server.nick)
        } else {
            queuedNicks.insert(server.nick)
        }
        persist()
    }

    func setRegion(_ region: RegionGroup, queued: Bool) {
        for server in region.servers {
            if queued {
                queuedNicks.insert(server.nick)
            } else {
                queuedNicks.remove(server.nick)
            }
        }
        persist()
    }

    func selectAllVisible() {
        for server in visibleServers {
            queuedNicks.insert(server.nick)
        }
        persist()
    }

    func clearQueue() {
        queuedNicks.removeAll()
        persist()
    }

    func addCustomServer() {
        let value = customNickDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if let existing = servers.first(where: { $0.nick.caseInsensitiveCompare(value) == .orderedSame }) {
            queuedNicks.insert(existing.nick)
        } else {
            let custom = ServerTarget(
                city: "Custom",
                nick: value,
                countryCode: "",
                regionName: "Custom",
                continent: "Custom",
                iata: "",
                premium: false,
                p2p: false,
                linkSpeedMbps: 0,
                isCustom: true
            )
            servers.insert(custom, at: 0)
            queuedNicks.insert(value)
        }
        customNickDraft = ""
        persist()
    }

    func toggleProtocol(_ proto: VPNProtocolKind) {
        if enabledProtocols.contains(proto) {
            enabledProtocols.remove(proto)
        } else {
            enabledProtocols.insert(proto)
        }
        persist()
    }

    func startTesting() {
        guard !isTesting else { return }
        guard cliAvailable else {
            present("Windscribe CLI was not found at:\n\(cliPath)")
            return
        }
        guard !queuedServers.isEmpty else {
            present("Add at least one server from the sidebar.")
            return
        }
        guard !selectedProtocols.isEmpty else {
            present("Choose at least one protocol.")
            return
        }

        isTesting = true
        isCancelling = false
        results.removeAll()
        progress = TestProgress(
            currentServer: queuedServers.first?.title ?? "",
            currentProtocol: selectedProtocols.first ?? .wireguard,
            step: 0,
            total: testCount,
            startedAt: Date()
        )
        persist()
        testTask = Task { await runTests() }
    }

    func cancelTesting() {
        guard isTesting else { return }
        isCancelling = true
        testTask?.cancel()
    }

    func connect(to result: TestResult) {
        guard cliAvailable else { return }
        Task {
            vpnStatus.connection = "Connecting to \(result.city)"
            await WindscribeCLI.connect(cliPath: cliPath, nick: result.nick, proto: result.proto, wait: true)
            await refreshStatus()
        }
    }

    func connectToBest() {
        guard let best = bestResult else { return }
        connect(to: best)
    }

    func retestFailed() {
        let failedNicks = Set(results.filter { $0.pingMs == nil }.map(\.nick))
        guard !failedNicks.isEmpty else { return }
        queuedNicks = failedNicks
        persist()
        startTesting()
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "windscribe-results.csv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var lines = ["Rank,Server,City,Nickname,Country,Protocol,Status,Ping ms"]
        for result in sortedResults {
            let rank = ranks[result.id].map(String.init) ?? ""
            let ping = result.pingMs.map { String(format: "%.1f", $0) } ?? ""
            let fields = [
                rank,
                csv(result.serverLabel),
                csv(result.city),
                csv(result.nick),
                csv(result.countryCode),
                result.proto.displayName,
                result.outcome.label,
                ping,
            ]
            lines.append(fields.joined(separator: ","))
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func copyNickname(_ nick: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(nick, forType: .string)
    }

    func persist() {
        let defaults = UserDefaults.standard
        defaults.set(cliPath, forKey: "cliPath")
        defaults.set(timeoutSeconds, forKey: "timeoutSeconds")
        defaults.set(uiScale, forKey: "uiScale")
        defaults.set(pingTarget, forKey: "pingTarget")
        defaults.set(stayConnectedToBest, forKey: "stayConnectedToBest")
        defaults.set(enabledProtocols.map(\.rawValue), forKey: "enabledProtocols")
        defaults.set(Array(queuedNicks), forKey: "queuedNicks")
        defaults.set(filter10G, forKey: "filter10G")
        defaults.set(filterP2P, forKey: "filterP2P")
        defaults.set(filterPro, forKey: "filterPro")
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        let storedPath = defaults.string(forKey: "cliPath") ?? ""
        cliPath = storedPath.isEmpty ? WindscribeCLI.detectPath() : storedPath
        let timeout = defaults.integer(forKey: "timeoutSeconds")
        timeoutSeconds = timeout == 0 ? 15 : min(60, max(5, timeout))
        let storedScale = defaults.double(forKey: "uiScale")
        uiScale = [1.0, 1.5, 2.0].contains(storedScale) ? storedScale : 1.0
        pingTarget = defaults.string(forKey: "pingTarget") ?? "1.1.1.1"
        stayConnectedToBest = defaults.bool(forKey: "stayConnectedToBest")
        filter10G = defaults.bool(forKey: "filter10G")
        filterP2P = defaults.bool(forKey: "filterP2P")
        filterPro = defaults.bool(forKey: "filterPro")
        if let raw = defaults.array(forKey: "enabledProtocols") as? [String] {
            let parsed = Set(raw.compactMap(VPNProtocolKind.init(rawValue:)))
            if !parsed.isEmpty { enabledProtocols = parsed }
        }
        if let nicks = defaults.array(forKey: "queuedNicks") as? [String] {
            queuedNicks = Set(nicks)
        }
    }

    private func present(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    private func csv(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func runTests() async {
        let queue = queuedServers
        let protocols = selectedProtocols
        let timeout = TimeInterval(timeoutSeconds)
        let target = pingTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "1.1.1.1" : pingTarget
        var step = 0

        for server in queue {
            if cancelled { break }
            for proto in protocols {
                if cancelled { break }
                step += 1
                progress.step = step
                progress.currentServer = server.title
                progress.currentProtocol = proto

                await WindscribeCLI.disconnect(cliPath: cliPath)
                if cancelled { break }

                await WindscribeCLI.connect(cliPath: cliPath, nick: server.nick, proto: proto, wait: false)
                let connected = await WindscribeCLI.waitUntilConnected(
                    cliPath: cliPath,
                    timeout: timeout,
                    isCancelled: { false }
                )

                if cancelled {
                    record(server: server, proto: proto, outcome: .cancelled, ping: nil)
                    break
                }

                if connected {
                    let ping = await PingService.measure(target: target, timeout: min(8, timeout))
                    if let ping {
                        record(server: server, proto: proto, outcome: .success, ping: ping)
                    } else {
                        record(server: server, proto: proto, outcome: .pingFailed, ping: nil)
                    }
                } else {
                    record(server: server, proto: proto, outcome: .timeout, ping: nil)
                }
            }
        }

        await WindscribeCLI.disconnect(cliPath: cliPath)

        if stayConnectedToBest, let best = bestResult, !isCancelling {
            await WindscribeCLI.connect(cliPath: cliPath, nick: best.nick, proto: best.proto, wait: true)
        }

        await refreshStatus()
        isTesting = false
        isCancelling = false
        testTask = nil
    }

    private func record(server: ServerTarget, proto: VPNProtocolKind, outcome: TestOutcome, ping: Double?) {
        let result = TestResult(
            id: UUID(),
            serverLabel: server.title,
            nick: server.nick,
            city: server.city,
            countryCode: server.countryCode,
            proto: proto,
            outcome: outcome,
            pingMs: ping,
            finishedAt: Date()
        )
        results.append(result)
        if ping != nil {
            progress.successful += 1
            if let ping, ping < (progress.bestPing ?? .greatestFiniteMagnitude) {
                progress.bestPing = ping
            }
        } else if outcome != .cancelled {
            progress.failed += 1
        }
    }
}

import SwiftUI

struct DetailView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: TestResult.ID?

    var body: some View {
        VStack(spacing: 0) {
            protocolBar
            Divider()
            if model.isTesting {
                liveCard
                    .padding(16)
                Divider()
            }
            resultsHeader
            if model.sortedResults.isEmpty {
                emptyState
            } else {
                resultsList
            }
            Divider()
            resultsFooter
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var protocolBar: some View {
        HStack(spacing: 10) {
            Text("Protocols")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(VPNProtocolKind.allCases) { proto in
                ProtocolChip(
                    proto: proto,
                    isOn: model.enabledProtocols.contains(proto)
                ) {
                    model.toggleProtocol(proto)
                }
                .disabled(model.isTesting)
            }
            Spacer()
            Text(queueSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var queueSummary: String {
        let servers = model.queuedNicks.count
        let protos = model.selectedProtocols.count
        if servers == 0 || protos == 0 {
            return "Nothing queued"
        }
        return "\(servers) servers × \(protos) protocols = \(model.testCount) tests"
    }

    private var liveCard: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: model.progress.fraction)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.25), value: model.progress.step)
                VStack(spacing: 0) {
                    Text("\(model.progress.step)")
                        .font(.headline.monospacedDigit())
                    Text("/\(model.progress.total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.isCancelling ? "Cancelling…" : "Testing now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(model.progress.currentServer)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 8) {
                    Label(model.progress.currentProtocol.displayName, systemImage: model.progress.currentProtocol.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(model.progress.etaText)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                ProgressView(value: model.progress.fraction)
                    .tint(Palette.accent)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                metric(model.progress.successful, "working", Palette.success)
                metric(model.progress.failed, "failed", Palette.fail)
                if let best = model.progress.bestPing {
                    metricLabel(String(format: "%.1f ms", best), "best ping", Palette.accent)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func metric(_ value: Int, _ title: String, _ color: Color) -> some View {
        metricLabel("\(value)", title, color)
    }

    private func metricLabel(_ value: String, _ title: String, _ color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var resultsHeader: some View {
        @Bindable var model = model
        return HStack {
            Text("Results")
                .font(.headline)
            Text("sorted by ping")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("Filter", selection: $model.resultFilter) {
                ForEach(ResultFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                model.results.isEmpty ? "No results yet" : "Nothing matches this filter",
                systemImage: "gauge.with.dots.needle.67percent"
            )
        } description: {
            Text(model.results.isEmpty
                 ? "Queue servers on the left, pick protocols, then start a test. Each attempt connects by nickname and pings \(model.pingTarget)."
                 : "Try showing all results.")
        } actions: {
            if !model.isTesting && model.testCount > 0 && model.results.isEmpty {
                Button("Start Test") { model.startTesting() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            ResultColumnHeader()
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            Divider()
            List(model.sortedResults, selection: $selection) { result in
                let rank = model.ranks[result.id]
                ResultRow(
                    result: result,
                    rank: rank,
                    isBest: rank == 1
                )
                .tag(result.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    model.connect(to: result)
                }
                .contextMenu {
                    Button("Connect Now") { model.connect(to: result) }
                    Button("Copy Nickname") { model.copyNickname(result.nick) }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(rowBackground(rank: rank))
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func rowBackground(rank: Int?) -> some View {
        if rank == 1 {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.gold.opacity(0.10))
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
        } else {
            Color.clear
        }
    }

    private var resultsFooter: some View {
        HStack(spacing: 10) {
            Button("Connect to Selected") {
                if let id = selection, let result = model.sortedResults.first(where: { $0.id == id }) {
                    model.connect(to: result)
                }
            }
            .disabled(selection == nil || model.isTesting)

            Button("Connect to Best") { model.connectToBest() }
                .disabled(model.bestResult == nil || model.isTesting)
                .keyboardShortcut("b", modifiers: [.command])

            Button("Retest Failed") { model.retestFailed() }
                .disabled(model.isTesting || model.results.allSatisfy { $0.pingMs != nil } || model.results.isEmpty)

            Spacer()

            if let best = model.bestResult {
                Text("Best: \(best.serverLabel) · \(best.proto.displayName) · \(best.pingText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if !model.results.isEmpty {
                Text("\(model.successCount) working of \(model.results.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Export CSV") { model.exportCSV() }
                .disabled(model.results.isEmpty)
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct ProtocolChip: View {
    let proto: VPNProtocolKind
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(proto.displayName, systemImage: proto.systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isOn ? Palette.accent.opacity(0.18) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isOn ? Palette.accent.opacity(0.7) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .foregroundStyle(isOn ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(proto.rawValue)
    }
}

private enum ResultColumns {
    static let rank: CGFloat = 36
    static let proto: CGFloat = 124
    static let status: CGFloat = 118
    static let ping: CGFloat = 108
}

private struct ResultColumnHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("#")
                .frame(width: ResultColumns.rank, alignment: .center)
            Text("Server")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Protocol")
                .frame(width: ResultColumns.proto, alignment: .leading)
            Text("Status")
                .frame(width: ResultColumns.status, alignment: .leading)
            Text("Ping")
                .frame(width: ResultColumns.ping, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct ResultRow: View {
    let result: TestResult
    let rank: Int?
    let isBest: Bool

    var body: some View {
        HStack(spacing: 12) {
            RankBadge(rank: rank)
                .frame(width: ResultColumns.rank, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.serverLabel)
                    .font(.body.weight(isBest ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(result.nick)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Label(result.proto.displayName, systemImage: result.proto.systemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .frame(width: ResultColumns.proto, alignment: .leading)

            StatusPill(outcome: result.outcome)
                .frame(width: ResultColumns.status, alignment: .leading)

            PingLabel(pingMs: result.pingMs)
                .frame(width: ResultColumns.ping, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }
}

private struct RankBadge: View {
    let rank: Int?

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
            if let rank {
                Text("\(rank)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(rank <= 3 ? Palette.rankColor(rank) : Color.secondary)
            } else {
                Text("–")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 28, height: 28)
    }

    private var fill: Color {
        guard let rank else { return Color.secondary.opacity(0.08) }
        switch rank {
        case 1: return Palette.gold.opacity(0.22)
        case 2: return Palette.silver.opacity(0.22)
        case 3: return Palette.bronze.opacity(0.22)
        default: return Color.secondary.opacity(0.08)
        }
    }
}

private struct PingLabel: View {
    let pingMs: Double?

    var body: some View {
        if let pingMs {
            Text(String(format: "%.1f ms", pingMs))
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.pingColor(pingMs))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Text("—")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}

private struct StatusPill: View {
    let outcome: TestOutcome

    var body: some View {
        Text(outcome.label)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch outcome {
        case .success: Palette.success
        case .pingFailed: Palette.warning
        case .timeout, .cancelled: Palette.fail
        }
    }
}

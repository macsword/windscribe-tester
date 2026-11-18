import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var expandedRegions: Set<String> = []

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            Divider()
            if model.isLoadingServers && model.servers.isEmpty {
                ProgressView("Loading servers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.groupedServers) { continent in
                        Section(continent.name) {
                            ForEach(continent.regions) { region in
                                DisclosureGroup(isExpanded: expansion(region.id)) {
                                    ForEach(region.servers) { server in
                                        ServerRow(server: server, isQueued: model.isQueued(server))
                                            .contentShape(Rectangle())
                                            .onTapGesture { model.toggleQueued(server) }
                                            .contextMenu {
                                                Button(model.isQueued(server) ? "Remove from Queue" : "Add to Queue") {
                                                    model.toggleQueued(server)
                                                }
                                                Button("Copy Nickname") { model.copyNickname(server.nick) }
                                            }
                                    }
                                } label: {
                                    RegionHeader(
                                        region: region,
                                        queued: queuedCount(in: region),
                                        onToggle: { toggleRegion(region) }
                                    )
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            footer
        }
        .onChange(of: model.filter10G) { _, _ in model.persist() }
        .onChange(of: model.filterP2P) { _, _ in model.persist() }
        .onChange(of: model.filterPro) { _, _ in model.persist() }
        .onChange(of: model.searchText) { _, query in
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                expandedRegions = Set(model.groupedServers.flatMap(\.regions).map(\.id))
            }
        }
        .onChange(of: model.servers.count) { _, _ in
            if expandedRegions.isEmpty {
                expandedRegions = Set(
                    model.groupedServers.first?.regions.prefix(3).map(\.id) ?? []
                )
            }
        }
    }

    private var header: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("City, nickname, country", text: $model.searchText)
                    .textFieldStyle(.plain)
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 6) {
                FilterChip(title: "10G", isOn: $model.filter10G)
                FilterChip(title: "P2P", isOn: $model.filterP2P)
                FilterChip(title: "Pro", isOn: $model.filterPro)
                Spacer()
                Text("\(model.visibleServers.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var footer: some View {
        @Bindable var model = model
        return VStack(spacing: 8) {
            HStack {
                Text("\(model.queuedNicks.count) queued")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Select visible") { model.selectAllVisible() }
                    .controlSize(.small)
                Button("Clear") { model.clearQueue() }
                    .controlSize(.small)
                    .disabled(model.queuedNicks.isEmpty)
            }
            HStack {
                TextField("Add nickname…", text: $model.customNickDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.addCustomServer() }
                Button("Add") { model.addCustomServer() }
                    .disabled(model.customNickDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !model.inventorySource.isEmpty {
                Text("Loaded from \(model.inventorySource)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(.bar)
    }

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedRegions.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedRegions.insert(id)
                } else {
                    expandedRegions.remove(id)
                }
            }
        )
    }

    private func queuedCount(in region: RegionGroup) -> Int {
        region.servers.filter { model.isQueued($0) }.count
    }

    private func toggleRegion(_ region: RegionGroup) {
        let allQueued = region.servers.allSatisfy { model.isQueued($0) }
        model.setRegion(region, queued: !allQueued)
    }
}

private struct FilterChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isOn ? Palette.accent.opacity(0.22) : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isOn ? Palette.accent : .secondary)
        }
        .buttonStyle(.plain)
    }
}

private struct RegionHeader: View {
    let region: RegionGroup
    let queued: Int
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: regionSymbol)
                    .foregroundStyle(queued > 0 ? Palette.accent : Color.secondary.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help(queued == region.servers.count ? "Remove region from queue" : "Add region to queue")

            Text(ServerTarget.flagEmoji(for: region.countryCode))
            Text(region.name)
                .font(.subheadline.weight(.semibold))
            Text("\(region.servers.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if queued > 0 {
                Text("\(queued)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.accent.opacity(0.2), in: Capsule())
            }
        }
    }

    private var regionSymbol: String {
        if queued == region.servers.count { return "checkmark.circle.fill" }
        if queued > 0 { return "minus.circle.fill" }
        return "circle"
    }
}

private struct ServerRow: View {
    let server: ServerTarget
    let isQueued: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isQueued ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isQueued ? Palette.accent : Color.secondary.opacity(0.45))
                .imageScale(.medium)
            VStack(alignment: .leading, spacing: 1) {
                Text(server.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(server.nick)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if server.is10Gbps {
                Badge(text: "10G")
            }
            if server.premium {
                Badge(text: "Pro")
            }
            if server.p2p {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("P2P allowed")
            }
        }
        .padding(.vertical, 2)
        .opacity(isQueued ? 1 : 0.86)
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

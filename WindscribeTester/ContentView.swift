import SwiftUI

struct UIScaleContainer<Content: View>: View {
    var scale: Double
    @ViewBuilder var content: Content

    var body: some View {
        let scale = CGFloat(max(scale, 1))
        if scale <= 1.01 {
            content
        } else {
            GeometryReader { proxy in
                content
                    .frame(
                        width: proxy.size.width / scale,
                        height: proxy.size.height / scale,
                        alignment: .topLeading
                    )
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .clipped()
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            subviews[index].place(
                at: CGPoint(x: bounds.minX + result.origins[index].x, y: bounds.minY + result.origins[index].y),
                proposal: ProposedViewSize(size)
            )
        }
    }

    private func arrange(in maxWidth: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
        }

        return (origins, CGSize(width: usedWidth, height: y + rowHeight))
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    private var scale: CGFloat { CGFloat(max(model.uiScale, 1)) }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            UIScaleContainer(scale: model.uiScale) {
                SidebarView()
            }
            .navigationSplitViewColumnWidth(
                min: 320 * scale,
                ideal: 360 * scale,
                max: 560 * scale
            )
        } detail: {
            UIScaleContainer(scale: model.uiScale) {
                DetailView()
            }
        }
        .navigationTitle("Windscribe Tester")
        .toolbar { toolbar }
        .frame(minWidth: 980 * scale, minHeight: 640 * scale)
        .task {
            await model.bootstrap()
            while !Task.isCancelled {
                await model.refreshStatus()
                try? await Task.sleep(for: .seconds(model.isTesting ? 1.2 : 3.0))
            }
        }
        .alert("Windscribe Tester", isPresented: $model.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
                .environment(model)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            StatusBadge(status: model.vpnStatus)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model.reloadServers() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.isTesting || model.isLoadingServers)
            .help("Reload datacenters from Windscribe")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("CLI path, timeout, ping target")
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.isTesting {
                Button(role: .destructive) {
                    model.cancelTesting()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .disabled(model.isCancelling)
                .keyboardShortcut(".", modifiers: [.command])
            } else {
                Button {
                    model.startTesting()
                } label: {
                    Label("Start Test", systemImage: "play.fill")
                }
                .disabled(model.testCount == 0)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }
}

struct StatusBadge: View {
    let status: VPNStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.8), radius: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text(status.shortSummary)
                    .font(.caption.weight(.semibold))
                if !status.ip.isEmpty {
                    Text(status.ip)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .help(status.raw.isEmpty ? "Windscribe status" : status.raw)
    }

    private var color: Color {
        if status.isConnected { return Palette.success }
        if status.isConnecting { return Palette.warning }
        if !status.isLoggedIn { return Palette.fail }
        return Color.secondary
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}

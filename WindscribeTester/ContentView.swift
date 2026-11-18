import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 440)
        } detail: {
            DetailView()
        }
        .navigationTitle("Windscribe Tester")
        .toolbar { toolbar }
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

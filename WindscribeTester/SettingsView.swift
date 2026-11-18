import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Windscribe CLI") {
                LabeledContent("CLI path") {
                    HStack {
                        TextField("CLI path", text: $model.cliPath)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .onChange(of: model.cliPath) { _, _ in model.persist() }
                        Button("Detect") {
                            model.cliPath = WindscribeCLI.detectPath()
                            model.persist()
                        }
                        Button("Browse…") { browseCLI() }
                    }
                }
                HStack {
                    Image(systemName: model.cliAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(model.cliAvailable ? Palette.success : Palette.fail)
                    Text(model.cliAvailable ? "CLI found" : "CLI not found at this path")
                        .foregroundStyle(.secondary)
                }
                Text("Connect uses the datacenter nickname, for example Magic City. Windscribe must already be installed and logged in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Test") {
                Stepper(value: $model.timeoutSeconds, in: 5...60, step: 1) {
                    LabeledContent("Connect timeout", value: "\(model.timeoutSeconds) seconds")
                }
                .onChange(of: model.timeoutSeconds) { _, _ in model.persist() }

                LabeledContent("Ping target") {
                    VStack(alignment: .trailing, spacing: 6) {
                        TextField("Host or IP", text: $model.pingTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .onChange(of: model.pingTarget) { _, _ in model.persist() }
                        HStack {
                            ForEach(["1.1.1.1", "8.8.8.8", "9.9.9.9"], id: \.self) { host in
                                Button(host) {
                                    model.pingTarget = host
                                    model.persist()
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }

                Toggle("Stay connected to the fastest result", isOn: $model.stayConnectedToBest)
                    .onChange(of: model.stayConnectedToBest) { _, _ in model.persist() }
                Text("After a full run, reconnect to the lowest-ping server instead of disconnecting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Servers loaded", value: "\(model.servers.count)")
                LabeledContent("Inventory source", value: model.inventorySource.isEmpty ? "—" : model.inventorySource)
                LabeledContent("Queue", value: "\(model.queuedNicks.count) servers")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func browseCLI() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let path = panel.url?.path {
            model.cliPath = path
            model.persist()
        }
    }
}

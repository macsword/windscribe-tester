import Foundation

enum ProcessRunnerError: LocalizedError {
    case missingExecutable(String)
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let path):
            "Executable not found: \(path)"
        case .startFailed(let message):
            message
        }
    }
}

enum ProcessRunner {
    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?

        func attach(_ process: Process) {
            lock.lock()
            self.process = process
            lock.unlock()
        }

        func terminate() {
            lock.lock()
            if let process, process.isRunning {
                process.terminate()
            }
            lock.unlock()
        }
    }

    static func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ProcessRunnerError.missingExecutable(executable)
        }

        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let output = try runSync(
                            executable: executable,
                            arguments: arguments,
                            timeout: timeout,
                            box: box
                        )
                        continuation.resume(returning: output)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    private static func runSync(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        box: ProcessBox
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.qualityOfService = .userInitiated

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        box.attach(process)

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.startFailed(error.localizedDescription)
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            box.terminate()
            process.waitUntilExit()
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

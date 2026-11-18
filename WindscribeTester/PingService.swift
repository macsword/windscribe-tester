import Foundation

enum PingService {
    static func measure(target: String, timeout: TimeInterval) async -> Double? {
        let host = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        let output = (try? await ProcessRunner.run(
            executable: "/sbin/ping",
            arguments: ["-c", "3", "-W", "2000", host],
            timeout: timeout
        )) ?? ""
        return parse(output)
    }

    static func parse(_ stdout: String) -> Double? {
        if let match = stdout.firstMatch(of: /min\/avg\/max\/[A-Za-z]+ = [\d.]+\/([\d.]+)\//) {
            return round1(Double(String(match.1)))
        }

        let named = /(?:Average|Mittelwert|Moyenne|Media|Gemiddelde|Média)\s*=\s*([\d.]+)\s*ms/
        if let match = stdout.firstMatch(of: named) {
            return round1(Double(String(match.1)))
        }

        var samples: [Double] = []
        for match in stdout.matches(of: /(?:time|zeit|temps|tiempo|tempo)\s*=\s*([\d.]+)\s*ms/) {
            if let value = Double(String(match.1)) {
                samples.append(value)
            }
        }
        samples.append(contentsOf: stdout.matches(of: /(?:time|zeit|temps)\s*<\s*1\s*ms/).map { _ in 1.0 })
        guard !samples.isEmpty else { return nil }
        return round1(samples.reduce(0, +) / Double(samples.count))
    }

    private static func round1(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return (value * 10).rounded() / 10
    }
}

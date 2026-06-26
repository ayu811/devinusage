import Foundation
import Combine

struct UsageAggregate: Codable {
    let key: String
    let label: String
    let models: [String]
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheReadTokens: Int64
    let cacheCreationTokens: Int64
    let costUsd: Double
    let lastActivityAt: Int64?

    enum CodingKeys: String, CodingKey {
        case key
        case label
        case models
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cacheCreationTokens = "cache_creation_tokens"
        case costUsd = "cost_usd"
        case lastActivityAt = "last_activity_at"
    }
}

class UsageStore: ObservableObject {
    @Published var todayCost: Double = 0
    @Published var todayInput: String = "0"
    @Published var todayOutput: String = "0"
    @Published var todayCache: String = "0"

    @Published var monthCost: Double = 0
    @Published var monthInput: String = "0"
    @Published var monthOutput: String = "0"
    @Published var monthCache: String = "0"

    @Published var sessionCost: Double = 0
    @Published var sessionInput: String = "0"
    @Published var sessionOutput: String = "0"
    @Published var sessionCache: String = "0"
    @Published var sessionLabel: String = "No active session"

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            self.refresh()
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .background).async {
            self.updateToday()
            self.updateMonth()
            self.updateSession()
        }
    }

    private func updateToday() {
        let today = dateString(Date())
        guard let data = runDevinUsage(args: ["daily", "--json", "--since", today, "--until", today]),
              let aggregates = parseAggregates(data) else { return }
        DispatchQueue.main.async {
            if let agg = aggregates.first {
                self.todayCost = agg.costUsd
                self.todayInput = self.formatTokens(agg.inputTokens)
                self.todayOutput = self.formatTokens(agg.outputTokens)
                self.todayCache = self.formatTokens(agg.cacheReadTokens)
            }
        }
    }

    private func updateMonth() {
        let firstDay = monthStartString(Date())
        let today = dateString(Date())
        guard let data = runDevinUsage(args: ["monthly", "--json", "--since", firstDay, "--until", today]),
              let aggregates = parseAggregates(data) else { return }
        DispatchQueue.main.async {
            if let agg = aggregates.first {
                self.monthCost = agg.costUsd
                self.monthInput = self.formatTokens(agg.inputTokens)
                self.monthOutput = self.formatTokens(agg.outputTokens)
                self.monthCache = self.formatTokens(agg.cacheReadTokens)
            }
        }
    }

    private func updateSession() {
        guard let data = runDevinUsage(args: ["session", "--json"]),
              let aggregates = parseAggregates(data) else { return }
        DispatchQueue.main.async {
            let current = aggregates.max { a, b in
                (a.lastActivityAt ?? 0) < (b.lastActivityAt ?? 0)
            }
            if let agg = current {
                self.sessionCost = agg.costUsd
                self.sessionInput = self.formatTokens(agg.inputTokens)
                self.sessionOutput = self.formatTokens(agg.outputTokens)
                self.sessionCache = self.formatTokens(agg.cacheReadTokens)
                self.sessionLabel = agg.label
            }
        }
    }

    private func formatTokens(_ n: Int64) -> String {
        if n < 1000 { return "\(n)" }
        if n < 1_000_000 { return String(format: "%.1fk", Double(n) / 1000) }
        return String(format: "%.2fM", Double(n) / 1_000_000)
    }
}

private func dateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    return formatter.string(from: date)
}

private func monthStartString(_ date: Date) -> String {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month], from: date)
    let firstDay = calendar.date(from: components) ?? date
    return dateString(firstDay)
}

private func parseAggregates(_ data: Data) -> [UsageAggregate]? {
    let decoder = JSONDecoder()
    return try? decoder.decode([UsageAggregate].self, from: data)
}

private func runDevinUsage(args: [String]) -> Data? {
    let candidates = locateDevinUsageCandidates()
    for path in candidates {
        if FileManager.default.fileExists(atPath: path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    return pipe.fileHandleForReading.readDataToEndOfFile()
                }
            } catch {
                continue
            }
        }
    }
    return nil
}

private func locateDevinUsageCandidates() -> [String] {
    var paths: [String] = []

    // Same directory as the running executable (packaged .app)
    let execURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    let execDir = execURL.deletingLastPathComponent()
    paths.append(execDir.appendingPathComponent("devinusage").path)

    // Project root when running via `swift run` from devinbar-swift/
    paths.append(URL(fileURLWithPath: "../devinusage").path)

    // Current working directory
    paths.append(URL(fileURLWithPath: "devinusage").path)

    // PATH lookup
    if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
        for dir in pathEnv.split(separator: ":") {
            paths.append(URL(fileURLWithPath: String(dir)).appendingPathComponent("devinusage").path)
        }
    }

    return paths
}

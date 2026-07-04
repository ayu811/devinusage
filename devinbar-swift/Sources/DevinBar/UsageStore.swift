import Foundation
import SwiftUI

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
    let breakdown: [UsageBreakdown]?

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
        case breakdown
    }
}

struct UsageBreakdown: Codable {
    let model: String
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheReadTokens: Int64
    let cacheCreationTokens: Int64
    let costUsd: Double

    enum CodingKeys: String, CodingKey {
        case model
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cacheCreationTokens = "cache_creation_tokens"
        case costUsd = "cost_usd"
    }
}

struct DailyPoint: Identifiable {
    let id = UUID()
    let date: Date
    let cost: Double
    let label: String
}

struct ModelShare: Identifiable {
    let id = UUID()
    let model: String
    let cost: Double
    let color: Color
}

struct AdaptiveRow: Codable {
    let model: String
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheReadTokens: Int64
    let cacheCreationTokens: Int64
    let marketCostUsd: Double
    let adaptiveCostUsd: Double
    let savedUsd: Double
    let savedPercent: Double

    enum CodingKeys: String, CodingKey {
        case model
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cacheCreationTokens = "cache_creation_tokens"
        case marketCostUsd = "market_cost_usd"
        case adaptiveCostUsd = "adaptive_cost_usd"
        case savedUsd = "saved_usd"
        case savedPercent = "saved_percent"
    }
}

extension AdaptiveRow: Identifiable {
    var id: String { model }
}

struct AdaptiveReport: Codable {
    let rows: [AdaptiveRow]
    let totalMarketCostUsd: Double
    let totalAdaptiveCostUsd: Double
    let totalSavedUsd: Double
    let totalSavedPercent: Double

    enum CodingKeys: String, CodingKey {
        case rows
        case totalMarketCostUsd = "total_market_cost_usd"
        case totalAdaptiveCostUsd = "total_adaptive_cost_usd"
        case totalSavedUsd = "total_saved_usd"
        case totalSavedPercent = "total_saved_percent"
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

    @Published var dailyHistory: [DailyPoint] = []
    @Published var modelShares: [ModelShare] = []
    @Published var lastUpdated: Date = Date.distantPast

    @Published var adaptiveMarketCost: Double = 0
    @Published var adaptiveCost: Double = 0
    @Published var adaptiveSaved: Double = 0
    @Published var adaptiveSavedPercent: Double = 0
    @Published var adaptiveRows: [AdaptiveRow] = []

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
            self.updateHistory()
            self.updateAdaptive()
            DispatchQueue.main.async {
                self.lastUpdated = Date()
            }
        }
    }

    private func updateToday() {
        let today = dateString(Date())
        guard let data = runDevinUsage(args: ["daily", "--json", "--breakdown", "--since", today, "--until", today]),
              let aggregates = parseAggregates(data) else { return }
        DispatchQueue.main.async {
            if let agg = aggregates.first {
                self.todayCost = agg.costUsd
                self.todayInput = formatTokens(agg.inputTokens)
                self.todayOutput = formatTokens(agg.outputTokens)
                self.todayCache = formatTokens(agg.cacheReadTokens)
                self.modelShares = self.buildModelShares(from: agg.breakdown ?? [])
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
                self.monthInput = formatTokens(agg.inputTokens)
                self.monthOutput = formatTokens(agg.outputTokens)
                self.monthCache = formatTokens(agg.cacheReadTokens)
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
                self.sessionInput = formatTokens(agg.inputTokens)
                self.sessionOutput = formatTokens(agg.outputTokens)
                self.sessionCache = formatTokens(agg.cacheReadTokens)
                self.sessionLabel = agg.label
            }
        }
    }

    private func updateHistory() {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -6, to: Date()) else { return }
        let since = dateString(start)
        let until = dateString(Date())
        guard let data = runDevinUsage(args: ["daily", "--json", "--since", since, "--until", until]),
              let aggregates = parseAggregates(data) else { return }
        DispatchQueue.main.async {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            var points: [DailyPoint] = []
            for agg in aggregates {
                if let date = formatter.date(from: agg.key) {
                    points.append(DailyPoint(date: date, cost: agg.costUsd, label: agg.label))
                }
            }
            self.dailyHistory = points.sorted { $0.date < $1.date }
        }
    }

    private func updateAdaptive() {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -30, to: Date()) else { return }
        let since = dateString(start)
        let until = dateString(Date())
        guard let data = runDevinUsage(args: ["adaptive", "--json", "--since", since, "--until", until]),
              let report = parseAdaptiveReport(data) else { return }
        DispatchQueue.main.async {
            self.adaptiveMarketCost = report.totalMarketCostUsd
            self.adaptiveCost = report.totalAdaptiveCostUsd
            self.adaptiveSaved = report.totalSavedUsd
            self.adaptiveSavedPercent = report.totalSavedPercent
            self.adaptiveRows = report.rows
                .sorted { $0.adaptiveCostUsd > $1.adaptiveCostUsd }
        }
    }

    private func buildModelShares(from breakdown: [UsageBreakdown]) -> [ModelShare] {
        let total = breakdown.reduce(0.0) { $0 + $1.costUsd }
        guard total > 0 else { return [] }
        return breakdown
            .sorted { $0.costUsd > $1.costUsd }
            .map { ModelShare(model: $0.model, cost: $0.costUsd, color: colorForModel($0.model)) }
    }
}

private func formatTokens(_ n: Int64) -> String {
    if n < 1000 { return "\(n)" }
    if n < 1_000_000 { return String(format: "%.1fk", Double(n) / 1000) }
    return String(format: "%.2fM", Double(n) / 1_000_000)
}

func colorForModel(_ model: String) -> Color {
    let colors: [Color] = [.indigo, .purple, .blue, .cyan, .teal, .green, .orange, .pink, .red]
    var hash = 5381
    for c in model.unicodeScalars {
        hash = ((hash &* 33) &+ Int(c.value)) & 0x7fffffff
    }
    return colors[hash % colors.count]
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

private func parseAdaptiveReport(_ data: Data) -> AdaptiveReport? {
    let decoder = JSONDecoder()
    return try? decoder.decode(AdaptiveReport.self, from: data)
}

private func runDevinUsage(args: [String]) -> Data? {
    let candidates = locateDevinUsageCandidates()
    for path in candidates {
        if FileManager.default.fileExists(atPath: path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe

            var outputData = Data()
            var errorData = Data()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    outputData.append(data)
                }
            }

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    errorData.append(data)
                }
            }

            do {
                try process.run()
                process.waitUntilExit()
                // Give a moment for any final async reads
                Thread.sleep(forTimeInterval: 0.05)
                pipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil

                if process.terminationStatus == 0 {
                    return outputData
                } else {
                    let errString = String(data: errorData, encoding: .utf8) ?? "(none)"
                    NSLog("[DevinBar] devinusage failed: \(errString)")
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

    let execURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    let execDir = execURL.deletingLastPathComponent()
    paths.append(execDir.appendingPathComponent("devinusage").path)

    paths.append(URL(fileURLWithPath: "../devinusage").path)
    paths.append(URL(fileURLWithPath: "devinusage").path)

    if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
        for dir in pathEnv.split(separator: ":") {
            paths.append(URL(fileURLWithPath: String(dir)).appendingPathComponent("devinusage").path)
        }
    }

    return paths
}

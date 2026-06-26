import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white.opacity(0.55)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.55)
    }

    private var subtleStroke: Color {
        colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.08)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                todaySection
                chartCard
                modelCard
                bottomGrid
                footer
            }
            .padding(16)
        }
        .frame(width: 300, height: 460)
        .background(
            Color(nsColor: colorScheme == .dark ? .controlBackgroundColor : .windowBackgroundColor)
        )
    }

    var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: devinAppIcon(size: 28))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                Text("DevinBar")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)
                Text("Updated \(timeAgo(store.lastUpdated))")
                    .font(.system(size: 10))
                    .foregroundStyle(secondaryText)
            }

            Spacer()
        }
    }

    var todaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)

            Text(store.todayCost, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)

            HStack(spacing: 16) {
                tokenStat(icon: "arrow.down.circle", value: store.todayInput, label: "input")
                tokenStat(icon: "arrow.up.circle", value: store.todayOutput, label: "output")
                tokenStat(icon: "clock.arrow.circlepath", value: store.todayCache, label: "cache")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(subtleStroke, lineWidth: 0.5)
        )
    }

    var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("7-Day Spend")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)

            if store.dailyHistory.isEmpty {
                Text("No recent data")
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(store.dailyHistory) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Cost", point.cost)
                    )
                    .foregroundStyle(
                        colorScheme == .dark
                            ? Color.white.opacity(0.85)
                            : Color.black.opacity(0.75)
                    )
                    .cornerRadius(3)
                }
                .frame(height: 80)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let cost = value.as(Double.self) {
                                Text(cost, format: .currency(code: "USD").precision(.fractionLength(0)))
                                    .font(.system(size: 8))
                                    .foregroundStyle(secondaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.day())
                            .font(.system(size: 8))
                    }
                }
                .chartBackground { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                        )
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(subtleStroke, lineWidth: 0.5)
        )
    }

    var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today by Model")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)

            if store.modelShares.isEmpty {
                Text("No model data")
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                HStack(spacing: 14) {
                    Chart(store.modelShares) { share in
                        SectorMark(
                            angle: .value("Cost", share.cost),
                            innerRadius: .ratio(0.6),
                            angularInset: 1.0
                        )
                        .foregroundStyle(grayColor(for: share.model).opacity(0.9))
                        .cornerRadius(2)
                    }
                    .frame(width: 70, height: 70)

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(store.modelShares) { share in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(grayColor(for: share.model))
                                    .frame(width: 6, height: 6)
                                Text(share.model)
                                    .font(.system(size: 10))
                                    .foregroundStyle(primaryText)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(share.cost, format: .currency(code: "USD").precision(.fractionLength(2)))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(secondaryText)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(subtleStroke, lineWidth: 0.5)
        )
    }

    var bottomGrid: some View {
        HStack(spacing: 10) {
            smallCard(title: "This Month", value: store.monthCost, subtitle: "\(store.monthInput) / \(store.monthOutput)")
            smallCard(title: "Session", value: store.sessionCost, subtitle: store.sessionLabel)
        }
    }

    var footer: some View {
        HStack(spacing: 10) {
            Button("Refresh") {
                store.refresh()
            }
            .keyboardShortcut("r")
            .buttonStyle(.borderedProminent)
            .tint(.primary)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
    }

    func tokenStat(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(secondaryText)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(secondaryText)
            }
        }
    }

    func smallCard(title: String, value: Double, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)
                .monospacedDigit()
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(subtleStroke, lineWidth: 0.5)
        )
    }

    func grayColor(for model: String) -> Color {
        let grays: [Color] = [
            .white,
            .white.opacity(0.75),
            .white.opacity(0.55),
            .white.opacity(0.40),
            .white.opacity(0.25)
        ]
        var hash = 5381
        for c in model.unicodeScalars {
            hash = ((hash &* 33) &+ Int(c.value)) & 0x7fffffff
        }
        return grays[hash % grays.count]
    }

    func timeAgo(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 10 { return "just now" }
        if diff < 60 { return "\(Int(diff))s ago" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        return "\(Int(diff / 3600))h ago"
    }
}

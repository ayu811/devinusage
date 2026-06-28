import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 0)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 14) {
                todaySection
                chartSection
                modelSection
                bottomGrid
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 20)

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .frame(width: 280, height: 470)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: devinAppIcon(size: 22))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text("DevinBar")
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            Text(timeAgo(store.lastUpdated))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    var todaySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(store.todayCost, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            HStack(spacing: 16) {
                Label(store.todayInput, systemImage: "arrow.down")
                Label(store.todayOutput, systemImage: "arrow.up")
                Label(store.todayCache, systemImage: "clock.arrow.2.circlepath")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
        }
    }

    var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("7-Day Spend")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if store.dailyHistory.isEmpty {
                Text("No recent data")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(store.dailyHistory) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Cost", point.cost)
                    )
                    .foregroundStyle(.primary)
                    .cornerRadius(3)
                }
                .frame(height: 80)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.day())
                            .font(.system(size: 9))
                    }
                }
                .chartBackground { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.background)
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        )
                }
            }
        }
    }

    var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today by Model")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if store.modelShares.isEmpty {
                Text("No model data")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.modelShares) { share in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(grayColor(for: share.model))
                                .frame(width: 6, height: 6)

                            Text(share.model)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            Text(share.cost, format: .currency(code: "USD").precision(.fractionLength(2)))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    var bottomGrid: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This Month")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(store.monthCost, format: .currency(code: "USD").precision(.fractionLength(2)))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text("\(store.monthInput) / \(store.monthOutput)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Session")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(store.sessionCost, format: .currency(code: "USD").precision(.fractionLength(2)))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(store.sessionLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    var footer: some View {
        HStack(spacing: 12) {
            Button("Refresh") {
                store.refresh()
            }
            .keyboardShortcut("r")
            .controlSize(.small)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .controlSize(.small)
        }
    }

    func grayColor(for model: String) -> Color {
        let grays: [Color] = [
            .primary,
            .primary.opacity(0.7),
            .primary.opacity(0.5),
            .primary.opacity(0.35),
            .primary.opacity(0.2)
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

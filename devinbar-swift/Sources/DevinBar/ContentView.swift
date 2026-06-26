import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                todayCard
                chartCard
                modelBreakdownCard
                gridCards
                footer
            }
            .padding()
        }
        .frame(width: 340, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: devinAppIcon(size: 36))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
            Text("Devin Usage")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Spacer()
        }
    }

    var todayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TODAY")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(store.todayCost, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            HStack(spacing: 12) {
                tokenBadge(value: store.todayInput, label: "input", color: .blue)
                tokenBadge(value: store.todayOutput, label: "output", color: .green)
                tokenBadge(value: store.todayCache, label: "cache", color: .orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    colorScheme == .dark
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Color.indigo.opacity(0.25), Color.purple.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                    : AnyShapeStyle(LinearGradient(
                        colors: [Color.indigo.opacity(0.12), Color.purple.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.indigo.opacity(colorScheme == .dark ? 0.35 : 0.2), lineWidth: 1)
        )
    }

    var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("7-DAY COST")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if store.dailyHistory.isEmpty {
                Text("No recent data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 110)
            } else {
                Chart(store.dailyHistory) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Cost", point.cost)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .bottom,
                        endPoint: .top))
                    .cornerRadius(4)
                }
                .frame(height: 110)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
                .chartBackground { _ in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    var modelBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TODAY BY MODEL")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if store.modelShares.isEmpty {
                Text("No model data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 120)
            } else {
                HStack(spacing: 16) {
                    Chart(store.modelShares) { share in
                        SectorMark(
                            angle: .value("Cost", share.cost),
                            innerRadius: .ratio(0.5),
                            angularInset: 1.5
                        )
                        .foregroundStyle(share.color)
                        .cornerRadius(4)
                    }
                    .frame(width: 110, height: 110)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.modelShares) { share in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(share.color)
                                    .frame(width: 8, height: 8)
                                Text(share.model)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(share.cost, format: .currency(code: "USD").precision(.fractionLength(2)))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    var gridCards: some View {
        HStack(spacing: 10) {
            smallCard(title: "THIS MONTH", cost: store.monthCost, tokens: "\(store.monthInput) / \(store.monthOutput) / \(store.monthCache)")
            smallCard(title: "SESSION", cost: store.sessionCost, tokens: store.sessionLabel)
        }
    }

    var footer: some View {
        HStack(spacing: 12) {
            Button("Refresh") {
                store.refresh()
            }
            .keyboardShortcut("r")
            .buttonStyle(.borderedProminent)
            .tint(.indigo)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
        }
    }

    func tokenBadge(value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    func smallCard(title: String, cost: Double, tokens: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(cost, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text(tokens)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

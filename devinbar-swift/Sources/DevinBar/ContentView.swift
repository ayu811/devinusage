import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme

    private var glass: some ShapeStyle {
        .ultraThinMaterial
    }

    private var textPrimary: Color {
        colorScheme == .dark ? .white : Color(nsColor: .labelColor)
    }

    private var textSecondary: Color {
        colorScheme == .dark ? .white.opacity(0.6) : Color(nsColor: .secondaryLabelColor)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                todayCard
                meterCard
                chartCard
                modelBreakdownCard
                bottomGrid
                footer
            }
            .padding()
        }
        .frame(width: 320, height: 540)
        .background(
            ZStack {
                Color.clear
                    .background(.ultraThinMaterial)
                RadialGradient(
                    colors: [
                        Color.indigo.opacity(0.12),
                        Color.purple.opacity(0.08),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 360
                )
                .opacity(0.7)
            }
        )
    }

    var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: devinAppIcon(size: 32))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text("DevinBar")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(textPrimary)
            Spacer()
            Text("Updated \(timeAgo(store.lastUpdated))")
                .font(.caption2)
                .foregroundStyle(textSecondary)
        }
    }

    var todayCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(.caption2.weight(.medium))
                .foregroundStyle(textSecondary)
                .textCase(.uppercase)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(store.todayCost, format: .currency(code: "USD").precision(.fractionLength(2)))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 12) {
                tokenStat(value: store.todayInput, label: "input")
                tokenStat(value: store.todayOutput, label: "output")
                tokenStat(value: store.todayCache, label: "cache")
            }
            .padding(.top, 2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.35), lineWidth: 0.5)
        )
    }

    var meterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Daily Meter")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(textSecondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(Int(min(store.todayCost / 50.0, 1.0) * 100))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.25))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.indigo.opacity(0.7), Color.purple.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geo.size.width * min(CGFloat(store.todayCost / 50.0), 1.0)), height: 6)
                }
            }
            .frame(height: 6)
            Text("of $50.00 estimated daily budget")
                .font(.caption2)
                .foregroundStyle(textSecondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.35), lineWidth: 0.5)
        )
    }

    var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("7-Day Spend")
                .font(.caption2.weight(.medium))
                .foregroundStyle(textSecondary)
                .textCase(.uppercase)
            if store.dailyHistory.isEmpty {
                Text("No recent data")
                    .font(.caption)
                    .foregroundStyle(textSecondary)
                    .frame(height: 90)
            } else {
                Chart(store.dailyHistory) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Cost", point.cost)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.indigo.opacity(0.8), Color.purple.opacity(0.6)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(3)
                }
                .frame(height: 90)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let cost = value.as(Double.self) {
                                Text(cost, format: .currency(code: "USD").precision(.fractionLength(0)))
                                    .font(.system(size: 8))
                                    .foregroundStyle(textSecondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
                .chartBackground { _ in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.15))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.35), lineWidth: 0.5)
        )
    }

    var modelBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today by Model")
                .font(.caption2.weight(.medium))
                .foregroundStyle(textSecondary)
                .textCase(.uppercase)
            if store.modelShares.isEmpty {
                Text("No model data")
                    .font(.caption)
                    .foregroundStyle(textSecondary)
                    .frame(height: 90)
            } else {
                Chart(store.modelShares) { share in
                    SectorMark(
                        angle: .value("Cost", share.cost),
                        innerRadius: .ratio(0.58),
                        angularInset: 1.0
                    )
                    .foregroundStyle(share.color.opacity(0.85))
                    .cornerRadius(3)
                }
                .frame(height: 90)
                .chartBackground { _ in
                    Circle()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.15))
                }
                .overlay(
                    VStack(spacing: 0) {
                        Text("Top")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(textSecondary)
                        Text(store.modelShares.first?.model.prefix(8) ?? "-")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(textPrimary)
                            .lineLimit(1)
                    }
                )

                HStack(spacing: 8) {
                    ForEach(store.modelShares.prefix(3)) { share in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(share.color)
                                .frame(width: 5, height: 5)
                            Text(share.model)
                                .font(.system(size: 9))
                                .foregroundStyle(textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.35), lineWidth: 0.5)
        )
    }

    var bottomGrid: some View {
        HStack(spacing: 10) {
            smallCard(title: "This Month", value: store.monthCost, subtitle: "\(store.monthInput) in / \(store.monthOutput) out")
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
            .tint(.indigo)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .tint(.gray)
        }
    }

    func tokenStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(textSecondary)
        }
    }

    func smallCard(title: String, value: Double, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(textSecondary)
                .textCase(.uppercase)
            Text(value, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(textPrimary)
                .monospacedDigit()
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(textSecondary)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.35), lineWidth: 0.5)
        )
    }

    func timeAgo(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 10 { return "just now" }
        if diff < 60 { return "\(Int(diff))s ago" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        return "\(Int(diff / 3600))h ago"
    }
}

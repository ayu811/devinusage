import SwiftUI
import Charts

struct AdaptiveView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            savingsSection
            Divider()
            routingSection
            Spacer()
        }
    }

    var savingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adaptive Savings")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if store.adaptiveRows.isEmpty {
                Text("No adaptive usage today")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Market cost")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(store.adaptiveMarketCost, format: .currency(code: "USD").precision(.fractionLength(2)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 4) {
                        Text("Adaptive cost")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(store.adaptiveCost, format: .currency(code: "USD").precision(.fractionLength(2)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 4) {
                        Text("Saved")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(store.adaptiveSaved, format: .currency(code: "USD").precision(.fractionLength(2)))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                            .monospacedDigit()
                    }

                    if store.adaptiveSavedPercent > 0 {
                        Text("\(Int(store.adaptiveSavedPercent * 100))% cheaper than market rate")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    var routingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Adaptive Routing")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if store.adaptiveRows.isEmpty {
                Text("No model data")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(alignment: .center, spacing: 10) {
                    donutChart
                        .frame(height: 120)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.adaptiveRows, id: \.model) { row in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(colorForModel(row.model))
                                    .frame(width: 6, height: 6)

                                Text(row.model)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer(minLength: 4)

                                Text(row.adaptiveCostUsd / max(store.adaptiveCost, 0.0001), format: .percent.precision(.fractionLength(0)))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()

                                Text(row.adaptiveCostUsd, format: .currency(code: "USD").precision(.fractionLength(2)))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
    }

    var donutChart: some View {
        Chart(store.adaptiveRows) { row in
            SectorMark(
                angle: .value("Cost", row.adaptiveCostUsd),
                innerRadius: .ratio(0.55),
                angularInset: 1.5
            )
            .foregroundStyle(colorForModel(row.model))
            .cornerRadius(3)
        }
        .chartBackground { chartProxy in
            GeometryReader { geometry in
                if let plotFrame = chartProxy.plotFrame {
                    let frame = geometry[plotFrame]
                    VStack(spacing: 2) {
                        Text(store.adaptiveSavedPercent, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.green)
                        Text("saved")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
    }
}

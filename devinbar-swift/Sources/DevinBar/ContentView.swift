import SwiftUI

struct ContentView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            todaySection
            monthSection
            sessionSection
            Spacer()
            footer
        }
        .padding()
        .frame(width: 320, height: 440)
    }

    var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "d.circle.fill")
                .font(.title2)
                .foregroundStyle(.primary)
            Text("Devin Usage")
                .font(.title2.bold())
            Spacer()
        }
    }

    var todaySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today")
                .font(.caption.uppercaseSmallCaps())
                .foregroundStyle(.secondary)
            Text(store.todayCost, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("\(store.todayInput) in / \(store.todayOutput) out / \(store.todayCache) cache")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var monthSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This Month")
                .font(.caption.uppercaseSmallCaps())
                .foregroundStyle(.secondary)
            Text(store.monthCost, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("\(store.monthInput) in / \(store.monthOutput) out / \(store.monthCache) cache")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var sessionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Current Session")
                .font(.caption.uppercaseSmallCaps())
                .foregroundStyle(.secondary)
            Text(store.sessionCost, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(store.sessionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("\(store.sessionInput) in / \(store.sessionOutput) out / \(store.sessionCache) cache")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var footer: some View {
        HStack {
            Button("Refresh") {
                store.refresh()
            }
            .keyboardShortcut("r")
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

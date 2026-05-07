//
//  StatsRow.swift
//  comparasion-toolbar
//
//  One column showing app icon + name + CPU/Memory/Threads.
//

import AppKit
import SwiftUI

struct StatsRow: View {

    let app: AppProcess?
    let stats: ProcessStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: icon + name
            HStack(spacing: 8) {
                AppIconView(pid: app?.pid)
                    .frame(width: 32, height: 32)
                Text(app?.name ?? "—")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Divider()

            // Stats lines, monospaced for stable column widths
            statLine(label: "CPU",     value: stats?.formattedCPU ?? "—")
            statLine(label: "Memory",  value: stats?.formattedMemory ?? "—")
            statLine(label: "Threads", value: stats.map { String($0.threadCount) } ?? "—")
            statLine(label: "Energy",  value: stats?.formattedPower ?? "—")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    /// One row inside the stats list — label on the left, value on the right.
    @ViewBuilder
    private func statLine(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.callout)
    }
}

/// Renders the app's icon by looking it up live from `NSRunningApplication`.
/// Falls back to a placeholder if the process is gone.
private struct AppIconView: View {
    let pid: pid_t?

    var body: some View {
        if let pid, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            Image(nsImage: icon)
                .resizable()
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .foregroundStyle(.secondary)
        }
    }
}

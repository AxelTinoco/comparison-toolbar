//
//  ComparisonPopover.swift
//  comparasion-toolbar
//
//  Root view of the menu bar dropdown.  Two columns: left vs right.
//

import AppKit
import SwiftUI

struct ComparisonPopover: View {

    /// `@Bindable` lets us write `$viewModel.leftSelection` to get a Binding
    /// to a property of an `@Observable` class.  It's the modern replacement
    /// for `@ObservedObject` on a child view.
    @Bindable var viewModel: ComparisonViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(alignment: .top, spacing: 12) {
                column(
                    title: "Left",
                    selection: $viewModel.leftSelection,
                    stats: viewModel.leftStats
                )
                column(
                    title: "Right",
                    selection: $viewModel.rightSelection,
                    stats: viewModel.rightStats
                )
            }
        }
        .padding(16)
        .frame(width: 480)
        // Polling lifecycle is tied to the popover's visibility — when the
        // user closes the menu, we stop sampling.  Nice and efficient.
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.tint)
            Text("Comparasion Toolbar")
                .font(.headline)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Comparasion Toolbar")
        }
    }

    /// One side (Left or Right) — title, picker, stats stacked vertically.
    /// `frame(maxWidth: .infinity)` makes both columns share the popover
    /// width equally, regardless of their content.
    @ViewBuilder
    private func column(
        title: String,
        selection: Binding<AppProcess?>,
        stats: ProcessStats?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            AppPicker(
                selection: selection,
                apps: viewModel.availableApps
            )
            StatsRow(
                app: selection.wrappedValue,
                stats: stats
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

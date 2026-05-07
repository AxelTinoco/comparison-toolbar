//
//  ComparisonViewModel.swift
//  comparasion-toolbar
//
//  The brain of the menu bar UI.  Holds user selections + the latest stats,
//  drives the polling loop, and reacts to apps launching/terminating.
//

import AppKit
import Foundation
import Observation

/// Drives the comparison popover.
///
/// `@Observable` means SwiftUI views can read any property of this class and
/// will auto-rerender when *just that property* changes — no `@Published`
/// boilerplate, no whole-object invalidation.
///
/// `@MainActor` pins the whole class to the UI thread.  All our work
/// (NSWorkspace, proc_pidinfo, SwiftUI state) is fine there at 1 Hz.
@MainActor
@Observable
final class ComparisonViewModel {

    // MARK: - Public, observable state

    /// The list of GUI apps the user can pick from.
    private(set) var availableApps: [AppProcess] = []

    /// User picks for left and right columns.  Settable from the View via `@Bindable`.
    var leftSelection: AppProcess?
    var rightSelection: AppProcess?

    /// Latest stats for each side.  `nil` means "not yet sampled / process gone".
    private(set) var leftStats: ProcessStats?
    private(set) var rightStats: ProcessStats?

    // MARK: - Configuration

    /// How often we poll.  1 second is the sweet spot — meaningful CPU% delta,
    /// negligible CPU cost from polling itself.
    let pollInterval: Duration = .seconds(1)

    // MARK: - Dependencies

    /// The service that actually reads from macOS.  We accept it via the
    /// initializer (dependency injection) so tests/previews can pass a fake.
    private let monitor: ProcessMonitor

    // MARK: - Internal state

    /// Long-lived `Task` running the polling loop.  We hold onto it so we can
    /// cancel it in `stop()` (and on `deinit`).
    private var pollingTask: Task<Void, Never>?

    /// Notification observers for when apps launch or terminate.
    private var launchObserver: (any NSObjectProtocol)?
    private var terminateObserver: (any NSObjectProtocol)?

    // MARK: - Init

    /// We accept an optional monitor for dependency injection (tests/previews).
    /// The default `nil` is evaluated in a non-isolated context, but that's
    /// fine — the actual `ProcessMonitor()` construction happens *inside* the
    /// init body, which IS `@MainActor`-isolated.  Swift 6 forbids creating
    /// `@MainActor` types from non-isolated default-argument expressions.
    init(monitor: ProcessMonitor? = nil) {
        self.monitor = monitor ?? ProcessMonitor()
    }

    // No `deinit` needed: the polling Task captures `self` weakly, so it
    // exits as soon as we're freed.  `stop()` (called from the View's
    // `.onDisappear`) gives us deterministic cleanup when we want it.

    // MARK: - Lifecycle

    /// Start the polling loop and subscribe to launch/quit notifications.
    /// Call from the view's `.onAppear` or right after constructing the VM.
    func start() {
        guard pollingTask == nil else { return }   // already running

        refreshAppList()
        subscribeToWorkspaceNotifications()

        pollingTask = Task { [weak self] in
            // `Task { ... }` here inherits @MainActor from the enclosing class.
            // The closure body runs on the main thread.
            while !Task.isCancelled {
                // `guard let self else { return }` upgrades the weak ref to
                // a strong one for this iteration only, and exits the loop
                // cleanly if the VM was deallocated.
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    /// Stop polling and unsubscribe from notifications.
    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        unsubscribeFromWorkspaceNotifications()
    }

    // MARK: - Per-tick work

    /// One sample of both sides.  Called every `pollInterval`.
    private func tick() {
        if let pid = leftSelection?.pid {
            leftStats = monitor.sample(pid: pid)
        } else {
            leftStats = nil
        }

        if let pid = rightSelection?.pid {
            rightStats = monitor.sample(pid: pid)
        } else {
            rightStats = nil
        }
    }

    // MARK: - App list

    private func refreshAppList() {
        let fresh = monitor.runningApps()
        availableApps = fresh

        // If a selected app has quit, clear the selection so the UI doesn't
        // hold a dangling reference.
        if let left = leftSelection, !fresh.contains(where: { $0.pid == left.pid }) {
            leftSelection = nil
            leftStats = nil
        }
        if let right = rightSelection, !fresh.contains(where: { $0.pid == right.pid }) {
            rightSelection = nil
            rightStats = nil
        }
    }

    // MARK: - NSWorkspace notifications

    private func subscribeToWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Notification handlers from .main queue land on the main thread,
            // but Swift 6 still wants explicit isolation: hop into a Task.
            Task { @MainActor [weak self] in self?.refreshAppList() }
        }

        terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAppList() }
        }
    }

    private func unsubscribeFromWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        if let launchObserver { center.removeObserver(launchObserver) }
        if let terminateObserver { center.removeObserver(terminateObserver) }
        launchObserver = nil
        terminateObserver = nil
    }
}

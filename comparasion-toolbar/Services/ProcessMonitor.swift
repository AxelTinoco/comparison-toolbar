//
//  ProcessMonitor.swift
//  comparasion-toolbar
//
//  Lists running apps (via NSWorkspace) and produces ProcessStats samples.
//  CPU% is a *delta*, so the monitor remembers the previous sample per pid.
//

import AppKit
import Foundation

/// Lists running apps and samples their resource usage.
///
/// Marked `@MainActor` because `NSWorkspace` is most safely used from the main
/// thread, and our sample frequency (~1 Hz) is far too low to need an `actor`
/// for parallelism.  If we ever needed dozens of samples per second, we'd
/// split out a background `actor` for the C calls.
@MainActor
final class ProcessMonitor {

    // MARK: - Stored state
    //
    // Per-pid record of the previous reading.  We need *both* CPU and energy
    // counters so we can compute deltas (CPU% and power in mW) on each tick.
    // This is the *only* mutable state in the class.
    private struct PreviousSample {
        let cpuNanoseconds: UInt64
        let energyNanojoules: UInt64
        let sampledAt: Date
    }
    private var lastSamples: [pid_t: PreviousSample] = [:]

    /// PIDs we've learned can't be queried for energy (kernel logs an error
    /// the first time we ask).  We skip them on subsequent ticks to keep the
    /// console clean and shave one syscall per tick.
    private var energyUnsupportedPids: Set<pid_t> = []

    // MARK: - Public API

    /// Returns the list of regular GUI apps the user could compare.
    ///
    /// We filter to `.regular` activation policy to hide background helpers
    /// (e.g. `.accessory` menu-bar tools, `.prohibited` faceless agents).
    func runningApps() -> [AppProcess] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppProcess? in
                guard let name = app.localizedName else { return nil }
                return AppProcess(
                    pid: app.processIdentifier,
                    name: name,
                    bundleIdentifier: app.bundleIdentifier
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reads one fresh stats snapshot for `pid`.
    /// Returns `nil` if the process is gone or unreadable.
    func sample(pid: pid_t) -> ProcessStats? {
        // Two C calls — both fast (microseconds).  We bail if the first one
        // fails (process gone); energy is best-effort.
        guard let task = SystemInfo.taskInfo(forPid: pid) else {
            lastSamples.removeValue(forKey: pid)
            energyUnsupportedPids.remove(pid)
            return nil
        }

        // Energy is best-effort; skip PIDs we already know reject the query
        // to avoid the kernel logging "task name port" failures every second.
        let energy: SystemInfo.EnergyInfo?
        if energyUnsupportedPids.contains(pid) {
            energy = nil
        } else {
            energy = SystemInfo.energyInfo(forPid: pid)
            if energy == nil {
                energyUnsupportedPids.insert(pid)
            }
        }

        let now = Date()
        let previous = lastSamples[pid]

        let cpuPercent = computeCPUPercent(
            previous: previous,
            currentCPU: task.cpuNanoseconds,
            now: now
        )
        let powerMilliwatts: Double? = computePowerMilliwatts(
            previous: previous,
            currentEnergy: energy?.cumulativeEnergyNanojoules,   // pass-through optional
            now: now
        )

        // Store this reading so next tick can compute the next delta.
        lastSamples[pid] = PreviousSample(
            cpuNanoseconds: task.cpuNanoseconds,
            energyNanojoules: energy?.cumulativeEnergyNanojoules ?? 0,
            sampledAt: now
        )

        return ProcessStats(
            cpuPercent: cpuPercent,
            memoryBytes: task.memoryBytes,
            threadCount: task.threadCount,
            powerMilliwatts: powerMilliwatts,
            sampledAt: now
        )
    }

    /// Forget a process's history — call when the user picks a different app
    /// to compare, so the next reading starts clean.
    func forget(pid: pid_t) {
        lastSamples.removeValue(forKey: pid)
        energyUnsupportedPids.remove(pid)
    }

    // MARK: - Delta math

    /// CPU% as a fraction of a single core.
    /// 100.0 = one core fully busy.  On an 8-core Mac, the theoretical max is 800.0.
    private func computeCPUPercent(
        previous: PreviousSample?,
        currentCPU: UInt64,
        now: Date
    ) -> Double {
        guard let previous else { return 0 }                          // first tick
        guard currentCPU >= previous.cpuNanoseconds else { return 0 } // counter reset (shouldn't)

        let cpuDeltaNs = Double(currentCPU - previous.cpuNanoseconds)
        let wallDeltaSeconds = now.timeIntervalSince(previous.sampledAt)
        guard wallDeltaSeconds > 0 else { return 0 }

        // (cpuNs / wallNs) * 100   ==   cpuNs / wallSec / 1e7
        return cpuDeltaNs / wallDeltaSeconds / 1_000_000_0
    }

    /// Instantaneous power in milliwatts, computed as Δ-energy / Δ-time.
    /// Returns:
    ///   • `nil` — energy info wasn't readable for this pid (proc_pid_rusage failed)
    ///   • `0`   — first sample, *or* readable but counter didn't advance (idle).
    ///             Note: on Apple Silicon `ri_billed_energy` advances rarely for
    ///             low-load processes, so 0 is a *valid* and common reading.
    ///   • `>0`  — actual power draw.
    private func computePowerMilliwatts(
        previous: PreviousSample?,
        currentEnergy: UInt64?,
        now: Date
    ) -> Double? {
        guard let currentEnergy else { return nil }     // unavailable
        guard let previous else { return 0 }            // first tick — valid 0
        guard currentEnergy >= previous.energyNanojoules else { return 0 }

        let energyDeltaNJ = Double(currentEnergy - previous.energyNanojoules)
        let wallDeltaSeconds = now.timeIntervalSince(previous.sampledAt)
        guard wallDeltaSeconds > 0 else { return 0 }

        // mW = (nJ / s) / 1e6
        return energyDeltaNJ / wallDeltaSeconds / 1_000_000
    }
}

//
//  ProcessStats.swift
//  comparasion-toolbar
//
//  An immutable snapshot of one process's resource usage at one moment.
//

import Foundation

/// One sample of CPU / memory / thread usage for a process.
///
/// Snapshots are produced by `ProcessMonitor` ~once per second and consumed
/// by `ComparisonViewModel`. Treat them as immutable readings.
struct ProcessStats: Hashable, Sendable {

    /// CPU usage as a percentage of one core.
    /// 100% = one core fully used. On an 8-core Mac the theoretical max is 800%.
    let cpuPercent: Double

    /// Resident memory (RSS) in bytes — RAM physically held by the process.
    let memoryBytes: UInt64

    /// Number of OS threads the process currently has.
    let threadCount: Int

    /// Instantaneous power draw, in milliwatts, derived as Δ-energy / Δ-time.
    ///   • `nil`   — energy reporting unavailable for this process.
    ///   • `0.0`   — valid reading; the process used no measurable energy in
    ///               the last interval.  Common on idle apps because the
    ///               kernel batches `ri_billed_energy` updates infrequently.
    ///   • `> 0`   — actual power draw.
    let powerMilliwatts: Double?

    /// When the sample was taken. Useful for computing CPU deltas later.
    let sampledAt: Date

    /// Convenience: an "empty" reading, used as the initial state in the UI
    /// before the first poll completes.
    static let empty = ProcessStats(
        cpuPercent: 0,
        memoryBytes: 0,
        threadCount: 0,
        powerMilliwatts: nil,
        sampledAt: .distantPast
    )
}

// MARK: - Display helpers
//
// We keep formatting *out* of the struct's stored properties — formatting is a
// presentation concern. But it's fine to expose computed views of the data.

extension ProcessStats {

    /// "245.3 MB" style memory string for the UI.
    var formattedMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    /// "12.4 %" style CPU string. We clamp negatives (can happen on the very
    /// first sample when there is no previous reading to diff against).
    var formattedCPU: String {
        let clamped = max(cpuPercent, 0)
        return String(format: "%.1f %%", clamped)
    }

    /// "245 mW" / "1.32 W" style power string.
    ///   • `nil`  → `—`  (reporting unavailable)
    ///   • `0`    → `0 mW`  (valid reading; idle)
    ///   • `≥ 1000` mW → render in watts.
    var formattedPower: String {
        guard let mW = powerMilliwatts else { return "—" }
        if mW >= 1000 {
            return String(format: "%.2f W", mW / 1000)
        } else if mW >= 1 {
            return String(format: "%.0f mW", mW)
        } else {
            return "0 mW"
        }
    }
}

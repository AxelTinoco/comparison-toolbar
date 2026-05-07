//
//  SystemInfo.swift
//  comparasion-toolbar
//
//  Thin Swift wrapper around the macOS C function `proc_pidinfo`, the official
//  way to read CPU time, resident memory, and thread count for any user-owned
//  process *without* root privileges or `task_for_pid` entitlements.
//

import Darwin
import Foundation

/// Namespace for low-level system queries.  We use an `enum` with no cases as
/// a "static-only namespace" — it cannot be instantiated, which signals intent.
enum SystemInfo {

    // MARK: - Task info (CPU / memory / threads) via proc_pidinfo

    /// Sendable, plain-data result of one `proc_pidinfo` call.
    struct TaskInfo: Sendable {
        /// Cumulative CPU time used by the process since it started, in nanoseconds.
        /// (Sum of user-mode + kernel-mode time.)
        let cpuNanoseconds: UInt64
        /// Resident set size — RAM physically held by the process, in bytes.
        let memoryBytes: UInt64
        /// Live thread count.
        let threadCount: Int
    }

    /// Reads task info for a single process.
    /// Returns `nil` if the pid is gone or we lack permission to inspect it.
    static func taskInfo(forPid pid: pid_t) -> TaskInfo? {
        // `proc_taskinfo` is a C struct.  Swift gives us a default initializer
        // that zero-fills all its fields.
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)

        // proc_pidinfo wants an `UnsafeMutableRawPointer` to a buffer it will
        // write into.  `withUnsafeMutablePointer(to:)` lends us a temporary
        // pointer to `info`, valid only inside this closure.  Outside, the
        // pointer is invalid — Swift won't let us escape it.
        let bytesWritten = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, ptr, size)
        }

        // proc_pidinfo's contract: returns the number of bytes written, or 0
        // (and sets errno) on failure.  We expect the full struct.
        guard bytesWritten == size else { return nil }

        return TaskInfo(
            cpuNanoseconds: info.pti_total_user + info.pti_total_system,
            memoryBytes: info.pti_resident_size,
            threadCount: Int(info.pti_threadnum)
        )
    }

    // MARK: - Energy / wakeups via proc_pid_rusage

    /// Sendable, plain-data result of one `proc_pid_rusage` call.
    struct EnergyInfo: Sendable {
        /// Cumulative energy "billed" to this process, in nanojoules.
        /// Zero on hardware that doesn't report energy (some older Intel Macs).
        /// On Apple Silicon this is well-populated.
        let cumulativeEnergyNanojoules: UInt64
        /// Cumulative interrupt wakeups — a secondary energy proxy.
        let interruptWakeups: UInt64
    }

    /// Reads energy / wakeup counters for a single process.
    /// Returns `nil` if the pid is gone or unreadable.
    static func energyInfo(forPid pid: pid_t) -> EnergyInfo? {
        // `rusage_info_v6` is the latest layout, added in macOS 13.  It's a
        // superset of v0; the kernel writes only the fields the requested
        // flavor knows about, but we allocate the v6 size to give it room.
        var info = rusage_info_v6()

        // ⚠️  `proc_pid_rusage`'s C signature is misleading.  It declares
        //         int proc_pid_rusage(int pid, int flavor, rusage_info_t *buffer)
        //     and `rusage_info_t` is typedef'd as `void *`, so syntactically
        //     `buffer` is `void **`.  But semantically the kernel treats it
        //     as a single `void *` — the *address of your struct*, NOT a
        //     pointer-to-a-pointer.  Apple's own sample code casts through:
        //         proc_pid_rusage(pid, RUSAGE_INFO_V3, (rusage_info_t *)&r)
        //     A double-indirection version *will* compile, then trash the
        //     stack on the first call and crash with a bus error elsewhere.
        //
        //     The Swift idiom is to cast through `OpaquePointer`, bypassing
        //     the type system to give the kernel the address of `info`.
        let result = withUnsafeMutablePointer(to: &info) { v6Ptr -> Int32 in
            let bridged = UnsafeMutablePointer<UnsafeMutableRawPointer?>(OpaquePointer(v6Ptr))
            return proc_pid_rusage(pid, RUSAGE_INFO_V6, bridged)
        }

        // Unlike proc_pidinfo, proc_pid_rusage returns 0 on success, -1 on failure.
        guard result == 0 else { return nil }

        return EnergyInfo(
            cumulativeEnergyNanojoules: info.ri_billed_energy,
            interruptWakeups: info.ri_interrupt_wkups
        )
    }
}

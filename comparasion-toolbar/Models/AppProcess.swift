//
//  AppProcess.swift
//  comparasion-toolbar
//
//  A pure-data description of a running macOS application.
//

import Foundation
import Darwin   // gives us `pid_t`

/// Represents one running app the user can pick to compare.
///
/// We deliberately keep this lightweight and `Sendable` so it can travel
/// freely between the polling actor and the main-thread UI.
struct AppProcess: Identifiable, Hashable, Sendable {
    /// macOS process identifier. Unique per running process for the session.
    let pid: pid_t

    /// User-visible name (e.g. "Safari"). Optional in AppKit, so we default it.
    let name: String

    /// Reverse-DNS bundle id (e.g. "com.apple.Safari"). May be missing for
    /// command-line tools or background helpers.
    let bundleIdentifier: String?

    // MARK: - Identifiable

    /// SwiftUI's `List` / `ForEach` / `Picker` use this to track items.
    var id: pid_t { pid }
}

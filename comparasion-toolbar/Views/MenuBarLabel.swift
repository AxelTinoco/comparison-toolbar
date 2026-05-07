//
//  MenuBarLabel.swift
//  comparasion-toolbar
//
//  The tiny glyph that lives in the macOS menu bar.
//

import SwiftUI

/// Just an SF Symbol.  MenuBarExtra automatically tints it for dark/light mode.
struct MenuBarLabel: View {
    var body: some View {
        Image(systemName: "chart.bar")
    }
}

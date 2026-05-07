//
//  comparasion_toolbarApp.swift
//  comparasion-toolbar
//
//  App entry point.  Declares a single MenuBarExtra scene — no main window,
//  no Dock icon (LSUIElement = YES is set in build settings).
//

import SwiftUI

@main
struct comparasion_toolbarApp: App {

    /// `@State` for an `@Observable` class is the new convention (replaces
    /// the old `@StateObject` for `ObservableObject`).  This instance lives
    /// for the entire app lifetime because the App struct is evaluated once.
    @State private var viewModel = ComparisonViewModel()

    var body: some Scene {
        MenuBarExtra {
            ComparisonPopover(viewModel: viewModel)
        } label: {
            MenuBarLabel()
        }
        // `.window` style turns the dropdown into a proper SwiftUI canvas
        // (lets us use HStack/VStack freely).  `.menu` style would render a
        // traditional menu — only suitable for simple menu items.
        .menuBarExtraStyle(.window)
    }
}

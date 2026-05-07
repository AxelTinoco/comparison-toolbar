//
//  AppPicker.swift
//  comparasion-toolbar
//
//  A dropdown of running apps, with a "None" option at the top.
//

import SwiftUI

struct AppPicker: View {

    @Binding var selection: AppProcess?
    let apps: [AppProcess]

    var body: some View {
        // The visible label is empty + `.labelsHidden()` so the Picker only
        // takes the width of its dropdown chevron + selected text.
        // `.frame(maxWidth: .infinity)` then stretches it to fill the column,
        // which is critical: without it, the Picker would size itself to its
        // *widest* menu item (e.g. "Visual Studio Code Insiders Helper"),
        // pushing the popover outward and triggering AppKit layout recursion.
        Picker("", selection: $selection) {
            // Optional-tag pattern: each row's `tag` must match the binding's
            // type exactly.  Since `selection` is `AppProcess?`, every tag has
            // to be `AppProcess?` — hence `.none` and `.some(app)`.
            Text("None").tag(AppProcess?.none)

            if !apps.isEmpty {
                Divider()
                ForEach(apps) { app in
                    Text(app.name).tag(AppProcess?.some(app))
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }
}

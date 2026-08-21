//
//  PeteKMApp.swift
//  PeteKM
//
//  Created by Pete McPherson on 8/19/26.
//
//  No database: Markdown files on disk are the only canonical store
//  (spec §2.2). Nothing here persists note content.
//

import SwiftUI

@main
struct PeteKMApp: App {
    @State private var folderStore = FolderStore()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(folderStore)
                .environment(settings)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

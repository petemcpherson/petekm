//
//  MissingFolderView.swift
//  PeteKM
//
//  Spec §19.6. The configured folder is unreachable: never crash, never create
//  a new folder at the old path, never write anywhere else. Blocking panel with
//  exactly three ways out.
//

import SwiftUI
import AppKit

struct MissingFolderView: View {
    let lastKnownPath: String
    var onLocate: (URL) -> Void
    var onReonboard: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            HStack(alignment: .top, spacing: DS.Space.s5) {
                PixelMark(size: 64)
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text("Can't find your PeteKM folder")
                        .font(DS.Text.title2)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(lastKnownPath)
                        .font(DS.Text.monoCaption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("It may be on a disconnected drive, renamed, or moved. Nothing was created in its place.")
                        .font(DS.Text.callout)
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.Text.callout)
                    .foregroundStyle(DS.Color.error)
            }

            Spacer(minLength: 0)

            HStack(spacing: DS.Space.s4) {
                Button("Quit") { NSApp.terminate(nil) }
                Spacer()
                Button("Choose or Create a New Folder…") { onReonboard() }
                Button("Locate Folder…") { locate() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Space.s8)
        .frame(width: 520, height: 260)
        .background(DS.Color.surfaceWindow)
    }

    private func locate() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Find your PeteKM folder"
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else { return }

        guard FolderStore.isReachable(url) else {
            errorMessage = "That folder isn't writable."
            return
        }
        errorMessage = nil
        onLocate(url)
    }
}

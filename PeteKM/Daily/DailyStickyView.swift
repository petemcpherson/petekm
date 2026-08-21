import SwiftUI
import AppKit

/// The Daily Sticky window contents. Plain-text editing for now — live Markdown styling is Phase 3 (§9).
struct DailyStickyView: View {
    @Environment(FolderStore.self) private var folderStore
    @Environment(AppSettings.self) private var settings

    let folder: PeteKMFolder

    @State private var session: DailySession?

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                Color.clear
                    .onAppear { session = DailySession(folder: folder, settings: settings) }
            }
        }
        .frame(minWidth: 460, minHeight: 320)
        .background(DS.Color.surfaceWindow)
    }

    @ViewBuilder
    private func content(_ session: DailySession) -> some View {
        VStack(spacing: 0) {
            header(session)
            Divider()
            editor(session)
        }
        .overlay {
            if let options = session.newDayOptions {
                ZStack {
                    DS.Color.surfaceWindow.opacity(0.85)
                    NewDayPrompt(options: options) { session.startNewDay($0) }
                }
            }
        }
        .conflictAlert(document: session.document)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            session.handleActivation()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            session.flush()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session.flush()
        }
        .onDisappear { session.flush() }
    }

    private func header(_ session: DailySession) -> some View {
        HStack(spacing: DS.Space.s4) {
            PixelMark(size: 16)
            Text(session.openedTitle)
                .font(DS.Text.uiLabel)
                .foregroundStyle(DS.Color.textPrimary)
            Text(session.openedFileName)
                .font(DS.Text.monoCaption)
                .foregroundStyle(DS.Color.textTertiary)
            Spacer(minLength: 0)
            if let error = session.document?.lastError ?? session.lastError {
                Text(error)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.error)
                    .lineLimit(1)
                    .help(error)
            }
        }
        .padding(.horizontal, DS.Space.s6)
        .padding(.vertical, DS.Space.s4)
    }

    @ViewBuilder
    private func editor(_ session: DailySession) -> some View {
        if let document = session.document {
            StickyTextEditor(document: document)
        } else {
            Spacer()
        }
    }
}

private struct StickyTextEditor: View {
    @Bindable var document: StickyDocument

    var body: some View {
        TextEditor(text: $document.text)
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(DS.Color.surfaceWindow)
            .padding(.horizontal, DS.Space.s5)
            .padding(.vertical, DS.Space.s4)
    }
}

private extension View {
    /// Three choices, no merge UI. Keep Both is the safe default (§19.4).
    func conflictAlert(document: StickyDocument?) -> some View {
        alert(
            "This file changed on disk.",
            isPresented: Binding(
                get: { document?.hasConflict ?? false },
                set: { if !$0 { } }
            )
        ) {
            Button("Keep Both") { document?.resolve(.keepBoth) }
                .keyboardShortcut(.defaultAction)
            Button("Keep Mine") { document?.resolve(.keepMine) }
            Button("Keep Disk") { document?.resolve(.keepDisk) }
        } message: {
            Text("You have unsaved changes and something else edited the same file. Keep Both writes the disk version alongside yours.")
        }
    }
}

import SwiftUI
import AppKit

/// The Daily Sticky window contents: live-styled Markdown editor with a heading outline (§9).
struct DailyStickyView: View {
    @Environment(FolderStore.self) private var folderStore
    @Environment(AppSettings.self) private var settings
    @Environment(SyncLaunchCheck.self) private var syncLaunchCheck
    @Environment(AutoSync.self) private var autoSync

    let folder: PeteKMFolder

    @State private var session: DailySession?
    @State private var scratch: ScratchStore?
    @State private var editorController = EditorController()
    @State private var scratchController = EditorController()
    @State private var palette = PaletteModel()
    @State private var keyMonitor: Any?
    /// Transient one-line result of an external-tool action (DESIGN §32).
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                Color.clear
                    .onAppear {
                        // Sync starts first so today's sticky can wait for the other Mac's copy (sync v2 §6.5).
                        autoSync.start(folder: folder)
                        let session = DailySession(folder: folder, settings: settings, autoSync: autoSync)
                        autoSync.register(session)
                        self.session = session
                    }
            }
        }
        .frame(minWidth: 460, minHeight: 320)
        .background(windowBackground)
    }

    /// Background color and transparency settings. Text stays fully opaque either way.
    private var windowBackground: some View {
        let base: Color = settings.backgroundColor.map(Color.init) ?? DS.Color.surfaceWindow
        return base.opacity(settings.backgroundOpacity).ignoresSafeArea()
    }

    @ViewBuilder
    private func content(_ session: DailySession) -> some View {
        VStack(spacing: 0) {
            header(session)
            Divider()
            syncBanner(session)
            editor(session)
            scratchPane
        }
        .overlay(alignment: .topTrailing) {
            SyncStatusDot { gitSync(session: session) }
        }
        .overlay {
            if let options = session.newDayOptions {
                ZStack {
                    DS.Color.surfaceWindow.opacity(0.85)
                    NewDayPrompt(options: options) { session.startNewDay($0) }
                }
            }
        }
        .overlay {
            if palette.isPresented {
                CommandPaletteView(model: palette)
            }
        }
        .conflictAlert(document: session.document)
        .onAppear {
            palette.configure(folder: folder) { perform($0, session: session) }
            palette.isDocumentOpen = session.document != nil
            installPaletteShortcut()
            noticeIfAgentFilesOutOfDate()
            prepareScratch()
            autoSync.register(session)
            autoSync.start(folder: folder)
            if !settings.syncAutomatically {
                syncLaunchCheck.runIfNeeded(folder: folder)
            }
            showAutoSyncNotice()
        }
        .onChange(of: autoSync.lastNotice) { _, _ in
            showAutoSyncNotice()
        }
        .onChange(of: session.document?.url) { _, _ in
            palette.isDocumentOpen = session.document != nil
        }
        .onDisappear {
            removePaletteShortcut()
            noticeTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .peteKMSyncNow)) { _ in
            gitSync(session: session)
        }
        .onReceive(NotificationCenter.default.publisher(for: .peteKMOpenSearch)) { _ in
            palette.present(mode: .search)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            session.handleActivation()
            scratch?.document.reconcileWithDisk()
        }
        // Summoned by the global shortcut: recheck the date, then land the cursor where it was (§8.2, §8.3).
        .onReceive(NotificationCenter.default.publisher(for: .peteKMDidSummon)) { _ in
            session.handleActivation()
            Task { @MainActor in editorController.focusEditor() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            session.flush()
            scratch?.flush()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session.flush()
            scratch?.flush()
        }
        .onDisappear {
            session.flush()
            scratch?.flush()
        }
    }

    // MARK: - Sync banner (sync spec §4.3)

    /// One non-modal, dismissible row. No counts, no ahead/behind, no Git words.
    @ViewBuilder
    private func syncBanner(_ session: DailySession) -> some View {
        // Automatic sync replaces the v1 banner (sync v2 §4, §8.2).
        if !settings.syncAutomatically && syncLaunchCheck.showsBanner {
            HStack(spacing: DS.Space.s4) {
                Text("Changes to sync.")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                Spacer(minLength: 0)
                Button("Sync") {
                    syncLaunchCheck.dismiss()
                    gitSync(session: session)
                }
                Button {
                    syncLaunchCheck.dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
            }
            .padding(.horizontal, DS.Space.s6)
            .padding(.vertical, DS.Space.s4)
            Divider()
        }
    }

    // MARK: - Palette

    /// A local key monitor rather than a hidden button: ⌘K has to work while the
    /// NSTextView owns first responder (§10.1).
    private func installPaletteShortcut() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.option)
            else { return event }

            switch event.charactersIgnoringModifiers?.lowercased() {
            case "k" where !event.modifierFlags.contains(.shift):
                Task { @MainActor in
                    if palette.isPresented { palette.dismiss() } else { palette.present() }
                }
                return nil

            case "s" where event.modifierFlags.contains(.shift):
                Task { @MainActor in toggleScratch() }
                return nil

            default:
                return event
            }
        }
    }

    private func removePaletteShortcut() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - Scratch

    /// One store for the life of the window. It is not rebuilt when the day rolls over or
    /// when a Library file opens — carrying over is the point.
    private func prepareScratch() {
        guard scratch == nil else { return }
        scratch = ScratchStore(folder: folder)

        // Folders created before Scratch existed keep their own `.gitignore`; make sure it
        // excludes the scratch file before the user can type anything into it. Folders
        // created before sync v2 also gain the daily union-merge line.
        let folder = folder
        Task.detached(priority: .utility) {
            FolderInitializer.ensureScratchIgnored(folder)
            FolderInitializer.ensureDailyUnionMerge(folder)
        }
    }

    @ViewBuilder
    private var scratchPane: some View {
        if let scratch {
            ScratchPaneView(store: scratch,
                            settings: settings,
                            controller: scratchController,
                            isExpanded: Binding(get: { settings.scratchVisible },
                                                set: { settings.scratchVisible = $0 }),
                            height: Binding(get: { settings.scratchHeight },
                                            set: { settings.scratchHeight = $0 }))
                .conflictAlert(document: scratch.document)
        }
    }

    private func showScratch() {
        settings.scratchVisible = true
        Task { @MainActor in scratchController.focusEditor() }
    }

    private func toggleScratch() {
        if settings.scratchVisible {
            settings.scratchVisible = false
            editorController.focusEditor()
        } else {
            showScratch()
        }
    }

    private func perform(_ outcome: PaletteOutcome, session: DailySession) {
        switch outcome {
        case .openToday:
            session.openToday()

        case .openDaily(let date):
            session.open(date: date)

        case .openScratch:
            showScratch()
            return

        case .openFile(let url, let reveal):
            session.open(fileURL: url, reveal: reveal)
            if let reveal {
                // The editor may have just been rebuilt for a different file; jump once it exists.
                Task { @MainActor in editorController.reveal(reveal) }
            }

        case .revealFolderInFinder:
            ExternalTools.revealInFinder(folder.root)

        case .openSettings:
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)

        case .openInEditor(let url):
            openInEditor(url)

        case .openCurrentFileInEditor:
            guard let url = session.document?.url else {
                show("No file is open.")
                return
            }
            openInEditor(url)

        case .openTerminalInFolder:
            if !ExternalTools.openTerminal(at: folder.root) {
                show(ExternalTools.terminalUnavailableNotice)
            }

        case .gitSync:
            gitSync(session: session)

        case .insertText(let text):
            editorController.insert(text)
        }

        editorController.focusEditor()
    }

    // MARK: - External tools (§12, §15.1, §17)

    private func openInEditor(_ url: URL) {
        let editor = ExternalEditorProvider.current
        let opened = FileWriting.isDirectory(url)
            ? editor.open(folder: url)
            : editor.open(file: url, in: folder.root)
        if !opened { show(editor.unavailableNotice) }
    }

    /// Git runs off the main actor and only ever reports back with a line of
    /// text — capture never waits on it (§17.4). Flush and reconcile are the
    /// only steps that come back to the main actor (sync v2 §6.1).
    private func gitSync(session: DailySession) {
        Task {
            guard let run = await autoSync.request(.manual) else { return }
            show(run.outcome.manualNotice(editorName: ExternalEditorProvider.current.displayName),
                 seconds: run.outcome == .pullConflict ? 15 : 6)
        }
    }

    private func showAutoSyncNotice() {
        guard let notice = autoSync.consumeNotice() else { return }
        show(notice.text, seconds: notice.seconds)
    }

    private func noticeIfAgentFilesOutOfDate() {
        let fingerprint = FolderInitializer.agentTemplatesFingerprint
        guard settings.agentFilesNoticeShownFor != fingerprint else { return }
        let folder = folder
        Task {
            let outOfDate = await Task.detached(priority: .utility) {
                FolderInitializer.agentFilesAreOutOfDate(folder)
            }.value
            guard outOfDate else { return }
            settings.agentFilesNoticeShownFor = fingerprint
            show("Agent files are out of date. Settings → Folder → Refresh Agent Files.", seconds: 15)
        }
    }

    private func show(_ text: String, seconds: Double = 6) {
        noticeTask?.cancel()
        notice = text
        noticeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            notice = nil
        }
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
            Button {
                palette.present()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Command Palette (⌘K)")
            Toggle(isOn: Binding(get: { settings.floatOnTop },
                                 set: { settings.floatOnTop = $0 })) {
                Image(systemName: settings.floatOnTop ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            .help("Float Above Other Apps")
            Toggle(isOn: Binding(get: { settings.showTableOfContents },
                                 set: { settings.showTableOfContents = $0 })) {
                Image(systemName: "list.bullet")
            }
            .toggleStyle(.button)
            .help("Table of Contents")
            Toggle(isOn: Binding(get: { settings.scratchVisible },
                                 set: { settings.scratchVisible = $0 })) {
                Image(systemName: "note.text")
            }
            .toggleStyle(.button)
            .help("Scratch (⌘⇧S)")
            if let error = session.document?.lastError ?? session.lastError {
                Text(error)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.error)
                    .lineLimit(1)
                    .help(error)
            } else if let notice {
                // External tools report here and then get out of the way.
                Text(notice)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
                    .help(notice)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.Space.s6)
        .padding(.vertical, DS.Space.s4)
    }

    @ViewBuilder
    private func editor(_ session: DailySession) -> some View {
        if let document = session.document {
            HStack(spacing: 0) {
                if settings.showTableOfContents {
                    TableOfContentsView(entries: MarkdownOutline.entries(in: document.text)) { entry in
                        editorController.reveal(entry.range)
                    }
                    Divider()
                }
                StickyTextEditor(document: document,
                                 settings: settings,
                                 controller: editorController,
                                 preferredSelection: session.revealRange,
                                 onEdit: autoSync.noteEdit)
                    .id(document.url)
            }
        } else {
            Spacer()
        }
    }
}

private struct StickyTextEditor: View {
    @Bindable var document: StickyDocument
    let settings: AppSettings
    let controller: EditorController
    let onEdit: () -> Void

    private let cursors = CursorMemory()

    init(document: StickyDocument,
         settings: AppSettings,
         controller: EditorController,
         preferredSelection: NSRange? = nil,
         onEdit: @escaping () -> Void) {
        _document = Bindable(document)
        self.settings = settings
        self.controller = controller
        self.onEdit = onEdit
        // A search hit wins over the remembered caret; otherwise restore where the
        // user left off before the text view is built (§8.3, §11.4).
        controller.initialSelection = preferredSelection ?? CursorMemory().selection(for: document.url)
    }

    var body: some View {
        MarkdownEditor(
            text: $document.text,
            style: settings.editorStyle,
            autoClosePairs: settings.autoClosePairs,
            continueListMarkers: settings.continueListMarkers,
            controller: controller,
            onSelectionChange: { cursors.remember($0, for: document.url) },
            onEdit: onEdit
        )
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

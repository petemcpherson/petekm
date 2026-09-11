import SwiftUI

/// A short-article guide to the day-to-day loop (capture → process → Library),
/// split into a sidebar of topics. Text only: it must never be the thing that
/// teaches by doing work for you, and it never claims the app itself files
/// anything (§13.1 — zero AI in the app).
struct GuideSettingsView: View {

    @State private var selection: GuideArticle? = .overview

    var body: some View {
        NavigationSplitView {
            List(GuideArticle.allCases, selection: $selection) { article in
                Label(article.title, systemImage: article.systemImage)
                    .tag(article)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            ScrollView {
                (selection ?? .overview).content
                    .padding(DS.Space.s7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 680, height: 480)
    }
}

// MARK: - Articles

enum GuideArticle: String, CaseIterable, Identifiable {
    case overview
    case capture
    case moveAround
    case process
    case backfill
    case inbox
    case libraryPaths
    case libraryTidy
    case scratch
    case trust

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .capture: return "Capture"
        case .moveAround: return "Move Around"
        case .process: return "Process a Day"
        case .backfill: return "Backfilling Notes"
        case .inbox: return "Inbox"
        case .libraryPaths: return "Library Paths"
        case .libraryTidy: return "Keeping the Library Tidy"
        case .scratch: return "Scratch"
        case .trust: return "Things Worth Trusting"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "book"
        case .capture: return "pencil"
        case .moveAround: return "command"
        case .process: return "gearshape.2"
        case .backfill: return "clock.arrow.circlepath"
        case .inbox: return "tray"
        case .libraryPaths: return "arrow.right"
        case .libraryTidy: return "books.vertical"
        case .scratch: return "scribble"
        case .trust: return "checkmark.shield"
        }
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .overview: GuideOverviewArticle()
        case .capture: GuideCaptureArticle()
        case .moveAround: GuideMoveAroundArticle()
        case .process: GuideProcessArticle()
        case .backfill: GuideBackfillArticle()
        case .inbox: GuideInboxArticle()
        case .libraryPaths: GuideLibraryPathsArticle()
        case .libraryTidy: GuideLibraryTidyArticle()
        case .scratch: GuideScratchArticle()
        case .trust: GuideTrustArticle()
        }
    }
}

private struct GuideOverviewArticle: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s7) {
            GuideIntro()
            GuideReplayOnboarding()
        }
    }
}

private struct GuideCaptureArticle: View {
    @Environment(AppSettings.self) private var settings

    private var shortcutText: String {
        settings.globalShortcut?.displayString ?? AppSettings.suggestedShortcut.displayString
    }
    private var shortcutIsSet: Bool { settings.globalShortcut != nil }

    var body: some View {
        GuideSection("Capture") {
            if shortcutIsSet {
                GuideLine("Press \(shortcutText) anywhere to show PeteKM. Press it again to hide.")
            } else {
                GuideLine("Set a global shortcut in General. \(shortcutText) is a safe suggestion. Press it anywhere to show PeteKM.")
            }
            GuideLine("Type. Today's Daily Sticky is created on first use and saved as you go. No file to name, no folder to choose.")
            GuideLine("Use `##` headings for topics. They make later filing much better, and they drive the table of contents.")
            GuideLine("Markdown markers stay visible. PeteKM styles `#`, `**`, and `-` without hiding them.")
        }
    }
}

private struct GuideMoveAroundArticle: View {
    var body: some View {
        GuideSection("Move Around") {
            GuideLine("⌘K opens the command palette. Everything lives there.")
            GuideKeyed("Open Daily Sticky", "today's file")
            GuideKeyed("Open Date…", "any past day")
            GuideKeyed("Search All PeteKM…", "full text, daily and Library")
            GuideKeyed("Open Library File…", "fuzzy filename match")
            GuideKeyed("Open Scratch", "the pane under the editor")
            GuideKeyed("Open Terminal in PeteKM Folder", "where processing happens")
            GuideLine("⌘, or ⌘. opens Settings.")
        }
    }
}

private struct GuideProcessArticle: View {
    var body: some View {
        GuideSection("Process a Day") {
            GuideLine("Filing is done by your own agent in a terminal, not by this app. PeteKM writes the instructions into the folder; the agent reads them.")
            GuideLine("Open Terminal in PeteKM Folder, start Claude Code, then run:")
            GuideCode("/petekm-process")
            GuideLine("It reads every Daily Sticky you haven't processed yet, oldest first, searches the Library, and updates or creates Library files with a `Source:` line pointing back at the day.")
            GuideLine("It never edits `daily/`. That folder is an append-only ledger — no rewrites, no \"processed\" markers, no grammar fixes.")
            GuideLine("`/petekm-status` reports what has and has not been processed.")
        }
    }
}

private struct GuideBackfillArticle: View {
    var body: some View {
        GuideSection("Backfilling Notes") {
            GuideLine("Backfilling old notes works. Put each one in `daily/` named exactly `YYYY-MM-DD.md` — the filename is the date.")
            GuideLine("Then just run Process. Plain `/petekm-process` picks up everything newer than the last processed day, oldest-first, whether the app created the file or you did.")
            GuideLine("To redo one specific day, pass it a date:")
            GuideCode("/petekm-process 2026-08-11")
            GuideLine("Same rules apply: the file you dropped in is never modified.")
            GuideLine("Open Date… in the palette opens a backfilled day like any other. There is no import step.")
        }
    }
}

private struct GuideInboxArticle: View {
    var body: some View {
        GuideSection("Inbox") {
            GuideLine("When the agent can't confidently place something, it does not guess. It copies the item into `INBOX.md` at the folder root with a one-line reason.")
            GuideLine("Review Inbox in the palette opens it. Clarify or delete lines, then run a processing skill again — the agent files what it now can and removes those lines.")
            GuideLine("Deleting a line means \"ignore this.\" It won't come back.")
        }
    }
}

private struct GuideLibraryPathsArticle: View {
    var body: some View {
        GuideSection("Library Paths") {
            GuideLine("Sometimes you already know where something belongs while you're still typing today's note. Point at it without leaving the Daily Sticky.")
            GuideKeyed("Insert Library Path…", "pick an existing Library file or folder")
            GuideLine("It inserts a hint at the cursor, in the form:")
            GuideCode("-> library/projects/petekm.md")
            GuideLine("That's a plain-text hint for the processing agent, not a link the app resolves. The path must already exist in the Library — pick a folder to point at a topic in general, or a file for something specific.")
            GuideLine("In the palette, typing `/ ` (slash, space) jumps straight into the same file list, as a shortcut to Open Library File….")
            GuideLine("You don't need to know the exact path. A literal `->` followed by plain language is also a hint:")
            GuideCode("- vendor pricing -> add to JSCAPE notes for work")
            GuideLine("The agent resolves that itself — searching the Library, consulting the Placement guide — and can create a new file if the language points at one clearly. Too vague to resolve confidently → it goes to Inbox instead of guessing. Must be `->` exactly; a bare `>` is Markdown blockquote syntax and is never treated as a hint.")
        }
    }
}

private struct GuideLibraryTidyArticle: View {
    var body: some View {
        GuideSection("Keeping the Library Tidy") {
            GuideCodeLine("/petekm-rebuild-index", "regenerate `INDEX.md` from the Library")
            GuideCodeLine("/petekm-organize", "deliberate restructuring: merges, renames, folder cleanup")
            GuideLine("Daily processing stays conservative on purpose. Big restructures are an explicit action.")
            GuideLine("You can also just talk to the agent: \"find everything I wrote about certificate auth and tell me what's still unresolved.\"")
        }
    }
}

private struct GuideScratchArticle: View {
    var body: some View {
        GuideSection("Scratch") {
            GuideLine("The pane under the editor is Scratch. It holds the same text every day, no matter which file is open. Nothing carries it forward — there is only ever one of it.")
            GuideLine("It is for what you don't want kept: a to-do list for the next few days, a phone number for this afternoon, a key you pasted once and will delete.")
            GuideLine("The agent is told never to read it, quote it, or file it. It's excluded from search, and it's listed in `.gitignore`, so Sync never sends it anywhere.")
            GuideLine("⌘⇧S shows and hides it. Drag its top edge to resize. It empties only when you clear it — the cleared text is kept as a `.bak` file in `.petekm-backups/`.")
            GuideLine("It is plain text on disk, not encrypted. Nothing about it is private from anyone who can read your folder.")
        }
    }
}

private struct GuideTrustArticle: View {
    var body: some View {
        GuideSection("Things Worth Trusting") {
            GuideLine("The `.md` files are the whole product. Indexes, caches, and `.petekm-state.json` are disposable and rebuildable.")
            GuideLine("PeteKM is not the only writer. Edit the same files in \(PaletteCommandID.editorName) or Finder; external changes are detected rather than clobbered.")
            GuideLine("Capture never blocks. A failed Sync, a missing editor, or an agent that isn't installed can't stop you from opening or saving today.")
            GuideLine("Your edits win. The agent treats what's on disk as authoritative.")
        }
    }
}

// MARK: - Pieces

/// Replays the first-run flow on demand (§6). Nothing on disk changes: onboarding
/// adopts a folder with `.keep`, so existing files are never overwritten — this only
/// walks the same steps again — including the last one, which is the reminder to
/// shape `library/` and import existing notes.
private struct GuideReplayOnboarding: View {

    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Button("Show Onboarding Again") {
                settings.hasCompletedOnboarding = false
                NotificationCenter.default.post(name: .peteKMSummonWindow, object: nil)
            }
            Text("Walks through the setup steps again in the main window, ending with the suggestions for shaping your Library and importing notes. Your folder and notes aren't touched.")
                .font(DS.Text.caption)
                .foregroundStyle(DS.Color.textSecondary)
        }
    }
}

private struct GuideIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text("How PeteKM works")
                .font(DS.Text.title1)
            Text("Two places. **Daily Sticky** is what you wrote today — raw, chronological, never rewritten. **Library** is the organized version, maintained later by an agent you run yourself.")
                .font(DS.Text.body)
                .foregroundStyle(DS.Color.textSecondary)
            Text("Capture now. File later. Nothing to name while you type.")
                .font(DS.Text.body)
                .foregroundStyle(DS.Color.textSecondary)
        }
    }
}

private struct GuideSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            Text(title)
                .font(DS.Text.title1)
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                content
            }
        }
    }
}

private struct GuideLine: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(.init(text))
            .font(DS.Text.body)
            .foregroundStyle(DS.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A palette command (or similar) paired with a short gloss.
private struct GuideKeyed: View {
    let name: String
    let detail: String
    init(_ name: String, _ detail: String) {
        self.name = name
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
            Text(name)
                .font(DS.Text.uiLabel)
                .frame(width: 190, alignment: .leading)
            Text(detail)
                .font(DS.Text.callout)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GuideCode: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DS.Text.mono)
            .textSelection(.enabled)
            .padding(.vertical, DS.Space.s3)
            .padding(.horizontal, DS.Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(DS.Color.borderHairline)
            )
    }
}

private struct GuideCodeLine: View {
    let command: String
    let detail: String
    init(_ command: String, _ detail: String) {
        self.command = command
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(command)
                .font(DS.Text.mono)
                .textSelection(.enabled)
            Text(.init(detail))
                .font(DS.Text.caption)
                .foregroundStyle(DS.Color.textSecondary)
        }
    }
}

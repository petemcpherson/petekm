import SwiftUI

/// A single-page guide to the day-to-day loop (capture → process → Library).
/// Text only: it must never be the thing that teaches by doing work for you,
/// and it never claims the app itself files anything (§13.1 — zero AI in the app).
struct GuideSettingsView: View {

    @Environment(AppSettings.self) private var settings

    private var shortcutText: String {
        settings.globalShortcut?.displayString ?? AppSettings.suggestedShortcut.displayString
    }

    private var shortcutIsSet: Bool { settings.globalShortcut != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s7) {

                GuideIntro()

                GuideSection("1. Capture") {
                    if shortcutIsSet {
                        GuideLine("Press \(shortcutText) anywhere to show PeteKM. Press it again to hide.")
                    } else {
                        GuideLine("Set a global shortcut in General. \(shortcutText) is a safe suggestion. Press it anywhere to show PeteKM.")
                    }
                    GuideLine("Type. Today's Daily Sticky is created on first use and saved as you go. No file to name, no folder to choose.")
                    GuideLine("Use `##` headings for topics. They make later filing much better, and they drive the table of contents.")
                    GuideLine("Markdown markers stay visible. PeteKM styles `#`, `**`, and `-` without hiding them.")
                }

                GuideSection("2. Move around") {
                    GuideLine("⌘K opens the command palette. Everything lives there.")
                    GuideKeyed("Open Daily Sticky", "today's file")
                    GuideKeyed("Open Date…", "any past day")
                    GuideKeyed("Search All PeteKM…", "full text, daily and Library")
                    GuideKeyed("Open Library File…", "fuzzy filename match")
                    GuideKeyed("Open Terminal in PeteKM Folder", "where processing happens")
                    GuideLine("⌘, or ⌘. opens Settings.")
                }

                GuideSection("3. Process a day") {
                    GuideLine("Filing is done by your own agent in a terminal, not by this app. PeteKM writes the instructions into the folder; the agent reads them.")
                    GuideLine("Open Terminal in PeteKM Folder, start Claude Code, then run:")
                    GuideCode("/petekm-process-today")
                    GuideLine("It reads today's Daily Sticky, searches the Library, and updates or creates Library files with a `Source:` line pointing back at the day.")
                    GuideLine("It never edits `daily/`. That folder is an append-only ledger — no rewrites, no \"processed\" markers, no grammar fixes.")
                    GuideLine("`/petekm-status` reports what has and has not been processed.")
                }

                GuideSection("4. Process notes you added by hand") {
                    GuideLine("Backfilling old notes works. Put each one in `daily/` named exactly `YYYY-MM-DD.md` — the filename is the date.")
                    GuideLine("Then process each one by date:")
                    GuideCode("/petekm-process-date 2026-08-11")
                    GuideLine("Same rules apply: the file you dropped in is never modified.")
                    GuideLine("Open Date… in the palette opens a backfilled day like any other. There is no import step.")
                }

                GuideSection("5. Inbox") {
                    GuideLine("When the agent can't confidently place something, it does not guess. It copies the item into `INBOX.md` at the folder root with a one-line reason.")
                    GuideLine("Review Inbox in the palette opens it. Clarify or delete lines, then run a processing skill again — the agent files what it now can and removes those lines.")
                    GuideLine("Deleting a line means \"ignore this.\" It won't come back.")
                }

                GuideSection("6. Keeping the Library tidy") {
                    GuideCodeLine("/petekm-rebuild-index", "regenerate `INDEX.md` from the Library")
                    GuideCodeLine("/petekm-organize", "deliberate restructuring: merges, renames, folder cleanup")
                    GuideLine("Daily processing stays conservative on purpose. Big restructures are an explicit action.")
                    GuideLine("You can also just talk to the agent: \"find everything I wrote about certificate auth and tell me what's still unresolved.\"")
                }

                GuideSection("7. Things worth trusting") {
                    GuideLine("The `.md` files are the whole product. Indexes, caches, and `.petekm-state.json` are disposable and rebuildable.")
                    GuideLine("PeteKM is not the only writer. Edit the same files in \(PaletteCommandID.editorName) or Finder; external changes are detected rather than clobbered.")
                    GuideLine("Capture never blocks. A failed Git Sync, a missing editor, or an agent that isn't installed can't stop you from opening or saving today.")
                    GuideLine("Your edits win. The agent treats what's on disk as authoritative.")
                }
            }
            .padding(DS.Space.s7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460, height: 460)
    }
}

// MARK: - Pieces

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
                .font(DS.Text.title3)
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

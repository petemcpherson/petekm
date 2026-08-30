//
//  ScratchPaneView.swift
//  PeteKM
//
//  A collapsible pane pinned under the editor. Same content on every day and every
//  file — that sameness is the whole feature. Collapsed it is a single strip showing
//  the first line; expanded it is a smaller Markdown editor the user can drag taller.
//

import SwiftUI
import AppKit

struct ScratchPaneView: View {

    let store: ScratchStore
    let settings: AppSettings
    let controller: EditorController

    @Binding var isExpanded: Bool
    @Binding var height: Double

    @Environment(\.colorScheme) private var colorScheme

    @State private var dragStartHeight: Double?
    @State private var confirmingClear = false

    /// The pane shifts against whatever the window is actually painted with — the user's
    /// own background color when they set one, the system appearance otherwise — so it
    /// stays a slight step away rather than a fixed gray that fights a custom color.
    private var groundIsDark: Bool {
        settings.groundIsDark(systemIsDark: colorScheme == .dark)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                resizeHandle
            } else {
                Divider()
            }
            header
            if isExpanded {
                Divider()
                ScratchTextEditor(document: store.document,
                                  style: settings.scratchEditorStyle,
                                  autoClosePairs: settings.autoClosePairs,
                                  continueListMarkers: settings.continueListMarkers,
                                  controller: controller)
                    .frame(height: height)
            }
        }
        .background(ground)
    }

    /// A wash plus a tiled dot grid. Both are pure alpha over the window, so a
    /// transparent window stays transparent (§ window opacity is user-set).
    private var ground: some View {
        ZStack {
            Color(nsColor: ScratchTexture.wash(dark: groundIsDark))
            Image(nsImage: ScratchTexture.dots(dark: groundIsDark))
                .resizable(resizingMode: .tile)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Strip

    private var header: some View {
        HStack(spacing: DS.Space.s4) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                .font(DS.Text.micro)
                .foregroundStyle(DS.Color.textTertiary)

            Text("Scratch")
                .font(DS.Text.uiLabel)
                .foregroundStyle(DS.Color.textSecondary)

            if isExpanded {
                Text("not filed · not in Git")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .help("Scratch is never read by the agent, never filed into the Library, and never committed. It is not encrypted.")
            } else if !store.firstLine.isEmpty {
                Text(store.firstLine)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            if let error = store.document.lastError ?? store.lastError {
                Text(error)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.error)
                    .lineLimit(1)
                    .help(error)
            }

            if isExpanded && !store.isEmpty {
                Button {
                    confirmingClear = true
                } label: {
                    Image(systemName: "trash")
                        .font(DS.Text.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DS.Color.textTertiary)
                .help("Clear Scratch")
            }
        }
        .padding(.horizontal, DS.Space.s6)
        .padding(.vertical, DS.Space.s3)
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
        .help(isExpanded ? "Hide Scratch (⌘⇧S)" : "Show Scratch (⌘⇧S)")
        .confirmationDialog("Clear Scratch?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) { store.clear() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The current text is moved aside as a .bak file in .petekm-backups. Scratch is not in Git, so there is no other copy.")
        }
    }

    // MARK: - Resize

    private var resizeHandle: some View {
        Divider()
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartHeight ?? height
                        dragStartHeight = start
                        height = AppSettings.clampScratchHeight(start - value.translation.height)
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
    }
}

/// The editor half. Split out so the text binding can go through `@Bindable`, and so the
/// empty-state line can sit over an `NSTextView`, which has no placeholder of its own.
private struct ScratchTextEditor: View {

    @Bindable var document: StickyDocument
    let style: MarkdownStyle
    let autoClosePairs: Bool
    let continueListMarkers: Bool
    let controller: EditorController

    private let cursors = CursorMemory()

    init(document: StickyDocument,
         style: MarkdownStyle,
         autoClosePairs: Bool,
         continueListMarkers: Bool,
         controller: EditorController) {
        _document = Bindable(document)
        self.style = style
        self.autoClosePairs = autoClosePairs
        self.continueListMarkers = continueListMarkers
        self.controller = controller
        controller.initialSelection = CursorMemory().selection(for: document.url)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MarkdownEditor(
                text: $document.text,
                style: style,
                autoClosePairs: autoClosePairs,
                continueListMarkers: continueListMarkers,
                controller: controller,
                onSelectionChange: { cursors.remember($0, for: document.url) }
            )
            if document.text.isEmpty {
                Text("Stays here. Never filed.")
                    .font(DS.Text.callout)
                    .foregroundStyle(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Space.s5 + 5)
                    .padding(.vertical, DS.Space.s4)
                    .allowsHitTesting(false)
            }
        }
    }
}


/// The Scratch pane's ground: a barely-there wash and a 7pt dot grid. Tiles are built
/// once per appearance — the pane's body re-runs on every keystroke, so this must not
/// allocate an image each time.
@MainActor
enum ScratchTexture {

    private static var tiles: [Bool: NSImage] = [:]

    static func wash(dark: Bool) -> NSColor {
        NSColor(white: dark ? 1 : 0, alpha: dark ? 0.030 : 0.022)
    }

    static func dots(dark: Bool) -> NSImage {
        if let cached = tiles[dark] { return cached }

        let spacing: CGFloat = 7
        let radius: CGFloat = 0.75
        let ink = NSColor(white: dark ? 1 : 0, alpha: dark ? 0.16 : 0.10)

        let tile = NSImage(size: NSSize(width: spacing, height: spacing), flipped: false) { _ in
            ink.setFill()
            NSBezierPath(ovalIn: NSRect(x: spacing / 2 - radius,
                                        y: spacing / 2 - radius,
                                        width: radius * 2,
                                        height: radius * 2)).fill()
            return true
        }
        tiles[dark] = tile
        return tile
    }
}

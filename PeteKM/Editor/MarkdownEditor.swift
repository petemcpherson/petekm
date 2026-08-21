import SwiftUI
import AppKit

/// Handle onto the live text view, used by the table of contents to jump around (§9.4).
@MainActor
final class EditorController {
    fileprivate weak var textView: MarkdownTextView?

    /// Applied when the text view is created — cursor restoration (§8.3).
    var initialSelection: NSRange?

    func reveal(_ range: NSRange) {
        guard let textView else { return }
        let clamped = clamp(range, in: textView)
        textView.setSelectedRange(NSRange(location: clamped.location, length: 0))
        textView.scrollRangeToVisible(clamped)
        textView.window?.makeFirstResponder(textView)
    }

    func focusEditor() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    fileprivate func clamp(_ range: NSRange, in textView: NSTextView) -> NSRange {
        let length = (textView.string as NSString).length
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(range.length, length - location))
    }
}

/// NSTextView-backed Markdown editor: live styling with the syntax still visible (§9.1–9.2).
struct MarkdownEditor: NSViewRepresentable {

    @Binding var text: String
    var style: MarkdownStyle = .default
    var autoClosePairs = true
    var continueListMarkers = true
    var controller: EditorController
    var onSelectionChange: (NSRange) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = makeTextView(context: context) else { return scrollView }

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        controller.textView = textView
        context.coordinator.textView = textView

        textView.string = text
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.highlight(textView.textStorage)

        let end = NSRange(location: (text as NSString).length, length: 0)
        textView.setSelectedRange(controller.initialSelection.map { controller.clamp($0, in: textView) } ?? end)
        textView.scrollRangeToVisible(textView.selectedRange())

        return scrollView
    }

    private func makeTextView(context: Context) -> MarkdownTextView? {
        let textView = MarkdownTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.autoClosePairs = autoClosePairs
        textView.continueListMarkers = continueListMarkers

        // Markdown is punctuation-sensitive: no smart quotes, dashes, or substitutions.
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true                       // in-memory only; cleared on quit (§9.7)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: DS.Space.s5, height: DS.Space.s4)
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = false
        textView.font = style.body
        textView.typingAttributes = [.font: style.body, .foregroundColor: NSColor.labelColor]

        return textView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        context.coordinator.parent = self
        controller.textView = textView
        textView.autoClosePairs = autoClosePairs
        textView.continueListMarkers = continueListMarkers

        if context.coordinator.style != style {
            context.coordinator.style = style
            context.coordinator.highlight(textView.textStorage)
        }

        // External reload or conflict resolution replaced the text under us.
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(controller.clamp(selection, in: textView))
            context.coordinator.highlight(textView.textStorage)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MarkdownEditor
        var style: MarkdownStyle
        weak var textView: MarkdownTextView?
        private var isHighlighting = false

        init(_ parent: MarkdownEditor) {
            self.parent = parent
            self.style = parent.style
        }

        func highlight(_ storage: NSTextStorage?) {
            guard let storage, !isHighlighting else { return }
            isHighlighting = true
            MarkdownSyntaxHighlighter.apply(to: storage, style: style)
            isHighlighting = false
        }

        nonisolated func textStorage(_ textStorage: NSTextStorage,
                                     didProcessEditing editedMask: NSTextStorageEditActions,
                                     range editedRange: NSRange,
                                     changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated { highlight(textStorage) }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.onSelectionChange(textView.selectedRange())
        }
    }
}

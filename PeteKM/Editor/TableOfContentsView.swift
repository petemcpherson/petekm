import SwiftUI

/// Heading-derived outline of the open document (§9.4). Nothing is stored — it is recomputed
/// from the text on every change.
struct TableOfContentsView: View {

    let entries: [MarkdownOutlineEntry]
    let onSelect: (MarkdownOutlineEntry) -> Void

    @State private var selection: MarkdownOutlineEntry.ID?

    var body: some View {
        Group {
            if entries.isEmpty {
                VStack {
                    Text("No headings.")
                        .font(DS.Text.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                    Spacer()
                }
                .padding(DS.Space.s5)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List(entries, selection: $selection) { entry in
                    Text(entry.title)
                        .font(entry.level <= 1 ? DS.Text.uiLabel : DS.Text.callout)
                        .foregroundStyle(entry.level <= 2 ? DS.Color.textPrimary : DS.Color.textSecondary)
                        .lineLimit(1)
                        .padding(.leading, CGFloat(entry.level - 1) * DS.Space.s5)
                        .tag(entry.id)
                }
                .listStyle(.sidebar)
                .onChange(of: selection) { _, new in
                    guard let entry = entries.first(where: { $0.id == new }) else { return }
                    onSelect(entry)
                }
            }
        }
        .frame(width: 200)
        .background(DS.Color.surfaceSunken)
    }
}
